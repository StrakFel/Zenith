param([string]$Scene,[string]$Out,[int]$Frames=90,[string]$Locale="",[string]$Hooks="")
# Developer screenshot helper (needs a real renderer, so NOT headless).
$g="$env:USERPROFILE\Desktop\Godot.exe"
$proj=Split-Path $PSScriptRoot -Parent
$arg = "--path `"$proj`" --resolution 1280x720 --script res://Tools/shot.gd -- $Scene `"$Out`" $Frames `"$Locale`" `"$Hooks`""
$p=Start-Process $g -ArgumentList $arg -RedirectStandardOutput "$Out.log" -RedirectStandardError "$Out.err" -Wait -PassThru -NoNewWindow
"exit $($p.ExitCode)"
Get-Content "$Out.log","$Out.err" -Encoding utf8 -ErrorAction SilentlyContinue | Where-Object { $_ -match 'ERROR|SCRIPT|WARNING|Parse|SHOT|Invalid|Cannot' } | Select -First 30
