#!/usr/bin/env python3
"""
Verifier for mrcc_wall_display_layout task.

Scoring System (100 points, Threshold >= 70):
1. MRCC_Malta QTH exists & coords correct: 10 pts
2. QTH Minimum Elevation mask is ~5 degrees: 10 pts
3. Module exists and is assigned to MRCC_Malta: 15 pts
4. Satellites correct (NOAA 15, 18, 19, SUOMI NPP): 20 pts (5 each)
5. Layout is 'Map Only' (checked via UI/VLM or config): 25 pts
6. Ground Tracks enabled: 20 pts

Uses multi-signal verification including strict config parsing and VLM trajectory analysis.
"""

import json
import os
import re
import base64
import tempfile
import logging

# Gym Anything VLM tools
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def extract_ini_value(content: str, key: str) -> str:
    """Safely extract a value from an INI-like string without configparser strictness."""
    match = re.search(rf"^{key}\s*=\s*(.+)$", content, re.IGNORECASE | re.MULTILINE)
    return match.group(1).strip() if match else ""

def close_enough(val_str: str, target: float, tol: float) -> bool:
    try:
        return abs(float(val_str) - target) <= tol
    except (ValueError, TypeError):
        return False

def verify_mrcc_wall_display_layout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available."}

    metadata = task_info.get('metadata', {})
    
    # Extract JSON results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Analyze Config Files
    # ---------------------------------------------------------
    qth_content = ""
    mod_content = ""
    
    if result.get('qth_found') and result.get('qth_content_b64'):
        qth_content = base64.b64decode(result['qth_content_b64']).decode('utf-8', errors='ignore')
    
    if result.get('mod_found') and result.get('mod_content_b64'):
        mod_content = base64.b64decode(result['mod_content_b64']).decode('utf-8', errors='ignore')

    # Criterion 1: Ground Station Exists & Correct (10 pts)
    if qth_content:
        lat = extract_ini_value(qth_content, "LAT")
        lon = extract_ini_value(qth_content, "LON")
        alt = extract_ini_value(qth_content, "ALT")
        
        lat_ok = close_enough(lat, metadata.get('malta_lat', 35.9375), 0.5)
        lon_ok = close_enough(lon, metadata.get('malta_lon', 14.3978), 0.5)
        
        if lat_ok and lon_ok:
            score += 10
            feedback_parts.append("MRCC_Malta QTH created with correct coordinates.")
        else:
            feedback_parts.append(f"QTH coordinates inaccurate (Found Lat:{lat}, Lon:{lon}).")
    else:
        feedback_parts.append("MRCC_Malta QTH file NOT FOUND.")

    # Criterion 2: Min Elevation set to 5 (10 pts)
    if qth_content:
        # GPredict uses MIN_EL or MIN_ELEV
        min_el = extract_ini_value(qth_content, "MIN_EL")
        if not min_el:
            min_el = extract_ini_value(qth_content, "MIN_ELEV")
        if close_enough(min_el, metadata.get('malta_min_el', 5), 1.0):
            score += 10
            feedback_parts.append("Elevation mask set to ~5 degrees.")
        else:
            feedback_parts.append(f"Elevation mask incorrect or not found (Got '{min_el}').")

    # Criterion 3: Module & Binding (15 pts)
    if mod_content:
        qthfile = extract_ini_value(mod_content, "QTHFILE")
        expected_qthfile = result.get('qth_filename', 'MRCC_Malta.qth')
        
        if expected_qthfile and expected_qthfile.lower() in qthfile.lower():
            score += 15
            feedback_parts.append(f"Module correctly bound to {expected_qthfile}.")
        else:
            feedback_parts.append(f"Module bound to wrong QTH '{qthfile}'.")
    else:
        feedback_parts.append("SAR_Wall_Display Module NOT FOUND.")

    # Criterion 4: Satellites (20 pts)
    if mod_content:
        sat_str = extract_ini_value(mod_content, "SATELLITES")
        found_sats = []
        missing_sats = []
        
        for sat in metadata.get('required_sats', []):
            if str(sat) in sat_str:
                score += 5
                found_sats.append(str(sat))
            else:
                missing_sats.append(str(sat))
        
        if not missing_sats:
            feedback_parts.append("All 4 SAR satellites present.")
        else:
            feedback_parts.append(f"Module missing satellites: {', '.join(missing_sats)}")

    # ---------------------------------------------------------
    # VLM UI Validation (Layout & Tracks)
    # ---------------------------------------------------------
    # We fall back to programmatic checks if VLM is uncertain, but prioritize VLM
    # as GPredict's LAYOUT integer mappings can vary.
    
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=2)
    images_to_check = frames + [final_screenshot] if final_screenshot else []

    vlm_prompt = """
    Analyze this screenshot of the GPredict satellite tracking software.
    
    1. Is the application showing a "Map Only" layout? 
       (TRUE if the main window is entirely filled with a world map, and NO satellite list tables or circular polar radar plots are visible on screen).
    
    2. Are there satellite ground tracks enabled?
       (TRUE if you see lines extending ahead of or behind the satellites indicating their future/past orbital path across the map).
    
    Answer strictly in JSON format:
    {
        "is_map_only_layout": true/false,
        "ground_tracks_visible": true/false
    }
    """
    
    vlm_is_map_only = False
    vlm_tracks_visible = False
    
    if images_to_check:
        vlm_resp = query_vlm(images=images_to_check, prompt=vlm_prompt)
        if vlm_resp and "parsed" in vlm_resp:
            vlm_is_map_only = vlm_resp["parsed"].get("is_map_only_layout", False)
            vlm_tracks_visible = vlm_resp["parsed"].get("ground_tracks_visible", False)

    # Criterion 5: Layout 'Map Only' (25 pts)
    # GPredict layout integers: 4 is often Map only, but we also check VLM
    layout_val = extract_ini_value(mod_content, "LAYOUT")
    
    if vlm_is_map_only or layout_val in ["1", "4"]:
        score += 25
        feedback_parts.append("Layout confirmed as Map-Only.")
    else:
        feedback_parts.append(f"Layout not Map-Only (Config LAYOUT={layout_val}, VLM={vlm_is_map_only}).")

    # Criterion 6: Ground Tracks (20 pts)
    # GPredict uses TRACK=true/1 or SHOW_TRACK=true/1 in the config
    track_match = bool(re.search(r"TRACK\s*=\s*(1|true)", mod_content, re.IGNORECASE))
    
    if vlm_tracks_visible or track_match:
        score += 20
        feedback_parts.append("Ground tracks are enabled.")
    else:
        feedback_parts.append("Ground tracks NOT enabled.")

    # Determine pass/fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "vlm_map_only": vlm_is_map_only,
            "vlm_tracks_visible": vlm_tracks_visible
        }
    }