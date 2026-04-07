#!/usr/bin/env python3
"""
Verification script for openice_data_model_fhir_mapping task.
"""

import json
import sys
import os
import tempfile
import re

def verify_openice_data_model_fhir_mapping(traj, env_info, task_info):
    """
    Verify the OpenICE data model extraction and FHIR mapping task.
    """
    # 1. Setup - Get copy function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Get metadata from task info
    metadata = task_info.get('metadata', {})
    expected_ice_types = metadata.get('expected_ice_types', [
        "Numeric", "SampleArray", "AlarmLimit", "InfusionObjective", 
        "DeviceIdentity", "Patient", "InfusionStatus"
    ])
    expected_field_names = metadata.get('expected_field_names', [
        "unique_device_identifier", "metric_id", "value", "unit_id", 
        "manufacturer", "model"
    ])
    expected_fhir_resources = metadata.get('expected_fhir_resources', [
        "Observation", "Device", "Patient", "DeviceMetric"
    ])

    # 3. Load result from environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 4. Parse Results
    task_start = int(result.get("task_start_time", 0))
    dd = result.get("data_dictionary", {})
    fhir = result.get("fhir_mapping", {})
    device_created = result.get("device_created", False)
    window_increased = result.get("window_increased", False)

    score = 0
    feedback_parts = []
    
    # Gate Condition check
    if not dd.get("exists") and not fhir.get("exists") and not device_created:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "GATE CONDITION FAILED: No files created and no device interaction detected."
        }

    # --- Criterion 1: Data Dictionary File (10 pts) ---
    dd_content = dd.get("content") or ""
    if dd.get("exists"):
        dd_size = dd.get("size_bytes", 0)
        dd_mtime = int(dd.get("mtime", 0))
        
        if dd_mtime > task_start and dd_size >= 500:
            score += 10
            feedback_parts.append("Data dictionary file valid (size/time)")
        elif dd_mtime > task_start:
            score += 5
            feedback_parts.append("Data dictionary file exists but small")
        else:
            feedback_parts.append("Data dictionary file pre-dates task start")
    else:
        feedback_parts.append("Data dictionary file missing")

    # --- Criterion 2: Data Types Found (20 pts) ---
    found_types = 0
    if dd_content:
        for typename in expected_ice_types:
            if re.search(r'\b' + re.escape(typename) + r'\b', dd_content, re.IGNORECASE):
                found_types += 1
    
    if found_types >= 5:
        score += 20
        feedback_parts.append(f"Excellent type coverage ({found_types} types)")
    elif found_types >= 3:
        score += 20
        feedback_parts.append(f"Good type coverage ({found_types} types)")
    elif found_types >= 1:
        score += 10
        feedback_parts.append(f"Minimal type coverage ({found_types} types)")
    else:
        feedback_parts.append("No valid OpenICE data types found in dictionary")

    # --- Criterion 3: Field Names Found (20 pts) ---
    found_fields = 0
    if dd_content:
        for field in expected_field_names:
            if re.search(r'\b' + re.escape(field) + r'\b', dd_content, re.IGNORECASE):
                found_fields += 1
                
    if found_fields >= 6:
        score += 20
        feedback_parts.append(f"Excellent field detail ({found_fields} fields)")
    elif found_fields >= 4:
        score += 20
        feedback_parts.append(f"Good field detail ({found_fields} fields)")
    elif found_fields >= 2:
        score += 10
        feedback_parts.append(f"Minimal field detail ({found_fields} fields)")
    else:
        feedback_parts.append("No valid field names found in dictionary")

    # --- Criterion 4: FHIR Mapping File (10 pts) ---
    fhir_content = fhir.get("content") or ""
    if fhir.get("exists"):
        fhir_size = fhir.get("size_bytes", 0)
        fhir_mtime = int(fhir.get("mtime", 0))
        
        if fhir_mtime > task_start and fhir_size >= 400:
            score += 10
            feedback_parts.append("FHIR mapping file valid (size/time)")
        elif fhir_mtime > task_start:
            score += 5
            feedback_parts.append("FHIR mapping file exists but small")
        else:
            feedback_parts.append("FHIR mapping file pre-dates task")
    else:
        feedback_parts.append("FHIR mapping file missing")

    # --- Criterion 5: FHIR Resources Found (15 pts) ---
    found_resources = 0
    if fhir_content:
        for res in expected_fhir_resources:
            if re.search(r'\b' + re.escape(res) + r'\b', fhir_content, re.IGNORECASE):
                found_resources += 1
    
    if found_resources >= 4:
        score += 15
        feedback_parts.append(f"Excellent FHIR resource mapping ({found_resources} resources)")
    elif found_resources >= 2:
        score += 15
        feedback_parts.append(f"Good FHIR resource mapping ({found_resources} resources)")
    elif found_resources >= 1:
        score += 7
        feedback_parts.append(f"Minimal FHIR resource mapping ({found_resources} resources)")
    else:
        feedback_parts.append("No valid FHIR resources found")

    # --- Criterion 6: Cross-Consistency (10 pts) ---
    # Does the FHIR document mention OpenICE types that we know about?
    cross_refs = 0
    if fhir_content:
        for typename in expected_ice_types:
            if re.search(r'\b' + re.escape(typename) + r'\b', fhir_content, re.IGNORECASE):
                cross_refs += 1
    
    if cross_refs >= 2:
        score += 10
        feedback_parts.append("Cross-document consistency valid")
    elif cross_refs == 1:
        score += 5
        feedback_parts.append("Weak cross-document consistency")
    
    # --- Criterion 7: Device Created (10 pts) ---
    if device_created:
        score += 10
        feedback_parts.append("Simulated device creation verified")
    elif window_increased:
        score += 5
        feedback_parts.append("Potential device creation (window count increased)")
    else:
        feedback_parts.append("No evidence of device creation")

    # --- Criterion 8: Formatting/Structure (5 pts) ---
    has_structure = False
    if dd_content and (re.search(r'^#', dd_content, re.MULTILINE) or re.search(r'^-', dd_content, re.MULTILINE)):
        has_structure = True
        score += 5
        feedback_parts.append("Good formatting detected")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "dd_types": found_types,
            "dd_fields": found_fields,
            "fhir_resources": found_resources,
            "cross_refs": cross_refs
        }
    }