#!/usr/bin/env python3
"""
Verifier for Configure Display Prefs task.

Verifies:
1. Expected text file was created with correct settings listed.
2. Expected screenshot was captured and is of reasonable size.
3. Actual Weasis config files contain the updated settings (Nearest Neighbor, Best Fit, 16pt+ Font).
4. VLM verifies that the Preferences dialog was opened during the trajectory.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import VLM tools safely
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM utilities not available. VLM checks will be skipped.")


VLM_TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent interacting with a DICOM Viewer.
Did the agent open the 'Preferences' or 'Settings' dialog window at any point in these frames?
Look for a popup window titled "Preferences", "Settings", or showing configuration options like "Viewer 2D", "Image Display", "Interpolation", or "Annotations".

Respond in JSON format:
{
    "preferences_opened": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what was seen"
}"""


def verify_configure_display_prefs(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Text File Verification (20 pts)
    text_exists = result.get('text_file_exists', False)
    text_created = result.get('text_created_during_task', False)
    text_content = result.get('text_content', '').lower()

    if text_exists and text_created:
        has_interpolation = 'nearest' in text_content
        has_zoom = 'fit' in text_content or 'bestfit' in text_content
        has_font = re.search(r'font[_\s]*size\s*=\s*(1[6-9]|[2-9][0-9])', text_content)

        if has_interpolation and has_zoom and has_font:
            score += 20
            feedback_parts.append("Text file verified (all keys present)")
        else:
            score += 10
            feedback_parts.append("Text file exists but missing some exact keys/values")
    elif text_exists:
        feedback_parts.append("Text file exists but was NOT created during task (Anti-gaming)")
    else:
        feedback_parts.append("Text file missing")

    # 2. Image Verification (20 pts)
    image_exists = result.get('image_file_exists', False)
    image_created = result.get('image_created_during_task', False)
    image_size = result.get('image_size_bytes', 0)

    if image_exists and image_created and image_size > 10240: # > 10 KB
        score += 20
        feedback_parts.append("Screenshot exported successfully")
    elif image_exists and image_created:
        score += 10
        feedback_parts.append(f"Screenshot exists but size is suspiciously small ({image_size} bytes)")
    else:
        feedback_parts.append("Screenshot missing or not created during task")

    # 3. Weasis Config Verification (45 pts total)
    configs = result.get('final_configs', '').lower()
    
    # Interpolation Check (15 pts)
    if 'nearest' in configs or 'neighbor' in configs:
        score += 15
        feedback_parts.append("Config updated: Interpolation (Nearest)")
    else:
        feedback_parts.append("Config missing: Interpolation change")

    # Zoom Check (15 pts)
    if 'fit' in configs or 'best' in configs:
        score += 15
        feedback_parts.append("Config updated: Zoom (Best Fit)")
    else:
        feedback_parts.append("Config missing: Zoom change")

    # Font Size Check (15 pts) - looks for standard font XML tags > 15
    # e.g. <property name="font.size" value="16"/> or similar UI strings
    font_changed = any(str(size) in configs for size in range(16, 36))
    if font_changed:
        score += 15
        feedback_parts.append("Config updated: Font Size (>=16)")
    else:
        feedback_parts.append("Config missing: Font Size change")

    # 4. VLM Trajectory Verification (15 pts)
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=6)
            vlm_res = query_vlm(prompt=VLM_TRAJECTORY_PROMPT, images=frames)
            
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('preferences_opened', False):
                    score += 15
                    feedback_parts.append("VLM confirmed Preferences dialog usage")
                else:
                    feedback_parts.append("VLM did not detect Preferences dialog usage")
            else:
                feedback_parts.append("VLM analysis failed")
        except Exception as e:
            logger.warning(f"VLM verification exception: {e}")
            feedback_parts.append("VLM exception")
    else:
        # If VLM is not available, grant points if config checks passed to avoid punishing the agent
        if score >= 65:
            score += 15
            feedback_parts.append("VLM skipped; points awarded based on config success")

    # Calculate final status
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }