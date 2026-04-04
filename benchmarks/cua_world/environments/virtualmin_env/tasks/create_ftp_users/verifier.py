#!/usr/bin/env python3
"""
Verifier for create_ftp_users task.

Verifies:
1. alice_dev exists with correct Home, Shell, FTP=Yes, Email=No
2. dave_uploads exists with correct Home, Shell, FTP=Yes, Email=No
3. Uploads directory was created
4. Anti-gaming: Users created during task window
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_ftp_users(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_users = metadata.get('users', [])
    
    # Files to retrieve
    result_json_path = "/tmp/task_result.json"
    virtualmin_dump_path = "/tmp/virtualmin_users.txt"
    
    # Temp files for local analysis
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_dump = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Copy files
        copy_from_env(result_json_path, temp_result.name)
        
        # Determine if we need to copy the dump file
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
            
        dump_path_in_env = result_data.get('virtualmin_users_dump_path')
        if dump_path_in_env:
            copy_from_env(dump_path_in_env, temp_dump.name)
            with open(temp_dump.name, 'r') as f:
                virtualmin_dump = f.read()
        else:
            virtualmin_dump = ""
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_dump.name):
            os.unlink(temp_dump.name)

    # =========================================================
    # Scoring Logic
    # =========================================================
    score = 0
    max_score = 100
    feedback_lines = []
    
    # Parse passwd entries from JSON
    # Format: alice_dev:x:1001:1001:Alice Chen:/home/acmecorp/public_html:/bin/false
    passwd_raw = result_data.get('passwd_entries', '')
    passwd_entries = {}
    for entry in passwd_raw.split(';'):
        if not entry.strip(): continue
        parts = entry.split(':')
        if len(parts) >= 7:
            passwd_entries[parts[0]] = {
                'uid': parts[2],
                'gid': parts[3],
                'real_name': parts[4],
                'home': parts[5],
                'shell': parts[6]
            }

    # Parse Virtualmin dump for capabilities (FTP/Email)
    # The dump is multiline text blocks.
    # We look for "Unix username: alice_dev" then scan following lines until next user.
    def get_user_caps(username, dump_text):
        caps = {'ftp': False, 'email': False}
        in_user_block = False
        for line in dump_text.splitlines():
            if line.strip().startswith("Unix username:"):
                current_user = line.split(":")[1].strip()
                if current_user == username:
                    in_user_block = True
                else:
                    in_user_block = False
            
            if in_user_block:
                # Check for capabilities
                # Output format varies slightly but usually:
                # "FTP access: Yes" or "Allow FTP: Yes"
                if "FTP" in line and "Yes" in line:
                    caps['ftp'] = True
                # "Email access: Yes" or "Mailbox: Yes"
                if ("Email" in line or "Mail" in line) and "Yes" in line:
                    caps['email'] = True
        return caps

    # Verify each user
    for target in expected_users:
        username = target['username']
        u_score = 0
        u_feedback = []
        
        # 1. Check Existence (System level)
        if username in passwd_entries:
            u_score += 10
            u_feedback.append(f"User {username} exists")
            
            entry = passwd_entries[username]
            
            # 2. Check Home Directory
            if entry['home'] == target['home']:
                u_score += 10
                u_feedback.append("Home directory correct")
            else:
                u_feedback.append(f"Home directory incorrect (found {entry['home']})")
                
            # 3. Check Shell
            if entry['shell'] in target['shell_options']:
                u_score += 10
                u_feedback.append("Shell restriction correct")
            else:
                u_feedback.append(f"Shell incorrect (found {entry['shell']})")
                
            # 4. Check Capabilities (Virtualmin level)
            caps = get_user_caps(username, virtualmin_dump)
            
            # FTP should be True
            if caps['ftp'] == target['ftp']:
                u_score += 10
                u_feedback.append("FTP enabled")
            else:
                u_feedback.append("FTP not enabled")
                
            # Email should be False
            if caps['email'] == target['email']:
                u_score += 10
                u_feedback.append("Email disabled")
            else:
                u_feedback.append("Email incorrectly enabled")
                
        else:
            u_feedback.append(f"User {username} NOT found")
        
        score += u_score
        feedback_lines.append(f"{username}: {', '.join(u_feedback)}")

    # =========================================================
    # Anti-Gaming & Environment Checks
    # =========================================================
    
    # 1. Directory creation check for dave_uploads
    if result_data.get('uploads_dir_exists'):
        score += 0  # No explicit points, but required for Home dir check implicitly
    else:
        feedback_lines.append("WARNING: Uploads directory physically missing")

    # 2. Users created count delta
    initial_count = int(result_data.get('initial_user_count', 0))
    final_count = int(result_data.get('final_user_count', 0))
    if final_count >= initial_count + 2:
        feedback_lines.append("User count increased correctly")
    else:
        feedback_lines.append("User count did not increase by 2")

    # 3. Modification during task
    if not result_data.get('passwd_modified_during_task'):
        score = 0
        feedback_lines.append("FAIL: /etc/passwd not modified during task (anti-gaming)")

    # Normalize score
    # Total possible raw score: 50 per user * 2 users = 100
    final_score = min(100, score)
    passed = final_score >= 80  # Require high accuracy for config tasks
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_lines)
    }