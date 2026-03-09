#!/usr/bin/env python3
"""
Verifier for add_employee_experience task.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import VLM utils if available in the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback/Mock for standalone testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, image=None, images=None): return {"success": False}


def verify_add_employee_experience(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that employee experience records were added correctly.
    
    Strategy:
    1. Check if database file was modified (basic anti-gaming).
    2. Check if export script found records in DB (if SQL schema matched).
    3. PRIMARY: Use VLM on trajectory to verify the data entry steps.
       This is robust against DB schema mismatch/access issues.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_records = metadata.get('expected_records', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Parse JSON result from Windows container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        # Windows path in container is C:\workspace\task_result.json
        # Docker cp handles the path translation usually, or we use the path mapped in env
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
        feedback_parts.append("Could not retrieve system state.")
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Database Modification Check (15 pts)
    # Even if we can't read the rows, the file mtime changes on save.
    db_modified = result.get('db_modified_during_task', False)
    if db_modified:
        score += 15
        feedback_parts.append("Database updated successfully.")
    else:
        feedback_parts.append("No changes detected in database file.")

    # 3. DB Record Count (15 pts)
    # If our SQL query worked
    db_count = result.get('records_count_db', 0)
    if db_count >= 2:
        score += 15
        feedback_parts.append(f"Found {db_count} experience records in database.")
    elif db_count > 0:
        score += 10
        feedback_parts.append(f"Found partial records ({db_count}).")

    # 4. VLM Verification (70 pts)
    # Since visual confirmation of the specific values is critical
    
    # A. Process Verification (Did they navigate and type?)
    frames = sample_trajectory_frames(traj, n=8)
    process_prompt = """
    Analyze these screenshots of a user interacting with AttendHRM.
    Did the user:
    1. Open an employee record (Rajesh Kumar)?
    2. Navigate to the 'Experience' or 'Previous Employment' tab?
    3. Enter data for 'Tata Consultancy Services' and 'Infosys'?
    
    Return JSON: {"navigated_to_employee": bool, "found_experience_tab": bool, "entered_company_names": bool}
    """
    
    process_result = query_vlm(prompt=process_prompt, images=frames)
    process_data = process_result.get('parsed', {}) if process_result.get('success') else {}
    
    if process_data.get('navigated_to_employee'): score += 10
    if process_data.get('found_experience_tab'): score += 10
    if process_data.get('entered_company_names'): score += 10

    # B. Content Verification (Final State)
    final_img = get_final_screenshot(traj)
    content_prompt = """
    Analyze this screenshot of the AttendHRM Experience/Employment History tab.
    
    I am looking for two entries:
    1. Company: Tata Consultancy Services, Designation: Senior Software Engineer, Year: 2018-2022
    2. Company: Infosys Limited, Designation: Software Engineer, Year: 2015-2018
    
    Assess if these records are visible in the list.
    
    Return JSON:
    {
        "tcs_record_visible": bool,
        "infosys_record_visible": bool,
        "values_match_expectations": bool,
        "feedback": "string"
    }
    """
    
    content_result = query_vlm(prompt=content_prompt, image=final_img)
    content_data = content_result.get('parsed', {}) if content_result.get('success') else {}
    
    if content_data.get('tcs_record_visible'): score += 20
    if content_data.get('infosys_record_visible'): score += 20
    
    if content_data.get('feedback'):
        feedback_parts.append(f"Visual check: {content_data['feedback']}")

    # Pass/Fail logic
    # Need at least 60 points AND clear visual evidence of data entry
    passed = score >= 60 and (content_data.get('tcs_record_visible') or content_data.get('infosys_record_visible'))
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }