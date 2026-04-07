#!/bin/bash
# Post-task export script
# Queries Nuxeo API for the folder state, ACLs, and children, and saves to JSON.

echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Use Python to robustly query API and format JSON
# This runs INSIDE the container to generate the result file
python3 -c '
import sys
import json
import requests
import time
import os

NUXEO_URL = "http://localhost:8080/nuxeo"
AUTH = ("Administrator", "Administrator")
HEADERS = {"Content-Type": "application/json", "X-NXproperties": "*"}
FOLDER_PATH = "/path/default-domain/workspaces/Projects/Confidential-HR"

result = {
    "task_start": int(os.environ.get("TASK_START", 0)),
    "task_end": int(os.environ.get("TASK_END", 0)),
    "folder_found": False,
    "folder_metadata": {},
    "acls": [],
    "children": [],
    "inheritance_blocked": False,
    "jsmith_permission": None,
    "members_permission": None,
    "note_found": False,
    "note_title": None
}

try:
    # 1. Get Folder Metadata & ACLs
    # We use the enricher to get ACLs in one go
    resp = requests.get(
        f"{NUXEO_URL}/api/v1{FOLDER_PATH}",
        auth=AUTH,
        headers=HEADERS,
        params={"enrichers.document": "acls"},
        timeout=10
    )
    
    if resp.status_code == 200:
        data = resp.json()
        result["folder_found"] = True
        result["folder_metadata"] = {
            "type": data.get("type"),
            "title": data.get("properties", {}).get("dc:title"),
            "uid": data.get("uid")
        }
        
        # Parse ACLs
        # Context parameters > acls OR explicit @acl adapter if enricher fails
        acls_list = data.get("contextParameters", {}).get("acls", [])
        if not acls_list:
             # Fallback to direct ACL endpoint
             acl_resp = requests.get(f"{NUXEO_URL}/api/v1{FOLDER_PATH}/@acl", auth=AUTH, headers=HEADERS)
             if acl_resp.status_code == 200:
                 acls_list = acl_resp.json().get("acl", [])
        
        result["acls"] = acls_list
        
        # Analyze ACLs for easier verification
        for acl in acls_list:
            for ace in acl.get("ace", acl.get("aces", [])):
                # Check blocked inheritance
                # Nuxeo represents this as an ACE with blockInheritance=True 
                # OR a deny Everything to Everyone (though usually blockInheritance flag is preferred in modern Nuxeo)
                if ace.get("blockInheritance") is True:
                    result["inheritance_blocked"] = True
                if ace.get("username") == "Everyone" and ace.get("permission") == "Everything" and ace.get("granted") is False:
                    result["inheritance_blocked"] = True
                    
                # Check permissions
                if ace.get("granted") is True:
                    if ace.get("username") == "jsmith":
                        result["jsmith_permission"] = ace.get("permission")
                    if ace.get("username") == "members":
                        result["members_permission"] = ace.get("permission")

    # 2. Get Children (to find the Note)
    if result["folder_found"]:
        children_resp = requests.get(
            f"{NUXEO_URL}/api/v1{FOLDER_PATH}/@children",
            auth=AUTH,
            headers=HEADERS
        )
        if children_resp.status_code == 200:
            entries = children_resp.json().get("entries", [])
            simple_children = []
            for entry in entries:
                child_type = entry.get("type")
                child_title = entry.get("properties", {}).get("dc:title")
                simple_children.append({"type": child_type, "title": child_title})
                
                # Check if this is the target note
                if child_type == "Note":
                    # Flexible matching for the note
                    if "policy" in child_title.lower() or "employee" in child_title.lower():
                        result["note_found"] = True
                        result["note_title"] = child_title
            
            result["children"] = simple_children

except Exception as e:
    result["error"] = str(e)

# Save result to file
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

' 2>/tmp/export_error.log

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated at /tmp/task_result.json"
echo "=== Export complete ==="