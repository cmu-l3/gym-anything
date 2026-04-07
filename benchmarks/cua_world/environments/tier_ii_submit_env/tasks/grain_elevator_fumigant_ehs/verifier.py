#!/usr/bin/env python3
"""
Verifier for grain_elevator_fumigant_ehs task.

This verifier assesses the SQLite database extracted from the agent's .t2s export.
It uses robust, case-insensitive keyword searches across the table columns to evaluate
the data, protecting against minor schema naming differences across EPA Tier2 Submit updates.
"""
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\Desktop\\grain_elevator_fumigant_ehs_result.json"

def verify_grain_elevator_fumigant_ehs(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", RESULT_PATH)
    pass_threshold = metadata.get("pass_threshold", 75)
    expected_cas = metadata.get("expected_cas", "20859-73-8")

    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # 1. File Generation & Anti-gaming (10 pts)
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found."}
    if not result.get("created_during_task", False):
        feedback.append("WARNING: File timestamp suggests it was not created during the task.")
    else:
        score += 10
        feedback.append("PASS: Valid .t2s file exported (+10)")

    tables = result.get("tables", {})

    # 2. Facility EPCRA 302 Status (15 pts)
    fac_table_name = next((t for t in tables.keys() if 'facility' in t.lower()), None)
    fac_data = tables.get(fac_table_name, [{}])[0] if fac_table_name and tables[fac_table_name] else {}
    
    epcra_302_found = False
    for k, v in fac_data.items():
        if '302' in k.lower() or 'emergencyplanning' in k.lower():
            if str(v).lower() in ['true', '1', 'yes', 'y']:
                epcra_302_found = True
                break
                
    if epcra_302_found:
        score += 15
        feedback.append("PASS: Facility EPCRA 302 flag set to Yes (+15)")
    else:
        feedback.append("FAIL: Facility EPCRA 302 flag not updated to Yes")

    # 3. Locate Chemical
    chem_table_name = next((t for t in tables.keys() if 'chemical' in t.lower()), None)
    chem_list = tables.get(chem_table_name, [])
    
    alum_phos = None
    chem_id = None
    for c in chem_list:
        cas_val = str(c.get('CASNumber', c.get('CAS', '')))
        if expected_cas in cas_val:
            alum_phos = c
            # Try to grab ID for foreign key joins
            chem_id = c.get('ChemicalID', c.get('ID', c.get('id')))
            break

    if not alum_phos:
        feedback.append(f"FAIL: Aluminum Phosphide (CAS {expected_cas}) not found.")
        passed = score >= pass_threshold
        return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}
    
    # Check EHS
    is_ehs = False
    for k, v in alum_phos.items():
        if 'ehs' in k.lower() and str(v).lower() in ['true', '1', 'yes', 'y']:
            is_ehs = True
            
    if is_ehs:
        score += 15
        feedback.append("PASS: Chemical added and marked as EHS (+15)")
    else:
        feedback.append("FAIL: Chemical added but not marked EHS")

    # 4. Physical State (10 pts)
    is_solid = False
    for k, v in alum_phos.items():
        if 'physicalstate' in k.lower() or 'state' in k.lower():
            if 'solid' in str(v).lower() or ('solid' in k.lower() and str(v).lower() in ['true', '1']):
                is_solid = True
                break
                
    if is_solid:
        score += 10
        feedback.append("PASS: Physical State marked as Solid (+10)")
    else:
        feedback.append("FAIL: Physical State is not Solid")

    # 5. Inventory Data (20 pts)
    # Check days on site, max amount, ave amount
    has_90_days = False
    has_max_03 = False
    has_ave_02 = False
    
    for k, v in alum_phos.items():
        v_str = str(v).lower()
        if 'days' in k.lower() and '90' in v_str:
            has_90_days = True
        if 'max' in k.lower() and ('amount' in k.lower() or 'code' in k.lower()) and ('03' in v_str or v_str == '3'):
            has_max_03 = True
        if 'ave' in k.lower() and ('amount' in k.lower() or 'code' in k.lower()) and ('02' in v_str or v_str == '2'):
            has_ave_02 = True

    if has_90_days and has_max_03 and has_ave_02:
        score += 20
        feedback.append("PASS: Inventory details (90 days, Codes 03 & 02) are correct (+20)")
    else:
        feedback.append(f"FAIL: Inventory details incorrect (Days=90: {has_90_days}, Max=03: {has_max_03}, Ave=02: {has_ave_02})")

    # 6. Hazards (20 pts)
    # Hazards can be columns in chemical table OR a separate hazard table
    acute_found = False
    water_reactive_found = False
    
    # Check embedded columns first
    for k, v in alum_phos.items():
        v_str = str(v).lower()
        if str(v).lower() in ['true', '1', 'yes', 'y']:
            if 'acute' in k.lower() or 'toxicity' in k.lower():
                acute_found = True
            if 'water' in k.lower() and 'reactive' in k.lower():
                water_reactive_found = True

    # Check separate hazard table if exists
    haz_table_name = next((t for t in tables.keys() if 'hazard' in t.lower()), None)
    if haz_table_name and chem_id is not None:
        for row in tables[haz_table_name]:
            # Match by foreign key
            if row.get('ChemicalID', row.get('Chemical_ID')) == chem_id:
                for k, v in row.items():
                    val_str = str(v).lower()
                    if 'acute' in val_str or ('acute' in k.lower() and val_str in ['true', '1']):
                        acute_found = True
                    if ('water' in val_str and 'flammable gas' in val_str) or ('water' in k.lower() and val_str in ['true', '1']):
                        water_reactive_found = True

    if acute_found and water_reactive_found:
        score += 20
        feedback.append("PASS: Acute Toxicity and Water-Reactive hazards correctly classified (+20)")
    else:
        feedback.append(f"FAIL: Missing expected hazards (Acute: {acute_found}, Water-Reactive: {water_reactive_found})")

    # 7. Storage Location (10 pts)
    stor_table_name = next((t for t in tables.keys() if 'storage' in t.lower()), None)
    storage_ok = False
    
    if stor_table_name and chem_id is not None:
        for row in tables[stor_table_name]:
            if row.get('ChemicalID', row.get('Chemical_ID')) == chem_id:
                row_str = json.dumps(row).lower()
                if 'drum' in row_str and 'building b' in row_str:
                    storage_ok = True
                    break
                    
    if storage_ok:
        score += 10
        feedback.append("PASS: Storage location (Drum, Building B) correctly logged (+10)")
    else:
        feedback.append("FAIL: Storage location parameters missing or incorrect")

    passed = score >= pass_threshold
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }