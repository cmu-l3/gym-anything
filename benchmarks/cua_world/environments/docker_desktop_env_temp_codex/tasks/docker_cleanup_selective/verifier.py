#!/usr/bin/env python3
"""
Verifier for docker_cleanup_selective task.
Verifies that specific resources were removed while others were preserved.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docker_cleanup_selective(traj, env_info, task_info):
    """
    Verify selective cleanup of Docker resources.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata expectations
    metadata = task_info.get('metadata', {})
    keep_containers = set(metadata.get('keep_containers', []))
    remove_containers = set(metadata.get('remove_containers', []))
    keep_volumes = set(metadata.get('keep_volumes', []))
    remove_volumes = set(metadata.get('remove_volumes', []))
    remove_networks = set(metadata.get('remove_networks', []))

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load result file: {e}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- 1. Verify Containers (35 points total) ---
    # Parse container state raw string: "name|status|state\n..."
    raw_containers = result.get('container_state_raw', '').strip().split('\n')
    current_containers = {}
    for line in raw_containers:
        if not line: continue
        parts = line.split('|')
        if len(parts) >= 3:
            name = parts[0].strip()
            state = parts[2].strip() # 'running' or 'exited'
            current_containers[name] = state

    # 1a. Check Preserved Containers (20 pts)
    # Must exist AND be running (except the snapshot which should be stopped)
    preserved_ok_count = 0
    for name in keep_containers:
        if name in current_containers:
            # prod-* should be running
            if name.startswith('prod-'):
                if current_containers[name] == 'running':
                    preserved_ok_count += 1
                else:
                    feedback.append(f"⚠️ Container '{name}' exists but is NOT running.")
            else:
                # staging-db-snapshot should exist (state doesn't matter much, but it started stopped)
                preserved_ok_count += 1
        else:
            feedback.append(f"❌ CRITICAL: Production container '{name}' was removed!")
    
    # Scale score for preserved
    score += (preserved_ok_count / len(keep_containers)) * 20

    # 1b. Check Removed Containers (15 pts)
    removed_ok_count = 0
    for name in remove_containers:
        if name not in current_containers:
            removed_ok_count += 1
        else:
            feedback.append(f"⚠️ Container '{name}' was not removed.")
    
    score += (removed_ok_count / len(remove_containers)) * 15


    # --- 2. Verify Dangling Images (15 points) ---
    dangling_count = result.get('dangling_image_count', 0)
    if dangling_count == 0:
        score += 15
        feedback.append("✅ All dangling images removed.")
    else:
        feedback.append(f"⚠️ {dangling_count} dangling images remain.")


    # --- 3. Verify Volumes (20 points total) ---
    current_volumes = set(result.get('volumes', '').split(','))
    
    # 3a. Preserved Volume (10 pts)
    preserved_vols_ok = 0
    for vol in keep_volumes:
        if vol in current_volumes:
            preserved_vols_ok += 1
        else:
            feedback.append(f"❌ CRITICAL: Volume '{vol}' was removed!")
    score += (preserved_vols_ok / len(keep_volumes)) * 10

    # 3b. Removed Volumes (10 pts)
    removed_vols_ok = 0
    for vol in remove_volumes:
        if vol not in current_volumes:
            removed_vols_ok += 1
        else:
            feedback.append(f"⚠️ Volume '{vol}' was not removed.")
    score += (removed_vols_ok / len(remove_volumes)) * 10


    # --- 4. Verify Networks (10 points) ---
    current_networks = set(result.get('networks', '').split(','))
    removed_nets_ok = 0
    for net in remove_networks:
        if net not in current_networks:
            removed_nets_ok += 1
        else:
            feedback.append(f"⚠️ Network '{net}' was not removed.")
    score += (removed_nets_ok / len(remove_networks)) * 10


    # --- 5. Verify Report (20 points) ---
    report = result.get('report', {})
    if report.get('exists', False) and report.get('created_during_task', False):
        content = report.get('content_preview', '').lower()
        # Check for meaningful content keywords
        keywords = ['remove', 'delete', 'clean', 'container', 'volume', 'image']
        if any(k in content for k in keywords):
            score += 20
            feedback.append("✅ Cleanup report created with valid content.")
        else:
            score += 10
            feedback.append("⚠️ Report exists but content seems generic or empty.")
    elif report.get('exists', False):
        score += 5
        feedback.append("⚠️ Report exists but timestamp indicates it might be old.")
    else:
        feedback.append("⚠️ No cleanup report found.")


    # --- Final Scoring Logic ---
    # Fail if any production container was removed
    passed = True
    if preserved_ok_count < len(keep_containers):
        passed = False
        feedback.insert(0, "FAILED: One or more production containers were deleted.")
    
    # Fail if config volume was removed
    if preserved_vols_ok < len(keep_volumes):
        passed = False
        feedback.insert(0, "FAILED: Critical volume 'persistent-config' was deleted.")

    if passed and score < 70:
        passed = False
        feedback.append("Score too low to pass.")

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback)
    }