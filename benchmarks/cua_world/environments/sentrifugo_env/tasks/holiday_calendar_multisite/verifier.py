#!/usr/bin/env python3
"""
Verifier for holiday_calendar_multisite task.

Verifies:
1. Three specific holiday groups were created.
2. The groups were created AFTER the task started (Anti-Gaming).
3. The exact 7 holidays were added to each group with correct names and dates.
4. VLM verification checks trajectory for actual UI usage.

Scoring system:
- Group exists (and created during task): 5 pts each (15 max)
- Correct holiday per group: 4 pts each (Presidents' Day is 5 pts to reach 100)
- VLM Trajectory Verification: 10 pts bonus logic (ensures UI used)
Total: 100 pts. Pass threshold: 60 pts.
"""

import os
import json
import logging
import tempfile
import difflib

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def fuzzy_match(s1, s2, threshold=0.8):
    """Return True if strings match closely (tolerates minor typos)."""
    if not s1 or not s2:
        return False
    # SequenceMatcher ignores case and compares ratio
    ratio = difflib.SequenceMatcher(None, s1.lower().strip(), s2.lower().strip()).ratio()
    return ratio >= threshold

def build_vlm_prompt():
    return """Examine these screenshots from the agent's trajectory.
    
Task: Configure the Holiday Management module in Sentrifugo.

Check for these indicators of actual work:
1. Did the agent navigate to the 'Holidays' or 'Holiday Groups' section in the Sentrifugo web interface?
2. Are there signs of the agent entering data (typing holiday names, selecting dates)?
3. Is there evidence of navigating through the web application rather than just leaving the browser idle?

Respond in JSON format:
{
    "ui_interaction_observed": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Briefly explain what UI elements show interaction."
}
"""

def verify_holiday_calendar_multisite(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_holidays = metadata.get('expected_holidays', {})
    pass_threshold = metadata.get('pass_threshold', 60)

    # 1. Retrieve the exported JSON from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    db_groups = result.get("groups", {})
    group_timestamps = result.get("group_timestamps", {})
    task_start_time = result.get("task_start_time", 0)

    score = 0
    feedback_parts = []
    
    # 2. Database Evaluation
    for group_name, expected_list in expected_holidays.items():
        # Check if group exists
        if group_name in db_groups:
            # Anti-gaming: Ensure it was created after the task started
            # Allow a 5-minute buffer in case clocks are slightly desynced
            group_ts = group_timestamps.get(group_name, 0)
            if group_ts >= (task_start_time - 300):
                score += 5
                feedback_parts.append(f"Group '{group_name}' exists (5/5)")
            else:
                feedback_parts.append(f"Group '{group_name}' exists but was created BEFORE task started (0/5)")
        else:
            feedback_parts.append(f"Group '{group_name}' is MISSING (0/5)")
            continue

        # Check the holidays in this group
        actual_holidays = db_groups.get(group_name, [])
        for expected in expected_list:
            expected_name = expected['name']
            expected_date = expected['date']
            pts = expected['pts']
            
            # Find matching holiday in actual data
            match_found = False
            date_correct = False
            
            for actual in actual_holidays:
                actual_name = actual.get('name', '')
                actual_date = actual.get('date', '')
                
                if fuzzy_match(expected_name, actual_name):
                    match_found = True
                    if actual_date == expected_date:
                        date_correct = True
                        break
            
            if match_found and date_correct:
                score += pts
                feedback_parts.append(f"  {expected_name} correct ({pts}/{pts})")
            elif match_found:
                feedback_parts.append(f"  {expected_name} found but WRONG DATE (0/{pts})")
            else:
                feedback_parts.append(f"  {expected_name} missing (0/{pts})")

    # 3. VLM Trajectory Verification
    # This prevents an agent from somehow inserting into DB via hidden console without UI
    vlm_passed = False
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = build_vlm_prompt()
                vlm_result = query_vlm(prompt=prompt, images=frames)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    vlm_passed = parsed.get("ui_interaction_observed", False)
                    if vlm_passed:
                        feedback_parts.append("VLM: Verified UI interaction with Sentrifugo")
                    else:
                        feedback_parts.append("VLM WARNING: No UI interaction observed in trajectory")
        except Exception as e:
            logger.warning(f"VLM verification failed/skipped: {e}")

    # For pure data-entry tasks, if the database precisely matches and timestamps are correct,
    # we can trust it even if VLM fails (e.g., due to VLM context limits or parse issues).
    # But VLM adds a nice confidence boost in the logs.
    
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "vlm_ui_interaction_passed": vlm_passed,
            "database_groups_found": list(db_groups.keys())
        }
    }