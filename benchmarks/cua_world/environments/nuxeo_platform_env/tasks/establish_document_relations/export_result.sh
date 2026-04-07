#!/bin/bash
echo "=== Exporting establish_document_relations results ==="

# ---------------------------------------------------------------------------
# 1. Capture Final Screenshot
# ---------------------------------------------------------------------------
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ---------------------------------------------------------------------------
# 2. Check Report File
# ---------------------------------------------------------------------------
REPORT_PATH="/home/ga/nuxeo_relations_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_VALID_TIMESTAMP="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | base64 -w 0)
    
    FILE_MOD=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MOD" -ge "$TASK_START" ]; then
        REPORT_VALID_TIMESTAMP="true"
    fi
fi

# ---------------------------------------------------------------------------
# 3. Verify Relations via Nuxeo API
# ---------------------------------------------------------------------------
echo "Querying Nuxeo API for relations..."

# We run a Python script to check the specific relations required
# Output is saved to a JSON file
python3 - <<'PYEOF'
import requests, json, sys, os

NUXEO = "http://localhost:8080/nuxeo"
AUTH = ("Administrator", "Administrator")

results = {
    "relation_1_found": False, # Annual Report -> IsBasedOn -> Proposal
    "relation_2_found": False, # Annual Report -> References -> Q3 Status
    "relation_3_found": False, # Contract -> ConformsTo -> Annual Report
    "api_error": None
}

def get_uid(path):
    try:
        r = requests.get(f"{NUXEO}/api/v1/path{path}", auth=AUTH, timeout=5)
        if r.status_code == 200:
            return r.json().get("uid")
    except:
        return None
    return None

try:
    # Get UIDs of target documents to verify relations accurately
    uid_proposal = get_uid("/default-domain/workspaces/Projects/Project-Proposal")
    uid_status = get_uid("/default-domain/workspaces/Projects/Q3-Status-Report")
    uid_report = get_uid("/default-domain/workspaces/Projects/Annual-Report-2023")

    # ---------------------------------------------------------
    # Check Relations for Annual Report 2023
    # ---------------------------------------------------------
    r1 = requests.get(
        f"{NUXEO}/api/v1/path/default-domain/workspaces/Projects/Annual-Report-2023/@relations",
        auth=AUTH,
        timeout=10
    )
    
    if r1.status_code == 200:
        entries = r1.json().get("entries", [])
        for rel in entries:
            pred = rel.get("predicate", "")
            target = rel.get("target", "")
            
            # Check 1: IsBasedOn -> Proposal
            if "IsBasedOn" in pred and (target == uid_proposal or "Project-Proposal" in target):
                results["relation_1_found"] = True
            
            # Check 2: References -> Q3 Status
            if "References" in pred and (target == uid_status or "Q3-Status-Report" in target):
                results["relation_2_found"] = True

    # ---------------------------------------------------------
    # Check Relations for Contract Template
    # ---------------------------------------------------------
    r2 = requests.get(
        f"{NUXEO}/api/v1/path/default-domain/workspaces/Templates/Contract-Template/@relations",
        auth=AUTH,
        timeout=10
    )
    
    if r2.status_code == 200:
        entries = r2.json().get("entries", [])
        for rel in entries:
            pred = rel.get("predicate", "")
            target = rel.get("target", "")
            
            # Check 3: ConformsTo -> Annual Report
            if "ConformsTo" in pred and (target == uid_report or "Annual-Report-2023" in target):
                results["relation_3_found"] = True

except Exception as e:
    results["api_error"] = str(e)

with open("/tmp/api_verification.json", "w") as f:
    json.dump(results, f)
PYEOF

# ---------------------------------------------------------------------------
# 4. Check Initial State (Anti-Gaming)
# ---------------------------------------------------------------------------
INITIAL_CLEAN="true"
if [ -f "/tmp/initial_relations_count.json" ]; then
    # If any count was > 0 initially (which shouldn't happen in clean env), flag it
    IS_CLEAN=$(python3 -c "import json; d=json.load(open('/tmp/initial_relations_count.json')); print(all(v==0 for v in d.values()))" 2>/dev/null)
    if [ "$IS_CLEAN" = "False" ]; then
        INITIAL_CLEAN="false"
    fi
fi

# ---------------------------------------------------------------------------
# 5. Compile Final Result JSON
# ---------------------------------------------------------------------------
# Combine API results and file checks
python3 -c "
import json
try:
    with open('/tmp/api_verification.json') as f:
        api_res = json.load(f)
except:
    api_res = {}

final = {
    'report_exists': '$REPORT_EXISTS' == 'true',
    'report_valid_timestamp': '$REPORT_VALID_TIMESTAMP' == 'true',
    'report_content_b64': '$REPORT_CONTENT',
    'initial_state_clean': '$INITIAL_CLEAN' == 'true',
    'api_results': api_res,
    'task_start': $TASK_START,
    'task_end': $(date +%s)
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final, f)
"

# Set permissions so verifier can copy it
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json