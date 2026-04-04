#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_archive_stale_opportunities(traj, env_info, task_info):
    """
    Verifies that the 3 specific opportunities were archived and no other records were lost.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
    
    # Check for execution errors
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {result['error']}"}

    score = 0
    feedback_parts = []
    
    targets = result.get("targets", {})
    target_names = [
        "Cloud Migration Assessment - GlobalTech Solutions",
        "POS System Rollout - Bay Area Retailers",
        "Data Analytics Platform - Meridian Corp"
    ]
    
    # 1. Scoring for Targets (25 pts each = 75 pts max)
    archived_count = 0
    for name in target_names:
        if name in targets:
            info = targets[name]
            # active should be False
            if not info.get("active", True):
                score += 25
                archived_count += 1
                feedback_parts.append(f"✅ Archived '{name}'")
            else:
                feedback_parts.append(f"❌ '{name}' is still Active")
        else:
            feedback_parts.append(f"❌ '{name}' not found in verification data")

    # 2. Collateral Damage Check (15 pts)
    collateral_damage = result.get("collateral_damage", False)
    if not collateral_damage:
        score += 15
        feedback_parts.append("✅ No collateral damage detected")
    else:
        details = result.get("collateral_details", "Unknown mismatch")
        feedback_parts.append(f"❌ Collateral damage detected ({details})")

    # 3. Timestamp/Anti-gaming Check (10 pts)
    # At least one record must have been modified after task start
    if result.get("timestamp_check_passed", False):
        score += 10
        feedback_parts.append("✅ Modifications verified in current session")
    elif archived_count > 0:
        feedback_parts.append("⚠️ Records archived but timestamps match pre-task state (suspicious)")
    
    # Final Evaluation
    passed = (score >= 60) and (archived_count >= 2) and (not collateral_damage)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }