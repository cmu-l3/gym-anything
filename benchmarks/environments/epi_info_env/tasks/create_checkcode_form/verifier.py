#!/usr/bin/env python3
"""
Verifier for create_checkcode_form task.

Checks:
1. Project file existence (.prj)
2. Database file existence (.mdb)
3. Schema verification (Columns present)
4. Data verification (3 records, correct values)
5. Check Code verification (ASSIGN logic found in project file)
6. VLM Verification of workflow
"""

import json
import os
import sys
import tempfile
import logging
from datetime import datetime

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM utils
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm, get_final_screenshot
except ImportError:
    # Fallback/Mock for testing outside framework
    def sample_trajectory_frames(traj, n): return []
    def get_final_screenshot(traj): return None
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}


def verify_create_checkcode_form(traj, env_info, task_info):
    """
    Verifies the Epi Info 7 form creation and data entry task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []
    
    # Get metadata expectations
    metadata = task_info.get('metadata', {})
    expected_case_ids = set(metadata.get('expected_case_ids', ["RS-0001", "RS-0002", "RS-0003"]))
    
    # 1. Retrieve Result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Programmatic Verification (60 points max)
    
    # Check Project Existence
    if result.get('project_exists'):
        score += 5
        feedback.append("Project file created.")
    else:
        feedback.append("Project file not found.")

    # Check Check Code (10 pts)
    # The Check Code is stored inside the PRJ XML. We look for 'ASSIGN' and 'Age' and 'YEARS'
    prj_content = result.get('check_code_content', '')
    if 'ASSIGN' in prj_content and 'Age' in prj_content and 'YEARS' in prj_content:
        score += 10
        feedback.append("Check Code logic (Age auto-calculation) found.")
    else:
        feedback.append("Check Code logic missing or incorrect.")

    # Check Database Existence
    if result.get('db_exists'):
        score += 5
        feedback.append("Database file created.")
    
    # Check Columns (Schema) (10 pts)
    columns = set(result.get('columns', []))
    required_cols = {'CaseID', 'FirstName', 'LastName', 'DOB', 'Age', 'Sex', 'County', 
                     'OnsetDate', 'Fever', 'Cough', 'Diagnosis', 'Hospitalized', 'Outcome'}
    # Note: Epi Info column names usually match field names.
    
    present_cols = required_cols.intersection(columns)
    if len(present_cols) >= len(required_cols) - 2: # Allow small mismatch
        score += 10
        feedback.append(f"Schema verification passed ({len(present_cols)}/{len(required_cols)} fields found).")
    else:
        feedback.append(f"Missing required fields. Found: {list(columns)}")

    # Check Data Records (20 pts)
    records = result.get('records', [])
    record_count = len(records)
    
    if record_count >= 3:
        score += 5
        feedback.append(f"Record count met ({record_count}).")
        
        # Verify Content
        found_ids = set()
        correct_diagnoses = 0
        ages_calculated = 0
        
        for rec in records:
            # Check CaseID
            cid = rec.get('CaseID')
            if cid in expected_case_ids:
                found_ids.add(cid)
            
            # Check Diagnosis match
            diag = rec.get('Diagnosis')
            if diag in ['Influenza', 'COVID-19', 'RSV']:
                correct_diagnoses += 1
                
            # Check Age Auto-calc
            # Age should be present and non-zero
            age_val = rec.get('Age')
            if age_val and str(age_val).isdigit() and int(float(age_val)) > 0:
                ages_calculated += 1
        
        if len(found_ids) == 3:
            score += 5
            feedback.append("All 3 CaseIDs found.")
            
        if correct_diagnoses >= 3:
            score += 5
            feedback.append("Diagnoses values match.")
            
        if ages_calculated >= 3:
            score += 5
            feedback.append("Age field auto-calculated successfully.")
    else:
        feedback.append(f"Insufficient records found: {record_count}/3.")

    # 3. VLM Verification (40 points max)
    # We check if the agent actually used the Form Designer and Enter modules
    
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    all_images = frames + ([final_img] if final_img else [])
    
    if all_images:
        prompt = """
        You are verifying an Epi Info 7 task. 
        The user should have:
        1. Used the 'Form Designer' to build a form (look for a grid of dots, field definitions).
        2. Used the 'Enter' module to input data (look for a data entry screen).
        3. Written Check Code (look for a code editor window with text like 'ASSIGN Age = ...').
        
        Based on these screenshots, did the agent perform these actions?
        Return JSON: {"form_design_visible": bool, "data_entry_visible": bool, "check_code_visible": bool, "confidence": float}
        """
        
        vlm_res = query_vlm(images=all_images, prompt=prompt)
        parsed = vlm_res.get('parsed', {})
        
        if parsed.get('form_design_visible'):
            score += 10
            feedback.append("VLM: Form Designer usage detected.")
        if parsed.get('data_entry_visible'):
            score += 15 # Weighted higher as it proves end-to-end flow
            feedback.append("VLM: Data Entry usage detected.")
        if parsed.get('check_code_visible'):
            score += 15
            feedback.append("VLM: Check Code editor detected.")
    else:
        feedback.append("No screenshots available for VLM verification.")

    # Final Pass/Fail
    passed = score >= 60 and result.get('project_exists') and record_count >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }