#!/bin/bash
# Export script for regulatory_compliance_remediation task.
# Collects Nuxeo state via REST API and writes to /tmp/task_result.json.

source /workspace/scripts/task_utils.sh

echo "=== Exporting regulatory_compliance_remediation results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Collect all verification state via Python
python3 << 'PYEOF'
import json, subprocess, sys, urllib.parse

NUXEO_URL = "http://localhost:8080/nuxeo"
AUTH = "Administrator:Administrator"

def api_get(endpoint):
    """GET a Nuxeo REST API endpoint and return parsed JSON."""
    try:
        result = subprocess.run(
            ["curl", "-s", "-u", AUTH,
             "-H", "X-NXproperties: *",
             "-H", "Content-Type: application/json",
             f"{NUXEO_URL}/api/v1{endpoint}"],
            capture_output=True, text=True, timeout=15
        )
        return json.loads(result.stdout)
    except Exception:
        return None

def nxql(query):
    """Execute an NXQL query and return parsed results."""
    encoded = urllib.parse.quote(query)
    return api_get(f"/search/lang/NXQL/execute?query={encoded}")

result = {}

# --- 1. Security-Policy-2024 document state ---
sp = api_get("/path/default-domain/workspaces/Projects/Security-Policy-2024")
if sp and "uid" in sp:
    props = sp.get("properties", {})
    result["security_policy"] = {
        "exists": True,
        "uid": sp.get("uid", ""),
        "version_label": sp.get("versionLabel", "0.0"),
        "dc_description": props.get("dc:description", ""),
        "dc_coverage": props.get("dc:coverage", "")
    }
else:
    result["security_policy"] = {"exists": False}

# --- 2. Security-Policy proxy in General-Publications (should NOT exist after remediation) ---
gp = nxql("SELECT * FROM Document WHERE ecm:path STARTSWITH "
          "'/default-domain/sections/General-Publications' "
          "AND ecm:primaryType != 'Section' AND ecm:isTrashed = 0")
gp_count = gp.get("resultsCount", 0) if gp else 0
result["sp_in_general_publications"] = gp_count

# --- 3. Security-Policy proxy in Compliance/Regulatory-Filings (should exist) ---
rf = nxql("SELECT * FROM Document WHERE ecm:path STARTSWITH "
          "'/default-domain/sections/Compliance/Regulatory-Filings' "
          "AND ecm:primaryType != 'Section' AND ecm:isTrashed = 0")
rf_count = rf.get("resultsCount", 0) if rf else 0
rf_title = ""
if rf and rf.get("entries"):
    rf_title = rf["entries"][0].get("title", "")
result["sp_in_regulatory_filings"] = rf_count
result["sp_in_regulatory_filings_title"] = rf_title

# --- 4. Data-Processing-Agreement document state ---
dpa = api_get("/path/default-domain/workspaces/Projects/Data-Processing-Agreement")
if dpa and "uid" in dpa:
    props = dpa.get("properties", {})
    fc = props.get("file:content") or {}
    result["dpa"] = {
        "exists": True,
        "uid": dpa.get("uid", ""),
        "version_label": dpa.get("versionLabel", "0.0"),
        "file_digest": fc.get("digest", ""),
        "file_name": fc.get("name", "")
    }
else:
    result["dpa"] = {"exists": False}

# --- 5. DPA tags ---
tags_resp = api_get("/path/default-domain/workspaces/Projects/Data-Processing-Agreement/@tagging")
if tags_resp and "entries" in tags_resp:
    result["dpa_tags"] = [t.get("label", "") for t in tags_resp.get("entries", [])]
else:
    result["dpa_tags"] = []

# --- 6. DPA ACL — check if external-reviewer still has access ---
acl_resp = api_get("/path/default-domain/workspaces/Projects/Data-Processing-Agreement/@acl")
ext_reviewer_access = False
if acl_resp:
    for acl_block in acl_resp.get("acl", []):
        for ace in acl_block.get("ace", []):
            if ace.get("username") == "external-reviewer" and ace.get("granted", False):
                ext_reviewer_access = True
result["dpa_external_reviewer_has_access"] = ext_reviewer_access

# --- 7. DPA proxy in Legal/Legal-Archive (should exist after remediation) ---
la = nxql("SELECT * FROM Document WHERE ecm:path STARTSWITH "
          "'/default-domain/sections/Legal/Legal-Archive' "
          "AND ecm:primaryType != 'Section' AND ecm:isTrashed = 0")
la_count = la.get("resultsCount", 0) if la else 0
la_title = ""
if la and la.get("entries"):
    la_title = la["entries"][0].get("title", "")
result["dpa_in_legal_archive"] = la_count
result["dpa_in_legal_archive_title"] = la_title

# --- 8. Remediation-Summary note ---
rs = api_get("/path/default-domain/workspaces/Projects/Remediation-Summary")
if rs and "uid" in rs:
    note_content = rs.get("properties", {}).get("note:note", "") or ""
    result["remediation_summary"] = {
        "exists": True,
        "type": rs.get("type", ""),
        "content_length": len(note_content),
        "has_security_policy_ref": "Security" in note_content and "Policy" in note_content,
        "has_dpa_ref": "Data" in note_content and "Processing" in note_content
    }
else:
    result["remediation_summary"] = {"exists": False}

# --- 9. Q1-2025-Compliance-Bundle collection ---
coll = nxql("SELECT * FROM Collection WHERE dc:title = 'Q1-2025-Compliance-Bundle' "
            "AND ecm:isTrashed = 0 AND ecm:isVersion = 0")
coll_entries = coll.get("entries", []) if coll else []
if coll_entries:
    coll_uid = coll_entries[0].get("uid", "")
    members = api_get(f"/id/{coll_uid}/@children?pageSize=20")
    member_titles = []
    if members and "entries" in members:
        member_titles = [e.get("title", "") for e in members["entries"]]
    result["collection"] = {
        "exists": True,
        "member_count": len(member_titles),
        "member_titles": member_titles
    }
else:
    result["collection"] = {"exists": False, "member_count": 0, "member_titles": []}

# --- 10. Load original DPA digest from setup ---
try:
    setup = json.load(open("/tmp/setup_state.json"))
    result["original_dpa_digest"] = setup.get("original_dpa_digest", "")
except Exception:
    result["original_dpa_digest"] = ""

# --- Write result ---
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("State collection complete.")
PYEOF

# Ensure readable
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json 2>/dev/null || true
echo ""
echo "=== Export complete ==="
