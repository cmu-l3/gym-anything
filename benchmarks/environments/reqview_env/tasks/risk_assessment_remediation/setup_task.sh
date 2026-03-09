#!/bin/bash
echo "=== Setting up risk_assessment_remediation task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project for this task
PROJECT_PATH=$(setup_task_project "risk_assessment")
echo "Task project path: $PROJECT_PATH"

# Zero out risk scores on CAUSE entries and clear responsibility/targetDate on ACT entries.
# Also remove existing mitigation link from SRS-160 to RISKS-26 (if it exists)
# so the agent must create a new mitigation link to RISKS-44.
python3 << 'PYEOF'
import json, sys

risks_path = "$PROJECT_PATH/documents/RISKS.json"
srs_path = "$PROJECT_PATH/documents/SRS.json"

# Corrupt RISKS entries
try:
    with open(risks_path) as f:
        risks = json.load(f)
except Exception as e:
    print(f"ERROR: Could not read RISKS.json: {e}", file=sys.stderr)
    sys.exit(1)

def corrupt_risks(items):
    for item in items:
        iid = str(item.get('id', ''))

        # Zero out severity/detectability/probability on CAUSE entries
        if iid == '40':
            item['severity'] = 0
            item['detectability'] = 0
            item['probability'] = 0
            print(f"Zeroed RISKS-40 (CAUSE) scores")
        elif iid == '44':
            item['severity'] = 0
            item['detectability'] = 0
            item['probability'] = 0
            print(f"Zeroed RISKS-44 (CAUSE) scores")

        # Clear responsibility and targetDate on ACT entries
        elif iid == '26':
            item['responsibility'] = ''
            item['targetDate'] = ''
            print(f"Cleared RISKS-26 (ACT) responsibility and targetDate")
        elif iid == '45':
            item['responsibility'] = ''
            item['targetDate'] = ''
            print(f"Cleared RISKS-45 (ACT) responsibility and targetDate")

        if 'children' in item:
            corrupt_risks(item['children'])

corrupt_risks(risks.get('data', []))

with open(risks_path, 'w') as f:
    json.dump(risks, f, indent=2)
print("RISKS corruption complete")

# Remove existing mitigation link from SRS-160 to RISKS-26
# (keep any other links on SRS-160 intact)
try:
    with open(srs_path) as f:
        srs = json.load(f)
except Exception as e:
    print(f"ERROR: Could not read SRS.json: {e}", file=sys.stderr)
    sys.exit(1)

def remove_mitigation_link(items, target_srs_id, risks_target):
    for item in items:
        if str(item.get('id', '')) == target_srs_id:
            links = item.get('links', {})
            mit = links.get('mitigation', [])
            if risks_target in mit:
                mit.remove(risks_target)
                if not mit:
                    del links['mitigation']
                print(f"Removed mitigation link from SRS-{target_srs_id} to {risks_target}")
            return True
        if 'children' in item:
            if remove_mitigation_link(item['children'], target_srs_id, risks_target):
                return True
    return False

# Don't remove existing link — agent needs to ADD a link to RISKS-44 (not RISKS-26)
# SRS-160 already has a mitigation link to RISKS-26. Agent needs to add RISKS-44.

with open(srs_path, 'w') as f:
    json.dump(srs, f, indent=2)
print("SRS preparation complete")
PYEOF

date +%s > /tmp/risk_assessment_start_ts

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 3

# Dismiss any dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the RISKS document in the project tree
# RISKS is in L1: Stakeholders group, below ASVS
echo "Opening RISKS document from project tree..."
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 114 375 click 1 2>/dev/null || true
sleep 4
echo "RISKS document opened"

take_screenshot /tmp/risk_assessment_start.png
echo "=== risk_assessment_remediation task setup complete ==="
