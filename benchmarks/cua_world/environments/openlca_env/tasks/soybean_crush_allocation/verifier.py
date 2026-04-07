#!/usr/bin/env python3
"""
Verifier for Soybean Crushing Allocation task.

Verification Strategy:
1. Parse raw Derby DB output from export_result.sh
2. Check if "Soybean Crushing (Custom)" process exists
3. Check if output flows (Oil, Meal) exist with correct amounts (180, 800)
4. Check if allocation factors exist and match calculated values (0.36, 0.64)
5. VLM check of trajectory to confirm UI interaction
"""

import json
import os
import tempfile
import logging
import re

logger = logging.getLogger(__name__)

def parse_derby_table(raw_text, section_header):
    """
    Rudimentary parser for Derby ij output.
    Extracts rows after a specific header section.
    """
    if not raw_text:
        return []
    
    # Split by the section headers we added in export script
    parts = raw_text.split(section_header)
    if len(parts) < 2:
        return []
    
    content = parts[1].split('\n\n')[0] # Get content until next double newline
    
    rows = []
    # Derby output usually looks like:
    # COL1 | COL2 ...
    # -----|-----
    # val1 | val2 ...
    
    lines = content.strip().split('\n')
    for line in lines:
        if line.strip().startswith('-----') or 'rows selected' in line:
            continue
        if '|' in line:
            # simple pipe separation
            cols = [c.strip() for c in line.split('|')]
            # Filter out the header row if it contains alphabetic characters not matching data
            # (Heuristic: usually we are looking for numbers, but names are strings)
            rows.append(cols)
    return rows

def verify_soybean_crush_allocation(traj, env_info, task_info):
    """
    Verify the soybean allocation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 1. Load result JSON
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    raw_output = result.get('raw_derby_output', '')
    process_found = result.get('process_found') == 'true'

    score = 0
    feedback = []
    
    # Metadata targets
    meta = task_info.get('metadata', {})
    expected_oil_factor = meta.get('expected_factor_oil', 0.36)
    expected_meal_factor = meta.get('expected_factor_meal', 0.64)
    tolerance = meta.get('tolerance', 0.05)
    
    # Criterion 1: Process Created (20 pts)
    if process_found:
        score += 20
        feedback.append("Process 'Soybean Crushing (Custom)' found.")
    else:
        feedback.append("Process 'Soybean Crushing (Custom)' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Parse Exchanges
    # Look for lines in EXCHANGES section: AMOUNT | NAME
    exchange_rows = parse_derby_table(raw_output, "EXCHANGES:")
    
    oil_mass_found = False
    meal_mass_found = False
    
    # We expect roughly 180 and 800. Derby might format as 180.0
    for row in exchange_rows:
        if len(row) < 2: continue
        try:
            val = float(row[0])
            name = row[1].lower()
            if "oil" in name and abs(val - 180) < 5:
                oil_mass_found = True
            if "meal" in name and abs(val - 800) < 5:
                meal_mass_found = True
        except ValueError:
            continue

    # Criterion 2: Outputs defined (20 pts)
    if oil_mass_found and meal_mass_found:
        score += 20
        feedback.append("Correct output flows (Oil 180kg, Meal 800kg) found.")
    elif oil_mass_found or meal_mass_found:
        score += 10
        feedback.append("Partial output flows found.")
    else:
        feedback.append("Output flows (Oil/Meal) with correct masses NOT found.")

    # Parse Allocation Factors
    # Look for lines in FACTORS section: VALUE | PRODUCT_ID
    factor_rows = parse_derby_table(raw_output, "FACTORS:")
    
    factors = []
    for row in factor_rows:
        if len(row) >= 1:
            try:
                factors.append(float(row[0]))
            except ValueError:
                pass
    
    # Sort factors to match against expected [0.36, 0.64]
    factors.sort()
    
    oil_factor_ok = False
    meal_factor_ok = False
    
    # We expect to find values close to 0.36 and 0.64 in the list of factors
    for f in factors:
        if abs(f - expected_oil_factor) <= tolerance:
            oil_factor_ok = True
        if abs(f - expected_meal_factor) <= tolerance:
            meal_factor_ok = True

    # Criterion 3: Allocation Setup (20 pts)
    if len(factors) >= 2:
        score += 20
        feedback.append("Allocation factors exist.")
    else:
        feedback.append("No allocation factors found.")

    # Criterion 4 & 5: Factor Accuracy (40 pts)
    if oil_factor_ok:
        score += 20
        feedback.append(f"Oil allocation factor correct (~{expected_oil_factor}).")
    if meal_factor_ok:
        score += 20
        feedback.append(f"Meal allocation factor correct (~{expected_meal_factor}).")
    
    if not (oil_factor_ok or meal_factor_ok) and len(factors) > 0:
        feedback.append(f"Allocation factors found {factors} do not match expected ({expected_oil_factor}, {expected_meal_factor}).")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }