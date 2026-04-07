#!/usr/bin/env python3
"""
Verifier for configure_apache_api_proxy task.

VERIFICATION STRATEGY:
1. File Verification: Evaluates if required Apache proxy modules are loaded.
2. Config Verification: Checks if 'ProxyPass' directives exist in Apache config.
3. Env Verification: Checks if .env variables point to the expected '/proxy/...' paths.
4. Live Network Verification (Primary): Checks the exported HTTP request results. 
   If curl successfully reached Express via port 80 proxy routing, the task truly succeeded.
5. VLM Verification: Analyzes trajectory to ensure agent used CLI/text editor.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import VLM utilities for trajectory verification
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_apache_api_proxy(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/apache_proxy_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Apache Modules (10 pts)
    # ---------------------------------------------------------
    if result.get('mod_proxy_enabled') and result.get('mod_proxy_http_enabled'):
        score += 10
        feedback_parts.append("Proxy modules loaded")
    else:
        feedback_parts.append("Proxy modules NOT fully enabled")

    # ---------------------------------------------------------
    # 2. Apache Configuration (15 pts)
    # ---------------------------------------------------------
    conf = result.get('apache_conf', '')
    if 'ProxyPass /proxy/user' in conf or 'ProxyPass /proxy/feeds' in conf:
        score += 15
        feedback_parts.append("ProxyPass directives found")
    else:
        feedback_parts.append("ProxyPass directives missing in Apache config")

    # ---------------------------------------------------------
    # 3. Environment File Configuration (25 pts)
    # ---------------------------------------------------------
    env_data = result.get('env', {})
    api_url = env_data.get('api_url', '')
    api_feeds = env_data.get('api_feeds', '')
    api_publish = env_data.get('api_publish', '')
    api_notification = env_data.get('api_notification', '')

    env_correct = True
    if '/proxy/user' not in api_url: env_correct = False
    if '/proxy/feeds' not in api_feeds: env_correct = False
    if '/proxy/publish' not in api_publish: env_correct = False
    if '/proxy/notification' not in api_notification: env_correct = False

    env_mtime = result.get('env_mtime', 0)
    task_start = result.get('task_start', 0)

    if env_correct and env_mtime > task_start:
        score += 25
        feedback_parts.append("Frontend .env correctly updated")
    elif env_correct:
        score += 10  # Partial credit if correct but timestamp doesn't align
        feedback_parts.append(".env has correct paths (but timestamp indicates it may be stale)")
    else:
        feedback_parts.append("Frontend .env NOT correctly updated")

    # ---------------------------------------------------------
    # 4. Live Proxy Routing (40 pts)
    # ---------------------------------------------------------
    live = result.get('live_proxy', {})
    working_proxies = sum([
        live.get('user', False),
        live.get('feeds', False),
        live.get('publish', False),
        live.get('notification', False)
    ])

    score += working_proxies * 10
    feedback_parts.append(f"Live endpoints reached: {working_proxies}/4")

    # ---------------------------------------------------------
    # 5. VLM Trajectory Verification (10 pts)
    # ---------------------------------------------------------
    vlm_score = 0
    if VLM_AVAILABLE and traj:
        frames = sample_trajectory_frames(traj, n=5)
        prompt = (
            "You are evaluating an AI agent performing system administration. "
            "The task was to configure Apache web server and edit a .env file. "
            "Looking across these trajectory frames, did the agent use a terminal, "
            "command-line interface, or text editor (like nano, vim, gedit) to perform configuration edits? "
            "Respond ONLY with a JSON dictionary containing 'used_tools': true/false."
        )
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        try:
            parsed = vlm_res.get('parsed', {})
            if parsed.get('used_tools', False):
                vlm_score = 10
                feedback_parts.append("VLM confirms CLI/editor usage")
            else:
                feedback_parts.append("VLM did not detect CLI/editor usage")
        except Exception:
            feedback_parts.append("VLM evaluation failed")
            
        score += vlm_score

    # Determine overall pass status
    # Must have >= 80 points, env configured, and at least 3 live endpoints functional
    passed = score >= 80 and env_correct and working_proxies >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }