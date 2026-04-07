#!/usr/bin/env python3
"""
Verifier for pacific_tsunami_wx_network task.

Task: Configure GPredict for NOAA Pacific Tsunami Warning Center:
  1. Add Ewa_Beach QTH (21.3069 N, 158.0872 W, 12m)
  2. Add Tiyan QTH (13.4834 N, 144.7977 E, 77m) - East Longitude check
  3. Add Pago_Pago QTH (14.2781 S, 170.7025 W, 3m) - Southern Hemisphere check
  4. Create PacificWX module with 5 weather satellites
  5. Set default QTH to Ewa_Beach
  6. Set units to Metric

Scoring (100 points, pass >= 70):
  - Ewa_Beach ground station: 15 pts
  - Tiyan ground station: 15 pts
  - Pago_Pago ground station (correct negative lat): 20 pts
  - PacificWX module exists: 5 pts
  - PacificWX module contains all 5 required satellites: 25 pts (5 pts each)
  - Default QTH set to Ewa_Beach: 10 pts
  - Metric units enabled: 10 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def _close_enough(val_str, expected, tol=0.05):
    try:
        if not val_str:
            return False
        return abs(float(val_str) - float(expected)) <= tol
    except (ValueError, TypeError):
        return False

def verify_pacific_tsunami_wx_network(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        copy_from_env("/tmp/pacific_tsunami_wx_network_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []
    
    qths = result.get('qth_files', [])
    mods = result.get('modules', [])
    task_start = result.get('task_start_time', 0)

    # --- Criterion 1: Ewa_Beach Ground Station (15 pts) ---
    ewa_found = False
    for qth in qths:
        if "ewa" in qth['name'].lower() or (_close_enough(qth['lat'], metadata['ewa_lat']) and _close_enough(qth['lon'], metadata['ewa_lon'])):
            ewa_found = True
            lat_ok = _close_enough(qth['lat'], metadata['ewa_lat'])
            lon_ok = _close_enough(qth['lon'], metadata['ewa_lon'])
            alt_ok = _close_enough(qth['alt'], metadata['ewa_alt'], 20)
            
            if qth['mtime'] < task_start:
                feedback_parts.append("Ewa_Beach predates task start (Anti-Gaming Triggered)")
                break

            if lat_ok and lon_ok and alt_ok:
                score += 15
                feedback_parts.append("Ewa_Beach QTH correct")
            elif lat_ok and lon_ok:
                score += 10
                feedback_parts.append(f"Ewa_Beach coords OK, alt wrong (got {qth['alt']}m)")
            else:
                score += 5
                feedback_parts.append(f"Ewa_Beach exists but coords wrong: {qth['lat']}, {qth['lon']}")
            break
            
    if not ewa_found:
        feedback_parts.append("Ewa_Beach QTH NOT FOUND")

    # --- Criterion 2: Tiyan Ground Station (15 pts) ---
    tiyan_found = False
    for qth in qths:
        if "tiyan" in qth['name'].lower() or "guam" in qth['name'].lower() or (_close_enough(qth['lat'], metadata['tiyan_lat']) and _close_enough(qth['lon'], metadata['tiyan_lon'])):
            tiyan_found = True
            lat_ok = _close_enough(qth['lat'], metadata['tiyan_lat'])
            lon_ok = _close_enough(qth['lon'], metadata['tiyan_lon'])
            alt_ok = _close_enough(qth['alt'], metadata['tiyan_alt'], 20)
            
            if qth['mtime'] < task_start:
                feedback_parts.append("Tiyan predates task start (Anti-Gaming)")
                break

            if lat_ok and lon_ok and alt_ok:
                score += 15
                feedback_parts.append("Tiyan QTH correct")
            elif lat_ok and lon_ok:
                score += 10
                feedback_parts.append(f"Tiyan coords OK, alt wrong (got {qth['alt']}m)")
            else:
                score += 5
                feedback_parts.append(f"Tiyan exists but coords wrong: {qth['lat']}, {qth['lon']}")
            break
            
    if not tiyan_found:
        feedback_parts.append("Tiyan QTH NOT FOUND")

    # --- Criterion 3: Pago_Pago Ground Station - Southern Hemisphere Check (20 pts) ---
    pago_found = False
    for qth in qths:
        if "pago" in qth['name'].lower() or "samoa" in qth['name'].lower() or (_close_enough(qth['lat'], metadata['pago_lat']) and _close_enough(qth['lon'], metadata['pago_lon'])):
            pago_found = True
            lat_ok = _close_enough(qth['lat'], metadata['pago_lat'])
            lat_pos_mistake = _close_enough(qth['lat'], abs(metadata['pago_lat']))
            lon_ok = _close_enough(qth['lon'], metadata['pago_lon'])
            alt_ok = _close_enough(qth['alt'], metadata['pago_alt'], 20)
            
            if qth['mtime'] < task_start:
                feedback_parts.append("Pago_Pago predates task start (Anti-Gaming)")
                break

            if lat_ok and lon_ok and alt_ok:
                score += 20
                feedback_parts.append("Pago_Pago QTH correct (Southern Hemisphere properly configured)")
            elif lat_ok and lon_ok:
                score += 15
                feedback_parts.append(f"Pago_Pago coords OK, alt wrong (got {qth['alt']}m)")
            elif lat_pos_mistake and lon_ok:
                score += 5
                feedback_parts.append("Pago_Pago latitude entered as positive (Northern Hemisphere). Must be negative for South.")
            else:
                score += 5
                feedback_parts.append(f"Pago_Pago exists but coords wrong: {qth['lat']}, {qth['lon']}")
            break
            
    if not pago_found:
        feedback_parts.append("Pago_Pago QTH NOT FOUND")

    # --- Criterion 4: PacificWX Module (30 pts = 5 base + 5 per satellite) ---
    wx_mod = None
    for mod in mods:
        if "pacificwx" in mod['name'].lower() or "weather" in mod['name'].lower() or "wx" in mod['name'].lower():
            wx_mod = mod
            break
            
    if wx_mod:
        if wx_mod['mtime'] < task_start:
            feedback_parts.append("PacificWX module predates task start (Anti-Gaming)")
        else:
            score += 5
            feedback_parts.append("PacificWX module exists")
            
            sats_str = wx_mod.get('satellites', '')
            found_sats = []
            missing_sats = []
            for sat_id in metadata['pacificwx_sats']:
                if str(sat_id) in sats_str:
                    score += 5
                    found_sats.append(str(sat_id))
                else:
                    missing_sats.append(str(sat_id))
            
            if len(found_sats) == 5:
                feedback_parts.append("PacificWX has all 5 required satellites")
            else:
                feedback_parts.append(f"PacificWX missing satellites: {', '.join(missing_sats)}")
    else:
        feedback_parts.append("PacificWX module NOT FOUND")

    # --- Criterion 5: Default QTH (10 pts) ---
    default_qth = result.get('default_qth', '')
    if 'ewa' in default_qth.lower():
        score += 10
        feedback_parts.append("Default QTH correctly set to Ewa_Beach")
    else:
        feedback_parts.append(f"Default QTH incorrect (got '{default_qth}')")

    # --- Criterion 6: Metric Units (10 pts) ---
    if result.get('metric_units', False):
        score += 10
        feedback_parts.append("Metric units enabled")
    else:
        feedback_parts.append("Metric units not enabled")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }