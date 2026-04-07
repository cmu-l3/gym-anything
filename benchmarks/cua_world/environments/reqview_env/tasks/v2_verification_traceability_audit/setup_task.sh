#!/bin/bash
echo "=== Setting up v2_verification_traceability_audit task ==="

source /workspace/scripts/task_utils.sh

# Kill any running ReqView
pkill -f "reqview" 2>/dev/null || true
sleep 2

# Set up a fresh copy of the example project
PROJECT_PATH=$(setup_task_project "v2_verification_audit")
echo "Task project path: $PROJECT_PATH"

# Delete any stale outputs
rm -f /tmp/v2_audit_start_ts /tmp/v2_audit_end_ts
rm -f /tmp/v2_audit_start.png /tmp/v2_audit_end.png
rm -f /tmp/v2_audit_ground_truth.json
rm -f /tmp/srs_result.json /tmp/tests_result.json

# Modify project data:
# 1. Add 'release' attribute and 'Blocked' status value to SRS
# 2. Tag 15 SRS items as v2.0 with specific priorities
# 3. Corrupt 5 verification links in TESTS (3 mismatches + 2 removals)
python3 << 'PYEOF'
import json
import sys

# Use hardcoded paths (single-quoted heredoc does not expand bash variables)
srs_path = "/home/ga/Documents/ReqView/v2_verification_audit_project/documents/SRS.json"
tests_path = "/home/ga/Documents/ReqView/v2_verification_audit_project/documents/TESTS.json"

# ============================================================
# STEP 1: Modify SRS document
# ============================================================
try:
    with open(srs_path) as f:
        srs = json.load(f)
except Exception as e:
    print(f"ERROR: Could not read SRS.json: {e}", file=sys.stderr)
    sys.exit(1)

# Add 'release' custom attribute
srs['attributes']['release'] = {
    "name": "Release",
    "type": "enum",
    "values": [
        {"key": "v1.0"},
        {"key": "v2.0"},
        {"key": "Unassigned"}
    ]
}

# Add 'Blocked' to status enum values
status_attr = srs['attributes']['status']
existing_keys = [v.get('key') for v in status_attr['values']]
if 'Blocked' not in existing_keys:
    status_attr['values'].append({"key": "Blocked"})
    print("Added 'Blocked' to SRS status enum")

# Define v2.0 items and their priorities
# These are SRS items that have existing verification links from TESTS items
v2_items = {
    # Verified by TESTS-4 "Open Local File": SRS-56
    "56": "H",
    # Verified by TESTS-5 "Save Local File": SRS-59
    "59": "M",
    # Verified by TESTS-21 "Create Requirements": SRS-53, 106, 107, 114, 115, 116
    "53": "H",
    "106": "H",
    "107": "M",
    "114": "M",
    "115": "L",
    "116": "L",
    # Verified by TESTS-22 "Restructure Requirement": SRS-108, 109, 110
    "108": "H",
    "109": "L",
    "110": "M",
    # Verified by TESTS-29 "Custom Attributes": SRS-119, 120
    "119": "M",
    "120": "L",
    # Verified by TESTS-30 "Discussion": SRS-132, 96
    "132": "M",
    "96": "M",
}

def tag_v2_items(items):
    """Recursively tag SRS items as v2.0 and set their priorities."""
    count = 0
    for item in items:
        iid = str(item.get('id', ''))
        if iid in v2_items:
            item['release'] = 'v2.0'
            item['priority'] = v2_items[iid]
            item['status'] = 'Approved'
            count += 1
            print(f"Tagged SRS-{iid} as v2.0 (Priority={v2_items[iid]}, Status=Approved)")
        if 'children' in item:
            count += tag_v2_items(item['children'])
    return count

tagged = tag_v2_items(srs.get('data', []))
print(f"Total SRS items tagged v2.0: {tagged}")

with open(srs_path, 'w') as f:
    json.dump(srs, f, indent=2)
print("SRS modifications complete")

# ============================================================
# STEP 2: Corrupt verification links in TESTS document
# ============================================================
try:
    with open(tests_path) as f:
        tests = json.load(f)
except Exception as e:
    print(f"ERROR: Could not read TESTS.json: {e}", file=sys.stderr)
    sys.exit(1)

# Corruption plan:
# Mismatch 1: Move SRS-56 from TESTS-4 ("Open Local File") to TESTS-30 ("Discussion")
#   -> SRS-56 (file opening) will appear verified by discussion test = WRONG
# Mismatch 2: Move SRS-119 from TESTS-29 ("Custom Attributes") to TESTS-5 ("Save Local File")
#   -> SRS-119 (custom attrs) will appear verified by file save test = WRONG
# Missing 1:  Remove SRS-108 from TESTS-22 ("Restructure Requirement")
#   -> SRS-108 will have no verification link
# Mismatch 3: Move SRS-96 from TESTS-30 ("Discussion") to TESTS-22 ("Restructure Requirement")
#   -> SRS-96 (discussion) will appear verified by restructure test = WRONG
# Missing 2:  Remove SRS-106 from TESTS-21 ("Create Requirements")
#   -> SRS-106 will have no verification link

def corrupt_test_links(items):
    """Apply all link corruptions to TESTS items."""
    for item in items:
        iid = str(item.get('id', ''))
        links = item.get('links', {})
        ver = links.get('verification', [])

        if iid == '4':
            # TESTS-4 "Open Local File": remove SRS-56
            if 'SRS-56' in ver:
                ver.remove('SRS-56')
                print(f"CORRUPTION: Removed SRS-56 from TESTS-4")

        elif iid == '5':
            # TESTS-5 "Save Local File": add SRS-119 (mismatch)
            if 'SRS-119' not in ver:
                ver.append('SRS-119')
                print(f"CORRUPTION: Added SRS-119 to TESTS-5 (MISMATCH)")

        elif iid == '21':
            # TESTS-21 "Create Requirements": remove SRS-106
            if 'SRS-106' in ver:
                ver.remove('SRS-106')
                print(f"CORRUPTION: Removed SRS-106 from TESTS-21")

        elif iid == '22':
            # TESTS-22 "Restructure Requirement": remove SRS-108, add SRS-96 (mismatch)
            if 'SRS-108' in ver:
                ver.remove('SRS-108')
                print(f"CORRUPTION: Removed SRS-108 from TESTS-22")
            if 'SRS-96' not in ver:
                ver.append('SRS-96')
                print(f"CORRUPTION: Added SRS-96 to TESTS-22 (MISMATCH)")

        elif iid == '29':
            # TESTS-29 "Custom Attributes": remove SRS-119
            if 'SRS-119' in ver:
                ver.remove('SRS-119')
                print(f"CORRUPTION: Removed SRS-119 from TESTS-29")

        elif iid == '30':
            # TESTS-30 "Discussion": remove SRS-96, add SRS-56 (mismatch)
            if 'SRS-96' in ver:
                ver.remove('SRS-96')
                print(f"CORRUPTION: Removed SRS-96 from TESTS-30")
            if 'SRS-56' not in ver:
                ver.append('SRS-56')
                print(f"CORRUPTION: Added SRS-56 to TESTS-30 (MISMATCH)")

        # Update links in item
        if ver:
            links['verification'] = ver
        elif 'verification' in links:
            del links['verification']
        if links:
            item['links'] = links

        if 'children' in item:
            corrupt_test_links(item['children'])

corrupt_test_links(tests.get('data', []))

with open(tests_path, 'w') as f:
    json.dump(tests, f, indent=2)
print("TESTS link corruption complete")

# ============================================================
# STEP 3: Save ground truth for verifier reference
# ============================================================
ground_truth = {
    "corrupted_items": [
        {"srs_id": "56", "issue": "mismatch", "wrong_test_id": "30", "wrong_test_name": "Discussion", "correct_test_id": "4", "correct_test_name": "Open Local File"},
        {"srs_id": "119", "issue": "mismatch", "wrong_test_id": "5", "wrong_test_name": "Save Local File", "correct_test_id": "29", "correct_test_name": "Custom Attributes"},
        {"srs_id": "108", "issue": "missing", "correct_test_id": "22", "correct_test_name": "Restructure Requirement"},
        {"srs_id": "96", "issue": "mismatch", "wrong_test_id": "22", "wrong_test_name": "Restructure Requirement", "correct_test_id": "30", "correct_test_name": "Discussion"},
        {"srs_id": "106", "issue": "missing", "correct_test_id": "21", "correct_test_name": "Create Requirements"}
    ]
}
with open('/tmp/v2_audit_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)
print("Ground truth saved")
PYEOF

# Record task start time AFTER setup is complete
date +%s > /tmp/v2_audit_start_ts

# Launch ReqView with the project
launch_reqview_with_project "$PROJECT_PATH"

sleep 3

# Dismiss any dialogs
dismiss_dialogs

# Maximize window
maximize_window

# Open the SRS document in the project tree
open_srs_document

take_screenshot /tmp/v2_audit_start.png
echo "=== v2_verification_traceability_audit task setup complete ==="
