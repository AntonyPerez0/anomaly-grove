# Format, lint and type check the game code. Must end with "CHECK PASSED".
# Usage (from the project root): powershell -ExecutionPolicy Bypass -File scripts/check.ps1

Set-Location (Split-Path -Parent $PSScriptRoot)

$dirs = @("ReplicatedStorage", "ServerScriptService", "ServerStorage", "StarterPlayerScripts")
$failed = $false

Write-Host "== 1/4 StyLua (format) =="
& stylua @dirs
if ($LASTEXITCODE -ne 0) { $failed = $true }

Write-Host "== 2/4 Selene (lint) =="
& selene @dirs
if ($LASTEXITCODE -ne 0) { $failed = $true }

Write-Host "== 3/4 Rojo (sourcemap for type checking) =="
& rojo sourcemap default.project.json --output sourcemap.json
if ($LASTEXITCODE -ne 0) { $failed = $true }

Write-Host "== 4/4 luau-lsp (type check) =="
if (-not (Test-Path "tools/globalTypes.d.luau")) {
    Write-Host "Missing tools/globalTypes.d.luau. Download it with:"
    Write-Host "  curl.exe -sSfL -o tools/globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau"
    $failed = $true
} else {
    & luau-lsp analyze --platform=roblox --sourcemap=sourcemap.json "--definitions:@roblox=tools/globalTypes.d.luau" @dirs
    if ($LASTEXITCODE -ne 0) { $failed = $true }
}

if ($failed) {
    Write-Host "CHECK FAILED"
    exit 1
}
Write-Host "CHECK PASSED"
