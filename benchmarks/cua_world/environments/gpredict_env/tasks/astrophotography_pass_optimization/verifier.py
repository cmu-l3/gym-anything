#!/usr/bin/env python3
"""
Verifier for astrophotography_pass_optimization task.
Evaluates agent's ability to configure advanced pass prediction preferences and multi-layered station data.

Scoring (100 points, pass >= 70):
  - MaunaKea.qth exists & has correct Lat/Lon/Alt/WX: 20 pts
  - Default QTH in gpredict.cfg points to MaunaKea: 10 pts
  - Astro_Targets.mod contains 4 required sats: 20 pts (5 pts each)
  - Predictor Min Elevation = 35: 15 pts
  - Predictor Max Sun Elevation = -12: 15 pts
  - Predictor Number of Passes = 20: 10 pts
  - Global UTC time set: 10 pts
"""

import json
import os
import re
import base64
import tempfile
import logging

logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_astrophotography_pass_optimization(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    # 1. Fetch JSON result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/astrophotography_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        if os.path.exists(temp_path): os.unlink(temp_path)
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []
    
    # Decode Base64 contents
    qth_content = base64.b64decode(result.get('maunakea_qth_b64', '')).decode('utf-8', errors='ignore')
    mod_content = base64.b64decode(result.get('astro_mod_b64', '')).decode('utf-8', errors='ignore')
    cfg_content = base64.b64decode(result.get('gpredict_cfg_b64', '')).decode('utf-8', errors='ignore')

    # --- Criterion 1: MaunaKea Ground Station (20 pts) ---
    if qth_content:
        lat_match = re.search(r'(?i)^LAT\s*=\s*([-0-9.]+)', qth_content, re.MULTILINE)
        lon_match = re.search(r'(?i)^LON\s*=\s*([-0-9.]+)', qth_content, re.MULTILINE)
        alt_match = re.search(r'(?i)^ALT\s*=\s*([-0-9.]+)', qth_content, re.MULTILINE)
        wx_match = re.search(r'(?i)^WX\s*=\s*([A-Z]+)', qth_content, re.MULTILINE)

        lat = lat_match.group(1) if lat_match else ""
        lon = lon_match.group(1) if lon_match else ""
        alt = alt_match.group(1) if alt_match else ""
        wx = wx_match.group(1).upper() if wx_match else ""

        lat_ok = _close_enough(lat, metadata.get('maunakea_lat', 19.8206), 0.1)
        lon_ok = _close_enough(lon, metadata.get('maunakea_lon', -155.4681), 0.1)
        alt_ok = _close_enough(alt, metadata.get('maunakea_alt', 4205), 50)
        wx_ok = (wx == metadata.get('maunakea_wx', 'PHSF'))

        if lat_ok and lon_ok and alt_ok:
            score += 15
            if wx_ok:
                score += 5
                feedback_parts.append("Mauna Kea QTH: Perfect (Lat, Lon, Alt, WX)")
            else:
                feedback_parts.append(f"Mauna Kea QTH: Coords OK, but WX code wrong ({wx})")
        else:
            score += 5
            feedback_parts.append(f"Mauna Kea QTH exists but coords are incorrect (Lat:{lat}, Lon:{lon}, Alt:{alt})")
    else:
        feedback_parts.append("Mauna Kea QTH: NOT FOUND")

    # --- Criterion 2: Default QTH Configuration (10 pts) ---
    qth_filename = result.get('qth_filename', '')
    if cfg_content and qth_filename:
        # Check if the exact filename is set as DEFAULT_QTH
        default_qth_match = re.search(r'(?i)^DEFAULT_QTH\s*=\s*([^\r\n]+)', cfg_content, re.MULTILINE)
        if default_qth_match and default_qth_match.group(1).strip() == qth_filename:
            score += 10
            feedback_parts.append("Default QTH successfully set to Mauna Kea")
        else:
            feedback_parts.append("Default QTH not updated to Mauna Kea")
    else:
        feedback_parts.append("Default QTH: Setup incomplete")

    # --- Criterion 3: Astro_Targets Module (20 pts) ---
    if mod_content:
        sat_match = re.search(r'(?i)^SATELLITES\s*=\s*([0-9;]+)', mod_content, re.MULTILINE)
        if sat_match:
            sat_str = sat_match.group(1)
            req_sats = metadata.get('required_sats', [25544, 48274, 49044, 37849])
            sats_found = 0
            for sat in req_sats:
                if str(sat) in sat_str:
                    sats_found += 1
            
            pts = sats_found * 5
            score += pts
            feedback_parts.append(f"Astro_Targets module: Found {sats_found}/4 required satellites (+{pts} pts)")
        else:
            feedback_parts.append("Astro_Targets module exists but SATELLITES key is missing/empty")
    else:
        feedback_parts.append("Astro_Targets module: NOT FOUND")

    # --- Criterion 4: Predictor & UTC Settings (50 pts total) ---
    if cfg_content:
        # Minimum Elevation (15 pts)
        min_el_match = re.search(r'(?i)^MIN_EL\s*=\s*([-0-9]+)', cfg_content, re.MULTILINE)
        if min_el_match and int(min_el_match.group(1)) == metadata.get('predictor_min_el', 35):
            score += 15
            feedback_parts.append("Predictor Min Elevation: Correct (35°)")
        else:
            v = min_el_match.group(1) if min_el_match else "Unset"
            feedback_parts.append(f"Predictor Min Elevation: Incorrect ({v})")

        # Maximum Sun Elevation (15 pts)
        sun_el_match = re.search(r'(?i)^MAX_SUN_EL\s*=\s*([-0-9]+)', cfg_content, re.MULTILINE)
        if sun_el_match and int(sun_el_match.group(1)) == metadata.get('predictor_max_sun_el', -12):
            score += 15
            feedback_parts.append("Predictor Max Sun Elevation: Correct (-12°)")
        else:
            v = sun_el_match.group(1) if sun_el_match else "Unset"
            feedback_parts.append(f"Predictor Max Sun Elevation: Incorrect ({v})")

        # Number of Passes (10 pts)
        passes_match = re.search(r'(?i)^NUM_PASSES\s*=\s*([-0-9]+)', cfg_content, re.MULTILINE)
        if passes_match and int(passes_match.group(1)) == metadata.get('predictor_num_passes', 20):
            score += 10
            feedback_parts.append("Predictor Passes Count: Correct (20)")
        else:
            v = passes_match.group(1) if passes_match else "Unset"
            feedback_parts.append(f"Predictor Passes Count: Incorrect ({v})")

        # UTC Time (10 pts) -> check for TIME_FORMAT=2 or utc=1
        utc_match = re.search(r'(?i)^(TIME_FORMAT\s*=\s*2|UTC\s*=\s*1)', cfg_content, re.MULTILINE)
        if utc_match:
            score += 10
            feedback_parts.append("Global Time Format: UTC enabled")
        else:
            feedback_parts.append("Global Time Format: UTC not enabled")
    else:
        feedback_parts.append("CRITICAL: gpredict.cfg not found")

    # VLM Trajectory Verification check (Secondary anti-gaming / confirmation)
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = (
                "You are reviewing the screen trajectory of an agent configuring GPredict software. "
                "Did the agent open the 'Preferences' dialog box and interact with the 'Predictor' tab? "
                "Just answer Yes or No."
            )
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and "yes" in str(vlm_res.get('parsed', '')).lower():
                feedback_parts.append("VLM confirms Preferences dialog interaction")
    except Exception as e:
        logger.warning(f"VLM trajectory check skipped or failed: {e}")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }