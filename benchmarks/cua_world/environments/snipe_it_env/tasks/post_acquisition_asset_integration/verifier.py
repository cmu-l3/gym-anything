#!/usr/bin/env python3
"""Verifier for post_acquisition_asset_integration task."""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/task_result.json"

def verify_post_acquisition_asset_integration(traj, env_info, task_info):
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
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    tech_company_id = result.get("tech_company_id", "")
    nova_company_id = result.get("nova_company_id", "")
    austin_loc_id = result.get("austin_loc_id", "")
    
    users = result.get("users", {})
    assets = result.get("assets", {})
    
    # Do nothing check
    if not tech_company_id and not nova_company_id and not austin_loc_id and not assets.get("NB-001", {}).get("found"):
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No entities were created."}

    # C1: TechVantage company exists (8 pts)
    if tech_company_id:
        score += 8
        feedback.append("C1: TechVantage Solutions company created (+8)")
    else:
        feedback.append("C1: TechVantage Solutions company NOT found (+0)")

    # C2: NovaBridge company exists (5 pts)
    if nova_company_id:
        score += 5
        feedback.append("C2: NovaBridge Consulting company created (+5)")
    else:
        feedback.append("C2: NovaBridge Consulting company NOT found (+0)")

    # C3: Austin Office location (10 pts)
    if austin_loc_id:
        score += 10
        feedback.append("C3: NovaBridge - Austin Office location created (+10)")
    else:
        feedback.append("C3: Austin Office location NOT found (+0)")

    # C4: Three users created (12 pts)
    expected_users = ["rchen", "mwebb", "pkapoor"]
    users_created = 0
    for u in expected_users:
        if users.get(u, {}).get("found"):
            users_created += 1
    
    c4_score = users_created * 4
    score += c4_score
    feedback.append(f"C4: {users_created}/3 users created (+{c4_score})")

    # C5: Four assets with correct tags/serials (20 pts)
    expected_assets = {
        "NB-001": "NB-SN-40981",
        "NB-002": "NB-SN-40982",
        "NB-003": "NB-SN-40983",
        "NB-004": "NB-SN-40984"
    }
    assets_created = 0
    assets_perfect = 0
    for tag, serial in expected_assets.items():
        asset = assets.get(tag, {})
        if asset.get("found"):
            assets_created += 1
            if str(asset.get("serial", "")).strip() == serial:
                assets_perfect += 1
                
    c5_score = assets_perfect * 5
    score += c5_score
    feedback.append(f"C5: {assets_perfect}/4 assets created with correct serials (+{c5_score})")

    # C6: Correct checkout assignments (15 pts)
    checkouts_correct = 0
    checkout_mapping = {
        "NB-001": "rchen",
        "NB-002": "mwebb",
        "NB-003": "pkapoor"
    }
    for tag, user in checkout_mapping.items():
        asset = assets.get(tag, {})
        user_data = users.get(user, {})
        if asset.get("found") and user_data.get("found"):
            asset_assigned_to = str(asset.get("assigned_to", "0")).strip()
            user_id = str(user_data.get("id", "-1")).strip()
            if asset_assigned_to == user_id and asset_assigned_to != "0":
                checkouts_correct += 1
                
    c6_score = checkouts_correct * 5
    score += c6_score
    feedback.append(f"C6: {checkouts_correct}/3 assets correctly checked out (+{c6_score})")

    # C7: All assets under TechVantage (20 pts)
    assets_under_tech = 0
    for tag in expected_assets.keys():
        asset = assets.get(tag, {})
        if asset.get("found") and tech_company_id:
            if str(asset.get("company_id", "")).strip() == str(tech_company_id).strip():
                assets_under_tech += 1
                
    c7_score = assets_under_tech * 5
    score += c7_score
    feedback.append(f"C7: {assets_under_tech}/4 assets correctly assigned to TechVantage (+{c7_score})")

    # C8: NB-004 unassigned (5 pts)
    nb004 = assets.get("NB-004", {})
    if nb004.get("found"):
        if str(nb004.get("assigned_to", "0")).strip() == "0":
            score += 5
            feedback.append("C8: NB-004 correctly left unassigned (+5)")
        else:
            feedback.append("C8: NB-004 incorrectly assigned to someone (+0)")
    else:
        feedback.append("C8: NB-004 not found (+0)")

    # C9: No collateral damage (5 pts)
    other_tech = int(result.get("other_assets_tech", 0))
    other_nova = int(result.get("other_assets_nova", 0))
    initial_assets = int(result.get("initial_assets", 0))
    current_assets = int(result.get("current_assets", 0))
    
    new_assets = current_assets - initial_assets
    
    if other_tech == 0 and other_nova == 0 and new_assets <= 4:
        score += 5
        feedback.append("C9: No collateral damage detected (+5)")
    else:
        feedback.append(f"C9: Collateral damage detected (other_tech={other_tech}, other_nova={other_nova}, unexpected_assets={max(0, new_assets - 4)}) (+0)")

    # Final logic
    feedback_str = " | ".join(feedback)
    passed = score >= 60 and assets_created >= 1

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str
    }