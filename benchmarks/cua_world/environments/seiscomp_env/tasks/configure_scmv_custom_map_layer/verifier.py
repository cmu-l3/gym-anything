#!/usr/bin/env python3
"""
Verifier for configure_scmv_custom_map_layer task.

Verification Multi-Signals:
1. BNA file created during task
2. BNA valid header and points
3. BNA correct coordinate system (Longitude Latitude)
4. scmv.cfg modified to display annotations
5. Agent's required screenshot exists
6. VLM trajectory verification (scmv UI visibility with layer and labels)
"""

import json
import tempfile
import os
import base64
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_scmv_custom_layer(traj, env_info, task_info):
    """Verify BNA geospatial format creation and config changes."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Extract task JSON result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    bna_exists = result.get('bna_exists', False)
    bna_new = result.get('bna_created_during_task', False)
    
    # Check 1: BNA File existence and anti-gaming (10 points)
    if bna_exists and bna_new:
        score += 10
        feedback_parts.append("BNA file correctly created during task")
    elif bna_exists:
        score += 5
        feedback_parts.append("BNA file exists but might be stale")
    else:
        feedback_parts.append("BNA file NOT found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # Check 2: BNA Syntax and Coordinates
    bna_content_b64 = result.get('bna_content_b64', '')
    try:
        bna_text = base64.b64decode(bna_content_b64).decode('utf-8')
        lines = [l.strip() for l in bna_text.split('\n') if l.strip()]
        
        if len(lines) > 0:
            header = lines[0]
            # Verify Header Format: "Name",rank,count (10 points)
            if 'noto aftershock zone' in header.lower() and ',' in header:
                score += 10
                feedback_parts.append("BNA header correct")
            else:
                feedback_parts.append("BNA header incorrect or missing expected name")
                
            coords = []
            for line in lines[1:]:
                # Parse standard CSV-like points
                parts = line.split(',')
                if len(parts) >= 2:
                    try:
                        coords.append((float(parts[0]), float(parts[1])))
                    except ValueError:
                        pass
                        
            if len(coords) >= 4:
                # CRITICAL GIS CHECK: Longitude (X), Latitude (Y) (30 points)
                # Noto Peninsula is Longitude ~137, Latitude ~37
                lon_correct = all(135 <= c[0] <= 139 for c in coords)
                lat_correct = all(35 <= c[1] <= 39 for c in coords)
                
                if lon_correct and lat_correct:
                    score += 30
                    feedback_parts.append("Coordinate order correct (Longitude, Latitude)")
                    
                    # Verify polygon boundaries (15 points)
                    min_lon = min(c[0] for c in coords)
                    max_lon = max(c[0] for c in coords)
                    min_lat = min(c[1] for c in coords)
                    max_lat = max(c[1] for c in coords)
                    
                    if (abs(min_lon - metadata.get('min_lon', 136.60)) <= 0.2 and 
                        abs(max_lon - metadata.get('max_lon', 137.50)) <= 0.2 and 
                        abs(min_lat - metadata.get('min_lat', 37.10)) <= 0.2 and 
                        abs(max_lat - metadata.get('max_lat', 37.50)) <= 0.2):
                        score += 15
                        feedback_parts.append("Polygon vertices match requested zone")
                    else:
                        score += 5
                        feedback_parts.append("Polygon vertices deviate from requested zone")
                        
                elif all(135 <= c[1] <= 139 for c in coords) and all(35 <= c[0] <= 39 for c in coords):
                    feedback_parts.append("FAIL: Coordinates reversed! Provided Latitude, Longitude instead of Longitude, Latitude.")
                else:
                    feedback_parts.append("Coordinates far outside expected Noto Japan region.")
            else:
                feedback_parts.append("Not enough coordinates defined in polygon.")
    except Exception as e:
        feedback_parts.append(f"Failed to parse BNA: {e}")

    # Check 3: scmv.cfg modified (15 points)
    cfg_exists = result.get('cfg_exists', False)
    cfg_b64 = result.get('cfg_content_b64', '')
    if cfg_exists:
        try:
            cfg_text = base64.b64decode(cfg_b64).decode('utf-8').lower()
            if 'annotations = true' in cfg_text or 'annotations=true' in cfg_text:
                score += 15
                feedback_parts.append("scmv.cfg correctly configured for annotations")
            else:
                feedback_parts.append("scmv.cfg missing 'annotations = true'")
        except:
            feedback_parts.append("scmv.cfg format parsing error")
    else:
        feedback_parts.append("scmv.cfg file not found")

    # Check 4: Evidence captured (10 points)
    if result.get('screenshot_exists', False):
        score += 10
        feedback_parts.append("Verification screenshot created")
    else:
        feedback_parts.append("Missing required verification screenshot")

    # Check 5: VLM visual verification (10 points)
    try:
        # Import dynamically so it runs safely on framework
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=3)
            if frames:
                prompt = "Does any of these images show the SeisComP 'scmv' map application running? Look for a polygon (rectangle) drawn on the map near Japan, and text labels (like TOLI, GSI) visible next to the station triangles. Answer simply 'Yes' or 'No'."
                vlm_res = query_vlm(images=frames, prompt=prompt)
                
                if vlm_res and 'yes' in vlm_res.get('text', '').lower():
                    score += 10
                    feedback_parts.append("VLM visual confirmation successful")
                else:
                    feedback_parts.append("VLM did not detect scmv map/polygon/labels")
        else:
            # Fallback if VLM isn't configured but other rigorous checks passed
            if score >= 65:
                score += 10
                feedback_parts.append("VLM skipped (awarded automatically)")
    except ImportError:
        logger.warning("gym_anything.vlm not available for trajectory check")
        if score >= 65:
            score += 10
    except Exception as e:
        logger.warning(f"VLM error: {e}")
        
    passed = score >= 60 and bna_exists and 'Coordinate order correct' in " ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }