#!/usr/bin/env python3
"""
Verifier for Hierarchical RBAC Implementation.

Checks:
1. Schema existence (Classes: AppUser, AppGroup, AppResource, MemberOf, HasAccess)
2. Graph Topology (Correct vertices and edge relationships)
3. Audit Report correctness (Sarah's entitlements)
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_hierarchical_rbac_implementation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    db_state = result.get('db_state', {})
    
    # --- 1. Schema Verification (20 pts) ---
    schema = db_state.get('schema', {})
    classes = [c.get('name') for c in schema.get('classes', [])]
    
    required_classes = ["AppUser", "AppGroup", "AppResource", "MemberOf", "HasAccess"]
    missing_classes = [c for c in required_classes if c not in classes]
    
    if not missing_classes:
        score += 20
        feedback_parts.append("Schema classes created correctly.")
    else:
        feedback_parts.append(f"Missing schema classes: {', '.join(missing_classes)}.")

    # --- 2. Graph Topology Verification (30 pts) ---
    # Helper to check vertex existence
    def get_names(json_result, key):
        return [item.get(key) for item in json_result.get('result', []) if item.get(key)]

    users = get_names(db_state.get('users', {}), 'username')
    groups = get_names(db_state.get('groups', {}), 'name')
    resources = get_names(db_state.get('resources', {}), 'name')

    topo_score = 0
    if 'sarah.connor' in users and 'john.smith' in users: topo_score += 5
    if {'Engineering_Leads', 'Software_Engineers', 'Full_Time_Staff'}.issubset(set(groups)): topo_score += 5
    if {'aws_prod_keys', 'git_repository', 'office_wifi'}.issubset(set(resources)): topo_score += 5

    # Check Edges (Topology)
    member_edges = db_state.get('member_edges', {}).get('result', [])
    access_edges = db_state.get('access_edges', {}).get('result', [])
    
    # Verify group hierarchy: Leads -> Engineers -> Staff
    hierarchy_valid = False
    has_leads_eng = any(e.get('group_src') == 'Engineering_Leads' and e.get('group_tgt') == 'Software_Engineers' for e in member_edges)
    has_eng_staff = any(e.get('group_src') == 'Software_Engineers' and e.get('group_tgt') == 'Full_Time_Staff' for e in member_edges)
    
    if has_leads_eng and has_eng_staff:
        topo_score += 10
        hierarchy_valid = True
    
    # Verify Sarah membership
    if any(e.get('user') == 'sarah.connor' and e.get('group_tgt') == 'Engineering_Leads' for e in member_edges):
        topo_score += 5

    if topo_score == 30:
        feedback_parts.append("Graph topology is correct.")
    else:
        feedback_parts.append(f"Graph topology issues (Score: {topo_score}/30).")
    
    score += topo_score

    # --- 3. Permissions Verification (20 pts) ---
    perm_score = 0
    # Expected: Leads->aws (admin), Eng->git (write), Staff->wifi (read)
    expected_perms = [
        ('Engineering_Leads', 'aws_prod_keys', 'admin'),
        ('Software_Engineers', 'git_repository', 'write'),
        ('Full_Time_Staff', 'office_wifi', 'read')
    ]
    
    found_perms = 0
    for grp, res, lvl in expected_perms:
        match = any(e.get('group') == grp and e.get('resource') == res and e.get('level') == lvl for e in access_edges)
        if match: found_perms += 1
    
    if found_perms == 3:
        perm_score = 20
        feedback_parts.append("Permission edges correct.")
    else:
        feedback_parts.append(f"Permission edges incomplete ({found_perms}/3 found).")
    
    score += perm_score

    # --- 4. Audit Report Verification (30 pts) ---
    report_data = result.get('output_file', {})
    if not report_data.get('exists'):
        feedback_parts.append("Audit report file not found.")
    else:
        try:
            content_str = report_data.get('content_raw', "[]").replace('\\"', '"')
            # Handle potential double encoding if the shell script over-escaped
            if content_str.startswith('"') and content_str.endswith('"'):
                content_str = json.loads(content_str)
            
            entitlements = json.loads(content_str)
            
            # Verify entitlements for Sarah
            # Sarah -> Leads (direct) -> AWS (admin)
            # Sarah -> Leads -> Engineers (inherited) -> Git (write)
            # Sarah -> Leads -> Engineers -> Staff (inherited) -> Wifi (read)
            
            expected_entitlements = {
                'aws_prod_keys': 'admin',
                'git_repository': 'write',
                'office_wifi': 'read'
            }
            
            matches = 0
            for item in entitlements:
                res = item.get('resource')
                perm = item.get('permission')
                if res in expected_entitlements and expected_entitlements[res] == perm:
                    matches += 1
            
            if matches >= 3 and len(entitlements) == 3:
                score += 30
                feedback_parts.append("Audit report is accurate.")
            elif matches > 0:
                score += (matches * 10)
                feedback_parts.append(f"Audit report partially correct ({matches}/3).")
            else:
                feedback_parts.append("Audit report content incorrect.")
                
        except json.JSONDecodeError:
            feedback_parts.append("Audit report is not valid JSON.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }