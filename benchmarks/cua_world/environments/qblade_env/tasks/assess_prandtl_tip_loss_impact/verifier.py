#!/usr/bin/env python3
"""
Verifier for assess_prandtl_tip_loss_impact.
Verifies that the agent ran two BEM simulations (one with tip loss, one without)
and correctly identified the performance impact.
"""

import json
import base64
import os
import re
import tempfile
import logging
from typing import Dict, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_bem_file(content_str: str) -> List[Tuple[float, float]]:
    """
    Parses QBlade export file content.
    Expects columns. Usually TSR is Col 0 or labeled 'lambda'/'TSR'.
    Cp is labeled 'Cp'/'Power Coeff'.
    
    Returns a list of (TSR, Cp) tuples.
    """
    data = []
    lines = content_str.splitlines()
    
    # Simple heuristic parser for QBlade text exports
    # They typically look like:
    # TSR   Cp   Ct ...
    # 3.0   0.2  0.4 ...
    
    header_found = False
    tsr_idx = -1
    cp_idx = -1
    
    for line in lines:
        parts = line.strip().split()
        if not parts:
            continue
            
        # Try to identify header
        if not header_found:
            lower_parts = [p.lower() for p in parts]
            # Find TSR column
            for i, p in enumerate(lower_parts):
                if 'tsr' in p or 'lambda' in p:
                    tsr_idx = i
                if 'cp' in p or 'power' in p: # QBlade sometimes uses "Power Coeff"
                    cp_idx = i
            
            if tsr_idx != -1 and cp_idx != -1:
                header_found = True
            continue
            
        # Parse data lines
        if header_found:
            try:
                # Handle cases where header might not align perfectly or extra chars
                if len(parts) > max(tsr_idx, cp_idx):
                    tsr_val = float(parts[tsr_idx])
                    cp_val = float(parts[cp_idx])
                    data.append((tsr_val, cp_val))
            except ValueError:
                continue
                
    # Fallback: if no header found, assume QBlade default: Col 0 = TSR, Col 1 or 2 = Cp
    # QBlade export often: TSR, Beta, Power, Cp, Ct... 
    # Let's try to extract numeric data and find the curve that looks like Cp (0 < max < 0.6)
    if not data and len(lines) > 5:
        numeric_rows = []
        for line in lines:
            try:
                nums = [float(x) for x in line.replace(',', ' ').split()]
                if len(nums) >= 2:
                    numeric_rows.append(nums)
            except ValueError:
                continue
        
        if numeric_rows:
            # Assume Col 0 is TSR (usually 3-10 range)
            # Find a column that looks like Cp (peak around 0.4-0.5)
            best_col = -1
            for col_i in range(1, len(numeric_rows[0])):
                vals = [r[col_i] for r in numeric_rows]
                if max(vals) > 0.1 and max(vals) < 0.6: # Reasonable Cp range
                    best_col = col_i
                    break
            
            if best_col != -1:
                for row in numeric_rows:
                    data.append((row[0], row[best_col]))
                    
    return data

def get_max_cp(data: List[Tuple[float, float]]) -> float:
    if not data:
        return 0.0
    return max(val for _, val in data)

def verify_assess_prandtl_tip_loss_impact(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    files_info = result.get("files", {})
    content_b64 = result.get("content_b64", {})
    
    # --- Criterion 1: Files Existence (10 pts) ---
    files_exist = (files_info.get("with_loss", {}).get("exists") and 
                   files_info.get("no_loss", {}).get("exists") and 
                   files_info.get("report", {}).get("exists"))
    
    if files_exist:
        score += 10
        feedback.append("All required output files found.")
    else:
        feedback.append("Missing one or more output files.")
        
    # --- Criterion 2: Data Validity (20 pts) ---
    try:
        raw_with = base64.b64decode(content_b64.get("with_loss", "")).decode('utf-8', errors='ignore')
        raw_no = base64.b64decode(content_b64.get("no_loss", "")).decode('utf-8', errors='ignore')
        raw_report = base64.b64decode(content_b64.get("report", "")).decode('utf-8', errors='ignore')
    except:
        return {"passed": False, "score": score, "feedback": "Failed to decode result files."}

    data_with = parse_bem_file(raw_with)
    data_no = parse_bem_file(raw_no)
    
    if len(data_with) > 5 and len(data_no) > 5:
        score += 20
        feedback.append("Simulation data files contain valid numeric data.")
    else:
        feedback.append("Simulation files appear empty or malformed.")
        # If data is invalid, we can't do physics checks
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # --- Criterion 3: Physics Check - Tip Loss Effect (30 pts) ---
    max_cp_with = get_max_cp(data_with)
    max_cp_no = get_max_cp(data_no)
    
    # Physics: No Loss should have HIGHER efficiency
    # The difference should be significant (e.g., > 1%)
    # If they are identical, the agent failed to change the setting
    
    diff = max_cp_no - max_cp_with
    percent_diff = (diff / max_cp_no) * 100 if max_cp_no > 0 else 0
    
    physics_passed = False
    if diff > 0.005 and percent_diff > 1.0: # Minimum 1% impact expected (usually 5-10%)
        score += 30
        physics_passed = True
        feedback.append(f"Physics verified: Tip Loss reduces Cp (Impact: {percent_diff:.2f}%).")
    elif abs(diff) < 0.001:
        feedback.append("Physics check failed: Results are identical. Did you toggle the Tip Loss setting?")
    else:
        feedback.append(f"Physics check failed: Unexpected results (NoLoss: {max_cp_no:.3f}, WithLoss: {max_cp_with:.3f}).")

    # --- Criterion 4: Reasonable Values (15 pts) ---
    # Cp for a wind turbine should be between 0.35 and 0.59 (Betz limit)
    if 0.35 <= max_cp_no <= 0.59:
        score += 15
        feedback.append(f"Cp values are physically realistic ({max_cp_no:.3f}).")
    else:
        feedback.append(f"Cp values are out of realistic range ({max_cp_no:.3f}). Check blade design.")

    # --- Criterion 5: Report Accuracy (15 pts) ---
    # Check if the text report matches the data
    # Look for numbers in the report
    report_nums = [float(x) for x in re.findall(r"[-+]?\d*\.\d+|\d+", raw_report)]
    
    # We expect to find the calculated % in the report
    report_accurate = False
    for num in report_nums:
        # Check against calculated percent diff (allow 0.5 tolerance for rounding)
        if abs(num - percent_diff) < 0.5:
            report_accurate = True
            break
            
    if report_accurate:
        score += 15
        feedback.append("Reported percentage matches simulation data.")
    else:
        feedback.append(f"Reported value mismatch. Calculated: {percent_diff:.2f}%, Found in report: {report_nums}")

    # --- Criterion 6: Optimization Success (10 pts) ---
    # Peak should be near TSR 7 (Design Point)
    peak_tsr_no = 0
    curr_max = -1
    for t, c in data_no:
        if c > curr_max:
            curr_max = c
            peak_tsr_no = t
            
    if 5.5 <= peak_tsr_no <= 8.5:
        score += 10
        feedback.append(f"Blade optimization successful (Peak at TSR {peak_tsr_no}).")
    else:
        feedback.append(f"Blade optimization off-target (Peak at TSR {peak_tsr_no}, expected ~7).")

    # Final Result
    # Pass threshold: 70 AND physics check must pass
    passed = (score >= 70) and physics_passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }