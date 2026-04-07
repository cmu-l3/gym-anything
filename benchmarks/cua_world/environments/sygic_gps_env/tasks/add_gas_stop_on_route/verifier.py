#!/usr/bin/env python3
"""
Verifier for add_gas_stop_on_route task.

Task: Plan route to Kabul, then add a Gas Station ALONG THE ROUTE as a waypoint.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_gas_stop_on_route(traj, env_info, task_info):
    """
    Verifies the task using:
    1. VLM Trajectory Analysis (Critical for 'On Route' usage)
    2. Final Screenshot Analysis (Verification of route + stop)
    3. UI Dump (XML) Text Check (Keywords)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # =========================================================================
    # 1. RETRIEVE DATA
    # =========================================================================
    temp_dir = tempfile.mkdtemp()
    result_json_path = os.path.join(temp_dir, "task_result.json")
    xml_dump_path = os.path.join(temp_dir, "ui_dump.xml")
    
    task_result = {}
    xml_content = ""
    
    try:
        # Get JSON result
        copy_from_env("/sdcard/task_result.json", result_json_path)
        if os.path.exists(result_json_path):
            with open(result_json_path, 'r') as f:
                task_result = json.load(f)
        
        # Get XML dump
        copy_from_env("/sdcard/ui_dump.xml", xml_dump_path)
        if os.path.exists(xml_dump_path):
            with open(xml_dump_path, 'r', errors='ignore') as f:
                xml_content = f.read()
    except Exception as e:
        logger.warning(f"Data retrieval warning: {e}")
    
    # =========================================================================
    # 2. VLM VERIFICATION (PRIMARY)
    # =========================================================================
    # We need to verify the PROCESS: Route -> Search Gas -> On Route Filter -> Add
    
    frames = sample_trajectory_frames(traj, n=6)
    final_img = get_final_screenshot(traj)
    
    if not frames:
        return {"passed": False, "score": 0, "feedback": "No trajectory frames available"}

    # Prompt for VLM
    prompt = """
    You are a judge for a GPS navigation task. The user was asked to:
    1. Plan a route to 'Kabul'.
    2. Add a 'Petrol Station' / 'Gas Station' specifically ALONG THE ROUTE (using the 'On Route' or 'Along Route' feature).
    
    Analyze the screenshots sequence:
    1. Did the user plan a route to Kabul?
    2. Did the user search for gas stations?
    3. CRITICAL: Did the user select the "On Route" / "Along Route" filter or tab? (Look for a route icon in search or "On route" text).
    4. Did the user add a station as a waypoint/stop?
    5. Does the final screen show a route with an intermediate stop (Start -> Gas -> Kabul)?
    
    Output JSON:
    {
        "route_planned": true/false,
        "search_gas_initiated": true/false,
        "on_route_filter_used": true/false,
        "stop_added": true/false,
        "final_route_correct": true/false,
        "reasoning": "..."
    }
    """
    
    vlm_response = query_vlm(images=frames + [final_img], prompt=prompt)
    
    # Default values in case VLM fails
    vlm_data = {
        "route_planned": False,
        "search_gas_initiated": False,
        "on_route_filter_used": False,
        "stop_added": False,
        "final_route_correct": False,
        "reasoning": "VLM analysis failed"
    }
    
    if vlm_response and 'parsed' in vlm_response:
        vlm_data.update(vlm_response['parsed'])
    
    # =========================================================================
    # 3. XML / TEXT VERIFICATION (SECONDARY)
    # =========================================================================
    # Check if 'Kabul' and 'Gas'/'Petrol' appear in the UI
    xml_score_modifier = 0
    ui_text = xml_content.lower()
    
    has_kabul = "kabul" in ui_text
    has_gas_keyword = any(k in ui_text for k in ["gas", "petrol", "pump", "station", "oil"])
    
    # "via" often appears in route summaries for waypoints
    has_via = "via" in ui_text or "stop 1" in ui_text or "waypoint" in ui_text
    
    if has_kabul and has_gas_keyword:
        xml_score_modifier = 10
    
    # =========================================================================
    # 4. SCORING
    # =========================================================================
    score = 0
    feedback = []
    
    # App running check (10 pts)
    if task_result.get("app_running", False):
        score += 10
    else:
        feedback.append("App was not running at end.")

    # VLM Criteria
    if vlm_data["route_planned"]:
        score += 20
        feedback.append("Route to Kabul planned.")
    
    if vlm_data["search_gas_initiated"]:
        score += 10
        feedback.append("Gas search initiated.")
        
    if vlm_data["on_route_filter_used"]:
        score += 30
        feedback.append("'On Route' filter used (CRITICAL).")
    else:
        feedback.append("'On Route' filter NOT detected.")
        
    if vlm_data["stop_added"]:
        score += 20
        feedback.append("Stop added to route.")
        
    if vlm_data["final_route_correct"]:
        score += 10
        feedback.append("Final route looks correct.")
        
    # XML Bonus
    score = min(100, score + xml_score_modifier)
    
    # Pass threshold
    # Must use "On Route" filter OR have a perfect final route execution that implies it
    passed = score >= 70 and (vlm_data["on_route_filter_used"] or vlm_data["final_route_correct"])
    
    full_feedback = f"Score: {score}/100. " + " ".join(feedback) + f" (VLM Reasoning: {vlm_data.get('reasoning', 'None')})"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": full_feedback
    }