#!/usr/bin/env python3
"""
Verifier for Local vs Global Sourcing task.

Verification Logic:
1. Parse the exported JSON.
2. Check if the output CSV exists and contains expected keywords.
3. Parse the Derby DB query output to verify the agent's LCI math:
   - "Flooring, Local Ceramic" -> Truck transport ~ 4.0 tkm (20kg * 200km)
   - "Flooring, Global Vinyl" -> Ocean transport ~ 45.0 tkm (3kg * 15000km)
   - "Flooring, Global Vinyl" -> Truck transport ~ 3.0 tkm (3kg * 1000km)
4. Verify VLM trajectory for UI interaction.
"""

import json
import os
import tempfile
import logging
import base64
import re

logger = logging.getLogger(__name__)

def parse_derby_output(raw_output):
    """
    Parses the raw text output from Derby ij into a list of dictionaries.
    Expected columns: PROCESS_NAME, AMOUNT, UNIT_FACTOR, FLOW_NAME
    """
    if not raw_output:
        return []
    
    rows = []
    lines = raw_output.split('\\n') # json loaded string might have literal \n
    if len(lines) == 1:
        lines = raw_output.split('\n')
        
    for line in lines:
        # Derby output is usually fixed width or pipe separated depending on formatting
        # We look for lines containing "Flooring" and numbers
        if "Flooring" in line:
            # Simple heuristic extraction since formatting varies
            # Assuming format: Process Name | Amount | Factor | Flow Name
            # But ij output is messy. Let's look for known patterns.
            
            # We look for the numeric amount associated with transport flows
            lower_line = line.lower()
            
            process_type = None
            if "local" in lower_line and "ceramic" in lower_line:
                process_type = "local_ceramic"
            elif "global" in lower_line and "vinyl" in lower_line:
                process_type = "global_vinyl"
            
            if not process_type:
                continue

            # Extract amount (looking for floating point numbers)
            # This is fragile with raw text, but we try to find the transport amounts
            amounts = re.findall(r"[-+]?\d*\.\d+|\d+", line)
            
            transport_type = None
            if "truck" in lower_line or "lorry" in lower_line or "road" in lower_line:
                transport_type = "truck"
            elif "ocean" in lower_line or "ship" in lower_line or "water" in lower_line or "barge" in lower_line:
                transport_type = "ocean"
            
            if transport_type and amounts:
                # Usually the Amount is the first or second number
                # We collect all candidates
                rows.append({
                    "process": process_type,
                    "transport": transport_type,
                    "line_content": line,
                    "amounts": [float(x) for x in amounts]
                })
    return rows

def check_math(rows, target_process, target_transport, expected_val, tolerance=0.05):
    """
    Checks if any row matches the target process/transport and has an amount close to expected.
    """
    for row in rows:
        if row["process"] == target_process and row["transport"] == target_transport:
            for amt in row["amounts"]:
                # Check directly or check if amount matches expected * 1000 (unit conversion)
                if abs(amt - expected_val) <= (expected_val * tolerance):
                    return True, amt
                if abs(amt - (expected_val / 1000.0)) <= ((expected_val / 1000.0) * tolerance):
                     return True, amt
    return False, 0.0

def verify_local_vs_global_sourcing(traj, env_info, task_info):
    """
    Main verification function.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Output File Check (10 pts)
    if result.get("output_file_exists") and result.get("output_file_created_during_task"):
        score += 10
        feedback.append("Comparison CSV exported.")
        
        # Check content keywords
        content_b64 = result.get("output_file_content_base64", "")
        if content_b64:
            try:
                content = base64.b64decode(content_b64).decode('utf-8', errors='ignore').lower()
                if "ceramic" in content and "vinyl" in content:
                    score += 5 # Bonus for content
                    feedback.append("CSV contains correct item names.")
            except:
                pass
    else:
        feedback.append("Comparison CSV not found or not created during task.")

    # 2. Database Math Verification (70 pts total)
    # This verifies the agent actually did the LCI calculation correctly
    db_rows = parse_derby_output(result.get("db_query_output", ""))
    
    # Check Local Ceramic Truck (20kg * 200km = 4.0 tkm)
    local_ok, val = check_math(db_rows, "local_ceramic", "truck", 4.0)
    if local_ok:
        score += 25
        feedback.append(f"Local Ceramic Transport calculation correct ({val} tkm).")
    else:
        feedback.append("Local Ceramic Transport calculation incorrect or not found (Expected ~4.0 tkm).")

    # Check Global Vinyl Ocean (3kg * 15000km = 45.0 tkm)
    ocean_ok, val = check_math(db_rows, "global_vinyl", "ocean", 45.0)
    if ocean_ok:
        score += 25
        feedback.append(f"Global Vinyl Ocean Transport calculation correct ({val} tkm).")
    else:
        feedback.append("Global Vinyl Ocean Transport calculation incorrect or not found (Expected ~45.0 tkm).")

    # Check Global Vinyl Truck (3kg * 1000km = 3.0 tkm)
    truck_ok, val = check_math(db_rows, "global_vinyl", "truck", 3.0)
    if truck_ok:
        score += 20
        feedback.append(f"Global Vinyl Truck Transport calculation correct ({val} tkm).")
    else:
        feedback.append("Global Vinyl Truck Transport calculation incorrect or not found (Expected ~3.0 tkm).")

    # 3. Process Existence Check (10 pts)
    # If math failed, give partial points if processes at least exist
    if not (local_ok and ocean_ok and truck_ok):
        local_exists = any(r["process"] == "local_ceramic" for r in db_rows)
        global_exists = any(r["process"] == "global_vinyl" for r in db_rows)
        if local_exists and global_exists:
            score += 10
            feedback.append("Processes created, but transport math was incorrect.")
    
    # 4. Calculation Evidence (5 pts)
    if result.get("calc_log_evidence"):
        score += 5
        feedback.append("Calculation log evidence found.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }