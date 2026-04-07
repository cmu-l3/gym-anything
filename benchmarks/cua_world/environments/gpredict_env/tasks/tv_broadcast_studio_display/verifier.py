#!/usr/bin/env python3
"""
Verifier for tv_broadcast_studio_display task.

Task criteria:
1. 'Amateur' module deleted.
2. 'New_York_Studio' ground station created (Lat 40.7128, Lon -74.0060, Alt 10).
3. 'Studio_Map' module created containing ISS (25544) and HST (20580).
4. 'Studio_Map' uses 'New_York_Studio' QTH and has a Map-only layout (NVIEWS=1).
5. Map aesthetic preferences set: Day/Night Shadow ON, Grid OFF, Sun OFF, Moon OFF.

Scoring (100 points, Pass >= 70):
- Amateur Module Removed: 10 pts
- New York QTH Created: 15 pts
- Studio_Map Created (with ISS & HST): 15 pts
- QTH Assigned to Studio_Map: 10 pts
- Map-Only Layout (NVIEWS=1) and VLM confirms map view: 10 pts
- Terminator (Shadow) Enabled: 15 pts
- Clutter Disabled (Grid, Sun, Moon): 25 pts (approx 8 pts each)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, sample_trajectory_frames, get_final_screenshot

logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_tv_broadcast_studio_display(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/tv_broadcast_studio_display_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        with open(temp_path, 'r') as f:
            result = json.load(f)

    except (json.JSONDecodeError, FileNotFoundError) as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        try:
            os.unlink(temp_path)
        except Exception:
            pass

    score = 0
    feedback_parts = []

    # 1. Amateur Module Removed (10 pts)
    if not result.get('amateur_exists', True):
        score += 10
        feedback_parts.append("Amateur module deleted")
    else:
        feedback_parts.append("Amateur module NOT deleted")

    # 2. New York QTH Created (15 pts)
    ny_qth_filename = result.get('ny_qth_filename', '')
    if result.get('ny_exists'):
        lat_ok = _close_enough(result.get('ny_lat', ''), metadata.get('ny_lat', 40.7128), 0.1)
        lon_ok = _close_enough(result.get('ny_lon', ''), metadata.get('ny_lon', -74.0060), 0.1)
        alt_ok = _close_enough(result.get('ny_alt', ''), metadata.get('ny_alt', 10), 5)
        
        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append(f"New York QTH '{ny_qth_filename}' correct")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append(f"New York QTH '{ny_qth_filename}' coordinates OK, alt incorrect")
        else:
            score += 5
            feedback_parts.append(f"New York QTH '{ny_qth_filename}' exists but coords wrong")
    else:
        feedback_parts.append("New York QTH NOT found")

    # 3. Studio_Map Created with 25544, 20580 (15 pts)
    sm_sats = result.get('sm_satellites', '')
    has_iss = "25544" in sm_sats
    has_hst = "20580" in sm_sats
    
    if result.get('studio_map_exists'):
        if has_iss and has_hst:
            score += 15
            feedback_parts.append("Studio_Map has ISS and HST")
        elif has_iss or has_hst:
            score += 7
            feedback_parts.append("Studio_Map missing either ISS or HST")
        else:
            feedback_parts.append("Studio_Map exists but missing target satellites")
    else:
        feedback_parts.append("Studio_Map module NOT found")

    # 4. QTH Assigned to Studio_Map (10 pts)
    sm_qth = result.get('sm_qth', '')
    if result.get('studio_map_exists') and ny_qth_filename:
        # e.g., "New_York_Studio.qth"
        if ny_qth_filename.lower() in sm_qth.lower():
            score += 10
            feedback_parts.append("Studio_Map bound to New York QTH")
        else:
            feedback_parts.append(f"Studio_Map bound to '{sm_qth}' instead of NY QTH")
    else:
        feedback_parts.append("QTH assignment check failed (missing module or QTH)")

    # 5. Map-Only Layout (10 pts)
    # Check if NVIEWS=1
    sm_nviews = result.get('sm_nviews', '0')
    if result.get('studio_map_exists'):
        if sm_nviews == "1":
            score += 10
            feedback_parts.append("Studio_Map layout configured to single view")
        else:
            feedback_parts.append(f"Studio_Map NVIEWS={sm_nviews} (expected 1 for Map-only)")

    # 6. Map Aesthetics (Terminator + Clutter)
    cfg_grid = result.get('cfg_grid', '').lower()
    cfg_sun = result.get('cfg_sun', '').lower()
    cfg_moon = result.get('cfg_moon', '').lower()
    cfg_shadow = result.get('cfg_shadow', '').lower()

    # Terminator Enabled (15 pts)
    if cfg_shadow == 'true':
        score += 15
        feedback_parts.append("Terminator shadow ENABLED")
    else:
        feedback_parts.append("Terminator shadow NOT enabled")

    # Clutter Disabled (25 pts total)
    clutter_score = 0
    if cfg_grid == 'false':
        clutter_score += 9
        feedback_parts.append("Map Grid DISABLED")
    else:
        feedback_parts.append("Map Grid still enabled")
        
    if cfg_sun == 'false':
        clutter_score += 8
        feedback_parts.append("Sun icon DISABLED")
    else:
        feedback_parts.append("Sun icon still enabled")
        
    if cfg_moon == 'false':
        clutter_score += 8
        feedback_parts.append("Moon icon DISABLED")
    else:
        feedback_parts.append("Moon icon still enabled")
        
    score += clutter_score

    # VLM Verification as a secondary check for aesthetics / single map layout
    vlm_feedback = ""
    try:
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            prompt = """
            You are evaluating a GPredict satellite tracking window configured for a TV broadcast.
            Look at the UI state shown in this screenshot.
            
            Determine the following:
            1. Is the application showing ONLY a single large map? (No satellite list pane, no circular radar/polar pane).
            2. Is the map clean, meaning there are NO visible grid lines (latitude/longitude boxes)?
            3. Is the day/night shadow clearly visible on the map?
            
            Return JSON only:
            {
                "is_single_map_only": true/false,
                "is_grid_disabled": true/false,
                "is_shadow_visible": true/false
            }
            """
            vlm_response = query_vlm(prompt=prompt, image=final_screenshot)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                vlm_feedback = f" [VLM Visual Check: single_map={parsed.get('is_single_map_only')}, grid_clean={parsed.get('is_grid_disabled')}, shadow={parsed.get('is_shadow_visible')}]"
                
                # We do not override programmatic file parsing score, but if file check fails and VLM sees it, 
                # or file check passes and VLM contradicts completely, we can note it. 
                # Since programmatic check is very reliable for Gpredict configs, we use VLM mostly as trajectory validation / human readable feedback.
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    final_feedback = " | ".join(feedback_parts) + vlm_feedback
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": final_feedback
    }