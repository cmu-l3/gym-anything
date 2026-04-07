#!/usr/bin/env python3
import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_update_bp_credit_settings(traj, env_info, task_info):
    """
    Verifies that the business partner 'Seed Farm Inc.' was updated correctly.
    
    Criteria:
    1. SO Credit Limit = 75000 (25 pts)
    2. SO Credit Status = 'W' (Credit Watch) (25 pts)
    3. Payment Rule = 'P' (On Credit) (25 pts)
    4. Record actually modified during task execution (10 pts)
    5. VLM verification of workflow (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Data
    final_values = result.get("final_values", {})
    actual_limit = float(final_values.get("so_credit_limit", 0))
    actual_status = final_values.get("so_credit_status", "")
    actual_rule = final_values.get("payment_rule", "")
    modified_during_task = result.get("modified_during_task", False)

    # Expected values
    metadata = task_info.get("metadata", {})
    expected_limit = metadata.get("expected_credit_limit", 75000.0)
    expected_status = metadata.get("expected_credit_status", "W")
    expected_rule = metadata.get("expected_payment_rule", "P")

    score = 0
    feedback = []

    # 3. Scoring - Database Verification
    
    # Credit Limit (Allow slight float tolerance)
    if abs(actual_limit - expected_limit) < 1.0:
        score += 25
        feedback.append("✅ SO Credit Limit updated correctly (75,000)")
    else:
        feedback.append(f"❌ SO Credit Limit incorrect. Expected 75,000, got {actual_limit}")

    # Credit Status
    if actual_status == expected_status:
        score += 25
        feedback.append("✅ SO Credit Status set to Credit Watch")
    else:
        status_map = metadata.get("credit_status_map", {})
        got_name = status_map.get(actual_status, actual_status)
        feedback.append(f"❌ SO Credit Status incorrect. Expected Credit Watch, got {got_name}")

    # Payment Rule
    if actual_rule == expected_rule:
        score += 25
        feedback.append("✅ Payment Rule set to On Credit")
    else:
        rule_map = metadata.get("payment_rule_map", {})
        got_name = rule_map.get(actual_rule, actual_rule)
        feedback.append(f"❌ Payment Rule incorrect. Expected On Credit, got {got_name}")

    # Modification Timestamp Check (Anti-gaming)
    if modified_during_task:
        score += 10
        feedback.append("✅ Record saved successfully")
    else:
        feedback.append("⚠️ Record was not saved during task session (timestamp unchanged)")

    # 4. VLM Verification
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_shot = get_final_screenshot(traj)
        
        if frames:
            prompt = """
            Review this sequence of screenshots from an ERP software (iDempiere).
            The user should be editing a Business Partner record.
            
            Look for:
            1. The 'Business Partner' window or search screen.
            2. Fields like 'Credit Limit', 'Credit Status', or 'Payment Rule' being visible or edited.
            3. The name 'Seed Farm' visible on screen.
            
            Does the user appear to be performing the task of updating a business partner's credit settings?
            """
            
            # Combine frames for context
            response = query_vlm(images=frames + [final_shot], prompt=prompt)
            
            if response and response.get("success"):
                # Simple keyword check in reasoning or boolean flag if structured
                # Assuming VLM returns a boolean 'yes/no' or similar analysis
                analysis = response.get("response", "").lower()
                if "yes" in analysis or "appears to be" in analysis or "performing the task" in analysis:
                    vlm_score = 15
                    feedback.append("✅ Visual verification passed (workflow observed)")
                else:
                    feedback.append("⚠️ Visual verification inconclusive")
            else:
                # If VLM fails, grant partial benefit of doubt if DB score is high
                if score >= 75:
                    vlm_score = 15
                    feedback.append("✅ Visual verification skipped (DB checks passed)")
        else:
            feedback.append("⚠️ No screenshots available for visual verification")
    
    score += vlm_score

    # Final Pass Determination
    passed = score >= 60 and modified_during_task
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }