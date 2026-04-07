#!/usr/bin/env python3
import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_branding(traj, env_info, task_info):
    """
    Verify that the agent successfully rebranded Socioboard.
    Uses multi-signal verification:
    1. Timestamps (detects do-nothing)
    2. File-based grep (detects code level intent)
    3. HTTP Response (detects functional frontend configuration)
    4. VLM (Visual verification of the branding applying successfully)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    feedback = []

    # Criterion 1: Anti-gaming Timestamp Check (10 pts)
    mods = result.get("modified_files_count", 0)
    if mods > 0:
        score += 10
        feedback.append(f"Files correctly modified during task ({mods} detected)")
    else:
        feedback.append("No files were modified (did nothing)")

    # Criterion 2: HTML Page Title updates (30 pts max)
    if result.get("file_has_title_count", 0) > 0:
        score += 15
        feedback.append("Title updated in codebase")
    if result.get("http_has_title", False):
        score += 15
        feedback.append("Title correctly served via HTTP")

    # Criterion 3: Login Text updates (30 pts max)
    if result.get("file_has_login_count", 0) > 0:
        score += 15
        feedback.append("Login text updated in codebase")
    if result.get("http_has_login", False):
        score += 15
        feedback.append("Login text correctly served via HTTP")

    # Criterion 4: CSS/Color Updates (10 pts)
    if result.get("file_has_color_count", 0) > 0:
        score += 10
        feedback.append("Branding color (#1B2A4A) applied in codebase")

    # Criterion 5: VLM Verification using trajectory & final rendering (20 pts max)
    frames = sample_trajectory_frames(traj, n=3)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames

    if images:
        vlm_prompt = """You are evaluating a UI branding task. Look at these screenshots of a web application.
Does the final UI show:
1. A dark navy blue top navigation bar?
2. Text containing 'Apex Digital Media' on the page?

Respond strictly in JSON format:
{
    "has_dark_navbar": true/false,
    "has_apex_text": true/false
}"""
        try:
            vlm_result = query_vlm(images=images, prompt=vlm_prompt)
            parsed = vlm_result.get("parsed", {})
            if parsed.get("has_dark_navbar", False):
                score += 10
                feedback.append("VLM: Confirmed dark navbar visibility")
            if parsed.get("has_apex_text", False):
                score += 10
                feedback.append("VLM: Confirmed 'Apex' text visibility")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback.append("VLM check failed or was inconclusive")
    else:
        feedback.append("No screenshots available for VLM verification")

    # Pass logic: Must have touched files AND got at least 60 total score
    key_criteria_met = (mods > 0) and (score >= 60)
    
    return {
        "passed": key_criteria_met,
        "score": score,
        "feedback": " | ".join(feedback)
    }