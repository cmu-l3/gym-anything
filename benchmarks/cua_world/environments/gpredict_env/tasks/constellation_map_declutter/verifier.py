#!/usr/bin/env python3
"""
Verifier for constellation_map_declutter task.

This verifier uses a hybrid approach (config parsing + VLM visual fallback)
to ensure task success despite potential GLib keyfile structural variants.
"""

import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_constellation_map_declutter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()
        
        copy_from_env("/tmp/constellation_map_declutter_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: SvalSat Ground Station (20 pts)
    # ---------------------------------------------------------
    if result.get('svalsat_exists'):
        lat_ok = _close_enough(result.get('svalsat_lat', ''), 78.2298, 0.5)
        lon_ok = _close_enough(result.get('svalsat_lon', ''), 15.4078, 0.5)
        alt_ok = _close_enough(result.get('svalsat_alt', ''), 450, 50)
        
        if lat_ok and lon_ok and alt_ok:
            score += 20
            feedback_parts.append("SvalSat ground station correct")
        else:
            score += 10
            feedback_parts.append(f"SvalSat exists but coords off (Lat: {result.get('svalsat_lat')}, Lon: {result.get('svalsat_lon')})")
    else:
        feedback_parts.append("SvalSat ground station NOT FOUND")

    # ---------------------------------------------------------
    # Criterion 2: Module Populated & Bound (30 pts)
    # ---------------------------------------------------------
    coverage_disabled = False
    track_disabled = False
    
    if result.get('module_exists'):
        sats_str = result.get('module_satellites', '')
        required_sats = [25544, 48274, 53239, 37849, 32958, 37214, 35951]
        
        found_sats = 0
        for sat in required_sats:
            if str(sat) in sats_str:
                found_sats += 1
                
        if found_sats == len(required_sats):
            score += 20
            feedback_parts.append("Dense_Constellation has all 7 required satellites")
        else:
            partial = int((found_sats / len(required_sats)) * 20)
            score += partial
            feedback_parts.append(f"Dense_Constellation has {found_sats}/{len(required_sats)} satellites")
            
        qthfile = result.get('module_qthfile', '').lower()
        svalsat_filename = result.get('svalsat_filename', '').lower()
        if qthfile and (svalsat_filename in qthfile or 'svalsat' in qthfile):
            score += 10
            feedback_parts.append("Module correctly bound to SvalSat")
        else:
            feedback_parts.append(f"Module QTH binding incorrect: {qthfile}")
            
        mod_content = result.get('module_content', '').lower()
        
        # Look for typical boolean properties setting these to false or 0
        if re.search(r'(coverage|footprint).*?(false|0)', mod_content):
            coverage_disabled = True
        if re.search(r'track.*?(false|0)', mod_content):
            track_disabled = True
            
    else:
        feedback_parts.append("Dense_Constellation module NOT FOUND")

    # ---------------------------------------------------------
    # Criterion 3: DMS Coordinate Format (20 pts)
    # ---------------------------------------------------------
    coord_format = result.get('coord_format', '')
    if coord_format == '1':
        score += 20
        feedback_parts.append("Coordinate format changed to DMS")

    # ---------------------------------------------------------
    # VLM Verification (Fallback for Map Tracking & Format)
    # ---------------------------------------------------------
    final_img = get_final_screenshot(traj)
    if final_img:
        prompt = """
        Analyze this screenshot of GPredict satellite tracking software.
        1. Look at the map view. Are there large semi-transparent circular "coverage areas" or "footprints" drawn around the satellites?
        2. Are there trailing sinusoidal "ground tracks" (lines indicating the satellite's past/future path) drawn on the map?
        3. Look at any coordinates shown on the screen (e.g., in the module list, status bar, or next to ground stations). Are they in Degrees, Minutes, Seconds (DMS) format containing ° ' " symbols, rather than plain decimals?
        
        Return JSON:
        {
            "has_coverage_areas": true/false,
            "has_ground_tracks": true/false,
            "uses_dms_format": true/false
        }
        """
        try:
            vlm_resp = query_vlm(prompt, image=final_img)
            parsed = vlm_resp.get("parsed", {})
            
            if not coverage_disabled and not parsed.get("has_coverage_areas", True):
                coverage_disabled = True
                feedback_parts.append("VLM confirms coverage areas are disabled visually")
                
            if not track_disabled and not parsed.get("has_ground_tracks", True):
                track_disabled = True
                feedback_parts.append("VLM confirms ground tracks are disabled visually")
                
            if coord_format != '1' and parsed.get("uses_dms_format", False):
                score += 20
                coord_format = '1'
                feedback_parts.append("VLM confirms DMS format is used visually")
                
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    # Accumulate points for successfully disabled map elements
    if coverage_disabled:
        score += 15
        feedback_parts.append("Coverage areas disabled in config/UI")
    else:
        feedback_parts.append("Coverage areas NOT disabled")

    if track_disabled:
        score += 15
        feedback_parts.append("Ground tracks disabled in config/UI")
    else:
        feedback_parts.append("Ground tracks NOT disabled")

    # Final scoring
    score = min(100, score)
    decluttering_success = coverage_disabled and track_disabled
    passed = score >= 70 and decluttering_success
    
    if not decluttering_success:
        feedback_parts.append("CRITICAL FAILURE: Map was not fully decluttered (must disable BOTH coverage areas and ground tracks)")
        
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }