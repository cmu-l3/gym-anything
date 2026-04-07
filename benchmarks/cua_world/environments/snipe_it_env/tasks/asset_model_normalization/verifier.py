#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)
RESULT_PATH = "/tmp/asset_model_normalization_result.json"

def verify_asset_model_normalization(traj, env_info, task_info):
    # CRITICAL: Verify using secure copy_from_env approach instead of exec_in_env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result file: {e}"}

    score = 0
    feedback = []

    models = result.get('models', {})
    assets = result.get('assets', [])
    c_lap_id = result.get('canonical_laptop_id')
    c_mon_id = result.get('canonical_monitor_id')

    # Gate 1: Check if anything at all happened (Anti-Gaming)
    assets_reassigned = 0
    for a in assets:
        tag = a.get('tag', '')
        m_id = a.get('model_id')
        if tag.startswith('ASSET-NORM-0') and int(tag[-1]) <= 5: # Laptop assets (1-5)
            if m_id == c_lap_id: assets_reassigned += 1
        elif tag.startswith('ASSET-NORM-0'): # Monitor assets (6-9)
            if m_id == c_mon_id: assets_reassigned += 1

    dup_deleted = sum(1 for key in ['dup_laptop_1', 'dup_laptop_2', 'dup_monitor_1', 'dup_monitor_2'] 
                      if models.get(key, {}).get('is_deleted', False))

    if assets_reassigned == 0 and dup_deleted == 0:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "DO-NOTHING: No assets were reassigned and no duplicates were deleted."
        }

    # C1: Laptop Asset Reassignment (25 points - 5 pts each)
    laptop_reassigned = sum(1 for a in assets if a.get('tag', '').startswith('ASSET-NORM-0') 
                            and int(a.get('tag')[-1]) <= 5 and a.get('model_id') == c_lap_id)
    if laptop_reassigned == 5:
        score += 25
        feedback.append("C1: All 5 laptop assets correctly reassigned to Canonical Laptop (+25)")
    else:
        pts = laptop_reassigned * 5
        score += pts
        feedback.append(f"C1: {laptop_reassigned}/5 laptop assets reassigned (+{pts})")

    # C2: Monitor Asset Reassignment (25 points - 6.25 pts each)
    monitor_reassigned = sum(1 for a in assets if a.get('tag', '').startswith('ASSET-NORM-0') 
                             and int(a.get('tag')[-1]) > 5 and a.get('model_id') == c_mon_id)
    if monitor_reassigned == 4:
        score += 25
        feedback.append("C2: All 4 monitor assets correctly reassigned to Canonical Monitor (+25)")
    else:
        pts = int(monitor_reassigned * 6.25)
        score += pts
        feedback.append(f"C2: {monitor_reassigned}/4 monitor assets reassigned (+{pts})")

    # C3: Canonical Models Updated (20 points - 10 pts each)
    c3_score = 0
    if models.get('canonical_laptop', {}).get('model_number') == "20W0009DUS":
        c3_score += 10
        feedback.append("C3a: Canonical Laptop model number updated correctly (+10)")
    else:
        feedback.append("C3a: Canonical Laptop model number incorrect (+0)")

    if models.get('canonical_monitor', {}).get('model_number') == "U2720Q":
        c3_score += 10
        feedback.append("C3b: Canonical Monitor model number updated correctly (+10)")
    else:
        feedback.append("C3b: Canonical Monitor model number incorrect (+0)")
    score += c3_score

    # C4: Duplicate Models Deleted (20 points - 5 pts each)
    if dup_deleted == 4:
        score += 20
        feedback.append("C4: All 4 duplicate models successfully soft-deleted (+20)")
    else:
        pts = dup_deleted * 5
        score += pts
        feedback.append(f"C4: {dup_deleted}/4 duplicate models deleted (+{pts})")

    # C5: No Collateral Damage (10 points)
    expected_models_dynamic = result.get('baseline_models', 0) - dup_deleted
    baseline_assets = result.get('baseline_assets', 0)
    current_models = result.get('current_models', 0)
    current_assets = result.get('current_assets', 0)

    if current_models == expected_models_dynamic and current_assets == baseline_assets:
        score += 10
        feedback.append("C5: No collateral damage detected (+10)")
    else:
        feedback.append(f"C5: Collateral damage detected! (Models: {current_models} expected {expected_models_dynamic}, Assets: {current_assets} expected {baseline_assets}) (+0)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }