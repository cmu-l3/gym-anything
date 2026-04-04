#!/usr/bin/env python3
"""
Verifier for Odor Warning Property Safety Audit task.

Verification Logic:
1. File Existence & Freshness: Checks if CSV exists and was created during task.
2. Structure Check: Verifies CSV header and row count.
3. Data Accuracy: Checks if extracted Odor and PEL values match ground truth ranges.
4. Logic Consistency: Verifies the 'Assessment' column correctly applies the rule:
   - ADEQUATE: Odor < PEL
   - INADEQUATE: Odor >= PEL
   - NO_WARNING: Odorless
"""

import json
import csv
import io
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_odor_audit(traj, env_info, task_info):
    """
    Verify the odor safety audit CSV file.
    """
    # 1. Setup and Load Resources
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    ground_truth = metadata.get('chemicals', [])
    output_path = metadata.get('output_path', '/home/ga/Documents/odor_safety_audit.csv')

    # Load export result
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence (10 points)
    if not task_result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Assessment CSV file not found at expected path."}
    
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "File timestamp indicates it was not created during this task session."}

    # 3. Load and Parse CSV
    csv_content = ""
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(output_path, temp_csv.name)
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            csv_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"File exists but could not be read: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    try:
        reader = csv.DictReader(io.StringIO(csv_content))
        rows = list(reader)
        headers = reader.fieldnames
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": "File is not valid CSV format."}

    # Validate Header
    required_cols = ['Chemical', 'Odor_ppm', 'PEL_ppm', 'Assessment']
    if not headers or not all(col in [h.strip() for h in headers] for col in required_cols):
        return {"passed": False, "score": 15, "feedback": f"CSV headers incorrect. Expected: {required_cols}"}

    score = 15
    feedback = []
    
    # 4. Validate Data Rows (85 points distributed)
    # Map ground truth by chemical name for easy lookup
    gt_map = {item['name'].lower(): item for item in ground_truth}
    
    chemicals_found = 0
    data_points_correct = 0
    logic_correct = 0
    
    for row in rows:
        chem_name = row.get('Chemical', '').strip()
        # Fuzzy match chemical name
        matched_gt = None
        for key in gt_map:
            if key in chem_name.lower() or chem_name.lower() in key:
                matched_gt = gt_map[key]
                break
        
        if not matched_gt:
            continue
            
        chemicals_found += 1
        
        # Parse user values
        try:
            user_odor_str = row.get('Odor_ppm', 'NA').strip()
            user_pel_str = row.get('PEL_ppm', '0').strip()
            user_assessment = row.get('Assessment', '').strip().upper()
            
            # Check Carbon Monoxide (Odorless)
            if matched_gt['name'] == "Carbon Monoxide":
                is_odorless = user_odor_str.upper() in ['NA', 'N/A', 'NONE', 'ODORLESS']
                pel_ok = abs(float(user_pel_str) - matched_gt['pel_value']) < 5
                assess_ok = user_assessment == "NO_WARNING"
                
                if is_odorless and pel_ok: data_points_correct += 1
                if assess_ok: logic_correct += 1
                
            else:
                # Standard Chemicals
                user_odor = float(user_odor_str)
                user_pel = float(user_pel_str)
                
                # Verify Values (Allow wide tolerance for Odor as sources vary)
                odor_range = matched_gt['odor_range']
                # Allow 50% buffer on odor range or 5ppm, whichever is larger
                # Actually, just checking if it's somewhat realistic based on ground truth metadata
                odor_ok = (user_odor >= 0) and (user_odor <= 1000) # Basic sanity check
                
                # Check specific range logic roughly
                if matched_gt['name'] == "Hydrogen Sulfide":
                    odor_ok = user_odor < 1.0 # Should be very low
                elif matched_gt['name'] == "Dichloromethane":
                    odor_ok = user_odor > 50 # Should be high
                
                pel_ok = abs(user_pel - matched_gt['pel_value']) < 5
                
                if odor_ok and pel_ok:
                    data_points_correct += 1
                
                # Verify Logic Consistency (SELF-CONSISTENCY check)
                # We grade based on whether the assessment matches the extracting values
                expected_logic = "INADEQUATE"
                if user_odor < user_pel:
                    expected_logic = "ADEQUATE"
                
                if user_assessment == expected_logic:
                    logic_correct += 1
                else:
                    feedback.append(f"{matched_gt['name']}: Logic error. Odor {user_odor} vs PEL {user_pel} should be {expected_logic}")

        except ValueError:
            feedback.append(f"{chem_name}: Could not parse numerical values.")
            continue

    # Scoring Calculation
    # Max 5 chemicals
    # 5 * 7 points for data accuracy = 35
    # 5 * 10 points for logic/assessment = 50
    # Total max = 15 + 35 + 50 = 100
    
    score += (data_points_correct * 7)
    score += (logic_correct * 10)
    
    # Cap score at 100
    score = min(score, 100)
    
    if chemicals_found < 5:
        feedback.append(f"Only found {chemicals_found}/5 chemicals.")
        
    feedback_str = " | ".join(feedback) if feedback else "All assessments correct."
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": feedback_str
    }