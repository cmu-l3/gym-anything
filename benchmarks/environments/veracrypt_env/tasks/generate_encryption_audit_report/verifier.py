#!/usr/bin/env python3
"""
Verifier for generate_encryption_audit_report task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_algo(s):
    """Normalize algorithm name for comparison (case-insensitive, remove spaces/dashes)."""
    if not isinstance(s, str):
        return ""
    # Common mappings
    s = s.strip().upper()
    s = s.replace(" ", "").replace("_", "").replace("-", "")
    return s

def verify_encryption_audit_report(traj, env_info, task_info):
    """
    Verify the encryption audit report task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_volumes = metadata.get('expected_volumes', {})
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Files to retrieve
    task_result_path = "/tmp/task_result.json"
    report_path = "/home/ga/Documents/encryption_audit_report.json"
    
    # 1. Retrieve task execution result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(task_result_path, temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 2. Check report existence and creation time (Anti-gaming)
    if not task_result.get('report_exists', False):
        return {"passed": False, "score": 0, "feedback": "Audit report file not found"}
        
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Report file exists but was not created during this task session"}
        
    score += 10
    feedback_parts.append("Report created during task")

    # 3. Retrieve and parse the actual report content
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    report_valid = False
    report_data = {}
    
    try:
        copy_from_env(report_path, temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_data = json.load(f)
        report_valid = True
        score += 10
        feedback_parts.append("Valid JSON format")
    except Exception as e:
        feedback_parts.append(f"Invalid JSON content: {str(e)[:50]}...")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
            
    if not report_valid:
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # 4. Analyze report content
    volumes_reported = report_data.get("volumes", [])
    if not isinstance(volumes_reported, list):
        feedback_parts.append("Invalid 'volumes' structure in JSON")
    else:
        # Check that we have entries for all expected volumes
        found_count = 0
        correct_entries = 0
        
        # Helper to find a reported volume by path match
        for vol_name, ground_truth in expected_volumes.items():
            found_vol = None
            for reported in volumes_reported:
                if isinstance(reported, dict) and vol_name in reported.get("path", ""):
                    found_vol = reported
                    break
            
            if found_vol:
                found_count += 1
                
                # Check Encryption Algorithm
                rep_enc = normalize_algo(found_vol.get("encryption_algorithm", ""))
                gt_encs = [normalize_algo(x) for x in ground_truth.get("encryption", [])]
                enc_correct = rep_enc in gt_encs
                
                # Check Hash Algorithm
                rep_hash = normalize_algo(found_vol.get("hash_algorithm", ""))
                gt_hashes = [normalize_algo(x) for x in ground_truth.get("hash", [])]
                hash_correct = rep_hash in gt_hashes
                
                if enc_correct and hash_correct:
                    correct_entries += 1
                    score += 20  # 20 points per fully correct volume
                    feedback_parts.append(f"{vol_name}: Correct")
                else:
                    # Partial credit logic could go here, or simple feedback
                    details = []
                    if not enc_correct: details.append(f"Enc '{rep_enc}'!='{gt_encs[0]}'")
                    if not hash_correct: details.append(f"Hash '{rep_hash}'!='{gt_hashes[0]}'")
                    feedback_parts.append(f"{vol_name}: Incorrect ({', '.join(details)})")
                    # Give partial points for partial correctness
                    if enc_correct: score += 10
                    if hash_correct: score += 10
            else:
                feedback_parts.append(f"{vol_name}: Missing from report")

        if found_count == 3:
            score += 15
            feedback_parts.append("All volumes reported")
        else:
            feedback_parts.append(f"{found_count}/3 volumes reported")

    # 5. Check if volumes were dismounted (Cleanup)
    mounted_count = task_result.get("mounted_volumes_count", 0)
    if mounted_count == 0:
        score += 5
        feedback_parts.append("Cleanup successful (all dismounted)")
    else:
        feedback_parts.append(f"Cleanup failed ({mounted_count} volumes still mounted)")

    # Final scoring
    # Max possible: 10 (exists) + 10 (valid) + 15 (all 3 found) + 60 (3 * 20 correct details) + 5 (cleanup) = 100
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }