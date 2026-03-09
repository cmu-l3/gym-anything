# Configure Offline Mode Task (`configure_offline_mode@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Settings configuration, network dependency management, workflow optimization  
**Duration**: 180 seconds  
**Steps**: ~20

## Objective

Configure VSCode for productive offline work by disabling network-dependent features and enabling aggressive auto-save. This prepares the development environment for working without internet connectivity (e.g., on flights, in remote locations, or with poor WiFi).

## Scenario

You're about to board a long international flight and want to continue working on a Python data science project. You need to configure VSCode to prevent network timeout hangs and ensure your work is saved frequently in case of battery failure.

## Expected Configuration

Modify VSCode settings (User or Workspace) to include:

1. **Disable updates**: `"update.mode": "none"` - Prevents update checks that cause startup delays
2. **Disable telemetry**: `"telemetry.telemetryLevel": "off"` - Stops analytics transmission
3. **Disable extension auto-updates**: `"extensions.autoUpdate": false` - Prevents marketplace checks
4. **Disable git auto-fetch**: `"git.autofetch": false` - Stops automatic remote fetches
5. **Enable aggressive auto-save**: `"files.autoSave": "afterDelay"` with `"files.autoSaveDelay": 500` (or ≤1000ms)

## Workflow

1. Open VSCode Settings (File → Preferences → Settings or Ctrl+,)
2. Search for each setting by name (e.g., "update.mode")
3. Modify the setting value as specified above
4. Alternatively, edit settings.json directly (click {} icon in Settings UI)
5. Save changes (auto-saved by VSCode)

## Verification

Verifier parses settings.json and checks:
- ✅ Update mode is "none" or "manual"
- ✅ Telemetry level is "off"
- ✅ Extension auto-update is disabled (false)
- ✅ Git auto-fetch is disabled (false)
- ✅ Auto-save is enabled with appropriate mode
- ✅ Auto-save delay is ≤ 1000ms (bonus points)

**Pass Threshold**: 70% (at least 4 out of 5 critical settings correct)

## Why This Matters

Without proper offline configuration:
- VSCode freezes for 30+ seconds on startup checking for updates
- Git operations hang waiting for remote fetch timeouts
- Extension marketplace checks cause UI delays
- Telemetry transmission attempts waste battery
- Unsaved work is lost if battery dies unexpectedly

With offline configuration:
- VSCode starts instantly
- All local operations work smoothly
- Battery life is conserved
- Work is auto-saved every second
- Productive coding anywhere, anytime