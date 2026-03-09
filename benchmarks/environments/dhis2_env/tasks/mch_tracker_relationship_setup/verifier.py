#!/usr/bin/env python3
"""
Verifier for mch_tracker_relationship_setup task.

Scoring (100 points total):
- Tracked entity attribute exists (25 pts) [MANDATORY for partial]
    - Correct Value Type (Text) (10 pts)
    - Searchable (10 pts)
    - Short Name present (5 pts)
- Relationship Type exists (25 pts) [MANDATORY for partial]
    - From Constraint correct (10 pts)
    - To Constraint correct (10 pts)
    - Both constraints match 'Person' (5 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_mch_tracker_relationship_setup(traj, env_info, task_info):
    """Verify that the attribute and relationship type were created correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Copy result file
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        copy_from_env("/tmp/mch_tracker_setup_result.json", temp_path)
        
        with open(temp_path, 'r') as f:
            result = json.load(f)
            
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not retrieve or parse result file: {e}"}

    score = 0
    feedback_parts = []
    
    # --- Check Attribute (50 pts total) ---
    tea_found = result.get('attribute_found', False)
    tea_data = result.get('attribute_data') or {}
    
    if tea_found:
        score += 25
        feedback_parts.append("Attribute 'Mother Registration ID' created (+25)")
        
        # Check Value Type
        val_type = tea_data.get('valueType', '')
        if val_type == 'TEXT':
            score += 10
            feedback_parts.append("Value Type is TEXT (+10)")
        else:
            feedback_parts.append(f"Incorrect Value Type: {val_type} (expected TEXT)")
            
        # Check Searchable
        searchable = tea_data.get('searchable', False)
        if searchable:
            score += 10
            feedback_parts.append("Marked as Searchable (+10)")
        else:
            feedback_parts.append("Not marked as Searchable")
            
        # Check Short Name
        short_name = tea_data.get('shortName', '')
        if short_name and len(short_name) > 0:
            score += 5
            feedback_parts.append("Short Name present (+5)")
        else:
            feedback_parts.append("Short Name missing")
    else:
        feedback_parts.append("Target Attribute not found")

    # --- Check Relationship Type (50 pts total) ---
    rt_found = result.get('relationship_found', False)
    rt_data = result.get('relationship_data') or {}
    
    if rt_found:
        score += 25
        feedback_parts.append("Relationship Type 'Mother-Child' created (+25)")
        
        from_c = rt_data.get('fromConstraint', {})
        to_c = rt_data.get('toConstraint', {})
        
        # Check From Constraint (Should be Person)
        from_ent = from_c.get('relationshipEntity', '')
        from_name = from_c.get('trackedEntityTypeName', '').lower()
        
        # In DHIS2, relationshipEntity is 'TRACKED_ENTITY_INSTANCE'
        if from_ent == 'TRACKED_ENTITY_INSTANCE' and 'person' in from_name:
            score += 10
            feedback_parts.append("From-Constraint is Person (+10)")
        else:
            feedback_parts.append(f"From-Constraint incorrect ({from_name})")
            
        # Check To Constraint (Should be Person)
        to_ent = to_c.get('relationshipEntity', '')
        to_name = to_c.get('trackedEntityTypeName', '').lower()
        
        if to_ent == 'TRACKED_ENTITY_INSTANCE' and 'person' in to_name:
            score += 10
            feedback_parts.append("To-Constraint is Person (+10)")
        else:
            feedback_parts.append(f"To-Constraint incorrect ({to_name})")
            
        # Bonus for consistency
        if 'person' in from_name and 'person' in to_name:
            score += 5
            feedback_parts.append("Both constraints consistent (+5)")
            
    else:
        feedback_parts.append("Target Relationship Type not found")

    # Pass logic
    passed = score >= 60 and (tea_found or rt_found)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }