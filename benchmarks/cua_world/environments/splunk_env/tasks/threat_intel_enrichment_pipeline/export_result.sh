#!/usr/bin/env bash
# export_result.sh — post_task hook for threat_intel_enrichment_pipeline
# Collects current state of all pipeline artifacts and compares to baselines.

set -euo pipefail
source /workspace/scripts/task_utils.sh

echo "[export] Starting threat_intel_enrichment_pipeline export..."

# ── 1. Take final screenshot ────────────────────────────────────────────────
take_screenshot /tmp/task_end_screenshot.png

# ── 2. Collect all artifact state via Splunk REST API + filesystem ───────────
TEMP_JSON="/tmp/tiep_result_tmp_$$.json"

python3 << 'PYEOF'
import json, os, re, subprocess, urllib.request, ssl

ctx = ssl._create_unverified_context()
USER = "admin"
PASS = "SplunkAdmin1!"
API  = "https://localhost:8089"

def api_get(path):
    """GET from Splunk REST API, return parsed JSON."""
    url = f"{API}{path}?output_mode=json&count=0"
    req = urllib.request.Request(url)
    req.add_header("Authorization", "Basic " + __import__("base64").b64encode(f"{USER}:{PASS}".encode()).decode())
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=30) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        print(f"[export] API error for {path}: {e}")
        return {"entry": []}

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except:
        return {"entry": []}

def normalize(name):
    return name.lower().replace(" ", "_").replace("-", "_")

# ── Load baselines ──
initial_searches = {e["name"] for e in load_json("/tmp/tiep_initial_saved_searches.json").get("entry", [])}
initial_dashboards = {e["name"] for e in load_json("/tmp/tiep_initial_dashboards.json").get("entry", [])}
initial_lookup_defs = {e["name"] for e in load_json("/tmp/tiep_initial_lookup_defs.json").get("entry", [])}

# ── Check 1: Lookup CSV file ──
lookup_file_paths = [
    "/opt/splunk/etc/apps/search/lookups/threat_intel.csv",
    "/opt/splunk/etc/apps/launcher/lookups/threat_intel.csv",
    "/opt/splunk/etc/system/lookups/threat_intel.csv",
]
lookup_file_info = {"exists": False, "path": None, "row_count": 0, "has_src_ip": False,
                    "has_threat_level": False, "has_attempt_count": False, "header": "", "sample_rows": []}
for p in lookup_file_paths:
    if os.path.isfile(p) and os.path.getsize(p) > 10:
        lookup_file_info["exists"] = True
        lookup_file_info["path"] = p
        try:
            with open(p) as f:
                lines = f.readlines()
            lookup_file_info["row_count"] = max(0, len(lines) - 1)
            if lines:
                header = lines[0].strip().lower()
                lookup_file_info["header"] = lines[0].strip()
                lookup_file_info["has_src_ip"] = "src_ip" in header
                lookup_file_info["has_threat_level"] = "threat_level" in header
                lookup_file_info["has_attempt_count"] = "attempt_count" in header or "count" in header
                lookup_file_info["sample_rows"] = [l.strip() for l in lines[1:6]]
        except:
            pass
        break

# ── Check 2: Lookup definition ──
current_lookup_defs = api_get("/servicesNS/-/-/data/transforms/lookups")
lookup_def_info = {"exists": False, "name": None, "filename": None, "is_new": False}
for entry in current_lookup_defs.get("entry", []):
    n = entry.get("name", "")
    if normalize(n) == "threat_intel_lookup":
        content = entry.get("content", {})
        lookup_def_info["exists"] = True
        lookup_def_info["name"] = n
        lookup_def_info["filename"] = content.get("filename", "")
        lookup_def_info["is_new"] = n not in initial_lookup_defs
        break

# ── Check 3: Automatic lookup ──
# Automatic lookups are stored under props.conf. Query the props/lookups endpoint.
auto_lookup_info = {"exists": False, "name": None, "stanza": None, "lookup_name": None,
                    "input_field": None, "output_fields": [], "is_new": False}
props_resp = api_get("/servicesNS/-/-/data/props/lookups")
for entry in props_resp.get("entry", []):
    n = entry.get("name", "")
    content = entry.get("content", {})
    val = content.get("value", "") if isinstance(content, dict) else ""
    # Also check the attribute/stanza for our auto-lookup
    if "threat_auto_enrich" in n.lower() or "threat_intel" in str(val).lower():
        auto_lookup_info["exists"] = True
        auto_lookup_info["name"] = n
        auto_lookup_info["stanza"] = content.get("stanza", "")
        auto_lookup_info["lookup_name"] = ""
        auto_lookup_info["is_new"] = True
        # Parse the value string: "LOOKUP-name lookup_def input_field AS lookup_field OUTPUT out1 out2"
        if val:
            auto_lookup_info["raw_value"] = val
            parts = val.split()
            if len(parts) >= 2:
                auto_lookup_info["lookup_name"] = parts[0]
            for i, p in enumerate(parts):
                if p.upper() == "OUTPUT" or p.upper() == "OUTPUTNEW":
                    auto_lookup_info["output_fields"] = parts[i+1:]
                    break
        break

# Alternative: check transforms.conf for automatic lookup via btool
try:
    result = subprocess.run(
        ["/opt/splunk/bin/splunk", "btool", "props", "list", "linux_secure", "--debug"],
        capture_output=True, text=True, timeout=15
    )
    btool_lines = result.stdout if result.returncode == 0 else ""
    for line in btool_lines.split("\n"):
        if "LOOKUP-" in line and "threat" in line.lower():
            auto_lookup_info["exists"] = True
            auto_lookup_info["btool_evidence"] = line.strip()
            break
except:
    pass

# ── Check 4: Dashboard ──
current_dashboards = api_get("/servicesNS/-/-/data/ui/views")
dashboard_info = {"exists": False, "name": None, "is_new": False, "panel_count": 0,
                  "has_time_picker": False, "has_threat_level_ref": False,
                  "has_timechart": False, "has_stats": False, "xml_snippet": ""}
target_names = ["threat_intelligence_monitor"]
for entry in current_dashboards.get("entry", []):
    n = entry.get("name", "")
    if normalize(n) in target_names:
        content = entry.get("content", {})
        xml = content.get("eai:data", "")
        dashboard_info["exists"] = True
        dashboard_info["name"] = n
        dashboard_info["is_new"] = n not in initial_dashboards
        dashboard_info["panel_count"] = len(re.findall(r"<panel", xml, re.IGNORECASE))
        dashboard_info["has_time_picker"] = bool(re.search(r'<input\s+type="time"', xml, re.IGNORECASE))
        dashboard_info["has_threat_level_ref"] = "threat_level" in xml.lower()
        dashboard_info["has_timechart"] = "timechart" in xml.lower()
        dashboard_info["has_stats"] = bool(re.search(r'\bstats\b', xml.lower()))
        dashboard_info["has_attempt_count_ref"] = "attempt_count" in xml.lower()
        dashboard_info["xml_snippet"] = xml[:3000]
        break

# If exact name not found, check for any new dashboard
if not dashboard_info["exists"]:
    for entry in current_dashboards.get("entry", []):
        n = entry.get("name", "")
        if n not in initial_dashboards and "threat" in n.lower():
            content = entry.get("content", {})
            xml = content.get("eai:data", "")
            dashboard_info["exists"] = True
            dashboard_info["name"] = n
            dashboard_info["is_new"] = True
            dashboard_info["panel_count"] = len(re.findall(r"<panel", xml, re.IGNORECASE))
            dashboard_info["has_time_picker"] = bool(re.search(r'<input\s+type="time"', xml, re.IGNORECASE))
            dashboard_info["has_threat_level_ref"] = "threat_level" in xml.lower()
            dashboard_info["has_timechart"] = "timechart" in xml.lower()
            dashboard_info["has_stats"] = bool(re.search(r'\bstats\b', xml.lower()))
            dashboard_info["has_attempt_count_ref"] = "attempt_count" in xml.lower()
            dashboard_info["xml_snippet"] = xml[:3000]
            break

# ── Check 5: Alert ──
current_searches = api_get("/servicesNS/-/-/saved/searches")
alert_info = {"exists": False, "name": None, "is_new": False, "search": "",
              "is_scheduled": False, "cron_schedule": "", "alert_type": "",
              "references_lookup": False, "references_critical": False}
for entry in current_searches.get("entry", []):
    n = entry.get("name", "")
    if normalize(n) == "critical_threat_activity":
        content = entry.get("content", {})
        alert_info["exists"] = True
        alert_info["name"] = n
        alert_info["is_new"] = n not in initial_searches
        alert_info["search"] = content.get("search", "")
        alert_info["is_scheduled"] = str(content.get("is_scheduled", "")).lower() in ("1", "true", "yes")
        alert_info["cron_schedule"] = content.get("cron_schedule", "")
        alert_info["alert_type"] = content.get("alert_type", "")
        spl = alert_info["search"].lower()
        alert_info["references_lookup"] = "lookup" in spl or "inputlookup" in spl
        alert_info["references_critical"] = "critical" in spl
        break

# ── Build result JSON ──
result = {
    "lookup_file": lookup_file_info,
    "lookup_definition": lookup_def_info,
    "automatic_lookup": auto_lookup_info,
    "dashboard": dashboard_info,
    "alert": alert_info,
    "export_timestamp": int(__import__("time").time()),
    "task_start_timestamp": 0
}

try:
    with open("/tmp/task_start_timestamp") as f:
        result["task_start_timestamp"] = int(f.read().strip())
except:
    pass

# Write result
import tempfile
temp_path = "/tmp/tiep_result_tmp.json"
final_path = "/tmp/tiep_task_result.json"
with open(temp_path, "w") as f:
    json.dump(result, f, indent=2)

# safe copy
import shutil
if os.path.exists(final_path):
    os.remove(final_path)
shutil.copy2(temp_path, final_path)
os.chmod(final_path, 0o666)
print(f"[export] Result written to {final_path}")
print(json.dumps(result, indent=2))

PYEOF

echo "[export] Export complete."
