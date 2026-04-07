#!/usr/bin/env python3
"""
Verifier for control_room_dashboards task.

Task: Set up GEO and LEO specific dashboards for a Miami NHC operations room.
1. Remove default Amateur module
2. Add Miami_NHC ground station
3. Add GEO_WX module bounded to Miami with layout = Map
4. Add LEO_WX module bounded to Miami with layout = Polar
5. Enable UTC time display
"""

import json
import os
import tempfile
import logging

from gym_anything.vlm import get_final_screenshot, query_vlm

logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

VLM_PROMPT = """
Analyze this screenshot of the GPredict satellite tracking application.
Does the application show exactly two tracking module windows/tabs visible simultaneously or accessible?
More importantly, look at the visual layouts of the tracking modules:
1. Is there a module that displays a "Map" view (a flat map of the Earth)?
2. Is there a module that displays a "Polar" plot view (a circular radar-like plot)?
Reply in JSON format:
{
    "map_view_visible": true,
    "polar_view_visible": true
}
"""

def verify_control_room_dashboards(traj, env_info, task_info):
    """
    Verify control room dashboards configuration.
    Uses multi-criteria verification, programmatically reading configuration files
    and utilizing Vision Language Model (VLM) fallback for visual layout confirmation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/control_room_dashboards_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Could not copy result file: {e}"}

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

    # Criterion 1: Amateur Module removed (10 pts)
    if not result.get('amateur_exists', True):
        score += 10
        feedback_parts.append("Amateur module successfully removed")
    else:
        feedback_parts.append("Amateur module was not removed")

    # Criterion 2: Miami_NHC Ground Station (15 pts)
    miami_exists = result.get('miami_exists', False)
    if miami_exists:
        lat_ok = _close_enough(result.get('miami_lat', ''), 25.7543, 0.1)
        lon_ok = _close_enough(result.get('miami_lon', ''), -80.3823, 0.1)
        alt_ok = _close_enough(result.get('miami_alt', ''), 2, 5)
        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Miami_NHC ground station accurate")
        else:
            score += 5
            feedback_parts.append("Miami ground station exists but coords/alt inaccurate")
    else:
        feedback_parts.append("Miami ground station NOT FOUND")

    # Criterion 3: GEO_WX Module Satellites and QTH (15 pts)
    geo_qth_bound = False
    if result.get('geo_wx_exists', False):
        sats = result.get('geo_wx_satellites', '')
        has_41866 = '41866' in sats
        has_51850 = '51850' in sats
        has_40732 = '40732' in sats
        
        qth = result.get('geo_wx_qth', '')
        miami_qth_filename = result.get('miami_qth_filename', 'Miami_NHC.qth')
        if miami_qth_filename and miami_qth_filename in qth:
            geo_qth_bound = True
            
        sat_count = sum([has_41866, has_51850, has_40732])
        score += (sat_count * 3)
        if geo_qth_bound:
            score += 6
            feedback_parts.append(f"GEO_WX has {sat_count}/3 GEO sats and properly bound to Miami_NHC")
        else:
            feedback_parts.append(f"GEO_WX has {sat_count}/3 GEO sats but NOT bound to Miami_NHC")
    else:
        feedback_parts.append("GEO_WX module NOT FOUND")

    # Criterion 4: LEO_WX Module Satellites and QTH (15 pts)
    leo_qth_bound = False
    if result.get('leo_wx_exists', False):
        sats = result.get('leo_wx_satellites', '')
        has_33591 = '33591' in sats
        has_43689 = '43689' in sats
        has_37849 = '37849' in sats
        
        qth = result.get('leo_wx_qth', '')
        miami_qth_filename = result.get('miami_qth_filename', 'Miami_NHC.qth')
        if miami_qth_filename and miami_qth_filename in qth:
            leo_qth_bound = True
            
        sat_count = sum([has_33591, has_43689, has_37849])
        score += (sat_count * 3)
        if leo_qth_bound:
            score += 6
            feedback_parts.append(f"LEO_WX has {sat_count}/3 LEO sats and properly bound to Miami_NHC")
        else:
            feedback_parts.append(f"LEO_WX has {sat_count}/3 LEO sats but NOT bound to Miami_NHC")
    else:
        feedback_parts.append("LEO_WX module NOT FOUND")

    # Criterion 5: UTC Time Configuration (15 pts)
    if result.get('utc_time_enabled', False):
        score += 15
        feedback_parts.append("UTC time enabled")
    else:
        feedback_parts.append("UTC time NOT enabled")

    # Criterion 6: Layout validation - Map vs Polar Views (30 pts)
    geo_layout = result.get('geo_wx_layout', '')
    leo_layout = result.get('leo_wx_layout', '')
    
    prog_map_ok = False
    prog_polar_ok = False
    
    # Check programmatic layout strings if agent successfully modified defaults
    if geo_layout == '7':  # Map only layout index
        prog_map_ok = True
    elif geo_layout and geo_layout != '0':
        prog_map_ok = True  # Partial check: they successfully modified it from default
        
    if leo_layout == '8':  # Polar only layout index
        prog_polar_ok = True
    elif leo_layout and leo_layout != '0' and leo_layout != geo_layout:
        prog_polar_ok = True # Partial check: layout was customized uniquely
        
    vlm_map_ok = False
    vlm_polar_ok = False
    
    # Supplement with VLM visual verification for layout accuracy
    try:
        final_img = get_final_screenshot(traj)
        if final_img:
            vlm_res = query_vlm(prompt=VLM_PROMPT, image=final_img)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                vlm_map_ok = parsed.get('map_view_visible', False)
                vlm_polar_ok = parsed.get('polar_view_visible', False)
                logger.info(f"VLM Layout evaluation: Map={vlm_map_ok}, Polar={vlm_polar_ok}")
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")

    layout_score = 0
    if prog_map_ok or vlm_map_ok:
        layout_score += 15
        feedback_parts.append("GEO Map Layout Verified")
    else:
        feedback_parts.append("GEO Map Layout Missing")
        
    if prog_polar_ok or vlm_polar_ok:
        layout_score += 15
        feedback_parts.append("LEO Polar Layout Verified")
    else:
        feedback_parts.append("LEO Polar Layout Missing")
        
    score += layout_score

    # To pass, they need at least 70%
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }