#!/usr/bin/env python3
"""Verifier for Search Term Redirect task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_search_term_redirect(traj, env_info, task_info):
    """
    Verify creation of 3 search term redirects.

    Criteria:
    1. Term 'cheap laptops' exists (10pts) and redirects to /electronics.html (20pts)
    2. Term 'gym equipment' exists (10pts) and redirects to /sports.html (20pts)
    3. Term 'mens outfit' exists (10pts) and redirects to /clothing.html (20pts)
    4. Store scope is set correctly (10pts total)

    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_terms = metadata.get('terms', [])
    # Default fallback if metadata missing
    if not expected_terms:
        expected_terms = [
            {"query": "cheap laptops", "redirect": "/electronics.html"},
            {"query": "gym equipment", "redirect": "/sports.html"},
            {"query": "mens outfit", "redirect": "/clothing.html"}
        ]

    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/search_term_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # Check initial vs current count for anti-gaming (at least some increase)
        initial = result.get('initial_count', 0)
        current = result.get('current_count', 0)
        if current <= initial:
            feedback_parts.append("No new search terms were added to the database.")
        
        # Map result keys to our expected list order
        term_keys = ['term1', 'term2', 'term3']
        
        for i, expected in enumerate(expected_terms):
            key = term_keys[i] if i < len(term_keys) else f'term{i+1}'
            term_data = result.get(key, {})
            
            query = expected['query']
            expected_redirect = expected['redirect']
            
            # 1. Existence Check (10 pts)
            if term_data.get('exists', False):
                score += 10
                feedback_parts.append(f"Term '{query}' exists (+10)")
                
                # 2. Redirect Check (20 pts)
                # Allow fuzzy match on redirect (e.g. with or without leading slash)
                actual_redirect = term_data.get('redirect', '').strip()
                # normalize both by stripping leading slash
                norm_expected = expected_redirect.lstrip('/')
                norm_actual = actual_redirect.lstrip('/')
                
                if norm_expected in norm_actual:
                    score += 20
                    feedback_parts.append(f"Redirect for '{query}' correct (+20)")
                else:
                    feedback_parts.append(f"Redirect for '{query}' incorrect. Expected '{expected_redirect}', got '{actual_redirect}'")
                    
            else:
                feedback_parts.append(f"Term '{query}' NOT found")

        # 3. Scope Check (10 pts total if any exist)
        # We just check if any store_id is valid (not NULL/empty). 
        # Magento usually saves '0' for All Store Views or specific ID.
        scope_ok = False
        for i in range(3):
            key = term_keys[i]
            term_data = result.get(key, {})
            if term_data.get('exists', False):
                sid = term_data.get('store_id', '')
                # valid if it's a number (including 0)
                if str(sid).isdigit():
                    scope_ok = True
                    break
        
        if scope_ok:
            score += 10
            feedback_parts.append("Store scope set correctly (+10)")
        
        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed: {e}"}