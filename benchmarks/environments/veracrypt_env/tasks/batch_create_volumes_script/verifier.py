#!/usr/bin/env python3
"""
Verifier for batch_create_volumes_script task.

Scoring Breakdown (Total 100):
1. Script file (20 pts):
   - Exists and executable: 10 pts
   - Content looks correct (contains commands/names): 10 pts
2. Volumes created and functional (60 pts, 20 per volume):
   - Volume exists and correct size: 5 pts
   - Mounts successfully with password: 10 pts
   - Encryption algorithm matches spec: 5 pts
3. Report file (10 pts):
   - Exists and reports PASS for 3 volumes: 10 pts
4. Clean state (10 pts):
   - All volumes dismounted at end: 10 pts

Anti-gaming:
- Checks if volume creation time is after task start.
- Programmatically mounts volumes to verify they are real and password is correct.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_batch_create_volumes(traj, env_info, task_info):
    """
    Verify that the agent wrote a script to create volumes and that the volumes work.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON from container
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

    score = 0
    feedback_parts = []
    
    # 1. Verify Script (20 pts)
    script_info = result.get('script', {})
    if script_info.get('exists'):
        if script_info.get('executable'):
            score += 10
            feedback_parts.append("Script exists and is executable")
        else:
            score += 5
            feedback_parts.append("Script exists but not executable")
            
        # Content check (0-5 matches mapped to 0-10 points)
        content_matches = script_info.get('content_matches', 0)
        # 5 matches possible -> 2 pts each
        script_content_score = min(10, content_matches * 2)
        score += script_content_score
        if script_content_score < 10:
             feedback_parts.append(f"Script content missing expected commands ({script_content_score}/10)")
    else:
        feedback_parts.append("Script file not found")

    # 2. Verify Volumes (60 pts)
    volumes = result.get('volumes', {})
    vol_names = ["finance_dept.hc", "legal_dept.hc", "engineering_dept.hc"]
    
    volumes_working = 0
    
    for vol_name in vol_names:
        vol_data = volumes.get(vol_name, {})
        vol_score = 0
        
        # Check existence and size
        if vol_data.get('exists') and vol_data.get('created_during_task'):
            size = vol_data.get('size_bytes', 0)
            min_size = vol_data.get('min_size', 0)
            if size >= min_size:
                vol_score += 5
            else:
                vol_score += 2 # Exists but too small
        
        # Check mount
        if vol_data.get('mount_success'):
            vol_score += 10
            
            # Check algo (only if mount worked)
            detected = vol_data.get('detected_algo', '').lower()
            expected = vol_data.get('expected_algo', '').lower()
            if expected in detected:
                vol_score += 5
            else:
                feedback_parts.append(f"{vol_name} wrong algo ({detected})")
        
        score += vol_score
        if vol_score >= 15: # Roughly working
            volumes_working += 1
            
        if vol_score < 20:
            feedback_parts.append(f"{vol_name}: {vol_score}/20 pts")

    if volumes_working == 3:
        feedback_parts.append("All volumes created & mounting correctly")

    # 3. Verify Report (10 pts)
    report_info = result.get('report', {})
    if report_info.get('exists'):
        pass_count = report_info.get('pass_count', 0)
        if pass_count >= 3:
            score += 10
            feedback_parts.append("Report correct")
        elif pass_count > 0:
            score += 5
            feedback_parts.append("Report incomplete")
        else:
            score += 2 # Empty report
    else:
        feedback_parts.append("Report missing")

    # 4. Clean State (10 pts)
    if result.get('clean_state'):
        score += 10
    else:
        feedback_parts.append("Volumes left mounted")

    # Final logic
    passed = score >= 70 and volumes_working >= 2
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }