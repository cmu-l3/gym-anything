#!/usr/bin/env python3
"""
Verifier for identify_inactive_operators task.
Reads the pre-calculated analysis from the container via copy_from_env.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_identify_inactive_operators(traj, env_info, task_info):
    """
    Verify the inactive operators report.
    
    Scoring:
    - 10 pts: Report file exists
    - 40 pts: No Active companies listed (Safety critical - don't ground active fleets!)
    - 50 pts: Inactive companies correctly identified (scaled by recall)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve validation data: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Report Exists (10 pts)
    if result.get("report_exists"):
        score += 10
        feedback_parts.append("✓ Report file created (+10)")
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "✗ Report file not found at /home/ga/Documents/inactive_operators_report.txt"
        }

    # Data for analysis
    correct_matches = result.get("correct_matches", [])
    false_positives = result.get("false_positives", []) # Active listed as inactive
    false_negatives = result.get("false_negatives", []) # Inactive missed
    
    total_inactive_count = len(correct_matches) + len(false_negatives)
    
    # 2. False Positives (Active companies listed) - 40 pts
    # This is a critical error. Listing an active operator as inactive could revoke their license.
    if len(false_positives) == 0:
        score += 40
        feedback_parts.append("✓ No active operators incorrectly flagged (+40)")
    else:
        # Heavy penalty
        penalty = min(40, len(false_positives) * 20)
        score += (40 - penalty)
        feedback_parts.append(f"✗ CRITICAL: {len(false_positives)} active operators were incorrectly listed as inactive (-{penalty}). Examples: {false_positives[:3]}")

    # 3. Recall (Did we find the inactive ones?) - 50 pts
    if total_inactive_count > 0:
        recall = len(correct_matches) / total_inactive_count
        points_earned = int(50 * recall)
        score += points_earned
        feedback_parts.append(f"✓ Identified {len(correct_matches)} of {total_inactive_count} inactive operators (+{points_earned})")
        
        if len(false_negatives) > 0:
            feedback_parts.append(f"  Missed: {false_negatives[:3]}...")
    else:
        # Edge case: No inactive operators existed in DB? (Shouldn't happen with our setup)
        score += 50
        feedback_parts.append("✓ No inactive operators existed (Correctly empty report)")

    # Final tally
    passed = score >= 90
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }