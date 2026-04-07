#!/usr/bin/env python3
"""
Verifier for arctic_icebreaker_wx_tracking task.

Verification Strategy:
1. RV_Polarstern QTH Created (15 pts) - Correct lat/lon/alt.
2. Default QTH Updated (10 pts) - gpredict.cfg DEFAULT_QTH points to Polarstern.
3. Arctic_WX Module Created (20 pts) - Contains NOAA 15, 18, 19.
4. No Extraneous Satellites (10 pts) - Module contains ONLY the 3 required sats.
5. Map visual settings (45 pts total, 15 each):
   - Grid enabled
   - Terminator enabled
   - 2 orbits tracked
   * Map settings are checked via config strings OR VLM fallback on trajectory/final screenshot.
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames, query_vlm

logger = logging.getLogger(__name__)


def _close_enough(value_str: str, expected_float: float, tolerance: float = 0.1) -> bool:
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def _check_config_visual_settings(gpredict_cfg: str, module_cfg: str) -> Dict[str, bool]:
    """Check map settings directly from config strings if available."""
    settings = {
        'grid': False,
        'terminator': False,
        'orbits': False
    }
    combined_cfg = gpredict_cfg + "|" + module_cfg

    # Check for GRID=1 or GRID=true
    if re.search(r'GRID\s*=\s*(1|true)', combined_cfg, re.IGNORECASE):
        settings['grid'] = True
    
    # Check for TERMINATOR=1 or TERMINATOR=true
    if re.search(r'TERMINATOR\s*=\s*(1|true)', combined_cfg, re.IGNORECASE):
        settings['terminator'] = True

    # Check for TRACK_ORBITS=2 or ORBITS=2
    if re.search(r'(TRACK_ORBITS|ORBITS)\s*=\s*2', combined_cfg, re.IGNORECASE):
        settings['orbits'] = True
        
    return settings


def _verify_visuals_vlm(traj: list) -> Dict[str, bool]:
    """Fallback to VLM if config file parsing isn't conclusive."""
    frames = sample_trajectory_frames(traj, n=3)
    final = get_final_screenshot(traj)
    if final:
        frames.append(final)
        
    if not frames:
        return {'grid': False, 'terminator': False, 'orbits': False}

    prompt = """You are analyzing screenshots of GPredict (a satellite tracking application).
Determine if the user successfully changed the Map View preferences.

Look at the map and answer these three questions with true/false:
1. Are latitude and longitude grid lines clearly visible on the map?
2. Is the day/night terminator visible? (A shaded dark area covering part of the Earth map representing night)
3. Do the satellite ground track lines (green/colored lines extending from the satellites) stretch out far enough to show multiple orbits (looping around the map multiple times)?

Respond strictly in JSON format:
{
    "grid_visible": true/false,
    "terminator_visible": true/false,
    "multiple_orbits_visible": true/false
}
"""
    vlm_result = query_vlm(images=frames, prompt=prompt)
    parsed = vlm_result.get("parsed", {})
    
    return {
        'grid': parsed.get('grid_visible', False),
        'terminator': parsed.get('terminator_visible', False),
        'orbits': parsed.get('multiple_orbits_visible', False)
    }


def verify_arctic_icebreaker_wx_tracking(traj, env_info, task_info):
    """
    Score the task execution out of 100 points.
    Pass threshold: 70 points.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_sats = [str(sat) for sat in metadata.get('expected_sats', [25338, 28654, 33591])]

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/arctic_icebreaker_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []

    # Anti-gaming check: Make sure QTH file was created during task
    qth_mtime = result.get('polarstern_mtime', 0)
    task_start = result.get('task_start_timestamp', 0)
    
    # 1. RV_Polarstern QTH (15 pts)
    if result.get('polarstern_exists'):
        if qth_mtime >= task_start:
            lat_ok = _close_enough(result.get('polarstern_lat', ''), 82.5, 0.1)
            lon_ok = _close_enough(result.get('polarstern_lon', ''), 15.0, 0.1)
            alt_ok = _close_enough(result.get('polarstern_alt', ''), 0, 1)

            if lat_ok and lon_ok and alt_ok:
                score += 15
                feedback_parts.append("RV_Polarstern QTH correctly configured")
            elif lat_ok and lon_ok:
                score += 10
                feedback_parts.append("RV_Polarstern QTH created, but altitude is wrong")
            else:
                score += 5
                feedback_parts.append("RV_Polarstern QTH created with incorrect coordinates")
        else:
            feedback_parts.append("RV_Polarstern QTH existed before task (invalid)")
    else:
        feedback_parts.append("RV_Polarstern QTH not found")

    # 2. Default QTH Updated (10 pts)
    default_qth = result.get('default_qth', '').lower()
    if 'polarstern' in default_qth:
        score += 10
        feedback_parts.append("Default QTH set to RV_Polarstern")
    else:
        feedback_parts.append(f"Default QTH not correctly updated (found: {default_qth})")

    # 3 & 4. Arctic_WX Module (30 pts total)
    if result.get('arctic_wx_exists'):
        sats_str = result.get('arctic_wx_sats', '')
        # Split by semicolon and remove empty items
        found_sats = [s.strip() for s in sats_str.split(';') if s.strip()]
        
        # Check required
        required_found = 0
        for req in expected_sats:
            if req in found_sats:
                required_found += 1
                
        # 20 pts for getting all 3 NOAA sats
        if required_found == 3:
            score += 20
            feedback_parts.append("Arctic_WX module contains all 3 required NOAA satellites")
        elif required_found > 0:
            score += required_found * 6
            feedback_parts.append(f"Arctic_WX module contains {required_found}/3 required satellites")
            
        # 10 pts for no extraneous satellites
        if required_found == 3 and len(found_sats) == 3:
            score += 10
            feedback_parts.append("No extraneous satellites found in Arctic_WX")
        elif len(found_sats) > 3:
            feedback_parts.append(f"Extraneous satellites found ({len(found_sats)} total)")
    else:
        feedback_parts.append("Arctic_WX module not found")

    # 5. Map visual settings (45 pts total)
    cfg_visuals = _check_config_visual_settings(
        result.get('gpredict_cfg_content', ''), 
        result.get('arctic_wx_content', '')
    )
    
    # Check VLM as a backup/validation for visual settings
    vlm_visuals = _verify_visuals_vlm(traj)
    
    # Grid (15 pts)
    if cfg_visuals['grid'] or vlm_visuals['grid']:
        score += 15
        feedback_parts.append("Map Grid enabled")
    else:
        feedback_parts.append("Map Grid not enabled")
        
    # Terminator (15 pts)
    if cfg_visuals['terminator'] or vlm_visuals['terminator']:
        score += 15
        feedback_parts.append("Terminator enabled")
    else:
        feedback_parts.append("Terminator not enabled")
        
    # Orbits (15 pts)
    if cfg_visuals['orbits'] or vlm_visuals['orbits']:
        score += 15
        feedback_parts.append("Extended orbits (2) configured")
    else:
        feedback_parts.append("Extended orbits not configured")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }