#!/usr/bin/env python3
"""
Verifier for build_dynamic_localization_system task.
Uses programmatic rendering verification to ensure the agent's macros dynamically update the view state.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_localization_system(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/localization_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------
    # CRITERION 1: DataTiddler Setup (15 pts)
    # -------------------------------------------------------------
    if result.get('sys_str_exists'):
        if 'application/json' in result.get('sys_str_type', ''):
            score += 15
            feedback_parts.append("SystemStrings DataTiddler correctly created")
        else:
            score += 5
            feedback_parts.append(f"SystemStrings created, but type is incorrect ({result.get('sys_str_type')})")
    else:
        feedback_parts.append("FAIL: SystemStrings DataTiddler missing")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # -------------------------------------------------------------
    # CRITERION 2: Components Creation (15 pts)
    # -------------------------------------------------------------
    components_met = 0
    if result.get('lang_set_exists'):
        components_met += 5
        feedback_parts.append("Language Settings UI exists")
    if result.get('dashboard_exists'):
        components_met += 5
        feedback_parts.append("Home Dashboard exists")
    if result.get('macro_exists'):
        components_met += 5
        if result.get('macro_references_dict'):
            feedback_parts.append("Macro exists and correctly references dictionary")
        else:
            feedback_parts.append("Macro exists but may not reference SystemStrings")
    score += components_met

    # -------------------------------------------------------------
    # CRITERION 3: Anti-gaming (Dynamic check)
    # -------------------------------------------------------------
    en_render = result.get('en_render', {})
    if en_render.get('has_es_leak', False):
        feedback_parts.append("FAIL: Detected hardcoded translations (English render contained Spanish text)")
        # Cap score for hardcoding
        return {"passed": False, "score": min(score, 30), "feedback": " | ".join(feedback_parts)}

    # -------------------------------------------------------------
    # CRITERION 4: English Rendering Validation (30 pts)
    # -------------------------------------------------------------
    en_score = sum([
        10 if en_render.get('has_welcome') else 0,
        10 if en_render.get('has_ticket') else 0,
        10 if en_render.get('has_kb') else 0
    ])
    score += en_score
    if en_score == 30:
        feedback_parts.append("English state correctly rendered via macro")
    elif en_score > 0:
        feedback_parts.append(f"English state partially rendered ({en_score}/30)")
    else:
        feedback_parts.append("FAIL: English strings failed to render")

    # -------------------------------------------------------------
    # CRITERION 5: Spanish Rendering Validation (20 pts)
    # -------------------------------------------------------------
    es_render = result.get('es_render', {})
    es_score = sum([
        7 if es_render.get('has_welcome') else 0,
        7 if es_render.get('has_ticket') else 0,
        6 if es_render.get('has_kb') else 0
    ])
    score += es_score
    if es_score == 20:
        feedback_parts.append("Spanish state dynamically rendered")
    elif es_score > 0:
        feedback_parts.append(f"Spanish state partially rendered ({es_score}/20)")
    else:
        feedback_parts.append("FAIL: Spanish dynamic rendering failed")

    # -------------------------------------------------------------
    # CRITERION 6: French Rendering Validation (20 pts)
    # -------------------------------------------------------------
    fr_render = result.get('fr_render', {})
    fr_score = sum([
        7 if fr_render.get('has_welcome') else 0,
        7 if fr_render.get('has_ticket') else 0,
        6 if fr_render.get('has_kb') else 0
    ])
    score += fr_score
    if fr_score == 20:
        feedback_parts.append("French state dynamically rendered")
    elif fr_score > 0:
        feedback_parts.append(f"French state partially rendered ({fr_score}/20)")

    # -------------------------------------------------------------
    # Evaluate Results
    # -------------------------------------------------------------
    # Key criteria: Data setup, components, AND dynamic rendering of multiple languages
    multiple_languages_working = (en_score > 15) and (es_score > 10 or fr_score > 10)
    passed = score >= 85 and multiple_languages_working

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }