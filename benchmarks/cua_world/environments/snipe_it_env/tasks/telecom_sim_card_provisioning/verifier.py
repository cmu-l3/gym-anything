#!/usr/bin/env python3
"""Verifier for telecom_sim_card_provisioning task.

Scoring breakdown (100 points):
| C1: Custom Fields | 15 | "Phone Number" and "Carrier" custom fields exist. |
| C2: Fieldset Binding | 15 | "Telecom Data" fieldset exists and both fields are assigned to it. |
| C3: Category Setup | 10 | "SIM Cards" category exists and is bound to the "Telecom Data" fieldset. |
| C4: Model Creation | 10 | "5G Business SIM" model created under the correct manufacturer and category. |
| C5: Asset Instantiation | 15 | SIM-001, SIM-002, and SIM-003 exist with correct ICCID serial numbers. |
| C6: Custom Data | 15 | The dynamic custom fields on the SIM assets correctly contain the phone numbers and carrier names. |
| C7: Asset-to-Asset Checkout | 20 | All three SIMs are checked out to `App\Models\Asset` targeting the correct iPhones (MOB-001 to 003). |
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/telecom_result.json"


def verify_telecom_sim_card_provisioning(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    score = 0
    feedback = []

    # C1: Custom Fields (15 pts)
    c1 = 0
    cf = result.get("custom_fields", {})
    if cf.get("phone_exists"):
        c1 += 7.5
        feedback.append("C1a: Phone Number field exists (+7.5)")
    else:
        feedback.append("C1a: Phone Number field missing (+0)")
        
    if cf.get("carrier_exists"):
        c1 += 7.5
        feedback.append("C1b: Carrier field exists (+7.5)")
    else:
        feedback.append("C1b: Carrier field missing (+0)")
    score += int(c1)
    
    # C2: Fieldset Binding (15 pts)
    c2 = 0
    fs = result.get("fieldset", {})
    if fs.get("exists"):
        c2 += 5
        feedback.append("C2a: Telecom Data fieldset exists (+5)")
        if fs.get("has_phone"):
            c2 += 5
            feedback.append("C2b: Phone field bound to fieldset (+5)")
        else:
            feedback.append("C2b: Phone field not bound to fieldset (+0)")
            
        if fs.get("has_carrier"):
            c2 += 5
            feedback.append("C2c: Carrier field bound to fieldset (+5)")
        else:
            feedback.append("C2c: Carrier field not bound to fieldset (+0)")
    else:
        feedback.append("C2: Telecom Data fieldset missing (+0)")
    score += int(c2)
    
    # C3: Category Setup (10 pts)
    cat = result.get("category", {})
    if cat.get("exists"):
        if cat.get("bound_to_fs"):
            score += 10
            feedback.append("C3: SIM Cards category exists and is bound to Telecom Data fieldset (+10)")
        else:
            score += 5
            feedback.append("C3: SIM Cards category exists but NOT bound to fieldset (+5)")
    else:
        feedback.append("C3: SIM Cards category missing (+0)")
        
    # C4: Model Creation (10 pts)
    mod = result.get("model", {})
    man = result.get("manufacturer", {})
    if man.get("exists"):
        feedback.append("C4a: Telecom Providers manufacturer exists")
    else:
        feedback.append("C4a: Telecom Providers manufacturer missing")

    if mod.get("exists"):
        if mod.get("correct_category"):
            score += 10
            feedback.append("C4b: 5G Business SIM model exists with correct category (+10)")
        else:
            score += 5
            feedback.append("C4b: 5G Business SIM model exists but wrong category (+5)")
    else:
        feedback.append("C4b: 5G Business SIM model missing (+0)")
        
    # SIM expected details
    expected_sims = {
        "SIM-001": {"serial": "89148000000000012345", "phone": "800-480-1001", "carrier": "Verizon", "mob": "MOB-001"},
        "SIM-002": {"serial": "89148000000000067890", "phone": "800-480-1002", "carrier": "Verizon", "mob": "MOB-002"},
        "SIM-003": {"serial": "89141000000000054321", "phone": "800-410-1003", "carrier": "AT&T", "mob": "MOB-003"}
    }
    
    sims = result.get("sims", {})
    mobs = result.get("mobs", {})
    
    c5_score = 0
    c6_score = 0
    c7_score = 0
    
    for tag, expected in expected_sims.items():
        sim = sims.get(tag, {})
        if sim.get("found"):
            # C5: Instantiation
            if expected["serial"] in sim.get("serial", ""):
                c5_score += 5
                feedback.append(f"C5: {tag} exists with correct serial (+5)")
            else:
                c5_score += 2
                feedback.append(f"C5: {tag} exists but wrong serial ({sim.get('serial')}) (+2)")
                
            # C6: Custom Data Validation
            phone_ok = expected["phone"] in sim.get("phone", "")
            carrier_ok = expected["carrier"].lower() in sim.get("carrier", "").lower()
            
            if phone_ok and carrier_ok:
                c6_score += 5
                feedback.append(f"C6: {tag} has correct phone and carrier data (+5)")
            elif phone_ok or carrier_ok:
                c6_score += 2
                feedback.append(f"C6: {tag} has partial custom data (+2)")
            else:
                feedback.append(f"C6: {tag} missing custom data (+0)")
                
            # C7: Checkout verification
            assigned_to = str(sim.get("assigned_to", ""))
            assigned_type = str(sim.get("assigned_type", ""))
            expected_mob_id = str(mobs.get(expected["mob"], ""))
            
            # Note: assigned_type string matching is robust against backslash escaping (App\Models\Asset)
            if "Asset" in assigned_type and assigned_to == expected_mob_id and expected_mob_id:
                c7_score += 6.66
                feedback.append(f"C7: {tag} checked out to {expected['mob']} properly (+6.66)")
            else:
                if assigned_to and assigned_to != "0" and assigned_to != "None":
                    feedback.append(f"C7: {tag} checked out, but to wrong target or not to Asset type ({assigned_type}, ID {assigned_to}) (+0)")
                else:
                    feedback.append(f"C7: {tag} not checked out (+0)")
        else:
            feedback.append(f"C5/6/7: {tag} missing (+0)")
            
    score += c5_score
    score += c6_score
    score += round(c7_score)
    
    # Do-Nothing / Anti-Gaming Check
    if c1 == 0 and not cat.get("exists") and not mod.get("exists") and c5_score == 0:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING detected. No relevant schema modifications or assets found."}
        
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }