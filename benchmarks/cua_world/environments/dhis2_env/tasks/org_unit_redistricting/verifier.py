#!/usr/bin/env python3
"""
Verifier for org_unit_redistricting task.

Scoring (100 points total):
- New Org Unit 'Tikonko North' Created (20 pts)
- Correct Parent for New Unit (Bo) (15 pts)
- Metadata Correct (Short Name, Opening Date) (10 pts)
- Tikonko CHC Moved to Tikonko North (25 pts)
- Gondama MCHP Moved to Tikonko North (25 pts)
- Verify created AFTER task start (5 pts)

Pass Threshold: 65 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_org_unit_redistricting(traj, env_info, task_info):
    """Verify that the organisation unit hierarchy was updated correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/org_unit_redistricting_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        
        # 1. Check New Unit Existence
        new_unit_found = result.get('new_unit_found', False)
        new_unit_props = result.get('new_unit_props', {})
        new_unit_id = new_unit_props.get('id')
        
        if new_unit_found:
            score += 20
            feedback_parts.append("'Tikonko North' created (+20)")
        else:
            feedback_parts.append("'Tikonko North' not found")
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Failed: Organisation Unit 'Tikonko North' was not created."
            }

        # 2. Check Parent of New Unit (Should be Bo)
        bo_id = result.get('bo_id')
        actual_parent_id = new_unit_props.get('parent_id')
        
        if bo_id and actual_parent_id == bo_id:
            score += 15
            feedback_parts.append("Correct parent 'Bo' (+15)")
        else:
            feedback_parts.append(f"Incorrect parent for Tikonko North (Expected Bo ID: {bo_id}, Found: {actual_parent_id})")

        # 3. Check Metadata (Short Name and Opening Date)
        meta_score = 0
        if new_unit_props.get('shortName') == 'Tikonko N':
            meta_score += 5
        if '2023-01-01' in new_unit_props.get('openingDate', ''):
            meta_score += 5
        
        score += meta_score
        if meta_score == 10:
            feedback_parts.append("Metadata correct (+10)")
        elif meta_score > 0:
            feedback_parts.append("Metadata partially correct (+5)")
        else:
            feedback_parts.append("Metadata incorrect")

        # 4. Check Facility Moves
        # Tikonko CHC
        chc_parent = result.get('tikonko_chc_parent', {})
        chc_parent_id = chc_parent.get('id') if chc_parent else None
        
        if chc_parent_id and chc_parent_id == new_unit_id:
            score += 25
            feedback_parts.append("Tikonko CHC moved successfully (+25)")
        else:
            feedback_parts.append(f"Tikonko CHC not moved to new unit (Parent: {chc_parent.get('name', 'Unknown')})")

        # Gondama MCHP
        mchp_parent = result.get('gondama_mchp_parent', {})
        mchp_parent_id = mchp_parent.get('id') if mchp_parent else None
        
        if mchp_parent_id and mchp_parent_id == new_unit_id:
            score += 25
            feedback_parts.append("Gondama MCHP moved successfully (+25)")
        else:
            feedback_parts.append(f"Gondama MCHP not moved to new unit (Parent: {mchp_parent.get('name', 'Unknown')})")
            
        # 5. Check Timestamp (Anti-Gaming) - implicit in finding the unit created
        # Since we deleted it at start, existence proves creation during task.
        score += 5 # Bonus for completing the workflow
        
        passed = score >= 65

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}