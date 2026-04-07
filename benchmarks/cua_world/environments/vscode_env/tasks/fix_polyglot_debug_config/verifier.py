#!/usr/bin/env python3
"""
Verifier for the Polyglot Debug Config task.

Checks:
1. tasks.json contains a background task "Start Redis"
2. launch.json contains configurations "Python API" and "Node Worker"
3. launch.json contains a compound configuration "Full Stack" referencing them
4. api/main.py has the race condition fixed (db.commit() before r.publish())
5. worker/processor.js has the null reference bug fixed (checks for null before .length)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def strip_comments(json_string):
    """Strip // and /* */ comments from JSON string so it can be parsed natively."""
    json_string = re.sub(r'/\*.*?\*/', '', json_string, flags=re.DOTALL)
    json_string = re.sub(r'//.*', '', json_string)
    return json_string

def verify_polyglot_debug(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/polyglot_debug_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback = []
    
    tasks_content = result.get('tasks.json')
    launch_content = result.get('launch.json')
    main_py = result.get('api/main.py', '')
    processor_js = result.get('worker/processor.js', '')
    
    tasks_json = {}
    if tasks_content:
        try:
            tasks_json = json.loads(strip_comments(tasks_content))
        except json.JSONDecodeError:
            feedback.append("[-] tasks.json is invalid JSON")
    else:
        feedback.append("[-] tasks.json not found")
        
    launch_json = {}
    if launch_content:
        try:
            launch_json = json.loads(strip_comments(launch_content))
        except json.JSONDecodeError:
            feedback.append("[-] launch.json is invalid JSON")
    else:
        feedback.append("[-] launch.json not found")
        
    # Criterion 1: Check tasks.json (15 pts)
    has_redis_task = False
    if 'tasks' in tasks_json:
        for t in tasks_json['tasks']:
            if t.get('label') == 'Start Redis' and 'redis-server' in t.get('command', ''):
                has_redis_task = True
                break
    
    if has_redis_task:
        score += 15
        feedback.append("[+] Valid 'Start Redis' task found")
    else:
        feedback.append("[-] 'Start Redis' task missing or incorrectly configured")
        
    # Criterion 2: Check launch.json single configs (15 pts)
    has_python_api = False
    has_node_worker = False
    has_full_stack = False
    
    if 'configurations' in launch_json:
        for c in launch_json['configurations']:
            if c.get('name') == 'Python API':
                has_python_api = True
            if c.get('name') == 'Node Worker':
                has_node_worker = True
                
    if has_python_api and has_node_worker:
        score += 15
        feedback.append("[+] 'Python API' and 'Node Worker' launch configs found")
    else:
        feedback.append("[-] Missing 'Python API' or 'Node Worker' launch config")
        
    # Criterion 3: Check compound config (20 pts)
    if 'compounds' in launch_json:
        for c in launch_json['compounds']:
            if c.get('name') == 'Full Stack':
                configs = c.get('configurations', [])
                if 'Python API' in configs and 'Node Worker' in configs:
                    has_full_stack = True
                    break
                    
    if has_full_stack:
        score += 20
        feedback.append("[+] Compound configuration 'Full Stack' found linking both services")
    else:
        feedback.append("[-] Compound configuration 'Full Stack' missing or incorrect")
        
    # Criterion 4: Check Race Condition Fix (25 pts)
    if main_py:
        # Extract process_upload body specifically so we don't catch the commit in setup_db()
        process_upload_body = re.search(r'def process_upload.*?conn\.close\(\)', main_py, re.DOTALL)
        if process_upload_body:
            body = process_upload_body.group(0)
            commit_match = re.search(r'conn\.commit\(\)', body)
            publish_match = re.search(r'r\.publish\(', body)
            
            if commit_match and publish_match:
                if commit_match.start() < publish_match.start():
                    score += 25
                    feedback.append("[+] Race condition fixed: db.commit() happens before r.publish()")
                else:
                    feedback.append("[-] Race condition remains: r.publish() happens before db.commit()")
            else:
                feedback.append("[-] Could not verify race condition fix: missing commit() or publish()")
        else:
            feedback.append("[-] Could not parse process_upload() in api/main.py")
    else:
        feedback.append("[-] api/main.py not found")
        
    # Criterion 5: Check Null Reference Fix (25 pts)
    if processor_js:
        # Check for safe access patterns protecting against null descriptions
        safe_patterns = [
            r'\?\.length',                       # desc?.length
            r'if\s*\([^)]*desc[^)]*\)',          # if (desc) or if (row.description)
            r'desc\s*\?',                        # desc ? ...
            r'description\s*\?',                 # row.description ? ...
            r'\|\|',                             # desc || ""
            r'!==\s*null',                       # desc !== null
            r'===\s*null',                       # desc === null
        ]
        
        is_safe = False
        for p in safe_patterns:
            if re.search(p, processor_js):
                is_safe = True
                break
                
        if is_safe:
            score += 25
            feedback.append("[+] Null reference bug fixed: safe access to description length")
        else:
            feedback.append("[-] Null reference bug remains: missing check for null description before length access")
    else:
        feedback.append("[-] worker/processor.js not found")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }