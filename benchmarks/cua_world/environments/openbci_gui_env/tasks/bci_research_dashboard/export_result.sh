#!/bin/bash
echo "=== Exporting bci_research_dashboard Result ==="

source /workspace/utils/openbci_utils.sh || true

TASK_NAME="bci_research_dashboard"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"

take_screenshot /tmp/${TASK_NAME}_final_screenshot.png

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
INITIAL_SCREENSHOT_COUNT=$(cat /tmp/${TASK_NAME}_initial_screenshot_count 2>/dev/null || echo "0")
CURRENT_SCREENSHOT_COUNT=$(count_screenshots)
NEW_SCREENSHOTS=$((CURRENT_SCREENSHOT_COUNT - INITIAL_SCREENSHOT_COUNT))

echo "Task start: $TASK_START"
echo "New screenshots: $NEW_SCREENSHOTS"

# Parse settings file
python3 << PYEOF > /tmp/${TASK_NAME}_settings_analysis.json
import json, os, glob, re

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
    "parse_error": None,
    "raw_keys": []
}

# All required widgets for this task
REQUIRED_WIDGETS = ["Time Series", "FFT Plot", "Band Power", "Accelerometer", "Focus", "Head Plot"]

try:
    settings_files = glob.glob(os.path.join(settings_dir, "*.json"))
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

        try:
            settings = json.loads(raw)
            analysis["raw_keys"] = list(settings.keys())[:20]

            # Expert Mode
            for key in ["expertModeEnabled", "expertMode", "isExpertMode",
                        "expert_mode_enabled", "expertModeIsActive"]:
                val = settings.get(key)
                if val is not None:
                    analysis["expert_mode_enabled"] = bool(val)
                    break
            if not analysis["expert_mode_enabled"]:
                for sub in settings.values():
                    if isinstance(sub, dict):
                        for key in ["expertModeEnabled", "expertMode"]:
                            val = sub.get(key)
                            if val is not None:
                                analysis["expert_mode_enabled"] = bool(val)
                                break

            # Bandpass
            for low_key in ["bandpassLowCut", "bp_lowCut", "lowerBandpass",
                            "bandpass_low", "bandpassLow", "bpLow"]:
                val = settings.get(low_key)
                if val is not None:
                    try:
                        analysis["bandpass_low_hz"] = float(val)
                        break
                    except (ValueError, TypeError):
                        pass

            for high_key in ["bandpassHighCut", "bp_highCut", "upperBandpass",
                             "bandpass_high", "bandpassHigh", "bpHigh"]:
                val = settings.get(high_key)
                if val is not None:
                    try:
                        analysis["bandpass_high_hz"] = float(val)
                        break
                    except (ValueError, TypeError):
                        pass

            # Notch
            for notch_key in ["notchFilterFreq", "notchFreq", "notch_hz", "notchHz",
                              "notchFilter", "notch_frequency", "notchFrequency"]:
                val = settings.get(notch_key)
                if val is not None:
                    try:
                        analysis["notch_hz"] = float(val)
                        break
                    except (ValueError, TypeError):
                        pass

            # Widgets — search raw JSON for all widget names
            raw_lower = raw.lower()
            all_widget_names = REQUIRED_WIDGETS + ["EMG", "Networking", "Signal Statistics",
                                                    "Custom Widget", "Pulse Oximetry"]
            analysis["widgets_found"] = [w for w in all_widget_names if w.lower() in raw_lower]

            # Panel count
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

        except json.JSONDecodeError as e:
            analysis["parse_error"] = f"JSON parse error: {e}"
            raw_lower = raw.lower()
            analysis["widgets_found"] = [w for w in REQUIRED_WIDGETS if w.lower() in raw_lower]

            # Try regex for notch
            notch_match = re.search(r'(?i)notch.{0,30}?(\d+\.?\d*)', raw)
            if notch_match:
                try:
                    analysis["notch_hz"] = float(notch_match.group(1))
                except (ValueError, IndexError):
                    pass

            # Expert mode
            if re.search(r'(?i)expert.{0,20}true', raw):
                analysis["expert_mode_enabled"] = True

except Exception as e:
    analysis["parse_error"] = str(e)

print(json.dumps(analysis, indent=2))
PYEOF

echo "Settings analysis:"
cat /tmp/${TASK_NAME}_settings_analysis.json

SETTINGS_FOUND=$(python3 -c "
import json
try:
    d = json.load(open('/tmp/${TASK_NAME}_settings_analysis.json'))
    print(str(d.get('settings_file_found', False)).lower())
except: print('false')
")
SETTINGS_NEWER=$(python3 -c "
import json
try:
    d = json.load(open('/tmp/${TASK_NAME}_settings_analysis.json'))
    print(str(d.get('settings_newer_than_task', False)).lower())
except: print('false')
")

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

echo "Result:"
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="
