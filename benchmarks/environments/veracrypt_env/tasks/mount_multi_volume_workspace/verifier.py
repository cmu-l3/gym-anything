#!/usr/bin/env python3
"""Verifier for mount_multi_volume_workspace task."""

import json
import base64
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mount_multi_volume_workspace(traj, env_info, task_info):
    """
    Verify the multi-volume workspace setup.
    
    Criteria:
    1. All 3 volumes mounted simultaneously.
    2. Volumes mounted to correct custom mount points.
    3. Files inside volumes are accessible (implies correct passwords used).
    4. Manifest file exists, created during task, and contains correct info.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 1. Check Mounts (45 points total)
    # 15 points per correct mount
    mounts_correct = 0
    
    if result.get('alpha_mounted_correctly'):
        score += 15
        mounts_correct += 1
        feedback.append("Volume 1 (Alpha) mounted correctly.")
    else:
        feedback.append("Volume 1 (Alpha) NOT mounted to correct path.")

    if result.get('beta_mounted_correctly'):
        score += 15
        mounts_correct += 1
        feedback.append("Volume 2 (Beta) mounted correctly.")
    else:
        feedback.append("Volume 2 (Beta) NOT mounted to correct path.")

    if result.get('gamma_mounted_correctly'):
        score += 15
        mounts_correct += 1
        feedback.append("Volume 3 (Gamma) mounted correctly.")
    else:
        feedback.append("Volume 3 (Gamma) NOT mounted to correct path.")

    # Bonus: Simultaneous check (10 points)
    if result.get('mount_count', 0) >= 3 and mounts_correct == 3:
        score += 10
        feedback.append("All volumes mounted simultaneously.")
    elif result.get('mount_count', 0) < 3:
        feedback.append("Not all volumes are mounted simultaneously.")

    # 2. Check File Accessibility (20 points total)
    # This verifies keys/passwords were actually correct and FS is readable
    files_ok = 0
    if result.get('alpha_file_accessible'):
        score += 5
        files_ok += 1
    
    if result.get('beta_files_accessible'):
        score += 10 # More files here
        files_ok += 1
        
    if result.get('gamma_file_accessible'):
        score += 5
        files_ok += 1
        
    if files_ok == 3:
        feedback.append("All volume contents are accessible.")
    elif files_ok > 0:
        feedback.append(f"Some volume contents accessible ({files_ok}/3).")
    else:
        feedback.append("Volume contents NOT accessible.")

    # 3. Check Manifest (25 points total)
    manifest_exists = result.get('manifest_exists')
    manifest_fresh = result.get('manifest_created_during_task')
    
    if manifest_exists and manifest_fresh:
        score += 5
        feedback.append("Manifest file created.")
        
        # Analyze content
        try:
            content_b64 = result.get('manifest_content_b64', "")
            content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
            
            # Check for required keywords/paths
            manifest_score = 0
            
            # Lists all volume paths (10 pts)
            if all(v in content for v in ["test_volume.hc", "data_volume.hc", "mounted_volume.hc"]):
                manifest_score += 10
                feedback.append("Manifest lists all volumes.")
            
            # Lists contents (5 pts)
            # Sample filenames
            if any(f in content for f in ["incident_report", "SF312", "network_topology"]):
                manifest_score += 5
                feedback.append("Manifest lists file contents.")
                
            # Total count (5 pts)
            if "Total files:" in content and "5" in content:
                manifest_score += 5
                feedback.append("Manifest contains correct total count.")
                
            score += manifest_score
        except Exception as e:
            feedback.append(f"Error parsing manifest: {str(e)}")
    else:
        feedback.append("Manifest file missing or not created during task.")

    passed = (score >= 60) and (mounts_correct == 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }