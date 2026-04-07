#!/usr/bin/env python3
"""
Verifier for localize_frontend_spanish task.

This verifier ensures that:
1. The app renders the login page in Spanish.
2. The agent correctly configured the app locale.
3. The agent created the proper language abstraction (resources/lang/es).
4. The agent DID NOT simply hardcode the Spanish text directly into the HTML/Blade templates.
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_localization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract states
    html_has_correo = result.get('html_has_correo', 0) > 0
    html_has_contra = result.get('html_has_contra', 0) > 0
    html_has_iniciar = result.get('html_has_iniciar', 0) > 0
    
    views_hardcoded = result.get('views_hardcoded', 0)
    lang_dir_exists = result.get('lang_dir_exists', False)
    lang_has_trans = result.get('lang_has_trans', 0) > 0
    locale_set = result.get('locale_set', False)
    lang_created_during_task = result.get('lang_created_during_task', False)

    # 1. Locale Configuration (15 points)
    if locale_set:
        score += 15
        feedback_parts.append("Locale configured to 'es'")
    else:
        feedback_parts.append("Locale NOT configured to 'es'")

    # 2. Language Abstraction / Files (25 points)
    if lang_dir_exists and lang_has_trans:
        if lang_created_during_task:
            score += 25
            feedback_parts.append("Spanish lang file created with translations")
        else:
            score += 10
            feedback_parts.append("Lang file exists but modification time is questionable")
    else:
        feedback_parts.append("Missing or incomplete resources/lang/es directory")

    # 3. Web Output Translated (30 points)
    rendered_correctly = html_has_correo and html_has_contra and html_has_iniciar
    if rendered_correctly:
        score += 30
        feedback_parts.append("Web interface successfully renders Spanish text")
    else:
        feedback_parts.append("Web interface is missing required Spanish translations")

    # 4. Proper i18n Architecture / Anti-Gaming (30 points)
    # They only get these points if they DIDN'T hardcode the text AND the text actually appears in the render
    if views_hardcoded == 0:
        if rendered_correctly and lang_has_trans:
            score += 30
            feedback_parts.append("Correct i18n implementation (No hardcoding detected)")
        else:
            feedback_parts.append("No hardcoded text, but translations aren't rendering properly")
    else:
        feedback_parts.append(f"FAILED ARCHITECTURE: Found {views_hardcoded} instances of hardcoded Spanish in Blade views")

    # VLM Trajectory check to supplement evidence (confirming terminal usage & browser validation)
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = (
            "You are grading a web development task. Look at these frames. "
            "1. Did the user edit code files (like .env or .blade.php) in a text editor or terminal? "
            "2. Does the final image show the web application login screen localized in Spanish (e.g. 'Correo', 'Contraseña')? "
            "Respond in JSON format: {\"edited_code\": boolean, \"is_spanish_ui\": boolean}"
        )
        
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        parsed = vlm_res.get("parsed", {})
        
        if parsed.get("edited_code") and parsed.get("is_spanish_ui"):
            feedback_parts.append("VLM confirms code editing and localized UI.")
        else:
            feedback_parts.append("VLM could not fully confirm trajectory actions.")
            
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # Determine if they passed the threshold and the critical architectural check
    passed = score >= 85 and (views_hardcoded == 0) and rendered_correctly

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }