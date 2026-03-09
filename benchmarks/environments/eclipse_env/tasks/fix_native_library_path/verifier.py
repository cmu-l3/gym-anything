#!/usr/bin/env python3
"""Verifier for fix_native_library_path task."""

import json
import tempfile
import os
import re
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fix_native_library_path(traj, env_info, task_info):
    """Verify that the native library path was configured and app runs.

    Criteria:
    1. Runtime Success (50 pts): dose_report.txt exists with correct value.
    2. Configuration Persistence (30 pts): .classpath contains correct attribute.
    3. Source Integrity (20 pts): 'native' keyword preserved in source.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_val = metadata.get('expected_result_value', '45.5')
    native_lib_path = metadata.get('native_lib_path', '/opt/medphys/lib')

    score = 0
    feedback_parts = []

    # Read result file
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification result: {e}"}

    # --- Criterion 1: Runtime Success (50 points) ---
    report_exists = result.get('report_exists', False)
    file_created = result.get('file_created_during_task', False)
    report_content = result.get('report_content', '')

    if report_exists and file_created:
        if expected_val in report_content:
            score += 50
            feedback_parts.append("Application ran successfully (report correct)")
        else:
            score += 25
            feedback_parts.append("Report generated but content incorrect")
    elif report_exists:
        feedback_parts.append("Report exists but is stale (not created during task)")
    else:
        feedback_parts.append("No runtime report generated")

    # --- Criterion 2: Configuration Persistence (30 points) ---
    classpath_content = result.get('classpath_content', '')
    config_valid = False
    
    # We look for: <attribute name="org.eclipse.jdt.launching.CLASSPATH_ATTR_LIBRARY_PATH_ENTRY" value="/opt/medphys/lib"/>
    # This attribute can be on the 'src' entry or the JRE container entry.
    if classpath_content:
        try:
            # Simple string check is usually robust enough for XML attributes if we aren't strict on whitespace
            # But let's try to be precise about the value
            if 'org.eclipse.jdt.launching.CLASSPATH_ATTR_LIBRARY_PATH_ENTRY' in classpath_content:
                if native_lib_path in classpath_content:
                    config_valid = True
            
            if config_valid:
                score += 30
                feedback_parts.append(".classpath configuration verified")
            else:
                feedback_parts.append("Native library path not found in .classpath")
        except Exception:
             feedback_parts.append("Error parsing .classpath")
    else:
        feedback_parts.append(".classpath file missing or empty")

    # --- Criterion 3: Source Integrity (20 points) ---
    source_content = result.get('source_content', '')
    if source_content:
        # Check for 'public native double calculateNative();'
        # Regex to handle whitespace variations
        if re.search(r'native\s+double\s+calculateNative', source_content) or \
           re.search(r'double\s+calculateNative\s*\([^)]*\)\s*;\s*//\s*native', source_content): # Unlikely comment case
           
           # Ensure they didn't just hardcode the return in Java
           if "return 45.5" in source_content:
               feedback_parts.append("INTEGRITY FAIL: Hardcoded return value detected in Java")
               # Penalty: Score cannot exceed 40 total if they cheated
               score = min(score, 40)
           else:
               score += 20
               feedback_parts.append("Source code integrity preserved")
        else:
            feedback_parts.append("INTEGRITY FAIL: 'native' modifier removed from source")
    else:
        feedback_parts.append("Source file not found")

    # --- VLM Verification (Bonus/Confirmation) ---
    # We use VLM to check if the user actually interacted with the Build Path dialog
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Configure Java Build Path to add a Native Library Location",
            checklist_items=[
                "Properties dialog for 'DoseCalculator' is visible",
                "Java Build Path settings are visible",
                "Native Library Location configuration dialog is visible",
                "Path '/opt/medphys/lib' is being entered or selected",
                "Console output shows 'Dose calculation successful'"
            ]
        )
        
        if vlm_result:
            if vlm_result.get('vlm_passed'):
                # If they passed VLM but missed something small programmatically, bump score slightly?
                # Or just append feedback.
                feedback_parts.append("VLM: Workflow visually verified.")
            else:
                feedback_parts.append(f"VLM: {vlm_result.get('vlm_feedback')}")

    except Exception as e:
        logger.debug(f"VLM check failed: {e}")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }