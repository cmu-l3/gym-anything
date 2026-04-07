#!/usr/bin/env python3
"""
Verifier for HL7 De-identification Pipeline Task.
Checks:
1. Channel creation and deployment
2. Output file existence and timestamp
3. Content verification (PHI removal and Replacement insertion)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hl7_deidentification_pipeline(traj, env_info, task_info):
    """
    Verify the de-identification pipeline.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata
    metadata = task_info.get('metadata', {})
    forbidden_strings = metadata.get('forbidden_strings', [])
    required_strings = metadata.get('required_strings', [])
    min_files = metadata.get('min_files', 3)

    # Load result
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
    
    # 1. Channel Status (20 points)
    channel_exists = result.get('channel_exists', False)
    is_deployed = result.get('is_deployed', False)
    
    if channel_exists:
        score += 10
        feedback_parts.append("Channel 'PHI_Deidentification_Pipeline' created.")
    else:
        feedback_parts.append("Channel 'PHI_Deidentification_Pipeline' NOT found.")

    if is_deployed:
        score += 10
        feedback_parts.append("Channel is deployed/started.")
    else:
        feedback_parts.append("Channel is NOT deployed/started.")

    # 2. Output Files Existence (15 points)
    output_count = result.get('output_file_count', 0)
    files_new = result.get('files_created_during_task', False)
    
    if output_count >= min_files:
        score += 15
        feedback_parts.append(f"Found {output_count} output files.")
    elif output_count > 0:
        score += 5
        feedback_parts.append(f"Found {output_count} output files (expected {min_files}).")
    else:
        feedback_parts.append("No output files found.")

    # Anti-gaming check
    if output_count > 0 and not files_new:
        feedback_parts.append("WARNING: Output files have old timestamps (pre-task).")
        score = 0 # Reset score if anti-gaming detected
        return {"passed": False, "score": 0, "feedback": "Anti-gaming: Output files were not created during the task."}

    # 3. Content Verification (65 points total)
    output_files = result.get('output_files', [])
    
    if not output_files:
        feedback_parts.append("No content to analyze.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback_parts)}

    # Check PHI Removal (30 points)
    # We check ALL files. If ANY file contains forbidden strings, we penalize.
    phi_found = []
    for f in output_files:
        content = f.get('content', '')
        for s in forbidden_strings:
            if s in content:
                phi_found.append(f"Found '{s}' in {f.get('filename')}")
    
    if not phi_found:
        score += 30
        feedback_parts.append("PHI Verification: No forbidden data found (Names, SSNs, Addresses removed).")
    else:
        # Partial penalty? No, PHI leakage is critical failure.
        feedback_parts.append(f"PHI LEAKAGE DETECTED: {', '.join(phi_found[:3])}...")

    # Check Replacement Strings (25 points)
    # "ANONYMOUS^PATIENT" and "REMOVED^^REMOVED^XX^00000" must exist in ALL files
    missing_replacements = []
    files_with_replacements = 0
    
    for f in output_files:
        content = f.get('content', '')
        has_all = True
        for s in required_strings:
            if s not in content:
                has_all = False
                missing_replacements.append(f"Missing '{s}' in {f.get('filename')}")
        if has_all:
            files_with_replacements += 1

    if files_with_replacements == output_count:
        score += 25
        feedback_parts.append("De-identification markers correctly applied.")
    elif files_with_replacements > 0:
        score += 10
        feedback_parts.append(f"De-identification markers found in {files_with_replacements}/{output_count} files.")
    else:
        feedback_parts.append("De-identification markers NOT found.")

    # Check HL7 Structure (10 points)
    # Basic check: MSH and PID segments present
    valid_structure_count = 0
    for f in output_files:
        content = f.get('content', '')
        if "MSH|" in content and "PID|" in content:
            valid_structure_count += 1
            
    if valid_structure_count == output_count:
        score += 10
        feedback_parts.append("Output files preserve HL7 structure.")
    else:
        feedback_parts.append("Some output files are missing MSH/PID segments.")

    # Final logic
    passed = (score >= 70) and (not phi_found) and (files_with_replacements > 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }