Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_pre_task_audit_and_deduplicate_commands.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up audit_and_deduplicate_commands task ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (-not (Test-Path $utils)) { throw "Missing task utils: $utils" }
    . $utils

    # Record task start timestamp
    $timestamp = (Get-Date).ToString("o")
    [System.IO.File]::WriteAllText("C:\Users\Docker\task_start_ts_audit_and_deduplicate_commands.txt", $timestamp)

    # Create the user_commands directory
    $cmdDir = "$Script:CommunityDir\user_commands"
    New-Item -ItemType Directory -Force -Path $cmdDir | Out-Null

    # Remove any previously created files for a clean state
    Get-ChildItem -Path $cmdDir -Filter "*.talon" -ErrorAction SilentlyContinue | Remove-Item -Force
    if (Test-Path "$cmdDir\audit_report.txt") { Remove-Item "$cmdDir\audit_report.txt" -Force }

    # -----------------------------------------------------------------------
    # File 1: editor_commands.talon
    # Contains: "go to line" (duplicate), "open terminal" (duplicate)
    # Scoped: OS-level (less specific - no app restriction)
    # -----------------------------------------------------------------------
    $editorContent = @'
# General editor commands (no app context - OS-wide)
os: windows
-
# Navigation
go to line:
    key(ctrl-g)
# Terminal
open terminal:
    key(ctrl-grave)
# Editing
select all: key(ctrl-a)
undo last: key(ctrl-z)
redo last: key(ctrl-y)
copy selection: key(ctrl-c)
paste here: key(ctrl-v)
'@
    [System.IO.File]::WriteAllText("$cmdDir\editor_commands.talon", $editorContent)
    Write-Host "Created editor_commands.talon (has 'go to line' and 'open terminal')"

    # -----------------------------------------------------------------------
    # File 2: general_commands.talon
    # Contains: "save file" (duplicate), scoped to no app (OS-wide)
    # -----------------------------------------------------------------------
    $generalContent = @'
# General productivity commands (no app context)
-
# File operations
save file: key(ctrl-s)
new file: key(ctrl-n)
close file: key(ctrl-w)
# Window
switch window: key(alt-tab)
minimize window: key(win-down)
maximize window: key(win-up)
# Clipboard
show clipboard: key(win-v)
'@
    [System.IO.File]::WriteAllText("$cmdDir\general_commands.talon", $generalContent)
    Write-Host "Created general_commands.talon (has 'save file')"

    # -----------------------------------------------------------------------
    # File 3: productivity_commands.talon
    # Contains: "go to line", "open terminal", "save file" (all duplicates)
    # Scoped more specifically to code editors
    # -----------------------------------------------------------------------
    $productivityContent = @'
# Code editor productivity commands (more specific: Notepad++)
app.name: /notepad\+\+/i
-
# Navigation - go to specific line in editor
go to line:
    key(ctrl-g)
    sleep(200ms)
    insert("Go to line: ")
# Terminal panel
open terminal:
    key(ctrl-grave)
    sleep(300ms)
# File saving with confirmation
save file:
    key(ctrl-s)
    sleep(100ms)
# Additional commands
format document: key(ctrl-shift-f)
toggle comment: key(ctrl-slash)
duplicate line:
    key(home)
    key(shift-end)
    key(ctrl-c)
    key(end)
    key(return)
    key(ctrl-v)
next tab: key(ctrl-tab)
previous tab: key(ctrl-shift-tab)
'@
    [System.IO.File]::WriteAllText("$cmdDir\productivity_commands.talon", $productivityContent)
    Write-Host "Created productivity_commands.talon (has all 3 duplicates)"

    # Open the directory in File Explorer
    Start-Process explorer.exe -ArgumentList $cmdDir
    Start-Sleep -Seconds 2

    # Open editor_commands.talon in the editor so agent can see an example
    Open-FileInteractive -FilePath "$cmdDir\editor_commands.talon" -WaitSeconds 7

    Minimize-TerminalWindows

    Write-Host "=== audit_and_deduplicate_commands task setup complete ==="
    Write-Host "=== 3 conflicts seeded across: editor_commands.talon, general_commands.talon, productivity_commands.talon ==="
    Write-Host "=== Duplicate triggers: 'go to line', 'open terminal', 'save file' ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
