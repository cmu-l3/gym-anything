#!/usr/bin/env python3
"""
Verifier for docker_state_extraction task.

SCORING CRITERIA (100 pts):
1. Dockerfile exists & valid base (20 pts)
2. Image 'acme-legacy-app:restored' exists (10 pts)
3. Restored image functional (Healthcheck 200 OK) (20 pts)
4. Application files present in image (15 pts)
5. Python dependencies installed (15 pts)
6. System packages (curl/vim) installed (10 pts)
7. Manifest file exists with content (10 pts)

Pass Threshold: 65 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_docker_state_extraction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
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
    feedback_parts = []

    # 1. Dockerfile Check (20 pts)
    if result.get('dockerfile_exists'):
        if result.get('has_correct_from'):
            score += 20
            feedback_parts.append("Valid Dockerfile found (+20)")
        else:
            score += 10
            feedback_parts.append("Dockerfile found but wrong Base Image (10/20)")
    else:
        feedback_parts.append("No Dockerfile found (0/20)")

    # 2. Image Exists (10 pts)
    if result.get('image_exists'):
        score += 10
        feedback_parts.append("Restored image exists (+10)")
    else:
        feedback_parts.append("Restored image not built (0/10)")

    # 3. Functional Health Check (20 pts)
    if result.get('app_healthy'):
        score += 20
        feedback_parts.append("Restored app is healthy (+20)")
    else:
        feedback_parts.append("Restored app failed health check (0/20)")

    # 4. File Restoration (15 pts)
    if result.get('files_exist'):
        score += 15
        feedback_parts.append("App files restored (+15)")
    else:
        feedback_parts.append("Missing app files in image (0/15)")

    # 5. Python Deps (15 pts)
    if result.get('pkgs_installed'):
        score += 15
        feedback_parts.append("Python dependencies restored (+15)")
    else:
        feedback_parts.append("Missing Python dependencies (0/15)")

    # 6. System Pkgs (10 pts)
    if result.get('sys_pkgs_installed'):
        score += 10
        feedback_parts.append("System packages restored (+10)")
    else:
        feedback_parts.append("Missing system packages (curl/vim) (0/10)")

    # 7. Manifest (10 pts)
    if result.get('manifest_exists') and result.get('manifest_size', 0) > 50:
        score += 10
        feedback_parts.append("Change manifest created (+10)")
    elif result.get('manifest_exists'):
        score += 5
        feedback_parts.append("Manifest empty/too short (5/10)")
    else:
        feedback_parts.append("No manifest file (0/10)")

    # Calculate final status
    passed = score >= task_info.get('metadata', {}).get('pass_threshold', 65)
    
    # Critical failure: if app is not healthy, verify functional requirement is unmet
    # (But score might pass if they did everything else perfectly? 
    # Max score without health is 80. So pass threshold ensures quality.)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }