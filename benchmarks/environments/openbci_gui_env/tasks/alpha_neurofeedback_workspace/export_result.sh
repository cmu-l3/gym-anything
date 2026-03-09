#!/bin/bash
echo "=== Exporting alpha_neurofeedback_workspace Result ==="

source /workspace/utils/openbci_utils.sh || true

TASK_NAME="alpha_neurofeedback_workspace"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
SCREENSHOTS_DIR="/home/ga/Documents/OpenBCI_GUI/Screenshots"

# Take final screenshot
take_screenshot /tmp/${TASK_NAME}_final_screenshot.png

# Read baseline values
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SCREENSHOT_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")

echo "Task start timestamp: $TASK_START"
echo "Initial screenshot count: $INITIAL_SCREENSHOT_COUNT"

# Count current screenshots
CURRENT_SCREENSHOT_COUNT=$(count_screenshots)
NEW_SCREENSHOTS=$((CURRENT_SCREENSHOT_COUNT - INITIAL_SCREENSHOT_COUNT))
echo "Current screenshot count: $CURRENT_SCREENSHOT_COUNT (new: $NEW_SCREENSHOTS)"

# Find and parse the newest settings JSON file that was created/modified after task start
python3 << PYEOF > /tmp/${TASK_NAME}_settings_analysis.json
import json, os, glob, time, sys

settings_dir = "$SETTINGS_DIR"
task_start = int("$TASK_START") if "$TASK_START".strip().isdigit() else 0

analysis = {
    "settings_file_found": False,
    "settings_newer_than_task": False,
    "settings_path": None,
    "settings_mtime": 0,
    "expert_mode_enabled": False,
    "bandpass_low_hz": None,
    "bandpass_high_hz": None,
    "notch_hz": None,
    "widgets_found": [],
    "panel_count": None,
    "channels_active_count": None,
    "channels_inactive_count": None,
    "parse_error": None,
    "raw_keys": []
}

