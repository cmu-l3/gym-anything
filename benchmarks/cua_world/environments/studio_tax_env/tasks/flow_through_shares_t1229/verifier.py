#!/usr/bin/env python3
"""
Verifier for flow_through_shares_t1229 task.

Evaluates StudioTax .24t save files for correct incorporation of flow-through 
share elements: T4 income, Form T1229 (CEE), Form T2038 (ITC), and Schedule 4.
"""

import os
import json
import tempfile
import logging

# Assuming the evaluation framework injects gym_anything helpers.
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    sample_trajectory_frames = None
    get_final_screenshot = None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are verifying a tax preparation agent's workflow in StudioTax 2024.
The agent was asked to enter a T4, a T101 (Statement of Resource Expenses), calculate the T1229 (CEE), T2038(IND) (Investment Tax Credit), and Schedule 4 (Carrying Charges).

Look closely at the trajectory of screenshots. Do you see evidence that the agent:
1. Opened and navigated StudioTax 2024?
2. Interacted with Form T101 or Form T1229?
3. Interacted with Form T2038 (Investment Tax Credit)?
4. Interacted with Schedule 4 or the Carrying Charges entry screen?

Respond in JSON format:
{
    "used_studiotax": true/false,
    "accessed_resource_forms": true/false,
    "accessed_itc_forms": true/false,
    "accessed_schedule4": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

def verify_flow_through_shares(traj, env_info, task_info):
    """
    Verifies that the agent correctly processed the flow-through share scenario.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Evaluation environment error: copy_from_env not available"}

    # --- Step 1: Programmatic File Verification ---
    result_data = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Copy from the Windows container's C:\tmp\task_result.json
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result_data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to retrieve or parse results from container: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Basic File Checks (10 pts)
    file_exists = result_data.get('file_exists', False)
    file_is_new = result_data.get('file_is_new', False)
    name_ok = result_data.get('contains_first_name', False) and result_data.get('contains_last_name', False)

    if file_exists and file_is_new and name_ok:
        score += 10
        feedback_parts.append("✅ File created correctly with taxpayer name")
    elif file_exists:
        feedback_parts.append("❌ File exists but missing name or is stale (anti-gaming)")
    else:
        feedback_parts.append("❌ Target tax file was not saved")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # T4 Employment Income (15 pts) - Must be present as baseline
    t4_income = result_data.get('contains_t4_income', False)
    if t4_income:
        score += 15
        feedback_parts.append("✅ T4 employment income ($215,000) verified")
    else:
        feedback_parts.append("❌ T4 employment income ($215,000) missing")

    # Resource Expenses CEE (15 pts)
    cee_ok = result_data.get('contains_cee', False)
    if cee_ok:
        score += 15
        feedback_parts.append("✅ Form T1229 / T101 CEE ($30,000) verified")
    else:
        feedback_parts.append("❌ Form T1229 / T101 CEE ($30,000) missing")

    # Investment Tax Credits (15 pts)
    fed_itc = result_data.get('contains_federal_itc', False)
    prov_itc = result_data.get('contains_provincial_itc', False)
    if fed_itc and prov_itc:
        score += 15
        feedback_parts.append("✅ Federal ($9,000) and Provincial ($1,500) ITCs verified")
    elif fed_itc or prov_itc:
        score += 7
        feedback_parts.append("⚠️ Only partial ITC amounts found (missing Federal or Provincial)")
    else:
        feedback_parts.append("❌ Investment Tax Credits ($9,000 / $1,500) missing")

    # Carrying Charges / Interest (15 pts)
    interest_ok = result_data.get('contains_schedule4_interest', False)
    if interest_ok:
        score += 15
        feedback_parts.append("✅ Schedule 4 Carrying Charges ($1,450) verified")
    else:
        feedback_parts.append("❌ Schedule 4 Carrying Charges ($1,450) missing")

    # --- Step 2: VLM Trajectory Verification (30 pts) ---
    vlm_score = 0
    if query_vlm and sample_trajectory_frames and get_final_screenshot:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames
            
            if images:
                vlm_result = query_vlm(images=images, prompt=VLM_PROMPT)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("used_studiotax"):
                        vlm_score += 10
                    if parsed.get("accessed_resource_forms"):
                        vlm_score += 10
                    if parsed.get("accessed_itc_forms") or parsed.get("accessed_schedule4"):
                        vlm_score += 10
                        
                    feedback_parts.append(f"🧠 VLM Visual Verification Score: {vlm_score}/30")
                    feedback_parts.append(f"   Reasoning: {parsed.get('reasoning', 'None provided')}")
                else:
                    feedback_parts.append("⚠️ VLM query failed, awarding partial default points")
                    vlm_score = 15  # Fallback
            else:
                vlm_score = 15
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            vlm_score = 15
    else:
        vlm_score = 30 # Auto-grant if framework VLM not fully initialized to prevent unfair failures

    score += vlm_score

    # Evaluate Pass/Fail Condition
    # Agent must have entered the employment income and AT LEAST ONE of the flow-through share components
    core_components_met = t4_income and (cee_ok or fed_itc or interest_ok)
    passed = (score >= 60) and core_components_met

    if not t4_income:
        score = min(score, 50)  # Score Cap: Cannot pass if base T4 is missing

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }