#!/bin/bash
# export_result.sh - Export results for OSINT Profile Setup task

echo "=== Exporting Task Results ==="

# 1. Take Final Screenshot (before killing Edge, to see the UI state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge (CRITICAL)
# Edge only writes certain preferences to disk when it closes or periodically.
# For verification, we must force a write by closing it.
echo "Stopping Edge to flush preferences..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 3
# Ensure it's dead
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true

# 3. Run Python Analysis Script
# This script parses the complicated Local State and Preferences files.
python3 << 'PYEOF'
import json
import os
import sys
import glob

# Paths
local_state_path = "/home/ga/.config/microsoft-edge/Local State"
config_dir = "/home/ga/.config/microsoft-edge"
report_path = "/home/ga/Desktop/osint_profile_config.txt"
task_start_path = "/tmp/task_start_time.txt"
initial_profiles_path = "/tmp/initial_profiles.json"
output_json_path = "/tmp/task_result.json"

result = {
    "profile_found": False,
    "profile_name_match": False,
    "profile_dir": None,
    "is_new_profile": False,
    "settings": {
        "tracking_prevention": None,
        "do_not_track": None,
        "password_manager_disabled": None,
        "autofill_disabled": None,
        "startup_urls": []
    },
    "report": {
        "exists": False,
        "content_valid": False,
        "modified_after_start": False
    }
}

try:
    # 1. Load timestamps and initial state
    task_start_time = 0
    if os.path.exists(task_start_path):
        with open(task_start_path, 'r') as f:
            task_start_time = int(f.read().strip())

    initial_profiles = []
    if os.path.exists(initial_profiles_path):
        with open(initial_profiles_path, 'r') as f:
            initial_profiles = json.load(f)

    # 2. Parse Local State to find the OSINT profile
    if os.path.exists(local_state_path):
        with open(local_state_path, 'r') as f:
            local_state = json.load(f)
        
        info_cache = local_state.get("profile", {}).get("info_cache", {})
        
        target_profile_dir = None
        
        # Search for profile by name "OSINT-Research" (case-insensitive partial match allowed for robustness)
        for dir_name, info in info_cache.items():
            name = info.get("name", "")
            if "osint" in name.lower():
                target_profile_dir = dir_name
                result["profile_found"] = True
                if "osint-research" in name.lower():
                    result["profile_name_match"] = True
                
                # Check if this is a new profile
                if dir_name not in initial_profiles:
                    result["is_new_profile"] = True
                break
        
        result["profile_dir"] = target_profile_dir

        # 3. If profile found, check its Preferences
        if target_profile_dir:
            pref_path = os.path.join(config_dir, target_profile_dir, "Preferences")
            if os.path.exists(pref_path):
                with open(pref_path, 'r') as f:
                    prefs = json.load(f)
                
                # Check Settings
                
                # Tracking Prevention: 
                # Key: "privacy.tracking_prevention.level" -> 3 (Strict), 2 (Balanced), 1 (Basic)
                # Note: Edge might store this in different places depending on version.
                # Checking generic top-level or nested keys.
                tp_level = prefs.get("privacy", {}).get("tracking_prevention", {}).get("level")
                # Fallback location
                if tp_level is None:
                    # Sometimes just "tracking_prevention": 3 at top level in older versions
                    tp_level = prefs.get("tracking_prevention")
                
                result["settings"]["tracking_prevention"] = tp_level

                # Do Not Track
                result["settings"]["do_not_track"] = prefs.get("enable_do_not_track")

                # Password Manager (False means enabled usually, wait: credentials_enable_service)
                # "credentials_enable_service": false means DISABLED.
                result["settings"]["password_manager_disabled"] = not prefs.get("credentials_enable_service", True)

                # Autofill (Addresses)
                # "autofill": { "profile_enabled": false }
                # OR "autofill": { "enabled": false }
                autofill = prefs.get("autofill", {})
                af_enabled = autofill.get("profile_enabled", True)
                # Fallback check
                if "enabled" in autofill:
                     af_enabled = autofill.get("enabled", True)
                
                result["settings"]["autofill_disabled"] = not af_enabled

                # Startup URLs
                # "session": { "restore_on_startup": 4, "startup_urls": [...] }
                session = prefs.get("session", {})
                restore_type = session.get("restore_on_startup")
                urls = session.get("startup_urls", [])
                
                # Filter URLs to be robust against trailing slashes/protocols
                clean_urls = []
                for u in urls:
                    if isinstance(u, str):
                        clean_urls.append(u.lower())
                
                result["settings"]["startup_urls"] = clean_urls
                result["settings"]["restore_on_startup_type"] = restore_type # 4 is 'open specific pages'

    # 4. Check Report File
    if os.path.exists(report_path):
        result["report"]["exists"] = True
        
        # Check modification time
        mtime = os.path.getmtime(report_path)
        if mtime > task_start_time:
            result["report"]["modified_after_start"] = True
        
        # Check content
        with open(report_path, 'r', errors='ignore') as f:
            content = f.read().lower()
            
        # Basic keyword checks
        keywords = ["osint", "tracking", "password", "autofill", "shodan"]
        hit_count = sum(1 for k in keywords if k in content)
        if hit_count >= 2 and len(content) > 50:
            result["report"]["content_valid"] = True

except Exception as e:
    result["error"] = str(e)

# Write result to JSON
with open(output_json_path, 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Move result to safe location and cleanup
cp /tmp/task_result.json /tmp/task_result_final.json
chmod 666 /tmp/task_result_final.json 2>/dev/null || true

echo "Export complete. Result:"
cat /tmp/task_result_final.json
echo "=== Export Complete ==="