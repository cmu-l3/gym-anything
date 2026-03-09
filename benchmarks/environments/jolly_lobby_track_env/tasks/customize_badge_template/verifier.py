#!/usr/bin/env python3
"""
Verifier for customize_badge_template task.

Verification Logic:
1. Programmatic Checks (40 points):
   - User saved a screenshot (10 pts)
   - User saved the badge template (file modified check) (15 pts)
   - Template file contains required strings ("VISITOR PASS", "TechVision") (15 pts)

2. VLM Verification (60 points):
   - Trajectory analysis to confirm Badge Designer was opened.
   - visual check for "VISITOR PASS" title.
   - Visual check for "Visitor Name" field.
   - Visual check for "Date" field.
   - Visual check for "TechVision Industries" footer.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_customize_badge_template(traj, env_info, task_info):
    """
    Verify the badge customization task using file checks and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load Programmatic Results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # --- Criteria 1: User Screenshot (10 pts) ---
    if result.get("user_screenshot_valid", False):
        score += 10
        feedback_parts.append("✅ Screenshot saved correctly.")
    elif result.get("user_screenshot_exists", False):
        score += 5
        feedback_parts.append("⚠️ Screenshot exists but has invalid timestamp/size.")
    else:
        feedback_parts.append("❌ Screenshot not found.")

    # --- Criteria 2: Template Saved (15 pts) ---
    if result.get("template_modified", False):
        score += 15
        feedback_parts.append("✅ Badge template file saved.")
    else:
        feedback_parts.append("❌ No badge template file modification detected (Did you save?).")

    # --- Criteria 3: String Verification in File (15 pts) ---
    # We check if the saved file contains the text. This is a strong signal if the file format isn't encrypted/compressed.
    # We give partial credit here because binary formats might obscure strings.
    str_score = 0
    if result.get("found_visitor_pass_string", False):
        str_score += 7.5
    if result.get("found_techvision_string", False):
        str_score += 7.5
    
    if str_score > 0:
        score += str_score
        feedback_parts.append(f"✅ Found required text in saved file (+{str_score} pts).")
    
    # --- Criteria 4: VLM Visual Verification (60 pts) ---
    # We check the user's screenshot (if it exists) AND trajectory frames
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    # If user took a screenshot, we should try to use that for verification too, 
    # but since it's inside the VM, we rely on the framework capturing the screen.
    # The final_screen is usually good enough.

    vlm_prompt = """
    You are verifying a task in Jolly Lobby Track software. The user was asked to customize a visitor badge.
    
    Review the image sequence. The user should have:
    1. Opened the Badge Designer window (look for a canvas with tools around it).
    2. Changed the badge title to "VISITOR PASS".
    3. Ensured a "Visitor Name" field is visible.
    4. Ensured a "Date" or "Date/Time" field is visible.
    5. Added a footer text "TechVision Industries".
    
    Assess the FINAL state of the design visible in the screenshots.
    
    Return JSON:
    {
        "badge_designer_opened": boolean,
        "title_visitor_pass_visible": boolean,
        "name_field_visible": boolean,
        "date_field_visible": boolean,
        "footer_techvision_visible": boolean,
        "confidence": "low|medium|high"
    }
    """
    
    images_to_check = frames + [final_screen] if final_screen else frames
    
    if not images_to_check:
        feedback_parts.append("❌ No screenshots available for visual verification.")
    else:
        vlm_res = query_vlm(
            prompt=vlm_prompt,
            images=images_to_check
        )
        
        if vlm_res.get("success"):
            analysis = vlm_res.get("parsed", {})
            
            # Badge Designer Open (10 pts)
            if analysis.get("badge_designer_opened"):
                score += 10
                feedback_parts.append("✅ Badge Designer was accessed.")
            else:
                feedback_parts.append("❌ Badge Designer not clearly seen.")

            # Title Check (15 pts)
            if analysis.get("title_visitor_pass_visible"):
                score += 15
                feedback_parts.append("✅ Title 'VISITOR PASS' visible.")
            else:
                feedback_parts.append("❌ Title 'VISITOR PASS' not found.")

            # Name Field (10 pts)
            if analysis.get("name_field_visible"):
                score += 10
                feedback_parts.append("✅ Name field visible.")
            else:
                feedback_parts.append("❌ Name field missing.")

            # Date Field (10 pts)
            if analysis.get("date_field_visible"):
                score += 10
                feedback_parts.append("✅ Date field visible.")
            else:
                feedback_parts.append("❌ Date field missing.")

            # Footer Check (15 pts)
            if analysis.get("footer_techvision_visible"):
                score += 15
                feedback_parts.append("✅ Footer 'TechVision Industries' visible.")
            else:
                feedback_parts.append("❌ Footer 'TechVision Industries' not found.")
        else:
             feedback_parts.append(f"⚠️ VLM verification failed: {vlm_res.get('error')}")

    # Final Pass/Fail Check
    # Pass threshold: 60 points + Key Requirements (Template Saved OR VLM confirms Visuals)
    # This allows passing if file format is binary (grep fails) but VLM sees it, 
    # OR if VLM is unsure but file analysis is perfect.
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback_parts)
    }