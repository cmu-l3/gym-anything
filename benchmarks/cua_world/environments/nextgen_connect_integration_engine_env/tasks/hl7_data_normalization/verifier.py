#!/usr/bin/env python3
"""
Verifier for hl7_data_normalization task.
Checks if the channel normalizes Phone, DOB, and Gender correctly.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hl7_normalization(traj, env_info, task_info):
    """
    Verify the HL7 data normalization task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expectations = metadata.get('expectations', {})
    
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
    
    # 1. Channel Configuration (35 points)
    if result.get('channel_id'):
        score += 8
        feedback_parts.append("Channel 'Data_Quality_Normalizer' created.")
        
        if result.get('has_transformer', False):
            score += 8
            feedback_parts.append("Transformer detected.")
        else:
            feedback_parts.append("WARNING: No transformer logic detected in channel.")
            
        status = result.get('channel_status', 'UNKNOWN')
        if status in ['STARTED', 'DEPLOYED', 'RUNNING']:
            score += 5
            feedback_parts.append(f"Channel is {status}.")
            
        stats_received = result.get('stats_received', 0)
        if stats_received >= 4:
            score += 14  # Full points if all 4 processed
            feedback_parts.append(f"Processed {stats_received} messages.")
        elif stats_received > 0:
            score += 5
            feedback_parts.append(f"Processed {stats_received} messages (expected 4).")
    else:
        feedback_parts.append("FAIL: Channel 'Data_Quality_Normalizer' not found.")
        
    # 2. Output File verification (65 points)
    output_files = result.get('output_files', [])
    valid_outputs = [f for f in output_files if 'error' not in f and 'sender' in f]
    
    if len(valid_outputs) >= 4:
        score += 13 # Base points for having output files
        feedback_parts.append(f"Found {len(valid_outputs)} valid output files.")
    elif len(valid_outputs) > 0:
        score += 5
        feedback_parts.append(f"Found {len(valid_outputs)} output files (expected 4).")
    else:
        feedback_parts.append("FAIL: No valid output files found in /tmp/normalized_output/.")
        
    # Check normalization accuracy
    # We map sender (HOSP_A, etc.) to expected values
    sender_map = {
        'HOSP_A': 'hospital_a',
        'HOSP_B': 'hospital_b',
        'HOSP_C': 'hospital_c',
        'HOSP_D': 'hospital_d'
    }
    
    normalization_score = 0
    max_norm_score = 52 # 13 points per file (5 phone + 5 DOB + 3 Gender)
    
    # Track which hospitals we've seen to avoid double counting if files duplicated
    seen_senders = set()
    
    for file_data in valid_outputs:
        sender = file_data.get('sender', '')
        if sender not in sender_map:
            continue
            
        if sender in seen_senders:
            continue # Skip duplicates
        seen_senders.add(sender)
            
        key = sender_map[sender]
        expected = expectations.get(key, {})
        actual = file_data.get('pid', {})
        
        file_score = 0
        file_feedback = []
        
        # Phone Check (5 pts)
        if actual.get('phone') == expected.get('phone'):
            file_score += 5
        else:
            file_feedback.append(f"Phone mismatch {sender}: '{actual.get('phone')}' != '{expected.get('phone')}'")
            
        # DOB Check (5 pts)
        if actual.get('dob') == expected.get('dob'):
            file_score += 5
        else:
            file_feedback.append(f"DOB mismatch {sender}: '{actual.get('dob')}' != '{expected.get('dob')}'")
            
        # Gender Check (3 pts)
        if actual.get('gender') == expected.get('gender'):
            file_score += 3
        else:
            file_feedback.append(f"Gender mismatch {sender}: '{actual.get('gender')}' != '{expected.get('gender')}'")
            
        normalization_score += file_score
        if file_feedback:
             feedback_parts.extend(file_feedback)

    score += normalization_score
    
    # Final cleanup
    feedback_parts.append(f"Normalization Score: {normalization_score}/{max_norm_score}")
    
    passed = score >= 65 and normalization_score >= 10 # Require at least some normalization success
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback_parts)
    }