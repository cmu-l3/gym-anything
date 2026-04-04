#!/usr/bin/env python3
"""
Verifier for regenerate_api_keys task.

Verification Logic:
1. Write API Key Changed in DB (15 pts)
2. Read API Key Changed in DB (15 pts)
3. Output file exists (10 pts)
4. Output file format correct (10 pts)
5. Output file Write Key matches DB (15 pts)
6. Output file Read Key matches DB (15 pts)
7. Old Write Key Revoked (10 pts)
8. Old Read Key Revoked (10 pts)

Pass Threshold: 70 points
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_regenerate_api_keys(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    feedback = []
    
    # Extract Data
    old_keys = result.get("old_keys", {})
    curr_keys = result.get("current_db_keys", {})
    agent_file = result.get("agent_file", {})

    old_write = old_keys.get("write", "").strip()
    old_read  = old_keys.get("read", "").strip()
    
    curr_write = curr_keys.get("write", "").strip()
    curr_read  = curr_keys.get("read", "").strip()
    
    file_exists = agent_file.get("exists", False)
    file_write = agent_file.get("write_key_content", "").strip()
    file_read  = agent_file.get("read_key_content", "").strip()

    # 1. Write API Key Changed in DB (15 pts)
    if curr_write and old_write and curr_write != old_write:
        score += 15
        feedback.append("Write API key rotated successfully.")
    else:
        feedback.append(f"Write API key NOT rotated (Current: {curr_write}, Old: {old_write}).")

    # 2. Read API Key Changed in DB (15 pts)
    if curr_read and old_read and curr_read != old_read:
        score += 15
        feedback.append("Read API key rotated successfully.")
    else:
        feedback.append("Read API key NOT rotated.")

    # 3. Output file exists (10 pts)
    if file_exists:
        score += 10
        feedback.append("Output file found.")
    else:
        feedback.append("Output file '/home/ga/new_apikeys.txt' NOT found.")

    # 4. File format correct (10 pts)
    # Basic check: keys are 32 chars hex
    hex_pattern = re.compile(r'^[0-9a-fA-F]{32}$')
    format_ok = False
    if file_exists:
        if hex_pattern.match(file_write) and hex_pattern.match(file_read):
            score += 10
            format_ok = True
            feedback.append("Output file format correct.")
        else:
            feedback.append(f"Output file format incorrect or keys invalid (Write: {file_write}, Read: {file_read}).")

    # 5. File Write Key matches DB (15 pts)
    if file_exists and format_ok:
        if file_write.lower() == curr_write.lower():
            score += 15
            feedback.append("File Write Key matches Database.")
        else:
            feedback.append("File Write Key does NOT match Database.")

    # 6. File Read Key matches DB (15 pts)
    if file_exists and format_ok:
        if file_read.lower() == curr_read.lower():
            score += 15
            feedback.append("File Read Key matches Database.")
        else:
            feedback.append("File Read Key does NOT match Database.")

    # 7. Old Write Key Revoked (10 pts)
    # If rotation happened in DB, this is implicitly true, but we check the API call result
    if not old_keys.get("write_still_works", True):
        score += 10
        feedback.append("Old Write Key successfully revoked.")
    else:
        feedback.append("Old Write Key still works!")

    # 8. Old Read Key Revoked (10 pts)
    if not old_keys.get("read_still_works", True):
        score += 10
        feedback.append("Old Read Key successfully revoked.")
    else:
        feedback.append("Old Read Key still works!")

    # Check Pass Threshold
    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }