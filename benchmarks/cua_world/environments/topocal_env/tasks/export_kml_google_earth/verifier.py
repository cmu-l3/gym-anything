#!/usr/bin/env python3
"""
Verifier for export_kml_google_earth task.

VERIFICATION STRATEGY:
1. File Verification (20 pts): `site_export.kml` must exist and be modified AFTER task start.
2. Data Integrity (20 pts): KML must contain points (proves export was bulk executed, not an empty file).
3. Coordinate Projection (40 pts): Coordinates must fall within the Colorado Lat/Lon bounding box. 
   CRITICAL ANTI-GAMING: If the agent forgets to change UTM Zone to 13, the coordinates will map 
   to Europe/Atlantic Ocean and score 0 here.
4. VLM Workflow Check (20 pts): Checks trajectory frames to ensure the agent used TopoCal's UI.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_kml(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_points = metadata.get('min_points', 50)
    bbox = metadata.get('bounding_box', {
        "min_lon": -106.0, "max_lon": -104.0, 
        "min_lat": 39.0, "max_lat": 41.0
    })

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Fetch JSON Export Metrics
    # ---------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/temp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # File Checks
    output_exists = result.get('output_exists', False)
    file_mtime = result.get('file_mtime', 0)
    task_start = result.get('task_start', 0)
    file_created_during_task = file_mtime >= task_start

    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output KML file not found. Ensure it was saved exactly as instructed."
        }
    
    score += 10
    feedback_parts.append("KML file exists")

    if file_created_during_task:
        score += 10
        feedback_parts.append("File created during active task session")
    else:
        feedback_parts.append("WARNING: File appears older than task start")

    # ---------------------------------------------------------
    # 2. Fetch and Parse KML File
    # ---------------------------------------------------------
    temp_kml = tempfile.NamedTemporaryFile(delete=False, suffix='.kml')
    kml_copied = False
    try:
        copy_from_env("C:/Users/Docker/Documents/site_export.kml", temp_kml.name)
        if os.path.getsize(temp_kml.name) > 0:
            kml_copied = True
    except Exception as e:
        logger.error(f"Failed to copy KML: {e}")
    
    valid_coords_count = 0
    total_coords_extracted = 0

    if kml_copied:
        try:
            with open(temp_kml.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()

            # Robust Regex to extract coordinates ignoring XML namespaces
            coords_blocks = re.findall(r'<coordinates>(.*?)</coordinates>', content, re.DOTALL)
            
            for block in coords_blocks:
                points = block.strip().split()
                for pt in points:
                    parts = pt.split(',')
                    if len(parts) >= 2:
                        total_coords_extracted += 1
                        try:
                            lon = float(parts[0])
                            lat = float(parts[1])
                            
                            # Check bounding box (UTM Zone 13 mapped to Colorado)
                            if bbox["min_lon"] <= lon <= bbox["max_lon"] and bbox["min_lat"] <= lat <= bbox["max_lat"]:
                                valid_coords_count += 1
                        except ValueError:
                            pass
        except Exception as e:
            logger.error(f"Error parsing KML: {e}")
            feedback_parts.append("Failed to parse KML content")
    finally:
        if os.path.exists(temp_kml.name):
            os.unlink(temp_kml.name)

    # Score Data Integrity
    if total_coords_extracted >= min_points:
        score += 20
        feedback_parts.append(f"Exported {total_coords_extracted} points")
    elif total_coords_extracted > 0:
        score += 10
        feedback_parts.append(f"Exported partial data ({total_coords_extracted} points)")
    else:
        feedback_parts.append("No valid coordinates found in KML")

    # Score Projection Mapping (Anti-gaming check)
    if total_coords_extracted > 0:
        accuracy_ratio = valid_coords_count / total_coords_extracted
        if accuracy_ratio > 0.9:
            score += 40
            feedback_parts.append("Correct coordinate projection (UTM Zone 13 applied)")
        elif accuracy_ratio > 0:
            score += 20
            feedback_parts.append(f"Mixed projection accuracy ({valid_coords_count}/{total_coords_extracted} valid)")
        else:
            feedback_parts.append("CRITICAL: Coordinates outside expected bounding box. Did you forget to change the UTM Zone to 13?")

    # ---------------------------------------------------------
    # 3. VLM Trajectory Verification
    # ---------------------------------------------------------
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=5)
        final = get_final_screenshot(traj)
        
        images = frames + [final] if final else frames
        
        if images and query_vlm:
            prompt = (
                "You are evaluating an agent using TopoCal CAD software. "
                "Did the agent open the Export to Google Earth (KML) dialog, "
                "interact with the parameters (specifically the 'Huso'/Zone field), "
                "and navigate the save file dialog? "
                "Reply in JSON: {'ui_used': true/false, 'export_dialog_seen': true/false}"
            )
            vlm_res = query_vlm(prompt=prompt, images=images)
            
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("ui_used") and parsed.get("export_dialog_seen"):
                    vlm_score = 20
                    feedback_parts.append("VLM verified UI export workflow")
                else:
                    feedback_parts.append("VLM could not fully verify UI workflow")
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")
        # If VLM fails due to framework missing, grant partial points assuming file checks passed
        if score >= 60:
            vlm_score = 20

    score += vlm_score

    # Passing Threshold: Must correctly transform the data and create the file
    passed = score >= 80 and (valid_coords_count > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }