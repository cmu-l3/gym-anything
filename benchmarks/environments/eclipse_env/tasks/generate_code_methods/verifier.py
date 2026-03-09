#!/usr/bin/env python3
"""
Verifier for generate_code_methods task.

Scores based on:
1. File Modification (Anti-gaming)
2. Compilation Success
3. JUnit Test Results
4. Source Code Analysis (Regex check for required methods)
5. VLM Trajectory Verification
"""

import json
import tempfile
import os
import re
import logging
import sys

# Add utils to path to import Eclipse utilities
sys.path.insert(0, '/workspace')
from utils.eclipse_verification_utils import vlm_verify_eclipse_task

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_code_methods(traj, env_info, task_info):
    """
    Verify the code generation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    required_methods = metadata.get('required_methods', [])

    # Initialize score components
    score = 0
    feedback_parts = []
    
    # --- 1. Load Exported Result (Execution Checks) ---
    task_result = {}
    try:
        temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            task_result = json.load(f)
        os.unlink(temp_res.name)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
        feedback_parts.append("Failed to retrieve task execution results")

    # Score: File Modified (5 pts)
    if task_result.get("file_modified", False):
        score += 5
        feedback_parts.append("File modified")
    else:
        feedback_parts.append("File NOT modified")

    # Score: Compilation (10 pts)
    if task_result.get("compile_success", False):
        score += 10
        feedback_parts.append("Compilation success")
    else:
        feedback_parts.append("Compilation failed")

    # Score: Tests (25 pts)
    tests_passed = task_result.get("tests_passed", 0)
    tests_run = task_result.get("tests_run", 0)
    
    if tests_run > 0:
        # Scale 25 points based on pass rate
        test_score = int((tests_passed / 5.0) * 25)
        test_score = min(25, test_score) # Cap at 25
        score += test_score
        feedback_parts.append(f"Tests passed: {tests_passed}/5 (+{test_score} pts)")
    else:
        feedback_parts.append("No tests run")

    # --- 2. Source Code Analysis (40 pts) ---
    # Check if specific methods were actually generated in the code
    employee_source = ""
    try:
        temp_src = tempfile.NamedTemporaryFile(delete=False, suffix='.java')
        copy_from_env("/home/ga/eclipse-workspace/EmployeeModel/src/main/java/com/example/model/Employee.java", temp_src.name)
        with open(temp_src.name, 'r') as f:
            employee_source = f.read()
        os.unlink(temp_src.name)
    except Exception as e:
        logger.error(f"Failed to read source file: {e}")
    
    if employee_source:
        # Check Constructor (10 pts)
        # Look for public Employee(String ..., String ..., int ..., String ..., double ...)
        # Using a loose regex to allow for formatting variations
        if re.search(r'public\s+Employee\s*\(\s*String\s+\w+,\s*String\s+\w+,\s*int\s+\w+,\s*String\s+\w+,\s*double\s+\w+\s*\)', employee_source):
            score += 10
            feedback_parts.append("Constructor found")
        else:
            feedback_parts.append("Full constructor not found")

        # Check Getters (10 pts - 2 pts each)
        getters = ["getFirstName", "getLastName", "getEmployeeId", "getDepartment", "getSalary"]
        getters_found = sum(1 for m in getters if m in employee_source)
        score += (getters_found * 2)
        if getters_found < 5:
            feedback_parts.append(f"Getters missing: {5 - getters_found}")

        # Check Setters (10 pts - 2 pts each)
        setters = ["setFirstName", "setLastName", "setEmployeeId", "setDepartment", "setSalary"]
        setters_found = sum(1 for m in setters if m in employee_source)
        score += (setters_found * 2)
        if setters_found < 5:
            feedback_parts.append(f"Setters missing: {5 - setters_found}")
            
        # Check toString (5 pts)
        if "toString" in employee_source and "@Override" in employee_source:
            score += 5
            feedback_parts.append("toString found")

        # Check hashCode/equals (5 pts)
        if "hashCode" in employee_source and "equals" in employee_source:
            score += 5
            feedback_parts.append("hashCode/equals found")
    else:
        feedback_parts.append("Could not read source code for analysis")

    # --- 3. VLM Verification (20 pts) ---
    vlm_checklist = [
        "Eclipse IDE is visible",
        "The Source menu (or right-click Source context menu) is visible/open",
        "Generate Constructor/Getters/Setters dialogs are visible",
        "The JUnit test runner view (green/red bar) is visible"
    ]
    
    vlm_result = vlm_verify_eclipse_task(
        traj=traj,
        env_info=env_info,
        task_description="Generate Java methods using Eclipse Source menu",
        checklist_items=vlm_checklist
    )
    
    if vlm_result:
        # Scale VLM score (0-100) to max 20 points
        vlm_points = int((vlm_result.get('vlm_score', 0) / 100.0) * 20)
        score += vlm_points
        feedback_parts.append(f"VLM: {vlm_result.get('vlm_feedback')} (+{vlm_points} pts)")
    else:
        feedback_parts.append("VLM verification failed")

    # --- Final Result ---
    # Cap score at 100
    score = min(100, score)
    
    # Pass threshold: 60 points (Requires at least basic generation and compilation)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }