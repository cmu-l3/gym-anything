#!/usr/bin/env python3
"""
Verifier for Create Hash Verifier task.

Evaluates multi-file Talon architecture generation and programmatic Python 
file I/O execution via a simulated trigger. Uses multiple signals to score.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_hash_verifier(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Export logic saves to C:\temp in the Windows container
        try:
            copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        except Exception:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # CRITERION 1: File Structure Present (15 points)
    # ================================================================
    files_present = sum([result.get("py_exists", False), result.get("talon_exists", False), result.get("list_exists", False)])
    score += files_present * 5
    
    if files_present == 3:
        feedback_parts.append("All 3 Talon files created")
    else:
        feedback_parts.append(f"Missing {3 - files_present} Talon files")

    # ================================================================
    # CRITERION 2: Syntax and References Check (15 points)
    # ================================================================
    py_content = result.get("py_content", "") or ""
    talon_content = result.get("talon_content", "") or ""
    list_content = result.get("list_content", "") or ""
    
    if "Module" in py_content and "verify_evidence" in py_content:
        score += 5
    if "verify evidence" in talon_content and "user.evidence_id" in talon_content:
        score += 5
    if "list: user.evidence_id" in list_content and "alpha" in list_content:
        score += 5

    # ================================================================
    # CRITERION 3: Runtime Log Audit Check (30 points)
    # ================================================================
    audit_log = result.get("audit_log_content", "") or ""
    error_log = result.get("error_log_content", "") or ""
    
    if error_log:
        feedback_parts.append(f"Runtime error during simulated execution: {error_log[:100]}...")
        
    if not result.get("audit_log_exists"):
        feedback_parts.append("Audit log NOT created (Python action failed or not triggered)")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    lines = [line.strip() for line in audit_log.strip().split('\n') if line.strip()]
    if len(lines) >= 3:
        score += 20
        feedback_parts.append("Audit log successfully written")
    elif len(lines) > 0:
        score += 10
        feedback_parts.append(f"Audit log partially written ({len(lines)} entries)")
        
    # ================================================================
    # CRITERION 4: Hashes & State Detection Logic (30 points)
    # ================================================================
    alpha_ok = False
    bravo_ok = False
    charlie_ok = False
    format_ok = True
    
    for line in lines:
        parts = [p.strip() for p in line.split(',')]
        if len(parts) >= 5:
            ev_id = parts[1]
            status = parts[-1]
            
            if ev_id == "alpha" and status == "VERIFIED":
                alpha_ok = True
            if ev_id == "bravo" and status == "VERIFIED":
                bravo_ok = True
            if ev_id == "charlie" and status == "CORRUPTED":
                charlie_ok = True
        else:
            format_ok = False
            
    if format_ok and len(lines) > 0:
        score += 10
        feedback_parts.append("Audit log CSV structure correct")
        
    if alpha_ok and bravo_ok and charlie_ok:
        score += 20
        feedback_parts.append("Hashes computed and corrupted state successfully detected")
    else:
        feedback_parts.append("Hash comparison logic or CSV output values incorrect")

    # ================================================================
    # CRITERION 5: Trajectory Verification via VLM (10 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = "Did the agent use a text editor to write Python and Talon configuration files? Respond in JSON format: {\"edited_files\": true/false}"
                vlm_result = query_vlm(prompt=prompt, images=images)
                if vlm_result.get("success") and vlm_result.get("parsed", {}).get("edited_files"):
                    score += 10
                    feedback_parts.append("VLM visual proof confirmed")
        except Exception as e:
            logger.warning(f"VLM check skipped: {e}")

    passed = score >= 80 and result.get("audit_log_exists")
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }