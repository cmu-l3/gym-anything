#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_forensic_hash_correlation_access(traj, env_info, task_info):
    """
    Verify the forensic hash correlation task.
    
    Criteria:
    1. 'extracted_flag.txt' exists.
    2. Content of 'extracted_flag.txt' matches ground truth exactly.
    3. Volume is mounted (optional but good indicator of correct process).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Files to copy
    result_remote_path = "/tmp/task_result.json"
    truth_remote_path = "/tmp/ground_truth_flag.txt"
    
    score = 0
    feedback_parts = []
    
    # Temp files for local storage
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_truth = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Copy Result JSON
        try:
            copy_from_env(result_remote_path, temp_result.name)
            with open(temp_result.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
            
        # Copy Ground Truth
        try:
            copy_from_env(truth_remote_path, temp_truth.name)
            with open(temp_truth.name, 'r') as f:
                ground_truth = f.read().strip()
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load ground truth: {e}"}

        # --- Verification Logic ---
        
        # 1. Flag Existence (20 pts)
        if result_data.get("flag_exists"):
            score += 20
            feedback_parts.append("Flag file found")
        else:
            feedback_parts.append("Flag file NOT found")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
            
        # 2. Content Match (50 pts)
        extracted = result_data.get("extracted_content", "").strip()
        if extracted == ground_truth:
            score += 50
            feedback_parts.append("Flag content matches ground truth")
        else:
            feedback_parts.append(f"Flag content incorrect. Expected '{ground_truth}', got '{extracted}'")
            
        # 3. Volume Mounted (20 pts)
        if result_data.get("volume_mounted_veracrypt") or result_data.get("volume_mounted_fs"):
            score += 20
            feedback_parts.append("Volume mounted successfully")
        else:
            feedback_parts.append("Volume not currently mounted (agent may have dismounted, acceptable if flag extracted)")
            
        # 4. Anti-Gaming: File Created During Task (10 pts)
        if result_data.get("file_created_during_task"):
            score += 10
            feedback_parts.append("Flag extracted during task session")
        else:
            feedback_parts.append("Flag file has old timestamp or invalid creation time")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        # Cleanup
        for f in [temp_result.name, temp_truth.name]:
            if os.path.exists(f):
                os.unlink(f)

    passed = (score >= 80) # Requires flag match + existence + anti-gaming check
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }