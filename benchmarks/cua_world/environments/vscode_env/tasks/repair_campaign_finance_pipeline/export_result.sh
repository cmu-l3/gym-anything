#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting Campaign Finance Pipeline Result ==="

WORKSPACE_DIR="/home/ga/workspace/election_investigation"
RESULT_FILE="/tmp/campaign_finance_result.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Best-effort: focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

# ──────────────────────────────────────────────────────────
# Execute Agent's Code Against Hidden Ground Truth Dataset
# ──────────────────────────────────────────────────────────
echo "Running agent script against secret dataset..."
mkdir -p /tmp/secret_out
export FEC_DATA_PATH="/var/lib/app/ground_truth/secret_itcont.txt"
export FEC_OUT_DIR="/tmp/secret_out/"

cd "$WORKSPACE_DIR"
# Run as root so it can access the 700 hidden directory
python3 fec_analysis.py > /tmp/secret_run.log 2>&1 || true
RUN_EXIT_CODE=$?

# ──────────────────────────────────────────────────────────
# Collect Results
# ──────────────────────────────────────────────────────────
MONTHLY=""
if [ -f /tmp/secret_out/monthly_trends.csv ]; then
    MONTHLY=$(cat /tmp/secret_out/monthly_trends.csv)
fi

FLAGGED=""
if [ -f /tmp/secret_out/flagged_violators.csv ]; then
    FLAGGED=$(cat /tmp/secret_out/flagged_violators.csv)
fi

SCRIPT_CONTENT=""
if [ -f "$WORKSPACE_DIR/fec_analysis.py" ]; then
    SCRIPT_CONTENT=$(cat "$WORKSPACE_DIR/fec_analysis.py")
fi

# Escape quotes and newlines for JSON payload
python3 << PYEXPORT
import json

data = {
    "run_exit_code": $RUN_EXIT_CODE,
    "secret_monthly_trends": """$MONTHLY""",
    "secret_flagged_violators": """$FLAGGED""",
    "script_content": """$SCRIPT_CONTENT""",
    "task_start": $TASK_START,
    "task_end": $TASK_END
}

with open("$RESULT_FILE", "w", encoding="utf-8") as out:
    json.dump(data, out, indent=2)
PYEXPORT

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result JSON saved to $RESULT_FILE"
echo "=== Export Complete ==="