#!/usr/bin/env python3
"""
Verifier for transfer_misfiled_document task.
Verifies that the file was moved from Case A to Case B and content is preserved.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_transfer_misfiled_document(traj, env_info, task_info):
    """
    Verify the document transfer task.
    
    Criteria:
    1. Document uploaded to Target Case (40 pts)
    2. Document deleted from Source Case (30 pts)
    3. Filename is preserved (15 pts)
    4. Content hash matches original (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # Check Target Case (40 pts)
    if result.get('target_has_file', False):
        score += 40
        feedback_parts.append("Document found in target case")
    else:
        feedback_parts.append("Document NOT found in target case")
        
    # Check Source Case (30 pts)
    if result.get('source_cleared', False):
        score += 30
        feedback_parts.append("Document removed from source case")
    else:
        feedback_parts.append("Document still present in source case")
        
    # Check Filename (15 pts)
    target_name = result.get('target_filename', '')
    expected_name = result.get('expected_filename', 'medical_evaluation_confidential.pdf')
    
    # Loose match (contains expected name)
    if expected_name in target_name:
        score += 15
        feedback_parts.append(f"Filename correct ({target_name})")
    elif result.get('target_has_file', False):
        feedback_parts.append(f"Filename incorrect (got '{target_name}', expected '{expected_name}')")
        
    # Check Hash (15 pts)
    if result.get('hash_match', False):
        score += 15
        feedback_parts.append("File content integrity verified")
    elif result.get('target_has_file', False):
        feedback_parts.append("File content mismatch (hash verification failed)")
        
    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }