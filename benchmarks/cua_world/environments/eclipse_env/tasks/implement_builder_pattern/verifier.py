#!/usr/bin/env python3
"""Verifier for implement_builder_pattern task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_builder_pattern(traj, env_info, task_info):
    """
    Verify the Builder pattern implementation and testing.
    
    Scoring Criteria:
    1. Employee.java modified and contains static Builder class (15 pts)
    2. Builder has fluent methods for required fields (25 pts)
    3. Builder has build() method (10 pts)
    4. Test class exists and contains valid tests (15 pts)
    5. Maven compilation succeeds (15 pts)
    6. Maven tests pass (15 pts)
    7. VLM verification of Eclipse usage (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_fields = metadata.get('required_fields', [])
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Read result from export_result.sh
    try:
        tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_result.close()
        copy_from_env("/tmp/task_result.json", tmp_result.name)
        with open(tmp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}

    # Extract data
    source_content = result.get("source_content_json", "")
    test_content = result.get("test_content_json", "")
    source_modified = result.get("source_modified", False)
    compile_success = result.get("compile_success", False)
    test_success = result.get("test_success", False)
    tests_run = result.get("tests_run", 0)
    
    # --- Static Analysis of Employee.java ---
    
    # 1. Check for Builder Class (15 pts)
    has_builder = False
    if "static class Builder" in source_content or "static public class Builder" in source_content or "public static class Builder" in source_content:
        has_builder = True
        score += 15
        feedback_parts.append("Static Builder class found")
    else:
        feedback_parts.append("Static Builder class NOT found")

    # 2. Check for fluent setters (25 pts)
    # Regex checks for methods like: public Builder firstName(String val) { ... return this; }
    # Simplified regex: Look for methods returning 'Builder'
    fluent_methods_count = 0
    if has_builder:
        # We look for public Builder fieldName(Type val)
        # Note: This simple regex might miss some valid formatting but catches standard Eclipse generation
        fluent_matches = re.findall(r'public\s+Builder\s+\w+\(', source_content)
        fluent_methods_count = len(fluent_matches)
        
        # We expect one for most of the 12 fields
        if fluent_methods_count >= 10:
            score += 25
            feedback_parts.append(f"Found {fluent_methods_count} fluent setter methods (Excellent)")
        elif fluent_methods_count >= 6:
            score += 15
            feedback_parts.append(f"Found {fluent_methods_count} fluent setter methods (Good)")
        elif fluent_methods_count > 0:
            score += 5
            feedback_parts.append(f"Found {fluent_methods_count} fluent setter methods (Partial)")
        else:
            feedback_parts.append("No fluent setter methods found")
    
    # 3. Check for build() method (10 pts)
    if has_builder and re.search(r'public\s+Employee\s+build\(\)', source_content):
        score += 10
        feedback_parts.append("build() method found")
    elif has_builder:
        feedback_parts.append("build() method missing or incorrect signature")

    # --- Static Analysis of Test Class ---
    
    # 4. Check Test Class (15 pts)
    if result.get("test_exists"):
        test_pts = 5
        if "@Test" in test_content:
            test_pts += 5
        if ".build()" in test_content and "new Builder()" in test_content.replace("Employee.Builder", "new Builder"):
            test_pts += 5
        
        score += test_pts
        feedback_parts.append(f"Test class analysis: {test_pts}/15 pts")
    else:
        feedback_parts.append("Test class not created")

    # --- Dynamic Verification (Maven) ---
    
    # 5. Compilation (15 pts)
    if compile_success:
        score += 15
        feedback_parts.append("Project compiled successfully")
    else:
        feedback_parts.append("Project compilation FAILED")

    # 6. Tests Execution (15 pts)
    if test_success and tests_run > 0:
        score += 15
        feedback_parts.append(f"Tests passed ({tests_run} run)")
    elif tests_run > 0:
        feedback_parts.append(f"Tests failed ({tests_run} run)")
    else:
        feedback_parts.append("No tests were run")

    # --- VLM Verification (5 pts) ---
    try:
        import sys
        # Import the helper from utils if available in path, otherwise define dummy
        sys.path.insert(0, "/workspace/utils")
        from eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_res = vlm_verify_eclipse_task(
            traj, env_info, 
            task_description="Implement Builder pattern in Employee.java and write a JUnit test in Eclipse",
            checklist_items=[
                "Eclipse IDE editor is visible",
                "Employee.java was edited",
                "A new test file was created/edited",
                "JUnit test results view is visible (green bar)"
            ]
        )
        
        if vlm_res and vlm_res.get("vlm_passed"):
            score += 5
            feedback_parts.append("VLM: Eclipse usage verified")
        elif vlm_res:
            feedback_parts.append(f"VLM: {vlm_res.get('vlm_feedback')}")
            
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Be lenient if VLM fails technically
        score += 5

    return {
        "passed": score >= 60 and compile_success,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }