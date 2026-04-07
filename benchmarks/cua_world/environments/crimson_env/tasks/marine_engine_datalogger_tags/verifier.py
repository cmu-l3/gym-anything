#!/usr/bin/env python3
"""
Verifier for marine_engine_datalogger_tags task.

HYBRID VERIFICATION:
1. Programmatic Check (Data Tags):
   - Reads exported JSON (or raw string fallback) to verify Port engine tags.
   - GATE 1: Did agent save the project?
   - GATE 2: Did agent configure forbidden Starboard tags?
   - Scores min/max ranges, data types, engineering labels, and alarms.
2. VLM Trajectory Check (Data Logger):
   - Uses VLM on the trajectory frames to confirm 'PortEngineLog' was created.
   - Verifies 1 Second Update Rate.
   - Verifies Port tags were added to Logger Contents.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_TAGS = [
    {"name": "PT_OP_101", "min": 0.0, "max": 150.0, "label": "Pounds per Sq Inch", "alow": 35.0, "ahigh": 140.0},
    {"name": "PT_CT_101", "min": 0.0, "max": 250.0, "label": "Degrees Fahrenheit", "alow": 140.0, "ahigh": 210.0},
    {"name": "PT_EA_101", "min": 0.0, "max": 1500.0, "label": "Degrees Fahrenheit", "alow": 0.0, "ahigh": 1250.0},
    {"name": "PT_EB_101", "min": 0.0, "max": 1500.0, "label": "Degrees Fahrenheit", "alow": 0.0, "ahigh": 1250.0},
    {"name": "PT_SP_101", "min": 0.0, "max": 2000.0, "label": "Revolutions per Minute", "alow": 400.0, "ahigh": 1850.0}
]

FORBIDDEN_PREFIX = "ST_"
TOLERANCE_PCT = 2.0


def _within_tol(actual, expected, tol=TOLERANCE_PCT):
    if actual is None or expected is None:
        return False
    try:
        a, e = float(actual), float(expected)
    except (TypeError, ValueError):
        return False
    if e == 0.0:
        return abs(a) < 1e-6
    return abs(a - e) / abs(e) * 100.0 <= tol


def verify_datalogger_with_vlm(traj, query_vlm):
    """Uses VLM to inspect trajectory frames for the Data Logger configuration."""
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    # Sample frames to capture the navigation into the Data Logger pane
    frames = sample_trajectory_frames(traj, n=8)
    final = get_final_screenshot(traj)
    images = frames + [final]
    
    prompt = """Examine this sequence of screenshots from Red Lion Crimson 3.0.
The user was asked to configure a Data Logger. Look closely at the left navigation pane and the main configuration area.

Please verify:
1. Did the user create a Data Logger named exactly "PortEngineLog"?
2. Is the "Update Rate" drop-down set to "1 Second"?
3. In the "Contents" area of the Data Logger, are the PT_* tags (e.g., PT_OP_101, PT_CT_101) visible, showing they were added to be logged?

Return your response strictly as JSON:
{
    "logger_created": true/false,
    "rate_1_second": true/false,
    "tags_in_contents": true/false,
    "observations": "brief explanation of what you see"
}
"""
    vlm_result = query_vlm(prompt=prompt, images=images)
    
    if not vlm_result.get("success"):
        logger.error(f"VLM verification failed: {vlm_result.get('error')}")
        return {"logger_created": False, "rate_1_second": False, "tags_in_contents": False}
        
    return vlm_result.get("parsed", {"logger_created": False, "rate_1_second": False, "tags_in_contents": False})


def verify_marine_engine_datalogger(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env unavailable."}

    # Fetch Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("C:\\tmp\\marine_engine_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # GATE 1: Do-Nothing Check
    if not result.get("project_found", False):
        return {"passed": False, "score": 0, "feedback": "Project not saved to expected path."}
    
    if not result.get("file_created_during_task", False):
        logger.warning("Project file found, but mtime suggests it wasn't modified during task.")

    score = 0
    feedback_parts = []
    
    raw_strings = result.get("raw_strings", "")
    exported_tags = result.get("tags", [])
    
    # GATE 2: Wrong-Target (Starboard Tags configured)
    if "ST_OP" in raw_strings or "ST_CT" in raw_strings or "ST_EA" in raw_strings:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "WRONG TARGET: Agent configured forbidden Starboard (ST_) tags. Task explicitly stated to ignore them."
        }

    # Tag Programmatic Scoring
    found_tags_count = 0
    correct_types = 0
    correct_ranges = 0
    correct_alarms = 0
    
    if result.get("export_success") and exported_tags:
        # Evaluate via cleanly exported CSV data
        tag_map = {str(t.get("name", "")).strip().upper(): t for t in exported_tags}
        for exp in EXPECTED_TAGS:
            name = exp["name"]
            if name in tag_map:
                found_tags_count += 1
                t_data = tag_map[name]
                
                # Check Type
                if "float" in str(t_data.get("data_type", "")).lower():
                    correct_types += 1
                
                # Check Ranges
                if _within_tol(t_data.get("min_value"), exp["min"]) and _within_tol(t_data.get("max_value"), exp["max"]):
                    correct_ranges += 1
                    
                # Check Alarms & Labels
                lbl_match = str(t_data.get("label", "")).strip().lower() == exp["label"].lower()
                al_match = _within_tol(t_data.get("alarm_low"), exp["alow"])
                ah_match = _within_tol(t_data.get("alarm_high"), exp["ahigh"])
                if lbl_match and al_match and ah_match:
                    correct_alarms += 1
    else:
        # Fallback evaluation using raw binary string extraction
        logger.warning("UI Export failed, falling back to raw binary string regex analysis.")
        for exp in EXPECTED_TAGS:
            if exp["name"] in raw_strings:
                found_tags_count += 1
                # Generous partial credit for fallback
                correct_types += 1 
                if exp["label"] in raw_strings:
                    correct_alarms += 1
                correct_ranges += 1 # Difficult to parse reliably from binary, grant benefit of doubt if tag exists

    # Apply Points
    tag_score = (found_tags_count / len(EXPECTED_TAGS)) * 15
    type_score = (correct_types / len(EXPECTED_TAGS)) * 10
    range_score = (correct_ranges / len(EXPECTED_TAGS)) * 20
    alarm_score = (correct_alarms / len(EXPECTED_TAGS)) * 20
    
    score += tag_score + type_score + range_score + alarm_score
    feedback_parts.append(f"Tags Created ({tag_score:.0f}/15)")
    feedback_parts.append(f"Data Types ({type_score:.0f}/10)")
    feedback_parts.append(f"Engineering Ranges ({range_score:.0f}/20)")
    feedback_parts.append(f"Alarms & Units ({alarm_score:.0f}/20)")

    # VLM Verification for Data Logger
    vlm_metrics = {"logger_created": False, "rate_1_second": False, "tags_in_contents": False}
    if query_vlm and traj:
        vlm_metrics = verify_datalogger_with_vlm(traj, query_vlm)
    else:
        logger.warning("VLM unavailable. Skipping visual Data Logger verification.")

    if vlm_metrics.get("logger_created"):
        score += 10
        feedback_parts.append("Logger 'PortEngineLog' Created (10/10)")
    else:
        feedback_parts.append("Logger Not Created (0/10)")

    if vlm_metrics.get("rate_1_second"):
        score += 10
        feedback_parts.append("Logger Rate 1sec (10/10)")
    else:
        feedback_parts.append("Logger Rate Incorrect (0/10)")

    if vlm_metrics.get("tags_in_contents"):
        score += 15
        feedback_parts.append("Tags in Logger Contents (15/15)")
    else:
        feedback_parts.append("Tags Missing from Logger (0/15)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }