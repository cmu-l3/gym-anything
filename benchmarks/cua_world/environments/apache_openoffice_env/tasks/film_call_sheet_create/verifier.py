#!/usr/bin/env python3
"""
Verifier for film_call_sheet_create task.

The agent must create a professional film production call sheet.
Success depends on:
1. File existence and valid ODT format.
2. Structure: Using tables for schedule and cast (not just tabs/spaces).
3. Data Accuracy: Specific times and names from JSON must match exactly.
4. Completeness: Logo, Header, Footer details.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_film_call_sheet(traj, env_info, task_info):
    """Verify the call sheet ODT document."""
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Scoring Logic
    score = 0
    feedback_parts = []
    
    # CRITERION 1: File Exists (Gatekeeper)
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Output file 'Call_Sheet_Day_14.odt' was not created."
        }
    score += 10
    feedback_parts.append("File created (+10)")
    
    # CRITERION 2: Document Structure (Tables)
    # A call sheet MUST use tables. At least 2 are expected (Schedule, Cast).
    table_count = result.get("table_count", 0)
    if table_count >= 2:
        score += 20
        feedback_parts.append(f"Tables used correctly ({table_count} found) (+20)")
    elif table_count == 1:
        score += 10
        feedback_parts.append("Only 1 table found (expected separate Schedule/Cast tables) (+10)")
    else:
        feedback_parts.append("WARNING: No tables found. Layout likely incorrect.")

    # CRITERION 3: Logo Image
    if result.get("has_image", False):
        score += 10
        feedback_parts.append("Logo image embedded (+10)")
    else:
        feedback_parts.append("Logo image missing")

    # CRITERION 4: Header Info
    if result.get("has_title", False) and result.get("has_day_info", False):
        score += 15
        feedback_parts.append("Header info (Title/Day) correct (+15)")
    elif result.get("has_title", False):
        score += 10
        feedback_parts.append("Title present but Day info missing (+10)")
    else:
        feedback_parts.append("Header info incomplete")

    # CRITERION 5: Data Accuracy (High Value)
    # Check for specific data points from JSON
    data_score = 0
    if result.get("has_scene_42", False): data_score += 10
    if result.get("has_actor_elena", False): data_score += 10
    if result.get("has_time_0545", False): data_score += 15  # Specific time check
    
    score += data_score
    if data_score == 35:
        feedback_parts.append("All key schedule/cast data present (+35)")
    else:
        feedback_parts.append(f"Partial data match (+{data_score})")

    # CRITERION 6: Footer Info
    if result.get("has_hospital_info", False):
        score += 10
        feedback_parts.append("Emergency/Hospital info present (+10)")
    else:
        feedback_parts.append("Hospital info missing")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }