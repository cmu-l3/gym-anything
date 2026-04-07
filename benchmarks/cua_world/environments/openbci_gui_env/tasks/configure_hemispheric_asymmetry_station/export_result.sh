#!/bin/bash
echo "=== Exporting configure_hemispheric_asymmetry_station results ==="

source /workspace/utils/openbci_utils.sh || true

TASK_NAME="configure_hemispheric_asymmetry_station"
RESULT_FILE="/tmp/task_result.json"
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
REPORT_FILE="/home/ga/Documents/asymmetry_station_report.txt"

# Capture final state screenshot
take_screenshot /tmp/${TASK_NAME}_final_screenshot.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- Screenshot count ---
INITIAL_SCREENSHOT_COUNT=$(cat /tmp/hemispheric_initial_screenshot_count 2>/dev/null || echo "0")
CURRENT_SCREENSHOT_COUNT=$(count_screenshots)
NEW_SCREENSHOTS=$((CURRENT_SCREENSHOT_COUNT - INITIAL_SCREENSHOT_COUNT))

# --- Check for new recordings ---
NEW_RECORDING_FOUND="false"
NEW_RECORDING_SIZE=0
if [ -d "$RECORDINGS_DIR" ]; then
    while IFS= read -r recfile; do
        if [ -f "$recfile" ]; then
            FILE_TIME=$(stat -c %Y "$recfile" 2>/dev/null || echo "0")
            if [ "$FILE_TIME" -gt "$TASK_START" ]; then
                NEW_RECORDING_FOUND="true"
                FSIZE=$(stat -c %s "$recfile" 2>/dev/null || echo "0")
                if [ "$FSIZE" -gt "$NEW_RECORDING_SIZE" ]; then
                    NEW_RECORDING_SIZE=$FSIZE
                fi
            fi
        fi
    done < <(find "$RECORDINGS_DIR" -maxdepth 2 \( -name "*.txt" -o -name "*.csv" -o -name "*.bdf" \) -newer /tmp/task_start_time.txt 2>/dev/null)
fi

# --- Check report file ---
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_HAS_LEFT="false"
REPORT_HAS_RIGHT="false"
REPORT_HAS_FILTER="false"
REPORT_HAS_STREAM="false"
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" 2>/dev/null | head -c 2000)

    if echo "$REPORT_CONTENT" | grep -iqE "(CH1|CH3|CH5|CH7|channel.?1|channel.?3|channel.?5|channel.?7|left.?hemi|Fp1|C3|P7|O1)"; then
        REPORT_HAS_LEFT="true"
    fi
    if echo "$REPORT_CONTENT" | grep -iqE "(CH2|CH4|CH6|CH8|channel.?2|channel.?4|channel.?6|channel.?8|right.?hemi|Fp2|C4|P8|O2)"; then
        REPORT_HAS_RIGHT="true"
    fi
    if echo "$REPORT_CONTENT" | grep -iqE "(bandpass|1.?[-_].?40|notch|60.?Hz|filter)"; then
        REPORT_HAS_FILTER="true"
    fi
    if echo "$REPORT_CONTENT" | grep -iqE "(Asymmetry_Monitor|LSL|stream)"; then
        REPORT_HAS_STREAM="true"
    fi
fi

# --- Parse settings file ---
python3 << 'PYEOF' > /tmp/${TASK_NAME}_settings_analysis.json
import json, os, glob, re

settings_dir = "/home/ga/Documents/OpenBCI_GUI/Settings"
task_start_file = "/tmp/task_start_time.txt"
task_start = 0
if os.path.exists(task_start_file):
    try:
        task_start = int(open(task_start_file).read().strip())
    except:
        pass

analysis = {
    "settings_file_found": False,
    "settings_newer_than_task": False,
    "expert_mode_enabled": False,
    "bandpass_low_hz": None,
    "bandpass_high_hz": None,
    "notch_hz": None,
    "widgets_found": [],
    "band_power_count": 0,
    "panel_count": None,
}

try:
    settings_files = glob.glob(os.path.join(settings_dir, "*.json"))
    settings_files += glob.glob(os.path.join(settings_dir, "*.txt"))
    settings_files.sort(key=os.path.getmtime, reverse=True)

    if settings_files:
        newest = settings_files[0]
        mtime = int(os.path.getmtime(newest))
        analysis["settings_file_found"] = True
        analysis["settings_newer_than_task"] = (mtime > task_start)

        with open(newest, "r", encoding="utf-8", errors="replace") as f:
            raw = f.read()

        raw_lower = raw.lower()

        # Count Band Power occurrences (case-insensitive)
        analysis["band_power_count"] = len(re.findall(r'band\s*power', raw_lower))

        # Widget detection
        all_widgets = ["Time Series", "FFT Plot", "Band Power", "Head Plot",
                       "Networking", "Focus", "Accelerometer", "EMG",
                       "Spectrogram", "Pulse"]
        analysis["widgets_found"] = [w for w in all_widgets if w.lower() in raw_lower]

        try:
            settings = json.loads(raw)

            # Bandpass
            for key in ["bandpassLowCut", "bp_lowCut", "bandpass_low",
                        "bandpassLow", "bpLow", "lowerBandpass"]:
                val = settings.get(key)
                if val is not None:
                    try:
                        analysis["bandpass_low_hz"] = float(val)
                        break
                    except (ValueError, TypeError):
                        pass
            for key in ["bandpassHighCut", "bp_highCut", "bandpass_high",
                        "bandpassHigh", "bpHigh", "upperBandpass"]:
                val = settings.get(key)
                if val is not None:
                    try:
                        analysis["bandpass_high_hz"] = float(val)
                        break
                    except (ValueError, TypeError):
                        pass

            # Notch
            for key in ["notchFilterFreq", "notchFreq", "notch_hz",
                        "notchHz", "notchFilter", "notch_frequency"]:
                val = settings.get(key)
                if val is not None:
                    try:
                        analysis["notch_hz"] = float(val)
                        break
                    except (ValueError, TypeError):
                        pass

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

            # Layout / panel count
            for key in ["currentLayout", "layout", "layoutIndex",
                        "numWidgets", "panelCount", "layoutNum"]:
                val = settings.get(key)
                if val is not None:
                    try:
                        analysis["panel_count"] = int(val)
                        break
                    except (ValueError, TypeError):
                        pass
        except json.JSONDecodeError:
            # Fallback: regex-based extraction from raw text
            notch_match = re.search(r'(?i)notch.{0,30}?(\d+\.?\d*)', raw)
            if notch_match:
                try:
                    analysis["notch_hz"] = float(notch_match.group(1))
                except:
                    pass
            if re.search(r'(?i)expert.{0,20}true', raw):
                analysis["expert_mode_enabled"] = True
except Exception as e:
    analysis["parse_error"] = str(e)

print(json.dumps(analysis, indent=2))
PYEOF

echo "Settings analysis:"
cat /tmp/${TASK_NAME}_settings_analysis.json

# --- Check if app is running ---
APP_RUNNING="false"
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    APP_RUNNING="true"
fi

# --- Merge everything into result JSON ---
TEMP_JSON=$(mktemp /tmp/result_hemispheric.XXXXXX.json)

# Build the JSON directly in bash to avoid true/false Python NameError
cat > "$TEMP_JSON" << EOF
{
    "task": "$TASK_NAME",
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "new_screenshots": $NEW_SCREENSHOTS,
    "new_recording_found": $NEW_RECORDING_FOUND,
    "new_recording_max_size": $NEW_RECORDING_SIZE,
    "report_exists": $REPORT_EXISTS,
    "report_has_left_channels": $REPORT_HAS_LEFT,
    "report_has_right_channels": $REPORT_HAS_RIGHT,
    "report_has_filter_info": $REPORT_HAS_FILTER,
    "report_has_stream_info": $REPORT_HAS_STREAM,
    "final_screenshot_path": "/tmp/${TASK_NAME}_final_screenshot.png"
}
EOF

# Merge settings analysis into the result JSON
python3 << MERGEEOF
import json
try:
    result = json.load(open("$TEMP_JSON"))
except Exception as e:
    result = {"error": f"Failed to load base result: {e}"}

try:
    analysis = json.load(open("/tmp/${TASK_NAME}_settings_analysis.json"))
    result["settings_analysis"] = analysis
except Exception as e:
    result["settings_analysis"] = {"error": str(e)}

with open("$TEMP_JSON", "w") as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2))
MERGEEOF

# Move to final location with permission handling
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to $RESULT_FILE"
echo "=== Export complete ==="
