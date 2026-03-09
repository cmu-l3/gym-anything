#!/usr/bin/env python3
"""Verifier for recover_pim_protected_volume task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_recover_pim(traj, env_info, task_info):
    """
    Verify that the PIM was recovered and data extracted.
    
    Criteria:
    1. Secret file extracted and contains the correct random unique ID (50 pts)
    2. Correct PIM value identified and written to file (30 pts)
    3. Volume is currently mounted at the expected location (20 pts)
    
    Bonus info: Checks if a script was used (informational)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Content Verification (The most important part)
    agent_content = result.get('agent_secret_content', '').strip()
    real_secret = result.get('real_secret', '').strip()
    
    if real_secret and real_secret in agent_content:
        score += 50
        feedback_parts.append("✅ Confidential file recovered successfully")
    elif result.get('file_exists'):
        feedback_parts.append("❌ Recovered file exists but content does not match")
    else:
        feedback_parts.append("❌ Recovered file not found")

    # Check 2: PIM Identification
    try:
        agent_pim = int(result.get('agent_pim_guess', -1))
        real_pim = int(result.get('real_pim', -2))
        
        if agent_pim == real_pim:
            score += 30
            feedback_parts.append(f"✅ Correct PIM identified ({real_pim})")
        else:
            feedback_parts.append(f"❌ Incorrect PIM (Expected {real_pim}, got {agent_pim})")
    except ValueError:
        feedback_parts.append("❌ Invalid PIM format in output file")

    # Check 3: Mount State
    if result.get('is_mounted'):
        score += 20
        feedback_parts.append("✅ Volume is mounted")
    else:
        feedback_parts.append("❌ Volume is not mounted at required slot")

    # Check Script usage (just for feedback, hard to enforce strictly but good signal)
    if result.get('script_found'):
        feedback_parts.append("ℹ️ Brute-force script detected")
    else:
        feedback_parts.append("ℹ️ No script detected (manual guessing?)")

    passed = score >= 80  # Must at least get the file and PIM correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }