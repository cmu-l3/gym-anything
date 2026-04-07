#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
import sys

# Add utils to path (relative to this file, for host execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring Weasis DICOM Viewer.
The agent was asked to change the application UI to a Dark Theme and increase the UI font size to at least 16.

Look at the progression of the screenshots (from early to late):
1. Did the application interface (menus, toolbars, side panels, window background) change to a Dark Theme (dark gray/black) by the end of the sequence?
2. Did the text size in the application interface (e.g., menu items, toolbar labels, panel titles) noticeably increase by the end of the sequence?

Respond in JSON format:
{
    "dark_theme_applied": true/false,
    "font_size_increased": true/false,
    "confidence": "high/medium/low",
    "reasoning": "brief explanation"
}
"""

def verify_configure_ergonomic_ui(traj, env_info, task_info):
    """
    Verify that the Weasis UI theme and font size were correctly modified.
    Uses multiple signals: output files, configuration file content, and VLM checking of trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_font_size = metadata.get('min_font_size', 16)
    
    # Read result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Output files evaluation (20 pts)
    files_exist = result.get('screenshot_exists', False) and result.get('report_exists', False)
    files_created = result.get('screenshot_created_during_task', False) and result.get('report_created_during_task', False)
    
    if files_exist and files_created:
        score += 20
        feedback_parts.append("Export files created successfully")
    elif files_exist:
        score += 10
        feedback_parts.append("Export files exist but creation time is suspect")
    else:
        feedback_parts.append("Expected export files not found")
        
    # 2. Text Report Content (10 pts)
    report_content = result.get('report_content', '').lower()
    has_dark = 'dark' in report_content or 'darcula' in report_content
    numbers = [int(n) for n in re.findall(r'\b(1[6-9]|[2-9][0-9])\b', report_content)]
    has_large_font = len(numbers) > 0
    
    if has_dark and has_large_font:
        score += 10
        feedback_parts.append("Report confirms dark theme and font size")
    elif has_dark or has_large_font:
        score += 5
        feedback_parts.append("Report content partially correct")
    else:
        feedback_parts.append("Report lacks required configuration details")
        
    # 3. Weasis Properties Check (10 pts)
    prefs_theme = result.get('prefs_theme', '').lower()
    prefs_font_str = result.get('prefs_font', '').strip()
    prefs_font = 0
    try:
        if prefs_font_str:
            prefs_font = int(prefs_font_str)
    except:
        pass
        
    prefs_dark = 'dark' in prefs_theme or 'darcula' in prefs_theme
    prefs_font_ok = prefs_font >= min_font_size
    
    if prefs_dark and prefs_font_ok:
        score += 10
        feedback_parts.append("Properties confirm settings applied")
    elif prefs_dark or prefs_font_ok:
        score += 5
        feedback_parts.append("Properties confirm partial settings")

    # 4. VLM Verification (60 pts)
    vlm_dark = False
    vlm_font = False
    
    try:
        # Retrieve trajectory framing utils
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            if final:
                frames.append(final)
            
            if frames:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    vlm_dark = parsed.get("dark_theme_applied", False)
                    vlm_font = parsed.get("font_size_increased", False)
                    
                    if vlm_dark:
                        score += 30
                        feedback_parts.append("VLM confirms Dark theme visible")
                    else:
                        feedback_parts.append("VLM: Dark theme not applied")
                        
                    if vlm_font:
                        score += 30
                        feedback_parts.append("VLM confirms larger UI font")
                    else:
                        feedback_parts.append("VLM: Font size not noticeably increased")
                else:
                    feedback_parts.append("VLM query failed")
            else:
                feedback_parts.append("No trajectory frames available for VLM")
        else:
            feedback_parts.append("VLM not available")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append("VLM verification error")

    # Final logic
    # The agent MUST have applied at least one configuration visually/via settings AND exported files
    key_criteria_met = (vlm_dark or vlm_font or (prefs_dark and prefs_font_ok)) and files_exist
    
    passed = score >= 60 and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }