#!/usr/bin/env python3
"""
Verifier for restrict_to_qr_only task.

VERIFICATION STRATEGY:
1. Validates the existence and timestamp of the required evidence screenshot.
2. Programmatically checks the Windows Registry settings (if keys match known bcWebCam patterns).
3. Uses VLM hybrid verification on the agent-saved screenshot to confirm settings toggles.
4. Uses VLM on the trajectory frames to verify actual UI navigation.
"""

import json
import tempfile
import os
import sys
import logging
from pathlib import Path

# Add standard gym_anything VLM utilities
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
except ImportError:
    # Fallback to local import if environment is structured differently
    sys.path.insert(0, str(Path(__file__).parent.parent))
    try:
        from vlm_utils import query_vlm
        from gym_anything.vlm import sample_trajectory_frames
    except ImportError:
        pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_restrict_to_qr_only(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0
    max_score = 100

    # 1. Fetch Task Results JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check Expected Output Screenshot (Anti-Gaming)
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_created_during_task = result.get('screenshot_created_during_task', False)
    
    local_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
    has_user_screenshot = False

    if screenshot_exists and screenshot_created_during_task:
        score += 20
        feedback.append("Evidence screenshot saved correctly during task.")
        try:
            copy_from_env("C:\\Users\\Docker\\Documents\\qr_only_config.png", local_screenshot)
            has_user_screenshot = True
        except:
            feedback.append("Failed to download screenshot for VLM check.")
    elif screenshot_exists:
        score += 5
        feedback.append("Evidence screenshot exists but timestamp is invalid (existed before task).")
    else:
        feedback.append("Required evidence screenshot was NOT saved to Documents.")

    # 3. Registry Programmatic Check
    reg_data = result.get("registry_data", {})
    reg_checked = False
    qr_enabled_reg = False
    others_disabled_reg = True

    for k, v in reg_data.items():
        k_lower = k.lower()
        val_str = str(v).lower()
        if "qr" in k_lower:
            reg_checked = True
            if val_str in ["1", "true"]:
                qr_enabled_reg = True
        elif any(x in k_lower for x in ["ean", "upc", "128", "39", "datamatrix", "aztec", "pdf417", "linear"]):
            reg_checked = True
            if val_str in ["1", "true"]:
                others_disabled_reg = False

    if reg_checked:
        if qr_enabled_reg and others_disabled_reg:
            score += 20
            feedback.append("Registry confirms QR Code is the only enabled symbology.")
        else:
            feedback.append("Registry indicates incorrect barcode settings.")

    # 4. VLM Verification on the Evidence Screenshot
    vlm_qr_enabled = False
    vlm_others_disabled = False

    if has_user_screenshot:
        prompt = """Analyze this settings window screenshot from a barcode scanner.
        Look specifically at the barcode types/symbologies configuration checkboxes.
        
        Answer these questions:
        1. Is this a settings window showing barcode options?
        2. Is the "QR Code" option visibly CHECKED (enabled)?
        3. Are all other barcode options (e.g., EAN, UPC, Code 128, DataMatrix, PDF417, Aztec) visibly UNCHECKED (disabled)?
        
        Respond in JSON format:
        {
            "is_settings_window": true/false,
            "qr_code_enabled": true/false,
            "other_barcodes_disabled": true/false,
            "reasoning": "brief explanation of what you see"
        }"""
        
        try:
            vlm_res = query_vlm(prompt=prompt, image=local_screenshot)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("is_settings_window"):
                    if parsed.get("qr_code_enabled"):
                        vlm_qr_enabled = True
                        score += 30
                        feedback.append("VLM visual check: QR Code is checked.")
                    else:
                        feedback.append("VLM visual check: QR Code is NOT checked.")
                    
                    if parsed.get("other_barcodes_disabled"):
                        vlm_others_disabled = True
                        score += 30
                        feedback.append("VLM visual check: All other barcodes are unchecked.")
                    else:
                        feedback.append("VLM visual check: Some non-QR barcodes are STILL checked.")
                else:
                    feedback.append("Saved screenshot does not appear to show barcode settings.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    # 5. Trajectory Verification (Ensure agent navigated)
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames and not reg_checked: # Only strictly rely on trajectory if programmatic registry failed
            traj_prompt = """Look at these chronological screenshots. 
            Did the user explicitly open the settings/options dialog and navigate to the barcode configuration section?
            Respond with JSON: {"navigated_to_settings": true/false}"""
            traj_res = query_vlm(prompt=traj_prompt, images=frames)
            if traj_res and traj_res.get("success"):
                if traj_res.get("parsed", {}).get("navigated_to_settings"):
                    if not reg_checked:
                        score += 20
                    feedback.append("Trajectory confirms navigation to settings.")
    except Exception as e:
        pass

    # Clean up local temp file
    if os.path.exists(local_screenshot):
        os.unlink(local_screenshot)

    # Passing Criteria: Score >= 70 AND QR Code visually verified as enabled AND visually verified as the only one
    key_criteria_met = vlm_qr_enabled and vlm_others_disabled and screenshot_created_during_task
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }