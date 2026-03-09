# Garmin BaseCamp Environment - Evidence Documentation

## Environment: garmin_basecamp_env
**Verified:** 2026-02-25
**Base Image:** windows-11
**App:** Garmin BaseCamp 4.7.5 (GPS route planning software)

---

## Pre-Start Hook Verification

**Script:** `scripts/install_garmin_basecamp.ps1`
- Downloads Garmin BaseCamp 4.7.5 (~61MB) via BITS
- Installs Python 3.11 for automation support
- Installs pyautogui, pywin32, pygetwindow, Pillow libraries
- Creates BaseCamp data directory structure

**Script:** `scripts/setup_garmin_basecamp.ps1`
- Imports `fells_loop.gpx` into BaseCamp library
- Creates database backup at `C:\GarminTools\BaseCampBackup\Database\4.7\`
- Backup files: `AllData.gdb` (12,618 bytes) + `FolderData.gfi` (1,924 bytes)
- Database contains 86 waypoints including BEAR HILL, BELLEVUE, SHEEPFOLD, DARKHOLLPO, etc.
- Disables OneDrive startup and backup notifications via registry policies

---

## Task Start States

### Task 1: change_waypoint_symbol
**Screenshot:** `ts_01_change_waypoint_symbol_start_state.png`
- BaseCamp open in foreground, map zoomed to Medford/Middlesex Fells area
- Library tree expanded showing fells_loop with waypoints visible in list
- No console windows (PyAutoGUI terminal) visible — minimized by WinHelper
- No OneDrive notification — disabled via registry policies
- BEAR HILL, BELLEVUE, SHEEPFOLD waypoints present in database

### Task 2: create_waypoint
**Screenshot:** `ts_02_create_waypoint_start_state.png`
- BaseCamp open in foreground, map zoomed to Medford/Middlesex Fells area
- Library populated with fells_loop waypoints
- No console windows or OneDrive notifications visible
- Agent must create a new waypoint at specified coordinates

### Task 3: rename_waypoint
**Screenshot:** `ts_03_rename_waypoint_start_state.png`
- BaseCamp open in foreground, map zoomed to Medford/Middlesex Fells area
- Library populated with fells_loop waypoints
- No console windows or OneDrive notifications visible
- Agent must rename BELLEVUE waypoint to "Bellevue Parking"

### Task 4: create_route
**Screenshot:** `ts_04_create_route_start_state.png`
- BaseCamp open in foreground, map zoomed to Medford/Middlesex Fells area
- Library populated with fells_loop waypoints
- No console windows or OneDrive notifications visible
- Agent must create a route using available waypoints

### Task 5: import_gpx_file
**Screenshot:** `ts_05_import_gpx_file_start_state.png`
- BaseCamp open in foreground with world map view
- Library shows "This list is empty." — database cleared before launch
- No console windows or OneDrive notifications visible
- `dole_langres_track.gpx` placed on Desktop for agent to import

---

## Key Technical Notes

### Task Launcher Behavior (CRITICAL)
- BaseCamp always shows a "Task Launcher" dialog on startup
- The Task Launcher IS BaseCamp's main window (hwnd = MainWindowHandle)
- Pressing ESC, clicking X, or clicking Close on Task Launcher **closes BaseCamp entirely**
- Correct dismissal: Click "Plan a Trip" button at (443, 210) in 1280x720 coordinates
- After clicking "Plan a Trip": Route Planner opens + Tutorial Video tip may appear
- Dismiss tutorial tip with ESC, then dismiss Detailed Map / 3D Terrain dialogs at (806, 405)
- Final ESC closes Route Planner → returns to main map view with library

### Window Management (CRITICAL)
- Console windows (PyAutoGUI terminal) are minimized using `WinHelper.cs` with Win32 `EnumWindows` API
- `EnumWindows` + `GetClassName` checks for `"ConsoleWindowClass"` to find console windows
- `ShowWindow(hwnd, SW_MINIMIZE)` minimizes consoles; `SetForegroundWindow` brings BaseCamp to front
- This runs inside the `schtasks /IT` script in Session 1 (interactive desktop)
- SSH Session 0 CANNOT manage Session 1 windows — `Get-Process.MainWindowHandle` returns 0

### Win32 API Approach
- Mouse clicks use `SetCursorPos` + `mouse_event` Win32 API (more reliable than SendKeys)
- SendKeys (`{ESCAPE}`) used for keyboard-only input
- All interactive session operations use `schtasks /IT` to run in Session 1 (interactive desktop)
- SSH runs in Session 0 (non-interactive) and cannot directly interact with GUI

### Map Zoom
- After dismissing Task Launcher dialogs, double-click on "fells_loop" in library tree (191, 236)
- This zooms the map to the Medford/Middlesex Fells Reservation area where waypoints are located
- For import_gpx_file task, library is empty so no zoom is performed (world view)

### Database Locations
- Active database: `C:\Users\Docker\AppData\Roaming\Garmin\BaseCamp\Database\4.7\`
- Backup: `C:\GarminTools\BaseCampBackup\Database\4.7\`
- Files: `AllData.gdb` (SQLite) + `FolderData.gfi`

### OneDrive Mitigation
- Registry policies set in `setup_garmin_basecamp.ps1` (persisted in checkpoint):
  - `HKLM:\SOFTWARE\Policies\Microsoft\OneDrive\KFMBlockOptIn = 1`
  - `HKLM:\SOFTWARE\Policies\Microsoft\OneDrive\PreventNetworkTrafficPreUserSignIn = 1`
  - OneDrive removed from `HKCU:\...\CurrentVersion\Run`
- WinHelper also minimizes any windows with "OneDrive" or "Windows Backup" in title

### Installation Notes
- BaseCamp_475.exe: Valid download size ~61MB; partial downloads (~47MB) are corrupt
- Use BITS (`Start-BitsTransfer`) for reliable download
- Silent install: `/install /quiet /norestart` (exit 0 = success, 3010 = reboot recommended)

---

## Verification Commands

```python
# Check VM is accessible
import paramiko
client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect("localhost", port=SSH_PORT, username="Docker", password="GymAnything123!")

# Run task setup
stdin, stdout, stderr = client.exec_command(
    "powershell -ExecutionPolicy Bypass -File C:\\workspace\\tasks\\change_waypoint_symbol\\setup_task.ps1",
    timeout=150
)
print(stdout.read().decode())

# Take screenshot
from gym_anything.runners.vnc_utils import VNCConnection
c = VNCConnection("localhost", VNC_PORT, password="password")
c.connect()
data = c.capture_screenshot()
```
