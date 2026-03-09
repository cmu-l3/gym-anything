#!/usr/bin/env python3
"""
Verifier for update_concept_limits task.

Checks:
1. Concept numeric limits match the required safety values.
2. Concept was modified *after* the task started (anti-gaming).
3. VLM verification to confirm usage of Admin UI.
"""

import json
import os
import tempfile
import logging
from datetime import datetime

# Import VLM utils provided by the framework
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_concept_limits(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result Data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract metadata targets
    meta = task_info.get('metadata', {})
    target_low_abs = meta.get('target_low_absolute', 0.1)
    target_low_crit = meta.get('target_low_critical', 2.0)
    target_hi_crit = meta.get('target_hi_critical', 150.0)
    target_hi_abs = meta.get('target_hi_absolute', 350.0)

    # Extract concept data
    concept = result.get('concept_data', {})
    if not result.get('concept_exists') or not concept:
        return {"passed": False, "score": 0, "feedback": "Target concept data not found in export."}

    score = 0
    feedback = []
    
    # 2. Verify Numeric Limits (80 points total)
    
    # Absolute High (25 pts)
    actual_hi_abs = concept.get('hiAbsolute')
    if actual_hi_abs == target_hi_abs:
        score += 25
        feedback.append(f"✓ Absolute High correct ({actual_hi_abs})")
    else:
        feedback.append(f"✗ Absolute High incorrect (Expected {target_hi_abs}, got {actual_hi_abs})")

    # Absolute Low (25 pts)
    actual_low_abs = concept.get('lowAbsolute')
    if actual_low_abs == target_low_abs:
        score += 25
        feedback.append(f"✓ Absolute Low correct ({actual_low_abs})")
    else:
        feedback.append(f"✗ Absolute Low incorrect (Expected {target_low_abs}, got {actual_low_abs})")

    # Critical High (15 pts)
    actual_hi_crit = concept.get('hiCritical')
    if actual_hi_crit == target_hi_crit:
        score += 15
        feedback.append(f"✓ Critical High correct ({actual_hi_crit})")
    else:
        feedback.append(f"✗ Critical High incorrect (Expected {target_hi_crit}, got {actual_hi_crit})")

    # Critical Low (15 pts)
    actual_low_crit = concept.get('lowCritical')
    if actual_low_crit == target_low_crit:
        score += 15
        feedback.append(f"✓ Critical Low correct ({actual_low_crit})")
    else:
        feedback.append(f"✗ Critical Low incorrect (Expected {target_low_crit}, got {actual_low_crit})")

    # 3. Anti-Gaming Timestamp Check (10 points)
    # OpenMRS ISO Format example: "2023-10-25T14:30:00.000+0000"
    date_changed_str = concept.get('dateChanged')
    task_start_ts = result.get('task_start', 0)
    
    timestamp_valid = False
    if date_changed_str:
        try:
            # Parse OpenMRS timestamp (simplified)
            # Python < 3.11 doesn't handle 'Z' or +0000 perfectly with fromisoformat without tweaks, 
            # but usually dateutil parser is safer if available. 
            # Fallback: simple string compare if same day, or minimal parsing.
            # Here we try strict parsing assuming standard ISO.
            dt_changed = datetime.strptime(date_changed_str.split('.')[0], "%Y-%m-%dT%H:%M:%S")
            ts_changed = dt_changed.timestamp()
            
            # Allow small clock skew, check if changed AFTER task start
            if ts_changed >= (task_start_ts - 5): 
                timestamp_valid = True
        except Exception:
            # If parsing fails, we might be lenient or check dateChanged vs dateCreated
            pass

    if timestamp_valid:
        score += 10
        feedback.append("✓ Modification verified during task session")
    else:
        feedback.append(f"⚠ Could not verify modification time (dateChanged: {date_changed_str})")

    # 4. VLM Verification (10 points)
    # Check if agent used the Legacy Admin UI
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, 4)
        final_ss = get_final_screenshot(traj)
        
        prompt = (
            "Review these screenshots of an agent performing a task in OpenMRS/Bahmni. "
            "Does the agent navigate to the 'OpenMRS Administration' legacy interface "
            "and interact with the 'Concept Dictionary' or 'Manage Concepts' pages? "
            "Look for a beige/grey old-school interface with tables of concepts."
        )
        
        try:
            vlm_resp = query_vlm(images=frames + [final_ss], prompt=prompt).get('parsed', {})
            # We expect a boolean or positive confirmation
            if vlm_resp.get('answer', False) is True or "yes" in str(vlm_resp).lower():
                vlm_score = 10
                feedback.append("✓ VLM confirms Admin UI navigation")
        except Exception:
            pass
            
    score += vlm_score

    # Final Pass Determination
    # Must have exact match on Absolute Limits (Safety critical)
    passed = (score >= 70) and (actual_hi_abs == target_hi_abs) and (actual_low_abs == target_low_abs)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }