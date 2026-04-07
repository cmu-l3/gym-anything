#!/usr/bin/env python3
"""
Verifier for icu_device_inventory_mapping task.

Strategy:
1. Parse the user's submitted CSV file.
2. Read the OpenICE session log (lines generated during task).
3. For each device in the CSV:
   - Check if the UUID format is valid.
   - SEARCH the session log for this specific UUID.
   - VALIDATE that the log lines containing this UUID also contain keywords
     matching the claimed device type (e.g. UUID for "Pulse Oximeter" must
     appear in log lines mentioning "Pulse", "SpO2", or "NonInvasive").
4. Verify file structure and window counts.
"""

import json
import csv
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_icu_inventory(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result JSON
    result_data = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp_json:
        try:
            copy_from_env("/tmp/task_result.json", tmp_json.name)
            with open(tmp_json.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
        finally:
            if os.path.exists(tmp_json.name):
                os.unlink(tmp_json.name)

    # Check File Existence
    if not result_data.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Inventory CSV file was not created."}

    # Load CSV File
    csv_rows = []
    with tempfile.NamedTemporaryFile(delete=False, suffix='.csv') as tmp_csv:
        try:
            copy_from_env(result_data["csv_path"], tmp_csv.name)
            with open(tmp_csv.name, 'r', encoding='utf-8') as f:
                # Handle BOM or potential header issues
                content = f.read().strip()
                if not content:
                    return {"passed": False, "score": 10, "feedback": "CSV file exists but is empty."}
                
                # Simple CSV parse
                reader = csv.DictReader(content.splitlines())
                # Normalize headers (strip whitespace, lower case)
                if reader.fieldnames:
                    reader.fieldnames = [h.strip() for h in reader.fieldnames]
                
                for row in reader:
                    csv_rows.append(row)
        except Exception as e:
            return {"passed": False, "score": 10, "feedback": f"Failed to parse CSV: {e}"}
        finally:
            if os.path.exists(tmp_csv.name):
                os.unlink(tmp_csv.name)

    # Load Session Log
    log_content = ""
    with tempfile.NamedTemporaryFile(delete=False, suffix='.log') as tmp_log:
        try:
            copy_from_env(result_data["session_log_path"], tmp_log.name)
            with open(tmp_log.name, 'r', encoding='utf-8', errors='ignore') as f:
                log_content = f.read()
        except Exception as e:
            # If log fails, we can't verify UUIDs, but shouldn't fail total 0 if file exists
            logger.error(f"Failed to read logs: {e}")
        finally:
            if os.path.exists(tmp_log.name):
                os.unlink(tmp_log.name)

    # Scoring Logic
    score = 0
    feedback = []
    
    # 1. File Created (10 pts) -> Already passed if we are here
    score += 10
    feedback.append("CSV file created")

    # 2. CSV Format/Headers (10 pts)
    required_headers = {'Bed_ID', 'Device_Type', 'Device_UDI'}
    headers_present = set()
    if csv_rows and len(csv_rows) > 0:
        keys = csv_rows[0].keys()
        headers_present = {k for k in keys if k in required_headers}
    
    if len(headers_present) == 3:
        score += 10
        feedback.append("Valid CSV headers")
    else:
        feedback.append(f"Invalid headers. Found: {list(csv_rows[0].keys()) if csv_rows else 'None'}")

    # 3. Verify Devices (20 pts per device)
    # Mapping required devices
    targets = {
        "101": {"type_regex": r"Multiparameter|Monitor", "name": "Multiparameter Monitor"},
        "102": {"type_regex": r"Pulse|Oximeter|SpO2", "name": "Pulse Oximeter"},
        "103": {"type_regex": r"Infusion|Pump", "name": "Infusion Pump"}
    }
    
    found_uuids = set()
    
    for row in csv_rows:
        bed_id = str(row.get('Bed_ID', '')).strip()
        udi = str(row.get('Device_UDI', '')).strip()
        
        # Check basic UUID format (simple regex for 36 chars with dashes)
        is_valid_uuid = bool(re.match(r'^[0-9a-fA-F-]{36}$', udi))
        
        if bed_id in targets:
            target = targets[bed_id]
            device_score = 0
            device_feedback = []

            # A. Valid UUID format
            if is_valid_uuid:
                # B. Check if UUID is in log (Proof it exists in this session)
                if udi in log_content:
                    # C. Check Type Consistency
                    # Find lines in log containing this UDI
                    log_lines = [line for line in log_content.splitlines() if udi in line]
                    # Check if any line also matches the device type
                    type_match = any(re.search(target["type_regex"], line, re.IGNORECASE) for line in log_lines)
                    
                    if type_match:
                        device_score = 20
                        found_uuids.add(udi)
                        device_feedback.append("Verified")
                    else:
                        device_score = 10 # UUID exists but type mismatch in log
                        device_feedback.append("Type mismatch in log")
                else:
                    device_score = 0
                    device_feedback.append("UUID not found in session logs")
            else:
                device_feedback.append("Invalid UUID format")
                
            score += device_score
            feedback.append(f"Bed {bed_id}: {', '.join(device_feedback)}")

    # 4. Check for Distinct UUIDs (10 pts)
    if len(found_uuids) >= 3:
        score += 10
        feedback.append("All 3 UUIDs are unique and verified")
    elif len(found_uuids) > 0:
        feedback.append(f"Found {len(found_uuids)} unique verified UUIDs")

    # 5. Check Active Windows (10 pts)
    # Expecting at least 3 device windows
    active_windows = result_data.get("active_device_windows", 0)
    if active_windows >= 3:
        score += 10
        feedback.append("Active device windows detected")
    else:
        feedback.append(f"Only {active_windows} device windows detected (expected 3)")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }