#!/usr/bin/env python3
"""
Verifier for organize_product_taxonomy task.

Scoring (100 points):
1. Vocabulary 'product_categories' exists (10 pts)
2. All 4 required terms exist (20 pts - 5 each)
3. 'Category' field exists on Product entity (20 pts)
4. Field is correct type (entity_reference) (10 pts)
5. Sony headphones categorized correctly (20 pts)
6. Logitech mouse categorized correctly (20 pts)

Pass threshold: 60/100
"""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organize_product_taxonomy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_terms = set(t.lower() for t in metadata.get('expected_terms', []))
    expected_assignments = metadata.get('assignments', {})

    try:
        # Load result
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # 1. Vocabulary Check (10 pts)
        if result.get('vocab_exists'):
            score += 10
            subscores['vocab'] = True
            feedback_parts.append("Vocabulary 'product_categories' created")
        else:
            subscores['vocab'] = False
            feedback_parts.append("Vocabulary 'product_categories' NOT found")

        # 2. Terms Check (20 pts)
        actual_terms = [t.lower() for t in result.get('terms', [])]
        terms_found = 0
        missing_terms = []
        
        for term in expected_terms:
            if term in actual_terms:
                terms_found += 1
            else:
                missing_terms.append(term)
        
        term_score = terms_found * 5
        score += term_score
        subscores['terms_score'] = term_score
        
        if len(missing_terms) == 0:
            feedback_parts.append("All category terms created")
        else:
            feedback_parts.append(f"Missing terms: {', '.join(missing_terms)}")

        # 3. Field Existence (20 pts)
        if result.get('field_exists'):
            score += 20
            subscores['field_exists'] = True
            feedback_parts.append("Category field created on Product")
        else:
            subscores['field_exists'] = False
            feedback_parts.append("Category field NOT found on Product type")

        # 4. Field Type Check (10 pts)
        # Prevents creating a simple text list instead of taxonomy reference
        field_type = result.get('field_type', 'unknown')
        if field_type == 'entity_reference':
            score += 10
            subscores['field_type'] = True
            feedback_parts.append("Field type is correct (Entity Reference)")
        elif result.get('field_exists'):
            feedback_parts.append(f"Field type incorrect: got '{field_type}', expected 'entity_reference'")
        
        # 5 & 6. Product Assignments (40 pts total)
        actual_assignments = result.get('assignments', {})
        # Normalize keys for comparison
        actual_assignments_norm = {k.lower(): v.lower() for k, v in actual_assignments.items()}
        
        # Check Sony (20 pts)
        sony_key = "Sony WH-1000XM5 Wireless Headphones".lower()
        sony_expected = expected_assignments.get("Sony WH-1000XM5 Wireless Headphones", "").lower()
        
        if sony_key in actual_assignments_norm:
            actual = actual_assignments_norm[sony_key]
            if actual == sony_expected:
                score += 20
                feedback_parts.append("Sony headphones categorized correctly")
            else:
                feedback_parts.append(f"Sony headphones category mismatch: expected '{sony_expected}', got '{actual}'")
        else:
            feedback_parts.append("Sony headphones not categorized")

        # Check Logitech (20 pts)
        logi_key = "Logitech MX Master 3S Wireless Mouse".lower()
        logi_expected = expected_assignments.get("Logitech MX Master 3S Wireless Mouse", "").lower()
        
        if logi_key in actual_assignments_norm:
            actual = actual_assignments_norm[logi_key]
            if actual == logi_expected:
                score += 20
                feedback_parts.append("Logitech mouse categorized correctly")
            else:
                feedback_parts.append(f"Logitech mouse category mismatch: expected '{logi_expected}', got '{actual}'")
        else:
            feedback_parts.append("Logitech mouse not categorized")

        # Final Evaluation
        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification system error: {str(e)}"
        }