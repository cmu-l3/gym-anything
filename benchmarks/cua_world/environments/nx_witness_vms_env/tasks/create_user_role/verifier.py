#!/usr/bin/env python3
"""
Verifier for create_user_role task.
Validates the existence and configuration of the 'Night Shift Monitor' role.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_role(traj, env_info, task_info):
    """
    Verify the 'Night Shift Monitor' role was created with correct permissions and resources.
    """
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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    target_role = result.get('target_role', {})
    ground_truth = result.get('ground_truth', {})
    initial_count = result.get('initial_role_count', 0)
    final_count = result.get('final_role_count', 0)
    
    # 1. Verify Role Exists (20 pts)
    if not target_role or not target_role.get('id'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Role 'Night Shift Monitor' was not found in the system."
        }
    
    score += 20
    feedback_parts.append("Role 'Night Shift Monitor' exists")
    
    # 2. Verify Permissions (60 pts total)
    permissions = target_role.get('permissions', [])
    # Normalize permissions: could be a list of strings
    if isinstance(permissions, str):
        # Sometimes API might return pipe-separated string depending on version? 
        # But JSON parser usually handles lists. Assuming list based on setup script.
        pass
        
    perm_list = set(permissions)
    
    # Positive checks
    if "GlobalViewLivePermission" in perm_list:
        score += 15
        feedback_parts.append("ViewLive OK")
    else:
        feedback_parts.append("Missing ViewLive permission")

    if "GlobalViewArchivePermission" in perm_list:
        score += 15
        feedback_parts.append("ViewArchive OK")
    else:
        feedback_parts.append("Missing ViewArchive permission")

    # Negative checks (Anti-gaming/Security)
    forbidden_hit = False
    if "GlobalAdminPermission" in perm_list:
        feedback_parts.append("FAIL: Role has Admin permission")
        forbidden_hit = True
    else:
        score += 10
        
    if "GlobalExportPermission" in perm_list:
        feedback_parts.append("FAIL: Role has Export permission")
        forbidden_hit = True
    else:
        score += 10
        
    if "GlobalEditCamerasPermission" in perm_list:
        feedback_parts.append("FAIL: Role has EditCameras permission")
        forbidden_hit = True
    else:
        score += 10

    # 3. Verify Resources (15 pts)
    # accessibleResources should contain the IDs of the two cameras
    resources = target_role.get('accessibleResources', [])
    # Normalize resource IDs (remove curly braces if present, lower case)
    res_clean = [r.strip('{}').lower() for r in resources]
    
    expected_parking = ground_truth.get('parking_id', '').strip('{}').lower()
    expected_entrance = ground_truth.get('entrance_id', '').strip('{}').lower()
    
    resource_score = 0
    if expected_parking and expected_parking in res_clean:
        resource_score += 7.5
    if expected_entrance and expected_entrance in res_clean:
        resource_score += 7.5
        
    if resource_score == 15:
        feedback_parts.append("Resources correct")
    elif resource_score > 0:
        feedback_parts.append("Resources partially correct")
    else:
        feedback_parts.append("Resources incorrect")
    
    score += int(resource_score)

    # 4. Anti-gaming check (5 pts)
    # Verify count increased (ensures we didn't just rename an existing one, though we deleted it in setup)
    if final_count > initial_count:
        score += 5
    
    passed = (score >= 60) and not forbidden_hit
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }