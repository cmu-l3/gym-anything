#!/usr/bin/env python3
"""
Verifier for GDPR Erasure Request task.

Verification Strategy:
1. Database Integrity (Primary):
   - Target visitor records must be 0 (Success).
   - Other visitor records must be > 0 (Safety check/Collateral damage).
2. Action Verification:
   - Compares initial vs final counts to ensure deletion happened during the task.

Scoring (100 points):
- Target visitor data completely removed: 50 pts
- Database NOT wiped (other users preserved): 30 pts
- Deletion performed during task (initial > 0 and final == 0): 20 pts

Pass threshold: 80 points (Must delete target AND preserve others)
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perform_gdpr_erasure_request(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify that the target visitor was deleted while preserving other data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/gdpr_erasure_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)

        # Extract metrics
        final_target_count = int(result.get('final_target_count', -1))
        final_other_count = int(result.get('final_other_count', -1))
        initial_target_count = int(result.get('initial_target_count', 0))
        target_id = result.get('target_id', 'unknown')

        score = 0
        feedback_parts = []
        subscores = {
            "target_deleted": False,
            "others_preserved": False,
            "action_performed": False
        }

        logger.info(f"Verification Metrics: Target ID={target_id}")
        logger.info(f"Target Count: {initial_target_count} -> {final_target_count}")
        logger.info(f"Other Users Count: {final_other_count}")

        # CRITERION 1: Target Deleted (50 pts)
        if final_target_count == 0:
            score += 50
            subscores["target_deleted"] = True
            feedback_parts.append(f"Target visitor ({target_id}) successfully deleted.")
        else:
            feedback_parts.append(f"Target visitor still has {final_target_count} records remaining.")

        # CRITERION 2: Database Integrity / Others Preserved (30 pts)
        # We expect other records to exist. 
        # Safety check: If final_other_count is 0, the agent might have wiped the whole DB.
        if final_other_count > 0:
            score += 30
            subscores["others_preserved"] = True
            feedback_parts.append(f"Other visitor data preserved ({final_other_count} records).")
        else:
            feedback_parts.append("WARNING: No other visitor records found. Possible database wipe or 'Delete All' executed.")
            # Penalize heavily if the target was deleted ONLY because everyone was deleted
            if final_target_count == 0:
                score = 0 
                feedback_parts.append("CRITICAL FAILURE: Excessive data loss. You deleted ALL users.")

        # CRITERION 3: Action Performed (20 pts)
        # Checks if we actually transitioned from existing to not existing
        if initial_target_count > 0 and final_target_count == 0:
            score += 20
            subscores["action_performed"] = True
            feedback_parts.append("Deletion confirmed during task execution.")
        elif initial_target_count == 0:
             feedback_parts.append("Setup error: Target did not exist at start.")

        passed = score >= 80

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": result
        }

    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed: {str(e)}"
        }