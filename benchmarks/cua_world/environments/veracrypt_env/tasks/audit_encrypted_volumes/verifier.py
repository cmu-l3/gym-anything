#!/usr/bin/env python3
"""
Verifier for audit_encrypted_volumes task.
Checks if the agent correctly identified encryption properties and files,
formatted the JSON report correctly, and cleaned up by dismounting.
"""

import json
import os
import tempfile
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_algo(s):
    """Normalize algorithm names for comparison (case-insensitive, remove dashes/spaces)."""
    if not s:
        return ""
    return s.strip().lower().replace("-", "").replace(" ", "")

def verify_audit_encrypted_volumes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Ground Truth
    metadata = task_info.get('metadata', {})
    gt_volumes = metadata.get('volumes', {})
    
    # Helper to check if a specific volume report is correct
    def check_volume_entry(entry, gt_key):
        gt = gt_volumes.get(gt_key)
        if not gt:
            return 0, []
        
        entry_score = 0
        feedback = []
        
        # Check Encryption Algo
        user_enc = normalize_algo(entry.get('encryption_algorithm', ''))
        gt_enc = normalize_algo(gt['encryption'])
        if user_enc == gt_enc:
            entry_score += 15
            feedback.append(f"{gt_key}: Encryption correct")
        else:
            feedback.append(f"{gt_key}: Encryption incorrect (Got: {entry.get('encryption_algorithm')}, Expected: {gt['encryption']})")
            
        # Check Hash Algo
        user_hash = normalize_algo(entry.get('hash_algorithm', ''))
        gt_hash = normalize_algo(gt['hash'])
        # Allow some variations like sha256 vs sha-256 (handled by normalize)
        if user_hash == gt_hash:
            entry_score += 10
            feedback.append(f"{gt_key}: Hash correct")
        else:
            feedback.append(f"{gt_key}: Hash incorrect (Got: {entry.get('hash_algorithm')}, Expected: {gt['hash']})")
            
        # Check Files
        user_files = set(entry.get('files', []))
        gt_files = set(gt['files'])
        if user_files == gt_files:
            entry_score += 10
            feedback.append(f"{gt_key}: File list correct")
        else:
            feedback.append(f"{gt_key}: File list mismatch")
            
        return entry_score, feedback

    # Load Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Report Exists & Timestamp (Anti-gaming)
    if not result.get('report_exists'):
        return {"passed": False, "score": 0, "feedback": "Audit report file not found at expected path."}
    
    if not result.get('report_created_during_task'):
        feedback_parts.append("Warning: Report file timestamp indicates it wasn't created during this task run.")
        # We might penalize heavily or fail, but let's just allow it for now if content is perfect
        # usually 0 points for pre-existing file
        return {"passed": False, "score": 0, "feedback": "Report file was not created during the task (anti-gaming check failed)."}

    report_content = result.get('report_content', {})
    if "error" in report_content:
        return {"passed": False, "score": 0, "feedback": "Report file is not valid JSON."}
    
    score += 10 # Valid JSON exists
    feedback_parts.append("Valid JSON report found")

    # Criterion 2: Audit Date
    if report_content.get('audit_date'):
        score += 5
        feedback_parts.append("Audit date present")
    else:
        feedback_parts.append("Audit date missing")

    # Criterion 3: Volume Entries
    reported_volumes = report_content.get('volumes', [])
    if not isinstance(reported_volumes, list):
         feedback_parts.append("Invalid 'volumes' format (expected list)")
    else:
        # Create a map for easier lookup by filename
        vol_map = {v.get('filename'): v for v in reported_volumes}
        
        # Check Finance Volume
        if 'dept_finance.hc' in vol_map:
            sub_score, sub_feed = check_volume_entry(vol_map['dept_finance.hc'], 'dept_finance.hc')
            score += sub_score
            feedback_parts.extend(sub_feed)
        else:
            feedback_parts.append("dept_finance.hc missing from report")

        # Check HR Volume
        if 'dept_hr.hc' in vol_map:
            sub_score, sub_feed = check_volume_entry(vol_map['dept_hr.hc'], 'dept_hr.hc')
            score += sub_score
            feedback_parts.extend(sub_feed)
        else:
            feedback_parts.append("dept_hr.hc missing from report")

    # Criterion 4: Dismounted
    if result.get('volumes_dismounted'):
        score += 15
        feedback_parts.append("Volumes correctly dismounted")
    else:
        feedback_parts.append("Volumes were left mounted")

    # Final tally
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }