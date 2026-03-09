#!/usr/bin/env python3
"""
Verifier for refactor_inheritance_to_delegation task.

Checks:
1. File Modification: Targeted file must be modified during the task.
2. Inheritance Removal: Class should no longer extend LegacySocket.
3. Composition Added: Class should have a field of type LegacySocket.
4. Delegation Implemented: 'sendData' and 'close' methods should be present.
5. Encapsulation Enforced: 'connectInsecure' and 'getRawStream' should be absent.
6. VLM Verification: Confirm use of IntelliJ refactoring tools via trajectory.
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_inheritance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    score = 0
    feedback_parts = []
    
    # --- Step 1: Read Result JSON ---
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

    content = result.get('file_content', '')
    file_modified = result.get('file_modified', False)
    compile_success = result.get('compile_success', 'unknown')

    if not file_modified:
        return {"passed": False, "score": 0, "feedback": "File was not modified during the task."}

    # --- Step 2: Static Code Analysis (60 points) ---
    
    # 2.1 Inheritance Removal (15 pts)
    # Check for "extends LegacySocket"
    if re.search(r'class\s+SecureDataTransmitter\s+extends\s+LegacySocket', content):
        feedback_parts.append("Fail: Class still extends LegacySocket")
    else:
        score += 15
        feedback_parts.append("Pass: Inheritance removed")

    # 2.2 Composition Added (15 pts)
    # Check for field "LegacySocket <name>"
    if re.search(r'(private|protected|public)\s+(final\s+)?LegacySocket\s+\w+', content):
        score += 15
        feedback_parts.append("Pass: Delegate field added")
    else:
        feedback_parts.append("Fail: No LegacySocket field found")

    # 2.3 Required Delegated Methods (15 pts)
    # Must have sendData and close
    has_send = 'void sendData' in content
    has_close = 'void close' in content
    if has_send and has_close:
        score += 15
        feedback_parts.append("Pass: Required methods (sendData, close) present")
    elif has_send or has_close:
        score += 7
        feedback_parts.append("Partial: Some required methods missing")
    else:
        feedback_parts.append("Fail: Required delegated methods missing")

    # 2.4 Forbidden Methods Hidden (15 pts)
    # Must NOT have connectInsecure or getRawStream
    has_unsafe = ('connectInsecure' in content) or ('getRawStream' in content)
    if not has_unsafe:
        score += 15
        feedback_parts.append("Pass: Unsafe methods successfully removed/hidden")
    else:
        feedback_parts.append("Fail: Unsafe methods (connectInsecure/getRawStream) still present")

    # --- Step 3: Compilation Check (10 points) ---
    if compile_success == "true":
        score += 10
        feedback_parts.append("Pass: File compiles successfully")
    else:
        feedback_parts.append("Info: File did not compile independently")

    # --- Step 4: VLM Trajectory Verification (30 points) ---
    # We want to see the "Replace Inheritance with Delegation" dialog or similar UI interaction
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        
        prompt = """
        You are verifying an IntelliJ IDEA task. The user should have used the "Refactor" menu, specifically "Replace Inheritance with Delegation".
        
        Look at the sequence of images. Do you see:
        1. The "Replace Inheritance with Delegation" dialog box? (It typically lists methods to delegate and options for the delegate field).
        2. The user selecting methods like 'sendData' or 'close' in a dialog?
        3. Code changing from 'extends' to having a field?
        
        Respond JSON:
        {
            "refactoring_dialog_seen": true/false,
            "dialog_details": "string description",
            "code_transformation_visible": true/false
        }
        """
        
        try:
            vlm_result = query_vlm(images=frames, prompt=prompt)
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('refactoring_dialog_seen', False):
                    vlm_score += 20
                    feedback_parts.append("VLM: Refactoring dialog observed")
                elif parsed.get('code_transformation_visible', False):
                    vlm_score += 10
                    feedback_parts.append("VLM: Code transformation observed")
            else:
                # Fallback if VLM fails but code is correct
                if score >= 50: 
                    vlm_score += 10
                    feedback_parts.append("VLM skipped, trusting code result")
        except Exception as e:
            logger.warning(f"VLM error: {e}")
            
    score += vlm_score

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }