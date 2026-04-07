#!/usr/bin/env python3
"""
Verifier for Configure Database Connection task.

Verifies:
1. Backup file exists and matches original state (Integrity Check)
2. Configuration file was updated with correct Host and Port
3. File modification timestamp indicates work was done
"""

import json
import os
import base64
import tempfile
import configparser
import io
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_database_connection(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Backup (50 points total)
    # --------------------------------
    backup_exists = result.get("backup_exists", False)
    backup_hash = result.get("backup_hash", "")
    original_hash = result.get("original_hash", "")

    if backup_exists:
        score += 30
        feedback_parts.append("Backup file created")
        
        if backup_hash and original_hash and backup_hash == original_hash:
            score += 20
            feedback_parts.append("Backup integrity verified (matches original)")
        else:
            feedback_parts.append("Backup file content does NOT match original state")
    else:
        feedback_parts.append("Backup file NOT found (Manager.ini.bak)")

    # 2. Verify Configuration Update (50 points total)
    # ----------------------------------------------
    ini_exists = result.get("ini_exists", False)
    ini_content_b64 = result.get("ini_content_base64", "")
    
    host_correct = False
    port_correct = False

    if ini_exists and ini_content_b64:
        try:
            ini_content = base64.b64decode(ini_content_b64).decode('utf-8', errors='ignore')
            
            # Use ConfigParser for robust checking, but handle potential lack of sections gracefully
            # MedinTux INI usually has [Connexion]
            config = configparser.ConfigParser(strict=False)
            try:
                config.read_string(ini_content)
                
                # Check [Connexion] section
                if "Connexion" in config:
                    host_val = config["Connexion"].get("host", "").strip()
                    port_val = config["Connexion"].get("port", "").strip()
                    
                    if host_val == "192.168.10.50":
                        host_correct = True
                    else:
                        feedback_parts.append(f"Incorrect Host: found '{host_val}'")
                        
                    if port_val == "3307":
                        port_correct = True
                    else:
                        feedback_parts.append(f"Incorrect Port: found '{port_val}'")
                else:
                    # Fallback to simple string parsing if section missing or malformed
                    lower_content = ini_content.lower()
                    if "host=192.168.10.50" in lower_content or "host = 192.168.10.50" in lower_content:
                        host_correct = True
                    if "port=3307" in lower_content or "port = 3307" in lower_content:
                        port_correct = True
                        
            except Exception as e:
                feedback_parts.append(f"INI parsing error: {str(e)}")
                # Last resort fallback
                if "192.168.10.50" in ini_content: host_correct = True
                if "3307" in ini_content: port_correct = True

        except Exception as e:
            feedback_parts.append("Failed to decode INI content")

    if host_correct:
        score += 25
        feedback_parts.append("Host updated correctly")
    
    if port_correct:
        score += 25
        feedback_parts.append("Port updated correctly")

    # Anti-gaming check: File modified during task
    if not result.get("ini_modified_during_task", False):
        feedback_parts.append("WARNING: Manager.ini timestamp not updated during task")
        # We don't zero the score here because they might have edited it very quickly or preserved timestamp
        # but usually this indicates "do nothing" if content is also wrong.

    passed = (score >= 75)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }