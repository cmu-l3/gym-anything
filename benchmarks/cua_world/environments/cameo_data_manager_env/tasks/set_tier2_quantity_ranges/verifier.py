#!/usr/bin/env python3
"""
Verifier for CAMEO Data Manager task: Set Tier II Quantity Ranges.

Verification Logic:
1. Verifies the correct quantity codes are set in the database (05, 04)
2. Verifies the correct days on site is set (365)
3. Checks if the database file was modified during the task
4. Uses VLM trajectory analysis to verify navigation and UI interaction
"""

import json
import os
import sys
import tempfile
import logging
from datetime import datetime

# Import VLM utils (assuming gym_anything context)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Mock for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, images): return {"success": False}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_windows_timestamp(ts_str):
    """Parse timestamp string from PowerShell export."""
    try:
        # PowerShell 'o' format: 2023-10-25T14:30:00.0000000-04:00
        # Python isoformat handles this mostly
        return datetime.fromisoformat(ts_str)
    except:
        return None

def verify_set_tier2_quantity_ranges(traj, env_info, task_info):
    """
    Verify that chemical quantity ranges were correctly set in CAMEO Data Manager.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_max = metadata.get('expected_max_code', "05")
    expected_avg = metadata.get('expected_avg_code', "04")
    expected_days = str(metadata.get('expected_days', 365))

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: In Windows env, paths like C:\tmp map to internal, but copy_from_env 
        # usually handles the path translation from the container's FS.
        # We assume the framework mounts or accesses the windows path correctly 
        # or we use the posix path if running via cygwin/wsl.
        # If the environment is purely Windows, the path provided to copy_from_env
        # might need to be the absolute Windows path.
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve verification data: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Database Verification (60 points)
    record_found = result.get("record_found", False)
    
    if record_found:
        # Check Max Daily Amount
        actual_max = str(result.get("max_daily_code", ""))
        # Handle cases where code might be "05" or just "5"
        if actual_max.zfill(2) == expected_max.zfill(2):
            score += 25
            feedback_parts.append("Max Daily Amount Correct (05)")
        else:
            feedback_parts.append(f"Max Daily Amount Incorrect: expected {expected_max}, got {actual_max}")

        # Check Average Daily Amount
        actual_avg = str(result.get("avg_daily_code", ""))
        if actual_avg.zfill(2) == expected_avg.zfill(2):
            score += 25
            feedback_parts.append("Avg Daily Amount Correct (04)")
        else:
            feedback_parts.append(f"Avg Daily Amount Incorrect: expected {expected_avg}, got {actual_avg}")

        # Check Days on Site
        actual_days = str(result.get("days_on_site", ""))
        if actual_days == expected_days:
            score += 20
            feedback_parts.append(f"Days On Site Correct ({expected_days})")
        else:
            feedback_parts.append(f"Days On Site Incorrect: expected {expected_days}, got {actual_days}")
    else:
        feedback_parts.append("Chemical record not found in database or database read failed")
        if result.get("error"):
            feedback_parts.append(f"DB Error: {result.get('error')}")

    # 2. Anti-Gaming / Persistence Check (10 points)
    # Check if DB was modified after start
    initial_state = result.get("initial_state", {})
    # Simple check: Are values different from initial?
    changed = False
    if initial_state.get("exists"):
        if str(initial_state.get("max")) != str(result.get("max_daily_code")): changed = True
        if str(initial_state.get("avg")) != str(result.get("avg_daily_code")): changed = True
        if str(initial_state.get("days")) != str(result.get("days_on_site")): changed = True
    else:
        # If record didn't exist initially but exists now, it changed
        if record_found: changed = True

    if changed:
        score += 10
        feedback_parts.append("Database records modified successfully")
    else:
        feedback_parts.append("No change detected from initial state")

    # 3. VLM Verification (20 points)
    # Verify the agent actually navigated the UI
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    vlm_prompt = """
    Review this sequence of screenshots from CAMEO Data Manager.
    The user task is to edit Tier II quantity ranges for Sulfuric Acid.
    
    Verify:
    1. Is the CAMEO Data Manager application visible?
    2. Did the agent navigate to a specific chemical record (Sulfuric Acid)?
    3. Is the "Tier II" or "Physical State / Quantity" tab/section visible in the final steps?
    4. Are the values "05" (Range Code) or "10,000 - 99,999" and "365" visible?
    
    Return JSON: {"ui_navigated": bool, "values_visible": bool, "reason": str}
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames + [final_screen])
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("ui_navigated"):
            score += 10
            feedback_parts.append("VLM confirmed UI navigation")
        if parsed.get("values_visible"):
            score += 10
            feedback_parts.append("VLM confirmed values visible in UI")
    else:
        # Fallback if VLM fails: give points if DB check passed perfectly
        if score >= 70:
            score += 20
            feedback_parts.append("VLM check skipped (DB confirmed)")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }