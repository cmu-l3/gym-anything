#!/usr/bin/env python3
"""
Verifier for create_ism_retention_policy task.

Criteria:
1. Policy 'wazuh-alert-retention' exists (10 pts)
2. Policy structure: 3 states (hot, warm, delete) (10 pts)
3. Hot state: Transitions to warm at 30d (15 pts)
4. Warm state: force_merge (1 segment) action (10 pts)
5. Warm state: read_only action (10 pts)
6. Warm state: Transitions to delete at 90d (15 pts)
7. Delete state: delete action (5 pts)
8. ISM Template: Matches 'wazuh-alerts-*' (10 pts)
9. Attachment: Policy attached to existing indices (15 pts)

Pass Threshold: 70 points
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_ism_retention_policy(traj, env_info, task_info):
    """Verify the creation and application of the ISM retention policy."""
    
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
    
    # 1. Check Policy Existence
    policy_def = result.get('policy_definition', {})
    policy_body = policy_def.get('policy', {})
    
    if '_id' in policy_def and policy_def['_id'] == 'wazuh-alert-retention':
        score += 10
        feedback_parts.append("Policy exists")
    else:
        return {"passed": False, "score": 0, "feedback": "Policy 'wazuh-alert-retention' not found"}

    # 2. Check States
    states = policy_body.get('states', [])
    state_names = [s.get('name') for s in states]
    
    if set(['hot', 'warm', 'delete']).issubset(set(state_names)):
        score += 10
        feedback_parts.append("States (hot, warm, delete) defined")
    else:
        feedback_parts.append(f"Missing states. Found: {state_names}")

    # 3. Check Hot State Transitions (30d)
    hot_state = next((s for s in states if s.get('name') == 'hot'), {})
    hot_transitions = hot_state.get('transitions', [])
    hot_to_warm = False
    for t in hot_transitions:
        if t.get('state_name') == 'warm':
            conditions = t.get('conditions', {})
            if conditions.get('min_index_age') == '30d':
                hot_to_warm = True
    
    if hot_to_warm:
        score += 15
        feedback_parts.append("Hot->Warm transition correct (30d)")
    else:
        feedback_parts.append("Hot->Warm transition missing or incorrect")

    # 4 & 5. Check Warm State Actions
    warm_state = next((s for s in states if s.get('name') == 'warm'), {})
    warm_actions = warm_state.get('actions', [])
    
    has_force_merge = False
    has_read_only = False
    
    for action in warm_actions:
        if 'force_merge' in action:
            if action['force_merge'].get('max_num_segments') == 1:
                has_force_merge = True
        if 'read_only' in action:
            has_read_only = True
            
    if has_force_merge:
        score += 10
        feedback_parts.append("Warm action: force_merge(1) correct")
    else:
        feedback_parts.append("Warm action: force_merge missing/incorrect")
        
    if has_read_only:
        score += 10
        feedback_parts.append("Warm action: read_only correct")
    else:
        feedback_parts.append("Warm action: read_only missing")

    # 6. Check Warm State Transitions (90d)
    warm_transitions = warm_state.get('transitions', [])
    warm_to_delete = False
    for t in warm_transitions:
        if t.get('state_name') == 'delete':
            conditions = t.get('conditions', {})
            if conditions.get('min_index_age') == '90d':
                warm_to_delete = True
                
    if warm_to_delete:
        score += 15
        feedback_parts.append("Warm->Delete transition correct (90d)")
    else:
        feedback_parts.append("Warm->Delete transition missing or incorrect")

    # 7. Check Delete State Actions
    delete_state = next((s for s in states if s.get('name') == 'delete'), {})
    delete_actions = delete_state.get('actions', [])
    has_delete = any('delete' in a for a in delete_actions)
    
    if has_delete:
        score += 5
        feedback_parts.append("Delete action correct")
    else:
        feedback_parts.append("Delete action missing")

    # 8. Check ISM Template
    ism_template = policy_body.get('ism_template', [])
    # can be a list or single dict depending on version/config
    if isinstance(ism_template, dict):
        ism_template = [ism_template]
        
    template_correct = False
    for tmpl in ism_template:
        patterns = tmpl.get('index_patterns', [])
        if 'wazuh-alerts-*' in patterns:
            template_correct = True
            
    if template_correct:
        score += 10
        feedback_parts.append("ISM Template correct")
    else:
        feedback_parts.append("ISM Template missing for wazuh-alerts-*")

    # 9. Check Policy Attachment (Attachment to existing indices)
    explanation = result.get('policy_explanation', {})
    # explanation response format: { "index_name": { "index.plugins.index_state_management.policy_id": "..." } } 
    # OR { "index_name": { "policy_id": "..." } } depending on API version
    
    attached_count = 0
    managed_indices = explanation.get('total_managed_indices', 0)
    
    # Iterate keys, ignoring metadata keys
    for k, v in explanation.items():
        if k == 'total_managed_indices': 
            continue
        
        pid = ""
        if isinstance(v, dict):
             # Try various locations where policy_id might be stored
            pid = v.get('policy_id', '')
            if not pid:
                pid = v.get('index.plugins.index_state_management.policy_id', '')
            if not pid:
                # deeper nested check
                pid = v.get('index', {}).get('plugins', {}).get('index_state_management', {}).get('policy_id', '')
        
        if pid == 'wazuh-alert-retention':
            attached_count += 1
            
    if attached_count > 0:
        score += 15
        feedback_parts.append(f"Policy attached to {attached_count} indices")
    else:
        feedback_parts.append("Policy NOT attached to existing indices")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }