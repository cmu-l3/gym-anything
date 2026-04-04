#!/usr/bin/env python3
"""Verifier for Search Synonyms SEO task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_terms(term_string):
    """
    Parse a comma-separated string into a set of normalized terms.
    e.g., " Laptop, Notebook " -> {"laptop", "notebook"}
    """
    if not term_string:
        return set()
    return {t.strip().lower() for t in term_string.split(',') if t.strip()}


def verify_search_synonyms(traj, env_info, task_info):
    """
    Verify that the 5 expected synonym groups were created.

    Criteria:
    - Group 1: laptop, notebook, ultrabook (20 pts)
    - Group 2: phone, smartphone, mobile, cellphone (20 pts)
    - Group 3: headphones, earphones, earbuds, headset (20 pts)
    - Group 4: tshirt, tee, t-shirt (20 pts)
    - Group 5: jacket, coat, outerwear, parka (20 pts)

    Verification Logic:
    - Reads all synonym groups from DB.
    - For each expected group, checks if ANY DB row contains EXACTLY those terms (order independent).
    - Checks if the count increased (anti-gaming).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected groups from metadata
    metadata = task_info.get('metadata', {})
    expected_groups_list = metadata.get('expected_groups', [])
    
    # Fallback if metadata missing
    if not expected_groups_list:
        expected_groups_list = [
            ["laptop", "notebook", "ultrabook"],
            ["phone", "smartphone", "mobile", "cellphone"],
            ["headphones", "earphones", "earbuds", "headset"],
            ["tshirt", "tee", "t-shirt"],
            ["jacket", "coat", "outerwear", "parka"]
        ]

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/search_synonyms_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        initial_count = result.get('initial_count', 0)
        current_count = result.get('current_count', 0)
        db_groups = result.get('synonym_groups', [])

        logger.info(f"Counts: initial={initial_count}, current={current_count}")
        logger.info(f"DB Groups found: {len(db_groups)}")

        # Anti-gaming check: Did the user actually add anything?
        if current_count <= initial_count and len(expected_groups_list) > 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"No new synonym groups created. Initial count: {initial_count}, Current: {current_count}. Please create the groups as requested."
            }

        score = 0
        max_score = 100
        points_per_group = max_score / len(expected_groups_list)
        feedback_parts = []
        
        # Convert DB groups to list of sets for easy comparison
        # We perform case-insensitive, whitespace-stripped comparison
        db_group_sets = []
        for dbg in db_groups:
            terms = normalize_terms(dbg.get('synonyms', ''))
            store_id = str(dbg.get('store_id', '0')).strip()
            db_group_sets.append({'terms': terms, 'store': store_id})

        # Check each expected group
        for idx, expected_list in enumerate(expected_groups_list, 1):
            expected_set = {t.strip().lower() for t in expected_list}
            expected_str = ", ".join(expected_list)
            
            # Find a match in DB
            found = False
            for db_entry in db_group_sets:
                # We check if the DB entry contains ALL expected terms
                # Strict check: expected set must equal DB set? 
                # The prompt implies "Enter terms exactly as listed".
                # Let's allow strict set equality (order doesn't matter, but no extra terms allowed to avoid lazy "add everything to one group" gaming)
                # Or slightly relaxed: expected set must be subset of DB set?
                # "exactly as specified" -> Strict equality prefered.
                
                if db_entry['terms'] == expected_set:
                    found = True
                    break
            
            if found:
                score += points_per_group
                feedback_parts.append(f"✅ Group {idx} ({expected_str}) created")
            else:
                feedback_parts.append(f"❌ Group {idx} missing or incorrect. Expected: {expected_str}")

        passed = score >= 60  # Pass if 3 out of 5 groups are correct
        
        return {
            "passed": passed,
            "score": int(score),
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed due to error: {str(e)}"
        }