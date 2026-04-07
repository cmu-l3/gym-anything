#!/usr/bin/env python3
"""
Verifier for Analyze Managed Crash Dump task.

MULTI-CRITERIA SCORING:
1. Target file exists and created during task (10 pts)
2. Exception Type correctly identified (20 pts)
3. Transaction ID precisely extracted from local heap memory (35 pts)
4. Retry Count precisely extracted from local heap memory (35 pts)
* VLM Trajectory Check: Agent must have actually utilized Visual Studio interface
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_managed_crash_dump(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Load exported state from the environment
        copy_from_env("C:\\workspace\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Unpack JSON Data
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)
    file_content = result.get('file_content', '')
    gt_tx_id = str(result.get('ground_truth_transaction_id', ''))
    gt_retry = str(result.get('ground_truth_retry_count', ''))
    gt_exception = result.get('ground_truth_exception', '')

    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Target file 'investigation_result.txt' not found."}
    
    if not created_during_task:
        feedback_parts.append("Warning: File timestamp indicates it was not created during task bounds.")
    
    score += 10
    feedback_parts.append("File exists")

    # Regular Expressions to parse strict formatting
    ext_match = re.search(r'(?i)Exception:\s*([a-zA-Z0-9_.]+)', file_content)
    tx_match = re.search(r'(?i)TransactionId:\s*(\d+)', file_content)
    retry_match = re.search(r'(?i)RetryCount:\s*(\d+)', file_content)

    extracted_exception = ext_match.group(1).strip() if ext_match else ""
    extracted_tx = tx_match.group(1).strip() if tx_match else ""
    extracted_retry = retry_match.group(1).strip() if retry_match else ""

    # Exception Check
    if gt_exception.lower() in extracted_exception.lower() and extracted_exception:
        score += 20
        feedback_parts.append("Exception identified correctly")
    else:
        feedback_parts.append(f"Exception mismatch (Expected '{gt_exception}', got '{extracted_exception}')")

    # Transaction ID check (Requires inspecting the dump heap locals)
    tx_correct = False
    if extracted_tx == gt_tx_id:
        score += 35
        tx_correct = True
        feedback_parts.append(f"TransactionId precisely extracted ({extracted_tx})")
    else:
        feedback_parts.append(f"TransactionId mismatch (Expected '{gt_tx_id}', got '{extracted_tx}')")

    # Retry count check
    retry_correct = False
    if extracted_retry == gt_retry:
        score += 35
        retry_correct = True
        feedback_parts.append(f"RetryCount precisely extracted ({extracted_retry})")
    else:
        feedback_parts.append(f"RetryCount mismatch (Expected '{gt_retry}', got '{extracted_retry}')")

    # Anti-gaming: Use trajectory to confirm Visual Studio was actually utilized
    query_vlm = env_info.get('query_vlm')
    vs_used = False
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """
            Look at these images sampled from an agent's desktop interaction sequence.
            Did the agent use Visual Studio 2022 to debug a crash dump? 
            Look for evidence such as the 'Minidump File Summary' tab, the orange debugging status bar, 
            the Call Stack window, or the Locals window.
            Respond strictly in JSON format: {"used_vs": true} or {"used_vs": false}
            """
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('used_vs', False):
                    vs_used = True
                    feedback_parts.append("VLM confirmed Visual Studio debugging interaction")
                else:
                    feedback_parts.append("VLM did NOT detect Visual Studio debugging interface")
            else:
                # If VLM fails, give benefit of the doubt
                vs_used = True
        else:
            vs_used = True
    else:
        vs_used = True

    # Final Pass Condition
    passed = tx_correct and retry_correct and output_exists and vs_used and created_during_task

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }