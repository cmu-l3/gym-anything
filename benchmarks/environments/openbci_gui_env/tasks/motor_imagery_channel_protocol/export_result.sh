#!/bin/bash
echo "=== Exporting motor_imagery_channel_protocol Result ==="

source /workspace/utils/openbci_utils.sh || true

TASK_NAME="motor_imagery_channel_protocol"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
SETTINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Settings"

take_screenshot /tmp/${TASK_NAME}_final_screenshot.png

TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
echo "Task start timestamp: $TASK_START"

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
    "bandpass_low_hz": None,
    "bandpass_high_hz": None,
    "notch_hz": None,
    "widgets_found": [],
    "channels_active_count": None,
    "channels_inactive_count": None,
    "channel_states": [],
    "parse_error": None,
    "raw_keys": []
}

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

            # Bandpass filter
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

            # Notch
            for notch_key in ["notchFilterFreq", "notchFreq", "notch_hz", "notchHz",
                              "notchFilter", "notch_frequency"]:
                val = settings.get(notch_key)
                if val is not None:
                    try:
                        analysis["notch_hz"] = float(val)
                        break
                    except (ValueError, TypeError):
                        pass

            # Widgets — search entire JSON text for widget name strings
            raw_lower = raw.lower()
            widget_names = ["Time Series", "FFT Plot", "Band Power", "Focus",
                            "Accelerometer", "Head Plot", "EMG", "Networking",
                            "Signal Statistics"]
            analysis["widgets_found"] = [w for w in widget_names if w.lower() in raw_lower]

            # Channel active/inactive states
            chan_active = 0
            chan_inactive = 0
            chan_states = []
            for key in ["channelSettings", "channels", "channelStates", "channelList"]:
                ch_list = settings.get(key)
                if isinstance(ch_list, list):
                    for i, ch in enumerate(ch_list):
                        if isinstance(ch, dict):
                            active = ch.get("isActive",
                                    ch.get("active",
                                    ch.get("enabled",
                                    ch.get("isEnabled", None))))
                            state = bool(active) if active is not None else None
                            chan_states.append({"channel": i + 1, "active": state})
                            if state is True:
                                chan_active += 1
                            elif state is False:
                                chan_inactive += 1
                    if chan_active + chan_inactive > 0:
                        analysis["channels_active_count"] = chan_active
                        analysis["channels_inactive_count"] = chan_inactive
                        analysis["channel_states"] = chan_states
                        break

            # Fallback: count "isActive" occurrences in raw JSON
            if analysis["channels_active_count"] is None:
                active_true_count = len(re.findall(r'"isActive"\s*:\s*true', raw, re.I))
                active_false_count = len(re.findall(r'"isActive"\s*:\s*false', raw, re.I))
                if active_true_count + active_false_count > 0:
                    analysis["channels_active_count"] = active_true_count
                    analysis["channels_inactive_count"] = active_false_count

        except json.JSONDecodeError as e:
            analysis["parse_error"] = f"JSON parse error: {e}"
            # Fallback: grep for widget names and channel states in raw
            raw_lower = raw.lower()
            analysis["widgets_found"] = [w for w in
                ["Time Series", "FFT Plot", "Band Power", "Focus",
                 "Accelerometer", "Head Plot"]
                if w.lower() in raw_lower]

            active_true = len(re.findall(r'(?i)isActive.{0,5}true', raw))
            active_false = len(re.findall(r'(?i)isActive.{0,5}false', raw))
            if active_true + active_false > 0:
                analysis["channels_active_count"] = active_true
                analysis["channels_inactive_count"] = active_false

            bp_match = re.search(
                r'(?i)(?:bandpass|filter).{0,50}?(\d+\.?\d*).{0,20}?(\d+\.?\d*)', raw)
            if bp_match:
                try:
                    v1 = float(bp_match.group(1))
                    v2 = float(bp_match.group(2))
                    analysis["bandpass_low_hz"] = min(v1, v2)
                    analysis["bandpass_high_hz"] = max(v1, v2)
                except (ValueError, IndexError):
                    pass

except Exception as e:
    analysis["parse_error"] = str(e)

print(json.dumps(analysis, indent=2))
PYEOF

echo "Settings analysis:"
cat /tmp/${TASK_NAME}_settings_analysis.json

SETTINGS_NEWER=$(python3 -c "
import json
try:
    d = json.load(open('/tmp/${TASK_NAME}_settings_analysis.json'))
    print(str(d.get('settings_newer_than_task', False)).lower())
except:
    print('false')
")
SETTINGS_FOUND=$(python3 -c "
import json
try:
    d = json.load(open('/tmp/${TASK_NAME}_settings_analysis.json'))
    print(str(d.get('settings_file_found', False)).lower())
except:
    print('false')
")

cat > "$RESULT_FILE" << EOF
{
    "task": "$TASK_NAME",
    "task_start": $TASK_START,
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
