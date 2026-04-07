#!/usr/bin/env python3
"""
Verifier for configure_scan_suffix task in bcWebCam.

Verification Strategy (Hybrid):
1. Registry verification (if configuration changes are accessible via HKCU)
2. Trajectory VLM verification (visual confirmation of dialog navigation & exact text field)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_scan_suffix(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_suffix = metadata.get('expected_suffix', '|;')

    # 1. Read exported execution state
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load task_result.json: {e}")
        result = {}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Basic Checks
    app_running = result.get('app_was_running', False)
    if app_running:
        score += 10
        feedback_parts.append("bcWebCam is running")
    else:
        feedback_parts.append("bcWebCam is NOT running")

    # 3. Direct Registry state validation
    registry_suffix = result.get('registry_suffix')
    registry_checked = False
    
    if registry_suffix is not None and registry_suffix != "":
        registry_checked = True
        if expected_suffix in registry_suffix:
            score += 40
            feedback_parts.append(f"Registry shows correct suffix '{registry_suffix}'")
        else:
            feedback_parts.append(f"Registry shows incorrect suffix '{registry_suffix}'")

    # 4. Trajectory VLM Verification
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            VLM_PROMPT = f"""You are evaluating an agent's performance on configuring the bcWebCam barcode scanner.
The user's goal was to set the "Suffix" field in the settings/options to the exact string `{expected_suffix}`.

Look at the provided trajectory frames of the agent's screen:
1. Did the agent open the Options/Settings dialog?
2. Is the "Suffix" field visible in any frame?
3. Does the "Suffix" field contain the string `{expected_suffix}`?
4. Is there evidence that the agent clicked OK or applied the changes?

Respond ONLY with a valid JSON object:
{{
    "opened_settings": true/false,
    "suffix_visible": true/false,
    "suffix_correct": true/false,
    "applied_changes": true/false
}}"""
            
            vlm_result = query_vlm(prompt=VLM_PROMPT, images=images)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("opened_settings"):
                    score += 10
                    feedback_parts.append("VLM: Settings opened")
                if parsed.get("suffix_visible"):
                    score += 10
                    feedback_parts.append("VLM: Suffix field visible")
                if parsed.get("suffix_correct"):
                    if not registry_checked:
                        score += 50  # Give bulk of points if registry check was unavailable but visually confirmed
                    feedback_parts.append(f"VLM: Suffix string visually confirmed as '{expected_suffix}'")
                if parsed.get("applied_changes"):
                    score += 20
                    feedback_parts.append("VLM: Changes applied")
            else:
                feedback_parts.append("VLM evaluation failed")
    except ImportError:
        feedback_parts.append("VLM utilities not available")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("VLM verification encountered an error")

    # 5. Evaluate final status
    passed = score >= 60 and app_running

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }