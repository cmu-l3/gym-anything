#!/usr/bin/env python3
"""
Verifier for OSINT Profile Setup task.

Verifies:
1. New Edge profile "OSINT-Research" created.
2. Tracking Prevention set to Strict.
3. Do Not Track enabled.
4. Password manager disabled.
5. Address autofill disabled.
6. Startup pages configured (osintframework.com, shodan.io).
7. Configuration report created.
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_osint_profile_setup(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result_final.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Scoring
    score = 0
    feedback_parts = []
    
    # 1. Profile Existence (20 pts)
    # Required: Must be found AND be a new profile (not reusing Default)
    if result.get("profile_found") and result.get("is_new_profile"):
        if result.get("profile_name_match"):
            score += 20
            feedback_parts.append("New OSINT-Research profile created (20/20)")
        else:
            score += 15
            feedback_parts.append("New profile created with 'OSINT' in name, but name not exact match (15/20)")
    elif result.get("profile_found"):
        # Found but not new (reused existing?) - partial credit unlikely if setup cleaned correctly, 
        # but maybe they renamed Default?
        score += 5
        feedback_parts.append("OSINT profile found but it was not a newly created profile (5/20)")
    else:
        return {"passed": False, "score": 0, "feedback": "No profile named 'OSINT-Research' found. Cannot verify settings."}

    # Settings Checks (only if profile exists)
    settings = result.get("settings", {})
    
    # 2. Tracking Prevention Strict (15 pts)
    # Edge stores Strict as level 3
    tp_level = settings.get("tracking_prevention")
    if tp_level == 3 or tp_level == "Strict":
        score += 15
        feedback_parts.append("Tracking Prevention set to Strict (15/15)")
    else:
        feedback_parts.append(f"Tracking Prevention not Strict (current: {tp_level})")

    # 3. Do Not Track (10 pts)
    if settings.get("do_not_track") is True:
        score += 10
        feedback_parts.append("Do Not Track enabled (10/10)")
    else:
        feedback_parts.append("Do Not Track not enabled")

    # 4. Password Manager Disabled (15 pts)
    if settings.get("password_manager_disabled") is True:
        score += 15
        feedback_parts.append("Password saving disabled (15/15)")
    else:
        feedback_parts.append("Password saving still enabled")

    # 5. Autofill Disabled (10 pts)
    if settings.get("autofill_disabled") is True:
        score += 10
        feedback_parts.append("Autofill disabled (10/10)")
    else:
        feedback_parts.append("Autofill still enabled")

    # 6. Startup URLs (15 pts)
    urls = settings.get("startup_urls", [])
    restore_type = settings.get("restore_on_startup_type")
    
    has_osint = any("osintframework.com" in u for u in urls)
    has_shodan = any("shodan.io" in u for u in urls)
    
    # Check if "Open specific pages" (type 4) is selected
    if restore_type == 4:
        if has_osint and has_shodan:
            score += 15
            feedback_parts.append("Startup URLs correctly configured (15/15)")
        elif has_osint or has_shodan:
            score += 8
            feedback_parts.append("Partial startup URLs configured (8/15)")
        else:
            feedback_parts.append("Startup pages mode enabled but URLs missing")
    else:
        feedback_parts.append("Startup behavior not set to 'Open specific pages'")

    # 7. Compliance Report (15 pts)
    report = result.get("report", {})
    if report.get("exists") and report.get("modified_after_start"):
        if report.get("content_valid"):
            score += 15
            feedback_parts.append("Compliance report created and valid (15/15)")
        else:
            score += 10
            feedback_parts.append("Compliance report exists but lacks specific keywords (10/15)")
    elif report.get("exists"):
        score += 5
        feedback_parts.append("Compliance report exists but not modified during task (5/15)")
    else:
        feedback_parts.append("Compliance report not found")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }