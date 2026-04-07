#!/usr/bin/env python3
"""
Verifier for active_device_session_uuid_logging task.

Verification Strategy:
1. Parse the OpenICE log tail (captured during export) to extract the "Ground Truth" UUIDs 
   of devices created during the session.
2. Parse the agent's submitted CSV file.
3. Compare the UUIDs in the CSV against the Ground Truth.
4. Verify that the requested device types (Multiparameter, Pulse Ox, Pump) are present.

Points:
- CSV file exists and has content (10 pts)
- Valid CSV format (header + rows) (10 pts)
- Multiparameter Monitor UUID match (25 pts)
- Pulse Oximeter UUID match (25 pts)
- Infusion Pump UUID match (25 pts)
- Distinct devices created (5 pts)
"""

import json
import os
import tempfile
import logging
import csv
import re

logger = logging.getLogger(__name__)

def verify_active_device_session_uuid_logging(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Retrieve Log Tail (Ground Truth)
    log_tail_path = result.get("log_tail_path", "/tmp/task_log_tail.txt")
    temp_log = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(log_tail_path, temp_log.name)
        with open(temp_log.name, 'r', errors='ignore') as f:
            log_content = f.read()
    except Exception as e:
        # If log extraction fails, we can't verify UUIDs
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve logs for verification: {e}"}
    finally:
        if os.path.exists(temp_log.name):
            os.unlink(temp_log.name)

    # 3. Retrieve Agent CSV
    output_file_path = result.get("output_file_path", "/home/ga/Desktop/active_device_inventory.csv")
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_retrieved = False
    if result.get("output_file_exists"):
        try:
            copy_from_env(output_file_path, temp_csv.name)
            csv_retrieved = True
        except Exception:
            pass

    # --- Processing Ground Truth ---
    # Extract UUIDs and Names from log
    # Pattern looks roughly like: 
    # "... Device connected: 12345678-1234-1234-1234-123456789abc ... (Multiparameter Monitor)"
    # Or just standard UUID regex near device names
    
    uuid_pattern = re.compile(r'([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})')
    
    # We map UUID -> Device Type String found in the same line (or nearby context)
    # Simple approach: Line by line, if UUID and "Monitor" are in line, assume mapping
    ground_truth = {} # UUID -> Type
    
    for line in log_content.splitlines():
        # Look for UUID
        match = uuid_pattern.search(line)
        if match:
            uuid = match.group(1).lower()
            # Determine type from line context
            line_lower = line.lower()
            d_type = "Unknown"
            if "multiparameter" in line_lower or "monitor" in line_lower:
                d_type = "Multiparameter Monitor"
            elif "pulse" in line_lower or "oximeter" in line_lower or "spo2" in line_lower:
                d_type = "Pulse Oximeter"
            elif "infusion" in line_lower or "pump" in line_lower:
                d_type = "Infusion Pump"
            
            # Add to ground truth if it looks like a device connection/creation event
            # or if we found a valid type association
            if d_type != "Unknown":
                ground_truth[uuid] = d_type

    logger.info(f"Ground Truth UUIDs found: {ground_truth}")

    # --- Scoring ---
    score = 0
    feedback_parts = []
    
    # Check CSV existence
    if not csv_retrieved:
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found"}
    
    score += 10
    feedback_parts.append("File exists")

    # Parse CSV
    agent_entries = [] # List of (Type, UUID)
    try:
        with open(temp_csv.name, 'r') as f:
            reader = csv.reader(f)
            rows = list(reader)
            if len(rows) > 0:
                # Basic header check (lenient)
                if "uuid" in rows[0][1].lower() or "device" in rows[0][0].lower():
                    score += 10
                    feedback_parts.append("Valid CSV format")
                    # data rows
                    for row in rows[1:]:
                        if len(row) >= 2:
                            agent_entries.append((row[0].strip(), row[1].strip().lower()))
                else:
                    # Maybe no header? treat all as data
                    for row in rows:
                        if len(row) >= 2:
                            agent_entries.append((row[0].strip(), row[1].strip().lower()))
    except Exception as e:
        feedback_parts.append(f"CSV Parse Error: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Matching Logic
    # We need to find: 1 Multiparameter, 1 Pulse Ox, 1 Pump
    found_types = set()
    
    # Helper to check if a specific type is matched correctly
    def check_match(target_type_keywords):
        # Find entry in agent_entries that matches this type AND exists in ground_truth
        for a_type, a_uuid in agent_entries:
            # Does agent label match target?
            is_target_label = any(k in a_type.lower() for k in target_type_keywords)
            
            if is_target_label:
                # Does UUID exist in ground truth?
                if a_uuid in ground_truth:
                    gt_type = ground_truth[a_uuid]
                    # Does ground truth type match target?
                    is_target_gt = any(k in gt_type.lower() for k in target_type_keywords)
                    
                    if is_target_gt:
                        return True, a_uuid
        return False, None

    # Check Multiparameter
    matched_multi, _ = check_match(["multiparameter", "monitor"])
    if matched_multi:
        score += 25
        found_types.add("multi")
        feedback_parts.append("Multiparameter Monitor UUID correct")
    else:
        feedback_parts.append("Multiparameter Monitor UUID incorrect or missing")

    # Check Pulse Ox
    matched_pulse, _ = check_match(["pulse", "oximeter", "spo2"])
    if matched_pulse:
        score += 25
        found_types.add("pulse")
        feedback_parts.append("Pulse Oximeter UUID correct")
    else:
        feedback_parts.append("Pulse Oximeter UUID incorrect or missing")

    # Check Infusion Pump
    matched_pump, _ = check_match(["infusion", "pump"])
    if matched_pump:
        score += 25
        found_types.add("pump")
        feedback_parts.append("Infusion Pump UUID correct")
    else:
        feedback_parts.append("Infusion Pump UUID incorrect or missing")

    # Distinct types check
    if len(found_types) == 3:
        score += 5
        feedback_parts.append("All 3 distinct types found")

    passed = score >= 60 # Requires file + format + at least 2 correct UUIDs (10+10+25+25 = 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }