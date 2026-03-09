#!/bin/bash
set -e

echo "=== Exporting configure_scqc_parameters_scconfig result ==="

source /workspace/scripts/task_utils.sh

TASK="configure_scqc_parameters_scconfig"
TASK_START=$(cat "/tmp/${TASK}_start_ts" 2>/dev/null || echo "0")
SCQC_CFG="$SEISCOMP_ROOT/etc/scqc.cfg"

take_screenshot "/tmp/${TASK}_end.png"

CONFIG_EXISTS=false
CONFIG_IS_NEW=false
REPORT_INTERVAL=""
REPORT_BUFFER=""
STREAM_MASK=""
REALTIME_BUFFER=""

if [ -f "$SCQC_CFG" ]; then
    CONFIG_EXISTS=true
    CONFIG_MTIME=$(stat -c %Y "$SCQC_CFG" 2>/dev/null || echo "0")
    if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
        CONFIG_IS_NEW=true
    fi

    PARAM_JSON=$(python3 <<'PY'
import json
import os

cfg_path = os.path.expandvars("/home/ga/seiscomp/etc/scqc.cfg")
params = {}
try:
    with open(cfg_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            params[key.strip()] = value.strip().strip('"').strip("'")
except Exception as exc:
    params["error"] = str(exc)

print(json.dumps(params))
PY
)

    REPORT_INTERVAL=$(echo "$PARAM_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('report.interval',''))" 2>/dev/null || echo "")
    REPORT_BUFFER=$(echo "$PARAM_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('report.buffer',''))" 2>/dev/null || echo "")
    STREAM_MASK=$(echo "$PARAM_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('streamMask',''))" 2>/dev/null || echo "")
    REALTIME_BUFFER=$(echo "$PARAM_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('realtime.buffer',''))" 2>/dev/null || echo "")
fi

cat > "/tmp/${TASK}_result.json" <<EOF
{
  "config_exists": ${CONFIG_EXISTS},
  "config_is_new": ${CONFIG_IS_NEW},
  "report_interval": "${REPORT_INTERVAL}",
  "report_buffer": "${REPORT_BUFFER}",
  "stream_mask": "${STREAM_MASK}",
  "realtime_buffer": "${REALTIME_BUFFER}"
}
EOF

chmod 666 "/tmp/${TASK}_result.json"
cat "/tmp/${TASK}_result.json"
echo "=== Export complete ==="
