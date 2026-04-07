#!/usr/bin/env python3
"""
Verifier for MTM CTA Tracking task.
"""

import json
import logging
import tempfile
import os
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mtm_implementation(traj, env_info, task_info):
    """
    Verify the Matomo Tag Manager configuration.
    
    Criteria:
    1. Trigger Created: Condition 'ClickId' equals 'hero-cta-primary'
    2. Tag Created: Type 'Matomo Analytics', Event Tracking
    3. Tag Attributes: Category='Engagement', Action='Hero Click'
    4. Linkage: Tag fires on the created Trigger
    5. Published: A new container version exists
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Parsed data
    triggers = result.get('triggers', [])
    tags = result.get('tags', [])
    versions = result.get('versions', [])
    task_start = result.get('task_start', 0)

    score = 0
    feedback = []
    
    # 1. Verify Trigger
    # Look for a trigger with specific conditions
    valid_trigger_found = False
    valid_trigger_id = None
    
    for t in triggers:
        # Check params structure for ClickId condition
        # Structure usually: conditions: [ { filter: 'ClickId', operator: 'equals', value: 'hero-cta-primary' } ]
        params = t.get('parameters', {})
        conditions = params.get('conditions', [])
        
        for cond in conditions:
            # Matomo stores filters as 'ClickId' or similar. 
            # We check for the value mostly.
            val = cond.get('value', '')
            op = cond.get('operator', '')
            if 'hero-cta-primary' in val and 'equals' in op:
                valid_trigger_found = True
                valid_trigger_id = t.get('idtrigger')
                feedback.append(f"Found valid trigger: {t.get('name')}")
                break
        if valid_trigger_found:
            break
            
    if valid_trigger_found:
        score += 25
    else:
        feedback.append("No trigger found with ClickID equals 'hero-cta-primary'")

    # 2. Verify Tag Existence & Type
    valid_tag_found = False
    tag_attrs_correct = False
    tag_linked = False
    
    for t in tags:
        params = t.get('parameters', {})
        
        # Check Tag Type (Matomo Analytics)
        # Usually implies some specific parameter keys or 'type' field in DB if not in params
        # We focus on the Event configuration
        tracking_type = params.get('trackingType', '')
        
        if tracking_type == 'event':
            valid_tag_found = True
            
            # Check Attributes
            cat = params.get('eventCategory', '')
            act = params.get('eventAction', '')
            
            if 'Engagement' in cat and 'Hero Click' in act:
                tag_attrs_correct = True
                
                # Check Linkage
                # trigger_list is usually a list of IDs in the tag parameters
                linked_triggers = params.get('trigger_list', [])
                # Sometimes it's a comma string or list
                if valid_trigger_id and (valid_trigger_id in linked_triggers or str(valid_trigger_id) in linked_triggers):
                    tag_linked = True
                    feedback.append(f"Found valid tag: {t.get('name')} linked to trigger")
                    break
    
    if valid_tag_found:
        score += 25
    else:
        feedback.append("No tag found with tracking type 'Event'")

    if tag_attrs_correct:
        score += 20
    elif valid_tag_found:
        feedback.append("Tag found but event Category/Action incorrect")

    if tag_linked:
        score += 15
    elif valid_tag_found and valid_trigger_found:
        feedback.append("Tag and Trigger exist but are not linked")

    # 3. Verify Publication (Anti-gaming check)
    # Check if a version was created AFTER task start
    version_published = False
    for v in versions:
        ts_created_str = v.get('ts_created', '')
        # ts_created comes from PHP as "YYYY-MM-DD HH:MM:SS" usually
        try:
            # Simple check: if we have datetime string
            dt = datetime.strptime(ts_created_str, "%Y-%m-%d %H:%M:%S")
            ts = dt.timestamp()
            if ts > task_start:
                version_published = True
                break
        except:
            pass
            
    if version_published:
        score += 15
        feedback.append("New container version published")
    else:
        feedback.append("No new container version published since task start")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback)
    }