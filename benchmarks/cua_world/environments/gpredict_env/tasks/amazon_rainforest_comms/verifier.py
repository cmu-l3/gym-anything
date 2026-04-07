#!/usr/bin/env python3
"""
Verifier for amazon_rainforest_comms task.

Task:
  1. Add Tiputini QTH (-0.6383, -76.1492, 220)
  2. Add Manaus QTH (-3.1131, -60.0253, 92)
  3. Create Bio_Relay module with 25544, 27607, 43017, 43137
  4. Create Trop_Weather module with 41866, 33591, 37849
  5. Set default QTH to Tiputini
  6. Delete Pittsburgh ground station

Scoring (100 points, pass >= 70):
  - Tiputini ground station correct: 15 pts
  - Manaus ground station correct: 15 pts
  - Bio_Relay module (5 pts per satellite): 20 pts
  - Trop_Weather module (5 pts per satellite): 15 pts
  - Default QTH changed to Tiputini: 15 pts
  - Pittsburgh deleted: 20 pts

Also includes VLM Trajectory Verification check to ensure GPredict was actually used.
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

def verify_amazon_rainforest_comms(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/amazon_rainforest_comms_result.json", temp_path)
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

    # --- Criterion 1: Tiputini Station (15 pts) ---
    if result.get('tiputini_exists'):
        lat_ok = _close_enough(result.get('tiputini_lat', ''), metadata.get('tiputini_lat', -0.6383), 0.1)
        lon_ok = _close_enough(result.get('tiputini_lon', ''), metadata.get('tiputini_lon', -76.1492), 0.1)
        alt_ok = _close_enough(result.get('tiputini_alt', ''), metadata.get('tiputini_alt', 220), 50)

        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Tiputini QTH correct")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append("Tiputini QTH coordinates OK, altitude wrong")
        else:
            score += 5
            feedback_parts.append(f"Tiputini QTH exists but coordinates inaccurate (Lat:{result.get('tiputini_lat')} Lon:{result.get('tiputini_lon')})")
    else:
        feedback_parts.append("Tiputini QTH NOT FOUND")

    # --- Criterion 2: Manaus Station (15 pts) ---
    if result.get('manaus_exists'):
        lat_ok = _close_enough(result.get('manaus_lat', ''), metadata.get('manaus_lat', -3.1131), 0.1)
        lon_ok = _close_enough(result.get('manaus_lon', ''), metadata.get('manaus_lon', -60.0253), 0.1)
        alt_ok = _close_enough(result.get('manaus_alt', ''), metadata.get('manaus_alt', 92), 30)

        if lat_ok and lon_ok and alt_ok:
            score += 15
            feedback_parts.append("Manaus QTH correct")
        elif lat_ok and lon_ok:
            score += 10
            feedback_parts.append("Manaus QTH coordinates OK, altitude wrong")
        else:
            score += 5
            feedback_parts.append(f"Manaus QTH exists but coordinates inaccurate (Lat:{result.get('manaus_lat')} Lon:{result.get('manaus_lon')})")
    else:
        feedback_parts.append("Manaus QTH NOT FOUND")

    # --- Criterion 3: Bio_Relay Module (20 pts) ---
    if result.get('bio_relay_exists'):
        if not result.get('bio_relay_created_during_task', False):
            feedback_parts.append("Bio_Relay module existed before task - potential gaming")
        else:
            sats_str = result.get('bio_relay_satellites', '')
            bio_sats = metadata.get('bio_relay_sats', [25544, 27607, 43017, 43137])
            found_count = 0
            for sat in bio_sats:
                if str(sat) in sats_str:
                    found_count += 1
                    score += 5
            feedback_parts.append(f"Bio_Relay module has {found_count}/{len(bio_sats)} required satellites")
    else:
        feedback_parts.append("Bio_Relay module NOT FOUND")

    # --- Criterion 4: Trop_Weather Module (15 pts) ---
    if result.get('trop_weather_exists'):
        if not result.get('trop_weather_created_during_task', False):
            feedback_parts.append("Trop_Weather module existed before task - potential gaming")
        else:
            sats_str = result.get('trop_weather_satellites', '')
            trop_sats = metadata.get('trop_weather_sats', [41866, 33591, 37849])
            found_count = 0
            for sat in trop_sats:
                if str(sat) in sats_str:
                    found_count += 1
                    score += 5
            feedback_parts.append(f"Trop_Weather module has {found_count}/{len(trop_sats)} required satellites")
    else:
        feedback_parts.append("Trop_Weather module NOT FOUND")

    # --- Criterion 5: Default QTH Changed (15 pts) ---
    default_qth = result.get('default_qth', '')
    expected_default = metadata.get('expected_default_qth', 'Tiputini')
    if expected_default.lower() in default_qth.lower():
        score += 15
        feedback_parts.append(f"Default QTH updated to {expected_default}")
    else:
        feedback_parts.append(f"Default QTH is '{default_qth}' (expected {expected_default})")

    # --- Criterion 6: Pittsburgh Deleted (20 pts) ---
    if not result.get('pittsburgh_exists', True):
        score += 20
        feedback_parts.append("Pittsburgh QTH successfully deleted")
    else:
        feedback_parts.append("Pittsburgh QTH still exists (should be deleted)")

    # --- VLM Verification ---
    vlm_feedback = ""
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        if frames and final:
            vlm_prompt = "Did the agent actively use the GPredict interface to configure ground stations and tracking modules? Respond strictly in JSON: {'ui_used': true/false}"
            vlm_res = query_vlm(images=frames + [final], prompt=vlm_prompt)
            if vlm_res and isinstance(vlm_res.get('parsed'), dict):
                if vlm_res['parsed'].get('ui_used'):
                    vlm_feedback = "VLM: GPredict UI usage verified."
                else:
                    vlm_feedback = "VLM WARNING: UI usage not detected."
            else:
                vlm_feedback = "VLM check failed to parse."
    except ImportError:
        vlm_feedback = "VLM unavailable for trajectory check."
    except Exception as e:
        vlm_feedback = f"VLM check error: {e}"
        
    if vlm_feedback:
        feedback_parts.append(vlm_feedback)

    # Key criteria: Must have created Tiputini and at least one module
    key_criteria_met = result.get('tiputini_exists', False) and (result.get('bio_relay_exists', False) or result.get('trop_weather_exists', False))
    
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }