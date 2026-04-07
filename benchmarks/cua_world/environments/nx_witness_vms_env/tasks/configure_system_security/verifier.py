#!/usr/bin/env python3
"""
Verifier for configure_system_security task.

Checks:
1. Five specific system settings via API state (18 points each = 90 points)
2. Existence and validity of a user-created report file (10 points)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_system_security(traj, env_info, task_info):
    """
    Verify that security settings were correctly applied.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expected values
    expected_settings = {
        "sessionLimitMinutes": 15,
        "autoDiscoveryEnabled": False,
        "trafficEncryptionForced": True,
        "statisticsAllowed": False,
        "insecureDeprecatedApiEnabled": False
    }

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # =========================================================
    # Check 1: Verify System Settings (18 points each)
    # =========================================================
    final_settings = result.get('final_settings', {})
    
    for key, expected_val in expected_settings.items():
        actual_val = final_settings.get(key)
        
        # Normalize types for comparison (API might return strings/ints/bools differently)
        # Convert actual to expected's type if possible
        match = False
        try:
            if isinstance(expected_val, bool):
                if str(actual_val).lower() == str(expected_val).lower():
                    match = True
            elif isinstance(expected_val, int):
                if int(actual_val) == expected_val:
                    match = True
            else:
                if actual_val == expected_val:
                    match = True
        except (ValueError, TypeError):
            match = False
            
        if match:
            score += 18
            feedback_parts.append(f"✅ {key} correctly set to {expected_val}")
        else:
            feedback_parts.append(f"❌ {key}: expected {expected_val}, got {actual_val}")

    # =========================================================
    # Check 2: Verify Report File (10 points)
    # =========================================================
    report_info = result.get('report_file', {})
    report_exists = report_info.get('exists', False)
    report_fresh = report_info.get('created_during_task', False)
    report_content = report_info.get('content_snippet', "")
    
    report_score = 0
    if report_exists and report_fresh:
        # Check content quality - should mention at least some setting names
        mentioned = 0
        for key in expected_settings.keys():
            if key.lower() in report_content.lower():
                mentioned += 1
        
        # Also check for user-friendly names that might appear instead of raw keys
        friendly_names = ["session", "timeout", "discovery", "encryption", "statistics", "api"]
        for name in friendly_names:
            if name in report_content.lower():
                mentioned += 1
                
        if len(report_content) > 20 and mentioned >= 3:
            report_score = 10
            feedback_parts.append("✅ Report file created with relevant content")
        elif len(report_content) > 10:
            report_score = 5
            feedback_parts.append("⚠️ Report file created but lacks detail")
        else:
            report_score = 2
            feedback_parts.append("⚠️ Report file is empty")
    else:
        feedback_parts.append("❌ Report file not created during task")
        
    score += report_score

    # =========================================================
    # Final Result
    # =========================================================
    passed = (score >= 60) # Need at least 3 settings correct + report OR 4 settings correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }