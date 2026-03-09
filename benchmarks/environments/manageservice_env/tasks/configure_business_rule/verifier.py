#!/usr/bin/env python3
"""
Verifier for configure_business_rule task.

Verification Logic:
1. Database Check (30 pts): Does a rule with the correct name exist?
2. Functional Test (50 pts): Did a test ticket trigger the rule?
   - Correct Priority (High)
   - Correct Group (Network Support)
   - Correct Category (Network)
3. VLM Verification (20 pts): Visual confirmation of UI settings.

Pass Threshold: 60 points (Must include functional success OR strong DB + VLM evidence)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_business_rule(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result from container
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
    feedback_parts = []
    
    # 2. Evaluate Database Evidence
    if result.get("rule_exists_in_db", False):
        score += 30
        feedback_parts.append("Business Rule found in database")
    else:
        feedback_parts.append("Business Rule NOT found in database")

    # 3. Evaluate Functional Test
    func_test = result.get("functional_test", {})
    details = func_test.get("details", {})
    
    if func_test.get("ticket_created", False):
        # Check specific actions
        prio = details.get("priority")
        group = details.get("group")
        category = details.get("category")
        
        actions_correct = 0
        if prio == "High":
            actions_correct += 1
            feedback_parts.append("Priority set correctly (High)")
        else:
            feedback_parts.append(f"Priority incorrect ({prio})")
            
        if group == "Network Support":
            actions_correct += 1
            feedback_parts.append("Group assigned correctly (Network Support)")
        else:
            feedback_parts.append(f"Group incorrect ({group})")
            
        if category == "Network":
            actions_correct += 1
            feedback_parts.append("Category set correctly (Network)")
        else:
            feedback_parts.append(f"Category incorrect ({category})")
            
        # Scoring for functional test
        # 50 points total available for functional correctness
        # 10 pts for creation, + ~13 pts per correct field
        if actions_correct > 0:
            score += 10 # Ticket created and at least partially processed
            score += int((actions_correct / 3) * 40)
            
        if actions_correct == 3:
             feedback_parts.append("Functional test PASSED perfectly")
    else:
        feedback_parts.append("Functional test could not create ticket (API/Login issue)")

    # 4. VLM Verification (Fallback/Bonus)
    # If score is low (<60), use VLM to check if they were on the right screen
    # This helps if API test failed but user did the work
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    if score < 100:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = """
        Review these screenshots of ManageEngine ServiceDesk Plus.
        The user is supposed to create a Business Rule named 'Auto-Route Network Issues'.
        
        Look for:
        1. A form for 'New Business Rule' or list of Business Rules.
        2. Rule Name 'Auto-Route Network Issues'.
        3. Criteria containing 'Subject' 'contains' 'network' OR 'connectivity'.
        4. Actions setting Priority to 'High', Group to 'Network Support'.
        
        Return JSON: {"evidence_found": true/false, "confidence": 0-10, "details": "what you see"}
        """
        
        try:
            vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
            parsed = vlm_res.get('parsed', {})
            if parsed.get('evidence_found', False):
                vlm_score = 20
                score += vlm_score
                feedback_parts.append(f"VLM verified configuration in UI (+{vlm_score}pts)")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Cap score
    score = min(score, 100)
    
    # 60 points to pass
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }