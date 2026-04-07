#!/usr/bin/env python3
"""
Verifier for C-CDA Allergy Extraction Task.
Verifies that the agent created a channel that correctly transforms
dynamically injected XML data into the required JSON format.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ccda_allergy_extraction(traj, env_info, task_info):
    """
    Verify the C-CDA extraction task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected values from metadata (backup) or task_result.json (dynamic)
    metadata = task_info.get('metadata', {})
    
    # Copy result file
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
    
    # 1. Channel Creation & Deployment (20 pts)
    channel_found = result.get('channel_found', False)
    channel_status = result.get('channel_status', 'UNKNOWN')
    
    if channel_found:
        score += 10
        feedback_parts.append(f"Channel found: {result.get('channel_name')}")
        
        if channel_status in ['STARTED', 'DEPLOYED', 'RUNNING']:
            score += 10
            feedback_parts.append(f"Channel is {channel_status}")
        else:
            feedback_parts.append(f"Channel status is {channel_status} (expected STARTED)")
    else:
        feedback_parts.append("No matching channel found")

    # 2. Output File Generation (20 pts)
    output_found = result.get('output_file_found', False)
    raw_content = result.get('output_content_raw', '')
    
    if output_found:
        score += 20
        feedback_parts.append("Output file generated from test input")
    else:
        feedback_parts.append("No output file generated from test input")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. JSON Validation & Data Correctness (60 pts)
    try:
        if not raw_content:
            raise ValueError("Empty content")
            
        data = json.loads(raw_content)
        score += 10 # Valid JSON
        feedback_parts.append("Output is valid JSON")
        
        # Check Patient Name (15 pts)
        expected_patient = result.get('expected_patient', 'VerifyBot User')
        actual_patient = data.get('patient', '')
        
        # Allow partial match (e.g. "VerifyBot User" vs "VerifyBot") or different order
        if expected_patient.lower() in actual_patient.lower():
            score += 15
            feedback_parts.append("Patient name correct")
        else:
            feedback_parts.append(f"Patient name mismatch (Expected: {expected_patient}, Got: {actual_patient})")
            
        # Check Allergies (35 pts)
        allergies = data.get('allergies', [])
        if isinstance(allergies, list) and len(allergies) > 0:
            allergy = allergies[0]
            
            # Substance
            expected_substance = result.get('expected_substance', 'Kryptonite')
            actual_substance = allergy.get('substance', '')
            if expected_substance.lower() in actual_substance.lower():
                score += 15
                feedback_parts.append("Allergy substance correct")
            else:
                feedback_parts.append(f"Substance mismatch (Expected: {expected_substance}, Got: {actual_substance})")
                
            # Reaction
            expected_reaction = result.get('expected_reaction', 'Weakness')
            actual_reaction = allergy.get('reaction', '')
            if expected_reaction.lower() in actual_reaction.lower():
                score += 10
                feedback_parts.append("Allergy reaction correct")
            else:
                feedback_parts.append(f"Reaction mismatch (Expected: {expected_reaction}, Got: {actual_reaction})")
                
            # Status (check existence)
            if 'status' in allergy:
                score += 10
                feedback_parts.append("Allergy status present")
        else:
            feedback_parts.append("Allergy list missing or empty")

    except json.JSONDecodeError:
        feedback_parts.append("Output file is not valid JSON")
    except Exception as e:
        feedback_parts.append(f"Error parsing verification data: {e}")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }