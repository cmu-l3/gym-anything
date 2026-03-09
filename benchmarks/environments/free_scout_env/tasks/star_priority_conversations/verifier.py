#!/usr/bin/env python3
"""
Verifier for star_priority_conversations task.

Criteria:
1. Activity Check: Starred count increased from 0. (20 pts)
2. Exact Count: Exactly 3 conversations are starred. (20 pts)
3. Correct Target 1: "Core Switch Failure" starred. (20 pts)
4. Correct Target 2: "VPN Gateway Timeout" starred. (20 pts)
5. Correct Target 3: "DNS Resolution Failures" starred. (20 pts)

Also includes VLM verification as a supplementary signal.
"""

import json
import tempfile
import os
import logging
import sys

# Add parent directory for shared utilities
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Try to import VLM utils if available
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_star_priority_conversations(traj, env_info, task_info):
    """Verify that exactly the 3 priority conversations were starred."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Target subjects from metadata (or hardcoded backup)
    metadata = task_info.get('metadata', {})
    targets = metadata.get('target_subjects', [
        "Core Switch Failure",
        "VPN Gateway Timeout",
        "DNS Resolution Failure"
    ])
    
    # Read result from container
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
    
    initial_count = int(result.get('initial_starred_count', 0))
    final_count = int(result.get('final_starred_count', 0))
    starred_subjects_raw = result.get('starred_subjects_raw', '')
    
    # Parse subjects (they are newline separated in the raw output from mysql command usually)
    # The export script sends raw string output from mysql
    starred_subjects = [s.strip() for s in starred_subjects_raw.split('\n') if s.strip()]
    
    logger.info(f"Initial: {initial_count}, Final: {final_count}")
    logger.info(f"Starred subjects found: {starred_subjects}")

    # Criterion 1: Activity Check (20 pts)
    # Did the user star ANYTHING?
    if final_count > initial_count:
        score += 20
        feedback_parts.append(f"Conversations starred (count: {final_count})")
    else:
        feedback_parts.append("No new conversations starred")
        
    # Criterion 2: Exact Count (20 pts)
    # Should be exactly 3 starred total (assuming we started with 0)
    if final_count == 3:
        score += 20
        feedback_parts.append("Exactly 3 conversations starred")
    elif final_count > 3:
        score += 5
        feedback_parts.append(f"Too many conversations starred ({final_count})")
    elif final_count > 0:
        score += 5
        feedback_parts.append(f"Too few conversations starred ({final_count})")
        
    # Criteria 3-5: Subject Checks (20 pts each)
    # We check if key phrases from targets are present in the starred subjects
    
    # Target 1: Core Switch Failure
    t1_found = any("Core Switch Failure" in s for s in starred_subjects)
    if t1_found:
        score += 20
        feedback_parts.append("Correct: 'Core Switch Failure'")
    else:
        feedback_parts.append("Missing: 'Core Switch Failure'")
        
    # Target 2: VPN Gateway Timeout
    t2_found = any("VPN Gateway Timeout" in s for s in starred_subjects)
    if t2_found:
        score += 20
        feedback_parts.append("Correct: 'VPN Gateway Timeout'")
    else:
        feedback_parts.append("Missing: 'VPN Gateway Timeout'")
        
    # Target 3: DNS Resolution Failures
    t3_found = any("DNS Resolution Failure" in s for s in starred_subjects)
    if t3_found:
        score += 20
        feedback_parts.append("Correct: 'DNS Resolution Failures'")
    else:
        feedback_parts.append("Missing: 'DNS Resolution Failures'")

    # Optional: VLM Confirmation
    # If the score is high but we want to be sure, or if DB failed somehow
    if VLM_AVAILABLE:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                # Ask VLM to verify the visible list
                prompt = "Does this screenshot show a list of email conversations? Are there exactly 3 conversations listed? Do the visible subjects relate to 'Switch Failure', 'VPN', and 'DNS'?"
                vlm_response = query_vlm(images=[final_screenshot], prompt=prompt)
                logger.info(f"VLM Analysis: {vlm_response}")
                # We don't change score based on VLM here to avoid false negatives, 
                # but we log it for debugging or future refinement.
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Final Pass Determination
    # Threshold 60 implies at least activity + 2 correct subjects, or activity + count + 1 subject
    passed = score >= 60 and final_count > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }