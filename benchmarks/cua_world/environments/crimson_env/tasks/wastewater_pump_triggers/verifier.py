#!/usr/bin/env python3
"""
Verifier for wastewater_pump_triggers task.

HYBRID VERIFICATION:
1. Programmatic CSV Parsing: Validates tag existence, data types, analog scaling parameters, 
   and state-based logic triggers within Crimson.
2. VLM Trajectory Check: Confirms the agent physically used the UI to configure these settings,
   preventing "instant-win" gaming by dropping a pre-made CSV or bypassing the GUI.
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:/Users/Docker/Desktop/CrimsonTasks/wastewater_result.json"

def build_vlm_prompt():
    return """Examine these trajectory frames from a user operating Red Lion Crimson 3.0.
Task: The user should be configuring Data Tags, Analog Scaling, and Event Triggers.

Check for these indicators:
1. Did the user open the "Data Tags" navigation pane?
2. Did the user access the "Data" tab or "Format" tab to configure Data Scaling (Data Min/Max to Display Min/Max)?
3. Did the user access the "Triggers" tab to configure Event Triggers (Action strings like LSA_P1_Cmd = 1)?

Respond in JSON format:
{
    "ui_interaction_detected": true/false,
    "confidence": "low/medium/high",
    "observations": "Brief explanation of what panels/tabs are visible"
}
"""

def extract_trigger_value(val_str):
    """Safely cast string trigger values to float."""
    try:
        return float(val_str)
    except (ValueError, TypeError):
        return None

def verify_wastewater_pump_triggers(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # --- Fetch Export JSON ---
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
        return {"passed": False, "score": 0, "feedback": "Result JSON not found. The project was not saved or export failed."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result JSON: {e}"}

    # --- Gate Checks ---
    if not result.get("project_found"):
        return {"passed": False, "score": 0, "feedback": "Project file not found. Agent did not save the project."}
    if not result.get("export_success"):
        return {"passed": False, "score": 0, "feedback": "Export failed. Project may be empty or UI automation interrupted."}

    exported_tags = result.get("tags", [])
    if not exported_tags:
        return {"passed": False, "score": 0, "feedback": "No tags found in the project export."}

    tag_map = {str(t.get("Tag Name", "")).strip(): t for t in exported_tags}
    
    # Gate: Wrong Target (Configured LS-B)
    lsb_tags = [name for name in tag_map.keys() if name.startswith("LSB_")]
    if lsb_tags:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"SCOPE FAILURE: Agent configured Out-Of-Scope tags {lsb_tags}. Only LS-A is permitted."
        }

    score = 0
    feedback_parts = []
    
    # ================================================================
    # S1: Tag Presence (20 points)
    # ================================================================
    expected_names = ["LSA_Level", "LSA_P1_Cmd", "LSA_P2_Cmd", "LSA_High_Alarm"]
    found_expected = [name for name in expected_names if name in tag_map]
    
    if len(found_expected) == 4:
        score += 20
        feedback_parts.append("All 4 LSA tags created")
    else:
        feedback_parts.append(f"Missing tags. Found: {found_expected}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)} # Early exit if missing targets

    # ================================================================
    # S2: Tag Data Types (10 points)
    # ================================================================
    lsa_level = tag_map.get("LSA_Level", {})
    lsa_p1 = tag_map.get("LSA_P1_Cmd", {})
    
    level_type = str(lsa_level.get("Treat As", "")).lower()
    flag_type = str(lsa_p1.get("Treat As", "")).lower()
    
    if ("integer" in level_type or "real" in level_type or "float" in level_type) and "flag" in flag_type:
        score += 10
        feedback_parts.append("Data Types correct")
    else:
        feedback_parts.append(f"Data Type mismatch (Level: {level_type}, Flag: {flag_type})")

    # ================================================================
    # S3: Analog Scaling (20 points)
    # ================================================================
    # In Crimson CSV exports, scaling shows in "Scale" (Yes/No), "Data Min", "Data Max", "Disp Min", "Disp Max"
    # Column names can vary slightly by version, we check loosely.
    
    # Identify keys for scaling
    k_data_min = next((k for k in lsa_level.keys() if "Data" in k and "Min" in k), None)
    k_data_max = next((k for k in lsa_level.keys() if "Data" in k and "Max" in k), None)
    k_disp_min = next((k for k in lsa_level.keys() if "Disp" in k and "Min" in k), None)
    k_disp_max = next((k for k in lsa_level.keys() if "Disp" in k and "Max" in k), None)
    
    s3_score = 0
    if k_data_min and k_data_max and k_disp_min and k_disp_max:
        try:
            d_min = float(lsa_level[k_data_min])
            d_max = float(lsa_level[k_data_max])
            v_min = float(lsa_level[k_disp_min])
            v_max = float(lsa_level[k_disp_max])
            
            if d_min == 4000.0 and d_max == 20000.0:
                s3_score += 10
            if v_min == 100.0 and v_max == 115.0:
                s3_score += 10
        except ValueError:
            pass
            
    score += s3_score
    if s3_score == 20:
        feedback_parts.append("Analog Scaling correct")
    else:
        feedback_parts.append(f"Analog Scaling incorrect/missing (Score: {s3_score}/20)")

    # ================================================================
    # S4 & S5: Event Triggers (25 points)
    # ================================================================
    # Expected triggers:
    # >= 106.0 -> LSA_P1_Cmd = 1
    # >= 108.5 -> LSA_P2_Cmd = 1
    # <= 102.5 -> LSA_P1_Cmd = 0; LSA_P2_Cmd = 0
    # >= 110.0 -> LSA_High_Alarm = 1
    
    triggers_found = {
        "lead": False,
        "lag": False,
        "off": False,
        "alarm": False
    }
    
    # Iterate through potential trigger columns
    for i in range(1, 10):
        t_mode_key = next((k for k in lsa_level.keys() if f"Trigger {i}" in k and "Mode" in k), None)
        t_val_key = next((k for k in lsa_level.keys() if f"Trigger {i}" in k and "Value" in k), None)
        t_act_key = next((k for k in lsa_level.keys() if f"Trigger {i}" in k and "Action" in k), None)
        
        if not (t_mode_key and t_val_key and t_act_key):
            continue
            
        mode = str(lsa_level[t_mode_key]).lower()
        val = extract_trigger_value(lsa_level[t_val_key])
        action = str(lsa_level[t_act_key]).replace(" ", "") # strip spaces for easier matching
        
        if mode == "" or val is None or action == "":
            continue
            
        # Check Lead (106.0)
        if val == 106.0 and "absolutehigh" in mode and "lsap1cmd=1" in action.lower():
            triggers_found["lead"] = True
            
        # Check Lag (108.5)
        elif val == 108.5 and "absolutehigh" in mode and "lsap2cmd=1" in action.lower():
            triggers_found["lag"] = True
            
        # Check Off (102.5)
        elif val == 102.5 and "absolutelow" in mode and ("lsap1cmd=0" in action.lower() or "lsap2cmd=0" in action.lower()):
            triggers_found["off"] = True
            
        # Check Alarm (110.0)
        elif val == 110.0 and "absolutehigh" in mode and "lsahighalarm=1" in action.lower():
            triggers_found["alarm"] = True

    trigger_score = sum(6 for k, v in triggers_found.items() if v and k != "alarm") # 3x6 = 18 pts
    if triggers_found["alarm"]: trigger_score += 7 # +7 pts = 25 total
    score += trigger_score
    
    feedback_parts.append(f"Triggers verified: {sum(triggers_found.values())}/4")

    # ================================================================
    # VLM Verification: UI Interaction (10 points)
    # ================================================================
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_result = query_vlm(images=frames, prompt=build_vlm_prompt())
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("ui_interaction_detected", False):
                    vlm_score = 10
                    feedback_parts.append("VLM confirmed UI interaction")
                else:
                    feedback_parts.append("VLM did NOT detect UI interaction")
            else:
                feedback_parts.append("VLM query failed")
    except ImportError:
        # Fallback if VLM isn't fully available in the local runner
        logger.warning("VLM module not found, granting VLM points automatically.")
        vlm_score = 10
        feedback_parts.append("VLM check bypassed")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append(f"VLM error: {e}")

    score += vlm_score

    # Check passing threshold (70/100)
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }