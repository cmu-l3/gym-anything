#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import re

def verify_docker_swarm_migration(traj, env_info, task_info):
    """
    Verify Docker Swarm migration task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
    
    # 1. Swarm Initialized (10 pts)
    if result.get('swarm_state') == 'active':
        score += 10
        feedback.append("Swarm active (+10)")
    else:
        feedback.append("Swarm not active (0)")

    # 2. Stack Deployed (10 pts)
    if result.get('stack_exists', 0) > 0:
        score += 10
        feedback.append("Stack 'acme-tools' deployed (+10)")
    else:
        feedback.append("Stack 'acme-tools' not found (0)")

    # 3. Images Built (10 pts)
    imgs = result.get('images_built', {})
    if imgs.get('web') and imgs.get('api'):
        score += 10
        feedback.append("Custom images built (+10)")
    else:
        feedback.append("Custom images missing (0)")

    # 4. Service Replicas (30 pts total)
    # Expected: web=3/3, api=2/2, db=1/1, cache=1/1
    reps = result.get('replicas', {})
    
    def check_rep(name, expected, pts):
        val = reps.get(name, "0/0")
        # Handle "3/3" or "3" depending on version
        match = re.search(r'(\d+)/(\d+)', val)
        if match:
            curr, target = int(match.group(1)), int(match.group(2))
            if curr == expected and target == expected:
                return pts, f"{name} {curr}/{target} (+{pts})"
            return 0, f"{name} {curr}/{target} != {expected} (0)"
        return 0, f"{name} invalid state '{val}' (0)"

    s, f = check_rep('web', 3, 10)
    score += s; feedback.append(f)
    
    s, f = check_rep('api', 2, 10)
    score += s; feedback.append(f)

    # DB and Cache combined (5 pts each)
    s1, f1 = check_rep('db', 1, 5)
    s2, f2 = check_rep('cache', 1, 5)
    score += s1 + s2
    feedback.append(f1); feedback.append(f2)

    # 5. Accessibility (15 pts)
    if result.get('http_code') == '200' and 'AcmeCorp' in result.get('http_body_snippet', ''):
        score += 15
        feedback.append("Web accessible (+15)")
    else:
        feedback.append(f"Web not accessible (Code: {result.get('http_code')}) (0)")

    # 6. Update Policy (10 pts)
    # Expect parallelism 1, delay 10s (10000000000 ns)
    update_conf = result.get('update_config', {})
    par = update_conf.get('Parallelism', 0)
    delay = update_conf.get('Delay', 0)
    if par == 1 and (delay == 10000000000 or delay == 10): # ns or sec depending on engine ver
        score += 10
        feedback.append("Update policy correct (+10)")
    elif par == 1:
        score += 5
        feedback.append("Update policy partial (Delay incorrect) (+5)")
    else:
        feedback.append(f"Update policy incorrect (Par:{par}, Del:{delay}) (0)")

    # 7. Resource Limits (15 pts)
    # Expect MemoryBytes ~ 268435456 (256MB)
    web_res = result.get('web_resources', {}).get('Limits', {}).get('MemoryBytes', 0)
    api_res = result.get('api_resources', {}).get('Limits', {}).get('MemoryBytes', 0)
    target_mem = 256 * 1024 * 1024
    
    if web_res == target_mem and api_res == target_mem:
        score += 15
        feedback.append("Resource limits correct (+15)")
    elif web_res == target_mem or api_res == target_mem:
        score += 7
        feedback.append("Resource limits partial (+7)")
    else:
        feedback.append("Resource limits incorrect (0)")

    # Anti-gaming check: Task duration
    start = result.get('task_start', 0)
    end = result.get('task_end', 0)
    if (end - start) < 10:
        score = 0
        feedback = ["Task completed too quickly (<10s). Potential gaming."]

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }