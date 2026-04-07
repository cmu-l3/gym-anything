#!/usr/bin/env python3
"""
Verifier for multicampus_qth_binding task.

Verifies:
1. 3 separate Ground Stations (QTH) created with correct coordinates.
2. 3 separate Tracking Modules (MOD) created containing 4 required satellites.
3. Each Tracking Module bound to its corresponding Ground Station (QTHFILE check).
4. System default QTH set to CU_Boulder.
5. UTC time enabled.
6. Anti-gaming: Files must have been created/modified after task started.
"""

import json
import os
import tempfile
import logging

# Fallback import for optional VLM integration
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logger = logging.getLogger(__name__)


def _close_enough(value_str, expected_float, tolerance=0.1):
    """Check if a string-encoded float is within tolerance of expected."""
    try:
        val = float(value_str)
        return abs(val - expected_float) <= tolerance
    except (ValueError, TypeError):
        return False

def _check_satellites(sat_str, required_ids):
    """Check if all required satellite IDs are in the semicolon-delimited string."""
    if not sat_str:
        return False, []
    
    # Extract all numbers from the string
    import re
    found_sats = re.findall(r'\d+', sat_str)
    
    missing = []
    for req in required_ids:
        # Check stripping leading zeros
        if str(req) not in found_sats and str(int(req)) not in found_sats:
            missing.append(req)
            
    return len(missing) == 0, missing

def verify_multicampus_qth_binding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    expected_stations = metadata.get('stations', {})
    required_sats = metadata.get('required_satellites', [25544, 27607, 40967, 43770])

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        copy_from_env("/tmp/multicampus_qth_binding_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result file: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    score = 0
    feedback = []
    task_start = result.get('task_start_time', 0)

    # Dictionary of components to check
    campuses = ['cu_boulder', 'csu_fortcollins', 'mines_golden']
    
    # Check 1: QTH Files (8 pts each = 24 pts)
    for campus in campuses:
        qth_data = result.get(f'qth_{campus}', {})
        exp = expected_stations.get(campus, {})
        
        if not qth_data.get('exists'):
            feedback.append(f"{campus} QTH: NOT FOUND")
            continue
            
        # Anti-gaming check
        if qth_data.get('mtime', 0) < task_start and task_start > 0:
            feedback.append(f"{campus} QTH: Existed before task started (Anti-gaming)")
            continue
            
        lat_ok = _close_enough(qth_data.get('lat', ''), exp.get('lat', 0), 0.05)
        lon_ok = _close_enough(qth_data.get('lon', ''), exp.get('lon', 0), 0.05)
        alt_ok = _close_enough(qth_data.get('alt', ''), exp.get('alt', 0), 20)
        
        if lat_ok and lon_ok and alt_ok:
            score += 8
            feedback.append(f"{campus} QTH: Correct")
        else:
            feedback.append(f"{campus} QTH: Incorrect coordinates")

    # Check 2: MOD Files & Satellites (10 pts each = 30 pts)
    for campus in campuses:
        mod_data = result.get(f'mod_{campus}', {})
        
        if not mod_data.get('exists'):
            feedback.append(f"{campus} Module: NOT FOUND")
            continue
            
        # Anti-gaming check
        if mod_data.get('mtime', 0) < task_start and task_start > 0:
            feedback.append(f"{campus} Module: Existed before task started (Anti-gaming)")
            continue
            
        sats_str = mod_data.get('satellites', '')
        has_all, missing = _check_satellites(sats_str, required_sats)
        
        if has_all:
            score += 10
            feedback.append(f"{campus} Module: All satellites present")
        else:
            feedback.append(f"{campus} Module: Missing sats {missing}")

    # Check 3: QTH Bindings (10 pts each = 30 pts)
    # This is the core new behavior being tested
    for campus in campuses:
        mod_data = result.get(f'mod_{campus}', {})
        qth_data = result.get(f'qth_{campus}', {})
        
        if not mod_data.get('exists'):
            continue
            
        bound_qth = mod_data.get('qthfile', '').lower()
        expected_qth_name = qth_data.get('filename', f"{campus}.qth").lower()
        
        # Make sure it points specifically to this campus's QTH file
        if bound_qth and (bound_qth == expected_qth_name or f"{campus}.qth" in bound_qth):
            score += 10
            feedback.append(f"{campus} Binding: Correct ({bound_qth})")
        else:
            feedback.append(f"{campus} Binding: Failed. Bound to '{bound_qth}', expected '{expected_qth_name}'")

    # Check 4: System Default QTH (8 pts)
    default_qth = result.get('cfg_default_qth', '').lower()
    if 'cu_boulder' in default_qth:
        score += 8
        feedback.append("Default QTH: Correct (CU_Boulder)")
    else:
        feedback.append(f"Default QTH: Incorrect ('{default_qth}')")

    # Check 5: UTC Time (8 pts)
    if result.get('cfg_utc_enabled', False):
        score += 8
        feedback.append("UTC Time: Enabled")
    else:
        feedback.append("UTC Time: Not enabled")

    # VLM Verification Fallback/Check
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            if frames:
                prompt = (
                    "Look at these screenshots from a satellite tracking application. "
                    "Did the user open dialog boxes to edit ground stations, module properties, or preferences? "
                    "Respond with JSON: {'user_navigated_ui': true/false}"
                )
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                if vlm_resp.get("success") and vlm_resp.get("parsed", {}).get("user_navigated_ui"):
                    feedback.append("VLM: UI navigation verified")
                else:
                    feedback.append("VLM: Could not verify UI interaction")
        except Exception as e:
            logger.warning(f"VLM verification skipped or failed: {e}")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }