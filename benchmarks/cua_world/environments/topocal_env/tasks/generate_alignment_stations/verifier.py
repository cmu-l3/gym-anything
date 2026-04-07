#!/usr/bin/env python3
"""
Verifier for Generate Alignment Stations task.

Verification metrics:
1. File Creation: CSV and TOP files must be created/modified during the task.
2. Geometric Accuracy: Parsed CSV coordinates must demonstrate consecutive spacing 
   of approximately 25.0 meters (validating proper tool usage).
3. Data Volume: Sufficient points must be generated to cover the alignment (>20 points).
4. VLM Trajectory: Confirms UI interaction with polyline tools and points rendering.
"""

import json
import os
import re
import tempfile
import math
import logging

from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_spanish_float(s):
    """Parses floats safely handling comma as decimal if present."""
    return float(s.replace(',', '.'))

def extract_coordinates(csv_path):
    """
    Robustly extract X and Y coordinates from a TopoCal CSV output.
    Looks for typical UTM Zone 13N ranges for Lookout Mountain to identify columns.
    """
    points = []
    try:
        with open(csv_path, 'r', encoding='utf-8', errors='ignore') as f:
            for line in f:
                # Replace tabs and semicolons with spaces to extract raw numbers
                clean_line = line.replace('\t', ' ').replace(';', ' ')
                
                # Match numbers (with optional negative signs and dot/comma decimals)
                nums = re.findall(r'-?\d+[\.,]\d+|-?\d+', clean_line)
                if len(nums) >= 3:
                    try:
                        # Scan the row to guess which column is X (~480000) and Y (~4398000)
                        x_val = None
                        y_val = None
                        
                        for val in nums:
                            f_val = parse_spanish_float(val)
                            if 470000 < f_val < 490000:
                                x_val = f_val
                            elif 4390000 < f_val < 4400000:
                                y_val = f_val
                                
                        if x_val is not None and y_val is not None:
                            points.append((x_val, y_val))
                    except ValueError:
                        continue
    except Exception as e:
        logger.error(f"Error parsing CSV: {e}")
        
    return points

VLM_PROMPT = """
You are verifying a CAD surveying task in TopoCal. 
The agent was asked to generate survey points at 25m intervals along a road alignment polyline.

Review the trajectory frames and the final screenshot.
1. Did the agent import or display the DXF polyline?
2. Are there multiple discrete points (PKs or stations) visibly overlaid evenly along the length of the line?
3. Is there evidence of the agent interacting with export/save dialogs or point generation menus?

Return JSON format:
{
    "polyline_visible": true/false,
    "points_evenly_spaced_on_line": true/false,
    "ui_interaction_successful": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

def verify_generate_alignment_stations(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_interval = metadata.get('expected_interval_m', 25.0)
    tolerance = metadata.get('tolerance_m', 0.5)
    min_points = metadata.get('min_points_expected', 25)

    feedback = []
    score = 0
    passed = False

    # 1. Retrieve the Task Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/Users/Docker/AppData/Local/Temp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Creation and Modifications
    csv_modified = result.get('csv_modified', False)
    top_modified = result.get('top_modified', False)
    
    if csv_modified:
        score += 20
        feedback.append("✅ CSV export file created/modified successfully.")
    else:
        feedback.append("❌ CSV file was not successfully exported.")
        
    if top_modified:
        score += 10
        feedback.append("✅ TopoCal project saved successfully.")
    else:
        feedback.append("❌ TopoCal project was not saved.")

    # 3. Retrieve and Parse Output Data
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    points = []
    try:
        copy_from_env("C:/Users/Docker/Documents/station_points.csv", temp_csv.name)
        points = extract_coordinates(temp_csv.name)
    except Exception as e:
        logger.warning(f"Could not copy or read CSV: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 4. Analyze Geometry (The core anti-gaming programmatic check)
    if len(points) >= min_points:
        score += 20
        feedback.append(f"✅ Exported adequate number of points ({len(points)}).")
        
        # Calculate consecutive distances
        valid_intervals = 0
        total_intervals = len(points) - 1
        
        for i in range(total_intervals):
            p1, p2 = points[i], points[i+1]
            dist = math.dist(p1, p2)
            if abs(dist - expected_interval) <= tolerance:
                valid_intervals += 1
                
        interval_accuracy = valid_intervals / total_intervals if total_intervals > 0 else 0
        
        if interval_accuracy >= 0.8:
            score += 30
            feedback.append(f"✅ Point spacing geometry is accurate (averaging {expected_interval}m).")
        elif interval_accuracy >= 0.4:
            score += 15
            feedback.append(f"⚠️ Point spacing is partially accurate ({valid_intervals}/{total_intervals} segments match).")
        else:
            feedback.append(f"❌ Points do not match the expected {expected_interval}m interval geometry.")
    elif len(points) > 0:
        feedback.append(f"❌ Exported file contains too few points ({len(points)}).")
    else:
        feedback.append("❌ Exported file contains no valid point coordinate data.")

    # 5. VLM Visual Verification (Ensures visual UI execution)
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_img = get_final_screenshot(traj)
        images = frames + [final_img] if final_img else frames
        
        if images:
            vlm_res = query_vlm(images=images, prompt=VLM_PROMPT)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("points_evenly_spaced_on_line", False):
                    score += 10
                    feedback.append("✅ VLM confirmed visual representation of station points.")
                if parsed.get("ui_interaction_successful", False):
                    score += 10
                    feedback.append("✅ VLM confirmed UI interaction with generation/export tools.")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback.append("⚠️ VLM verification skipped or failed.")

    # Final logic
    if score >= 70 and csv_modified:
        passed = True

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "points_extracted": len(points)
        }
    }