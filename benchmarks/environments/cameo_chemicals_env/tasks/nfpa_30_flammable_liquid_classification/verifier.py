#!/usr/bin/env python3
"""
Verifier for nfpa_30_flammable_liquid_classification task.
Verifies the CSV output containing Flash Points, Boiling Points, and NFPA 30 Classes.
"""

import json
import csv
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nfpa_30_flammable_liquid_classification(traj, env_info, task_info):
    """
    Verify that the agent correctly identified properties and classified chemicals.
    
    Scoring:
    - File existence & creation: 10 pts
    - Structure (headers): 10 pts
    - Data accuracy (per chemical):
      - Flash Point: 3 pts
      - Boiling Point: 3 pts
      - Classification: 8 pts
      - Total per chemical: 14 pts approx -> Normalized to total score
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('ground_truth', [])
    tolerance = metadata.get('tolerance_degrees', 10)
    expected_output_path = metadata.get('expected_output_path', "/home/ga/Documents/flammable_liquid_classes.csv")

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load Task Result Metadata
    temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_meta.name):
            os.unlink(temp_meta.name)
            
    # 2. Check File Existence and Creation
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file was not created."}
    
    if not task_result.get('file_created_during_task', False):
         return {"passed": False, "score": 0, "feedback": "Output file timestamp indicates it was not created during the task."}
         
    score += 10
    feedback_parts.append("File created successfully")

    # 3. Retrieve and Parse CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(expected_output_path, temp_csv.name)
        
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            # Read all lines to handle potential empty lines or format issues
            lines = [line.strip() for line in f if line.strip()]
            
        if not lines:
            return {"passed": False, "score": score, "feedback": "CSV file is empty."}
            
        reader = csv.DictReader(lines)
        headers = reader.fieldnames if reader.fieldnames else []
        
        # Check headers (allowing case-insensitive or partial matching if needed, but strict is better for code)
        # Expected: Chemical Name, Flash Point (F), Boiling Point (F), NFPA 30 Class
        required_headers = ["Chemical Name", "Flash Point (F)", "Boiling Point (F)", "NFPA 30 Class"]
        header_map = {}
        
        # Simple fuzzy matching for headers to be lenient
        for req in required_headers:
            match = None
            for h in headers:
                if req.lower() in h.lower():
                    match = h
                    break
            if match:
                header_map[req] = match
            else:
                feedback_parts.append(f"Missing header: {req}")
        
        if len(header_map) == len(required_headers):
            score += 10
        else:
            # Penalize but try to continue if we can guess columns by index? 
            # For now, if headers are missing, we might fail row parsing.
            pass

        rows = list(reader)
        
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse CSV file: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 4. Validate Data against Ground Truth
    # Map rows by chemical name
    agent_data = {}
    for row in rows:
        # Find the column that corresponds to 'Chemical Name'
        name_col = header_map.get("Chemical Name")
        if name_col and row.get(name_col):
            chem_name = row[name_col].strip().lower()
            agent_data[chem_name] = row

    # Points remaining: 80. Distributed among 6 chemicals ~= 13.3 pts each
    # Breakdown: 3 pts Flash, 3 pts Boiling, 7.3 pts Class
    
    chemicals_passed = 0
    
    for item in ground_truth:
        gt_name = item['name']
        gt_name_lower = gt_name.lower()
        
        if gt_name_lower not in agent_data:
            feedback_parts.append(f"Missing chemical: {gt_name}")
            continue
            
        row = agent_data[gt_name_lower]
        chem_score = 0
        
        # Helper to parse number
        def parse_temp(val):
            try:
                # Remove non-numeric chars except minus and dot
                cleaned = "".join(c for c in val if c.isdigit() or c in ".-")
                return float(cleaned)
            except:
                return None

        # Check Flash Point
        fp_col = header_map.get("Flash Point (F)")
        agent_fp = parse_temp(row.get(fp_col, ""))
        if agent_fp is not None and abs(agent_fp - item['flash_point']) <= tolerance:
            chem_score += 3
        else:
            feedback_parts.append(f"{gt_name}: Incorrect Flash Point (Exp ~{item['flash_point']}, Got {row.get(fp_col)})")

        # Check Boiling Point
        bp_col = header_map.get("Boiling Point (F)")
        agent_bp = parse_temp(row.get(bp_col, ""))
        if agent_bp is not None and abs(agent_bp - item['boiling_point']) <= tolerance:
            chem_score += 3
        else:
            feedback_parts.append(f"{gt_name}: Incorrect Boiling Point (Exp ~{item['boiling_point']}, Got {row.get(bp_col)})")

        # Check Class
        cls_col = header_map.get("NFPA 30 Class")
        agent_cls = row.get(cls_col, "").strip()
        # Normalize class string (remove 'Class', spaces, case)
        def normalize_class(s):
            return s.upper().replace("CLASS", "").strip()
            
        if normalize_class(agent_cls) == normalize_class(item['class']):
            chem_score += 7.33  # Approx remaining points
        else:
            feedback_parts.append(f"{gt_name}: Incorrect Class (Exp {item['class']}, Got {agent_cls})")

        score += chem_score
        if chem_score > 10: # Passed most criteria for this chemical
            chemicals_passed += 1

    score = min(round(score), 100) # Cap at 100 and round
    
    passed = score >= 80 and chemicals_passed >= 5
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }