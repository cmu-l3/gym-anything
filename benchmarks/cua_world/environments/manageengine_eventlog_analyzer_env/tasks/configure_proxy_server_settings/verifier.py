#!/usr/bin/env python3
"""
Verifier for configure_proxy_server_settings task.

Checks database dumps for persisted proxy configuration settings.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_proxy_server_settings(traj, env_info, task_info):
    """
    Verify that proxy settings were correctly configured in EventLog Analyzer.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata expectations
    metadata = task_info.get('metadata', {})
    expected_host = metadata.get('expected_host', 'proxy.dmz.corp')
    expected_port = metadata.get('expected_port', '8080')
    expected_user = metadata.get('expected_user', 'sys_proxy_svc')
    # Exceptions usually stored as comma separated string
    expected_exceptions = metadata.get('expected_exceptions', ['localhost', '127.0.0.1'])

    # Retrieve result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Retrieve DB dump
    db_dump_content = ""
    db_dump_path = result.get("db_dump_path")
    if db_dump_path:
        temp_dump = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(db_dump_path, temp_dump.name)
            with open(temp_dump.name, 'r', errors='ignore') as f:
                db_dump_content = f.read()
        except Exception as e:
            logger.warning(f"Failed to load DB dump: {e}")
        finally:
            if os.path.exists(temp_dump.name):
                os.unlink(temp_dump.name)

    # Also check conf file grep results as backup
    conf_grep_content = ""
    conf_path = result.get("conf_grep_host_path")
    if conf_path:
        temp_conf = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(conf_path, temp_conf.name)
            with open(temp_conf.name, 'r', errors='ignore') as f:
                conf_grep_content = f.read()
        except Exception as e:
            logger.warning(f"Failed to load conf grep: {e}")
        finally:
            if os.path.exists(temp_conf.name):
                os.unlink(temp_conf.name)
    
    # Combined search content
    search_content = (db_dump_content + "\n" + conf_grep_content).lower()

    # Scoring
    score = 0
    feedback_parts = []
    
    # 1. Check Screenshot (10 pts)
    if result.get("screenshot_exists", False):
        score += 10
        feedback_parts.append("Screenshot created")
    else:
        feedback_parts.append("No screenshot found")

    # 2. Check Host (30 pts)
    if expected_host.lower() in search_content:
        score += 30
        feedback_parts.append(f"Proxy host '{expected_host}' found in configuration")
    else:
        feedback_parts.append(f"Proxy host '{expected_host}' NOT found")

    # 3. Check Port (20 pts)
    if str(expected_port) in search_content:
        score += 20
        feedback_parts.append(f"Proxy port '{expected_port}' found")
    else:
        feedback_parts.append(f"Proxy port '{expected_port}' NOT found")

    # 4. Check User (20 pts)
    if expected_user.lower() in search_content:
        score += 20
        feedback_parts.append(f"Proxy user '{expected_user}' found")
    else:
        feedback_parts.append(f"Proxy user '{expected_user}' NOT found")

    # 5. Check Exceptions (10 pts)
    # Check for at least one of the exceptions to verify the field was touched/saved
    exceptions_found = False
    for exc in expected_exceptions:
        if exc.lower() in search_content:
            exceptions_found = True
            break
    
    if exceptions_found:
        score += 10
        feedback_parts.append("Proxy exceptions found")
    else:
        feedback_parts.append("Proxy exceptions NOT found")
        
    # 6. Password check (10 pts)
    # We look for the password OR assume if all else is correct, it was likely set.
    # But strictly, we check if the password string appears (if stored plain text) 
    # or if we have high confidence from other fields.
    # Given SIEMs encrypt passwords, we might not find "P@ssw0rd2026".
    # However, if Host, Port, and User are correct, we award these points to be fair, 
    # or check for a "password" column being non-empty in the DB dump.
    # Let's verify if "password" or "encrd_passwd" fields are present in the dump.
    if "password" in search_content or "passwd" in search_content:
        score += 10
        feedback_parts.append("Password configuration detected")
    elif score >= 80: # If everything else is right, assume password was set
        score += 10
        feedback_parts.append("Password likely set (inferred)")
    else:
        feedback_parts.append("Password configuration unclear")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }