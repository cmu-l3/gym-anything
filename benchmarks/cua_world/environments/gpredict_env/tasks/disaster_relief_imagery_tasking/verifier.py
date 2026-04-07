#!/usr/bin/env python3
"""
Verifier for disaster_relief_imagery_tasking.

Uses a hybrid programmatic and VLM verification strategy.
Programmatic checks parse GPredict's INI files accurately using Regex to avoid configparser faults.
VLM verifies the complex visual settings (Map only view, shadows, ground tracks) if programmatic signals are missing due to unflushed buffers.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def extract_val(pattern, text):
    """Safely extracts a regex group from text."""
    if not text: 
        return None
    match = re.search(pattern, text, re.IGNORECASE | re.MULTILINE)
    return match.group(1).strip() if match else None

def close_enough(value_str, expected_float, tolerance=0.1):
    """Compares numeric string values with tolerance."""
    if not value_str: 
        return False
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_disaster_relief_imagery_tasking(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Safely load the JSON result from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    qth_content = result.get("qth_content")
    cfg_content = result.get("cfg_content")
    mod_content = result.get("mod_content")

    score = 0
    feedback = []

    # 1. Kathmandu QTH Check (15 pts)
    if qth_content:
        lat = extract_val(r'^LAT\s*=\s*([-\d\.]+)', qth_content)
        lon = extract_val(r'^LON\s*=\s*([-\d\.]+)', qth_content)
        alt = extract_val(r'^ALT\s*=\s*(\d+)', qth_content)
        wx = extract_val(r'^WX\s*=\s*(\w+)', qth_content)
        
        lat_ok = close_enough(lat, metadata.get("kathmandu_lat", 27.7172), 0.1)
        lon_ok = close_enough(lon, metadata.get("kathmandu_lon", 85.3240), 0.1)
        alt_ok = close_enough(alt, metadata.get("kathmandu_alt", 1400), 50)
        wx_ok = wx and wx.upper() == metadata.get("kathmandu_wx", "VNKT").upper()

        if lat_ok and lon_ok and alt_ok and wx_ok:
            score += 15
            feedback.append("Kathmandu QTH fully correct (15/15).")
        elif lat_ok and lon_ok:
            score += 10
            feedback.append("Kathmandu QTH coordinates correct, but ALT/WX missing or incorrect (10/15).")
        else:
            score += 5
            feedback.append("Kathmandu QTH exists but coordinates are wrong (5/15).")
    else:
        feedback.append("Kathmandu QTH not found (0/15).")

    # 2. Default QTH Changed (15 pts)
    cfg_qth = extract_val(r'^DEFAULT_QTH\s*=\s*(.+)', cfg_content)
    if cfg_qth and "kathmandu" in cfg_qth.lower():
        score += 15
        feedback.append("Default QTH correctly set to Kathmandu (15/15).")
    else:
        feedback.append(f"Default QTH incorrect or missing (found: {cfg_qth}) (0/15).")

    # 3. Disaster_EO Module Check (20 pts)
    if mod_content:
        sats = extract_val(r'^SATELLITES\s*=\s*([0-9;]+)', mod_content)
        if sats:
            req_sats = metadata.get("required_satellites", [37849, 33591, 38771, 43689])
            found_count = sum([1 for req in req_sats if str(req) in sats])
            pts = found_count * 5
            score += pts
            feedback.append(f"Disaster_EO module contains {found_count}/4 required satellites ({pts}/20).")
        else:
            feedback.append("Disaster_EO module exists but contains no satellites (0/20).")
    else:
        feedback.append("Disaster_EO module not found (0/20).")

    # Map Properties setup (Programmatic signals)
    layout_val = extract_val(r'^LAYOUT\s*=\s*(\d+)', mod_content)
    mod_tracks = extract_val(r'^TRACK_ORBITS\s*=\s*(\d+)', mod_content)
    cfg_tracks = extract_val(r'^TRACK_ORBITS\s*=\s*(\d+)', cfg_content)
    mod_shadow = extract_val(r'^SHOW_SHADOW\s*=\s*(\w+)', mod_content)
    cfg_shadow = extract_val(r'^SHOW_SHADOW\s*=\s*(\w+)', cfg_content)

    prog_map_only = (layout_val == '1')
    prog_multi_orbit = (mod_tracks == '3' or cfg_tracks == '3')
    prog_shadow = (mod_shadow in ['1', 'true', 'True'] or cfg_shadow in ['1', 'true', 'True'])

    # VLM signals (Fallback logic)
    vlm_map_only = False
    vlm_multi_orbit = False
    vlm_shadow = False

    try:
        from gym_anything.vlm import query_vlm, get_final_screenshot
        final_img = get_final_screenshot(traj)
        if final_img:
            vlm_prompt = """You are verifying a satellite tracking interface (GPredict).
Please check the following visual elements:
1. Is the view EXCLUSIVELY a Map? (No satellite list tables, no circular polar radar dials).
2. Are there long ground tracks behind the satellites projecting MULTIPLE orbits?
3. Is the day/night terminator shadow visibly rendered on the map (a dark shaded area)?

Respond in JSON format:
{
    "is_map_only_view": true/false,
    "multi_orbit_tracks_visible": true/false,
    "shadow_visible": true/false
}"""
            vlm_res = query_vlm(prompt=vlm_prompt, image=final_img)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                vlm_map_only = parsed.get("is_map_only_view", False)
                vlm_multi_orbit = parsed.get("multi_orbit_tracks_visible", False)
                vlm_shadow = parsed.get("shadow_visible", False)
                feedback.append(f"VLM visual check successful. MapOnly:{vlm_map_only}, MultiOrbit:{vlm_multi_orbit}, Shadow:{vlm_shadow}")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")
        feedback.append("VLM visual verification unavailable.")

    # 4. Map-Only Layout (20 pts)
    if prog_map_only or vlm_map_only:
        score += 20
        feedback.append("Map-only layout confirmed (20/20).")
    else:
        feedback.append("Map-only layout not confirmed (0/20).")

    # 5. Multi-Orbit Tracks (20 pts)
    if prog_multi_orbit or vlm_multi_orbit:
        score += 20
        feedback.append("Multi-orbit tracks (3) confirmed (20/20).")
    else:
        feedback.append("Multi-orbit tracks not confirmed (0/20).")

    # 6. Day/Night Shadow (10 pts)
    if prog_shadow or vlm_shadow:
        score += 10
        feedback.append("Day/night shadow confirmed (10/10).")
    else:
        feedback.append("Day/night shadow not confirmed (0/10).")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }