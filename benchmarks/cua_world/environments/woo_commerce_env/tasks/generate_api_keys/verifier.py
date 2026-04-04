#!/usr/bin/env python3
"""
Verifier for Generate API Keys task.

Scoring System (100 points total):
1. API Key Record Exists in DB (25 pts)
2. Permissions are Read/Write (15 pts)
3. User is Admin (5 pts)
4. Credentials File Exists (10 pts)
5. File contains valid key formats (10 pts)
6. File key matches DB record (Truncated Check) (5 pts)
7. Live API Authentication Test Passed (15 pts)
8. Description matches (Implicit in DB lookup, +15 if found)

Total: 100 points
Pass Threshold: 65 points AND Record Exists
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_api_keys(traj, env_info, task_info):
    """
    Verify that valid REST API keys were generated and saved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # 1. DB Record Check (45 pts total)
    if result.get('db_record_found', False):
        score += 25  # Base points for creating the key
        score += 15  # Implicitly checked description in export script query
        feedback_parts.append("API key record created in database")
        
        # Permissions check
        perms = result.get('db_permissions', '')
        if perms == 'read_write':
            score += 15
            feedback_parts.append("Permissions set correctly (Read/Write)")
        else:
            feedback_parts.append(f"Incorrect permissions: {perms}")
            
        # User check
        user_id = result.get('db_user_id', '')
        if user_id == '1': # Admin is usually ID 1
            score += 5
            feedback_parts.append("Assigned to admin user")
    else:
        feedback_parts.append("No API key with description 'ShipStation Integration' found")

    # 2. File Check (25 pts total)
    if result.get('file_exists', False):
        score += 10
        feedback_parts.append("Credentials file created")
        
        has_ck = result.get('file_has_ck', False)
        has_cs = result.get('file_has_cs', False)
        
        if has_ck and has_cs:
            score += 10
            feedback_parts.append("File contains key and secret")
        elif has_ck or has_cs:
            score += 5
            feedback_parts.append("File contains incomplete credentials")
            
        # Truncated match check
        if result.get('truncated_match', False):
            score += 5
            feedback_parts.append("Saved key matches database record")
        elif has_ck:
            feedback_parts.append("Saved key does not match database record")
    else:
        feedback_parts.append("Credentials file NOT found")

    # 3. Live Test (15 pts)
    if result.get('api_test_success', False):
        score += 15
        feedback_parts.append("Live API authentication successful")
    elif result.get('file_exists', False) and result.get('file_has_ck', False):
        feedback_parts.append("Live API authentication failed")

    passed = (score >= 65) and result.get('db_record_found', False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }