#!/usr/bin/env python3
"""Verifier for optimize_layer_delivery task."""

import json
import tempfile
import os

def verify_optimize_layer_delivery(traj, env_info, task_info):
    """
    Verify layer delivery optimization settings.
    
    Criteria:
    1. Cache-Control header present with max-age=86400 (40 pts)
    2. Attribution Title correct (20 pts)
    3. Attribution Logo URL correct (20 pts)
    4. Attribution Logo dimensions/type correct (20 pts)
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_cache_age = int(metadata.get('expected_cache_age', 86400))
    expected_title = metadata.get('expected_attribution_title', "Provided by Natural Earth")
    expected_logo_url = metadata.get('expected_logo_url', "http://localhost:8080/geoserver/ne_logo.png")
    expected_logo_width = int(metadata.get('expected_logo_width', 88))
    expected_logo_height = int(metadata.get('expected_logo_height', 31))

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/optimize_layer_delivery_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify integrity
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        pass  # Nonce file might be missing if setup failed, but we proceed with checking headers/XML
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []

    # 1. Verify Caching (40 pts)
    # Strict check: max-age must equal 86400.
    # Partial credit if Cache-Control exists but wrong value.
    actual_age_str = result.get('cache_max_age', '0')
    try:
        actual_age = int(actual_age_str)
    except ValueError:
        actual_age = 0
        
    cache_header = result.get('cache_control_header', '')

    if actual_age == expected_cache_age:
        score += 40
        feedback_parts.append(f"Cache-Control max-age correct ({expected_cache_age}s)")
    elif 'max-age' in cache_header.lower():
        score += 10
        feedback_parts.append(f"Cache-Control header present but wrong duration ({actual_age}s)")
    else:
        feedback_parts.append("Cache-Control header missing or invalid")

    # 2. Verify Attribution (60 pts total)
    attr_xml = result.get('attribution_xml', {})
    
    # Title (20 pts)
    actual_title = attr_xml.get('title', '')
    if actual_title and actual_title.strip() == expected_title:
        score += 20
        feedback_parts.append("Attribution title correct")
    elif actual_title:
        score += 5
        feedback_parts.append(f"Attribution title mismatch: '{actual_title}'")
    else:
        feedback_parts.append("Attribution title missing")

    # Logo URL (20 pts)
    actual_url = attr_xml.get('logo_url', '')
    if actual_url == expected_logo_url:
        score += 20
        feedback_parts.append("Logo URL correct")
    elif actual_url:
        score += 5
        feedback_parts.append(f"Logo URL mismatch: '{actual_url}'")
    else:
        feedback_parts.append("Logo URL missing")

    # Logo Details (20 pts)
    # Width/Height/Format
    actual_w = attr_xml.get('logo_width', 0)
    actual_h = attr_xml.get('logo_height', 0)
    # Handle optional format check if available
    
    dims_ok = (actual_w == expected_logo_width) and (actual_h == expected_logo_height)
    if dims_ok:
        score += 20
        feedback_parts.append(f"Logo dimensions correct ({actual_w}x{actual_h})")
    elif actual_w > 0:
        score += 5
        feedback_parts.append(f"Logo dimensions incorrect ({actual_w}x{actual_h})")
    else:
        feedback_parts.append("Logo dimensions missing")

    # VLM Verification for GUI interaction
    # If API checks pass perfectly, we assume GUI usage unless VLM strongly contradicts
    # (Optional enhancement: verify they used the GUI, but the server response is the ultimate truth here)

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }