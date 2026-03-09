#!/usr/bin/env python3
"""
Verifier for configure_advanced_polling task.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_cron(spec):
    """
    Parse a standard 5-part cron string into components.
    Returns list of 5 strings or None if invalid.
    Handles multiline inputs by taking the first non-comment line.
    """
    if not spec:
        return None
    
    # Filter out comments and empty lines
    lines = [line.strip() for line in spec.split('\n') if line.strip() and not line.strip().startswith('#')]
    if not lines:
        return None
        
    # Take the first valid line
    parts = lines[0].split()
    if len(parts) != 5:
        return None
        
    return parts

def verify_configure_advanced_polling(traj, env_info, task_info):
    """
    Verify Jenkins SCM polling configuration.
    
    Criteria:
    1. Polling trigger enabled (spec exists).
    2. Schedule Minutes: Every 15 (H/15 or */15).
    3. Schedule Hours: 8-18.
    4. Schedule DOM/Month: *.
    5. Schedule DOW: 1-5 or Mon-Fri.
    6. Quiet Period: 120.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Check basics
    if not result.get('job_exists'):
        return {"passed": False, "score": 0, "feedback": "Job deleted or not found"}

    score = 0
    feedback = []
    
    # 1. Trigger Enabled (20 pts)
    poll_spec = result.get('poll_spec', '').strip()
    if poll_spec:
        score += 20
        feedback.append("Polling trigger enabled")
    else:
        feedback.append("Polling trigger NOT enabled")
        # Fail early if not enabled
        return {"passed": False, "score": score, "feedback": ". ".join(feedback)}

    # Parse Cron
    cron_parts = parse_cron(poll_spec)
    if not cron_parts:
        feedback.append(f"Invalid cron format: '{poll_spec}'")
    else:
        minute, hour, dom, month, dow = cron_parts
        
        # 2. Minutes (15 pts)
        # Accept H/15, */15, or explicit lists like 0,15,30,45
        if '15' in minute and ('/' in minute or ',' in minute):
            score += 15
            feedback.append("Minute schedule correct")
        else:
            feedback.append(f"Minute incorrect (expected every 15, got '{minute}')")

        # 3. Hours (15 pts)
        # Expected 8-18
        if hour == '8-18':
            score += 15
            feedback.append("Hour schedule correct")
        else:
            feedback.append(f"Hour incorrect (expected 8-18, got '{hour}')")

        # 4. Days (15 pts)
        # Expected 1-5 or Mon-Fri
        if '1-5' in dow or 'Mon-Fri' in dow or '1,2,3,4,5' in dow:
            score += 15
            feedback.append("Day of week correct")
        else:
            feedback.append(f"DOW incorrect (expected 1-5, got '{dow}')")

    # 5. Quiet Period Set (15 pts) and Value (20 pts)
    qp_raw = result.get('quiet_period', 'null')
    
    if qp_raw != 'null' and qp_raw != '':
        score += 15
        try:
            qp_val = int(qp_raw)
            if qp_val == 120:
                score += 20
                feedback.append("Quiet period value correct (120)")
            else:
                feedback.append(f"Quiet period incorrect (expected 120, got {qp_val})")
        except ValueError:
            feedback.append(f"Quiet period invalid format: {qp_raw}")
    else:
        feedback.append("Quiet period NOT set")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": ". ".join(feedback)
    }