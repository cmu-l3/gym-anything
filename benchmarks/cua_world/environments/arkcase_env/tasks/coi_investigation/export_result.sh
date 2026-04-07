#!/bin/bash
set -euo pipefail
echo "=== Exporting COI Investigation results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# ── Read ground truth ───────────────────────────────────────────────────────
GT_PATH="/root/validation/coi_ground_truth.json"
if [ ! -f "$GT_PATH" ]; then
    echo "ERROR: Ground truth file not found at $GT_PATH"
    cat > /tmp/task_result.json <<'EOF'
{"error": "Ground truth file missing", "export_timestamp": 0}
EOF
    exit 0
fi

TASK_START=$(python3 -c "import json; print(json.load(open('$GT_PATH'))['task_start_time'])" 2>/dev/null || echo "0")

# ── Check agent output file ─────────────────────────────────────────────────
REPORT_PATH="/home/ga/Documents/coi_report.json"
REPORT_EXISTS=false
REPORT_CREATED_DURING_TASK=false
REPORT_CONTENT=""
REPORT_SIZE=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS=true
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_MTIME=$(stat -c%Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ] 2>/dev/null; then
        REPORT_CREATED_DURING_TASK=true
    fi
    REPORT_CONTENT=$(cat "$REPORT_PATH" 2>/dev/null || echo "")
fi

# ── Query DB for new ethics review complaints ──────────────────────────────
# Find complaints created after the last Meridian/investigation case (i.e., during the task)
# by looking for titles containing "Ethics Review"
ETHICS_COMPLAINTS=$(kubectl exec -n arkcase arkcase-rdbms-0 -- \
    psql -U arkcase -d arkcase -t -A -c \
    "SELECT cm_complaint_number, cm_complaint_title, cm_complaint_priority, cm_complaint_details
     FROM acm_complaint
     WHERE LOWER(cm_complaint_title) LIKE '%ethics review%'
     ORDER BY cm_complaint_id;" 2>/dev/null || echo "")

# ── Build result JSON ──────────────────────────────────────────────────────
python3 <<PYEOF
import json, os

gt_path = "$GT_PATH"
report_path = "$REPORT_PATH"
report_exists = "$REPORT_EXISTS" == "true"
report_created = "$REPORT_CREATED_DURING_TASK" == "true"
report_size = int("$REPORT_SIZE")
task_start = int("$TASK_START")
ethics_raw = """$ETHICS_COMPLAINTS"""

# Parse ground truth
try:
    with open(gt_path) as f:
        gt = json.load(f)
except Exception as e:
    gt = {"error": str(e)}

# Parse agent report
agent_report = None
if report_exists:
    try:
        with open(report_path) as f:
            agent_report = json.load(f)
    except Exception as e:
        agent_report = {"parse_error": str(e)}

# Parse ethics complaints from DB
ethics_complaints = []
for line in ethics_raw.strip().split('\n'):
    if '|' in line:
        parts = line.split('|', 3)
        ethics_complaints.append({
            "number": parts[0].strip(),
            "title": parts[1].strip(),
            "priority": parts[2].strip(),
            "details": parts[3].strip() if len(parts) > 3 else ""
        })

result = {
    "report_exists": report_exists,
    "report_created_during_task": report_created,
    "report_size": report_size,
    "agent_report": agent_report,
    "ethics_complaints_found": len(ethics_complaints),
    "ethics_complaints": ethics_complaints,
    "ground_truth": gt,
    "export_timestamp": int(os.popen("date +%s").read().strip())
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Copy ground truth to /tmp for verifier access
cp "$GT_PATH" /tmp/coi_ground_truth.json 2>/dev/null || true
chmod 644 /tmp/coi_ground_truth.json 2>/dev/null || true

echo "=== Export complete ==="
