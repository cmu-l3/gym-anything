#!/usr/bin/env python3
"""
Verifier for detect_phonetic_duplicates task.

Criteria:
1. JSON output file validity (10 pts)
2. Script existence (10 pts)
3. Correctly identifies Exact Duplicate (20 pts)
4. Correctly identifies Accent Duplicate (20 pts)
5. Correctly identifies Typo Duplicate (20 pts)
6. Does NOT flag Homonym Control (20 pts)

Pass Threshold: 70 pts (Must find fuzzy matches and exclude homonyms)
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_name(name):
    """Normalize name for comparison (uppercase, remove extra spaces)."""
    if not name:
        return ""
    return " ".join(name.upper().split())

def verify_detect_phonetic_duplicates(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check File Existence & Validity (10 pts)
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file duplicate_candidates.json not found."}
    
    agent_output = result_data.get("agent_output")
    if not isinstance(agent_output, list):
        return {"passed": False, "score": 0, "feedback": "Output file is not a valid JSON list."}
    
    score += 10
    feedback_parts.append("Valid JSON output")

    # 2. Check Script Existence (10 pts)
    if result_data.get("script_exists", False):
        score += 10
        feedback_parts.append("Python script created")
    else:
        feedback_parts.append("Python script missing")

    # Prepare Ground Truth
    gt = result_data.get("ground_truth", {})
    
    # Helper to check if a specific pair was found
    # We check if (NameA in Pair AND NameB in Pair) OR (DOB matches if specified)
    def check_pair_found(agent_list, expected_names, expected_dob):
        """
        Check if any pair in agent_list matches the expected criteria.
        expected_names: list of strings (e.g. ['MARTIN Alice']) or list of lists for fuzzy
        """
        norm_expected = [normalize_name(n) for n in expected_names]
        
        for pair in agent_list:
            p_a = pair.get("patient_a", {})
            p_b = pair.get("patient_b", {})
            
            name_a = normalize_name(p_a.get("name", "") + " " + p_a.get("firstname", "")) # handle split fields if agent used them
            if not name_a: name_a = normalize_name(p_a.get("name", "")) # fallback simple key
            
            name_b = normalize_name(p_b.get("name", "") + " " + p_b.get("firstname", ""))
            if not name_b: name_b = normalize_name(p_b.get("name", ""))

            dob_a = str(p_a.get("dob", "")).split()[0] # basic date norm
            dob_b = str(p_b.get("dob", "")).split()[0]
            
            # Check DOB matches expected
            if dob_a != expected_dob or dob_b != expected_dob:
                continue

            # Check Names
            # We want to see if the SET of names in the pair matches the SET of expected names
            pair_names = {name_a, name_b}
            expected_set = set(norm_expected)
            
            # Simple set intersection/match
            # Allow flexible matching for "Last First" vs "First Last" if needed, but MedinTux usually distinguishes
            # For this task, we assume "Last First" concatenation
            
            # Exact Match Case: expected ['MARTIN Alice'], pair should contain 'MARTIN Alice' twice
            if len(expected_set) == 1:
                target = list(expected_set)[0]
                if name_a == target and name_b == target:
                    return True
            else:
                # Fuzzy Case: expected ['DUBOIS Hélène', 'DUBOIS Helene']
                # Pair must contain both (order doesn't matter)
                if expected_set == pair_names:
                    return True
                
                # Loose check for reversed order (First Last)
                rev_names = {" ".join(n.split()[::-1]) for n in pair_names}
                if expected_set == rev_names:
                    return True

        return False

    # 3. Check Exact Duplicate (20 pts)
    if check_pair_found(agent_output, gt['exact_match']['names'], gt['exact_match']['dob']):
        score += 20
        feedback_parts.append("Found Exact Duplicate")
    else:
        feedback_parts.append("Missed Exact Duplicate")

    # 4. Check Accent Duplicate (20 pts)
    if check_pair_found(agent_output, gt['accent_match']['names'], gt['accent_match']['dob']):
        score += 20
        feedback_parts.append("Found Accent Duplicate")
    else:
        feedback_parts.append("Missed Accent Duplicate")

    # 5. Check Typo Duplicate (20 pts)
    if check_pair_found(agent_output, gt['typo_match']['names'], gt['typo_match']['dob']):
        score += 20
        feedback_parts.append("Found Typo Duplicate")
    else:
        feedback_parts.append("Missed Typo Duplicate")

    # 6. Check Homonym Control (20 pts)
    # This one fails if FOUND.
    # The control case has different DOBs.
    homonym_name = normalize_name(gt['homonym_control']['name'])
    control_failed = False
    
    for pair in agent_output:
        p_a = pair.get("patient_a", {})
        p_b = pair.get("patient_b", {})
        
        n_a = normalize_name(p_a.get("name", ""))
        n_b = normalize_name(p_b.get("name", ""))
        
        d_a = str(p_a.get("dob", ""))
        d_b = str(p_b.get("dob", ""))
        
        # If names match the control name
        if n_a == homonym_name and n_b == homonym_name:
            # And DOBs are different (which they are in control)
            if d_a != d_b:
                control_failed = True
                break
                
    if not control_failed:
        score += 20
        feedback_parts.append("Correctly ignored Homonyms")
    else:
        feedback_parts.append("Incorrectly flagged Homonyms (False Positive)")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }