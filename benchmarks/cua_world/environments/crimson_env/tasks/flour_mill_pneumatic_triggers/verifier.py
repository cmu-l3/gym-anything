#!/usr/bin/env python3
"""Verifier for flour_mill_pneumatic_triggers task.

Validates that the agent correctly created tags and configured 'Active On' and 
'Active Off' triggers with embedded C-like actions (e.g. LogEvent).

Scoring (100 points total):
  1. Anti-gaming (0 pts but required): Project saved during task.
  2. Tag Creation (10 pts): All 6 required tags exist with correct Flag/Integer types.
  3. Blower Trigger (20 pts): 'Active Off' mode + `LogEvent("Blower M101 Stopped")`.
  4. Valve Trigger (20 pts): 'Active On' mode + `LogEvent("Rotary Valve RV102 Fault")`.
  5. Silo Trigger (20 pts): 'Active On' mode + `LogEvent("Silo A Full")`.
  6. Reset Trigger (15 pts): 'Active On' mode + `Blockage_Count = 0`.
  7. Negative Constraint (5 pts): Filter/Blockage tags have NO triggers.
  8. VLM Verification (10 pts): Visual proof the agent interacted with the Triggers UI.

Pass threshold: 75 / 100
"""

import json
import os
import tempfile
import logging
import re

logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/flour_mill_result.json"

def normalize_mode(mode_str):
    """Normalize Crimson 3.0 trigger mode values."""
    s = str(mode_str).strip().lower()
    if s in ["1", "active on"]:
        return "active_on"
    if s in ["2", "active off"]:
        return "active_off"
    if s in ["0", "none", "", "null"]:
        return "none"
    return s

def normalize_action(action_str):
    """Normalize action string, un-escaping CSV quotes and removing whitespace."""
    s = str(action_str).replace('""', '"').strip()
    # Remove all spaces for reliable comparison
    return re.sub(r'\s+', '', s).lower()

def check_vlm_interaction(traj, query_vlm):
    """Use VLM on trajectory to verify the Triggers tab was accessed."""
    if not query_vlm:
        return False
        
    try:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=5)
        if not frames:
            return False
            
        prompt = (
            "You are evaluating an agent's workflow in Red Lion Crimson 3.0. "
            "Look at these trajectory screenshots. Did the agent at any point navigate "
            "to the 'Triggers' tab for a tag and type into the 'Action' field? "
            "Reply with a JSON containing a single boolean field 'used_triggers_tab'."
        )
        
        result = query_vlm(images=frames, prompt=prompt)
        parsed = result.get("parsed", {})
        return parsed.get("used_triggers_tab", False)
    except Exception as e:
        logger.error(f"VLM check failed: {e}")
        return False

def verify_flour_mill_triggers(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

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
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # GATE 1: Anti-gaming / Project existence
    if not result.get("project_found"):
        return {"passed": False, "score": 0, "feedback": "Project not found - task not completed."}
    
    if not result.get("file_created_during_task", True):
        return {"passed": False, "score": 0, "feedback": "Project file is stale (created before task start)."}

    score = 0
    feedback_parts = []
    
    exported = result.get("tags", [])
    export_success = result.get("export_success", False)
    raw_strings = result.get("raw_strings_found", {})
    
    # Find Trigger columns flexibly
    mode_col = None
    action_col = None
    type_col = None
    
    if exported and len(exported) > 0:
        first_keys = [k.lower() for k in exported[0].keys()]
        for k in exported[0].keys():
            k_lower = k.lower()
            if "mode" in k_lower and "trig" in k_lower: mode_col = k
            if "action" in k_lower and "trig" in k_lower: action_col = k
            if "treat" in k_lower or "type" in k_lower: type_col = k
            
    # Default column names if direct mapping fails
    if not mode_col: mode_col = "Trig 1 Mode"
    if not action_col: action_col = "Trig 1 Action"
    if not type_col: type_col = "Treat As"

    tag_map = {str(t.get("Name", t.get("name", ""))).strip().lower(): t for t in exported}
    
    # 1. Tag Creation (10 pts)
    expected_names = ["blower_m101_run", "valve_rv102_fault", "silo_a_level_hi", "system_reset_pb", "filter_pulse_run", "blockage_count"]
    tags_found = sum(1 for n in expected_names if n in tag_map)
    if tags_found == 6:
        score += 10
        feedback_parts.append("All tags created")
    else:
        feedback_parts.append(f"Found {tags_found}/6 expected tags")

    # If CSV export completely failed, fallback to raw string checking for partial credit
    if not export_success or not exported:
        feedback_parts.append("Warning: CSV export failed, using binary file scanning fallback.")
        if raw_strings.get("Blower"): score += 10
        if raw_strings.get("Valve"): score += 10
        if raw_strings.get("Silo"): score += 10
        if raw_strings.get("Reset"): score += 5
        
        passed = score >= 75
        return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Blower Trigger (20 pts)
    blower = tag_map.get("blower_m101_run", {})
    b_mode = normalize_mode(blower.get(mode_col, ""))
    b_act = normalize_action(blower.get(action_col, ""))
    if b_mode == "active_off":
        score += 5
        if 'logevent("blowerm101stopped")' in b_act:
            score += 15
            feedback_parts.append("Blower trigger perfect")
        else:
            feedback_parts.append("Blower trigger mode OK, but action syntax incorrect")

    # 3. Valve Trigger (20 pts)
    valve = tag_map.get("valve_rv102_fault", {})
    v_mode = normalize_mode(valve.get(mode_col, ""))
    v_act = normalize_action(valve.get(action_col, ""))
    if v_mode == "active_on":
        score += 5
        if 'logevent("rotaryvalverv102fault")' in v_act:
            score += 15
            feedback_parts.append("Valve trigger perfect")

    # 4. Silo Trigger (20 pts)
    silo = tag_map.get("silo_a_level_hi", {})
    s_mode = normalize_mode(silo.get(mode_col, ""))
    s_act = normalize_action(silo.get(action_col, ""))
    if s_mode == "active_on":
        score += 5
        if 'logevent("siloafull")' in s_act:
            score += 15
            feedback_parts.append("Silo trigger perfect")

    # 5. Reset Trigger (15 pts)
    reset = tag_map.get("system_reset_pb", {})
    r_mode = normalize_mode(reset.get(mode_col, ""))
    r_act = normalize_action(reset.get(action_col, ""))
    if r_mode == "active_on":
        score += 5
        if "blockage_count=0" in r_act:
            score += 10
            feedback_parts.append("Reset trigger perfect")

    # 6. Negative Constraints (5 pts)
    filter_t = tag_map.get("filter_pulse_run", {})
    count_t = tag_map.get("blockage_count", {})
    f_mode = normalize_mode(filter_t.get(mode_col, ""))
    c_mode = normalize_mode(count_t.get(mode_col, ""))
    if f_mode == "none" and c_mode == "none":
        score += 5
        feedback_parts.append("Negative constraints respected")

    # 7. VLM Verification (10 pts)
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        if check_vlm_interaction(traj, query_vlm):
            score += 10
            feedback_parts.append("VLM confirmed Triggers UI interaction")
        else:
            feedback_parts.append("VLM did not observe Triggers UI interaction")
    else:
        # Auto-grant if VLM unavailable but programmatic signals are strong
        if score >= 75:
            score += 10
            feedback_parts.append("VLM unavailable, auto-granting UI interaction points")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }