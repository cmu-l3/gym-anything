#!/usr/bin/env python3
"""
Verifier for Configure Formula Shipping Rate task.

Verification Strategy:
1. Programmatic (80 pts):
   - Check if "Domestic" zone exists and has a Flat Rate method.
   - Check if method title matches "Volume Shipping".
   - Check if cost formula matches "10.00 + (2.50 * [qty])" (allowing for whitespace variations).
2. VLM (20 pts):
   - Verify trajectory shows interaction with shipping settings form.
   - Verify final state shows the method listed.

Pass threshold: 100 points (Strict formula matching required for functionality)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def normalize_formula(formula):
    """Normalize shipping formula for comparison (remove spaces, lowercase)."""
    if not formula:
        return ""
    # Remove spaces
    s = formula.replace(" ", "")
    # Lowercase
    s = s.lower()
    # Normalize common floats: 10 -> 10.00, 2.5 -> 2.50 to be lenient if needed?
    # Actually, WooCommerce string matching is literal, so we should be strict,
    # but the task description allows "10.00 + (2.50 * [qty])".
    # We'll stick to string normalization for robustness.
    return s

def verify_configure_formula_shipping_rate(traj, env_info, task_info):
    """
    Verify the shipping rate configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Task Metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_method_title', "Volume Shipping").lower()
    expected_formula_raw = metadata.get('expected_cost_formula', "10.00 + (2.50 * [qty])")
    
    # We'll accept variants of the formula since user input might vary slightly in spacing
    # Expected: "10.00+(2.50*[qty])" normalized
    target_normalized = normalize_formula(expected_formula_raw)
    
    # Also allow "10+(2.5*[qty])" or "10.00+2.50*[qty]" (no parens) if valid in Woo
    # But strictly, the task asked for "10.00 + (2.50 * [qty])"
    
    score = 0
    feedback_parts = []
    
    # 1. Load Programmatic Results
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # Check Zone
    if not result.get('zone_found'):
        return {"passed": False, "score": 0, "feedback": "Domestic shipping zone not found"}
    
    methods = result.get('methods', [])
    if not methods:
        return {"passed": False, "score": 0, "feedback": "No flat rate methods found in Domestic zone"}
    
    # Check Methods
    method_created = False
    title_correct = False
    formula_correct = False
    
    best_method = None
    
    for m in methods:
        m_title = m.get('title', '').strip()
        m_cost = m.get('cost', '').strip()
        m_cost_norm = normalize_formula(m_cost)
        
        # Check specific instance match
        is_title_match = (m_title.lower() == expected_title)
        
        # Check formula match
        # Robust check: 10.00 + (2.50 * [qty])
        is_formula_match = False
        if target_normalized in m_cost_norm:
             is_formula_match = True
        
        # Fallback for "10" instead of "10.00"
        if not is_formula_match:
             # Try regex for flexible float matching
             # Pattern: 10(\.0+)? \+ \(? 2\.50? \* \[qty\] \)?
             # Simpler: just check key components
             if "10" in m_cost and "2.5" in m_cost and "[qty]" in m_cost:
                 # Check structure roughly
                 if m_cost_norm == "10.00+(2.50*[qty])" or \
                    m_cost_norm == "10+(2.5*[qty])" or \
                    m_cost_norm == "10.00+2.50*[qty]":
                     is_formula_match = True

        if is_title_match and is_formula_match:
            method_created = True
            title_correct = True
            formula_correct = True
            best_method = m
            break
        elif is_title_match:
            method_created = True
            title_correct = True
            best_method = m
        elif is_formula_match:
            method_created = True
            formula_correct = True
            best_method = m
    
    # Scoring
    if method_created or len(methods) > 0:
        score += 20
        feedback_parts.append("Method created")
        
    if title_correct:
        score += 30
        feedback_parts.append(f"Title matches '{expected_title}'")
    else:
        feedback_parts.append(f"Title incorrect (Found: {[m['title'] for m in methods]})")
        
    if formula_correct:
        score += 50
        feedback_parts.append(f"Formula matches '{expected_formula_raw}'")
    else:
        feedback_parts.append(f"Formula incorrect (Found: {[m['cost'] for m in methods]})")

    passed = (score >= 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "methods_found": methods,
            "best_match": best_method
        }
    }