#!/usr/bin/env python3
"""
Verifier for Custom LCIA Method task.

Checks:
1. Method creation in DB (Name, Categories, Factors)
2. Normalization/Weighting sets and factors
3. Exported result file existence and content

Scoring:
- Method Structure: 30 pts
- Characterization Factors: 20 pts
- Norm/Weight Sets: 30 pts
- Exported Result: 20 pts
"""

import json
import os
import tempfile
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_derby_output(raw_text):
    """
    Parses crude Derby ij output into list of dicts or list of lists.
    Assumes ij output format with headers and rows.
    """
    if not raw_text:
        return []
    
    lines = raw_text.splitlines()
    data = []
    # Skip header lines (usually until a line with ----)
    start_idx = 0
    for i, line in enumerate(lines):
        if line.strip().startswith('---'):
            start_idx = i + 1
            break
            
    for line in lines[start_idx:]:
        line = line.strip()
        if not line or line.startswith('(') or 'rows selected' in line:
            continue
        # Split by whitespace (ij columns are usually fixed width or space sep)
        # This is a heuristic; might be fragile if names contain spaces
        # Better heuristic: split by multiple spaces
        parts = re.split(r'\s{2,}', line)
        if len(parts) == 1: 
             parts = line.split() # Fallback
        data.append(parts)
    return data

def verify_custom_lcia_method(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    # 1. Method Existence (10 pts)
    if not result.get('method_found'):
        return {"passed": False, "score": 0, "feedback": "LCIA Method 'Corporate Eco-Strategy 2025' not found in database."}
    
    score += 10
    feedback.append("Method created.")

    # Parse DB dumps
    categories_raw = result.get('db_dump_categories', '')
    factors_raw = result.get('db_dump_factors', '')
    flows_raw = result.get('db_dump_flows', '')
    nw_sets_raw = result.get('db_dump_nw_sets', '')
    nw_factors_raw = result.get('db_dump_nw_factors', '')

    # 2. Categories Verification (20 pts)
    # Categories dump: ID | NAME | UNIT | ...
    # We look for "Climate Priority" and "Acidification Watch"
    has_climate = "Climate Priority" in categories_raw
    has_acid = "Acidification Watch" in categories_raw
    
    if has_climate: score += 10
    if has_acid: score += 10
    if has_climate and has_acid:
        feedback.append("Both impact categories found.")
    else:
        feedback.append(f"Categories status: Climate={has_climate}, Acidification={has_acid}")

    # 3. Characterization Factors Verification (20 pts)
    # Check if flows linked. We look for flow names in the flows dump and 
    # check if their IDs appear in the factors dump with value 1.0
    
    # Simple check: does flows dump contain CO2 and SO2?
    has_co2_flow = "Carbon dioxide" in flows_raw
    has_so2_flow = "Sulfur dioxide" in flows_raw
    
    # Does factors dump contain "1.0"?
    has_factor_1 = "1.0" in factors_raw
    
    if has_co2_flow and has_so2_flow and has_factor_1:
        score += 20
        feedback.append("Characterization factors linked correctly (Flows found + value 1.0).")
    else:
        score += 5 # Partial credit for trying
        feedback.append("Characterization factors incomplete or incorrect.")

    # 4. Normalization and Weighting Sets (30 pts)
    # Check NW sets names
    has_norm_set = "Reference Baseline 2020" in nw_sets_raw
    has_weight_set = "Strategic Weights" in nw_sets_raw
    
    if has_norm_set: score += 10
    if has_weight_set: score += 10
    
    # Check factors values
    # Look for 10000.0, 50.0, 0.8, 0.2 in nw_factors_raw
    factors_found = 0
    if "10000" in nw_factors_raw: factors_found += 1
    if "50.0" in nw_factors_raw: factors_found += 1
    if "0.8" in nw_factors_raw: factors_found += 1
    if "0.2" in nw_factors_raw: factors_found += 1
    
    if factors_found >= 4:
        score += 10
        feedback.append("All normalization and weighting factors verified.")
    elif factors_found > 0:
        score += 5
        feedback.append(f"Some normalization/weighting factors found ({factors_found}/4).")

    # 5. Exported Result (20 pts)
    if result.get('output_exists') and result.get('file_created_during_task'):
        score += 20
        feedback.append("Result file exported successfully.")
    elif result.get('output_exists'):
        score += 10
        feedback.append("Result file exists but timestamp unclear.")
    else:
        feedback.append("No result file exported.")

    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }