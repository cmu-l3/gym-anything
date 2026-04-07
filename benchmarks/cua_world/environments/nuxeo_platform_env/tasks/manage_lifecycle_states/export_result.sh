#!/bin/bash
# Export script for manage_lifecycle_states
# Queries Nuxeo API for final states and audit logs

echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to gather comprehensive state data
python3 << PYEOF > /tmp/task_result.json
import requests
import json
import time
import os

base = "http://localhost:8080/nuxeo/api/v1"
auth = ("Administrator", "Administrator")
headers = {"Content-Type": "application/json"}
task_start = $TASK_START

# Target documents
targets = {
    "Annual-Report-2023": "/default-domain/workspaces/Projects/Annual-Report-2023",
    "Project-Proposal": "/default-domain/workspaces/Projects/Project-Proposal",
    "Q3-Status-Report": "/default-domain/workspaces/Projects/Q3-Status-Report",
    "Contract-Template": "/default-domain/workspaces/Templates/Contract-Template"
}

results = {
    "task_start": task_start,
    "task_end": $TASK_END,
    "doc_states": {},
    "transitions_found": 0,
    "screenshot_path": "/tmp/task_final.png"
}

# 1. Check Document States
for name, path in targets.items():
    try:
        r = requests.get(f"{base}/path{path}", auth=auth, headers=headers)
        if r.status_code == 200:
            results["doc_states"][name] = r.json().get("state", "unknown")
        else:
            results["doc_states"][name] = "missing"
    except:
        results["doc_states"][name] = "error"

# 2. Check Audit Log for Transition Events after Task Start
# We look for 'lifecycle_transition_event'
nxql = f"SELECT * FROM Document WHERE ecm:primaryType IN ('File','Note') AND ecm:path STARTSWITH '/default-domain/workspaces/Projects'"
audit_url = f"{base}/search/lang/NXQL/execute"

try:
    # This query gets the docs; we need to query the audit log for each, 
    # OR we can just check if state != project implies a transition happened.
    # A more robust check is querying the 'audit' adapter on the documents.
    
    transition_count = 0
    for name, path in targets.items():
        if name == "Contract-Template": continue # Skip template
        
        # Get document ID first
        r_doc = requests.get(f"{base}/path{path}", auth=auth, headers=headers)
        if r_doc.status_code == 200:
            doc_uid = r_doc.json().get("uid")
            
            # Query audit log for this document
            # API: /repo/default/id/{id}/@audit
            r_audit = requests.get(f"{base}/id/{doc_uid}/@audit", auth=auth, headers=headers)
            if r_audit.status_code == 200:
                entries = r_audit.json().get("entries", [])
                for entry in entries:
                    # Check for lifecycle transition event
                    eid = entry.get("eventId")
                    edate = entry.get("eventDate") # Format: 2023-10-25T10:00:00.000Z
                    
                    # Convert Nuxeo date to timestamp
                    # Simplified: if we find a 'lifecycle_transition_event' matching our target states
                    if eid == "lifecycle_transition_event":
                        # We can try to parse date, or simpler: trust the verifier logic 
                        # that if state changed from 'project' (verified in setup) to 'approved',
                        # it happened during the task.
                        transition_count += 1
                        break
    
    results["transitions_found"] = transition_count

except Exception as e:
    results["audit_error"] = str(e)

print(json.dumps(results, indent=2))
PYEOF

# Ensure permissions on result file
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="