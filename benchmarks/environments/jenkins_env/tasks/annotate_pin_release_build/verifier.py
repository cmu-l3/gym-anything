#!/usr/bin/env python3
"""
Verifier for Annotate and Pin Release Build task.

Checks:
1. Build #3 is pinned (keepLog = true).
2. Build #3 has correct Display Name.
3. Build #3 has correct Description.
4. Other builds (#1, #2, #4, #5) are untouched (Anti-gaming).
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_annotate_pin_release_build(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_build_num = metadata.get('target_build_number', 3)
    expected_display_name = metadata.get('expected_display_name', "RC-v2.1.0")
    anti_gaming_builds = metadata.get('anti_gaming_builds', [1, 2, 4, 5])
    
    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/annotate_pin_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic checks
    if not result.get('job_exists'):
        return {"passed": False, "score": 0, "feedback": "Job 'regression-test-suite' was deleted or missing."}

    builds = {b['number']: b for b in result.get('builds', [])}
    
    # Check if target build exists
    if target_build_num not in builds:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Build #{target_build_num} not found. Did you delete it?"
        }

    target_build = builds[target_build_num]
    score = 0
    feedback_parts = []
    
    # --- Scoring ---
    
    # 1. Check Pinned Status (20 pts)
    # keepLog is boolean in JSON
    is_pinned = target_build.get('keepLog', False)
    if is_pinned:
        score += 20
        feedback_parts.append(f"Build #{target_build_num} is pinned correctly.")
    else:
        feedback_parts.append(f"Build #{target_build_num} is NOT pinned.")

    # 2. Check Display Name (20 pts)
    # Note: displayName might be just the number if not set, or the custom name
    current_display_name = target_build.get('displayName', '')
    if expected_display_name in current_display_name:
        score += 20
        feedback_parts.append(f"Display name set to '{current_display_name}'.")
    else:
        feedback_parts.append(f"Incorrect display name. Expected '{expected_display_name}', got '{current_display_name}'.")

    # 3. Check Description (30 pts)
    # Split into components
    desc = target_build.get('description', '')
    if desc is None: desc = ""
    
    desc_score = 0
    if "Release Candidate" in desc: desc_score += 15
    if "v2.1.0" in desc: desc_score += 10
    if "regression tests passed" in desc: desc_score += 5
    
    score += desc_score
    if desc_score == 30:
        feedback_parts.append("Description is correct.")
    elif desc_score > 0:
        feedback_parts.append(f"Description partially correct ({desc}).")
    else:
        feedback_parts.append("Description missing or incorrect.")

    # 4. Anti-gaming / Safety (30 pts)
    # Ensure other builds weren't modified
    others_ok = True
    for b_num in anti_gaming_builds:
        if b_num not in builds:
            continue # If missing, maybe okay, but let's check content
        
        b = builds[b_num]
        
        # Check if pinned (should be false)
        if b.get('keepLog', False):
            others_ok = False
            feedback_parts.append(f"Anti-gaming fail: Build #{b_num} was pinned unnecessarily.")
            
        # Check description (should be null or empty)
        if b.get('description') and len(b.get('description', '')) > 0:
            others_ok = False
            feedback_parts.append(f"Anti-gaming fail: Build #{b_num} has a description.")
            
        # Check display name (should not contain RC-v2.1.0)
        d_name = b.get('displayName', '')
        if d_name and expected_display_name in d_name:
            others_ok = False
            feedback_parts.append(f"Anti-gaming fail: Build #{b_num} was renamed.")

    if others_ok:
        score += 30
        feedback_parts.append("Other builds correctly left unmodified.")
    else:
        # Penalize heavily for shotgun approach
        feedback_parts.append("Penalty applied for modifying untargeted builds.")

    # Final logic
    passed = score >= 60 and is_pinned and ("Release Candidate" in desc)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }