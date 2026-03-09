#!/usr/bin/env python3
"""
Verifier for Isomer Physical State Differentiation task.

Task requires:
1. Identifying 3 isomers of Dichlorobenzene (1,2-, 1,3-, 1,4-)
2. Finding their Melting Points
3. Determining State (Solid/Liquid) at 20°C
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_isomer_physical_state(traj, env_info, task_info):
    """
    Verifies the content of the isomer analysis file.
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

    # Basic checks
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found at ~/Documents/isomer_analysis.txt"}
    
    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task session"}

    content = result.get("file_content", "").lower()  # normalize case for easier searching
    if len(content) < 20:
        return {"passed": False, "score": 10, "feedback": "File created but content is empty or too short"}

    # Scoring Logic
    score = 10  # Base score for creating file
    feedback_parts = []
    
    metadata = task_info.get("metadata", {})
    isomers = metadata.get("isomers", {})

    # Helper to check for isomer presence and accuracy
    def check_isomer(name, data):
        isomer_score = 0
        isomer_feedback = []
        
        # 1. Identity Check (Name or CAS)
        # Search for any of the keywords
        found_identity = any(k.lower() in content for k in data.get("keywords", []))
        found_cas = data.get("cas") in content
        
        if found_identity or found_cas:
            isomer_score += 5
            isomer_feedback.append(f"Found entry for {name}")
        else:
            return 0, [f"Missing entry for {name}"]

        # 2. Melting Point Check (Approximate)
        # Look for numbers near the expected MP
        expected_mp = data.get("mp_c_approx")
        # Regex to find numbers, allowing for negatives and decimals
        # We look for the number in the whole text, which is lenient, but usually sufficient combined with state check
        # To be stricter, we'd split the file by lines, but simple regex search is often robust enough for simple text files
        mp_found = False
        
        # Ranges: +/- 5 degrees tolerance
        lower_bound = expected_mp - 5
        upper_bound = expected_mp + 5
        
        # Find all numbers in content
        numbers = [float(x) for x in re.findall(r'-?\d+\.?\d*', content)]
        for num in numbers:
            if lower_bound <= num <= upper_bound:
                mp_found = True
                break
        
        if mp_found:
            isomer_score += 10
            isomer_feedback.append(f"Correct MP (~{expected_mp}C)")
        else:
            isomer_feedback.append(f"Missing/Incorrect MP (expected ~{expected_mp}C)")

        # 3. Physical State Check
        expected_state = data.get("state_at_20c").lower()
        
        # We need to associate the state with the specific isomer. 
        # Simple approach: Check if the state word exists near the isomer name? 
        # For this verification, we will check global presence if simple, 
        # but to distinguish 1,4-solid from 1,2-liquid, we need context.
        # Since we have the whole content string, let's try to split by lines and process each line.
        
        lines = content.split('\\n') # content from JSON has escaped newlines
        state_correct = False
        
        for line in lines:
            # If line contains identity
            if any(k.lower() in line for k in data.get("keywords", [])) or (data.get("cas") in line):
                # Check for state in this line
                if expected_state in line:
                    state_correct = True
                    break
                # Special case: if expected is liquid, ensure "solid" is NOT in line (unless it says "not solid" etc, but keep simple)
                if expected_state == "liquid" and "solid" in line:
                    state_correct = False 
                if expected_state == "solid" and "liquid" in line:
                    state_correct = False

        if state_correct:
            isomer_score += 15
            isomer_feedback.append(f"Correct State ({expected_state.upper()})")
        else:
            isomer_feedback.append(f"Incorrect/Missing State (expected {expected_state.upper()})")
            
        return isomer_score, isomer_feedback

    # Check all three isomers
    total_isomer_score = 0
    
    # 1,2-Dichlorobenzene (Liquid)
    s1, f1 = check_isomer("1,2-Dichlorobenzene", isomers["1,2-Dichlorobenzene"])
    total_isomer_score += s1
    feedback_parts.extend(f1)
    
    # 1,3-Dichlorobenzene (Liquid)
    s2, f2 = check_isomer("1,3-Dichlorobenzene", isomers["1,3-Dichlorobenzene"])
    total_isomer_score += s2
    feedback_parts.extend(f2)
    
    # 1,4-Dichlorobenzene (Solid)
    s3, f3 = check_isomer("1,4-Dichlorobenzene", isomers["1,4-Dichlorobenzene"])
    total_isomer_score += s3
    feedback_parts.extend(f3)

    score += total_isomer_score

    # Final logic check
    # If they got the states right, they likely did the task.
    # Pass threshold: 70
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }