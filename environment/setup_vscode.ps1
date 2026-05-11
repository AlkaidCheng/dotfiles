$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$extensionsFile = Join-Path $scriptDir "vscode_extensions.txt"

if (-not (Test-Path $extensionsFile)) {
  Write-Error "vscode_extensions.txt not found at $extensionsFile"
  exit 1
}

# Read extensions, stripping comments and blank lines
$extensions = Get-Content $extensionsFile |
  Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' } |
  ForEach-Object { $_.Trim() }

Write-Host "Installing $($extensions.Count) VS Code extensions..."

foreach ($ext in $extensions) {
  Write-Host "Installing $ext..."
  code --install-extension $ext --force
}

Write-Host "Done! Restart VS Code to activate all extensions."