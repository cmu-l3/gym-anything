#!/usr/bin/env python3
"""
Verifier for saa_radiation_pass_analysis task.

Task: Configure GPredict for scientific radiation pass analysis:
  1. Create Tristan_da_Cunha ground station (37.1052 S, 12.2777 W, 20m)
  2. Create SAA_Targets module with METOP-B (38771), METOP-C (43689), SUOMI NPP (37849), NOAA 19 (33591)
  3. Bind the SAA_Targets module to use the Tristan_da_Cunha QTH
  4. Adjust Global Preferences:
     - Number of passes to predict = 50
     - Map -> Show grid = Enabled
     - Map -> Show terminator = Enabled

Scoring (100 points, pass >= 70):
  - Tristan_da_Cunha QTH exists & correct: 15 pts
  - SAA_Targets module exists: 15 pts
  - Satellites Correct (5 pts each × 4): 20 pts
  - QTH Binding Correct (module points to Tristan QTH): 20 pts
  - 50 passes configured: 10 pts
  - Grid enabled: 10 pts
  - Terminator enabled: 10 pts
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


def verify_saa_radiation_pass_analysis(traj, env_info, task_info):
    """
    Verify the South Atlantic Anomaly pass analysis configuration.
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
            copy_from_env("/tmp/saa_radiation_pass_analysis_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0,
                    "feedback": f"Could not copy result file: {e}. Was the task run?"}

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

    # --- 1. Tristan da Cunha QTH (15 pts) ---
    tristan_qth_filename = result.get('tristan_qth_filename', '')
    if result.get('tristan_exists'):
        lat_ok = _close_enough(result.get('tristan_lat', ''), metadata.get('tristan_lat', -37.1052), 0.1)
        lon_ok = _close_enough(result.get('tristan_lon', ''), metadata.get('tristan_lon', -12.2777), 0.1)
        
        if lat_ok and lon_ok:
            score += 15
            feedback_parts.append("Tristan da Cunha QTH: Correct coordinates (S/W properly applied)")
        else:
            score += 5
            feedback_parts.append(f"Tristan da Cunha QTH exists but coords are off (lat={result.get('tristan_lat')}, lon={result.get('tristan_lon')})")
    else:
        feedback_parts.append("Tristan da Cunha QTH: NOT FOUND (missing or incorrect S/W quadrant)")

    # --- 2. SAA_Targets Module exists (15 pts) ---
    if result.get('saa_exists'):
        score += 15
        feedback_parts.append(f"SAA_Targets module found ({result.get('saa_mod_name')}.mod)")
    else:
        feedback_parts.append("SAA_Targets module: NOT FOUND")

    # --- 3. Satellites Correct (20 pts total, 5 each) ---
    if result.get('saa_exists'):
        sats_found = []
        sats_missing = []
        
        checks = [
            ('saa_has_metopb', 38771, 'METOP-B'),
            ('saa_has_metopc', 43689, 'METOP-C'),
            ('saa_has_suomi', 37849, 'SUOMI NPP'),
            ('saa_has_noaa19', 33591, 'NOAA 19')
        ]
        
        for key, norad, name in checks:
            if result.get(key, False):
                score += 5
                sats_found.append(f"{name} ({norad})")
            else:
                sats_missing.append(f"{name} ({norad})")
                
        if sats_found:
            feedback_parts.append(f"Satellites included: {', '.join(sats_found)}")
        if sats_missing:
            feedback_parts.append(f"Satellites MISSING: {', '.join(sats_missing)}")

    # --- 4. QTH Binding Correct (20 pts) ---
    if result.get('saa_exists') and result.get('tristan_exists'):
        module_qth = result.get('saa_qth_binding', '').strip()
        expected_qth = tristan_qth_filename.strip()
        
        if module_qth and expected_qth and module_qth == expected_qth:
            score += 20
            feedback_parts.append(f"QTH Binding: Correctly assigned to {expected_qth}")
        else:
            feedback_parts.append(f"QTH Binding: Incorrect (is '{module_qth}', expected '{expected_qth}')")
    elif result.get('saa_exists'):
        feedback_parts.append("QTH Binding: Could not verify because Tristan QTH is missing")

    # --- 5. 50 Passes Configured (10 pts) ---
    try:
        pred_passes = int(result.get('pred_passes', 10))
    except (ValueError, TypeError):
        pred_passes = 10
        
    if pred_passes >= metadata.get('required_passes', 50):
        score += 10
        feedback_parts.append(f"Prediction limit updated: {pred_passes} passes")
    else:
        feedback_parts.append(f"Prediction limit: {pred_passes} (expected 50)")

    # --- 6. Map Grid Enabled (10 pts) ---
    if result.get('map_draw_grid'):
        score += 10
        feedback_parts.append("Map Grid: Enabled")
    else:
        feedback_parts.append("Map Grid: Not enabled")

    # --- 7. Map Terminator Enabled (10 pts) ---
    if result.get('map_draw_term'):
        score += 10
        feedback_parts.append("Map Terminator: Enabled")
    else:
        feedback_parts.append("Map Terminator: Not enabled")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }