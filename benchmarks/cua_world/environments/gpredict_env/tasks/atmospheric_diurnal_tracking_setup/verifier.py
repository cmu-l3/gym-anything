#!/usr/bin/env python3
"""
Verifier for atmospheric_diurnal_tracking_setup task.

Verifies programmatic configuration files and utilizes VLM trajectory analysis 
as a multi-signal fallback for visual map elements (terminator line, track lengths).
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    """Check if a string-encoded float is within tolerance of expected."""
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_atmospheric_diurnal_tracking(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        try:
            copy_from_env("/tmp/atmospheric_diurnal_result.json", temp_path)
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
    
    # 1. Taipei Ground Station (20 pts)
    if result.get('taipei_exists'):
        lat_ok = _close_enough(result.get('taipei_lat', ''), metadata.get('taipei_lat', 25.0380), 0.1)
        lon_ok = _close_enough(result.get('taipei_lon', ''), metadata.get('taipei_lon', 121.5030), 0.1)
        alt_ok = _close_enough(result.get('taipei_alt', ''), metadata.get('taipei_alt', 9), 5)
        
        if lat_ok and lon_ok and alt_ok:
            score += 20
            feedback_parts.append("Taipei ground station: correct")
        elif lat_ok and lon_ok:
            score += 15
            feedback_parts.append(f"Taipei: coords OK but alt wrong ({result.get('taipei_alt')}m)")
        else:
            score += 5
            feedback_parts.append(f"Taipei exists but coords wrong (Lat={result.get('taipei_lat')}, Lon={result.get('taipei_lon')})")
    else:
        feedback_parts.append("Taipei ground station: NOT FOUND")

    # 2. Default QTH Updated (10 pts)
    default_qth = result.get('default_qth', '').lower()
    taipei_file = result.get('taipei_qth_file', '').lower()
    
    if taipei_file and taipei_file in default_qth:
        score += 10
        feedback_parts.append("Default QTH set to Taipei")
    elif 'taipei' in default_qth:
        score += 10
        feedback_parts.append("Default QTH set to Taipei")
    else:
        feedback_parts.append(f"Default QTH not set to Taipei (currently: {result.get('default_qth')})")

    # 3. COSMIC-2 Module Populated (30 pts, 5 per satellite)
    required_sats = metadata.get('cosmic_satellites', [44327, 44328, 44329, 44330, 44331, 44332])
    if result.get('cosmic_exists'):
        sat_str = result.get('cosmic_satellites', '')
        found_sats = []
        for sat in required_sats:
            if str(sat) in sat_str:
                score += 5
                found_sats.append(str(sat))
        
        if len(found_sats) == len(required_sats):
            feedback_parts.append("COSMIC-2 module has all 6 satellites")
        else:
            feedback_parts.append(f"COSMIC-2 module missing satellites (found {len(found_sats)}/{len(required_sats)})")
    else:
        feedback_parts.append("COSMIC-2 module NOT FOUND")

    # 4. UTC Time Configured (10 pts)
    if result.get('utc_time_enabled'):
        score += 10
        feedback_parts.append("UTC time enabled")
    else:
        feedback_parts.append("UTC time NOT enabled")

    # 5. Terminator & Tracks (15 pts each) via config heuristics OR VLM Trajectory analysis
    cfg_content = result.get('gpredict_cfg_content', '').lower()
    cosmic_content = result.get('cosmic_content', '').lower()
    
    terminator_config = False
    tracks_config = False
    
    if 'shadow=1' in cfg_content or 'shadow=true' in cfg_content or 'terminator=1' in cfg_content:
        terminator_config = True
    if 'shadow=1' in cosmic_content or 'shadow=true' in cosmic_content:
        terminator_config = True
        
    if re.search(r'(track|orbit)[a-z_-]*\s*=\s*2', cfg_content):
        tracks_config = True
    if re.search(r'(track|orbit)[a-z_-]*\s*=\s*2', cosmic_content):
        tracks_config = True

    # Fallback/Primary Check: Vision-Language Model over trajectory frames to catch visual effects
    vlm_terminator = False
    vlm_orbits = False
    
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        prompt = """Look at these screenshots of the GPredict satellite tracking software.
We need to verify two map visualization settings:
1. Is the day/night terminator line (a dark semi-transparent shadow covering the nighttime portion of the Earth map) visible in any of the map views?
2. Do the satellite ground tracks show multiple orbits ahead (long wavy lines wrapping around the map) rather than just a single short line?

Respond in JSON format exactly like this:
{
    "terminator_visible": true,
    "multiple_orbits_visible": true
}"""
        
        images = []
        if frames: images.extend(frames)
        if final: images.append(final)
        
        if images:
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res and isinstance(vlm_res, dict) and 'parsed' in vlm_res:
                parsed = vlm_res['parsed']
                if isinstance(parsed, dict):
                    vlm_terminator = parsed.get('terminator_visible', False)
                    vlm_orbits = parsed.get('multiple_orbits_visible', False)
    except Exception as e:
        logger.warning(f"VLM verification failed or unavailable: {e}")

    # Calculate final rendering points
    if terminator_config or vlm_terminator:
        score += 15
        feedback_parts.append("Terminator line enabled")
    else:
        feedback_parts.append("Terminator line NOT enabled")

    if tracks_config or vlm_orbits:
        score += 15
        feedback_parts.append("Multiple orbit tracks enabled")
    else:
        feedback_parts.append("Multiple orbit tracks NOT enabled")

    # Final pass logic (Score must be >= 70 AND they MUST have actually created the module and enabled terminator)
    passed = score >= 70 and result.get('cosmic_exists', False) and (terminator_config or vlm_terminator)
    
    if passed and score < 70:
        passed = False
        feedback_parts.append("Score below pass threshold (70)")
        
    if not result.get('cosmic_exists', False):
        feedback_parts.append("FAIL: COSMIC-2 module not created (Required)")

    if not (terminator_config or vlm_terminator):
        feedback_parts.append("FAIL: Terminator not enabled (Required)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }