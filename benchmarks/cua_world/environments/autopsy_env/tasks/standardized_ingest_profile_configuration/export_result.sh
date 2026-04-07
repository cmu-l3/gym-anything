#!/bin/bash
# Export script for standardized_ingest_profile_configuration task

echo "=== Exporting results for profile_configuration ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot showing end state
take_screenshot /tmp/task_final.png ga

# Kill Autopsy to release SQLite locks and flush module outputs
kill_autopsy
sleep 3

python3 << 'PYEOF'
import json, os, sqlite3, glob, re

result = {
    "task": "standardized_ingest_profile_configuration",
    "start_time": 0,
    "case_db_found": False,
    "case_name_matches": False,
    "data_source_added": False,
    "profile_created": False,
    "all_profiles": [],
    "db_mime_count": 0,
    "db_md5_count": 0,
    "db_ext_mismatch_count": 0,
    "module_output_folders": [],
    "heavy_modules_ran": False,
    "audit_report_exists": False,
    "audit_report_mtime": 0,
    "audit_report_content": "",
    "error": ""
}

try:
    with open("/tmp/profile_config_start_time") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

# 1. Check Global Ingest Profiles
try:
    profiles_base = "/home/ga/.autopsy/dev/config/IngestProfiles"
    if os.path.isdir(profiles_base):
        result["all_profiles"] = os.listdir(profiles_base)
        for p in result["all_profiles"]:
            if p.lower().replace(" ", "_") == "fast_triage":
                result["profile_created"] = True
except Exception as e:
    result["error"] += f" | Profile check error: {e}"

# 2. Locate case DB
db_paths = glob.glob("/home/ga/Cases/Backlog_Triage_2024*/autopsy.db")
if db_paths:
    db_path = db_paths[0]
    result["case_db_found"] = True
    result["case_name_matches"] = True
    
    # 3. Check ModuleOutput folders (highly reliable indicator of which modules actually ran)
    case_dir = os.path.dirname(db_path)
    module_output_dir = os.path.join(case_dir, "ModuleOutput")
    if os.path.isdir(module_output_dir):
        folders = os.listdir(module_output_dir)
        result["module_output_folders"] = folders
        
        # Check if heavy modules ran
        heavy_indicators = ["keyword search", "photorec", "carver", "picture analyzer", "recent activity"]
        for folder in folders:
            if any(h in folder.lower() for h in heavy_indicators):
                result["heavy_modules_ran"] = True

    # 4. Check Database artifacts
    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
        cur = conn.cursor()
        
        # Data source
        try:
            cur.execute("SELECT COUNT(*) FROM data_source_info")
            result["data_source_added"] = cur.fetchone()[0] > 0
        except:
            pass
            
        # File Type ID (MIME types populated)
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE mime_type IS NOT NULL AND mime_type != ''")
            result["db_mime_count"] = cur.fetchone()[0]
        except: pass
            
        # Hash Lookup (MD5 populated)
        try:
            cur.execute("SELECT COUNT(*) FROM tsk_files WHERE md5 IS NOT NULL AND md5 != ''")
            result["db_md5_count"] = cur.fetchone()[0]
        except: pass
        
        # Extension Mismatch (Artifacts)
        try:
            cur.execute("""
                SELECT COUNT(*) FROM blackboard_artifacts ba
                JOIN blackboard_artifact_types bat ON ba.artifact_type_id = bat.artifact_type_id
                WHERE bat.type_name = 'TSK_EXT_MISMATCH_DETECT'
            """)
            result["db_ext_mismatch_count"] = cur.fetchone()[0]
        except: pass
        
        conn.close()
    except Exception as e:
        result["error"] += f" | DB error: {e}"

# 5. Check Audit Report
report_path = "/home/ga/Reports/profile_audit.txt"
if os.path.exists(report_path):
    result["audit_report_exists"] = True
    result["audit_report_mtime"] = int(os.path.getmtime(report_path))
    with open(report_path, "r", errors="replace") as f:
        result["audit_report_content"] = f.read(4096)

print(json.dumps(result, indent=2))
with open("/tmp/profile_config_result.json", "w") as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/profile_config_result.json")
PYEOF

echo "=== Export complete ==="