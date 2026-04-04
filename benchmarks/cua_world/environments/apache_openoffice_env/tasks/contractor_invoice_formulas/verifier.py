#!/usr/bin/env python3
"""
Verifier for contractor_invoice_formulas task.

Verifies:
1. File existence
2. Content accuracy (Company/Client names)
3. **Use of formulas** (Primary Anti-Gaming Check)
4. Calculation accuracy
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_contractor_invoice_formulas(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    expected_subtotal = metadata.get('expected_values', {}).get('subtotal', 3350.50)
    expected_total = metadata.get('expected_values', {}).get('grand_total', 3534.78)
    tolerance = metadata.get('expected_values', {}).get('tolerance', 0.1)
    
    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback = []
    
    # 1. File Existence (10 pts)
    if result.get("file_exists"):
        score += 10
        feedback.append("File created successfully.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
        
    # 2. Content Check (10 pts)
    content = result.get("text_content", "")
    req_strings = metadata.get("required_strings", ["GreenLeaf", "Henderson"])
    missing = [s for s in req_strings if s.lower() not in content.lower()]
    
    if not missing:
        score += 10
        feedback.append("Required text content found.")
    else:
        feedback.append(f"Missing text content: {', '.join(missing)}")
        
    # 3. Formula Verification (CRITICAL - 50 pts)
    # The user must use table formulas, not type numbers manually.
    formula_count = result.get("formula_count", 0)
    min_formulas = metadata.get("min_formulas_count", 5) # 5 lines + sub + tax + total = 8 ideal
    
    if formula_count >= min_formulas:
        score += 50
        feedback.append(f"Excellent! {formula_count} formulas detected in table.")
    elif formula_count > 0:
        # Partial credit if they used some formulas but maybe missed summary rows
        score += 25
        feedback.append(f"Some formulas detected ({formula_count}), but expected at least {min_formulas}.")
    else:
        feedback.append("NO formulas detected. Did you manually type the calculations? The task requires using Table Formulas.")
        # Failing score if no formulas used, as that's the core skill test
    
    # 4. Calculation Accuracy (20 pts)
    # Check if the calculated values exist in the document (either as static text or formula results)
    # The export script extracts 'office:value' from the XML.
    values = result.get("calculated_values", [])
    
    found_subtotal = any(abs(v - expected_subtotal) <= tolerance for v in values)
    found_total = any(abs(v - expected_total) <= tolerance for v in values)
    
    if found_subtotal and found_total:
        score += 20
        feedback.append("Calculated values match expectations.")
    elif found_total:
        score += 10
        feedback.append("Grand total matches, but subtotal not explicitly found as a value.")
    else:
        feedback.append(f"Expected Grand Total ({expected_total}) not found in document metadata.")
        
    # 5. Currency Formatting (10 pts)
    if result.get("currency_format_count", 0) >= 5:
        score += 10
        feedback.append("Currency formatting applied.")
    else:
        feedback.append("Currency formatting missing or insufficient.")

    passed = (score >= 70) and (formula_count > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }