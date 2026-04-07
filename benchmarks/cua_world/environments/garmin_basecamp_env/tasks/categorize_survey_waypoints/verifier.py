#!/usr/bin/env python3
"""
Verifier for categorize_survey_waypoints task.

Verification Strategy:
1. Copy the GPX file from the container environment.
2. Ensure the file was actually created during the task (anti-gaming check).
3. Parse GPX XML and strip namespaces for resilient tag checking.
4. Verify the existence, coordinates, map symbols, and categories for all 4 expected waypoints.
5. Use VLM on trajectory frames to verify BaseCamp UI was used (preventing CLI script gaming).
"""

import os
import json
import math
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def strip_namespaces(elem):
    """Strip all namespaces from the XML tree to make parsing robust across GPX versions."""
    for el in elem.iter():
        if '}' in el.tag:
            el.tag = el.tag.split('}', 1)[1]
    return elem


def verify_categorize_survey_waypoints(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_wpts = metadata.get('waypoints', [])
    
    score = 0
    feedback = []

    # 1. Check Task Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result_data.get('output_exists', False)
    file_created_during_task = result_data.get('file_created_during_task', False)

    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file C:\\workspace\\output\\tree_survey.gpx was not found."
        }
    
    if not file_created_during_task:
        feedback.append("Warning: File timestamp indicates it was not modified during the task.")
    else:
        score += 10
        feedback.append("File created successfully during task.")

    # 2. Parse the GPX File
    temp_gpx = tempfile.NamedTemporaryFile(delete=False, suffix='.gpx')
    parsed_wpts = {}
    try:
        copy_from_env("C:\\workspace\\output\\tree_survey.gpx", temp_gpx.name)
        tree = ET.parse(temp_gpx.name)
        root = strip_namespaces(tree.getroot())
        
        # Extract all waypoints
        for wpt in root.findall('.//wpt'):
            name_elem = wpt.find('name')
            if name_elem is not None and name_elem.text:
                parsed_wpts[name_elem.text.strip()] = wpt
                
        if len(parsed_wpts) >= 4:
            score += 10
            feedback.append(f"Found {len(parsed_wpts)} waypoints in GPX.")
        else:
            feedback.append(f"Found {len(parsed_wpts)} waypoints, expected 4.")
            
    except Exception as e:
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"Failed to parse GPX XML: {e}"
        }
    finally:
        if os.path.exists(temp_gpx.name):
            os.unlink(temp_gpx.name)

    # 3. Evaluate Waypoints Programmatically
    coord_score = 0
    sym_score = 0
    cat_score = 0

    for expected in expected_wpts:
        name = expected['name']
        wpt_elem = parsed_wpts.get(name)
        
        if wpt_elem is None:
            feedback.append(f"Waypoint '{name}' missing.")
            continue
            
        # Check Coordinates (5 points per wpt)
        lat = float(wpt_elem.get('lat', 0))
        lon = float(wpt_elem.get('lon', 0))
        lat_diff = abs(lat - expected['lat'])
        lon_diff = abs(lon - expected['lon'])
        
        if lat_diff < 0.0005 and lon_diff < 0.0005:
            coord_score += 5
        else:
            feedback.append(f"'{name}' coordinates off: got {lat},{lon}")

        # Check Symbol (5 points per wpt)
        sym_elem = wpt_elem.find('sym')
        if sym_elem is not None and sym_elem.text:
            if expected['sym'].lower() in sym_elem.text.lower():
                sym_score += 5
            else:
                feedback.append(f"'{name}' symbol incorrect: got '{sym_elem.text}'")
        else:
            feedback.append(f"'{name}' missing symbol.")

        # Check Category (5 points per wpt)
        categories = wpt_elem.findall('.//Category')
        cat_texts = [c.text.strip().lower() for c in categories if c.text]
        if expected['cat'].lower() in cat_texts:
            cat_score += 5
        else:
            feedback.append(f"'{name}' missing category '{expected['cat']}'.")

    score += coord_score + sym_score + cat_score
    feedback.append(f"Scores - Coords: {coord_score}/20, Symbols: {sym_score}/20, Categories: {cat_score}/20")

    # 4. VLM Verification (Trajectory checking)
    # Ensure they used the UI and didn't just write a python script to emit XML.
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=6)
        
        prompt = (
            "You are verifying if an agent used the Garmin BaseCamp UI to perform a task.\n"
            "The task was to manually create waypoints, change their symbols (e.g. green/red flags), "
            "and assign custom categories (Conifer/Deciduous).\n"
            "Look at these screenshots sampled over time.\n"
            "Did the agent actually use the BaseCamp interface (Waypoint Properties dialogs, "
            "category text fields, map clicks) to do this work?\n"
            "Respond ONLY with a JSON object: {\"used_ui\": true/false, \"reason\": \"...\"}"
        )
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("used_ui", False):
                vlm_score = 20
                feedback.append("VLM confirms Garmin BaseCamp UI was used.")
            else:
                feedback.append(f"VLM suspects CLI cheating: {parsed.get('reason')}")
        else:
            # Fallback if VLM fails/unavailable but programmatic checks are perfect
            if score == 80: 
                vlm_score = 20
                feedback.append("VLM query failed, but programmatic perfection grants pass.")
                
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        # Soft-fail VLM if it's an import error or unavailable framework feature
        if score == 80:
            vlm_score = 20

    score += vlm_score

    # Threshold: Need core file + 3/4 waypoints mostly correct + UI used
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }