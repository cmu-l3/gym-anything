#!/bin/bash
echo "=== Exporting configure_scautopick_thresholds_scconfig result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
TASK="configure_scautopick_thresholds_scconfig"

TASK_START=$(cat /tmp/${TASK}_start_ts 2>/dev/null || echo "0")
SCAUTOPICK_CFG="$SEISCOMP_ROOT/etc/scautopick.cfg"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK}_end_screenshot.png 2>/dev/null || true

# Check if config file exists and was modified after task start
CONFIG_EXISTS=false
CONFIG_IS_NEW=false
FILTER_VALUE=""
TRIG_ON_VALUE=""
TRIG_OFF_VALUE=""
MIN_SNR_VALUE=""

if [ -f "$SCAUTOPICK_CFG" ]; then
    CONFIG_EXISTS=true
    CONFIG_MTIME=$(stat -c %Y "$SCAUTOPICK_CFG" 2>/dev/null || echo "0")
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_IS_NEW=true
    fi

    # Extract parameter values using Python for robust INI-style parsing
    # scautopick.cfg uses key = value format (no section headers)
    PARAM_JSON=$(python3 << 'PYEOF'
import os
import re
import json

cfg_path = os.path.expandvars("$SEISCOMP_ROOT/etc/scautopick.cfg")
params = {}
try:
    with open(cfg_path, "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("#") or "=" not in line:
                continue
            key, _, val = line.partition("=")
            params[key.strip()] = val.strip().strip('"').strip("'")
except Exception as e:
    params["error"] = str(e)

print(json.dumps(params))
PYEOF
2>/dev/null || echo "{}")

    FILTER_VALUE=$(echo "$PARAM_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('filter',''))" 2>/dev/null || echo "")
    TRIG_ON_VALUE=$(echo "$PARAM_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('thresholds.trigOn',''))" 2>/dev/null || echo "")
    TRIG_OFF_VALUE=$(echo "$PARAM_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('thresholds.trigOff',''))" 2>/dev/null || echo "")
    MIN_SNR_VALUE=$(echo "$PARAM_JSON" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('picker.AIC.minSNR',''))" 2>/dev/null || echo "")

    echo "Raw params found: $PARAM_JSON"
fi

echo "Config exists: $CONFIG_EXISTS"
echo "Config modified after task start: $CONFIG_IS_NEW"
echo "filter: $FILTER_VALUE"
echo "thresholds.trigOn: $TRIG_ON_VALUE"
echo "thresholds.trigOff: $TRIG_OFF_VALUE"
echo "picker.AIC.minSNR: $MIN_SNR_VALUE"

# Also copy the config file to /tmp for verifier to read directly
if [ -f "$SCAUTOPICK_CFG" ]; then
    cp "$SCAUTOPICK_CFG" /tmp/${TASK}_scautopick.cfg 2>/dev/null || true
fi

cat > /tmp/${TASK}_result.json << EOF
{
    "task": "$TASK",
    "task_start": $TASK_START,
    "config_exists": $CONFIG_EXISTS,
    "config_is_new": $CONFIG_IS_NEW,
    "filter": "${FILTER_VALUE}",
    "thresholds_trigOn": "${TRIG_ON_VALUE}",
    "thresholds_trigOff": "${TRIG_OFF_VALUE}",
    "picker_AIC_minSNR": "${MIN_SNR_VALUE}"
}
EOF

echo "Result written to /tmp/${TASK}_result.json"
cat /tmp/${TASK}_result.json
echo "=== Export complete ==="
