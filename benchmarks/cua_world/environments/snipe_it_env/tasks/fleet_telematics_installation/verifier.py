#!/usr/bin/env python3
"""
Verifier for fleet_telematics_installation task.

Scoring breakdown (100 points total):
  C1: Taxonomy Setup - Category, Manufacturer, Models correct (15 pts)
  C2: Asset Registration - 6 assets exist, cost and PO correct (25 pts)
  C3: Asset-to-Asset Integrity - successfully checked out to parent vehicles (30 pts)
  C4: Checkout Documentation - correct note in action log (10 pts)
  C5: Exception Handling - VEH-103 marked 'Out for Repair' (10 pts)
  C6: Exception Documentation - VEH-103 notes updated (10 pts)
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/fleet_telematics_result.json"


def verify_fleet_telematics_installation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    vehicles = result.get('vehicles', {})
    telematics = result.get('telematics', [])
    telem_dict = {t.get('tag'): t for t in telematics if t.get('tag')}
    
    # --- Do-Nothing Gate ---
    if not any(t.get('found') for t in telematics) and vehicles.get('VEH-103', {}).get('status_name') != 'Out for Repair':
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No telematics assets found and VEH-103 status unchanged."}
        
    score = 0
    feedback = []
    
    expected_tags = ['DASH-01', 'DASH-02', 'DASH-03', 'ELD-01', 'ELD-02', 'ELD-03']
    
    # --- C1: Taxonomy Setup (15 points) ---
    tax_correct = 0
    for tag in expected_tags:
        asset = telem_dict.get(tag, {})
        if asset.get('found'):
            if asset.get('category') == 'Telematics' and asset.get('manufacturer') == 'Samsara':
                expected_model = 'CM31 Dashcam' if 'DASH' in tag else 'VG34 ELD'
                if asset.get('model') == expected_model:
                    tax_correct += 1
    c1_score = int(15 * (tax_correct / 6))
    score += c1_score
    feedback.append(f"C1 Taxonomy Setup: {tax_correct}/6 assets have correct Category/Manufacturer/Model (+{c1_score})")

    # --- C2: Asset Registration (25 points) ---
    reg_correct = 0
    for tag in expected_tags:
        asset = telem_dict.get(tag, {})
        if asset.get('found'):
            expected_cost = 350.0 if 'DASH' in tag else 150.0
            try:
                # Remove common currency formatting just in case
                actual_cost_str = str(asset.get('cost', '0')).replace('$', '').replace(',', '')
                actual_cost = float(actual_cost_str)
            except (ValueError, TypeError):
                actual_cost = 0.0
            
            if abs(actual_cost - expected_cost) < 0.1 and asset.get('order') == 'PO-TEL-001':
                reg_correct += 1
    c2_score = int(25 * (reg_correct / 6))
    score += c2_score
    feedback.append(f"C2 Asset Registration: {reg_correct}/6 assets have correct Cost and PO (+{c2_score})")

    # --- C3: Asset-to-Asset Integrity (30 points) ---
    integ_correct = 0
    mapping = {
        'DASH-01': 'VEH-101', 'DASH-02': 'VEH-102', 'DASH-03': 'VEH-103',
        'ELD-01': 'VEH-101', 'ELD-02': 'VEH-102', 'ELD-03': 'VEH-103'
    }
    for tag in expected_tags:
        asset = telem_dict.get(tag, {})
        if asset.get('found'):
            atype = str(asset.get('assigned_type', ''))
            ato = asset.get('assigned_to')
            
            target_veh_tag = mapping[tag]
            target_veh = vehicles.get(target_veh_tag, {})
            target_id = target_veh.get('id')
            
            # Verify the polymorphic relation points to the correct asset
            if 'Asset' in atype and ato == target_id and target_id is not None:
                integ_correct += 1
    c3_score = int(30 * (integ_correct / 6))
    score += c3_score
    feedback.append(f"C3 Nested Assignment: {integ_correct}/6 assets correctly checked out to parent vehicles (+{c3_score})")
    
    # --- C4: Checkout Documentation (10 points) ---
    note_correct = sum(1 for tag in expected_tags if telem_dict.get(tag, {}).get('checkout_note_found'))
    c4_score = int(10 * (note_correct / 6))
    score += c4_score
    feedback.append(f"C4 Checkout Documentation: {note_correct}/6 checkout logs have expected note (+{c4_score})")

    # --- C5: Exception Handling - Status (10 points) ---
    veh103 = vehicles.get('VEH-103', {})
    if veh103.get('status_name') == 'Out for Repair':
        score += 10
        feedback.append("C5 Exception Handling: VEH-103 correctly marked 'Out for Repair' (+10)")
    else:
        feedback.append(f"C5 Exception Handling: VEH-103 status is '{veh103.get('status_name')}', expected 'Out for Repair' (+0)")

    # --- C6: Exception Documentation - Notes (10 points) ---
    if 'cracked windshield' in str(veh103.get('notes', '')).lower():
        score += 10
        feedback.append("C6 Exception Documentation: VEH-103 notes contain 'Cracked windshield' (+10)")
    else:
        feedback.append("C6 Exception Documentation: VEH-103 notes missing expected text (+0)")

    # Pass condition: High score and must have demonstrated some nested assignments
    passed = (score >= 75) and (integ_correct >= 4)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }