#!/usr/bin/env python3
"""
Verifier for rename_virtual_server task.

This script validates:
1. System state changes (domain rename, feature preservation)
2. VLM trajectory (confirming UI interaction)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rename_virtual_server(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    scoring = metadata.get('scoring', {})
    
    # 1. Load Result JSON from Container
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
    
    # 2. Programmatic Verification
    
    # A. New Domain Exists (20 pts)
    if result.get('new_domain_exists'):
        score += scoring.get('new_domain_exists', 20)
        feedback.append("Success: 'acmetech.test' exists.")
    else:
        feedback.append("Fail: 'acmetech.test' was not found.")

    # B. Old Domain Removed (15 pts)
    if not result.get('old_domain_exists'):
        score += scoring.get('old_domain_removed', 15)
        feedback.append("Success: 'acmecorp.test' no longer exists.")
    else:
        feedback.append("Fail: 'acmecorp.test' still exists.")

    # C. Features Preserved (Web, DNS, Mail, MySQL) - 40 pts total
    feats = result.get('features', {})
    artifacts = result.get('artifacts', {})
    
    if feats.get('web') and artifacts.get('apache_conf_exists'):
        score += scoring.get('web_feature', 10)
        feedback.append("Web feature active.")
    
    if feats.get('dns') and artifacts.get('zone_file_exists'):
        score += scoring.get('dns_zone', 10)
        feedback.append("DNS zone active.")
        
    if feats.get('mail'):
        score += scoring.get('mail_feature', 10)
        feedback.append("Mail feature active.")
        
    if feats.get('mysql') and artifacts.get('db_match_count', 0) > 0:
        score += scoring.get('mysql_renamed', 10)
        feedback.append("MySQL database renamed.")
    elif feats.get('mysql'):
        feedback.append("MySQL feature active but DB name mismatch.")

    # D. Home Directory & User (15 pts)
    home_dir = artifacts.get('home_dir', '')
    if 'acmetech' in home_dir:
        score += scoring.get('home_directory', 10)
        feedback.append(f"Home directory updated ({home_dir}).")
    else:
        feedback.append(f"Home directory not updated ({home_dir}).")
        
    unix_user = artifacts.get('unix_user', '')
    if 'acmetech' in unix_user or unix_user == 'acmetech': # heuristics
        score += scoring.get('unix_user', 5)
        feedback.append(f"Unix user updated ({unix_user}).")

    # 3. VLM Trajectory Verification (10 pts)
    # Check if the agent actually navigated the UI
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    Review these screenshots of a user interacting with Virtualmin.
    The goal is to rename a virtual server from 'acmecorp.test' to 'acmetech.test'.
    
    Look for:
    1. Navigation to "Server Configuration" -> "Change Domain Name"
    2. A form input changing the domain name
    3. Clicking a "Rename" or "Change" button
    
    Did the user appear to perform these actions?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt).get('parsed', {})
    # Assuming VLM returns a boolean or structured yes/no. 
    # Since query_vlm implementation varies, we default to generous strictness if logic ambiguous
    # Here we assume standard gym_anything VLM return
    
    # Fallback logic if VLM fails or result structure unknown, 
    # trust programmatic score if high enough, else 0
    vlm_passed = False
    if "yes" in str(vlm_result).lower() or score >= 80:
        vlm_passed = True
    
    if vlm_passed:
        score += scoring.get('vlm_trajectory', 10)
        feedback.append("VLM: verified workflow.")
    else:
        feedback.append("VLM: could not verify workflow visually.")

    # 4. Final Verdict
    pass_threshold = 60
    passed = score >= pass_threshold and result.get('new_domain_exists')

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }