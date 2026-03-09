#!/usr/bin/env python3
"""
Verifier for project_funding_classification task.

Scoring Criteria:
1. Category Options Created (20 pts): 'Project Alpha', 'Beta', 'Gamma', 'Delta' exist.
2. Category Option Groups Created (20 pts): 'Global Fund' and 'USAID' groups exist.
3. Group Membership (20 pts): Options are correctly assigned to groups.
4. Group Set Configured (20 pts): 'Donor Funding Source' exists, contains groups, AND has dataDimension=True.
5. Visualization (20 pts): Visualization exists and uses the Group Set as a dimension.

Pass Threshold: 80 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_project_funding_classification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/project_funding_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check Options (20 pts)
    # Expect 4 specific names
    expected_opts = ["Project Alpha", "Project Beta", "Project Gamma", "Project Delta"]
    found_opts = [o['name'] for o in data.get('options', [])]
    
    opts_found_count = sum(1 for e in expected_opts if e in found_opts)
    if opts_found_count == 4:
        score += 20
        feedback.append("All 4 Project Options found.")
    else:
        score += opts_found_count * 5
        feedback.append(f"Found {opts_found_count}/4 Project Options.")

    # 2. Check Groups (20 pts)
    groups = data.get('groups', [])
    gf_group = next((g for g in groups if "global fund" in g['name'].lower()), None)
    usaid_group = next((g for g in groups if "usaid" in g['name'].lower()), None)

    if gf_group:
        score += 10
        feedback.append("Global Fund Group found.")
    else:
        feedback.append("Global Fund Group NOT found.")

    if usaid_group:
        score += 10
        feedback.append("USAID Group found.")
    else:
        feedback.append("USAID Group NOT found.")

    # 3. Check Membership (20 pts)
    membership_score = 0
    if gf_group:
        gf_members = [o['name'] for o in gf_group.get('categoryOptions', [])]
        if "Project Alpha" in gf_members and "Project Beta" in gf_members:
            membership_score += 10
    
    if usaid_group:
        usaid_members = [o['name'] for o in usaid_group.get('categoryOptions', [])]
        if "Project Gamma" in usaid_members and "Project Delta" in usaid_members:
            membership_score += 10
            
    score += membership_score
    if membership_score == 20:
        feedback.append("Group memberships correct.")
    else:
        feedback.append("Group memberships incorrect or incomplete.")

    # 4. Check Group Set (20 pts)
    # Must exist, contain the groups, and have dataDimension=True
    group_sets = data.get('group_sets', [])
    target_gs = None
    for gs in group_sets:
        # Check name
        if "donor" in gs['name'].lower() or "funding" in gs['name'].lower():
            target_gs = gs
            break
    
    if target_gs:
        gs_score = 0
        feedback.append(f"Group Set '{target_gs['name']}' found.")
        
        # Check Data Dimension flag (Critical!)
        if target_gs.get('dataDimension') is True:
            gs_score += 10
            feedback.append("Data Dimension enabled.")
        else:
            feedback.append("Data Dimension NOT enabled (0 pts).")
            
        # Check if it contains the groups
        gs_groups = [g['id'] for g in target_gs.get('categoryOptionGroups', [])]
        
        has_gf = gf_group and gf_group['id'] in gs_groups
        has_usaid = usaid_group and usaid_group['id'] in gs_groups
        
        if has_gf and has_usaid:
            gs_score += 10
            feedback.append("Group Set contains both donor groups.")
        else:
            feedback.append("Group Set missing one or more donor groups.")
            
        score += gs_score
    else:
        feedback.append("Donor Funding Group Set NOT found.")

    # 5. Check Visualization (20 pts)
    # Must use the Group Set ID in rows, columns, or filters
    visualizations = data.get('visualizations', [])
    
    viz_valid = False
    if target_gs:
        gs_id = target_gs['id']
        for v in visualizations:
            # Aggregate all dimensions used in the viz
            used_dims = []
            for dim_list in [v.get('columns', []), v.get('rows', []), v.get('filters', [])]:
                used_dims.extend([d['id'] for d in dim_list])
            
            if gs_id in used_dims:
                viz_valid = True
                break
    
    if viz_valid:
        score += 20
        feedback.append("Visualization uses the new Donor dimension.")
    else:
        feedback.append("Visualization using the new dimension NOT found.")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }