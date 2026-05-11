$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$extensionsFile = Join-Path $scriptDir "vscode_extensions.txt"

# Fail fast if extensions.txt is missing
if (-not (Test-Path $extensionsFile)) {
  Write-Error "vscode_extensions.txt not found at $extensionsFile"
  exit 1
}

# Fail fast if code CLI is not available
if (-not (Get-Command code -ErrorAction SilentlyContinue)) {
  Write-Error "'code' CLI not found. Open VS Code and run: Shell Command: Install 'code' command in PATH"
  exit 1
}

# Read extensions, stripping comments and blank lines
$extensions = Get-Content $extensionsFile | ForEach-Object {
  $line = $_ -replace '#.*', ''   # strip inline comments
  $line.Trim()
} | Where-Object { $_ -ne '' }

Write-Host "Installing $($extensions.Count) VS Code extensions..."

$failed = 0

foreach ($ext in $extensions) {
  Write-Host "Installing $ext..."
  code --install-extension $ext --force
  if ($LASTEXITCODE -ne 0) {
    Write-Warning "Failed to install: $ext"
    $failed++
  }
}

if ($failed -gt 0) {
  Write-Error "Done with $failed failure(s). Check the output above."
  exit 1
} else {
  Write-Host "✅ Done! Restart VS Code to activate all extensions."
}