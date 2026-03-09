#!/usr/bin/env python3
"""Verifier for deploy_wfs_stored_query task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_deploy_wfs_stored_query(traj, env_info, task_info):
    """
    Verify that the WFS Stored Query 'GetLargeCities' was deployed and works correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/deploy_wfs_stored_query_result.json", temp_file.name)
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
        if result.get('result_nonce'):
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce in result but nonce file unreadable"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []

    # 1. Stored Query Exists (40 points)
    if result.get('stored_query_found', False):
        score += 40
        feedback_parts.append("Stored Query 'GetLargeCities' found in WFS capabilities")
    else:
        feedback_parts.append("Stored Query 'GetLargeCities' NOT found")

    # 2. Live Execution Success (30 points)
    http_code = result.get('test_execution_http_code', '0')
    if http_code == '200':
        score += 15
        feedback_parts.append("Query execution returned HTTP 200")
        
        # Check content
        if result.get('test_response_contains_features', False):
            score += 15
            feedback_parts.append("Query returned valid WFS features")
        else:
            feedback_parts.append("Query returned empty or invalid feature set")
    else:
        feedback_parts.append(f"Query execution failed with HTTP {http_code}")

    # 3. Logic Verification (Filtering works) (20 points)
    if result.get('test_response_valid_filter', False):
        score += 20
        feedback_parts.append("Query correctly filtered features based on population")
    elif http_code == '200' and result.get('test_response_contains_features', False):
        feedback_parts.append("Query returned too many features (filtering likely failed)")

    # 4. Agent Output File (10 points)
    if result.get('agent_file_exists', False):
        score += 10
        size = result.get('agent_file_size', 0)
        feedback_parts.append(f"Output file found ({size} bytes)")
    else:
        feedback_parts.append("Output file not saved")

    # Anti-gaming: If query exists but live execution failed completely, reduce score
    if result.get('stored_query_found') and http_code != '200':
        score = min(score, 40)
        feedback_parts.append("Penalty: Query listed but failed to execute")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }