#!/usr/bin/env python3
"""
Verifier for Enrich Product Fields task.

Scoring Breakdown (100 pts total):
1. 'Brands' Vocabulary Created (10 pts)
2. All 5 Brand Terms Exist (15 pts)
3. 'Brand' Field Configured correctly (10 pts)
4. 'Weight' Field Configured correctly (10 pts)
5. Product Data Accuracy (55 pts):
   - 5 pts per correct brand assignment (25 max)
   - 6 pts per correct weight assignment (30 max)

Pass Threshold: 60/100
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_enrich_product_fields(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    metadata = task_info.get('metadata', {})
    expected_product_data = metadata.get('product_data', {})
    expected_terms = set(t.lower() for t in metadata.get('expected_terms', []))
    
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/enrich_product_fields_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    
    score = 0
    feedback = []
    
    # 1. Check Vocabulary (10 pts)
    if result.get('vocab_exists', 0) > 0:
        score += 10
        feedback.append("Vocab 'brands' created.")
    else:
        feedback.append("Vocab 'brands' NOT found.")
        
    # 2. Check Terms (15 pts)
    found_terms = result.get('terms_found', [])
    found_terms_lower = set(t.lower() for t in found_terms)
    
    # Check overlap
    missing_terms = expected_terms - found_terms_lower
    if not missing_terms:
        score += 15
        feedback.append("All brand terms found.")
    else:
        # Partial credit? Let's do 3 pts per term
        term_matches = len(expected_terms) - len(missing_terms)
        score += term_matches * 3
        feedback.append(f"Missing terms: {list(missing_terms)}")
        
    # 3. Check Fields (20 pts)
    if result.get('field_brand_exists'):
        score += 10
        feedback.append("Field 'field_brand' exists.")
    else:
        feedback.append("Field 'field_brand' missing.")
        
    if result.get('field_weight_exists'):
        score += 10
        feedback.append("Field 'field_weight' exists.")
    else:
        feedback.append("Field 'field_weight' missing.")
        
    # 4. Check Product Data (55 pts)
    actual_data_map = result.get('product_data', {})
    
    # Map expected partial keys to actual keys found
    # The actual keys in result are full titles from DB
    
    data_score = 0
    
    for expected_key_partial, expected_vals in expected_product_data.items():
        # Find matching key in actual results
        matched_key = next((k for k in actual_data_map.keys() if expected_key_partial in k), None)
        
        if matched_key:
            actual_vals = actual_data_map[matched_key]
            
            # Check Brand (5 pts)
            act_brand = actual_vals.get('brand')
            if act_brand and act_brand.lower() == expected_vals['brand'].lower():
                data_score += 5
            else:
                feedback.append(f"{expected_key_partial}: Brand mismatch (Exp: {expected_vals['brand']}, Got: {act_brand})")
            
            # Check Weight (6 pts)
            act_weight = actual_vals.get('weight')
            exp_weight = expected_vals['weight']
            if act_weight is not None:
                try:
                    if abs(float(act_weight) - float(exp_weight)) < 0.005:
                        data_score += 6
                    else:
                        feedback.append(f"{expected_key_partial}: Weight mismatch (Exp: {exp_weight}, Got: {act_weight})")
                except:
                    feedback.append(f"{expected_key_partial}: Weight invalid")
            else:
                feedback.append(f"{expected_key_partial}: Weight not set")
        else:
            feedback.append(f"Product '{expected_key_partial}' not found in DB.")
            
    score += data_score
    feedback.append(f"Data verification score: {data_score}/55")
    
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }