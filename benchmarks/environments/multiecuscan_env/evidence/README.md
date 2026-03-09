# Multiecuscan Environment - Evidence Documentation

## Environment Setup Verification

### Pipeline-Generated Screenshots

| File | Description | Status |
|------|-------------|--------|
| `frame_00000_pipeline.png` | **Pipeline frame_00000.png** from automated `env.reset()` — MES main UI with vehicle selection (Alfa Romeo/Fiat/Lancia makes, model list, system/control module panels). No Disclaimer, no terminals, no OneDrive. | **Verified via visual_grounding** |
| `01_main_ui_vehicle_select.png` | Main UI showing vehicle make/model/system selection panels | Verified via visual_grounding |
| `02_simulation_mode_info_tab.png` | Simulation mode active - Info tab showing ECU details for Fiat 500 1.3 Multijet | Verified |
| `03_errors_tab_dtc_codes.png` | Errors tab showing DTCs (B0110-15, P068A-68) with descriptions | Verified |
| `04_parameters_tab.png` | Parameters tab showing OBD parameters (RPM, voltage, pressure, etc.) | Verified |
| `05_fiat_model_selection.png` | Fiat selected - showing 500 model variants (0.9 TwinAir, 1.2 8V, 1.3 Multijet, etc.) | Verified |

### Setup Log Snippet

See `setup_log_snippet.txt` for actual output from the automated pipeline run showing:
- QEMU VM boot with KVM acceleration
- SSH connection established
- 3 mounts copied (scripts, tasks, data)
- Windows desktop ready detection
- PyAutoGUI server started (1280x720)
- Pre-start hook execution (~787s for .NET 3.5 install + ngen + MSI install)
- Post-start hook execution (ngen queue drain + warm-up launch + OneDrive disable + terminal hide)
- Pre-task hook execution (~140s for OneDrive kill + app launch + synchronized dialog dismissal)

### Checklist

- [x] Installation script completes without errors (.NET 3.5 via DISM + ngen executeQueuedItems + MSI)
- [x] Setup script completes without errors (ngen drain, warm-up launch, OneDrive disable, terminal hide)
- [x] Application is visible in frame_00000.png (Multiecuscan 5.4 vehicle selection UI)
- [x] Application is in correct initial state (Disclaimer dismissed, main selection view)
- [x] No terminal/command prompt windows visible in frame_00000.png
- [x] No OneDrive popup visible; OneDrive process not running
- [x] Real data is loaded and available (dtc_database_full.csv, real OBD session CSVs)
- [x] Task setup runs without errors (app launched, dialogs dismissed, completion marker written)
- [x] Task start state verified via visual_grounding MCP tool
- [x] Simulation mode works (Info/Errors/Parameters tabs all functional)
- [x] Sufficient evidence that tasks are completable (vehicle selection, simulation, DTC reading, parameter viewing)

### Key Technical Findings

1. **.NET 3.5 + ngen required**: Windows 11 base image has .NET 3.5 "DisabledWithPayloadRemoved". After DISM installs it, `ngen executeQueuedItems` must run for all .NET Framework versions to compile native images. Without this, MES crashes on first launch.

2. **Disclaimer is an embedded panel**: The MES "Disclaimer" is NOT a separate top-level window. It's rendered inside the main "Multiecuscan 5.4" window. `FindWindow("Disclaimer")` returns Zero. Dismissal requires focusing the MES window and using center-relative clicking (closeBtnX = centerX + 175, closeBtnY = centerY + 175) plus keyboard strategies.

3. **Synchronized dismiss**: `dismiss_dialogs.ps1` writes `C:\Temp\dismiss_complete.txt` when done. `Run-DismissDialogs` in task_utils.ps1 polls for this marker (90s timeout) instead of blind sleep.

4. **Hidden PowerShell windows**: All schtasks launches use `powershell.exe -WindowStyle Hidden -NonInteractive` directly. No CMD batch wrappers. Terminal windows hidden with SW_HIDE (0).

5. **OneDrive suppression**: Killed in post_start hook (setup_multiecuscan.ps1), disabled via registry, renamed executable. Also killed again in pre_task hook via Kill-OneDriveAndNotifications.

6. **MSI pre-bundled**: Multiecuscan MSI is pre-included in data directory as reliable fallback (no network download needed).
