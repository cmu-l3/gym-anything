#!/usr/bin/env python3
"""
Verifier for Viral Marketing Analysis Task
"""
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_viral_marketing_analysis(traj, env_info, task_info):
    """
    Verifies that the agent:
    1. Added 'NetworkValue' and 'IsViralHub' properties to Profiles schema.
    2. Correctly calculated NetworkValue for test profiles.
    3. Correctly set IsViralHub based on the logic.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Metadata for expectations
    test_cases = task_info.get('metadata', {}).get('test_cases', {})
    
    # 1. Schema Verification (20 points)
    schema = result.get('schema', {})
    schema_passed = True
    
    # Check NetworkValue
    if 'NetworkValue' in schema:
        # OrientDB types: DOUBLE is often represented by ID or string in some contexts, 
        # but here we just check key existence first. 
        # Ideally check type, but loose check is safer for now.
        score += 10
        feedback.append("Schema: NetworkValue property exists.")
    else:
        schema_passed = False
        feedback.append("Schema: NetworkValue property MISSING.")

    # Check IsViralHub
    if 'IsViralHub' in schema:
        score += 10
        feedback.append("Schema: IsViralHub property exists.")
    else:
        schema_passed = False
        feedback.append("Schema: IsViralHub property MISSING.")

    # 2. Data Calculation Verification (80 points total)
    profiles = result.get('profiles', {})
    
    # Helper to check loose equality for floats
    def is_close(a, b, tol=1.0):
        try:
            return abs(float(a or 0) - float(b)) <= tol
        except:
            return False

    # Case A: Liam (The Hub) - Exp: 1750, Hub: True
    liam = profiles.get(test_cases['hub']['email'])
    if liam:
        val = liam.get('NetworkValue')
        is_hub = liam.get('IsViralHub')
        
        # Check Value (30 pts split)
        if is_close(val, 1750.0):
            score += 15
            feedback.append("Liam: NetworkValue correct (1750).")
        else:
            feedback.append(f"Liam: NetworkValue incorrect. Expected 1750, got {val}.")

        # Check Hub Status (25 pts split)
        if is_hub is True: # Strict True check
            score += 15
            feedback.append("Liam: IsViralHub correct (True).")
        else:
            feedback.append(f"Liam: IsViralHub incorrect. Expected True, got {is_hub}.")
    else:
        feedback.append("Liam profile not found in results.")

    # Case B: Damon (Popular but Cheap) - Exp: 50, Hub: False
    damon = profiles.get(test_cases['popular_low_spender']['email'])
    if damon:
        val = damon.get('NetworkValue')
        is_hub = damon.get('IsViralHub')
        
        if is_close(val, 50.0):
            score += 10
            feedback.append("Damon: NetworkValue correct (50).")
        else:
            feedback.append(f"Damon: NetworkValue incorrect. Expected 50, got {val}.")

        if is_hub is False:
            score += 10
            feedback.append("Damon: IsViralHub correct (False).")
        else:
            feedback.append(f"Damon: IsViralHub incorrect. Expected False, got {is_hub}.")

    # Case C: Graham (Loner) - Exp: 0, Hub: False
    graham = profiles.get(test_cases['loner']['email'])
    if graham:
        val = graham.get('NetworkValue')
        is_hub = graham.get('IsViralHub')
        
        if is_close(val, 0.0):
            score += 5
            feedback.append("Graham: NetworkValue correct (0).")
        else:
            feedback.append(f"Graham: NetworkValue incorrect. Expected 0, got {val}.")

        if is_hub is False:
            score += 5
            feedback.append("Graham: IsViralHub correct (False).")
        else:
            feedback.append(f"Graham: IsViralHub incorrect. Expected False, got {is_hub}.")

    passed = score >= 70 and schema_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }