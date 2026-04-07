#!/usr/bin/env python3
"""
Verifier for dsn_multisite_visibility task.

Task: Configure GPredict with three distributed tracking modules assigned to respective ground stations.
  1. Create 3 DSN Ground Stations: Goldstone (US), Madrid (Spain), Canberra (Australia)
  2. Create 3 Modules: DSN_Goldstone, DSN_Madrid, DSN_Canberra
  3. All 3 modules track the same 4 satellites: 25544, 48274, 33591, 7530
  4. CRITICAL: Each module's QTHFILE property must point to its respective ground station.
  5. Enable UTC Time.

Scoring (100 points, pass >= 70):
  - QTH Coordinates: 10 pts per station = 30 pts
  - Module Satellites: 10 pts per module = 30 pts
  - Module QTHFILE Binding: 10 pts per module = 30 pts
  - UTC Time Enabled: 10 pts
  - Anti-gaming: Output must be created AFTER task start.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    try:
        if not value_str: return False
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False


def _verify_sats(sat_str, required_ids):
    """Check if the required NORAD IDs are in the semicolon-separated SATELLITES string."""
    if not sat_str:
        return 0, []
    
    # Extract just the IDs (GPredict uses format: ID;flag;flag,ID;flag;flag...)
    found_ids = []
    # Simple search since the IDs are unique and distinct
    for req_id in required_ids:
        if str(req_id) in sat_str:
            found_ids.append(req_id)
            
    return len(found_ids), found_ids


def verify_dsn_multisite_visibility(traj, env_info, task_info):
    """
    Verify the DSN multisite visibility module and QTH assignments.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    
    required_sats = metadata.get('required_satellites', [25544, 48274, 33591, 7530])
    pts_per_sat = 10.0 / len(required_sats)

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/dsn_multisite_visibility_result.json", temp_path)
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

    # Validate Ground Stations (30 points)
    qth_checks = [
        ('Goldstone', 'goldstone', metadata.get('goldstone', {})),
        ('Madrid', 'madrid', metadata.get('madrid', {})),
        ('Canberra', 'canberra', metadata.get('canberra', {}))
    ]
    
    for display_name, prefix, expected in qth_checks:
        qth_file = result.get(f'{prefix}_qth_file', '')
        if not qth_file:
            feedback_parts.append(f"{display_name} ground station: NOT FOUND")
            continue
            
        mtime = result.get(f'{prefix}_mtime', 0)
        if mtime < task_start:
            feedback_parts.append(f"{display_name} ground station: Pre-existing file (gaming detected)")
            continue

        lat_ok = _close_enough(result.get(f'{prefix}_lat'), expected.get('lat', 0), 0.1)
        lon_ok = _close_enough(result.get(f'{prefix}_lon'), expected.get('lon', 0), 0.1)
        alt_ok = _close_enough(result.get(f'{prefix}_alt'), expected.get('alt', 0), 50)

        if lat_ok and lon_ok and alt_ok:
            score += 10
            feedback_parts.append(f"{display_name} QTH: Correct (10/10 pts)")
        elif lat_ok and lon_ok:
            score += 7
            feedback_parts.append(f"{display_name} QTH: Coords OK but Alt wrong (7/10 pts)")
        else:
            feedback_parts.append(f"{display_name} QTH: Found but Coords wrong")

    # Validate Modules and Satellites (30 points)
    mod_checks = [
        ('DSN_Goldstone', 'mod_goldstone'),
        ('DSN_Madrid', 'mod_madrid'),
        ('DSN_Canberra', 'mod_canberra')
    ]
    
    for display_name, prefix in mod_checks:
        mod_file = result.get(f'{prefix}_file', '')
        if not mod_file:
            feedback_parts.append(f"{display_name} module: NOT FOUND")
            continue
            
        mtime = result.get(f'{prefix}_mtime', 0)
        if mtime < task_start:
            feedback_parts.append(f"{display_name} module: Pre-existing file (gaming detected)")
            continue
            
        sat_str = result.get(f'{prefix}_sats', '')
        found_count, found_ids = _verify_sats(sat_str, required_sats)
        
        mod_score = int(found_count * pts_per_sat)
        score += mod_score
        
        if found_count == len(required_sats):
            feedback_parts.append(f"{display_name} sats: All required satellites present ({mod_score}/10 pts)")
        else:
            feedback_parts.append(f"{display_name} sats: {found_count}/{len(required_sats)} sats present ({mod_score}/10 pts)")

    # Validate Module-to-QTH Bindings (30 points)
    binding_checks = [
        ('Goldstone binding', 'mod_goldstone_qth', 'goldstone_qth_file'),
        ('Madrid binding', 'mod_madrid_qth', 'madrid_qth_file'),
        ('Canberra binding', 'mod_canberra_qth', 'canberra_qth_file')
    ]
    
    for display_name, mod_qth_key, actual_qth_key in binding_checks:
        mod_qth_val = result.get(mod_qth_key, '').strip()
        actual_qth_val = result.get(actual_qth_key, '').strip()
        
        if mod_qth_val and actual_qth_val and mod_qth_val == actual_qth_val:
            score += 10
            feedback_parts.append(f"{display_name}: Correct ({actual_qth_val}) (10/10 pts)")
        elif mod_qth_val:
            feedback_parts.append(f"{display_name}: Incorrect (points to '{mod_qth_val}', expected '{actual_qth_val}')")
        else:
            feedback_parts.append(f"{display_name}: No QTH assigned")

    # Validate UTC Time (10 points)
    # Check boolean flag and raw cfg fallback
    utc_ok = result.get('utc_time_enabled', False)
    cfg_content = result.get('gpredict_cfg_content', '')
    
    if not utc_ok and cfg_content:
        # Fallback check for various UTC/Time forms
        if re.search(r'utc\s*=\s*1', cfg_content, re.IGNORECASE) or \
           re.search(r'use_local_time\s*=\s*0', cfg_content, re.IGNORECASE) or \
           re.search(r'time_format\s*=\s*[12]', cfg_content, re.IGNORECASE):
            utc_ok = True

    if utc_ok:
        score += 10
        feedback_parts.append("UTC Time: Enabled (10/10 pts)")
    else:
        feedback_parts.append("UTC Time: Not enabled")

    # Determine final result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }