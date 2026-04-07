#!/usr/bin/env python3
import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/rma_task_result.json"

def verify_warranty_rma_device_swap(traj, env_info, task_info):
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
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    baseline = result.get('baseline', {})
    sl_retired_id = str(result.get('sl_retired_id', ''))
    old_assets = result.get('old_assets', {})
    new_assets = result.get('new_assets', {})

    # DO-NOTHING CHECK
    any_modifications = False
    for tag in ["LPT-ERR-01", "LPT-ERR-02", "LPT-ERR-03"]:
        asset = old_assets.get(tag, {})
        if asset.get('found'):
            if str(asset.get('status_id')) == sl_retired_id or "RMA-9988" in str(asset.get('notes', '')).upper():
                any_modifications = True
            if asset.get('assigned_to') in [None, "", "0", "NULL"]:
                any_modifications = True # It was originally checked out, checking it in proves progress
    
    for tag in ["LPT-REP-01", "LPT-REP-02", "LPT-REP-03"]:
        if new_assets.get(tag, {}).get('found'):
            any_modifications = True

    if not any_modifications:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No assets were modified or created."}

    # CRITERIA 1: Old Assets Retired (15 points)
    old_retired_count = 0
    for i in [1, 2, 3]:
        tag = f"LPT-ERR-0{i}"
        asset = old_assets.get(tag, {})
        if asset.get('found'):
            status_match = str(asset.get('status_id')) == sl_retired_id
            unassigned_match = asset.get('assigned_to') in [None, "", "0", "NULL"]
            
            if status_match and unassigned_match:
                old_retired_count += 1
            elif not status_match:
                feedback.append(f"C1: {tag} status is not Retired.")
            elif not unassigned_match:
                feedback.append(f"C1: {tag} is still assigned to a user.")
        else:
            feedback.append(f"C1: {tag} was deleted entirely (should be Retired).")

    c1_pts = int((old_retired_count / 3.0) * 15)
    score += c1_pts
    if old_retired_count == 3:
        feedback.append("C1: All old assets correctly checked in and retired (+15)")
    else:
        feedback.append(f"C1: {old_retired_count}/3 old assets retired (+{c1_pts})")

    # CRITERIA 2: Old Assets Noted (10 points)
    old_noted_count = 0
    for i in [1, 2, 3]:
        tag = f"LPT-ERR-0{i}"
        asset = old_assets.get(tag, {})
        if asset.get('found') and "RMA-9988" in str(asset.get('notes', '')).upper():
            old_noted_count += 1
        elif asset.get('found'):
            feedback.append(f"C2: {tag} notes missing 'RMA-9988'.")
            
    c2_pts = int((old_noted_count / 3.0) * 10)
    score += c2_pts
    if old_noted_count == 3:
        feedback.append("C2: All old assets properly noted with RMA-9988 (+10)")
    else:
        feedback.append(f"C2: {old_noted_count}/3 old assets properly noted (+{c2_pts})")

    # CRITERIA 3: New Assets Created (15 points)
    new_created_count = 0
    expected_serials = {"LPT-REP-01": "NEW-SN-01", "LPT-REP-02": "NEW-SN-02", "LPT-REP-03": "NEW-SN-03"}
    for tag, exp_serial in expected_serials.items():
        asset = new_assets.get(tag, {})
        if asset.get('found'):
            if str(asset.get('serial', '')).strip().upper() == exp_serial.upper():
                new_created_count += 1
            else:
                feedback.append(f"C3: {tag} created but wrong serial (expected {exp_serial}).")
        else:
            feedback.append(f"C3: {tag} was not created.")

    c3_pts = int((new_created_count / 3.0) * 15)
    score += c3_pts
    if new_created_count == 3:
        feedback.append("C3: All new assets created with correct tags and serials (+15)")
    else:
        feedback.append(f"C3: {new_created_count}/3 new assets correctly created (+{c3_pts})")

    # CRITERIA 4 & 5: Financial Fidelity (30 pts) & User Provisioning (30 pts)
    fidelity_count = 0
    prov_count = 0
    mappings = {"LPT-REP-01": "LPT-ERR-01", "LPT-REP-02": "LPT-ERR-02", "LPT-REP-03": "LPT-ERR-03"}

    for new_tag, old_tag in mappings.items():
        asset = new_assets.get(new_tag, {})
        base = baseline.get(old_tag, {})
        
        if asset.get('found'):
            # Check Fidelity
            try:
                base_cost = float(base.get('cost', 0))
                actual_cost = float(asset.get('purchase_cost', -1))
                cost_match = abs(base_cost - actual_cost) < 0.1
            except:
                cost_match = False

            date_match = str(asset.get('purchase_date'))[:10] == str(base.get('date'))[:10]
            model_match = str(asset.get('model_id')) == str(base.get('model_id'))

            fid_ok = True
            if not cost_match:
                feedback.append(f"C4: {new_tag} cost mismatch (expected {base.get('cost')}).")
                fid_ok = False
            if not date_match:
                feedback.append(f"C4: {new_tag} date mismatch (expected {base.get('date')}).")
                fid_ok = False
            if not model_match:
                feedback.append(f"C4: {new_tag} model mismatch.")
                fid_ok = False

            if fid_ok:
                fidelity_count += 1

            # Check Provisioning
            exp_user = str(base.get('username', ''))
            act_user = str(asset.get('assigned_username', ''))
            if act_user == exp_user and exp_user != '':
                prov_count += 1
            else:
                feedback.append(f"C5: {new_tag} checked out to wrong user (expected '{exp_user}', got '{act_user}').")

    c4_pts = int((fidelity_count / 3.0) * 30)
    score += c4_pts
    if fidelity_count == 3:
        feedback.append("C4: All new assets correctly copied financial/model metadata (+30)")
    else:
        feedback.append(f"C4: {fidelity_count}/3 new assets copied metadata correctly (+{c4_pts})")

    c5_pts = int((prov_count / 3.0) * 30)
    score += c5_pts
    if prov_count == 3:
        feedback.append("C5: All new assets checked out to original users (+30)")
    else:
        feedback.append(f"C5: {prov_count}/3 new assets correctly checked out (+{c5_pts})")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }