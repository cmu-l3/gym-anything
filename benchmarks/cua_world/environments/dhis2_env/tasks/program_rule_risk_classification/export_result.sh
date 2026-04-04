#!/bin/bash
# Export script for Program Rule Risk Classification task

echo "=== Exporting Program Rule Risk Classification Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

echo "Collecting metadata configuration..."

# python script to traverse the DHIS2 metadata graph
# We need to find:
# 1. The new Data Element (Neonatal Risk Status)
# 2. Its assignment to the Child Programme
# 3. The Program Rule Variable
# 4. The Program Rule and its Actions

METADATA_EXPORT=$(python3 << 'PYEOF'
import json
import sys
import subprocess
from datetime import datetime

def api_get(endpoint):
    cmd = ["curl", "-s", "-u", "admin:district", f"http://localhost:8080/api/{endpoint}"]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True)
        return json.loads(result.stdout)
    except:
        return {}

def parse_date(date_str):
    if not date_str: return datetime.min
    try:
        # Handle formats like 2023-10-25T10:00:00.000 or 2023-10-25T10:00:00.000+0000
        clean_str = date_str.split('.')[0] 
        return datetime.fromisoformat(clean_str)
    except:
        return datetime.min

task_start_iso = "$TASK_START_ISO"
task_start_dt = parse_date(task_start_iso)

results = {
    "data_element": None,
    "program_stage_entry": None,
    "rule_variable": None,
    "program_rule": None
}

# 1. Find Data Element "Neonatal Risk Status"
de_resp = api_get("dataElements?filter=name:ilike:neonatal%20risk&fields=id,displayName,domainType,valueType,created&paging=false")
found_de = None
for de in de_resp.get("dataElements", []):
    if "risk" in de.get("displayName", "").lower():
        found_de = de
        break

if found_de:
    results["data_element"] = {
        "id": found_de["id"],
        "name": found_de["displayName"],
        "domainType": found_de["domainType"],
        "valueType": found_de["valueType"],
        "created": found_de["created"],
        "created_after_start": parse_date(found_de["created"]) >= task_start_dt
    }

    # 2. Check if assigned to Program Stage
    # Find Child Programme first
    prog_resp = api_get("programs?filter=name:ilike:child&fields=id,programStages[id,displayName,programStageDataElements[dataElement[id]]]&paging=false")
    programs = prog_resp.get("programs", [])
    
    if programs:
        child_prog = programs[0]
        # Look for Birth stage
        birth_stage = next((s for s in child_prog.get("programStages", []) if "birth" in s.get("displayName", "").lower()), None)
        
        if birth_stage:
            # Check if our DE is in this stage
            ps_des = birth_stage.get("programStageDataElements", [])
            is_assigned = any(psde.get("dataElement", {}).get("id") == found_de["id"] for psde in ps_des)
            results["program_stage_entry"] = {
                "program_id": child_prog["id"],
                "stage_id": birth_stage["id"],
                "stage_name": birth_stage["displayName"],
                "is_assigned": is_assigned
            }

# 3. Find Program Rule Variable
# Look for variables created recently or linked to "Weight"
prv_resp = api_get("programRuleVariables?fields=id,displayName,programRuleVariableSourceType,dataElement[id,displayName],created,program[id]&paging=false")
target_prv = None

# Filter for variables in Child Programme
child_prog_id = results.get("program_stage_entry", {}).get("program_id")

for prv in prv_resp.get("programRuleVariables", []):
    # Check if linked to child program (if we found it)
    if child_prog_id and prv.get("program", {}).get("id") != child_prog_id:
        continue
        
    # Check if linked to a "Weight" data element
    de_name = prv.get("dataElement", {}).get("displayName", "").lower()
    if "weight" in de_name:
        target_prv = prv
        # Prefer one created recently
        if parse_date(prv.get("created")) >= task_start_dt:
            break

if target_prv:
    results["rule_variable"] = {
        "id": target_prv["id"],
        "name": target_prv["displayName"],
        "source_type": target_prv.get("programRuleVariableSourceType"),
        "source_data_element": target_prv.get("dataElement", {}).get("displayName"),
        "created": target_prv["created"],
        "created_after_start": parse_date(target_prv["created"]) >= task_start_dt
    }

# 4. Find Program Rule
# Look for rules created recently in Child Programme
pr_resp = api_get("programRules?fields=id,displayName,condition,program[id],programRuleActions[programRuleActionType,dataElement[id],content]&paging=false")

target_pr = None
for pr in pr_resp.get("programRules", []):
    if child_prog_id and pr.get("program", {}).get("id") != child_prog_id:
        continue
        
    # Check creation date or name
    # Note: programRules API might not always return 'created' field depending on version, 
    # relying on name similarity or condition logic
    cond = pr.get("condition", "")
    if "2500" in cond and "<" in cond:
        target_pr = pr
        break

if target_pr:
    # Check actions
    actions = target_pr.get("programRuleActions", [])
    target_action = None
    for action in actions:
        # Check if action assigns to our created data element
        if found_de and action.get("dataElement", {}).get("id") == found_de["id"]:
            target_action = action
            break
            
    results["program_rule"] = {
        "id": target_pr["id"],
        "name": target_pr["displayName"],
        "condition": target_pr["condition"],
        "has_assign_action": target_action is not None,
        "action_value": target_action.get("content") if target_action else None,
        "action_type": target_action.get("programRuleActionType") if target_action else None
    }

print(json.dumps(results))
PYEOF
)

echo "$METADATA_EXPORT" > /tmp/program_rule_risk_result.json

echo "Exported JSON content:"
cat /tmp/program_rule_risk_result.json

echo "=== Export Complete ==="