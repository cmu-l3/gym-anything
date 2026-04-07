#!/usr/bin/env python3
"""
Verifier for customize_contact_layout task.

Verifies CRM UI/Data model configuration by directly inspecting
Vtiger's database schema tables (`vtiger_field`).

CRITERIA:
1. Title is set to Summary/Key Field View (20 pts)
2. Mobile is set to Summary/Key Field View (20 pts)
3. Department is set to Summary/Key Field View (20 pts)
4. Email is set to Mandatory (typeofdata contains ~M) (30 pts)
5. VLM trajectory confirms the agent used the Settings UI (10 pts)
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VERIFICATION_PROMPT = """You are verifying an agent's trajectory for a CRM administration task.

The agent was asked to navigate to the CRM Settings > Module Layouts & Fields (Layout Editor) and modify field properties for the Contacts module.

Look at the provided trajectory frames and final screenshot. Did the agent at any point navigate to the Settings/Admin area, specifically the "Module Layouts & Fields" or "Layout Editor" screen? Look for a drag-and-drop layout interface, field lists, or "Field Properties" modal dialog boxes.

Respond with a JSON object containing a boolean "used_layout_editor" and a short "reason" string.
Example: {"used_layout_editor": true, "reason": "Saw the Layout Editor screen with the field blocks visible."}
"""

def verify_customize_contact_layout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Error: copy_from_env not available"}

    score = 0
    feedback_parts = []
    
    # Extract results from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/customize_contact_layout_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Verify Title Key Field View
    if str(result.get("title_summary")) == "1":
        score += 20
        feedback_parts.append("✅ Title set to Summary View")
    else:
        feedback_parts.append("❌ Title NOT set to Summary View")

    # 2. Verify Mobile Key Field View
    if str(result.get("mobile_summary")) == "1":
        score += 20
        feedback_parts.append("✅ Mobile Phone set to Summary View")
    else:
        feedback_parts.append("❌ Mobile Phone NOT set to Summary View")

    # 3. Verify Department Key Field View
    if str(result.get("department_summary")) == "1":
        score += 20
        feedback_parts.append("✅ Department set to Summary View")
    else:
        feedback_parts.append("❌ Department NOT set to Summary View")

    # 4. Verify Email Mandatory Field
    email_type = result.get("email_typeofdata", "")
    if "~M" in email_type:
        score += 30
        feedback_parts.append("✅ Email set to Mandatory")
    else:
        feedback_parts.append(f"❌ Email NOT set to Mandatory (Found type: {email_type})")

    # 5. VLM Trajectory Verification (Anti-gaming / Workflow proof)
    query_vlm = env_info.get('query_vlm')
    used_ui = False
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_result = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    used_ui = parsed.get("used_layout_editor", False)
                    vlm_reason = parsed.get("reason", "")
                    
                    if used_ui:
                        score += 10
                        feedback_parts.append(f"✅ VLM Trajectory Verified: {vlm_reason}")
                    else:
                        feedback_parts.append(f"⚠️ VLM Check failed: {vlm_reason}")
                else:
                    feedback_parts.append("⚠️ VLM request failed")
            else:
                feedback_parts.append("⚠️ No frames available for VLM verification")
        except Exception as e:
            logger.error(f"VLM Verification error: {e}")
            feedback_parts.append("⚠️ VLM Exception occurred")
    else:
        feedback_parts.append("⚠️ VLM not enabled")
        # Give free points if VLM isn't available to not penalize
        score += 10 

    # Key criteria: Must have made the email mandatory and set at least two summary fields
    summary_fields_set = sum([
        str(result.get("title_summary")) == "1",
        str(result.get("mobile_summary")) == "1",
        str(result.get("department_summary")) == "1"
    ])
    
    key_criteria_met = ("~M" in email_type) and (summary_fields_set >= 2)
    
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }