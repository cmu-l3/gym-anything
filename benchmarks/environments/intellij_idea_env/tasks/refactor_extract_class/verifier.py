#!/usr/bin/env python3
"""Verifier for refactor_extract_class task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_extract_class(traj, env_info, task_info):
    """
    Verify that the 'AddressValidator' class was extracted from 'CustomerService'.
    
    Criteria:
    1. AddressValidator.java exists (20 pts)
    2. Logic moved: AddressValidator contains key methods/fields (30 pts)
    3. Source cleaned: CustomerService NO LONGER contains the implementation (20 pts)
    4. Dependency wired: CustomerService has a field of type AddressValidator (10 pts)
    5. Build & Tests pass (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Read result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    god_content = result.get('god_class_content', '')
    new_content = result.get('new_class_content', '')
    
    # --- Criterion 1: New Class Exists (20 pts) ---
    if result.get('new_class_exists', False):
        score += 20
        feedback_parts.append("AddressValidator.java created")
    else:
        feedback_parts.append("AddressValidator.java NOT found")
        # If class doesn't exist, we can't check much else, but we check if logic is still in God class
    
    # --- Criterion 2: Logic Moved to New Class (30 pts) ---
    if new_content:
        logic_score = 0
        # Check for presence of moved items in the new class
        if 'VALID_COUNTRY_CODES' in new_content: logic_score += 5
        if 'zipCodePatterns' in new_content: logic_score += 5
        if 'boolean validateAddress' in new_content: logic_score += 10
        if 'String formatAddressLabel' in new_content: logic_score += 5
        if 'String resolveRegion' in new_content: logic_score += 5
        
        score += logic_score
        feedback_parts.append(f"Logic in new class: {logic_score}/30 pts")
    else:
        feedback_parts.append("No content in new class")

    # --- Criterion 3: Source Cleaned (20 pts) ---
    if god_content:
        cleaned_score = 0
        # The methods should NOT be implemented in God Class anymore
        # They might exist as delegate calls, so we check for implementation details
        
        # Check if the regex pattern logic is gone from God class
        if 'Pattern.compile' not in god_content: 
            cleaned_score += 10
        
        # Check if the long format string is gone
        if '%s\\n%s, %s' not in god_content:
            cleaned_score += 5

        # Check if VALID_COUNTRY_CODES definition is gone
        if 'List.of("US", "CA"' not in god_content:
            cleaned_score += 5
            
        score += cleaned_score
        feedback_parts.append(f"Logic removed from CustomerService: {cleaned_score}/20 pts")
        
        # Anti-gaming: Ensure God class was actually modified
        if not result.get('file_modified_during_task', False):
            feedback_parts.append("WARNING: CustomerService.java was not modified!")
            score = 0 # Fail if no changes made

    # --- Criterion 4: Dependency Wired (10 pts) ---
    # CustomerService should have a field of type AddressValidator
    if god_content and re.search(r'AddressValidator\s+\w+;', god_content):
        score += 10
        feedback_parts.append("CustomerService delegates to AddressValidator")
    elif god_content and 'AddressValidator' in god_content:
        score += 5 # Partial credit if mentioned but maybe not clearly a field
        feedback_parts.append("AddressValidator referenced in CustomerService")
    else:
        feedback_parts.append("No reference to AddressValidator in CustomerService")

    # --- Criterion 5: Tests Pass (20 pts) ---
    if result.get('test_result') == 'pass':
        score += 20
        feedback_parts.append("Tests passed")
    else:
        feedback_parts.append("Tests FAILED")
        # Check if build failed vs tests failed
        if "COMPILATION ERROR" in result.get('test_output', ''):
            feedback_parts.append("(Compilation Error)")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }