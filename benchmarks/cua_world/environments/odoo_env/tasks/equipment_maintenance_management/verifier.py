#!/usr/bin/env python3
"""
Verifier for equipment_maintenance_management task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_equipment_maintenance_management(traj, env_info, task_info):
    """
    Verify 2 main components:
    1. New Equipment creation (Haas VF-2SS) with correct settings.
    2. Corrective Maintenance Request for existing equipment (Hydraulic Press).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_file.close()
    try:
        copy_from_env('/tmp/task_result.json', temp_file.name)
        with open(temp_file.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Error in export: {result['error']}"}

    score = 0
    feedback = []

    # 1. Equipment Verification (55 points max)
    if result.get('equip_found'):
        score += 20
        feedback.append("New equipment 'CNC Vertical Milling Machine' created (20/20)")
        
        # Category
        if result.get('category_correct'):
            score += 15
            feedback.append("Correct category 'CNC Machinery' assigned (15/15)")
        else:
            cat = result.get('equip_category_name', 'None')
            feedback.append(f"Incorrect category: {cat} (expected 'CNC Machinery') (0/15)")

        # Preventive Maintenance Period (90 days)
        period = result.get('equip_period', 0)
        if period == 90:
            score += 15
            feedback.append("Preventive Maintenance period set to 90 days (15/15)")
        else:
            feedback.append(f"Incorrect PM period: {period} (expected 90) (0/15)")

        # Team Assigned
        if result.get('equip_has_team'):
            score += 5
            feedback.append("Maintenance team assigned (5/5)")
        else:
            feedback.append("No maintenance team assigned (0/5)")
    else:
        feedback.append("New equipment NOT found created after task start (0/55)")

    # 2. Maintenance Request Verification (45 points max)
    if result.get('request_found'):
        score += 20
        feedback.append("Corrective maintenance request created (20/20)")

        # Link Verification (Anti-gaming)
        linked_id = result.get('request_linked_id')
        target_id = result.get('setup_target_id')
        
        if linked_id == target_id:
            score += 5
            feedback.append("Request linked to correct 'Hydraulic Press' equipment (5/5)")
        else:
            feedback.append(f"Request linked to WRONG equipment ID {linked_id} (expected {target_id}) (0/5)")

        # Priority (3 stars = '3')
        prio = str(result.get('request_priority', '0'))
        if prio == '3':
            score += 10
            feedback.append("Priority set to Urgent/3 stars (10/10)")
        else:
            feedback.append(f"Priority incorrect: {prio} (expected 3) (0/10)")

        # Description Check
        desc = (result.get('request_description') or "").lower()
        if 'leak' in desc or 'cylinder' in desc or 'fluid' in desc:
            score += 10
            feedback.append("Description contains failure details (10/10)")
        else:
            feedback.append("Description missing or generic (0/10)")
    else:
        feedback.append("No maintenance request found for Hydraulic Press created after task start (0/45)")

    # Final check
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }