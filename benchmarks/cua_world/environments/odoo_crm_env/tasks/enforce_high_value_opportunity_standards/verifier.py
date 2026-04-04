#!/usr/bin/env python3
"""
Verifier for enforce_high_value_opportunity_standards task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enforce_high_value_opportunity_standards(traj, env_info, task_info):
    """
    Verify that high value opportunities were correctly prioritized and tagged.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Basic Check
    if "error" in result:
        return {"passed": False, "score": 0, "feedback": f"Runtime error during export: {result['error']}"}

    score = 0
    feedback_parts = []
    
    opportunities = result.get("opportunities", {})
    tag_exists = result.get("tag_exists", False)
    
    # Criterion 1: Tag Exists (10 points)
    if tag_exists:
        score += 10
        feedback_parts.append("Tag 'Key Account' exists (10/10)")
    else:
        feedback_parts.append("Tag 'Key Account' missing (0/10)")

    # Criterion 2: Global Logistics Contract ($150k) (35 points total)
    # Expected: High Priority, Tagged
    opp_a = opportunities.get("Global Logistics Contract", {"exists": False})
    if opp_a["exists"]:
        # Priority Check (20 pts)
        prio = opp_a.get("priority", "0")
        # '1' is star, '2' or '3' also valid high priorities
        if prio in ['1', '2', '3']:
            score += 20
            feedback_parts.append("Global Logistics: Priority High (20/20)")
        else:
            feedback_parts.append(f"Global Logistics: Priority Low/Normal ({prio}) (0/20)")
            
        # Tag Check (15 pts)
        if opp_a.get("has_key_account_tag", False):
            score += 15
            feedback_parts.append("Global Logistics: Tagged (15/15)")
        else:
            feedback_parts.append("Global Logistics: Not Tagged (0/15)")
    else:
        feedback_parts.append("Global Logistics: Record deleted/missing (0/35)")

    # Criterion 3: New HQ Furniture ($55k) (35 points total)
    # Expected: High Priority, Tagged
    opp_b = opportunities.get("New HQ Furniture", {"exists": False})
    if opp_b["exists"]:
        # Priority Check (20 pts)
        prio = opp_b.get("priority", "0")
        if prio in ['1', '2', '3']:
            score += 20
            feedback_parts.append("New HQ Furniture: Priority High (20/20)")
        else:
            feedback_parts.append(f"New HQ Furniture: Priority Low/Normal ({prio}) (0/20)")
            
        # Tag Check (15 pts)
        if opp_b.get("has_key_account_tag", False):
            score += 15
            feedback_parts.append("New HQ Furniture: Tagged (15/15)")
        else:
            feedback_parts.append("New HQ Furniture: Not Tagged (0/15)")
    else:
        feedback_parts.append("New HQ Furniture: Record deleted/missing (0/35)")

    # Criterion 4: Server Upgrade ($12k) (20 points total)
    # Expected: Normal Priority, NOT Tagged (Control)
    opp_c = opportunities.get("Server Upgrade", {"exists": False})
    if opp_c["exists"]:
        control_passed = True
        
        # Priority Check
        prio = opp_c.get("priority", "0")
        if prio != '0':
            control_passed = False
            feedback_parts.append(f"Server Upgrade (Control): Priority improperly changed to {prio}")
            
        # Tag Check
        if opp_c.get("has_key_account_tag", False):
            control_passed = False
            feedback_parts.append("Server Upgrade (Control): Improperly tagged")
            
        if control_passed:
            score += 20
            feedback_parts.append("Server Upgrade (Control): Correctly ignored (20/20)")
        else:
            feedback_parts.append("Server Upgrade (Control): Failed (0/20)")
    else:
        feedback_parts.append("Server Upgrade: Record deleted/missing (0/20)")

    # Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }