#!/usr/bin/env python3
"""
Verifier for spatial_geofencing_analysis task.

Criteria:
1. Spatial Index 'Hotels.Location' must exist with LUCENE algorithm.
2. 'Hotel Artemide' (inside polygon) must have MarketingZone='HistoricCenter'.
3. 'Hotel Adlon Kempinski' (outside polygon) must NOT have MarketingZone='HistoricCenter'.
4. Total tagged count should be reasonable (small number, not all hotels).
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spatial_geofencing_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 2. Verify Index (30 pts)
    index_exists = result.get('index_exists', False)
    algo = result.get('index_algorithm', '').upper()
    
    if index_exists:
        if 'LUCENE' in algo:
            score += 30
            feedback.append("Spatial Index created correctly (LUCENE).")
        else:
            score += 15
            feedback.append(f"Index created but algorithm is '{algo}' (expected LUCENE).")
    else:
        feedback.append("Index 'Hotels.Location' NOT found.")

    # 3. Verify Tags (Target vs Control)
    tags = result.get('tag_results', {})
    artemide_val = tags.get('artemide')
    adlon_val = tags.get('adlon')
    target_val = "HistoricCenter"

    # Positive Match (30 pts)
    if artemide_val == target_val:
        score += 30
        feedback.append("Target hotel 'Hotel Artemide' correctly tagged.")
    else:
        feedback.append(f"Target hotel 'Hotel Artemide' has wrong tag: '{artemide_val}'.")

    # Negative Match (20 pts)
    if adlon_val != target_val:
        score += 20
        feedback.append("Control hotel 'Hotel Adlon Kempinski' correctly NOT tagged.")
    else:
        feedback.append("Control hotel 'Hotel Adlon Kempinski' was incorrectly tagged (False Positive).")

    # 4. Count Logic (20 pts)
    # The polygon is small (center of Rome). Only a few hotels should match.
    # If count > 100, they likely did 'UPDATE Hotels SET ...' without a WHERE clause or with a wrong one.
    total_tagged = result.get('total_tagged_count', 0)
    
    if 0 < total_tagged < 20:
        score += 20
        feedback.append(f"Tagged count reasonable ({total_tagged}).")
    elif total_tagged == 0:
        feedback.append("No hotels were tagged.")
    else:
        feedback.append(f"Too many hotels tagged ({total_tagged}). Check query logic.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }