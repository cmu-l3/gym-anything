#!/usr/bin/env python3
"""
Verifier for Create Concept Source Task.

Checks:
1. Concept Source exists in OpenMRS (40 pts)
2. Name matches 'ICD-11' exactly (15 pts)
3. Description contains required keywords (20 pts)
4. HL7 Code is 'I11' (10 pts)
5. Total count of concept sources increased (Anti-gaming) (15 pts)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_concept_source(traj, env_info, task_info):
    """
    Verify the creation of the ICD-11 concept source.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'ICD-11')
    expected_hl7 = metadata.get('expected_hl7_code', 'I11')
    
    # Description keywords to check
    desc_keywords = ["International Classification", "Diseases", "11"]

    score = 0
    max_score = 100
    feedback_parts = []
    
    try:
        # Retrieve result file
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
        
        source_data = result.get('source_data', {})
        found = source_data.get('found', False)
        
        # Criterion 1: Source Found (40 pts)
        if found:
            score += 40
            feedback_parts.append("Concept Source created")
        else:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "FAILED: ICD-11 concept source not found in OpenMRS."
            }

        # Criterion 2: Name Exact Match (15 pts)
        actual_name = source_data.get('name', '')
        if actual_name.strip() == expected_name:
            score += 15
            feedback_parts.append("Name matches exactly")
        else:
            feedback_parts.append(f"Name mismatch (Expected: {expected_name}, Got: {actual_name})")

        # Criterion 3: Description Quality (20 pts)
        actual_desc = source_data.get('description', '') or ""
        keywords_found = [kw for kw in desc_keywords if kw.lower() in actual_desc.lower()]
        
        if len(keywords_found) == len(desc_keywords):
            score += 20
            feedback_parts.append("Description contains all key terms")
        elif len(keywords_found) > 0:
            partial = int(20 * (len(keywords_found) / len(desc_keywords)))
            score += partial
            feedback_parts.append(f"Description partially correct ({len(keywords_found)}/{len(desc_keywords)} terms)")
        else:
            feedback_parts.append("Description missing required info")

        # Criterion 4: HL7 Code (10 pts)
        actual_hl7 = source_data.get('hl7Code', '')
        if actual_hl7 == expected_hl7:
            score += 10
            feedback_parts.append("HL7 Code correct")
        else:
            feedback_parts.append(f"HL7 Code incorrect (Expected: {expected_hl7}, Got: {actual_hl7})")

        # Criterion 5: Anti-gaming / Count Increase (15 pts)
        initial_count = result.get('initial_count', 0)
        current_count = result.get('current_count', 0)
        
        if current_count > initial_count:
            score += 15
            feedback_parts.append("Source count increased")
        else:
            feedback_parts.append("Warning: Source count did not increase (did you overwrite an existing one?)")

        # Pass Threshold
        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed with error: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }