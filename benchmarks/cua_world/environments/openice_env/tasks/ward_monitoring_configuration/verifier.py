#!/usr/bin/env python3
"""
Verifier for Ward Monitoring Configuration task in OpenICE.

Logic:
1. Verify CSV file exists and has correct structure.
2. Verify OpenICE is running.
3. Verify specific devices were created (via log analysis).
4. CRITICAL: Verify the UDIs in the CSV match the actual UDIs in the logs.
   - This prevents the agent from just writing random IDs.
   - It requires the agent to actually find the ID in the GUI/Logs and transcribe it.
"""

import json
import os
import tempfile
import csv
import io
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ward_monitoring_configuration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    
    # 1. Basic Requirements (10 pts)
    openice_running = result.get('openice_running', False)
    if openice_running:
        score += 10
    else:
        feedback.append("OpenICE is not running.")

    csv_exists = result.get('csv_exists', False)
    csv_content = result.get('csv_content', "").strip()
    
    if not csv_exists:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "CSV file not found. " + " | ".join(feedback)
        }
    
    score += 10 # File created
    feedback.append("CSV file created.")

    # 2. Parse CSV (20 pts)
    # Expected: Bed_ID, Device_Type, UDI_Prefix
    parsed_rows = []
    try:
        reader = csv.DictReader(io.StringIO(csv_content))
        # Normalizing headers to be case-insensitive
        reader.fieldnames = [f.strip().lower() for f in (reader.fieldnames or [])]
        
        # Check required columns
        required_cols = ['bed_id', 'device_type', 'udi_prefix']
        if not all(col in reader.fieldnames for col in required_cols):
             feedback.append(f"CSV missing required columns: {required_cols}")
        else:
             score += 10
             
        for row in reader:
            parsed_rows.append(row)
            
        if len(parsed_rows) >= 3:
            score += 10
            feedback.append(f"CSV contains {len(parsed_rows)} rows.")
        else:
            feedback.append(f"CSV contains only {len(parsed_rows)} rows (expected 3).")
            
    except Exception as e:
        feedback.append(f"Failed to parse CSV: {e}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 3. Analyze Logs for Ground Truth UDIs (Logs contain the real truth)
    log_snippet = result.get('log_snippet', "")
    
    # Simple heuristic to extract UUID-like strings associated with device types from logs
    # Log lines often look like: "Created DeviceAdapter ... id=1234-5678..." or similar.
    # We will search for the prefixes provided by the agent in the logs.
    
    def check_udi_match(claimed_prefix, device_type_hint):
        """
        Returns True if the claimed_prefix is found in the logs 
        NEAR the device_type_hint.
        """
        if not claimed_prefix or len(claimed_prefix) < 4:
            return False
            
        # Case insensitive search
        cleaned_log = log_snippet.lower()
        cleaned_prefix = claimed_prefix.strip().lower()
        cleaned_type = device_type_hint.lower()
        
        # Check if prefix exists in log
        if cleaned_prefix not in cleaned_log:
            return False
            
        # Check if device type exists in log (weak check, just ensures the type was created)
        if cleaned_type == "multiparameter":
            if "multiparameter" not in cleaned_log and "monitor" not in cleaned_log:
                return False
        elif cleaned_type == "pulse oximeter":
            if "pulse" not in cleaned_log and "oximeter" not in cleaned_log:
                return False
        elif cleaned_type == "infusion pump":
            if "pump" not in cleaned_log and "infusion" not in cleaned_log:
                return False
                
        return True

    # 4. verify Specific Entries (20 pts each)
    
    # Bed 1: Multiparameter Monitor
    bed1_entry = next((r for r in parsed_rows if "bed 1" in r.get('bed_id', '').lower()), None)
    if bed1_entry:
        dtype = bed1_entry.get('device_type', '').lower()
        udi = bed1_entry.get('udi_prefix', '')
        
        if "multiparameter" in dtype or "monitor" in dtype:
            if check_udi_match(udi, "Multiparameter"):
                score += 20
                feedback.append("Bed 1 (Monitor) setup and UDI verified.")
            else:
                # Partial credit if row exists but UDI wrong/not found
                score += 5
                feedback.append(f"Bed 1 row exists, but UDI '{udi}' not found in logs for Monitor.")
        else:
            feedback.append(f"Bed 1 device type mismatch: {dtype}")
    else:
        feedback.append("Bed 1 entry missing.")

    # Bed 2: Pulse Oximeter
    bed2_pulse = next((r for r in parsed_rows if "bed 2" in r.get('bed_id', '').lower() and ("pulse" in r.get('device_type', '').lower() or "oximeter" in r.get('device_type', '').lower())), None)
    if bed2_pulse:
        udi = bed2_pulse.get('udi_prefix', '')
        if check_udi_match(udi, "Pulse Oximeter"):
            score += 20
            feedback.append("Bed 2 (Pulse Ox) setup and UDI verified.")
        else:
            score += 5
            feedback.append(f"Bed 2 (Pulse Ox) row exists, but UDI '{udi}' not found in logs.")
    else:
        feedback.append("Bed 2 Pulse Oximeter entry missing.")

    # Bed 2: Infusion Pump
    bed2_pump = next((r for r in parsed_rows if "bed 2" in r.get('bed_id', '').lower() and "pump" in r.get('device_type', '').lower()), None)
    if bed2_pump:
        udi = bed2_pump.get('udi_prefix', '')
        if check_udi_match(udi, "Infusion Pump"):
            score += 20
            feedback.append("Bed 2 (Pump) setup and UDI verified.")
        else:
            score += 5
            feedback.append(f"Bed 2 (Pump) row exists, but UDI '{udi}' not found in logs.")
    else:
        feedback.append("Bed 2 Infusion Pump entry missing.")

    # Pass Threshold
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }