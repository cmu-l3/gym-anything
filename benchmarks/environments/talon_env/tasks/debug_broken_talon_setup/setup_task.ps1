Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_debug_broken_talon_setup.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up debug_broken_talon_setup task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Record task start timestamp
    $timestamp = (Get-Date).ToString("o")
    [System.IO.File]::WriteAllText("C:\Users\Docker\task_start_ts_debug_broken_talon_setup.txt", $timestamp)
    Write-Host "Task start time recorded: $timestamp"

    # Create the user_config subdirectory in community dir
    $configDir = "$Script:CommunityDir\user_config"
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null
    Write-Host "Created config directory: $configDir"

    # -----------------------------------------------------------------------
    # Bug 1: user_settings.talon
    # Error: speech.timeout is a quoted string "3" instead of the number 3
    # -----------------------------------------------------------------------
    $settingsContent = @'
# User settings for Talon voice control
# Developer productivity configuration
settings():
    # Speech recognition timeout in seconds (numeric value required)
    speech.timeout = "3"
    # Mouse scroll amount
    user.mouse_wheel_down_amount = 5
    # UI scale factor
    imgui.scale = 1.2
'@
    [System.IO.File]::WriteAllText("$configDir\user_settings.talon", $settingsContent)
    Write-Host "Created broken user_settings.talon (Bug: quoted string for numeric setting)"

    # -----------------------------------------------------------------------
    # Bug 2: window_management.talon
    # Error: missing '-' separator between context header and command body
    # -----------------------------------------------------------------------
    $windowContent = @'
# Window management voice commands
# Context: Windows operating system
os: windows
switch to previous window: key(alt-tab)
maximize current window: key(win-up)
minimize current window: key(win-down)
snap window left: key(win-left)
snap window right: key(win-right)
close current window: key(alt-f4)
'@
    [System.IO.File]::WriteAllText("$configDir\window_management.talon", $windowContent)
    Write-Host "Created broken window_management.talon (Bug: missing dash separator)"

    # -----------------------------------------------------------------------
    # Bug 3: user.browser_shortcuts.talon-list
    # Error: list name header says 'user.web_shortcuts' but file is named
    #        'user.browser_shortcuts.talon-list', so Talon can't match them
    # -----------------------------------------------------------------------
    $listContent = @'
list: user.web_shortcuts
-
new tab: ctrl-t
close tab: ctrl-w
reopen closed tab: ctrl-shift-t
bookmark page: ctrl-d
open history: ctrl-h
open downloads: ctrl-j
address bar: ctrl-l
'@
    [System.IO.File]::WriteAllText("$configDir\user.browser_shortcuts.talon-list", $listContent)
    Write-Host "Created broken user.browser_shortcuts.talon-list (Bug: list name mismatch)"

    # -----------------------------------------------------------------------
    # Bug 4: text_actions.py
    # Error: IndentationError — one line inside duplicate_line() has 9 spaces
    #        instead of 8 spaces (one extra leading space)
    # -----------------------------------------------------------------------
    # Build string carefully to embed the indentation bug
    # Line "         actions.key(`"home`")" must have exactly 9 leading spaces
    $pyLines = @(
        "from talon import Module, actions",
        "",
        "mod = Module()",
        "",
        "",
        "@mod.action_class",
        "class Actions:",
        "    def insert_date_stamp():",
        "        `"Insert the current date as a timestamp`"",
        "        actions.insert(`"2024-01-15`")",
        "",
        "    def duplicate_line():",
        "        `"Duplicate the current line`"",
        "         actions.key(`"home`")",   # 9 spaces - BUG
        "        actions.key(`"shift-end`")",
        "        actions.key(`"ctrl-c`")",
        "        actions.key(`"end`")",
        "        actions.key(`"return`")",
        "        actions.key(`"ctrl-v`")"
    )
    $pythonContent = $pyLines -join "`r`n"
    [System.IO.File]::WriteAllText("$configDir\text_actions.py", $pythonContent)
    Write-Host "Created broken text_actions.py (Bug: IndentationError on duplicate_line body)"

    # Open the community dir in File Explorer so the agent can see the files
    Start-Process explorer.exe -ArgumentList $configDir
    Start-Sleep -Seconds 3

    # Minimize terminal windows
    Minimize-TerminalWindows

    Write-Host "=== debug_broken_talon_setup task setup complete ==="
    Write-Host "=== Four broken files created in: $configDir ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
