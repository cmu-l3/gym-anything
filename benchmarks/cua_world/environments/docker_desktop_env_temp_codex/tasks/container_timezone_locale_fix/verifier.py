#!/usr/bin/env python3
"""
Verifier for container_timezone_locale_fix task.

Verifies:
1. Container is running.
2. 'tzdata' package is installed (Alpine requirement).
3. 'TZ' env var is set to America/New_York.
4. 'LANG' (or LC_ALL) env var is set to a UTF-8 locale.
5. 'date' command inside container returns EST/EDT time.
6. Logs show successful processing of Unicode name (Raphaël).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_container_timezone_locale_fix(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result file
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

    score = 0
    feedback_parts = []
    
    # 1. Service Running (20 pts)
    if result.get('is_running', False):
        score += 20
        feedback_parts.append("Container running (+20)")
    else:
        feedback_parts.append("Container NOT running")
        # Fatal for other checks typically
        return {"passed": False, "score": score, "feedback": "Container is not running."}

    # 2. Timezone Package (20 pts)
    # Essential for Alpine timezone support
    if result.get('has_tzdata', False):
        score += 20
        feedback_parts.append("'tzdata' installed (+20)")
    else:
        feedback_parts.append("'tzdata' missing (Timezone fix incomplete)")

    # 3. Timezone Variable & Effect (20 pts)
    # Check if TZ var is set correctly
    env_tz = result.get('env_tz', '')
    is_est_edt = result.get('is_est_edt', False)
    
    if 'New_York' in env_tz and is_est_edt:
        score += 20
        feedback_parts.append("Timezone correctly set to America/New_York (+20)")
    elif 'New_York' in env_tz and not is_est_edt:
        # Var set but date command implies it didn't work (maybe missing tzdata)
        score += 10
        feedback_parts.append("TZ variable set but system time is incorrect (missing tzdata?) (+10)")
    elif is_est_edt:
        # Time is correct but maybe they used 'EST5EDT' or similar instead of America/New_York
        score += 15
        feedback_parts.append("System time is correct (EST/EDT) (+15)")
    else:
        feedback_parts.append(f"Timezone incorrect. Var: {env_tz}, Date: {result.get('container_date_output')}")

    # 4. Locale/Unicode Fix (20 pts for Env, 20 pts for Logs)
    
    # Check Env Var (20 pts)
    env_lang = result.get('env_lang', '').upper()
    if 'UTF-8' in env_lang or 'UTF8' in env_lang:
        score += 20
        feedback_parts.append(f"Locale set to {env_lang} (+20)")
    else:
        feedback_parts.append(f"Locale env var missing/incorrect (Found: {env_lang})")

    # Check Runtime Logs (20 pts)
    # This proves Python is actually handling the unicode string correctly
    if result.get('logs_unicode', False) and result.get('logs_success', False):
        score += 20
        feedback_parts.append("Application successfully processed Unicode (+20)")
    else:
        feedback_parts.append("Application logs do not show success with Unicode")

    # Final Verification
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }