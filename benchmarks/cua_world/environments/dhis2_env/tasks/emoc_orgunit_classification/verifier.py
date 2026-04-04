#!/usr/bin/env python3
"""
Verifier for emoc_orgunit_classification task.

Scoring (100 points total):
1. Created required Org Unit Groups (15 pts each -> 45 total)
   - CEmOC Facilities
   - BEmOC Facilities
   - Non-EmOC Facilities
2. Assigned members to groups (5 pts each group -> 15 total)
3. Created Org Unit Group Set "EmOC Capability Level" (20 pts)
4. Group Set marked as Data Dimension (10 pts)
5. Group Set contains the 3 created groups (10 pts)

Pass threshold: 60 points
Mandatory: At least one group created.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_emoc_orgunit_classification(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        copy_from_env("/tmp/emoc_task_result.json", temp_path)
        
        with open(temp_path, 'r') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback_parts = []
    
    created_groups = result.get('created_groups', [])
    created_sets = result.get('created_sets', [])
    
    # 1. Verify Groups (45 pts + 15 pts for members)
    groups_found = {
        'cemoc': {'found': False, 'members': False, 'obj': None},
        'bemoc': {'found': False, 'members': False, 'obj': None},
        'non': {'found': False, 'members': False, 'obj': None}
    }
    
    for g in created_groups:
        name = g.get('name', '').lower()
        member_count = g.get('member_count', 0)
        
        if 'cemoc' in name and 'non' not in name:
            groups_found['cemoc']['found'] = True
            groups_found['cemoc']['members'] = member_count > 0
            groups_found['cemoc']['obj'] = g
        elif 'bemoc' in name:
            groups_found['bemoc']['found'] = True
            groups_found['bemoc']['members'] = member_count > 0
            groups_found['bemoc']['obj'] = g
        elif 'non-emoc' in name or 'non emoc' in name:
            groups_found['non']['found'] = True
            groups_found['non']['members'] = member_count > 0
            groups_found['non']['obj'] = g

    # Score groups
    for key, data in groups_found.items():
        if data['found']:
            score += 15
            feedback_parts.append(f"Group '{key.upper()}' created (+15)")
            if data['members']:
                score += 5
                feedback_parts.append(f"  - Members assigned (+5)")
            else:
                feedback_parts.append(f"  - No members assigned (0)")
        else:
            feedback_parts.append(f"Group '{key.upper()}' NOT found")

    # 2. Verify Group Set (40 pts)
    target_set = None
    for s in created_sets:
        name = s.get('name', '').lower()
        if 'emoc' in name and ('level' in name or 'capability' in name):
            target_set = s
            break
            
    if target_set:
        score += 20
        feedback_parts.append("Group Set created (+20)")
        
        if target_set.get('dataDimension', False):
            score += 10
            feedback_parts.append("Data Dimension enabled (+10)")
        else:
            feedback_parts.append("Data Dimension NOT enabled")
            
        # Check if groups are in the set
        # We look for overlap between created group names and set group names
        set_group_names = [gn.lower() for gn in target_set.get('groups', [])]
        found_in_set = 0
        for key, data in groups_found.items():
            if data['obj']:
                g_name = data['obj']['name'].lower()
                if g_name in set_group_names:
                    found_in_set += 1
        
        if found_in_set >= 2:
            score += 10
            feedback_parts.append(f"Set contains {found_in_set} correct groups (+10)")
        elif found_in_set > 0:
            score += 5
            feedback_parts.append(f"Set contains {found_in_set} correct groups (+5)")
        else:
            feedback_parts.append("Set empty or missing correct groups")
    else:
        feedback_parts.append("Group Set NOT found")

    passed = score >= 60 and any(g['found'] for g in groups_found.values())

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }