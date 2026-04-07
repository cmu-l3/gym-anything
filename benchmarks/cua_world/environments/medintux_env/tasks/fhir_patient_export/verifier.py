#!/usr/bin/env python3
"""
Verifier for fhir_patient_export task.

Checks:
1. File existence and valid JSON (10 pts)
2. FHIR Bundle Structure (resourceType='Bundle') (10 pts)
3. Patient Count Accuracy (Matches DB count) (10 pts)
4. Data Integrity (8 specific test patients match expected fields) (65 pts)
   - Name match
   - Gender mapping (H/F -> male/female)
   - DOB format
   - NIR identifier present
   - Address/City match
5. Anti-gaming (File created during task) (5 pts)
"""

import json
import os
import tempfile
import logging
import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fhir_patient_export(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_patients = metadata.get('expected_patients', [])
    
    score = 0
    feedback_parts = []
    
    # 1. Load Task Result (Metadata from export script)
    task_result = {}
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)
            
    # Check if file exists
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
        
    # Check if file created during task (Anti-gaming)
    if task_result.get('file_created_during_task', False):
        score += 5
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("Warning: File timestamp indicates it was not created during this session")

    # 2. Load and Parse FHIR Bundle
    fhir_bundle = {}
    temp_fhir_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(task_result.get('output_path'), temp_fhir_file.name)
        with open(temp_fhir_file.name, 'r') as f:
            fhir_bundle = json.load(f)
        score += 10
        feedback_parts.append("Valid JSON")
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Invalid JSON file: {e}"}
    finally:
        if os.path.exists(temp_fhir_file.name):
            os.unlink(temp_fhir_file.name)

    # 3. Check Bundle Structure
    if fhir_bundle.get('resourceType') == 'Bundle' and isinstance(fhir_bundle.get('entry'), list):
        score += 10
        feedback_parts.append("Valid Bundle structure")
    else:
        return {"passed": False, "score": score, "feedback": "Invalid FHIR structure (not a Bundle or missing entries)"}
        
    entries = fhir_bundle.get('entry', [])
    bundle_count = len(entries)
    db_count = task_result.get('db_patient_count', 0)
    
    # 4. Check Count Accuracy
    if abs(bundle_count - db_count) == 0:
        score += 10
        feedback_parts.append(f"Patient count exact match ({bundle_count})")
    elif abs(bundle_count - db_count) <= 2:
        score += 5
        feedback_parts.append(f"Patient count close ({bundle_count} vs {db_count})")
    else:
        feedback_parts.append(f"Patient count mismatch (Found {bundle_count}, Expected {db_count})")

    # 5. Check Data Integrity for Test Patients
    # We index the bundle by (Family, Given) for lookup
    bundle_patients = {}
    for entry in entries:
        res = entry.get('resource', {})
        if res.get('resourceType') != 'Patient':
            continue
            
        try:
            name_obj = res.get('name', [{}])[0]
            family = name_obj.get('family', '').upper()
            given = name_obj.get('given', [''])[0]
            key = (family, given)
            bundle_patients[key] = res
        except:
            continue
            
    # Verify each expected patient
    patients_found = 0
    fields_correct = 0
    total_fields_checked = 0
    
    for expected in expected_patients:
        key = (expected['family'].upper(), expected['given'])
        if key in bundle_patients:
            patients_found += 1
            res = bundle_patients[key]
            
            # Check Gender (10 pts total weight distributed)
            total_fields_checked += 1
            if res.get('gender') == expected['gender']:
                fields_correct += 1
                
            # Check DOB (10 pts total weight)
            total_fields_checked += 1
            if res.get('birthDate') == expected['birthDate']:
                fields_correct += 1
                
            # Check Address/City (10 pts total weight)
            total_fields_checked += 1
            addr = res.get('address', [{}])[0]
            if expected['city'].upper() in addr.get('city', '').upper() and \
               expected['postalCode'] in addr.get('postalCode', ''):
                fields_correct += 1
                
            # Check NIR Identifier (10 pts total weight)
            total_fields_checked += 1
            identifiers = res.get('identifier', [])
            nir_found = False
            for ident in identifiers:
                if expected['nir'] in ident.get('value', '').replace(' ', ''):
                    nir_found = True
                    break
            if nir_found:
                fields_correct += 1
                
        else:
            feedback_parts.append(f"Missing patient: {expected['family']} {expected['given']}")

    # Calculate Data Score (Max 65 pts)
    # 15 pts for finding all patients
    if len(expected_patients) > 0:
        found_ratio = patients_found / len(expected_patients)
        score += int(15 * found_ratio)
        
    # 50 pts for correct fields
    if total_fields_checked > 0:
        field_ratio = fields_correct / total_fields_checked
        score += int(50 * field_ratio)
        
    feedback_parts.append(f"Data verification: {patients_found}/{len(expected_patients)} patients found, {fields_correct}/{total_fields_checked} fields correct")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }