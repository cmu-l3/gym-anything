#!/usr/bin/env python3
"""
Verifier for create_web_to_lead_form task.

Checks:
1. Webform Header exists, correct name and target module.
2. Return URL is correct.
3. Standard mapped fields (lastname, company, email, phone) exist.
4. Lead Source field exists and is configured as hidden.
5. Lead Source has correct default/override value ('Web Site').
6. Anti-gaming: Webform count incremented.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_web_to_lead_form(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'B2B Landing Page')
    expected_module = metadata.get('expected_module', 'Leads')
    expected_return_url = metadata.get('expected_return_url', 'https://www.store-example.com/thank-you')
    expected_override = metadata.get('expected_override_value', 'Web Site')

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_web_to_lead_form_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    webform_found = result.get("webform_found", False)
    initial_count = result.get("initial_count", 0)
    current_count = result.get("current_count", 0)

    # 1. Anti-gaming check (Did they just modify an existing one, or actually create it?)
    if current_count > initial_count:
        feedback.append("✅ New webform record created")
    else:
        feedback.append("❌ Webform count did not increase (task requires creating a NEW webform)")
        if not webform_found:
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Header Check
    if webform_found:
        mod = result.get("target_module", "")
        if mod.lower() == expected_module.lower():
            score += 20
            feedback.append(f"✅ Webform created for correct module ({mod})")
        else:
            feedback.append(f"❌ Incorrect target module: expected {expected_module}, got {mod}")

        # 3. Return URL Check
        ret_url = result.get("return_url", "")
        if ret_url == expected_return_url:
            score += 15
            feedback.append("✅ Return URL configured correctly")
        else:
            feedback.append(f"❌ Return URL mismatch. Got: {ret_url}")

        # 4. Standard Fields Check
        fields = result.get("fields", {})
        std_fields = [
            fields.get("has_lastname", 0),
            fields.get("has_company", 0),
            fields.get("has_email", 0),
            fields.get("has_phone", 0)
        ]
        
        # Prorated points for standard fields (up to 25 pts)
        std_field_pts = sum([6.25 for f in std_fields if f > 0])
        score += std_field_pts
        if std_field_pts == 25:
            feedback.append("✅ All required standard fields mapped correctly")
        else:
            feedback.append(f"⚠️ Missing some standard fields (Mapped {sum([1 for f in std_fields if f>0])}/4)")

        # 5. Lead Source Field Check
        has_ls = fields.get("has_leadsource", 0)
        if has_ls > 0:
            score += 10
            feedback.append("✅ Lead Source field mapped to webform")
            
            ls_config = result.get("leadsource_config", {})
            
            # 6. Hidden property
            if str(ls_config.get("hidden", "0")) == "1":
                score += 15
                feedback.append("✅ Lead Source marked as Hidden")
            else:
                feedback.append("❌ Lead Source is NOT marked as Hidden")

            # 7. Override/Default value
            ls_val = ls_config.get("default_value", "")
            if ls_val == expected_override:
                score += 15
                feedback.append(f"✅ Override value set correctly ('{expected_override}')")
            else:
                feedback.append(f"❌ Override value mismatch. Expected '{expected_override}', got '{ls_val}'")
        else:
            feedback.append("❌ Lead Source field was NOT added to the webform")
            
    else:
        feedback.append(f"❌ Webform '{expected_name}' not found in database")

    # Final logic: Need the header, the hidden property, and the override value to be considered passing.
    # Pass threshold is 70, but we also require the key marketing automation steps to be complete.
    ls_config_correct = (
        webform_found and 
        fields.get("has_leadsource", 0) > 0 and 
        str(result.get("leadsource_config", {}).get("hidden", "0")) == "1" and 
        result.get("leadsource_config", {}).get("default_value", "") == expected_override
    )

    passed = (score >= 70) and ls_config_correct

    if passed:
        feedback.insert(0, "🎉 SUCCESS: Webform fully configured for marketing automation.")
    else:
        feedback.insert(0, "⚠️ FAILED: Did not meet required automation criteria.")

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback),
        "details": result
    }