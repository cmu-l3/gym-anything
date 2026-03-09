#!/usr/bin/env python3
"""Verifier for live_forensic_analysis task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_algo_name(name):
    """Normalize algorithm names to handle case/minor variations."""
    if not name:
        return ""
    name = name.lower().strip()
    # Map common variations if necessary, but exact match usually expected for forensics
    return name

def verify_live_forensic_analysis(traj, env_info, task_info):
    """
    Verify the forensic analysis report.
    
    Scoring:
    - Report exists and is valid JSON: 10 pts
    - Correct Container Path: 30 pts
    - Correct Encryption Algorithm: 10 pts
    - Correct Hash Algorithm: 10 pts
    - Correct File Count: 20 pts
    - Volume Successfully Dismounted: 20 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # Load Result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Check Report Existence/Validity (10 pts)
    if not result.get("report_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Forensic report file not found at /home/ga/Documents/forensic_report.json"
        }
    
    score += 10
    feedback_parts.append("Report file found")

    ground_truth = result.get("ground_truth", {})
    agent_report = result.get("agent_report", {})
    
    # Check if agent_report is actually a dict (valid JSON parsed)
    if not isinstance(agent_report, dict) or not agent_report:
        feedback_parts.append("Report file contained invalid JSON")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Check Container Path (30 pts)
    gt_path = ground_truth.get("container_path", "UNKNOWN")
    agent_path = agent_report.get("container_path", "").strip()
    
    if agent_path == gt_path:
        score += 30
        feedback_parts.append("Correct container path identified")
    else:
        feedback_parts.append(f"Incorrect path. Expected: {gt_path}, Got: {agent_path}")

    # 3. Check Encryption Algorithm (10 pts)
    gt_algo = normalize_algo_name(ground_truth.get("encryption_algorithm", ""))
    agent_algo = normalize_algo_name(agent_report.get("encryption_algorithm", ""))
    
    if gt_algo == agent_algo:
        score += 10
        feedback_parts.append(f"Correct Algo ({gt_algo})")
    else:
        feedback_parts.append(f"Incorrect Algo. Expected: {gt_algo}, Got: {agent_algo}")

    # 4. Check Hash Algorithm (10 pts)
    gt_hash = normalize_algo_name(ground_truth.get("hash_algorithm", ""))
    agent_hash = normalize_algo_name(agent_report.get("hash_algorithm", ""))
    
    if gt_hash == agent_hash:
        score += 10
        feedback_parts.append(f"Correct Hash ({gt_hash})")
    else:
        feedback_parts.append(f"Incorrect Hash. Expected: {gt_hash}, Got: {agent_hash}")

    # 5. Check File Count (20 pts)
    gt_count = ground_truth.get("file_count", -1)
    agent_count = agent_report.get("file_count", -2)
    
    if agent_count == gt_count:
        score += 20
        feedback_parts.append(f"Correct File Count ({gt_count})")
    else:
        feedback_parts.append(f"Incorrect File Count. Expected: {gt_count}, Got: {agent_count}")

    # 6. Check Dismount Status (20 pts)
    still_mounted = result.get("volume_still_mounted", True)
    if not still_mounted:
        score += 20
        feedback_parts.append("Volume successfully dismounted")
    else:
        feedback_parts.append("Volume was NOT dismounted")

    # Final Pass/Fail
    # Threshold 80: Needs Path + Crypto + some other correct, or all correct but maybe forgot dismount
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }