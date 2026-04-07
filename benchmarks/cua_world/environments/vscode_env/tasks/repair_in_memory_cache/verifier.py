#!/usr/bin/env python3
"""
Verifier for repair_in_memory_cache task.

Uses `copy_from_env` to retrieve the programmatic test evaluation executed
inside the container in `export_result.sh`.
"""

import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cache_fixes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. LRU
    if result.get("lru", False):
        score += 20
        feedback_parts.append("[+] LRU Cache: Pointer bug fixed (backward traversal works)")
    else:
        feedback_parts.append("[-] LRU Cache: Backward links broken or memory leak persists")

    # 2. TTL
    if result.get("ttl", False):
        score += 20
        feedback_parts.append("[+] TTL Cache: Concurrency dictionary mutation bug fixed")
    else:
        feedback_parts.append("[-] TTL Cache: RuntimeError still raised during sweep()")

    # 3. WAL
    if result.get("wal", False):
        score += 20
        feedback_parts.append("[+] WAL: Absolute timestamp logic implemented")
    else:
        feedback_parts.append("[-] WAL: Relative TTLs still being logged")

    # 4. Sharding
    if result.get("sharding", False):
        score += 20
        feedback_parts.append("[+] Sharding: Multi-bracket tags extracted non-greedily")
    else:
        feedback_parts.append("[-] Sharding: Greedy extraction bug persists on '}'")

    # 5. Sorted Set
    if result.get("sorted_set", False):
        score += 20
        feedback_parts.append("[+] Sorted Set: Tie-breaking lexicographical sort fixed")
    else:
        feedback_parts.append("[-] Sorted Set: Array not sorted by member string on tie")

    # Anti-gaming: Check if VS Code was running / files were edited
    if not result.get("vscode_running", True):
        feedback_parts.append("Warning: VS Code process not found.")
        
    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }