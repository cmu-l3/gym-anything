#!/usr/bin/env python3
"""
Verifier for research_vessel_expedition task.

Task: Configure GPredict for a North Atlantic research expedition:
  1. Delete stale PreviousCruise.qth
  2. Add Woods_Hole QTH (41.5243 N, 70.6693 W, 2m)
  3. Add MidAtlantic QTH (42.0000 N, 30.0000 W, 0m)
  4. Create WX_Reception.mod (NOAA 15, 18, 19) locked to Woods_Hole
  5. Create SatComm.mod (ISS, SO-50, AO-73) locked to MidAtlantic
  6. Keep Amateur.mod intact

Scoring (100 points, pass >= 60):
  - PreviousCruise.qth deleted: 10 pts
  - Woods_Hole QTH correct: 12 pts
  - MidAtlantic QTH correct: 12 pts
  - WX_Reception module exists: 5 pts
  - WX_Reception satellites correct (5x3): 15 pts
  - WX_Reception QTH override correct: 10 pts
  - SatComm module exists: 5 pts
  - SatComm satellites correct (5x3): 15 pts
  - SatComm QTH override correct: 10 pts
  - Amateur.mod exists: 6 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def verify_research_vessel_expedition(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    # Load result JSON
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/research_vessel_expedition_result.json", temp_path)
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
    task_start = result.get('task_start_time', 0)

    # 1. PreviousCruise deleted (10 pts)
    if result.get('previous_cruise_deleted'):
        score += 10
        feedback_parts.append("PreviousCruise deleted")
    else:
        feedback_parts.append("PreviousCruise NOT deleted")

    # 2. Woods_Hole QTH (12 pts)
    wh_qth_filename = ""
    if result.get('woods_hole_exists'):
        lat_ok = _close_enough(result.get('woods_hole_lat', ''), metadata.get('woods_hole_lat', 41.5243), 0.05)
        lon_ok = _close_enough(result.get('woods_hole_lon', ''), metadata.get('woods_hole_lon', -70.6693), 0.05)
        alt_ok = _close_enough(result.get('woods_hole_alt', ''), metadata.get('woods_hole_alt', 2), 10)
        
        if lat_ok and lon_ok and alt_ok:
            score += 12
            wh_qth_filename = result.get('woods_hole_qth_file', '')
            feedback_parts.append("Woods_Hole QTH correct")
        elif lat_ok and lon_ok:
            score += 8
            wh_qth_filename = result.get('woods_hole_qth_file', '')
            feedback_parts.append("Woods_Hole QTH: coords ok, alt wrong")
    else:
        feedback_parts.append("Woods_Hole QTH NOT found")

    # 3. MidAtlantic QTH (12 pts)
    ma_qth_filename = ""
    if result.get('midatlantic_exists'):
        lat_ok = _close_enough(result.get('midatlantic_lat', ''), metadata.get('midatlantic_lat', 42.0), 0.05)
        lon_ok = _close_enough(result.get('midatlantic_lon', ''), metadata.get('midatlantic_lon', -30.0), 0.05)
        alt_ok = _close_enough(result.get('midatlantic_alt', ''), metadata.get('midatlantic_alt', 0), 10)
        
        if lat_ok and lon_ok and alt_ok:
            score += 12
            ma_qth_filename = result.get('midatlantic_qth_file', '')
            feedback_parts.append("MidAtlantic QTH correct")
        elif lat_ok and lon_ok:
            score += 8
            ma_qth_filename = result.get('midatlantic_qth_file', '')
            feedback_parts.append("MidAtlantic QTH: coords ok, alt wrong")
    else:
        feedback_parts.append("MidAtlantic QTH NOT found")

    # 4 & 6. WX_Reception module exists (5 pts) and QTH override (10 pts)
    if result.get('wx_exists'):
        # Check if created during task (anti-gaming)
        if result.get('wx_mtime', 0) > task_start:
            score += 5
            
            # Satellites (15 pts)
            wx_sats = result.get('wx_satellites', '')
            sats_found = 0
            for sid in metadata.get('wx_satellites', [25338, 28654, 33591]):
                if str(sid) in wx_sats:
                    score += 5
                    sats_found += 1
            feedback_parts.append(f"WX_Reception has {sats_found}/3 satellites")
            
            # QTH override (10 pts)
            wx_qthfile = result.get('wx_qthfile', '')
            # Match the exact filename we discovered, or just text containing "wood"
            if wh_qth_filename and wh_qth_filename == wx_qthfile:
                score += 10
                feedback_parts.append("WX_Reception QTH locked correctly")
            elif "wood" in wx_qthfile.lower():
                score += 8
                feedback_parts.append("WX_Reception QTH locked (fuzzy match)")
            else:
                feedback_parts.append(f"WX_Reception QTH mismatch (got {wx_qthfile})")
        else:
            feedback_parts.append("WX_Reception module created BEFORE task started (gaming detected)")
    else:
        feedback_parts.append("WX_Reception module NOT found")

    # 5 & 6. SatComm module exists (5 pts) and QTH override (10 pts)
    if result.get('satcomm_exists'):
        if result.get('satcomm_mtime', 0) > task_start:
            score += 5
            
            # Satellites (15 pts)
            satcomm_sats = result.get('satcomm_satellites', '')
            sats_found = 0
            for sid in metadata.get('satcomm_satellites', [25544, 27607, 39444]):
                if str(sid) in satcomm_sats:
                    score += 5
                    sats_found += 1
            feedback_parts.append(f"SatComm has {sats_found}/3 satellites")
            
            # QTH override (10 pts)
            satcomm_qthfile = result.get('satcomm_qthfile', '')
            if ma_qth_filename and ma_qth_filename == satcomm_qthfile:
                score += 10
                feedback_parts.append("SatComm QTH locked correctly")
            elif "mid" in satcomm_qthfile.lower() or "atlantic" in satcomm_qthfile.lower():
                score += 8
                feedback_parts.append("SatComm QTH locked (fuzzy match)")
            else:
                feedback_parts.append(f"SatComm QTH mismatch (got {satcomm_qthfile})")
        else:
            feedback_parts.append("SatComm module created BEFORE task started (gaming detected)")
    else:
        feedback_parts.append("SatComm module NOT found")

    # 7. Amateur.mod untouched (6 pts)
    if result.get('amateur_exists'):
        score += 6
        feedback_parts.append("Amateur.mod intact")
    else:
        feedback_parts.append("Amateur.mod MISSING")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }