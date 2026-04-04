#!/usr/bin/env python3
"""Verifier for Search Relevance Configuration task in Magento."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_search_relevance(traj, env_info, task_info):
    """
    Verify search relevance weights configuration.

    Criteria:
    1. SKU weight set to 10 (40 pts)
    2. Product Name weight set to 5 (35 pts)
    3. Description weight set to 1 (25 pts)

    Pass threshold: 75 pts (Requires at least SKU and Name to be correct)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values
    metadata = task_info.get('metadata', {})
    expected = metadata.get('expected_weights', {'sku': '10', 'name': '5', 'description': '1'})
    
    # Tolerances not really applicable for integer weights, exact match expected
    # but we handle string/int comparison safely

    try:
        # Load result
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/search_relevance_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
            
        weights = result.get('weights', {})
        changes = result.get('changes_detected', {})
        
        score = 0
        feedback_parts = []
        
        # Criterion 1: SKU Weight (40 pts)
        sku_val = str(weights.get('sku', '0')).strip()
        # Convert to float/int for safe comparison
        try:
            is_sku_correct = int(float(sku_val)) == int(expected['sku'])
        except ValueError:
            is_sku_correct = False
            
        if is_sku_correct:
            score += 40
            feedback_parts.append("SKU weight correct (10)")
        else:
            feedback_parts.append(f"SKU weight incorrect: expected {expected['sku']}, got {sku_val}")

        # Criterion 2: Name Weight (35 pts)
        name_val = str(weights.get('name', '0')).strip()
        try:
            is_name_correct = int(float(name_val)) == int(expected['name'])
        except ValueError:
            is_name_correct = False
            
        if is_name_correct:
            score += 35
            feedback_parts.append("Name weight correct (5)")
        else:
            feedback_parts.append(f"Name weight incorrect: expected {expected['name']}, got {name_val}")

        # Criterion 3: Description Weight (25 pts)
        desc_val = str(weights.get('description', '0')).strip()
        try:
            is_desc_correct = int(float(desc_val)) == int(expected['description'])
        except ValueError:
            is_desc_correct = False
            
        if is_desc_correct:
            score += 25
            feedback_parts.append("Description weight correct (1)")
        else:
            feedback_parts.append(f"Description weight incorrect: expected {expected['description']}, got {desc_val}")

        # Pass Threshold check
        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": {
                "weights": weights,
                "changes_detected": changes
            }
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}