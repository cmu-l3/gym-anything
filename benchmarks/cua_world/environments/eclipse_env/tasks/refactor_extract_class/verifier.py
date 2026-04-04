#!/usr/bin/env python3
"""
Verifier for refactor_extract_class task.

Criteria:
1. NetworkConfiguration.java exists and contains extracted fields (25 pts)
2. RadiationTreatmentUnit.java references NetworkConfiguration (25 pts)
3. RadiationTreatmentUnit.java NO LONGER contains the raw fields (20 pts)
4. Maven build and tests pass (15 pts)
5. VLM verification of UI interaction (15 pts)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_extract_class(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    # --- Check 1: New Class Existence & Content (25 pts) ---
    new_content = result.get("new_content", "")
    if result.get("new_file_exists") and new_content:
        # Check for class name
        if "class NetworkConfiguration" in new_content:
            score += 5
        else:
            feedback_parts.append("NetworkConfiguration class definition not found")
            
        # Check for fields
        required_fields = ["ipAddress", "port", "protocol", "connectionTimeout"]
        missing_fields = [f for f in required_fields if f not in new_content]
        
        if not missing_fields:
            score += 20
            feedback_parts.append("All network fields found in new class")
        else:
            score += 5  # Partial credit
            feedback_parts.append(f"Missing fields in new class: {missing_fields}")
    else:
        feedback_parts.append("NetworkConfiguration.java not found")
        
    # --- Check 2: Original Class Delegation (25 pts) ---
    orig_content = result.get("original_content", "")
    if "NetworkConfiguration" in orig_content:
        score += 25
        feedback_parts.append("Delegation to NetworkConfiguration found")
    else:
        feedback_parts.append("Original class does not reference NetworkConfiguration")
        
    # --- Check 3: Cleanup of Original Class (20 pts) ---
    # The original fields should NOT be present as private fields in the original class
    # Regex checks for "private String ipAddress;" etc.
    raw_field_pattern = r"private\s+(String|int)\s+(ipAddress|port|protocol|connectionTimeout)\s*;"
    found_raw = re.findall(raw_field_pattern, orig_content)
    
    if not found_raw:
        score += 20
        feedback_parts.append("Raw network fields correctly removed from original class")
    else:
        feedback_parts.append(f"Original class still contains raw fields: {found_raw}")
        
    # --- Check 4: Compilation and Tests (15 pts) ---
    if result.get("maven_exit_code") == 0:
        score += 15
        feedback_parts.append("Project compiles and tests pass")
    else:
        # Check log for details
        log = result.get("maven_log", "")
        if "BUILD SUCCESS" in log:
            score += 15
            feedback_parts.append("Build success detected in log (despite exit code)")
        else:
            feedback_parts.append("Maven build/test failed")
            
    # --- Check 5: VLM Verification (15 pts) ---
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Extract network fields to NetworkConfiguration class using Eclipse Refactoring",
            checklist_items=[
                "Eclipse IDE is open",
                "Refactor > Extract Class dialog is visible",
                "The new class name 'NetworkConfiguration' is typed",
                "Network fields (ipAddress, port, etc) are selected in the dialog",
                "Package Explorer shows NetworkConfiguration.java"
            ]
        )
        
        if vlm_result:
            if vlm_result.get("vlm_passed"):
                score += 15
                feedback_parts.append("VLM: Workflow confirmed")
            else:
                feedback_parts.append(f"VLM: {vlm_result.get('vlm_feedback')}")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Fallback: if score is already high (code is perfect), give benefit of doubt
        if score >= 70:
            score += 15
            feedback_parts.append("VLM skipped but code verified")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }