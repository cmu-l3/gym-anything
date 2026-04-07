#!/usr/bin/env python3
"""Verifier for Create Database Activity task in Moodle."""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_database_activity(traj, env_info, task_info):
    """
    Verify creation of Moodle Database activity with specific fields and entry.
    
    Scoring Criteria (100 pts):
    1. Database activity exists in BIO101 (15 pts)
    2. Activity name matches 'Medication Reference Database' (10 pts)
    3. Fields defined correctly:
       - 'Drug Name' [text] (10 pts)
       - 'Drug Class' [menu] (15 pts)
       - 'Indications' [textarea] (10 pts)
       - 'Common Side Effects' [textarea] (10 pts)
    4. At least one entry exists (15 pts)
    5. Entry content contains 'Amoxicillin' (15 pts)
    
    Pass Threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/create_database_activity_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Activity Existence (15 pts)
        if result.get('activity_found', False):
            # Check for newly created
            initial = int(result.get('initial_count', 0))
            current = int(result.get('current_count', 0))
            if current > initial:
                score += 15
                feedback_parts.append("New Database activity created")
            else:
                score += 10 # Found but count didn't increase? (Maybe deleted one then added one, or verification glitch. Giving partial credit for state)
                feedback_parts.append("Database activity found (count didn't increase)")
        else:
            feedback_parts.append("Database activity NOT found")
            return {"passed": False, "score": 0, "feedback": "Activity not found"}

        # 2. Name Match (10 pts)
        act_name = result.get('activity_name', '').lower()
        if 'medication reference' in act_name:
            score += 10
            feedback_parts.append("Activity name correct")
        else:
            feedback_parts.append(f"Name mismatch: '{result.get('activity_name')}'")

        # 3. Field Verification (45 pts total)
        fields = result.get('fields', [])
        
        # Helper to find field by fuzzy name
        def find_field(pattern):
            for f in fields:
                if re.search(pattern, f.get('name', ''), re.IGNORECASE):
                    return f
            return None

        # Drug Name (text)
        f_name = find_field(r'drug\s*name')
        if f_name:
            if f_name['type'] == 'text':
                score += 10
                feedback_parts.append("'Drug Name' field correct")
            else:
                score += 5
                feedback_parts.append(f"'Drug Name' wrong type: {f_name['type']}")
        else:
            feedback_parts.append("'Drug Name' field missing")

        # Drug Class (menu)
        f_class = find_field(r'drug\s*class')
        if f_class:
            if f_class['type'] == 'menu':
                score += 15
                feedback_parts.append("'Drug Class' field correct")
                # Optional: Check params/options?
                # params = f_class.get('param1', '')
                # if 'antibiotic' in params.lower(): score += extra
            else:
                score += 5
                feedback_parts.append(f"'Drug Class' wrong type: {f_class['type']}")
        else:
            feedback_parts.append("'Drug Class' field missing")

        # Indications (textarea)
        f_ind = find_field(r'indication')
        if f_ind:
            if f_ind['type'] == 'textarea':
                score += 10
                feedback_parts.append("'Indications' field correct")
            else:
                score += 5
                feedback_parts.append(f"'Indications' wrong type: {f_ind['type']}")
        else:
            feedback_parts.append("'Indications' field missing")

        # Side Effects (textarea)
        f_side = find_field(r'side\s*effect')
        if f_side:
            if f_side['type'] == 'textarea':
                score += 10
                feedback_parts.append("'Side Effects' field correct")
            else:
                score += 5
                feedback_parts.append(f"'Side Effects' wrong type: {f_side['type']}")
        else:
            feedback_parts.append("'Side Effects' field missing")

        # 4. Entry Existence (15 pts)
        entries = result.get('entries', [])
        if len(entries) > 0:
            score += 15
            feedback_parts.append("Entry created")
            
            # 5. Content Check (15 pts)
            entry = entries[0] # Check first entry found
            # Flatten values string for searching
            all_content = " ".join([str(v) for v in entry.values()]).lower()
            
            if 'amoxicillin' in all_content:
                score += 15
                feedback_parts.append("Entry content matches (Amoxicillin)")
            elif 'antibiotic' in all_content:
                score += 10
                feedback_parts.append("Entry content partial match (Antibiotic)")
            else:
                feedback_parts.append("Entry content mismatch")
        else:
            feedback_parts.append("No entries found")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}