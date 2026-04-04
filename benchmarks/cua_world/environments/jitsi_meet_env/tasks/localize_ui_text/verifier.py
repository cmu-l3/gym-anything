#!/usr/bin/env python3
"""
Verifier for localize_ui_text task.

Criteria:
1. Localization file modification (60 points):
   - 'welcomepage.joinMeeting' == "Enter Consultation"
   - 'welcomepage.enterDisplayName' == "Patient Name"
2. Visual Evidence (40 points):
   - Agent created screenshot evidence
   - VLM confirms the text "Enter Consultation" and "Patient Name" is visible in the final UI
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_localize_ui_text(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # ------------------------------------------------------------------
    # 1. Verify JSON Content (60 points)
    # ------------------------------------------------------------------
    lang_file_exported = result_data.get("lang_file_exported", False)
    
    if lang_file_exported:
        temp_lang = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/jitsi_main.json", temp_lang.name)
            with open(temp_lang.name, 'r') as f:
                lang_data = json.load(f)
            
            # Check keys
            # Note: Keys might be nested or flat depending on Jitsi version, 
            # but usually flat in main.json for these specific keys or under "welcomepage" dict.
            # We check both flat dotted access (common in i18n libs) and nested dicts.
            
            def get_val(data, key):
                # Try direct key
                if key in data: return data[key]
                # Try nested
                parts = key.split('.')
                curr = data
                for p in parts:
                    if isinstance(curr, dict) and p in curr:
                        curr = curr[p]
                    else:
                        return None
                return curr

            # Check Button Text
            val_button = get_val(lang_data, "welcomepage.joinMeeting")
            if val_button == "Enter Consultation":
                score += 30
                feedback.append("Button text correctly updated in JSON.")
            else:
                feedback.append(f"Button text incorrect in JSON. Found: '{val_button}'")

            # Check Placeholder Text
            val_placeholder = get_val(lang_data, "welcomepage.enterDisplayName")
            if val_placeholder == "Patient Name":
                score += 30
                feedback.append("Placeholder text correctly updated in JSON.")
            else:
                feedback.append(f"Placeholder text incorrect in JSON. Found: '{val_placeholder}'")

        except json.JSONDecodeError:
            feedback.append("Failed to parse main.json - invalid JSON format.")
        except Exception as e:
            feedback.append(f"Error reading language file: {e}")
        finally:
            if os.path.exists(temp_lang.name):
                os.unlink(temp_lang.name)
    else:
        feedback.append("Could not export language file from container.")

    # ------------------------------------------------------------------
    # 2. Visual Verification (40 points)
    # ------------------------------------------------------------------
    
    # Check if agent saved evidence (10 points)
    if result_data.get("evidence_screenshot_exists", False):
        score += 10
        feedback.append("Evidence screenshot created.")
    else:
        feedback.append("Evidence screenshot NOT created.")

    # VLM Check on Final State (30 points)
    final_screenshot = get_final_screenshot(traj)
    
    vlm_prompt = """
    Analyze this screenshot of the Jitsi Meet pre-join screen.
    I am looking for specific custom text changes:
    1. Does the main action button say "Enter Consultation"?
    2. Does the name input field have placeholder text "Patient Name"?
    
    Respond in JSON:
    {
        "button_text_correct": boolean,
        "placeholder_text_correct": boolean,
        "observed_button_text": "string",
        "observed_placeholder_text": "string"
    }
    """
    
    vlm_result = query_vlm(vlm_prompt, image=final_screenshot)
    
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("button_text_correct", False):
            score += 15
            feedback.append("VLM confirms button text 'Enter Consultation' visible.")
        else:
            feedback.append(f"VLM did not see correct button text. Saw: {parsed.get('observed_button_text')}")
            
        if parsed.get("placeholder_text_correct", False):
            score += 15
            feedback.append("VLM confirms placeholder 'Patient Name' visible.")
        else:
            feedback.append(f"VLM did not see correct placeholder. Saw: {parsed.get('observed_placeholder_text')}")
    else:
        feedback.append("VLM verification failed or inconclusive.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }