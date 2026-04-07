#!/usr/bin/env python3
"""
Verifier for configure_indexer_auditor_access task.

Checks:
1. User 'compliance_auditor' exists with correct backend roles.
2. Role 'compliance_read_alerts' exists with correct index patterns and permissions.
3. Role mapping exists linking the user to the role.
4. Functional access: User can read wazuh-alerts-* but cannot read system indices or write data.
5. Agent created evidence files.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_indexer_auditor_access(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # === 1. User Verification (20 pts) ===
    user_data = result.get('api_state', {}).get('user', {})
    target_user_key = 'compliance_auditor'
    
    if target_user_key in user_data:
        score += 15
        user_props = user_data[target_user_key]
        backend_roles = user_props.get('backend_roles', [])
        description = user_props.get('description', '')
        
        if 'auditors' in backend_roles and 'PCI-DSS' in description:
            score += 5
            feedback_parts.append("User 'compliance_auditor' created correctly.")
        else:
            feedback_parts.append("User created but missing backend role or correct description.")
    else:
        feedback_parts.append("User 'compliance_auditor' NOT found.")

    # === 2. Role Verification (30 pts) ===
    role_data = result.get('api_state', {}).get('role', {})
    target_role_key = 'compliance_read_alerts'
    
    if target_role_key in role_data:
        score += 15
        role_props = role_data[target_role_key]
        
        # Check Cluster Perms
        cluster_perms = role_props.get('cluster_permissions', [])
        if 'cluster_composite_ops_ro' in cluster_perms:
            score += 5
        
        # Check Index Perms
        index_perms = role_props.get('index_permissions', [])
        found_alerts = False
        found_monitoring = False
        perms_correct = True
        
        for entry in index_perms:
            patterns = entry.get('index_patterns', [])
            actions = entry.get('allowed_actions', [])
            
            # Check for overly permissive actions
            for action in actions:
                if action not in ['read', 'search', 'indices:data/read/search', 'indices:data/read/get']:
                    # Allow specific low-level read actions or the alias groups
                    pass 
                if '*' in action or 'write' in action or 'delete' in action:
                    perms_correct = False

            if 'wazuh-alerts-*' in patterns:
                found_alerts = True
            if 'wazuh-monitoring-*' in patterns:
                found_monitoring = True
                
        if found_alerts and found_monitoring:
            score += 5
            if perms_correct:
                score += 5
                feedback_parts.append("Role 'compliance_read_alerts' configured correctly.")
            else:
                feedback_parts.append("Role permissions are too broad (check allowed_actions).")
        else:
            feedback_parts.append("Role missing required index patterns.")
    else:
        feedback_parts.append("Role 'compliance_read_alerts' NOT found.")

    # === 3. Mapping Verification (15 pts) ===
    mapping_data = result.get('api_state', {}).get('mapping', {})
    
    if target_role_key in mapping_data:
        score += 10
        mapping_props = mapping_data[target_role_key]
        mapped_users = mapping_props.get('users', [])
        
        if target_user_key in mapped_users:
            score += 5
            feedback_parts.append("Role mapping correct.")
        else:
            feedback_parts.append(f"Role mapping exists but user '{target_user_key}' not assigned.")
    else:
        feedback_parts.append("Role mapping NOT found.")

    # === 4. Functional Testing (25 pts) ===
    func_tests = result.get('functional_tests', {})
    pos_code = func_tests.get('positive_search_code', 0)
    neg_code = func_tests.get('negative_search_code', 0)
    write_code = func_tests.get('write_test_code', 0)
    
    # Positive: Expect 200 OK
    if pos_code == 200:
        score += 10
        feedback_parts.append("Auditor can successfully query alert indices.")
    else:
        feedback_parts.append(f"Auditor FAILED to query alert indices (HTTP {pos_code}).")

    # Negative: Expect 403 Forbidden
    if neg_code == 403:
        score += 10
        feedback_parts.append("Auditor correctly denied access to security index.")
    elif neg_code == 200:
        score -= 5 # Penalty for security breach
        feedback_parts.append("SECURITY FAIL: Auditor could access restricted system indices!")
    else:
        feedback_parts.append(f"Unexpected response for restricted index (HTTP {neg_code}).")
        
    # Write Check: Expect 403
    if write_code == 403:
        score += 5
        feedback_parts.append("Auditor correctly denied write access.")
    elif write_code in [200, 201]:
        score -= 5
        feedback_parts.append("SECURITY FAIL: Auditor has write permissions!")

    # === 5. Evidence Files (10 pts) ===
    files = result.get('file_artifacts', {})
    if files.get('user_check_exists') and files.get('role_check_exists') and files.get('access_test_exists'):
        score += 10
        feedback_parts.append("All evidence files created.")
    else:
        feedback_parts.append("Some evidence files are missing.")

    # Final Check
    passed = score >= 60 and pos_code == 200 and neg_code == 403
    
    return {
        "passed": passed,
        "score": max(0, min(100, score)),
        "feedback": " | ".join(feedback_parts)
    }