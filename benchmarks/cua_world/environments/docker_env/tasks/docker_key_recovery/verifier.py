#!/usr/bin/env python3
"""
Verifier for docker_key_recovery task.

Scores based on:
1. Identifying correct key fragments (partial credit)
2. Assembling the full key correctly
3. Providing a methodology report that mentions the containers

Correct Key Construction (Alphabetical order of containers):
keyvault-cache:     c4d81f56
keyvault-proxy:     e9027a4d
keyvault-scheduler: a2f4d709
keyvault-storage:   7f3a9b2e
keyvault-worker:    5b6c8e31

Full Key: c4d81f56-e9027a4d-a2f4d709-7f3a9b2e-5b6c8e31
"""

import json
import tempfile
import os
import base64
import logging

logger = logging.getLogger(__name__)

# Ground Truth
FRAGMENTS = {
    "cache": "c4d81f56",
    "proxy": "e9027a4d",
    "scheduler": "a2f4d709",
    "storage": "7f3a9b2e",
    "worker": "5b6c8e31"
}

CORRECT_KEY = "c4d81f56-e9027a4d-a2f4d709-7f3a9b2e-5b6c8e31"

def verify_docker_key_recovery(traj, env_info, task_info):
    """Verify the recovered key and report."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/key_recovery_result.json", temp_path)
            with open(temp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_path):
                os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback_parts = []
    
    # Extract data
    submitted_key = result.get("submitted_key", "").strip()
    key_exists = result.get("key_exists", False)
    key_fresh = result.get("key_created_during_task", False)
    
    report_exists = result.get("report_exists", False)
    report_fresh = result.get("report_created_during_task", False)
    report_b64 = result.get("report_content_b64", "")
    
    try:
        report_content = base64.b64decode(report_b64).decode('utf-8', errors='ignore').lower()
    except:
        report_content = ""

    # === Criterion 1: Key Fragments Found (15 pts each = 75 pts) ===
    # We check if fragments exist in the submitted string, even if order is wrong
    
    if not key_exists:
        feedback_parts.append("No key file found.")
    elif not key_fresh:
        feedback_parts.append("Key file exists but was not created/modified during task.")
    else:
        # Check cache fragment
        if FRAGMENTS["cache"] in submitted_key:
            score += 15
            feedback_parts.append("Found cache fragment")
        
        # Check proxy fragment
        if FRAGMENTS["proxy"] in submitted_key:
            score += 15
            feedback_parts.append("Found proxy fragment")
            
        # Check scheduler fragment
        if FRAGMENTS["scheduler"] in submitted_key:
            score += 15
            feedback_parts.append("Found scheduler fragment")
            
        # Check storage fragment
        if FRAGMENTS["storage"] in submitted_key:
            score += 15
            feedback_parts.append("Found storage fragment")
            
        # Check worker fragment
        if FRAGMENTS["worker"] in submitted_key:
            score += 15
            feedback_parts.append("Found worker fragment")

    # === Criterion 2: Correct Assembly (15 pts) ===
    if submitted_key == CORRECT_KEY and key_fresh:
        score += 15
        feedback_parts.append("Full key assembled correctly (+15)")
    elif key_exists and key_fresh:
        feedback_parts.append("Key assembly incorrect or incomplete")

    # === Criterion 3: Methodology Report (10 pts) ===
    # Must mention all 5 container names/roles
    if report_exists and report_fresh:
        mentions = 0
        container_terms = ["cache", "proxy", "scheduler", "storage", "worker"]
        for term in container_terms:
            if term in report_content:
                mentions += 1
        
        if mentions >= 5:
            score += 10
            feedback_parts.append("Report covers all containers (+10)")
        elif mentions >= 3:
            score += 5
            feedback_parts.append(f"Report covers {mentions}/5 containers (+5)")
        else:
            feedback_parts.append("Report content insufficient")
    else:
        feedback_parts.append("Report missing or not new")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }