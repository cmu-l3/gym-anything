#!/usr/bin/env python3
"""
Verifier for Simultaneous Equations (3SLS) task in Gretl.

Verifies:
1. Output file existence and freshness.
2. Correct estimation method (3SLS).
3. Correct system specification (2 equations).
4. Economic validity of coefficients (Demand Law: P < 0, Supply Law: P > 0).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sem_supply_demand_3sls(traj, env_info, task_info):
    """
    Verify 3SLS estimation of truffles supply/demand system.
    """
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Load Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Check Basic Criteria
    score = 0
    feedback_parts = []
    
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    score += 10 # File exists
    
    if result.get("file_created_during_task", False):
        score += 10 # Created during task
    else:
        feedback_parts.append("File not created during this session (stale?).")

    # 4. Content Analysis
    # Copy the actual output file from environment
    output_path = result.get("output_path")
    content = ""
    if output_path:
        temp_out = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(output_path, temp_out.name)
            with open(temp_out.name, 'r', errors='ignore') as f:
                content = f.read()
        except Exception as e:
            feedback_parts.append(f"Could not read output file content: {e}")
        finally:
            if os.path.exists(temp_out.name):
                os.unlink(temp_out.name)

    # 5. Verify Estimation Method (3SLS)
    # Gretl output for 3SLS typically contains: "System: ... 3SLS" or "Three-Stage Least Squares"
    method_ok = False
    if re.search(r"Three-Stage Least Squares|3SLS", content, re.IGNORECASE):
        score += 20
        method_ok = True
        feedback_parts.append("Method identified as 3SLS.")
    elif re.search(r"Two-Stage Least Squares|2SLS|TSLS", content, re.IGNORECASE):
        score += 5
        feedback_parts.append("Used 2SLS instead of 3SLS (partial credit).")
    elif re.search(r"Ordinary Least Squares|OLS", content, re.IGNORECASE):
        feedback_parts.append("Used OLS (incorrect for simultaneous equations).")
    else:
        feedback_parts.append("Could not identify estimation method.")

    # 6. Verify System Structure (2 Equations)
    # Look for "Equation 1" and "Equation 2" or variable headers
    equations_found = len(re.findall(r"Equation \d+:", content))
    if equations_found >= 2:
        score += 20
        feedback_parts.append("System contains at least 2 equations.")
    elif "Equation 1" in content and "Equation 2" in content: # Alternate check
        score += 20
    else:
        # Gretl system output might list "Equation 1: q" ... "Equation 2: q"
        if content.count("Dependent variable: q") >= 2:
            score += 20
            feedback_parts.append("Found two equations for 'q'.")

    # 7. Verify Coefficients (Signs)
    # We need to parse the coefficients for 'p' (Price)
    # Demand Eq: p should be Negative
    # Supply Eq: p should be Positive
    # This is tricky to parse robustly, so we look for patterns
    
    # regex to find blocks. 
    # Gretl system output usually separates equations.
    # Let's try to split by "Equation"
    
    demand_sign_correct = False
    supply_sign_correct = False
    
    # Normalize content
    lines = content.splitlines()
    
    # Heuristic: Find lines starting with "p " or "p" followed by numbers
    # We expect two such lines (one per equation)
    # Example line: "  p             -1.234   0.555   ..."
    
    p_coeffs = []
    for line in lines:
        # Match "p" or "const" etc. We want "p" specifically.
        # Regex: Start of line (maybe whitespace), "p", word boundary, whitespace, float
        match = re.search(r"^\s*p\b\s+([+-]?\d+\.\d+)", line)
        if match:
            try:
                val = float(match.group(1))
                p_coeffs.append(val)
            except:
                pass

    if len(p_coeffs) >= 2:
        # We need to distinguish Demand vs Supply.
        # Demand usually includes 'ps' and 'di'. Supply includes 'pf'.
        # But here we just check if ONE is negative and ONE is positive, 
        # which validates identification of the curves.
        
        has_negative = any(c < 0 for c in p_coeffs)
        has_positive = any(c > 0 for c in p_coeffs)
        
        if has_negative:
            score += 20
            demand_sign_correct = True
        else:
            feedback_parts.append("No negative price coefficient found (Law of Demand violated?).")
            
        if has_positive:
            score += 20
            supply_sign_correct = True
        else:
            feedback_parts.append("No positive price coefficient found (Law of Supply violated?).")
            
        if demand_sign_correct and supply_sign_correct:
            feedback_parts.append("Price coefficients have correct signs (Demand < 0, Supply > 0).")
    else:
        feedback_parts.append(f"Could not parse 'p' coefficients (found {len(p_coeffs)}).")

    # 8. Final Scoring
    passed = (score >= 70) and method_ok and demand_sign_correct and supply_sign_correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }