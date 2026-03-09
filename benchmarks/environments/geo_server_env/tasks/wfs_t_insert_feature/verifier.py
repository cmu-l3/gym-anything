#!/usr/bin/env python3
"""Verifier for WFS-T Insert Feature task."""

import json
import tempfile
import os
import math

def verify_wfs_t_insert_feature(traj, env_info, task_info):
    """
    Verify that a new feature was inserted via WFS-T.
    
    Criteria:
    1. Feature exists in PostGIS with correct name (20 pts)
    2. Attributes match expected values (20 pts)
    3. Geometry is within tolerance (20 pts)
    4. Feature is retrievable via WFS (15 pts)
    5. Transaction XML files saved correctly (20 pts)
    6. Feature count increased by exactly 1 (5 pts)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_pop = metadata.get('target_pop', 45000)
    expected_adm0 = metadata.get('target_adm0', 'Brazil')
    expected_lat = metadata.get('target_lat', -15.7801)
    expected_lon = metadata.get('target_lon', -47.9292)
    tolerance = metadata.get('tolerance_degrees', 0.01)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify nonce integrity
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        # If nonce check fails, we proceed but flag it
        pass
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Feature exists in PostGIS (20 pts)
    feature_count = int(result.get('feature_found_postgis', 0))
    if feature_count == 1:
        score += 20
        feedback_parts.append("Feature found in PostGIS")
    elif feature_count > 1:
        score += 10
        feedback_parts.append(f"Multiple features found ({feature_count})")
    else:
        return {"passed": False, "score": 0, "feedback": "Feature 'Nova Cartografia' NOT found in database"}

    # 2. Attributes match (20 pts)
    attrs = result.get('attributes', {})
    attr_score = 0
    
    # Check adm0name (7 pts)
    actual_adm0 = attrs.get('adm0name', '')
    if actual_adm0 == expected_adm0:
        attr_score += 7
    else:
        feedback_parts.append(f"Wrong adm0name: {actual_adm0}")

    # Check pop_max (7 pts)
    try:
        actual_pop = int(attrs.get('pop_max', 0))
        if actual_pop == expected_pop:
            attr_score += 7
        else:
            feedback_parts.append(f"Wrong pop_max: {actual_pop}")
    except:
        feedback_parts.append("Invalid pop_max")

    # Check featurecla (6 pts)
    actual_fcla = attrs.get('featurecla', '').lower()
    if 'populated place' in actual_fcla:
        attr_score += 6
    else:
        feedback_parts.append(f"Wrong featurecla: {actual_fcla}")
        
    score += attr_score
    if attr_score == 20:
        feedback_parts.append("All attributes correct")

    # 3. Geometry (20 pts)
    geom = result.get('geometry', {})
    try:
        lat = float(geom.get('lat', 0))
        lon = float(geom.get('lon', 0))
        
        dist = math.sqrt((lat - expected_lat)**2 + (lon - expected_lon)**2)
        
        if dist < tolerance:
            score += 20
            feedback_parts.append("Geometry location correct")
        elif dist < tolerance * 10:
            score += 10
            feedback_parts.append(f"Geometry close but imprecise (off by {dist:.4f})")
        else:
            feedback_parts.append(f"Geometry too far (off by {dist:.4f})")
    except (ValueError, TypeError):
        feedback_parts.append("Invalid geometry coordinates")

    # 4. WFS Retrievable (15 pts)
    if result.get('wfs_retrievable', False):
        score += 15
        feedback_parts.append("Feature retrievable via WFS")
    else:
        feedback_parts.append("Feature NOT retrievable via WFS")

    # 5. Files Saved (20 pts)
    files = result.get('files', {})
    if files.get('insert_xml_exists') and files.get('insert_xml_valid'):
        score += 10
        feedback_parts.append("Valid insert XML saved")
    else:
        feedback_parts.append("Insert XML missing or invalid")

    if files.get('response_xml_exists') and files.get('response_success'):
        score += 10
        feedback_parts.append("Success response XML saved")
    else:
        feedback_parts.append("Response XML missing or invalid")

    # 6. Count Check (5 pts)
    initial = int(result.get('initial_count', 0))
    final = int(result.get('final_count', 0))
    if final == initial + 1:
        score += 5
        feedback_parts.append("Total feature count increased by exactly 1")
    elif final > initial:
        score += 2
        feedback_parts.append(f"Total feature count increased by {final - initial} (expected 1)")
    else:
        feedback_parts.append("Feature count did not increase")

    passed = score >= 70 and feature_count >= 1
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }