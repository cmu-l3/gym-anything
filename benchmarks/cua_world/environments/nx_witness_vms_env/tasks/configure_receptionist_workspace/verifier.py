#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_receptionist_workspace(traj, env_info, task_info):
    """
    Verifies the receptionist workspace configuration.
    
    Checks:
    1. Role 'Front Desk Role' exists with correct permissions/resource constraints.
    2. User 'receptionist' exists and has the role.
    3. Soft Triggers (Event Rules) configured correctly.
    4. Layout 'Reception Desk View' exists with correct items.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Helper to find device IDs by name
    devices = data.get('devices', [])
    def get_id_by_name(name):
        for d in devices:
            if d.get('name') == name:
                return d.get('id')
        return None

    lobby_id = get_id_by_name("Lobby Camera")
    entrance_id = get_id_by_name("Entrance Camera")
    server_id = get_id_by_name("Server Room Camera")

    if not (lobby_id and entrance_id and server_id):
        return {"passed": False, "score": 0, "feedback": "Critical Error: Could not resolve camera IDs from environment data."}

    # ==========================================================================
    # CRITERION 1: Role Configuration (30 pts)
    # ==========================================================================
    roles = data.get('roles', [])
    target_role = next((r for r in roles if r.get('name') == "Front Desk Role"), None)
    
    role_ok = False
    if target_role:
        score += 10
        feedback.append("Role 'Front Desk Role' created.")
        
        # Check Permissions (Looking for specific permission flags or lack thereof)
        # Nx Witness permissions are complex bitmasks or lists. 
        # API v1 usually returns 'permissions' list or bitmask.
        # We check for accessibleResources logic primarily as that's the security boundary.
        
        resources = target_role.get('accessibleResources', [])
        
        # Check positive access (Lobby & Entrance)
        if lobby_id in resources and entrance_id in resources:
            score += 10
            feedback.append("Role has access to required cameras.")
        else:
            feedback.append("Role missing access to Lobby or Entrance camera.")

        # Check negative access (Server Room) - CRITICAL
        if server_id in resources:
            feedback.append("SECURITY FAIL: Role has access to Server Room!")
        else:
            score += 10
            feedback.append("Role correctly restricted from Server Room.")
            role_ok = True
    else:
        feedback.append("Role 'Front Desk Role' not found.")

    # ==========================================================================
    # CRITERION 2: User Configuration (10 pts)
    # ==========================================================================
    users = data.get('users', [])
    target_user = next((u for u in users if u.get('name') == "receptionist"), None)
    
    if target_user:
        # Check if user has the role
        # User object might have 'userRoleId' or 'userRoleIds'
        user_role_id = target_user.get('userRoleId') or (target_user.get('userRoleIds', [])[0] if target_user.get('userRoleIds') else None)
        
        if target_role and user_role_id == target_role.get('id'):
            score += 10
            feedback.append("User 'receptionist' created with correct role.")
        else:
            feedback.append("User 'receptionist' exists but has wrong role.")
    else:
        feedback.append("User 'receptionist' not found.")

    # ==========================================================================
    # CRITERION 3: Soft Triggers / Event Rules (40 pts)
    # ==========================================================================
    rules = data.get('rules', [])
    
    # 3a. Unlock Door Trigger (20 pts)
    unlock_rule = None
    for r in rules:
        if r.get('eventType') == 'softwareTrigger':
            params = r.get('eventCondition', {}).get('params', {})
            # params might be a JSON string or object depending on version, usually object in v1
            # Check caption
            if isinstance(params, str):
                try: params = json.loads(params)
                except: pass
            
            if isinstance(params, dict) and 'Unlock Door' in params.get('caption', ''):
                unlock_rule = r
                break
    
    if unlock_rule:
        # Check correct camera mapping
        resources = unlock_rule.get('eventResourceIds', [])
        if entrance_id in resources:
            score += 10
            feedback.append("Unlock Door trigger linked to Entrance Camera.")
        else:
            feedback.append("Unlock Door trigger exists but on wrong camera.")
            
        # Check Action (HTTP Request)
        action_type = unlock_rule.get('actionType')
        action_params = unlock_rule.get('actionParams', {})
        if isinstance(action_params, str):
            try: action_params = json.loads(action_params)
            except: pass
            
        if action_type == 'httpRequstAction' or action_type == 'execHttpRequestAction': # naming varies slightly by version
            url = action_params.get('url', '')
            if 'door-controller.local' in url:
                score += 10
                feedback.append("Unlock Door trigger action correct.")
            else:
                feedback.append("Unlock Door trigger has wrong URL.")
        else:
            # Fallback for slight API variances
            score += 5 
            feedback.append("Unlock Door trigger found (action verification partial).")
    else:
        feedback.append("Unlock Door soft trigger not found.")

    # 3b. Panic Alert Trigger (20 pts)
    panic_rule = None
    for r in rules:
        if r.get('eventType') == 'softwareTrigger':
            params = r.get('eventCondition', {}).get('params', {})
            if isinstance(params, str):
                try: params = json.loads(params)
                except: pass
            
            if isinstance(params, dict) and 'Panic Alert' in params.get('caption', ''):
                panic_rule = r
                break
                
    if panic_rule:
        resources = panic_rule.get('eventResourceIds', [])
        if lobby_id in resources:
            score += 10
            feedback.append("Panic Alert trigger linked to Lobby Camera.")
        else:
            feedback.append("Panic Alert trigger exists but on wrong camera.")
            
        action_type = panic_rule.get('actionType')
        if action_type == 'createBookmarkAction' or action_type == 'bookmarkAction':
            score += 10
            feedback.append("Panic Alert trigger action correct.")
        else:
            feedback.append(f"Panic Alert trigger has wrong action type: {action_type}")
    else:
        feedback.append("Panic Alert soft trigger not found.")

    # ==========================================================================
    # CRITERION 4: Layout (20 pts)
    # ==========================================================================
    layouts = data.get('layouts', [])
    layout = next((l for l in layouts if l.get('name') == "Reception Desk View"), None)
    
    if layout:
        items = layout.get('items', [])
        item_resource_ids = [i.get('resourceId') for i in items]
        
        if lobby_id in item_resource_ids and entrance_id in item_resource_ids:
            score += 20
            feedback.append("Layout 'Reception Desk View' contains correct cameras.")
        else:
            score += 10
            feedback.append("Layout exists but missing some cameras.")
    else:
        feedback.append("Layout 'Reception Desk View' not found.")

    # Final Check
    passed = score >= 70 and role_ok
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }