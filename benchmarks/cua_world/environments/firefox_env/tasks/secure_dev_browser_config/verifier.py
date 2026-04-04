#!/usr/bin/env python3
"""
Verifier for secure_dev_browser_config task.

Verifies:
1. `prefs.js` contains the 8 required hardening preferences with correct values.
2. `prefs.js` indicates Strict tracking protection and correct homepage.
3. `browser_security_config.json` exists, is valid JSON, and matches the requirements.
4. Timestamps to ensure work was done during the task.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_secure_dev_browser_config(traj, env_info, task_info):
    """
    Verify browser hardening configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    required_prefs = metadata.get('required_prefs', {})
    required_ui_settings = metadata.get('required_ui_settings', {})
    
    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result: {e}")
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    max_score = 100
    feedback_parts = []
    
    actual_prefs = result.get("actual_prefs", {})
    task_start_time = result.get("task_start_time", 0)

    # --- Section 1: Verify about:config preferences (56 points, 7 per pref) ---
    # We check the 8 hardening prefs.
    # Note: If a pref is missing from prefs.js, it means it has the default value.
    # The task requires changing them from default, so missing = fail.
    
    prefs_correct_count = 0
    
    for pref_name, expected_val in required_prefs.items():
        actual_val = actual_prefs.get(pref_name)
        
        # Handle type mismatches (e.g., 0 vs "0")
        match = False
        if actual_val == expected_val:
            match = True
        elif str(actual_val) == str(expected_val): # Loose comparison
            match = True
            
        if match:
            score += 7
            prefs_correct_count += 1
            # feedback_parts.append(f"✓ {pref_name}") 
        else:
            feedback_parts.append(f"✗ {pref_name}: expected {expected_val}, got {actual_val}")

    if prefs_correct_count == 8:
        feedback_parts.append("All 8 security preferences set correctly (+56)")
    else:
        feedback_parts.append(f"{prefs_correct_count}/8 security preferences correct")

    # --- Section 2: Verify UI Settings (14 points, 7 each) ---
    
    # Check ETP (Strict mode)
    # Strict mode usually corresponds to browser.contentblocking.category = "strict"
    etp_val = actual_prefs.get("browser.contentblocking.category")
    if etp_val == "strict":
        score += 7
        feedback_parts.append("Enhanced Tracking Protection is Strict (+7)")
    else:
        feedback_parts.append(f"Enhanced Tracking Protection not Strict (found: {etp_val})")

    # Check Homepage
    # Should contain developer.mozilla.org
    homepage_val = actual_prefs.get("browser.startup.homepage", "")
    if "developer.mozilla.org" in str(homepage_val):
        score += 7
        feedback_parts.append("Homepage set correctly (+7)")
    else:
        feedback_parts.append(f"Homepage incorrect (found: {homepage_val})")

    # --- Section 3: Verify Audit Report (30 points) ---
    
    report_exists = result.get("report_exists", False)
    report_mtime = result.get("report_mtime", 0)
    report_content = result.get("report_content")
    
    if not report_exists:
        feedback_parts.append("Audit report file not found")
    elif report_mtime <= task_start_time:
        feedback_parts.append("Audit report file is stale (created before task start)")
    elif report_content is None:
        feedback_parts.append("Audit report is not valid JSON")
    else:
        # File exists and is fresh JSON (+8 base points)
        score += 8
        
        # Check content requirements
        # 1. Contains about_config_changes matching requirements (6 pts)
        report_changes = report_content.get("about_config_changes", {})
        changes_match = True
        if isinstance(report_changes, dict):
            for key in required_prefs:
                if key not in report_changes:
                    changes_match = False
                    break
        else:
            changes_match = False
            
        if changes_match:
            score += 6
        else:
            feedback_parts.append("Report missing required keys in about_config_changes")

        # 2. Values in report match actual values (6 pts)
        # We verify that the report *accurately* reflects what they did (or what was required)
        # Ideally, it should match the required values.
        values_match = True
        if isinstance(report_changes, dict):
            for key, val in required_prefs.items():
                if report_changes.get(key) != val:
                    values_match = False
                    break
        
        if values_match:
            score += 6
        else:
            feedback_parts.append("Reported values do not match requirements")
            
        # 3. Check other report fields (10 pts total)
        # tracking_protection: strict
        # homepage: developer.mozilla.org
        if str(report_content.get("tracking_protection")).lower() == "strict":
            score += 5
        else:
            feedback_parts.append("Report incorrect tracking_protection value")
            
        if "developer.mozilla.org" in str(report_content.get("homepage", "")):
            score += 5
        else:
            feedback_parts.append("Report incorrect homepage value")
            
        feedback_parts.append("Report file verification complete")

    # --- Final Score Calculation ---
    passed = (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }