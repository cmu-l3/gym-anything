#!/usr/bin/env python3
"""
Verifier for custom_fieldset_medical_devices task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_custom_fieldset_medical_devices(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected metadata
    metadata = task_info.get('metadata', {})
    expected_fields = metadata.get('expected_fields', [])
    expected_custom_values = metadata.get('expected_custom_values', {})

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    fieldset = result.get('fieldset', {})
    fields = result.get('fields', {})
    pivot = result.get('pivot', {})
    category = result.get('category', {})
    manufacturer = result.get('manufacturer', {})
    model = result.get('model', {})
    asset_db = result.get('asset_db', {})
    asset_api = result.get('asset_api', {})

    # Early exit if nothing was done
    if not fieldset.get('found') and not model.get('found') and not asset_db.get('found'):
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: No target entities were created."}

    # C1: Fieldset Exists (15 pts)
    if fieldset.get('found'):
        score += 15
        feedback_parts.append("C1: Fieldset 'Medical Device Compliance' found (+15)")
    else:
        feedback_parts.append("C1: Fieldset not found (+0)")

    # C2: Custom Fields Created (15 pts)
    found_fields = 0
    for fname in expected_fields:
        if fname in fields:
            found_fields += 1
    
    if found_fields == 4:
        score += 15
        feedback_parts.append("C2: All 4 custom fields created (+15)")
    else:
        partial = int((found_fields / 4) * 15)
        score += partial
        feedback_parts.append(f"C2: {found_fields}/4 custom fields created (+{partial})")

    # C3: Field-Fieldset Associations & Required Flags (10 pts)
    pivot_score = 0
    if fieldset.get('found') and pivot:
        expected_reqs = {
            "FDA 510(k) Number": "1",
            "Next Calibration Due": "1",
            "Patient Contact Class": "0",
            "Biomedical Cert Expiry": "0"
        }
        correct_pivots = 0
        for fname, req_val in expected_reqs.items():
            if fname in fields:
                fid = str(fields[fname]['id'])
                if fid in pivot and pivot[fid] == req_val:
                    correct_pivots += 1
        
        if correct_pivots == 4:
            pivot_score = 10
            feedback_parts.append("C3: All fields correctly associated with required flags (+10)")
        else:
            pivot_score = int((correct_pivots / 4) * 10)
            feedback_parts.append(f"C3: {correct_pivots}/4 fields correctly associated (+{pivot_score})")
    else:
        feedback_parts.append("C3: Fieldset associations missing (+0)")
    score += pivot_score

    # C4: Category & Manufacturer (10 pts)
    c4_score = 0
    if category.get('found'):
        c4_score += 5
        feedback_parts.append("C4a: Category 'Medical Devices' found (+5)")
    else:
        feedback_parts.append("C4a: Category not found (+0)")
        
    if manufacturer.get('found'):
        c4_score += 5
        feedback_parts.append("C4b: Manufacturer 'GE Healthcare' found (+5)")
    else:
        feedback_parts.append("C4b: Manufacturer not found (+0)")
    score += c4_score

    # C5: Model Configured correctly (15 pts)
    if model.get('found'):
        is_correct = True
        if category.get('id') and str(model.get('category_id')) != str(category['id']):
            is_correct = False
        if manufacturer.get('id') and str(model.get('manufacturer_id')) != str(manufacturer['id']):
            is_correct = False
        if fieldset.get('id') and str(model.get('fieldset_id')) != str(fieldset['id']):
            is_correct = False
        if model.get('model_number') != metadata.get('expected_model_no'):
            is_correct = False
            
        if is_correct:
            score += 15
            feedback_parts.append("C5: Model configured correctly with proper relations (+15)")
        else:
            score += 7
            feedback_parts.append("C5: Model exists but relations (cat/mfg/fieldset/number) are partially incorrect (+7)")
    else:
        feedback_parts.append("C5: Model not found (+0)")

    # C6: Asset Created (15 pts)
    if asset_db.get('found'):
        if model.get('id') and str(asset_db.get('model_id')) == str(model['id']) and asset_db.get('serial') == metadata.get('expected_serial'):
            score += 15
            feedback_parts.append("C6: Asset 'MED-001' created with correct model and serial (+15)")
        else:
            score += 7
            feedback_parts.append("C6: Asset 'MED-001' exists but model or serial is incorrect (+7)")
    else:
        feedback_parts.append("C6: Asset not found (+0)")

    # C7: Custom Field Values Populated (20 pts)
    custom_fields_data = asset_api.get('custom_fields', {})
    correct_vals = 0
    
    # API might return a list of objects or dict of objects depending on Snipe-IT version
    # Standardize dictionary lookup based on field name
    parsed_custom_values = {}
    if isinstance(custom_fields_data, dict):
        for k, v in custom_fields_data.items():
            if isinstance(v, dict) and 'value' in v:
                parsed_custom_values[k] = str(v['value'])
            else:
                parsed_custom_values[k] = str(v)
    elif isinstance(custom_fields_data, list):
        for item in custom_fields_data:
            if isinstance(item, dict) and 'field' in item and 'value' in item:
                parsed_custom_values[item['field']] = str(item['value'])

    for fname, expected_val in expected_custom_values.items():
        if fname in parsed_custom_values and expected_val in parsed_custom_values[fname]:
            correct_vals += 1
            
    if correct_vals == 4:
        score += 20
        feedback_parts.append("C7: All 4 custom field values correctly populated on asset (+20)")
    else:
        partial = int((correct_vals / 4) * 20)
        score += partial
        feedback_parts.append(f"C7: {correct_vals}/4 custom field values correct on asset (+{partial})")

    # Pass condition
    passed = score >= 60 and fieldset.get('found') and model.get('found') and asset_db.get('found')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }