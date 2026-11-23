---
name: godot-verify
description: >-
  Use this skill after editing GDScript, scenes, shaders, or data/*.json in
  HellWalker_DollProtocol to refresh Godot 4.7.2 imports, run the 45-test core
  2D regression gate, inspect logs via godot-ai MCP, and visually verify
  screenshots.
---

# Godot 4.7.2 编译、回归门禁与视觉验收流程

## 变量约定
```powershell
$GODOT = "D:\Godot\Godot_v4.7.2-stable_win64_console.exe"
$PROJ  = "D:\AI Game\HellWalker\HellWalker_DollProtocol"
```
> 命令行无头测试务必使用 console 版本（`D:\Godot\Godot_v4.7.2-stable_win64_console.exe`），否则 stdout 无法捕获。

## 步骤 1：刷新资源与全局类缓存（新增/改名脚本或资源后必跑）
```powershell
& $GODOT --headless --path $PROJ --import
```
核查无新增 `SCRIPT ERROR`、`Parse Error`、`Could not find type`（注：`addons/phantom_camera` 自带 `update_button.gd:62` 插件内部噪音，与业务脚本无关）。若 Godot GUI 编辑器正打开且未增删脚本/资源，测试时可加 `-SkipImport` 避免与编辑器争夺 `.godot` 缓存。

## 步骤 2：运行核心 2D 回归门禁（45 个测试）
使用汇总脚本 [run_core_tests.ps1](./scripts/run_core_tests.ps1)（日志输出至 `out/test_logs/`，自动校验输出摘要而非仅看进程退出码）：

```powershell
# 全量 45 个核心 2D 回归（任务收口前必跑；基线 1441 条断言，0 失败）
powershell -ExecutionPolicy Bypass -File .agents/skills/godot-verify/scripts/run_core_tests.ps1

# 跳过 --import（编辑器正运行或仅验证已有脚本时）
powershell -ExecutionPolicy Bypass -File .agents/skills/godot-verify/scripts/run_core_tests.ps1 -SkipImport

# 快速迭代：仅跑与本次改动相关的子集
powershell -ExecutionPolicy Bypass -File .agents/skills/godot-verify/scripts/run_core_tests.ps1 -SkipImport -Tests shoot_2d_test,bullet_speed_test,ads_test
```

### 可选/共享补充测试（按需运行）
```powershell
# 共享 Sfx 采样与命中材质（15 项）
& $GODOT --headless --path $PROJ --script res://tests/impact_audio_test.gd
# 新武器装配与开火冒烟（18 项）
& $GODOT --headless --path $PROJ --script res://tests/_verify_new_weapons.gd
# 跨进程存档持久化（必须按顺序分 3 个独立进程执行）
& $GODOT --headless --path $PROJ --script res://tests/save_persistence_test.gd -- --phase write --save-path user://save_persist.json
& $GODOT --headless --path $PROJ --script res://tests/save_persistence_test.gd -- --phase write --save-path user://save_persist.json
& $GODOT --headless --path $PROJ --script res://tests/save_persistence_test.gd -- --phase verify --save-path user://save_persist.json
```

### 不纳入 2D 门禁的测试
- 21 个 3D 遗留测试（`ballistics_test`、`base_room_test`、`camera_test`、`combat_feedback_test`、`demo_capture_test`、`information_warfare_test`、`looting_test`、`m3_test`、`m4_1_test`~`m4_4_test`、`m5_test`、`occlusion_test`、`reliability_test`、`run_loop_test`、`settings_test`、`smoke_test`、`sound_support_test`、`vision_test`、`wall_window_test`）。

## 步骤 3：利用 `godot-ai` MCP 检查实时编辑器状态（编辑器已打开时）
- `session_manage(op="list")`：确认连接会话与当前场景；
- `editor_state`：确认播放/就绪状态；
- `logs_read`：查看编辑器和运行期错误日志；
- `editor_screenshot`：采集实时编辑器或游戏窗口画面。

## 步骤 4：视觉验收（UI、瞄具、武器对齐、视野、动画改动必做）
1. 抓图/录屏脚本（`_capture_*`、`_record_*`、`capture_*`、`record_*`）**必须在窗口模式下运行，不能加 `--headless`**；为保持游戏本体轻量，截图与 MovieWriter 录屏原始帧统一输出到工程外的 **`D:\AI Game\HellWalker\captures\screenshots\`** 与 **`D:\AI Game\HellWalker\captures\record\`**（成片 GIF 放至 `D:\AI Game\temp_20261027_01\videos\`），不要堆在 `HellWalker_DollProtocol` 内（并加 `--save-path user://...` 隔离存档）。
2. 使用 `read_file` 直接查看生成的 `.png` 截图与录像关键帧，核查布局溢出、遮挡、层级、准心对齐、透明通道白边及比例。

## 验收标准
- `--import` 无本项目脚本解析/类型错误；
- 相关测试及全量 45 项核心 2D 门禁全部 `PASS`（0 fail，无新增 `SCRIPT ERROR`）；
- 涉及画面/UI 的改动已通过 `read_file` 实图核验。
