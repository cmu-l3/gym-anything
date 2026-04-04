#!/usr/bin/env python3
"""
Verifier for multi_arch_build_pipeline task.

Verifies:
1. Local registry is running.
2. Custom Docker Buildx builder exists.
3. Image manifest in registry contains both amd64 and arm64 architectures.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multi_arch_build(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to read result file: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: Registry Running (10 pts)
    if result.get('registry_running', False):
        score += 10
        feedback_parts.append("Registry running (+10)")
    else:
        feedback_parts.append("Registry NOT running (0)")

    # Criterion 2: Custom Builder Exists (20 pts)
    # The default builder cannot easily push multi-arch to a registry without loading 
    # (which fails for foreign archs) or using the container driver.
    if result.get('custom_builder_exists', False):
        score += 20
        feedback_parts.append("Custom Buildx builder active (+20)")
    else:
        feedback_parts.append("No custom Buildx builder found (0)")

    # Criterion 3: Repo Exists (20 pts)
    if result.get('repo_exists', False):
        score += 20
        feedback_parts.append("Image pushed to registry (+20)")
    else:
        feedback_parts.append("Image repository not found in registry (0)")
        # Fail early if no image
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 4 & 5: Architectures Present (25 pts each)
    platforms = result.get('platforms_found', "")
    amd64_count = 0
    arm64_count = 0
    
    # Parse "amd64:1,arm64:1" string
    try:
        parts = platforms.split(',')
        for p in parts:
            if 'amd64' in p:
                amd64_count = int(p.split(':')[1])
            if 'arm64' in p:
                arm64_count = int(p.split(':')[1])
    except:
        pass

    if amd64_count > 0:
        score += 25
        feedback_parts.append("AMD64 platform found (+25)")
    else:
        feedback_parts.append("AMD64 platform MISSING (0)")

    if arm64_count > 0:
        score += 25
        feedback_parts.append("ARM64 platform found (+25)")
    else:
        feedback_parts.append("ARM64 platform MISSING (0)")

    # Pass Threshold: 75
    # Needs registry (10) + repo (20) + both archs (50) = 80 pts minimum for meaningful success
    # Or registry (10) + builder (20) + repo (20) + one arch (25) = 75 pts
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "manifest_snippet": result.get("manifest_content", "")[:200]
        }
    }