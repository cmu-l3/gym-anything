#!/usr/bin/env python3
"""
Verifier for Docker Build Cache Debug Task.

Points logic (Total 100):
1. Ordering (60 pts):
   - System deps (apt) BEFORE source copy: 20 pts
   - Requirements COPY BEFORE pip install: 20 pts
   - pip install BEFORE source copy: 20 pts
2. .dockerignore (20 pts):
   - Exists: 10 pts
   - Excludes .git: 5 pts
   - Excludes __pycache__: 5 pts
3. Execution (20 pts):
   - Image exists and is valid: 10 pts
   - Container runs (health check pass): 10 pts

Pass Threshold: 70 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_build_cache_debug(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check Dockerfile Modification (Anti-gaming)
    if not result.get("dockerfile_modified", False) or not result.get("modified_during_task", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Dockerfile was not modified. No work detected."
        }

    lines = result.get("lines", {})
    apt_line = int(lines.get("apt", 9999))
    copy_req_line = int(lines.get("copy_req", 9999))
    pip_line = int(lines.get("pip", 9999))
    copy_src_line = int(lines.get("copy_src", 9999))

    # Criterion 1.1: apt-get before source copy (20 pts)
    # Rationale: System deps rarely change, source changes often.
    # Note: apt_line must be valid (<9999) and less than copy_src_line
    if apt_line < 9999 and apt_line < copy_src_line:
        score += 20
        feedback_parts.append("System installs placed before source copy (+20)")
    elif apt_line == 9999:
        feedback_parts.append("apt-get instruction removed/missing")
    else:
        feedback_parts.append("apt-get should be before 'COPY . .'")

    # Criterion 1.2: COPY requirements before pip install (20 pts)
    # Rationale: Only re-run pip if requirements.txt changes.
    if copy_req_line < 9999 and copy_req_line < pip_line:
        score += 20
        feedback_parts.append("requirements.txt copied separately before pip install (+20)")
    else:
        feedback_parts.append("requirements.txt should be copied before running pip install")

    # Criterion 1.3: pip install before source copy (20 pts)
    # Rationale: Don't let app code changes invalidate pip cache.
    if pip_line < 9999 and pip_line < copy_src_line:
        score += 20
        feedback_parts.append("pip install placed before source copy (+20)")
    else:
        feedback_parts.append("pip install should be before 'COPY . .'")

    # Criterion 2: .dockerignore (20 pts)
    di = result.get("dockerignore", {})
    if di.get("exists", False):
        score += 10
        feedback_parts.append(".dockerignore created (+10)")
        
        extras = 0
        if di.get("ignores_git", False):
            extras += 5
        if di.get("ignores_pycache", False):
            extras += 5
        
        if extras > 0:
            score += extras
            feedback_parts.append(f".dockerignore content good (+{extras})")
    else:
        feedback_parts.append("No .dockerignore file found")

    # Criterion 3: Execution (20 pts)
    img = result.get("image", {})
    func = result.get("functionality", {})
    
    if img.get("exists", False) and img.get("has_pip_layer", False):
        score += 10
        feedback_parts.append("Image built successfully (+10)")
        
        if func.get("container_works", False):
            score += 10
            feedback_parts.append("Container runs and passes healthcheck (+10)")
        else:
            feedback_parts.append("Container failed to start or failed healthcheck")
    else:
        feedback_parts.append("Image build failed or missing pip layer")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }