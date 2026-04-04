#!/usr/bin/env python3
"""Verifier for configure_wfs_limits_precision task."""

import json
import tempfile
import os

def verify_configure_wfs_limits_precision(traj, env_info, task_info):
    """
    Verify GeoServer WFS limits and precision settings.
    
    Criteria:
    1. 'ne:ne_populated_places' returns exactly 50 features (40 pts)
    2. WFS output coordinate precision is max 3 decimal places (30 pts)
    3. 'ne:ne_countries' is NOT limited to 50 features (Scope check) (20 pts)
    4. Configuration settings visible in REST API (10 pts)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_limit = metadata.get('expected_feature_limit', 50)
    expected_precision = metadata.get('expected_precision', 3)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_wfs_limits_precision_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify nonce
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        # Fail if result exists but nonce file missing (gaming attempt)
        if result: 
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce missing"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    data = result.get("verification_data", {})
    error = data.get("error")
    if error:
        return {"passed": False, "score": 0, "feedback": f"Verification script error: {error}"}

    score = 0
    feedback_parts = []

    # 1. Feature Limit Check (40 pts)
    pop_count = data.get("pop_places_count", 0)
    if pop_count == expected_limit:
        score += 40
        feedback_parts.append(f"Correct feature limit: {pop_count}")
    else:
        feedback_parts.append(f"Incorrect feature limit: got {pop_count}, expected {expected_limit}")

    # 2. Precision Check (30 pts)
    # The script calculates max decimals found in output
    measured_precision = data.get("pop_places_precision", -1)
    
    # We accept precision <= expected (GeoServer drops trailing zeros)
    # If standard is 15 (double), we expect > 3. If configured to 3, we expect <= 3.
    if 0 <= measured_precision <= expected_precision:
        score += 30
        feedback_parts.append(f"Precision correct: max {measured_precision} decimals")
    else:
        feedback_parts.append(f"Precision incorrect: found {measured_precision} decimals (expected <= {expected_precision})")

    # 3. Scope Check (20 pts)
    # Countries should NOT be capped at 50. Natural Earth countries is ~177 features.
    countries_count = data.get("countries_count", 0)
    if countries_count > expected_limit:
        score += 20
        feedback_parts.append(f"Scope correct: Countries layer not limited ({countries_count} features)")
    else:
        feedback_parts.append(f"Scope error: Countries layer seems limited ({countries_count} features)")

    # 4. Config Check (10 pts)
    # Check if REST API reflects the settings
    global_prec = data.get("global_precision_setting")
    layer_limit = data.get("layer_limit_setting")
    
    config_ok = False
    if global_prec == expected_precision and layer_limit == expected_limit:
        score += 10
        config_ok = True
        feedback_parts.append("REST configuration matches")
    else:
        feedback_parts.append(f"REST config mismatch (Global Prec: {global_prec}, Layer Limit: {layer_limit})")

    # VLM / GUI check
    gui_detected = result.get("gui_interaction_detected", False)
    if not gui_detected and score > 0:
        feedback_parts.append("WARNING: No GUI interaction detected via logs")

    passed = score >= 70 and (pop_count == expected_limit) and (0 <= measured_precision <= expected_precision)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }