<#!
.SYNOPSIS
Builds a standalone AI Usage Monitor executable from a fully provisioned Python environment.
#>
[CmdletBinding()]
param(
    [string]$Python = "py"
)

$ErrorActionPreference = "Stop"

& $Python -m pip install -r requirements.txt pyinstaller
& $Python -m PyInstaller --noconsole --onefile --name "AI Usage Monitor" --collect-all pystray app.py

Write-Host "Built dist\AI Usage Monitor.exe"
