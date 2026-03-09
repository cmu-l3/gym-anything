# bcWebCam Environment - Evidence Documentation

## Environment Summary

- **Application**: bcWebCam v3.0.4 by QS QualitySoft GmbH
- **Platform**: Windows 11 (QEMU VM with KVM)
- **Base Preset**: `base_windows_11`
- **SSH User**: `Docker` / `GymAnything123!`
- **VNC Password**: `password`
- **Tasks**: 5 configuration tasks (all easy difficulty)

## Checklist Verification

### Installation (pre_start hook)
- [x] .NET Framework 4.8 verified present
- [x] bcWebCam downloaded from `https://bcwebcam.de/wp-content/uploads/area-en/bcwebcam_en.zip`
- [x] MSI silent install completed (exit code 0)
- [x] bcWebCam.exe found at `C:\Program Files\bcWebCam\bcWebCam.exe`
- [x] Python 3.11 verified present
- [x] Barcode libraries installed (pyzbar, python-barcode, Pillow)
- [x] Barcode images generated to `C:\workspace\data\barcodes\`

### Setup (post_start hook)
- [x] Config directory created at `C:\Users\Docker\AppData\Local\bcWebCam`
- [x] Desktop shortcut created
- [x] Warm-up launch completed (first-run dialogs dismissed via PyAutoGUI)
- [x] Barcode data copied to `C:\Users\Docker\Desktop\Barcodes\`
- [x] Edge browser disabled (registry policies + session data cleared)

### Task Start State
- [x] bcWebCam main window visible (see `01_task_start_state.png`)
- [x] No blocking dialogs or browsers covering the application
- [x] Options dialog accessible via gear icon (see `02_options_dialog.png`)
- [x] Barcode Options dialog accessible via barcode icon (see `03_barcode_options_dialog.png`)
- [x] All settings in expected default state for task descriptions

### Default Settings Verified (from Options Dialog)
| Setting | Default State | Task |
|---------|--------------|------|
| Append terminating character | `<ENTER>` selected | set_terminating_character (change to TAB) |
| Copy read barcode to clipboard | Unchecked | enable_clipboard_copy (check it) |
| Open detected URL | Unchecked | enable_url_detection (check it) |
| Delete recognized Barcode after | Unchecked, 0 seconds | configure_barcode_timeout (enable, set 500s) |
| Read Linear Barcodes | Unchecked | enable_linear_barcodes (check it) |
| Read EAN barcodes | Checked | (default, not a task) |
| Read QR Codes | Checked | (default, not a task) |

## Screenshots

### 01_task_start_state.png
bcWebCam main window after pre_task hook completes. Shows the tutorial page "How to read barcodes with bcWebCam in 3 steps". No Edge browser or blocking dialogs visible. PyAutoGUI console is visible on the right side (used for GUI automation during setup).

### 02_options_dialog.png
The bcWebCam Options dialog (opened via gear icon in bottom toolbar). Shows all configurable settings including:
- Barcode handling (terminating character, auto-deletion timeout)
- Clipboard copy option
- URL detection option
- Image capture device settings
- Software update settings

### 03_barcode_options_dialog.png
The Barcode Options dialog (opened via barcode icon button). Shows:
- Read EAN barcodes: Checked
- Read QR Codes: Checked
- Read Linear Barcodes: Unchecked
- Read Data Matrix: Unchecked
- Read Aztec Codes: Unchecked
- Read PDF 417: Unchecked

## Log Evidence

### pre_start (install_bcwebcam.ps1) - Key Output
```
=== Installing bcWebCam Environment ===
--- Checking .NET Framework 4.8 ---
.NET Framework 4.8 or later is already installed (release=533509)
--- Downloading bcWebCam ---
Trying: https://bcwebcam.de/wp-content/uploads/area-en/bcwebcam_en.zip
Downloaded successfully from https://bcwebcam.de/wp-content/uploads/area-en/bcwebcam_en.zip
--- Installing bcWebCam ---
Found MSI installer: C:\temp\bcwebcam_install\bcwebcam_extracted\bcWebCamSetup.en.msi
MSI install exit code: 0
Copied bcWebCam.default config
Copied qsbc.lic license file
--- Verifying bcWebCam installation ---
bcWebCam found at: C:\Program Files\bcWebCam\bcWebCam.exe
--- Installing Python 3 ---
Python already installed: C:\Program Files\Python311\python.exe
--- Installing Python barcode libraries ---
Python barcode libraries installed
--- Generating barcode images ---
Barcode images generated successfully
=== bcWebCam Environment Installation Complete ===
```

### post_start (setup_bcwebcam.ps1) - Key Output
```
=== Setting up bcWebCam Environment ===
--- Preparing bcWebCam config ---
Config directory ready at C:\Users\Docker\AppData\Local\bcWebCam
--- Locating bcWebCam ---
Found bcWebCam at: C:\Program Files\bcWebCam\bcWebCam.exe
--- Warm-up launch of bcWebCam ---
Dismissing First Start dialog via PyAutoGUI...
Dismissing No WebCam error dialog...
Dialogs dismissed via PyAutoGUI
Closing bcWebCam gracefully (Alt+F4)...
Warm-up launch complete
--- Copying barcode data ---
--- Closing browser windows and disabling Edge ---
=== bcWebCam Environment Setup Complete ===
```

### pre_task (setup_task.ps1) - Behavior
The pre_task hook for each task:
1. Starts a background job that repeatedly kills Edge every 2 seconds (Windows 11 session restore keeps bringing Edge back from the checkpoint)
2. Calls `Close-Browsers` (kills browsers, clears Edge session data, sets registry policies)
3. Kills any existing bcWebCam process
4. Launches bcWebCam in the interactive desktop session via `schtasks /IT`
5. Calls `Close-Browsers` again (Edge may have auto-restored during bcWebCam launch)
6. Dismisses the "No WebCam device driver" error dialog using PyAutoGUI (Alt+Tab to bring dialog to front, then Enter/click)
7. Stops the background Edge killer job

## Known Issues and Workarounds

### Edge Auto-Restore from Checkpoint
Windows 11 automatically restores previously running applications when resuming from a VM checkpoint (savevm). Edge was running when the base Windows 11 image was created, so it auto-restores every time. The workaround is a background PowerShell job that repeatedly kills Edge during the pre_task setup.

### PyAutoGUI Console Window Z-Order
The PyAutoGUI TCP server runs in a console window in the interactive desktop session. This console can cover bcWebCam dialogs, causing click coordinates to miss their targets. The `Dismiss-BcWebCamDialogs` function uses Alt+Tab to cycle windows and Enter key presses to dismiss dialogs regardless of which window has focus.

### PowerShell `$Host` Variable
PowerShell's `$Host` is a read-only automatic variable. The `Invoke-PyAutoGUICommand` function uses `$Server` as the parameter name for the TCP server address (NOT `$Host`).

### bcWebCam First-Run Dialog Sequence
On first launch, bcWebCam shows:
1. "bcWebCam - First Start" welcome dialog (OK button at ~639, 536)
2. Tutorial page in main window
3. "No compatible Virtual device driver available" error (OK button at ~782, 418)

The post_start hook performs a warm-up launch to dismiss these first-run dialogs and save the first-run state. Subsequent launches from pre_task only show the "No WebCam" error dialog.

## Task Descriptions

### 1. set_terminating_character
Change the terminating character from ENTER to TAB. Useful for scanning barcodes into spreadsheets.

### 2. enable_clipboard_copy
Enable automatic clipboard copy of scanned barcode data.

### 3. enable_url_detection
Enable automatic opening of URLs detected in QR codes.

### 4. configure_barcode_timeout
Enable auto-deletion of recognized barcodes after 500 seconds.

### 5. enable_linear_barcodes
Enable reading of linear barcodes (Code 128, Code 39) in addition to EAN and QR codes.
