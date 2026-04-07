#!/usr/bin/env python3
"""Verifier for byod_zero_trust_registration task.

Scoring System (100 points total):
  C1 (10 pts): Custom fields exist with correct formats (MAC, Alpha Numeric)
  C2 (10 pts): Fieldset exists and contains both fields
  C3 (10 pts): Status Label "BYOD - Approved" exists and is Deployable
  C4 (10 pts): Model exists, linked to right category, manufacturer, and fieldset
  C5 (20 pts): Assets created with $0 cost and correct status
  C6 (20 pts): Assets are checked out/assigned to correct specific users
  C7 (10 pts): Assets contain the correct exact string values for MAC and OS
  C8 (10 pts): No collateral damage (asset count increased by exactly 3)
"""

import json
import tempfile
import os
import logging
import math

logger = logging.getLogger(__name__)

def verify_byod_registration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve output
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    expected_assets = task_info.get('metadata', {}).get('assets', [])
    assets_data = result.get('assets', {})

    # DO-NOTHING CHECK:
    cf = result.get('custom_fields', {})
    fs = result.get('fieldset', {})
    if not cf.get('mac_format') and not fs.get('exists') and not assets_data.get('BYOD-001', {}).get('found'):
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No required schema objects or assets created."}

    # C1: Custom Fields (10 pts)
    c1_score = 0
    mac_fmt = cf.get('mac_format', '')
    if mac_fmt == 'MAC':
        c1_score += 5
        feedback.append("C1: Network MAC Address field exists with MAC format (+5)")
    else:
        feedback.append(f"C1: Network MAC Address field missing or wrong format (found: '{mac_fmt}') (+0)")
    
    os_fmt = cf.get('os_format', '')
    if os_fmt == 'ALPHA':
        c1_score += 5
        feedback.append("C1: Mobile OS Version field exists with Alpha Numeric format (+5)")
    else:
        feedback.append(f"C1: Mobile OS Version field missing or wrong format (found: '{os_fmt}') (+0)")
    score += c1_score

    # C2: Fieldset (10 pts)
    c2_score = 0
    if fs.get('exists'):
        if fs.get('mac_linked') and fs.get('os_linked'):
            c2_score += 10
            feedback.append("C2: BYOD Device Info fieldset exists and contains both custom fields (+10)")
        else:
            c2_score += 5
            feedback.append("C2: BYOD Device Info fieldset exists but is missing one or both fields (+5)")
    else:
        feedback.append("C2: BYOD Device Info fieldset does not exist (+0)")
    score += c2_score

    # C3: Status Label (10 pts)
    status_label = result.get('status_label', {})
    if status_label.get('exists') and status_label.get('deployable'):
        score += 10
        feedback.append("C3: Status Label 'BYOD - Approved' exists and is Deployable (+10)")
    else:
        feedback.append("C3: Status Label 'BYOD - Approved' missing or not Deployable (+0)")

    # C4: Model (10 pts)
    model = result.get('model', {})
    if model.get('exists'):
        c4_score = 4
        if model.get('category') == "Mobile Devices":
            c4_score += 2
        if model.get('manufacturer') == "Generic":
            c4_score += 2
        if model.get('target_fieldset_id') and str(model.get('fieldset_id')) == str(model.get('target_fieldset_id')):
            c4_score += 2
        score += c4_score
        feedback.append(f"C4: Personal Smartphone model exists with partial/full correctness (+{c4_score})")
    else:
        feedback.append("C4: Personal Smartphone model does not exist (+0)")

    # Process Assets (C5, C6, C7)
    c5_correct = 0
    c6_correct = 0
    c7_correct = 0

    max_id_start = result.get('max_asset_id_start', 0)
    for expected in expected_assets:
        tag = expected['tag']
        ast = assets_data.get(tag, {})
        if not ast.get('found'):
            feedback.append(f"C5/6/7: Asset {tag} not found")
            continue

        # C5: Cost and Status
        cost_str = ast.get('cost', '0').replace('$', '').replace(',', '')
        try:
            cost = float(cost_str)
        except ValueError:
            cost = -1.0
        
        status = ast.get('status', '')
        created_during_task = ast.get('id', 0) > max_id_start

        if math.isclose(cost, 0.0) and status == "BYOD - Approved" and created_during_task:
            c5_correct += 1

        # C6: Checked out user
        if ast.get('user') == expected['user']:
            c6_correct += 1
        
        # C7: Custom fields values
        mac = ast.get('mac', '').lower()
        os_ver = ast.get('os', '').lower()
        if expected['mac'].lower() in mac and expected['os'].lower() in os_ver and os_ver != "":
            c7_correct += 1

    c5_score = int(20 * (c5_correct / 3))
    score += c5_score
    feedback.append(f"C5: {c5_correct}/3 assets have $0 cost and 'BYOD - Approved' status (+{c5_score})")

    c6_score = int(20 * (c6_correct / 3))
    score += c6_score
    feedback.append(f"C6: {c6_correct}/3 assets assigned to correct users (+{c6_score})")

    c7_score = int(10 * (c7_correct / 3))
    score += c7_score
    feedback.append(f"C7: {c7_correct}/3 assets have correct custom field values (+{c7_score})")

    # C8: Collateral Damage (10 pts)
    initial_assets = result.get('initial_asset_count', 0)
    current_assets = result.get('current_asset_count', 0)
    assets_diff = current_assets - initial_assets
    if assets_diff == 3:
        score += 10
        feedback.append("C8: Exactly 3 new assets added (no collateral damage) (+10)")
    else:
        feedback.append(f"C8: Expected 3 new assets, but found difference of {assets_diff} (+0)")

    # Overall outcome
    passed = score >= 70 and c5_correct > 0 and c6_correct > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }