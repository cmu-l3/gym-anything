#!/usr/bin/env python3
"""Verifier for implement_lru_cache_mri task."""

import json
import tempfile
import os
import re
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_lru_cache_mri(traj, env_info, task_info):
    """
    Verify that the MRISliceCache was correctly refactored to an LRU cache.
    
    Criteria:
    1. Tests Passed (50 pts): Maven test execution must pass (exit code 0 + report check).
    2. Logic Correctness (30 pts): Source code must use LinkedHashMap and removeEldestEntry.
    3. Implementation Details (20 pts): Cache limit must be 20.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Extract data
    mvn_exit_code = result.get('mvn_exit_code', -1)
    file_modified = result.get('file_modified', False)
    source_content = result.get('source_content', '')
    test_report_xml = result.get('test_report_content', '')

    # --- Criterion 1: Tests Passed (50 pts) ---
    tests_passed = False
    if mvn_exit_code == 0 and test_report_xml:
        try:
            root = ET.fromstring(test_report_xml)
            failures = int(root.attrib.get('failures', 0))
            errors = int(root.attrib.get('errors', 0))
            if failures == 0 and errors == 0:
                tests_passed = True
                score += 50
                feedback_parts.append("Maven tests passed successfully (No OOM, correct eviction).")
            else:
                feedback_parts.append(f"Maven tests failed: {failures} failures, {errors} errors.")
        except ET.ParseError:
            feedback_parts.append("Could not parse test report XML.")
    else:
        feedback_parts.append("Maven tests failed or crashed (possible OutOfMemoryError).")

    # --- Criterion 2: Logic Correctness (30 pts) ---
    logic_score = 0
    if not file_modified:
        feedback_parts.append("Source file was not modified.")
    else:
        # Check for LinkedHashMap import/usage
        if 'LinkedHashMap' in source_content:
            logic_score += 10
        else:
            feedback_parts.append("LinkedHashMap not found.")
            
        # Check for removeEldestEntry override
        if 'removeEldestEntry' in source_content:
            logic_score += 10
        else:
            feedback_parts.append("removeEldestEntry method not overridden.")
            
        # Check that it's actually initialized (anonymous class or constructor)
        # Regex for 'new LinkedHashMap... {' or similar
        if re.search(r'new\s+LinkedHashMap.*\{', source_content, re.DOTALL):
            logic_score += 10
        elif re.search(r'extends\s+LinkedHashMap', source_content): # Alternative: extending the class
            logic_score += 10
            
    if logic_score == 30:
        feedback_parts.append("Correct LRU implementation structure detected.")
    
    score += logic_score

    # --- Criterion 3: Implementation Details (20 pts) ---
    impl_score = 0
    # Check for the size limit of 20
    if re.search(r'size\(\)\s*>\s*20', source_content) or re.search(r'size\(\)\s*>\s*MAX', source_content):
        impl_score += 20
        feedback_parts.append("Cache size limit (20) correctly implemented.")
    else:
        feedback_parts.append("Could not verify cache size limit in code.")
        
    score += impl_score
    
    # --- VLM Verification (Bonus/Confirmation) ---
    # We use VLM to verify the agent actually interacted with Eclipse if tests failed but code looks okay
    # Or to confirm the "Green Bar" in JUnit view if available
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        vlm_res = vlm_verify_eclipse_task(
            traj, env_info, 
            task_description="Refactor MRISliceCache to use LinkedHashMap with LRU eviction",
            checklist_items=[
                "Eclipse IDE is open",
                "MRISliceCache.java is open in the editor",
                "Code changes for LinkedHashMap are visible",
                "JUnit test results (Green bar) are visible"
            ]
        )
        if vlm_res and vlm_res.get('vlm_passed'):
            # If program tests failed but VLM says it passed, maybe give partial credit?
            # For now, we just append feedback.
            feedback_parts.append(f"VLM: {vlm_res.get('vlm_feedback')}")
    except ImportError:
        pass

    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }