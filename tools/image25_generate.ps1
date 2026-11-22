param(
	[Parameter(Mandatory = $true)][string]$Prompt,
	[Parameter(Mandatory = $true)][string]$OutPath,
	[string]$Size = "1536x1024",
	[string]$Model = "gpt-image-2.5-sunburst"
)

# image2.5 只能走 images 端点，chat/completions 会返回 model_endpoint_mismatch。
# 密钥从环境变量读取，不要写进仓库：$env:RINKO_API_KEY = "sk-..."
$key = $env:RINKO_API_KEY
if (-not $key) {
	throw "未设置环境变量 RINKO_API_KEY"
}

$body = @{ model = $Model; prompt = $Prompt; n = 1; size = $Size } | ConvertTo-Json -Compress
$resp = Invoke-RestMethod -Uri "https://api.rinko.ai/v1/images/generations" `
	-Method Post `
	-Headers @{ Authorization = "Bearer $key" } `
	-ContentType "application/json" `
	-Body $body `
	-TimeoutSec 300

if ($resp.error) {
	throw $resp.error.message
}
if (-not $resp.data -or -not $resp.data[0].b64_json) {
	throw "接口没有返回图片数据"
}

$bytes = [Convert]::FromBase64String($resp.data[0].b64_json)
$dir = Split-Path -Parent $OutPath
if ($dir -and -not (Test-Path $dir)) {
	New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
[System.IO.File]::WriteAllBytes($OutPath, $bytes)
Write-Output "saved $OutPath ($($resp.data[0].width)x$($resp.data[0].height))"