try:
    settings_files = glob.glob(os.path.join(settings_dir, "*.json"))
    # Also try .txt files (OpenBCI sometimes saves as .txt)
    settings_files += glob.glob(os.path.join(settings_dir, "*.txt"))
    settings_files.sort(key=os.path.getmtime, reverse=True)

    if settings_files:
        newest = settings_files[0]
        mtime = int(os.path.getmtime(newest))
        analysis["settings_file_found"] = True
        analysis["settings_path"] = newest
        analysis["settings_mtime"] = mtime
        analysis["settings_newer_than_task"] = (mtime > task_start)

        with open(newest, "r", encoding="utf-8", errors="replace") as f:
            raw = f.read()

        # Try JSON parse
        try:
            settings = json.loads(raw)
            analysis["raw_keys"] = list(settings.keys())[:20]

            # --- Expert Mode ---
            # Try multiple known key patterns across OpenBCI GUI versions
            for key in ["expertModeEnabled", "expertMode", "isExpertMode",
                        "expert_mode_enabled", "expertModeIsActive"]:
                val = settings.get(key)
                if val is not None:
                    analysis["expert_mode_enabled"] = bool(val)
                    break
            # Also check nested structures
            if not analysis["expert_mode_enabled"]:
                for sub in settings.values():
                    if isinstance(sub, dict):
                        for key in ["expertModeEnabled", "expertMode", "isExpertMode"]:
                            val = sub.get(key)
                            if val is not None:
                                analysis["expert_mode_enabled"] = bool(val)
                                break

            # --- Bandpass Filter ---
            for low_key in ["bandpassLowCut", "bp_lowCut", "lowerBandpass",
                            "bandpass_low", "bandpassLow", "bpLow", "bp_low_cut",
                            "bpLowCut", "bandpassLowerBound"]:
                val = settings.get(low_key)
                if val is not None:
                    try:
                        analysis["bandpass_low_hz"] = float(val)
                        break
                    except (ValueError, TypeError):
                        pass
            for high_key in ["bandpassHighCut", "bp_highCut", "upperBandpass",
                             "bandpass_high", "bandpassHigh", "bpHigh", "bp_high_cut",
                             "bpHighCut", "bandpassUpperBound"]:
                val = settings.get(high_key)
                if val is not None:
                    try:
                        analysis["bandpass_high_hz"] = float(val)
                        break
                    except (ValueError, TypeError):
                        pass

            # --- Notch ---
            for notch_key in ["notchFilterFreq", "notchFreq", "notch_hz", "notchHz",
                              "notchFilter", "notch_frequency"]:
                val = settings.get(notch_key)
                if val is not None:
                    try:
                        analysis["notch_hz"] = float(val)
                        break
                    except (ValueError, TypeError):
                        pass

            # --- Widgets ---
            # Search entire JSON for widget names as string values
            raw_lower = raw.lower()
            widget_names = [
                "Time Series", "FFT Plot", "Band Power", "Focus",
                "Accelerometer", "Head Plot", "EMG", "Networking",
                "Signal Statistics", "Custom Widget", "Pulse Oximetry"
            ]
            found_widgets = []
            for w in widget_names:
                if w.lower() in raw_lower:
                    found_widgets.append(w)
            analysis["widgets_found"] = found_widgets

            # --- Panel / Layout ---
            for layout_key in ["currentLayout", "layout", "layoutIndex",
                               "numWidgets", "panelCount", "numColumns",
                               "layoutInt", "layoutNum"]:
                val = settings.get(layout_key)
                if val is not None:
                    try:
                        analysis["panel_count"] = int(val)
                        break
                    except (ValueError, TypeError):
                        pass

            # --- Channels ---
            # Try to count active/inactive channels
            chan_active = 0
            chan_inactive = 0
            for key in ["channelSettings", "channels", "channelStates"]:
                ch_list = settings.get(key)
                if isinstance(ch_list, list):
                    for ch in ch_list:
                        if isinstance(ch, dict):
                            active = ch.get("isActive", ch.get("active", ch.get("enabled", None)))
                            if active is True:
                                chan_active += 1
                            elif active is False:
                                chan_inactive += 1
                    if chan_active + chan_inactive > 0:
                        analysis["channels_active_count"] = chan_active
                        analysis["channels_inactive_count"] = chan_inactive
                        break

        except json.JSONDecodeError as e:
            analysis["parse_error"] = f"JSON parse error: {e}"
            # Still try to grep for widget names in raw content
            raw_lower = raw.lower()
            widget_names = ["time series", "fft plot", "band power", "focus",
                            "accelerometer", "head plot"]
            analysis["widgets_found"] = [w for w in ["Time Series", "FFT Plot",
                "Band Power", "Focus", "Accelerometer", "Head Plot"]
                if w.lower() in raw_lower]

            # Grep for filter values
            import re
            # Look for numbers near bandpass-related keywords
            bp_match = re.search(r'(?i)bandpass.{0,30}?(\d+\.?\d*).{0,10}?(\d+\.?\d*)', raw)
            if bp_match:
                try:
                    analysis["bandpass_low_hz"] = float(bp_match.group(1))
                    analysis["bandpass_high_hz"] = float(bp_match.group(2))
                except (ValueError, IndexError):
                    pass

except Exception as e:
    analysis["parse_error"] = str(e)

print(json.dumps(analysis, indent=2))
PYEOF

echo "Settings analysis:"
cat /tmp/${TASK_NAME}_settings_analysis.json

# Build final result JSON
SETTINGS_NEWER=$(python3 -c "import json; d=json.load(open('/tmp/${TASK_NAME}_settings_analysis.json')); print(str(d.get('settings_newer_than_task', False)).lower())" 2>/dev/null || echo "false")
SETTINGS_FOUND=$(python3 -c "import json; d=json.load(open('/tmp/${TASK_NAME}_settings_analysis.json')); print(str(d.get('settings_file_found', False)).lower())" 2>/dev/null || echo "false")

cat > "$RESULT_FILE" << EOF
{
    "task": "$TASK_NAME",
    "task_start": $TASK_START,
    "initial_screenshot_count": $INITIAL_SCREENSHOT_COUNT,
    "current_screenshot_count": $CURRENT_SCREENSHOT_COUNT,
    "new_screenshots": $NEW_SCREENSHOTS,
    "settings_file_found": $SETTINGS_FOUND,
    "settings_newer_than_task": $SETTINGS_NEWER,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Merge settings analysis into result
python3 << MERGEEOF
import json
result = json.load(open("$RESULT_FILE"))
try:
    analysis = json.load(open("/tmp/${TASK_NAME}_settings_analysis.json"))
    result["settings_analysis"] = analysis
except Exception as e:
    result["settings_analysis"] = {"error": str(e)}
with open("$RESULT_FILE", "w") as f:
    json.dump(result, f, indent=2)
print("Result JSON written.")
MERGEEOF

echo "Result file:"
cat "$RESULT_FILE"

echo "=== Export Complete ==="
