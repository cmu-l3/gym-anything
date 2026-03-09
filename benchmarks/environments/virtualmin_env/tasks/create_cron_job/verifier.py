#!/usr/bin/env python3
"""
Verifier for create_cron_job task.

Criteria:
1. Cron entry exists for the correct user (25 pts)
2. Command is correct (25 pts)
3. Schedule is correct (30 pts: 10 for hour, 10 for min, 10 for wildcards)
4. Anti-gaming: Entry created during task (10 pts)
5. VLM Trajectory: Confirms UI interaction (10 pts)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_cron_line(line):
    """
    Parses a standard cron line.
    Returns dict with fields or None if invalid.
    Format: min hour dom month dow command
    """
    parts = line.strip().split()
    if len(parts) < 6:
        return None
    
    # Handle special strings like @daily if necessary, but task asks for specific time
    if line.startswith('@'):
        return {"special": parts[0], "command": " ".join(parts[1:])}

    return {
        "min": parts[0],
        "hour": parts[1],
        "dom": parts[2],
        "month": parts[3],
        "dow": parts[4],
        "command": " ".join(parts[5:])
    }

def verify_create_cron_job(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_cmd = metadata.get('target_command', '/home/acmecorp/bin/db_maintenance.sh')
    exp_min = metadata.get('expected_min', '30')
    exp_hour = metadata.get('expected_hour', '2')

    # Load result from container
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

    score = 0
    feedback = []
    
    user_crontab = result.get('user_crontab', '')
    root_crontab = result.get('root_crontab', '')
    target_user = result.get('target_user', 'acmecorp')
    
    # Find matching line
    matched_line = None
    on_wrong_user = False
    
    # Check user crontab
    for line in user_crontab.split('\n'):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if 'db_maintenance.sh' in line:
            matched_line = line
            break
            
    # Check root crontab if not found
    if not matched_line:
        for line in root_crontab.split('\n'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if 'db_maintenance.sh' in line:
                matched_line = line
                on_wrong_user = True
                break

    # Evaluation
    if matched_line:
        if on_wrong_user:
            feedback.append(f"Found cron job, but on ROOT user instead of {target_user} (-25 pts)")
            # No points for existence if on wrong user, strict security requirement
        else:
            score += 25
            feedback.append(f"Cron job found for user {target_user}")

            # Check command
            cron_parts = parse_cron_line(matched_line)
            if cron_parts:
                cmd_found = cron_parts['command']
                if expected_cmd in cmd_found:
                    score += 25
                    feedback.append("Command path correct")
                else:
                    feedback.append(f"Command mismatch: found '{cmd_found}'")

                # Check Schedule
                # Minute
                if cron_parts['min'] == exp_min:
                    score += 10
                    feedback.append("Minute correct (30)")
                else:
                    feedback.append(f"Minute incorrect: {cron_parts['min']}")

                # Hour
                if cron_parts['hour'] == exp_hour:
                    score += 10
                    feedback.append("Hour correct (2)")
                else:
                    feedback.append(f"Hour incorrect: {cron_parts['hour']}")

                # Wildcards
                if cron_parts['dom'] == '*' and cron_parts['month'] == '*' and cron_parts['dow'] == '*':
                    score += 10
                    feedback.append("Daily schedule wildcards correct")
                else:
                    feedback.append("Schedule wildcards incorrect (should be *)")
    else:
        feedback.append("No cron job found containing 'db_maintenance.sh'")

    # Anti-gaming: Check modification
    if result.get('spool_modified', False):
        score += 10
        feedback.append("Crontab modified during task")
    elif matched_line and not on_wrong_user:
        feedback.append("Warning: Crontab matched but file not modified during task? (Pre-existing?)")

    # VLM Verification (Trajectory)
    # Check if agent was interacting with Cron module
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = (
            "Does the user interface show the 'Scheduled Cron Jobs' module in Webmin/Virtualmin? "
            "Are there forms for setting time (minutes, hours) and commands?"
        )
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res.get('success') and (vlm_res.get('yes') or 'yes' in str(vlm_res.get('parsed', '')).lower()):
            score += 10
            feedback.append("VLM confirms interaction with Cron module")
        else:
            feedback.append("VLM could not confirm Cron module interaction")
    else:
        # Fallback if no frames (shouldn't happen in real run)
        feedback.append("No trajectory frames for VLM")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }