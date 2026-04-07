#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_family_migration(traj, env_info, task_info):
    """
    Verifies that the agent correctly extracted family members from notes
    and created structured records for them.
    """
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
    feedback = []
    
    # Define Ground Truth (from setup/task description)
    # Note in DB: "Paul (Garçon), né le 14 février 2015"
    gt_child1 = {
        "name": "Paul",
        "dob": "2015-02-14",
        "sex": "M",
        "address_keyword": "Paix"  # 10 Rue de la Paix
    }
    
    # Note in DB: "Juliette (Fille), née le 30 juin 2018"
    gt_child2 = {
        "name": "Juliette",
        "dob": "2018-06-30",
        "sex": "F",
        "address_keyword": "Paix"
    }

    # Verify Child 1 (Paul) - 50 Points Max
    c1 = result.get('child1', {})
    if c1.get('exists'):
        score += 15
        feedback.append("Child 1 (Paul) record created.")
        
        # Check DOB (Crucial - requires parsing "14 février 2015")
        if c1.get('dob') == gt_child1['dob']:
            score += 15
            feedback.append("Child 1 DOB correct.")
        else:
            feedback.append(f"Child 1 DOB incorrect (Expected {gt_child1['dob']}, got {c1.get('dob')}).")
            
        # Check Sex
        if c1.get('sex') == gt_child1['sex']:
            score += 10
            feedback.append("Child 1 Sex correct.")
            
        # Check Address (Context retention)
        addr = c1.get('address', '')
        if gt_child1['address_keyword'].lower() in addr.lower():
            score += 10
            feedback.append("Child 1 Address correct.")
        else:
            feedback.append("Child 1 Address incorrect (Should match mother's).")
    else:
        feedback.append("Child 1 (Paul) record NOT found.")

    # Verify Child 2 (Juliette) - 50 Points Max
    c2 = result.get('child2', {})
    if c2.get('exists'):
        score += 15
        feedback.append("Child 2 (Juliette) record created.")
        
        # Check DOB
        if c2.get('dob') == gt_child2['dob']:
            score += 15
            feedback.append("Child 2 DOB correct.")
        else:
            feedback.append(f"Child 2 DOB incorrect (Expected {gt_child2['dob']}, got {c2.get('dob')}).")
            
        # Check Sex
        if c2.get('sex') == gt_child2['sex']:
            score += 10
            feedback.append("Child 2 Sex correct.")
            
        # Check Address
        addr = c2.get('address', '')
        if gt_child2['address_keyword'].lower() in addr.lower():
            score += 10
            feedback.append("Child 2 Address correct.")
        else:
            feedback.append("Child 2 Address incorrect.")
    else:
        feedback.append("Child 2 (Juliette) record NOT found.")

    # Pass logic
    # Must have created both patients with correct DOBs to pass
    # Threshold 85 means they can miss minor address details but must get core demographics right
    passed = score >= 85

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }