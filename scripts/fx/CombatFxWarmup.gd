extends Node
class_name CombatFxWarmup
## 命中/击杀与枪口 PixelFX 异步预热器（后台单工作线程 + user:// 磁盘缓存）：
##   1) 全程在 WorkerThreadPool 后台线程顺序烘焙 Baker.Track（纯 CPU Image 生成，不触碰 SceneTree/GPU），
##      彻底消除开局 6-14 秒主线程 20-60ms/帧的严重掉帧；
##   2) 烘焙成品按内容哈希原子写入 user://fx_bake_cache/（ZSTD 压缩），二次启动加载仅需数十毫秒；
##   3) 跨主菜单 → 局内共享进程级去重队列，退出时安全回收工作线程与缓存，零泄漏。

const BAKER := preload("res://addons/pixelfx/bake/baker.gd")
const PX := preload("res://addons/pixelfx/core/px.gd")
const CACHE_DIR := "user://fx_bake_cache"
const CACHE_VERSION := 1

static var _mutex := Mutex.new()
static var _pending: Array[Dictionary] = []
static var _completed: Array[Dictionary] = []
static var _scheduled: Dictionary = {}
static var _task_id := -1
static var _abort := false
static var _exit_hooked := false


static func cache_key(id_or_script: Variant, opts: Dictionary = {}, which_layer: String = "") -> String:
	var mod: Script = id_or_script if id_or_script is Script else _load_fx_script(String(id_or_script))
	if mod == null:
		return ""
	return "%s|%s|%s" % [
		mod.resource_path if mod.resource_path else str(mod.get_instance_id()),
		JSON.stringify(opts),
		which_layer,
	]


static func _load_fx_script(id: String) -> Script:
	if id.is_empty():
		return null
	var path := "res://addons/pixelfx/fx/%s.gd" % id
	return load(path) as Script if ResourceLoader.exists(path) else null


static func _disk_cache_path(key: String) -> String:
	return "%s/v%d_%s.dat" % [CACHE_DIR, CACHE_VERSION, key.md5_text()]


## O(1) 检查指定变体是否已在 PixelFx2D._cache 中完整烘焙就绪。
static func is_ready(id_or_script: Variant, opts: Dictionary = {}, which_layer: String = "") -> bool:
	var key := cache_key(id_or_script, opts, which_layer)
	if key == "":
		return true
	var tr: Variant = PixelFx2D._cache.get(key)
	return tr != null and (tr as BAKER.Track).done()


static func is_worker_active() -> bool:
	_mutex.lock()
	var busy := _task_id != -1 or not _pending.is_empty() or not _completed.is_empty()
	_mutex.unlock()
	return busy


static func _hook_tree_exit() -> void:
	if _exit_hooked:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return
	_exit_hooked = true
	tree.root.tree_exiting.connect(_on_tree_exiting, CONNECT_ONE_SHOT)


static func _on_tree_exiting() -> void:
	shutdown_worker()
	_exit_hooked = false


static func shutdown_worker() -> void:
	_mutex.lock()
	_abort = true
	var tid := _task_id
	_pending.clear()
	_mutex.unlock()
	if tid != -1:
		WorkerThreadPool.wait_for_task_completion(tid)
	_mutex.lock()
	_task_id = -1
	_completed.clear()
	_scheduled.clear()
	_abort = false
	_mutex.unlock()


func setup(variants: Array[Dictionary]) -> void:
	# 无头测试没有渲染与真实帧预算，跳过后台线程与磁盘缓存，避免拖慢用例。
	if DisplayServer.get_name() == "headless":
		set_process(false)
		queue_free()
		return
	_hook_tree_exit()
	var enqueued := false
	for variant in variants:
		var id := String(variant.get("id", ""))
		var opts: Dictionary = variant.get("opts", {})
		var mod := _load_fx_script(id)
		if mod == null:
			continue
		var key := cache_key(mod, opts, "")
		if key == "":
			continue
		var existing: Variant = PixelFx2D._cache.get(key)
		if existing != null and (existing as BAKER.Track).done():
			continue
		# 必须在主线程预填充 Px.Fx._info，确保后台线程全程只读脚本元数据，零数据竞争。
		PX.Fx.info(mod)
		_mutex.lock()
		if not _scheduled.has(key):
			_scheduled[key] = true
			_pending.append({
				"key": key,
				"mod": mod,
				"opts": opts.duplicate(true),
				"cache_path": _disk_cache_path(key),
			})
			enqueued = true
		_mutex.unlock()
	if enqueued:
		_ensure_worker_started()
	_drain_completed()
	if not is_worker_active():
		set_process(false)
		queue_free()
		return
	set_process(true)


static func _ensure_worker_started() -> void:
	_mutex.lock()
	if _task_id == -1 and not _pending.is_empty() and not _abort:
		_task_id = WorkerThreadPool.add_task(_worker_loop, false, "CombatFxWarmup")
	_mutex.unlock()


func _process(_delta: float) -> void:
	_drain_completed()
	var finished_tid := -1
	var restart := false
	_mutex.lock()
	if _task_id != -1 and WorkerThreadPool.is_task_completed(_task_id):
		finished_tid = _task_id
		_task_id = -1
		restart = not _pending.is_empty() and not _abort
	_mutex.unlock()
	if finished_tid != -1:
		WorkerThreadPool.wait_for_task_completion(finished_tid)
		_drain_completed()
	if restart:
		_ensure_worker_started()
		return
	if not is_worker_active():
		set_process(false)
		queue_free()


static func _drain_completed() -> void:
	var ready_batch: Array[Dictionary] = []
	_mutex.lock()
	if not _completed.is_empty():
		ready_batch = _completed.duplicate()
		_completed.clear()
	_mutex.unlock()
	if ready_batch.is_empty():
		return
	for item in ready_batch:
		var key := String(item["key"])
		var tr: BAKER.Track = item["track"]
		var existing: Variant = PixelFx2D._cache.get(key)
		if existing != null and existing is BAKER.Track:
			var ex_tr: BAKER.Track = existing
			if not ex_tr.done():
				ex_tr.frames = tr.frames
				ex_tr.inst = null
		else:
			PixelFx2D._cache[key] = tr
			PixelFx2D._hook_cleanup()


static func _worker_loop() -> void:
	while true:
		var job: Dictionary = {}
		_mutex.lock()
		if _abort or _pending.is_empty():
			_mutex.unlock()
			return
		job = _pending.pop_front()
		_mutex.unlock()

		var key := String(job["key"])
		var mod: Script = job["mod"]
		var opts: Dictionary = job["opts"]
		var cache_path := String(job["cache_path"])
		var tr := _try_load_cached_track(cache_path, key, mod, opts)
		if tr == null:
			tr = _bake_track_offline(mod, opts)
			if tr == null:
				return
			_save_cached_track(cache_path, key, tr)
		_mutex.lock()
		if not _abort:
			_completed.append({"key": key, "track": tr})
		_mutex.unlock()


static func _bake_track_offline(mod: Script, opts: Dictionary) -> BAKER.Track:
	var tr: BAKER.Track = BAKER.track(mod, opts, "")
	for i in tr.n:
		_mutex.lock()
		var stop := _abort
		_mutex.unlock()
		if stop:
			return null
		tr.get_frame(i)
	return tr


static func _try_load_cached_track(path: String, expected_key: String,
		mod: Script, opts: Dictionary) -> BAKER.Track:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return null
	var payload: Variant = f.get_var(false)
	f.close()
	if not (payload is Dictionary):
		return null
	var d: Dictionary = payload
	if int(d.get("v", 0)) != CACHE_VERSION or String(d.get("key", "")) != expected_key:
		return null
	var w := int(d.get("w", 0))
	var h := int(d.get("h", 0))
	var raw_frames = d.get("frames", null)
	if w <= 0 or h <= 0 or not (raw_frames is Array):
		return null
	var tr: BAKER.Track = BAKER.track(mod, opts, "")
	if tr.w != w or tr.h != h or (raw_frames as Array).size() != tr.n:
		return null
	var expected_bytes := w * h * 4
	var restored: Array = []
	for entry in raw_frames:
		if not (entry is Array) or (entry as Array).size() != 3:
			return null
		var cb: PackedByteArray = entry[0]
		var lb: PackedByteArray = entry[1]
		var bb: PackedByteArray = entry[2]
		if cb.size() != expected_bytes or bb.size() != expected_bytes:
			return null
		var color_img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, cb)
		var light_img: Variant = null
		if lb.size() == expected_bytes:
			light_img = Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, lb)
		var both_img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bb)
		restored.append([color_img, light_img, both_img])
	tr.frames = restored
	tr.inst = null
	return tr


static func _save_cached_track(path: String, key: String, tr: BAKER.Track) -> void:
	if tr == null or not tr.done():
		return
	var abs_dir := ProjectSettings.globalize_path(CACHE_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)
	var packed_frames: Array = []
	for fr in tr.frames:
		var color_img: Image = fr[0]
		var light_img: Variant = fr[1]
		var both_img: Image = fr[2]
		packed_frames.append([
			color_img.get_data(),
			(light_img as Image).get_data() if light_img is Image else PackedByteArray(),
			both_img.get_data(),
		])
	var payload := {
		"v": CACHE_VERSION,
		"key": key,
		"w": tr.w,
		"h": tr.h,
		"n": tr.n,
		"fps": tr.fps,
		"frames": packed_frames,
	}
	var tmp_path := path + ".tmp"
	var f := FileAccess.open_compressed(tmp_path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null:
		return
	f.store_var(payload, false)
	f.close()
	var abs_tmp := ProjectSettings.globalize_path(tmp_path)
	var abs_dst := ProjectSettings.globalize_path(path)
	DirAccess.rename_absolute(abs_tmp, abs_dst)
