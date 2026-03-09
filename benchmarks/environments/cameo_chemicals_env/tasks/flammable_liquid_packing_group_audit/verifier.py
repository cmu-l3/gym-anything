#!/usr/bin/env python3
"""
Verifier for Flammable Liquid Packing Group Audit.
Checks if the agent correctly researched chemical properties and applied DOT classification rules.
"""

import json
import os
import csv
import logging
import tempfile
import io

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_packing_group_audit(traj, env_info, task_info):
    """
    Verifies the CSV report for correct chemical properties and Packing Group assignment.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_chemicals = metadata.get('chemicals', {})
    tolerance_bp = metadata.get('tolerance_bp', 10)
    tolerance_fp = metadata.get('tolerance_fp', 10)
    output_path = metadata.get('output_file', '/home/ga/Documents/packing_group_audit.csv')

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON (from export_result.sh)
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task execution stats"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check Anti-Gaming (File created during task)
    if not task_result.get('file_created_during_task', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Output file was not created or modified during the task session."
        }

    # 2. Retrieve and Parse CSV File
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(output_path, temp_csv.name)
        with open(temp_csv.name, 'r', newline='') as csvfile:
            # Read all content to handle potential BOM or weird encoding
            content = csvfile.read()
            # Normalize newlines
            content = content.replace('\r\n', '\n').replace('\r', '\n')
            
            # Check for header
            if "Chemical" not in content or "Packing_Group" not in content:
                return {"passed": False, "score": 10, "feedback": "CSV file missing required headers."}
            
            reader = csv.DictReader(io.StringIO(content))
            rows = list(reader)
    except Exception as e:
        logger.error(f"Failed to read CSV: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not read or parse the output CSV file."}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 3. Verify Content
    if not rows:
        return {"passed": False, "score": 0, "feedback": "CSV file is empty."}

    # Normalize keys (handle case sensitivity or whitespace in headers)
    normalized_rows = []
    for row in rows:
        new_row = {}
        for k, v in row.items():
            if k:
                # Map headers to standard keys
                key_lower = k.lower().strip()
                if "chemical" in key_lower: new_row["name"] = v
                elif "boiling" in key_lower: new_row["bp"] = v
                elif "flash" in key_lower: new_row["fp"] = v
                elif "packing" in key_lower: new_row["pg"] = v
        normalized_rows.append(new_row)

    # Scoring Logic
    # 4 chemicals * (5 pts BP + 5 pts FP + 10 pts PG) = 80 pts
    # Base score for file existence/format = 20 pts
    score += 20
    
    chemicals_found = 0
    properties_correct = 0
    logic_correct = 0

    for expected_name, expected_data in expected_chemicals.items():
        # Find matching row
        matched_row = None
        for row in normalized_rows:
            if expected_name.lower() in row.get("name", "").lower():
                matched_row = row
                break
        
        if not matched_row:
            feedback_parts.append(f"Missing chemical: {expected_name}")
            continue

        chemicals_found += 1
        
        # Verify BP
        try:
            # clean value (remove units if present)
            bp_val = float(''.join(c for c in matched_row.get("bp", "0") if c.isdigit() or c in '.-'))
            if abs(bp_val - expected_data["bp"]) <= tolerance_bp:
                score += 5
            else:
                feedback_parts.append(f"{expected_name} BP incorrect (got {bp_val}, expected ~{expected_data['bp']})")
        except ValueError:
            feedback_parts.append(f"{expected_name} BP invalid format")

        # Verify FP
        try:
            fp_val = float(''.join(c for c in matched_row.get("fp", "0") if c.isdigit() or c in '.-'))
            if abs(fp_val - expected_data["fp"]) <= tolerance_fp:
                score += 5
            else:
                feedback_parts.append(f"{expected_name} FP incorrect (got {fp_val}, expected ~{expected_data['fp']})")
        except ValueError:
            feedback_parts.append(f"{expected_name} FP invalid format")

        # Verify Packing Group (Case insensitive, handle 'PG I', 'I', 'Group I')
        agent_pg = matched_row.get("pg", "").upper()
        expected_pg = expected_data["pg"]
        
        # Check if the expected roman numeral is in the agent's string
        # e.g. "I" in "PG I" -> True. But "I" in "III" -> True (Problem).
        # Better: Strict mapping or regex
        clean_pg = ""
        if "III" in agent_pg: clean_pg = "III"
        elif "II" in agent_pg: clean_pg = "II"
        elif "I" in agent_pg: clean_pg = "I"
        
        if clean_pg == expected_pg:
            score += 10
        else:
            feedback_parts.append(f"{expected_name} Packing Group incorrect (got {agent_pg}, expected {expected_pg})")

    # 4. Final Score Calculation
    feedback = " | ".join(feedback_parts) if feedback_parts else "All data and classifications correct."
    
    # Optional VLM check (Logic: did they actually visit the pages?)
    # Since we have strong programmatic verification here (values), VLM is secondary but good for confirming method.
    # We'll skip complex VLM logic here to keep verifier robust and focused on the outcome, 
    # as correct numbers imply correct research.
    
    passed = (score >= 80) and (chemicals_found == 4)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }