#!/usr/bin/env python3
"""
Verifier for glass_forehearth_thermal_averaging task.

Uses a robust binary context extraction method from the `export_result.ps1` to
evaluate the agent's Crimson 3.0 configuration without relying on brittle UI automation.

Scoring (100 points total):
  S1: Tag Creation (15 pts) - Z1_Avg_Temp through Z5_Avg_Temp exist in the project.
  S2: Data Type & Units (10 pts) - Mentions of 'deg C' near the tags.
  S3: Standard Averages (40 pts) - Z1, Z2, Z4, Z5 correctly average 3 sensors (/3).
  S4: Exception Average (20 pts) - Z3 correctly averages ONLY Left and Right (/2), ignores Center.
  S5: Alarm Configuration (15 pts) - High Alarm setpoints match specifications.

Pass threshold: 70 points.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/glass_forehearth_result.json"

EXPECTED_ALARMS = {
    "Z1_Avg_Temp": "1200",
    "Z2_Avg_Temp": "1180",
    "Z3_Avg_Temp": "1160",
    "Z4_Avg_Temp": "1150",
    "Z5_Avg_Temp": "1120"
}

def verify_glass_forehearth_tags(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Retrieve the exported JSON result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp_path = tmp.name
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {
            "passed": False, 
            "score": 0,
            "feedback": "Result file not found. The agent likely did not save the project."
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # 2. Base Validation Gates
    if not result.get("project_found"):
        return {
            "passed": False, 
            "score": 0,
            "feedback": "Project file 'forehearth_configured.c3' not found in Documents. Agent did not save correctly."
        }
        
    if not result.get("file_created_during_task"):
        return {
            "passed": False, 
            "score": 0,
            "feedback": "Project file was not created/modified during the task window (anti-gaming block)."
        }

    contexts = result.get("binary_contexts", {})
    if not contexts:
        return {
            "passed": False, 
            "score": 0,
            "feedback": "No configured tags found in the project. Agent may have created an empty project."
        }

    score = 0
    feedback_parts = []
    
    # S1: Tag Creation (15 pts, 3 per tag)
    s1_score = 0
    found_tags = []
    for tag in EXPECTED_ALARMS.keys():
        if tag in contexts and contexts[tag]:
            s1_score += 3
            found_tags.append(tag)
    score += s1_score
    feedback_parts.append(f"S1-Tag Creation: {s1_score}/15 pts")

    if s1_score == 0:
        return {"passed": False, "score": 0, "feedback": "None of the requested tags were found in the project."}

    # Helper function to normalize text block for analysis
    def norm(txt):
        return txt.upper().replace(' ', '').replace('"', '').replace('.0', '')

    # S2: Data Type & Units (10 pts, 2 per tag)
    s2_score = 0
    for tag in found_tags:
        ctx = contexts[tag].upper()
        # Look for "DEG C" or "DEGC"
        if "DEG C" in ctx or "DEGC" in ctx.replace(" ", ""):
            s2_score += 2
    score += s2_score
    feedback_parts.append(f"S2-Units: {s2_score}/10 pts")

    # S3: Standard Averages (40 pts, 10 per tag for Z1, Z2, Z4, Z5)
    s3_score = 0
    standard_zones = ["Z1", "Z2", "Z4", "Z5"]
    for zone in standard_zones:
        tag = f"{zone}_Avg_Temp"
        if tag not in found_tags:
            continue
        c = norm(contexts[tag])
        
        # Check standard formula elements
        has_left = f"TC_{zone}_LEFT" in c
        has_center = f"TC_{zone}_CENTER" in c
        has_right = f"TC_{zone}_RIGHT" in c
        has_div3 = "/3" in c
        
        if has_left and has_center and has_right and has_div3:
            s3_score += 10
        elif has_left and has_right and has_div3:
            s3_score += 5  # Partial if they missed center but divided by 3
            
    score += s3_score
    feedback_parts.append(f"S3-Std Averages: {s3_score}/40 pts")

    # S4: Exception Average for Z3 (20 pts)
    s4_score = 0
    if "Z3_Avg_Temp" in found_tags:
        c = norm(contexts["Z3_Avg_Temp"])
        
        has_left = "TC_Z3_LEFT" in c
        has_right = "TC_Z3_RIGHT" in c
        has_center = "TC_Z3_CENTER" in c
        has_div2 = "/2" in c
        has_div3 = "/3" in c
        
        if has_left and has_right and not has_center and has_div2 and not has_div3:
            s4_score += 20
        elif has_center or has_div3:
            # They failed to read/apply the maintenance log exception
            s4_score += 0
            feedback_parts.append("Z3 EXCEPTION FAILED: Agent included failed Center sensor or divided by 3.")
        else:
            s4_score += 10 # Partial if somewhat configured but not perfect
            
    score += s4_score
    feedback_parts.append(f"S4-Exception Z3: {s4_score}/20 pts")

    # S5: Alarms (15 pts, 3 per tag)
    s5_score = 0
    for tag in found_tags:
        expected_alarm = EXPECTED_ALARMS[tag]
        # Alarms are stored near the tag name in the binary
        c = norm(contexts[tag])
        if expected_alarm in c:
            s5_score += 3
    score += s5_score
    feedback_parts.append(f"S5-Alarms: {s5_score}/15 pts")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }