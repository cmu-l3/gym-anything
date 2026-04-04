#!/usr/bin/env python3
"""
Verifier for check_running_memory task.

Requires:
1. Android Developer Options enabled (verified via settings get)
2. Audit text file with RAM value (verified via file content)
3. Screenshot of Running Services (verified via VLM)
"""

import json
import os
import tempfile
import logging
import re

# Import VLM utilities from framework
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Fallback for local testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_check_running_memory(traj, env_info, task_info):
    """
    Verifies that the agent enabled dev options and documented memory usage.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Host error: copy_from_env not available"}

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_json.close()
    
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        if os.path.exists(temp_json.name): os.unlink(temp_json.name)
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    
    os.unlink(temp_json.name)

    # 2. Retrieve Evidence Screenshot
    # Note: We prioritize the agent-taken screenshot for specific evidence, 
    # but verify against trajectory to prevent pre-baked image usage if needed.
    # For this task, the agent taking the screenshot is part of the instructions.
    evidence_path = "/sdcard/ram_evidence.png"
    temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    temp_img.close()
    
    has_evidence_img = False
    try:
        if result_data.get("evidence_screenshot_exists"):
            copy_from_env(evidence_path, temp_img.name)
            has_evidence_img = True
    except Exception:
        pass

    # --- SCORING ---
    score = 0
    feedback = []
    
    # Criterion 1: Developer Options Enabled (40 pts)
    # settings get returns "1" or "null" or "0"
    dev_enabled_raw = str(result_data.get("dev_options_enabled", "0")).strip()
    if dev_enabled_raw == "1":
        score += 40
        feedback.append("Developer Options enabled (+40)")
    else:
        feedback.append("Failed to enable Developer Options")

    # Criterion 2: Audit File Created (20 pts)
    audit_content = result_data.get("audit_content", "").strip()
    if result_data.get("audit_file_exists") and len(audit_content) > 0:
        score += 20
        feedback.append(f"Memory value recorded: {audit_content} (+20)")
        
        # Check if content looks like memory value (digits + optional unit)
        if re.search(r'\d+', audit_content):
            pass # Valid
        else:
            feedback.append("(Warning: Recorded value doesn't look like a number)")
    else:
        feedback.append("Memory audit file missing or empty")

    # Criterion 3: Evidence Screenshot Exists (10 pts)
    if has_evidence_img:
        score += 10
        feedback.append("Evidence screenshot saved (+10)")
    else:
        feedback.append("Evidence screenshot missing")

    # Criterion 4: Visual Verification (30 pts)
    # We check the specific evidence screenshot if it exists, otherwise final state
    image_to_check = temp_img.name if has_evidence_img else get_final_screenshot(traj)
    
    if image_to_check and os.path.exists(image_to_check) and os.path.getsize(image_to_check) > 0:
        vlm_prompt = """
        Review this screenshot from an Android device.
        1. Does it show the 'Running services' screen (or 'Process Stats')?
        2. Is 'Flight Crew View' (or 'com.robert.fcView') visible in the list?
        3. Can you see a memory/RAM usage value next to it?
        
        Return JSON: {"is_running_services": bool, "app_visible": bool, "ram_visible": bool}
        """
        
        vlm_res = query_vlm(
            prompt=vlm_prompt,
            images=[image_to_check] 
        )
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("is_running_services"):
                score += 10
                feedback.append("Screen matches 'Running services' (+10)")
            if parsed.get("app_visible"):
                score += 10
                feedback.append("Flight Crew View process visible (+10)")
            if parsed.get("ram_visible"):
                score += 10
                feedback.append("RAM usage value visible (+10)")
        else:
            feedback.append("Visual verification failed (VLM error)")
    else:
        feedback.append("No valid image for visual verification")

    # Cleanup
    if os.path.exists(temp_img.name):
        os.unlink(temp_img.name)

    # Final Pass Determination
    # Must have enabled dev options and recorded data (score >= 60 implies decent partial success, 
    # but strict pass requires dev options enabled)
    passed = (dev_enabled_raw == "1") and (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }