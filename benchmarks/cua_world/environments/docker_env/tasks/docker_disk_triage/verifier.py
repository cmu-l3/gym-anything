#!/usr/bin/env python3
"""
Verifier for docker_disk_triage task.
"""

import json
import base64
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_docker_disk_triage(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Critical Safety (30 points)
    # - 3 prod containers must be running (10 pts each, scaled)
    # - Debug container must exist (5 pts)
    # - Prod volume must exist (5 pts)
    prod_count = result.get("prod_running_count", 0)
    if prod_count == 3:
        score += 20
        feedback.append("All production containers running (+20)")
    else:
        score += (prod_count * 6)
        feedback.append(f"Only {prod_count}/3 production containers running")

    if result.get("debug_container_exists", 0):
        score += 5
        feedback.append("Debug container preserved (+5)")
    else:
        feedback.append("FAIL: Critical debug container was deleted")

    if result.get("prod_volume_exists", 0):
        score += 5
        feedback.append("Production database volume preserved (+5)")
    else:
        feedback.append("FAIL: Production database volume was deleted")

    # 2. Cleanup Effectiveness (40 points)
    # - Dangling images (10)
    # - Trash containers (15)
    # - Trash volumes (15)
    
    dangling = result.get("dangling_images_remaining", 999)
    if dangling == 0:
        score += 10
        feedback.append("Dangling images cleaned (+10)")
    else:
        feedback.append(f"{dangling} dangling images remaining")

    trash_containers = result.get("trash_containers_remaining", 999)
    if trash_containers == 0:
        score += 15
        feedback.append("Stopped trash containers cleaned (+15)")
    else:
        feedback.append(f"{trash_containers} trash containers remaining")

    trash_volumes = result.get("trash_volumes_remaining", 999)
    if trash_volumes == 0:
        score += 15
        feedback.append("Orphaned volumes cleaned (+15)")
    else:
        feedback.append(f"{trash_volumes} orphaned volumes remaining")

    # 3. Documentation & Automation (30 points)
    # - Report (10)
    # - Script (20)
    
    if result.get("report_exists") and result.get("report_modified"):
        score += 10
        feedback.append("Cleanup report created (+10)")
    else:
        feedback.append("Cleanup report missing or not updated")

    script_ok = False
    if result.get("script_exists") and result.get("script_executable"):
        # Check script content for safety measures
        content = ""
        try:
            content = base64.b64decode(result.get("script_content_b64", "")).decode('utf-8')
        except:
            pass
        
        has_prune = "prune" in content or "rm" in content
        has_filter = "--filter" in content or "grep" in content or "label" in content
        
        if has_prune and has_filter:
            score += 20
            script_ok = True
            feedback.append("Automation script valid with safety filters (+20)")
        elif has_prune:
            score += 10
            feedback.append("Automation script lacks explicit safety filters (10/20)")
        else:
            feedback.append("Automation script does not appear to perform cleanup")
    else:
        feedback.append("Automation script missing or not executable")

    # Final Pass Check
    # Must have preserved prod services AND done some cleanup
    passed = (score >= 60) and (prod_count == 3) and (trash_containers == 0 or trash_volumes == 0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }