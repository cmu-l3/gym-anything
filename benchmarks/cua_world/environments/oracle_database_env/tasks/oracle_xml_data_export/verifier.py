#!/usr/bin/env python3
"""
Verifier for oracle_xml_data_export task.

Scoring Breakdown (100 pts total):

1. Organizational Structure XML File (40 pts)
   - File exists: 5 pts
   - File created/modified during task: 5 pts
   - Valid XML format: 5 pts
   - Root tag <organization>: 3 pts
   - Department count (11 expected): 7 pts
   - Employee count (106-107 expected): 5 pts
   - Required attributes/fields present: 10 pts

2. Compensation Feed XML File (30 pts)
   - File exists: 5 pts
   - File created/modified during task: 5 pts
   - Valid XML format: 5 pts
   - Job count (19 expected): 5 pts
   - Required fields present: 10 pts

3. PL/SQL Function (30 pts)
   - Function exists: 5 pts
   - Function status VALID: 10 pts
   - Function execution successful: 10 pts
   - Function returns correct data (employee count check): 5 pts

Pass threshold: 55 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_oracle_xml_data_export(traj, env_info, task_info):
    """
    Verifies that the agent generated correct XML files and created the requested PL/SQL function.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "score": 0.0,
            "passed": False,
            "feedback": "copy_from_env not available"
        }

    # Retrieve result JSON from container
    with tempfile.TemporaryDirectory() as tmpdir:
        result_path = os.path.join(tmpdir, "result.json")
        try:
            copy_from_env("/tmp/oracle_xml_export_result.json", result_path)
            if not os.path.exists(result_path):
                return {"score": 0, "passed": False, "feedback": "Result file not found via copy_from_env"}
            
            with open(result_path, "r") as f:
                result = json.load(f)
        except Exception as e:
            return {"score": 0, "passed": False, "feedback": f"Error retrieving/parsing result: {e}"}

    score = 0
    feedback_parts = []

    # --- 1. Organization File Verification (40 pts) ---
    if result.get("org_file_exists"):
        score += 5
        if result.get("org_file_created_during_task"):
            score += 5
        else:
            feedback_parts.append("Org file timestamp too old")
            
        if result.get("org_file_valid_xml"):
            score += 5
            
            # Root tag
            if result.get("org_root_tag") == "organization":
                score += 3
            else:
                feedback_parts.append(f"Org root tag mismatch: {result.get('org_root_tag')}")
            
            # Counts
            dept_count = result.get("org_dept_count", 0)
            if 10 <= dept_count <= 12: # Expect 11, allow small variance
                score += 7
            else:
                feedback_parts.append(f"Org dept count incorrect: {dept_count} (expected 11)")
                
            emp_count = result.get("org_emp_count", 0)
            if emp_count >= 100: # Expect ~107
                score += 5
            else:
                feedback_parts.append(f"Org emp count low: {emp_count}")
                
            # Attributes
            if result.get("org_attributes_ok"):
                score += 10
            else:
                feedback_parts.append("Org XML missing required attributes/fields")
                
        else:
            feedback_parts.append("Org file is invalid XML")
    else:
        feedback_parts.append("Org structure XML file missing")

    # --- 2. Compensation File Verification (30 pts) ---
    if result.get("comp_file_exists"):
        score += 5
        if result.get("comp_file_created_during_task"):
            score += 5
        
        if result.get("comp_file_valid_xml"):
            score += 5
            
            job_count = result.get("comp_job_count", 0)
            if 15 <= job_count <= 25: # Expect 19
                score += 5
            else:
                feedback_parts.append(f"Comp job count incorrect: {job_count} (expected 19)")
                
            if result.get("comp_fields_ok"):
                score += 10
            else:
                feedback_parts.append("Comp XML missing required fields")
        else:
            feedback_parts.append("Comp file is invalid XML")
    else:
        feedback_parts.append("Compensation XML file missing")

    # --- 3. PL/SQL Function Verification (30 pts) ---
    if result.get("function_exists"):
        score += 5
        if result.get("function_status") == "VALID":
            score += 10
            
            if result.get("function_test_result") == "SUCCESS":
                score += 10
                
                # Check data returned by function (Dept 60 IT has 5 employees)
                func_emp_count = result.get("function_test_emp_count", 0)
                if func_emp_count == 5:
                    score += 5
                else:
                    feedback_parts.append(f"Function returned wrong emp count for Dept 60: {func_emp_count}")
            else:
                feedback_parts.append(f"Function execution failed: {result.get('function_test_result')}")
        else:
            feedback_parts.append(f"Function exists but status is {result.get('function_status')}")
    else:
        feedback_parts.append("PL/SQL function GENERATE_DEPT_XML not found")

    # Final verdict
    passed = score >= 55
    feedback = " | ".join(feedback_parts) if feedback_parts else "All criteria met perfectly."
    
    return {
        "score": score,
        "passed": passed,
        "feedback": feedback
    }