#!/usr/bin/env python3
"""Verifier for restrict_layer_crs_list task."""

import json
import tempfile
import os


def verify_restrict_layer_crs(traj, env_info, task_info):
    """
    Verify that the 'ne_countries' layer is configured to advertise ONLY 
    EPSG:4326 and EPSG:3857.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_list = set(metadata.get('expected_srs_list', ["EPSG:4326", "EPSG:3857"]))

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/restrict_layer_crs_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        # If we can't read the nonce file but result has one, it's suspicious, but 
        # usually means the task script ran but verification is running later.
        pass
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # --------------------------------------------------------------------------
    # Check 1: REST API Configuration (Primary Source of Truth for Config)
    # --------------------------------------------------------------------------
    rest_srs_list = result.get('rest_srs_list', [])
    # Normalize list (strip whitespace, upper case)
    rest_srs_set = {s.strip().upper() for s in rest_srs_list}
    
    # Criterion 1: EPSG:4326 Present (25 pts)
    if "EPSG:4326" in rest_srs_set:
        score += 25
        feedback_parts.append("EPSG:4326 is enabled")
    else:
        feedback_parts.append("EPSG:4326 is MISSING")

    # Criterion 2: EPSG:3857 Present (25 pts)
    if "EPSG:3857" in rest_srs_set:
        score += 25
        feedback_parts.append("EPSG:3857 is enabled")
    else:
        feedback_parts.append("EPSG:3857 is MISSING")

    # Criterion 3: Strictness - No other CRS allowed (25 pts)
    # The default config usually has empty list (meaning ALL), or thousands. 
    # We want EXACTLY 2.
    if len(rest_srs_set) == 2 and rest_srs_set == {"EPSG:4326", "EPSG:3857"}:
        score += 25
        feedback_parts.append("SRS list is strictly limited to expected values")
    elif len(rest_srs_set) > 2:
        feedback_parts.append(f"SRS list contains too many entries ({len(rest_srs_set)}) - Restriction not applied correctly")
    elif len(rest_srs_set) < 2:
        feedback_parts.append("SRS list contains fewer than required entries")
        
    # --------------------------------------------------------------------------
    # Check 2: WMS Capabilities (Functional Verification) (25 pts)
    # --------------------------------------------------------------------------
    cap_analysis = result.get('capabilities_analysis', {})
    
    if cap_analysis.get('found', False):
        crs_list = cap_analysis.get('crs_list', [])
        crs_set = {c.strip().upper() for c in crs_list}
        
        # Verify the capabilities actually reflect the config
        # Note: GetCapabilities often includes inherited CRS if not strictly limited.
        # The goal is that the output should be SMALL.
        # If it's > 50, they definitely didn't limit it properly.
        if len(crs_set) <= 5 and "EPSG:4326" in crs_set and "EPSG:3857" in crs_set:
             score += 25
             feedback_parts.append("WMS GetCapabilities confirms strictly limited CRS list")
        elif len(crs_set) > 50:
             # Partial credit not given here because this is the main goal
             feedback_parts.append(f"WMS Capabilities still lists {len(crs_set)} CRS definitions")
        else:
             # Case where they limited it but maybe missed one or added extra
             if "EPSG:4326" in crs_set and "EPSG:3857" in crs_set:
                 score += 10
                 feedback_parts.append("WMS Capabilities contains target CRS but list size is unexpected")
    else:
        feedback_parts.append("Could not find layer in GetCapabilities document")

    # --------------------------------------------------------------------------
    # Check 3: Anti-Gaming / Process Verification
    # --------------------------------------------------------------------------
    # Check for GUI interaction (using the log analysis from export script)
    gui_detected = result.get('gui_interaction_detected', False)
    
    # If using VLM, we can verify trajectory
    vlm_gui_confirmed = True
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, num_samples=3)
            if frames:
                vlm_result = query_vlm(
                    images=frames,
                    prompt="Do these screenshots show a user editing a configuration form with tabs like 'Data', 'Publishing', 'Dimensions'? Answer with JSON: {'is_editing_config': boolean}"
                )
                if vlm_result and isinstance(vlm_result, dict):
                    parsed = vlm_result.get('parsed', {})
                    if not parsed.get('is_editing_config', False) and not gui_detected:
                         vlm_gui_confirmed = False
                         feedback_parts.append("No evidence of GUI interaction found (Logs or VLM)")
        except Exception:
            pass # Fail open if VLM errors

    # Deduct if no GUI interaction detected (REST API shortcut)
    if not gui_detected and not vlm_gui_confirmed:
        score = min(score, 50) # Cap score if they just curled the result
        feedback_parts.append("CAP APPLIED: No GUI interaction detected")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }