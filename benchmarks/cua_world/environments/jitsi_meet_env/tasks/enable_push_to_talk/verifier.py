#!/usr/bin/env python3
"""
Verifier for enable_push_to_talk task.

Verification Strategy:
1. File Existence: Checks that 3 specific screenshots exist and were created during the task.
2. VLM Content Verification:
   - ptt_settings.png: Must show Settings dialog with "Push to talk" checked.
   - ptt_inactive.png: Must show meeting interface with Muted microphone.
   - ptt_active.png: Must show meeting interface with Unmuted microphone (indicating key press).
"""

import json
import os
import tempfile
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_push_to_talk(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "Capabilities missing (copy or VLM)"}

    # 1. Load Task Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    files_info = result.get('files', {})
    score = 0
    feedback_lines = []

    # 2. Retrieve Screenshots for VLM Analysis
    # We need to copy the agent's screenshots from the container to host temp files
    temp_dir = tempfile.mkdtemp()
    
    images_to_verify = {}
    
    try:
        for key in ['settings', 'inactive', 'active']:
            info = files_info.get(key, {})
            if info.get('exists') and info.get('created_during_task') and info.get('size', 0) > 1000:
                local_path = os.path.join(temp_dir, f"{key}.png")
                try:
                    copy_from_env(info['path'], local_path)
                    images_to_verify[key] = local_path
                    score += 10 # Points for valid file creation
                    feedback_lines.append(f"File {key} created successfully.")
                except Exception as e:
                    feedback_lines.append(f"Failed to copy {key}: {e}")
            else:
                feedback_lines.append(f"File {key} missing or invalid.")

        # 3. VLM Analysis
        
        # Check Settings Image
        if 'settings' in images_to_verify:
            prompt_settings = (
                "This is a screenshot of a video conferencing settings dialog. "
                "Is the 'Push to talk' option visible AND checked/enabled? "
                "Answer yes/no and explain."
            )
            vlm_res = query_vlm(prompt=prompt_settings, image=images_to_verify['settings'])
            if vlm_res.get('success'):
                # Simple keyword check in reasoning or a structured parse if available
                # Assuming the VLM returns a boolean 'yes' or positive reasoning
                text = vlm_res.get('text', '').lower()
                parsed = vlm_res.get('parsed', {})
                # Some VLMs might return structured dicts if requested, but text is safer fallback
                if "yes" in text or "checked" in text or "enabled" in text:
                    score += 30
                    feedback_lines.append("VLM: confirmed 'Push to talk' is enabled in settings.")
                else:
                    feedback_lines.append(f"VLM: Could not confirm PTT enabled in settings. Response: {text}")
            else:
                feedback_lines.append("VLM error on settings image.")

        # Check Inactive State (Muted)
        if 'inactive' in images_to_verify:
            prompt_inactive = (
                "This is a Jitsi Meet interface. Look at the microphone icon (usually bottom center). "
                "Is the microphone MUTED (slashed out or indicating inactive)? "
                "Answer yes/no."
            )
            vlm_res = query_vlm(prompt=prompt_inactive, image=images_to_verify['inactive'])
            text = vlm_res.get('text', '').lower() if vlm_res.get('success') else ""
            if "yes" in text or "muted" in text:
                score += 20
                feedback_lines.append("VLM: confirmed microphone is muted (inactive state).")
            else:
                feedback_lines.append("VLM: Microphone does not appear muted in inactive screenshot.")

        # Check Active State (Unmuted)
        if 'active' in images_to_verify:
            prompt_active = (
                "This is a Jitsi Meet interface. Look at the microphone icon (usually bottom center). "
                "Is the microphone UNMUTED (active/transmitting)? "
                "Answer yes/no."
            )
            vlm_res = query_vlm(prompt=prompt_active, image=images_to_verify['active'])
            text = vlm_res.get('text', '').lower() if vlm_res.get('success') else ""
            if "yes" in text or "unmuted" in text or "active" in text:
                score += 30
                feedback_lines.append("VLM: confirmed microphone is unmuted (active state).")
            else:
                feedback_lines.append("VLM: Microphone does not appear unmuted in active screenshot.")

        # Check that active and inactive are different
        if 'active' in images_to_verify and 'inactive' in images_to_verify:
            # Basic check: file sizes shouldn't be identical (unlikely for screenshots even if nothing changed, but good sanity check)
            s_active = os.path.getsize(images_to_verify['active'])
            s_inactive = os.path.getsize(images_to_verify['inactive'])
            if s_active == s_inactive:
                feedback_lines.append("WARNING: Active and Inactive screenshots are identical bytes.")
                score -= 10 # Penalty for duplicate files
            else:
                 score += 10 # Bonus for distinct evidence
                 feedback_lines.append("Evidence files are distinct.")

    finally:
        shutil.rmtree(temp_dir)

    # Pass Threshold
    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_lines)
    }