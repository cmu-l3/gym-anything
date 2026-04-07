#!/usr/bin/env python3
"""
Verifier for noaa_apt_reception_setup task.

Verification Strategy:
  1. Module Validation: Check NOAA_APT exists, contains 25338, 28654, 33591 (24 pts)
  2. Module Cleanliness: No extraneous satellites (6 pts)
  3. Transponder Frequencies: DOWN_LOW within +/- 500 Hz for each satellite (30 pts, 10 each)
  4. Transponder Modes: MODE=APT present (5 pts)
  5. Ground Station: Wallops QTH exists with correct LAT/LON/ALT (20 pts)
  6. Ground Tracks: TRACK_NUM set to 3 (5 pts)
  7. Anti-Gaming: Files created AFTER task start, old configs preserved (10 pts)
"""

import json
import os
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


def verify_noaa_apt_reception_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    noaa15_id = str(metadata.get('noaa15_id', 25338))
    noaa18_id = str(metadata.get('noaa18_id', 28654))
    noaa19_id = str(metadata.get('noaa19_id', 33591))
    
    noaa15_freq = float(metadata.get('noaa15_freq_hz', 137620000))
    noaa18_freq = float(metadata.get('noaa18_freq_hz', 137912500))
    noaa19_freq = float(metadata.get('noaa19_freq_hz', 137100000))
    freq_tolerance = float(metadata.get('freq_tolerance_hz', 500))
    expected_mode = metadata.get('expected_mode', 'APT')
    
    wallops_lat = metadata.get('wallops_lat', 37.9402)
    wallops_lon = metadata.get('wallops_lon', -75.4664)
    wallops_alt = metadata.get('wallops_alt', 12)
    expected_track_count = str(metadata.get('expected_track_count', 3))

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or read result file: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback_parts = []
    task_start = result.get('task_start', 0)
    
    # === Criterion 1 & 2: NOAA_APT Module (30 pts) ===
    if result.get('noaa_mod_exists', False):
        sats = result.get('noaa_satellites', '')
        sat_list = [s for s in sats.split(';') if s.strip()]
        
        has_15 = any(noaa15_id in s for s in sat_list)
        has_18 = any(noaa18_id in s for s in sat_list)
        has_19 = any(noaa19_id in s for s in sat_list)
        
        if has_15: score += 8
        if has_18: score += 8
        if has_19: score += 8
        
        if has_15 and has_18 and has_19:
            feedback_parts.append("NOAA_APT module contains all 3 NOAA satellites")
            if len(sat_list) == 3:
                score += 6
                feedback_parts.append("Module cleanly isolated (no extra satellites)")
            else:
                feedback_parts.append(f"Module contains {len(sat_list)} satellites (expected 3)")
        else:
            feedback_parts.append("NOAA_APT module missing some required NOAA satellites")
    else:
        feedback_parts.append("NOAA_APT module NOT FOUND")

    # === Criterion 3 & 4: Transponders (35 pts) ===
    def check_trsp(name, key_exists, key_down, key_mode, expected_freq):
        trsp_score = 0
        if result.get(key_exists, False):
            down_val = result.get(key_down, '')
            if _close_enough(down_val, expected_freq, freq_tolerance):
                trsp_score += 10
            elif _close_enough(down_val, expected_freq / 1e6, 0.01):
                # Fallback if agent used MHz instead of Hz despite instructions
                trsp_score += 5
                feedback_parts.append(f"Warning: {name} frequency entered in MHz, not Hz")
            else:
                feedback_parts.append(f"{name} transponder has incorrect frequency: {down_val}")
        return trsp_score

    score += check_trsp("NOAA 15", "trsp_15_exists", "trsp_15_down", "trsp_15_mode", noaa15_freq)
    score += check_trsp("NOAA 18", "trsp_18_exists", "trsp_18_down", "trsp_18_mode", noaa18_freq)
    score += check_trsp("NOAA 19", "trsp_19_exists", "trsp_19_down", "trsp_19_mode", noaa19_freq)

    # Check Modes
    modes = [result.get("trsp_15_mode", "").upper(), result.get("trsp_18_mode", "").upper(), result.get("trsp_19_mode", "").upper()]
    if expected_mode in modes:
        score += 5
        feedback_parts.append(f"MODE={expected_mode} correctly configured")

    # === Criterion 5: Wallops Ground Station (20 pts) ===
    if result.get('wallops_exists', False):
        score += 5
        lat_ok = _close_enough(result.get('wallops_lat', ''), wallops_lat, 0.1)
        lon_ok = _close_enough(result.get('wallops_lon', ''), wallops_lon, 0.1)
        alt_ok = _close_enough(result.get('wallops_alt', ''), wallops_alt, 5)
        
        if lat_ok: score += 5
        if lon_ok: score += 5
        if alt_ok: score += 5
        
        if lat_ok and lon_ok and alt_ok:
            feedback_parts.append("Wallops ground station correctly configured")
        else:
            feedback_parts.append(f"Wallops coordinates imprecise (Lat: {lat_ok}, Lon: {lon_ok}, Alt: {alt_ok})")
    else:
        feedback_parts.append("Wallops ground station NOT FOUND")

    # === Criterion 6: Ground Tracks (5 pts) ===
    track_num = result.get('noaa_track_num', '').strip()
    if track_num == expected_track_count:
        score += 5
        feedback_parts.append("Ground tracks configured to 3")
    else:
        feedback_parts.append(f"Ground tracks not set to {expected_track_count} (found: {track_num})")

    # === Criterion 7: Anti-Gaming & Preservation (10 pts) ===
    if result.get('amateur_preserved', False) and result.get('pittsburgh_preserved', False):
        score += 5
    else:
        feedback_parts.append("Warning: Existing GPredict configuration was tampered with")

    # Check timestamps: ensure files were created/modified during the task
    mtimes = [
        result.get('noaa_mod_mtime', 0),
        result.get('wallops_mtime', 0),
        result.get('trsp_15_mtime', 0)
    ]
    if any(m > task_start for m in mtimes if m > 0):
        score += 5
    elif any(m > 0 for m in mtimes):
        feedback_parts.append("Warning: Files appear to pre-date the task start time (Gaming attempt?)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }