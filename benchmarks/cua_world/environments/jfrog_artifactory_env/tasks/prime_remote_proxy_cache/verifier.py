#!/usr/bin/env python3
"""
Verifier for prime_remote_proxy_cache task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_prime_remote_proxy_cache(traj, env_info, task_info):
    """
    Verifies that:
    1. The remote repository 'central-proxy-test' exists.
    2. It is configured as a REMOTE repository pointing to Maven Central.
    3. The requested artifact is present in the repository cache (proof of download).
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    repo_config = result.get('repo_config', {})
    artifact_info = result.get('artifact_verification', {})
    task_start = result.get('task_start', 0)
    
    score = 0
    feedback_parts = []
    
    # 1. Verify Repository Exists and Config (40 pts)
    if repo_config and repo_config.get('key') == 'central-proxy-test':
        score += 20
        repo_type = repo_config.get('type', '').upper()
        repo_url = repo_config.get('url', '')
        
        if repo_type == 'REMOTE':
            score += 10
            feedback_parts.append("Remote repository created.")
        else:
            feedback_parts.append(f"Repository created but wrong type: {repo_type} (expected REMOTE).")

        # Check URL (contains repo1.maven.org)
        if 'repo1.maven.org/maven2' in repo_url:
            score += 10
            feedback_parts.append("Correct upstream URL.")
        else:
            feedback_parts.append(f"Incorrect upstream URL: {repo_url}")
    else:
        feedback_parts.append("Repository 'central-proxy-test' not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Verify Artifact Cached (60 pts)
    # This is the proof that the proxy actually worked and the agent triggered the download
    if artifact_info.get('exists'):
        # Check size (commons-collections4-4.4.jar is approx 750KB)
        size = artifact_info.get('size_bytes', 0)
        if size > 700000:
            score += 50
            feedback_parts.append("Artifact successfully cached.")
            
            # Anti-gaming: Check timestamp
            created_ts = artifact_info.get('created_timestamp', 0)
            if created_ts > task_start:
                score += 10
                feedback_parts.append("Artifact downloaded during task session.")
            else:
                feedback_parts.append("Artifact timestamp predates task (stale data?).")
        else:
            score += 10 # Partial credit for file existence but wrong size
            feedback_parts.append(f"Artifact found but size suspicious ({size} bytes).")
    else:
        feedback_parts.append("Artifact NOT found in cache. Did you trigger the download?")

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }