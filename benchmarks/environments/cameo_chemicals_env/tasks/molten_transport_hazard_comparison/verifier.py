#!/usr/bin/env python3
"""
Verifier for Molten Transport Hazard Comparison Task.
"""

import json
import csv
import io
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_molten_transport_hazard_comparison(traj, env_info, task_info):
    """
    Verify the CSV file content matches the expected UN and Guide numbers for solid/molten chemicals.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result metadata from export_result.sh
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # Basic Checks
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found at ~/Desktop/molten_hazards.csv"}
    
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file exists but was not created/modified during the task (anti-gaming check failed)."}

    # Load the CSV Content
    csv_path = task_result.get("output_path", "/home/ga/Desktop/molten_hazards.csv")
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(csv_path, temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            csv_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read CSV file: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Parse CSV
    rows = []
    try:
        reader = csv.reader(io.StringIO(csv_content.strip()))
        rows = list(reader)
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"File exists but is not valid CSV: {e}"}

    if len(rows) < 2:
        return {"passed": False, "score": 10, "feedback": "CSV file is empty or missing data rows."}

    # Normalize Header
    header = [h.strip().lower() for h in rows[0]]
    expected_cols = ["chemical", "solid_un", "solid_guide", "molten_un", "molten_guide"]
    
    # Check for required columns
    col_map = {}
    for col in expected_cols:
        found = False
        for i, h in enumerate(header):
            if col in h: # Fuzzy match "Solid UN" vs "Solid_UN"
                col_map[col] = i
                found = True
                break
        if not found:
            return {"passed": False, "score": 10, "feedback": f"Missing required column '{col}' in header: {rows[0]}"}

    # Evaluation Logic
    score = 10 # Base score for creating valid CSV
    feedback = []
    
    # Ground Truth Data
    gt = task_info.get("metadata", {}).get("ground_truth", {})
    
    # We need to match rows to chemicals. 
    # Logic: Look for chemical name keywords in the first column.
    
    chemicals_found = 0
    total_chemicals = 4
    
    for row in rows[1:]:
        if not row: continue
        
        # Get chemical name
        try:
            chem_name_cell = row[col_map["chemical"]].strip().lower()
        except IndexError:
            continue

        target_chem = None
        if "sulfur" in chem_name_cell:
            target_chem = "Sulfur"
        elif "naphthalene" in chem_name_cell:
            target_chem = "Naphthalene"
        elif "phenol" in chem_name_cell:
            target_chem = "Phenol"
        elif "phosphorus" in chem_name_cell:
            target_chem = "Phosphorus"
            
        if not target_chem:
            continue
            
        chemicals_found += 1
        chem_score = 0
        chem_gt = gt[target_chem]
        
        # Helper to clean and check value
        def check_val(col_key, expected_val, tolerance_list=None):
            try:
                val = row[col_map[col_key]].strip()
                # Remove common noise like "UN" prefix
                clean_val = val.replace("UN", "").replace("NA", "").strip()
                
                if clean_val == expected_val:
                    return True
                if tolerance_list and clean_val in tolerance_list:
                    return True
                return False
            except IndexError:
                return False

        # Verify Solid Data (5 pts each: UN, Guide)
        if check_val("solid_un", chem_gt["solid"]["un"]):
            chem_score += 5
        else:
            feedback.append(f"{target_chem} Solid UN mismatch")

        if check_val("solid_guide", chem_gt["solid"]["guide"]):
            chem_score += 5
        else:
            feedback.append(f"{target_chem} Solid Guide mismatch")

        # Verify Molten Data (5 pts each: UN, Guide)
        # CRITICAL PART: Molten data is distinct
        if check_val("molten_un", chem_gt["molten"]["un"]):
            chem_score += 5
        else:
            feedback.append(f"{target_chem} Molten UN mismatch")

        if check_val("molten_guide", chem_gt["molten"]["guide"]):
            chem_score += 5
        else:
            feedback.append(f"{target_chem} Molten Guide mismatch")
            
        score += chem_score

    # Final Score Calculation
    # Max score calculation: 10 (base) + 4 chemicals * 20 pts = 90.
    # Adjusting to 100 scale: 
    # Let's say header is worth 10 pts.
    # Total = 10 (file/header) + 80 (data) = 90. 
    # Bonus 10 points if all 4 chemicals found.
    
    if chemicals_found == 4:
        score += 10
    
    # Cap at 100
    score = min(100, score)
    
    # Pass threshold
    passed = score >= 70
    
    if passed:
        feedback.insert(0, "Task PASSED. Comparison table is accurate.")
    else:
        feedback.insert(0, f"Task FAILED. Score: {score}/100. Missing or incorrect values found.")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }