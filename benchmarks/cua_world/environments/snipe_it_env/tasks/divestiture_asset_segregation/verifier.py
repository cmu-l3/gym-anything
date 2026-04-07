#!/usr/bin/env python3
"""
Verifier for divestiture_asset_segregation task.

Scoring breakdown (100 points):
  C1: Company 'Aura Health' created (10 pts)
  C2: 'Consumer Wearables' department associated with Aura Health (10 pts)
  C3: All employees in the Wearables department associated with Aura Health (20 pts)
  C4: All assets checked out to Wearables employees associated with Aura Health (30 pts)
  C5: All undeployed assets with 'Wearable' in the name associated with Aura Health (15 pts)
  C6: No collateral damage — Enterprise Health users/assets remain unchanged (15 pts)
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/divestiture_result.json"

def verify_divestiture_asset_segregation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(RESULT_PATH, temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found in VM."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result JSON: {e}"}

    score = 0
    feedback = []
    
    medtech_id = int(result.get("medtech_id", 0))
    aura_id = int(result.get("aura_id", 0))
    
    # Do-nothing detection: If Aura Health doesn't even exist, task wasn't attempted
    if aura_id == 0:
        return {"passed": False, "score": 0, "feedback": "DO-NOTHING: Company 'Aura Health' was not created."}
        
    score += 10
    feedback.append("C1: Company 'Aura Health' successfully created (+10)")
    
    def check_assignment(entity_data, entity_name, expected_id, pts_to_award):
        company_id = int(entity_data.get("company_id", 0))
        if company_id == expected_id:
            feedback.append(f"Pass: {entity_name} successfully assigned to company ID {expected_id} (+{pts_to_award})")
            return pts_to_award
        else:
            feedback.append(f"Fail: {entity_name} is assigned to company ID {company_id}, expected {expected_id} (+0)")
            return 0

    # C2: Department update
    score += check_assignment(result.get("dept_wearable", {}), "Department 'Consumer Wearables'", aura_id, 10)
    
    # C3: User update
    score += check_assignment(result.get("user_wearable", {}), "User 'Alice Wearable'", aura_id, 20)
    
    # C4: Deployed Asset update
    c4_pts = check_assignment(result.get("asset_w1", {}), "Deployed Asset AST-W1", aura_id, 30)
    score += c4_pts
    
    # C5: Unassigned Asset update
    score += check_assignment(result.get("asset_w2", {}), "Unassigned Asset AST-W2", aura_id, 15)
    
    # C6: Control Group / Collateral Damage
    c6_passed = True
    control_targets = [
        (result.get("dept_enterprise", {}), "Department 'Enterprise Health'"),
        (result.get("user_enterprise", {}), "User 'Bob Enterprise'"),
        (result.get("asset_e1", {}), "Control Asset AST-E1"),
        (result.get("asset_e2", {}), "Control Asset AST-E2")
    ]
    
    for entity, name in control_targets:
        current_cid = int(entity.get("company_id", 0))
        if current_cid != medtech_id:
            feedback.append(f"Fail (Collateral Damage): {name} was wrongly reassigned to company ID {current_cid}!")
            c6_passed = False
            
    if c6_passed:
        score += 15
        feedback.append("C6: Control group (Enterprise Health) safely remained unchanged (+15)")
        
    # Agent must correctly navigate relational targets (C4 > 0) AND avoid collateral damage to pass
    passed = score >= 80 and c4_pts > 0 and c6_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }