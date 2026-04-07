#!/usr/bin/env python3
"""
Verifier for create_commission_plan task.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_commission_plan(traj, env_info, task_info):
    """
    Verify the creation of a Sales Commission Plan in iDempiere.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_name', 'Q3 2024 Sales Incentive')
    expected_search_key = metadata.get('expected_search_key', 'COMM-Q3-2024')
    expected_rep = metadata.get('expected_rep_name', 'Joe Block')
    expected_line1_rate = float(metadata.get('expected_line1_rate', 5.0))
    expected_line2_rate = float(metadata.get('expected_line2_rate', 10.0))
    expected_category = metadata.get('expected_category', 'Patio Furniture')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/final_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. Verify Header (55 points max)
    header = result.get('header')
    if not header:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No commission record found with search key " + expected_search_key
        }

    score += 10
    feedback.append("Commission record created.")

    # Name check
    if header.get('name') == expected_name:
        score += 10
        feedback.append("Name is correct.")
    else:
        feedback.append(f"Name mismatch: Expected '{expected_name}', got '{header.get('name')}'")

    # Business Partner check
    if header.get('bp_name') == expected_rep:
        score += 10
        feedback.append("Sales Rep is correct.")
    else:
        feedback.append(f"Sales Rep mismatch: Expected '{expected_rep}', got '{header.get('bp_name')}'")

    # Currency check
    if header.get('currency') == 'USD':
        score += 5
        feedback.append("Currency is USD.")
    else:
        feedback.append(f"Currency mismatch: Got '{header.get('currency')}'")

    # Frequency check ('Q' for Quarterly)
    if header.get('frequencytype') == 'Q':
        score += 5
        feedback.append("Frequency is Quarterly.")
    else:
        feedback.append(f"Frequency mismatch: Got '{header.get('frequencytype')}'")

    # Basis check ('I' for Invoice)
    if header.get('docbasistype') == 'I':
        score += 10
        feedback.append("Calc Basis is Invoice.")
    else:
        feedback.append(f"Basis mismatch: Got '{header.get('docbasistype')}'")
        
    # List Details check ('Y')
    if header.get('listdetails') == 'Y':
        score += 5
        feedback.append("List Details enabled.")

    # 2. Verify Lines (45 points max)
    lines = result.get('lines', [])
    
    # Sort lines by multiplier to easier matching
    lines.sort(key=lambda x: x.get('multiplier', 0))
    
    line1_found = False
    line2_found = False

    # Check for Base Line (5% rate, no category or empty category)
    for line in lines:
        rate = line.get('multiplier', 0.0)
        cat = line.get('category')
        is_pos = line.get('positive_only') == 'Y'
        
        # Tolerance for float comparison
        if abs(rate - expected_line1_rate) < 0.1:
            if not cat or cat == 'None' or cat == '':
                score += 15
                feedback.append(f"Base commission line ({expected_line1_rate}%) found.")
                line1_found = True
                if is_pos:
                    score += 2.5
                break
    
    # Check for Bonus Line (10% rate, Patio Furniture category)
    for line in lines:
        rate = line.get('multiplier', 0.0)
        cat = line.get('category')
        is_pos = line.get('positive_only') == 'Y'
        
        if abs(rate - expected_line2_rate) < 0.1:
            if cat == expected_category:
                score += 15
                feedback.append(f"Bonus commission line ({expected_line2_rate}% on {expected_category}) found.")
                line2_found = True
                if is_pos:
                    score += 2.5
                break

    if not line1_found:
        feedback.append(f"Missing base commission line ({expected_line1_rate}% on all categories).")
    if not line2_found:
        feedback.append(f"Missing bonus commission line ({expected_line2_rate}% on {expected_category}).")
        
    # Anti-gaming check (creation count)
    if result.get('final_count', 0) > result.get('initial_count', 0):
        score += 5
        feedback.append("Record count increased.")
    
    final_score = min(100, score)
    passed = final_score >= 60 and line1_found or line2_found
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback)
    }