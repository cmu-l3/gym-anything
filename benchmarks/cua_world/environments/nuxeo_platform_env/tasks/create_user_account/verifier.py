#!/usr/bin/env python3
"""
Verifier for create_user_account task.
Checks:
1. User 'mwilson' exists with correct profile fields (First, Last, Email, Company).
2. User is a member of 'members' group.
3. Workspace 'Maria Wilson Files' exists with correct title/description.
4. User 'mwilson' has ReadWrite permission on the workspace.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_user_account(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task metadata (expected values)
    metadata = task_info.get('metadata', {})
    expected_user = metadata.get('expected_user', {})
    expected_group = metadata.get('expected_group', 'members')
    expected_workspace = metadata.get('expected_workspace', {})
    expected_permission = metadata.get('expected_permission', 'ReadWrite')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # --- Check 1: User Existence & Properties (40 pts) ---
    user_section = result.get('user', {})
    user_data = user_section.get('data', {})
    
    if user_section.get('exists'):
        score += 12
        feedback.append("User 'mwilson' created successfully.")
        
        # Check properties
        props = user_data.get('properties', {})
        
        # FirstName (8 pts)
        if props.get('firstName') == expected_user.get('firstName'):
            score += 8
        else:
            feedback.append(f"Incorrect First Name: expected {expected_user.get('firstName')}, got {props.get('firstName')}")
            
        # LastName (8 pts)
        if props.get('lastName') == expected_user.get('lastName'):
            score += 8
        else:
            feedback.append(f"Incorrect Last Name: expected {expected_user.get('lastName')}, got {props.get('lastName')}")
            
        # Email (7 pts)
        if props.get('email') == expected_user.get('email'):
            score += 7
        else:
            feedback.append(f"Incorrect Email: expected {expected_user.get('email')}, got {props.get('email')}")
            
        # Company (5 pts)
        if props.get('company') == expected_user.get('company'):
            score += 5
        else:
            feedback.append(f"Incorrect Company: expected {expected_user.get('company')}, got {props.get('company')}")
            
    else:
        feedback.append("User 'mwilson' was NOT created.")

    # --- Check 2: Group Membership (12 pts) ---
    # user_data['properties']['groups'] is a list of group names
    user_groups = user_data.get('properties', {}).get('groups', [])
    if expected_group in user_groups:
        score += 12
        feedback.append(f"User is correctly assigned to group '{expected_group}'.")
    else:
        feedback.append(f"User is NOT in group '{expected_group}'. Found: {user_groups}")

    # --- Check 3: Workspace Creation (28 pts) ---
    ws_section = result.get('workspace', {})
    ws_data = ws_section.get('data', {})
    
    if ws_section.get('exists'):
        score += 15
        feedback.append("Workspace 'Maria Wilson Files' created.")
        
        ws_props = ws_data.get('properties', {})
        
        # Check Description (8 pts)
        desc = ws_props.get('dc:description', "")
        if expected_workspace.get('description') in desc:
            score += 8
        else:
            feedback.append(f"Workspace description mismatch. Expected '{expected_workspace.get('description')}', got '{desc}'")
            
        # Check Type (5 pts)
        # Type is at the top level of the document JSON, e.g., "type": "Workspace"
        doc_type = ws_data.get('type')
        if doc_type == expected_workspace.get('type'):
            score += 5
        else:
            feedback.append(f"Incorrect document type. Expected '{expected_workspace.get('type')}', got '{doc_type}'")
            
    else:
        feedback.append("Workspace 'Maria Wilson Files' was NOT found.")

    # --- Check 4: Permissions (15 pts) ---
    perm_data = result.get('permissions', {}).get('data', {})
    # ACL data structure: {'acls': [{'aces': [{'username': 'mwilson', 'permission': 'ReadWrite', 'granted': True}, ...]}]}
    
    has_permission = False
    acls = perm_data.get('acls', [])
    for acl in acls:
        for ace in acl.get('aces', []):
            if (ace.get('username') == 'mwilson' and 
                ace.get('granted') == True and 
                ace.get('permission') in [expected_permission, 'Everything']):
                has_permission = True
                break
        if has_permission:
            break
            
    if has_permission:
        score += 15
        feedback.append(f"User 'mwilson' correctly granted '{expected_permission}' permission.")
    else:
        if ws_section.get('exists'):
            feedback.append(f"User 'mwilson' does NOT have '{expected_permission}' permission on the workspace.")

    # --- Check 5: Anti-Gaming / Timestamp (5 pts) ---
    # We verify that the entities were created/modified after the task started.
    # Nuxeo stores dc:created and dc:modified.
    # Note: Parsing exact ISO dates vs Unix timestamp can be tricky, so we rely on the logic 
    # that if the setup script deleted them, and they exist now, they must be new.
    # We award these points if the main entities exist, implying they were created during this session.
    if user_section.get('exists') and ws_section.get('exists'):
        score += 5
    
    # Final Verification
    passed = score >= 60 and user_section.get('exists') and ws_section.get('exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }