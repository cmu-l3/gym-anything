#!/usr/bin/env python3
"""
Verifier for design_linear_taper_blade task.

Verification Logic:
1. Check files existence and freshness.
2. Parse 'tsr7_bem_results.txt' to find the Peak Cp and its corresponding TSR.
3. Parse 'tsr7_geometry.txt' to verify the chord distribution is linear.
4. Check physics sanity (solidity) to prevent gaming.
"""

import json
import os
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_linear_taper_blade(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_tsr = metadata.get('target_tsr', 7.0)
    tsr_tolerance = metadata.get('tsr_tolerance', 0.2)
    
    score = 0
    feedback_parts = []
    
    # 1. Load Metadata Result
    try:
        temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            result_meta = json.load(f)
        os.unlink(temp_meta.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task metadata: {e}"}

    # Files existence check
    if not result_meta.get("project_exists"):
        feedback_parts.append("Project file (.wpa) missing.")
    else:
        score += 10

    if not result_meta.get("geometry_exists"):
        feedback_parts.append("Geometry export (.txt) missing.")
    
    if not result_meta.get("results_exists"):
        feedback_parts.append("BEM results export (.txt) missing.")
        
    if not result_meta.get("files_fresh"):
        feedback_parts.append("Files were not created during this session (timestamps old).")
        score = 0 # Anti-gaming penalty
    else:
        score += 10 # Freshness bonus

    # Stop if critical files missing
    if not (result_meta.get("geometry_exists") and result_meta.get("results_exists")):
        return {"passed": False, "score": score, "feedback": " ".join(feedback_parts)}

    # 2. Analyze BEM Results (Target TSR)
    try:
        temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env(result_meta["results_path"], temp_res.name)
        
        # Parse QBlade BEM output (usually headers then data)
        # We look for TSR/Lambda column and Cp/Power Coeff column
        data = []
        with open(temp_res.name, 'r') as f:
            lines = f.readlines()
            
        # Simple heuristic parsing: find line with numbers
        # Assuming format: Lambda/TSR is often 1st column, Cp is often 2nd or 3rd
        # QBlade Export format usually has a header line
        
        parsed_data = []
        for line in lines:
            parts = line.strip().split()
            # Check if line is all numbers
            try:
                nums = [float(p) for p in parts]
                if len(nums) >= 2:
                    parsed_data.append(nums)
            except ValueError:
                continue
        
        if not parsed_data:
            feedback_parts.append("Could not parse numeric data from results file.")
            max_cp = 0
            peak_tsr = 0
        else:
            # Assuming Col 0 is TSR, Col 1 is Cp (Standard QBlade Graph Export)
            # If QBlade exports Col 0 as WindSpeed, this logic might fail, 
            # but usually graph export matches X/Y axes. TSR sweep X=TSR, Y=Cp.
            data_arr = np.array(parsed_data)
            
            # Find column with max variance (likely TSR) and column with values < 1.0 (Cp)
            # Standard assumption: Col 0 = X (TSR), Col 1 = Y (Cp)
            tsr_col = data_arr[:, 0]
            cp_col = data_arr[:, 1]
            
            max_cp_idx = np.argmax(cp_col)
            max_cp = cp_col[max_cp_idx]
            peak_tsr = tsr_col[max_cp_idx]
            
            feedback_parts.append(f"Measured Peak Cp: {max_cp:.3f} at TSR: {peak_tsr:.2f}.")

            if abs(peak_tsr - target_tsr) <= tsr_tolerance:
                score += 40
                feedback_parts.append("Peak TSR is within target range.")
            else:
                feedback_parts.append(f"Peak TSR {peak_tsr} is outside target {target_tsr} +/- {tsr_tolerance}.")

        os.unlink(temp_res.name)
    except Exception as e:
        feedback_parts.append(f"Error analyzing results file: {e}")

    # 3. Analyze Geometry (Linearity Check)
    try:
        temp_geo = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env(result_meta["geometry_path"], temp_geo.name)
        
        geo_data = []
        with open(temp_geo.name, 'r') as f:
            lines = f.readlines()
            
        # QBlade Geometry Export: Pos(m) Chord(m) Twist(deg) ...
        # Skip headers
        for line in lines:
            parts = line.strip().split()
            try:
                # Need at least Pos and Chord
                nums = [float(p) for p in parts]
                if len(nums) >= 2:
                    geo_data.append(nums)
            except ValueError:
                continue
        
        if len(geo_data) < 3:
            feedback_parts.append("Geometry file contains too few points.")
        else:
            geo_arr = np.array(geo_data)
            pos = geo_arr[:, 0]
            chord = geo_arr[:, 1]
            
            # Linearity Check using Correlation Coefficient
            correlation_matrix = np.corrcoef(pos, chord)
            correlation_xy = correlation_matrix[0,1]
            r_squared = correlation_xy**2
            
            if r_squared > 0.98: # Allow slight deviation for discretization
                score += 20
                feedback_parts.append(f"Blade geometry is linear (R^2={r_squared:.4f}).")
            else:
                feedback_parts.append(f"Blade geometry is NOT linear (R^2={r_squared:.4f}). Task required linear taper.")
                
            # Physics/Solidity Check (Anti-Gaming)
            # At R=2m, TSR=7, Tip chord should be roughly 0.05 - 0.15m
            tip_chord = chord[-1]
            if 0.01 < tip_chord < 0.25:
                score += 20
                feedback_parts.append(f"Tip chord ({tip_chord:.3f}m) is physically reasonable for TSR 7.")
            else:
                feedback_parts.append(f"Tip chord ({tip_chord:.3f}m) seems unrealistic for high-speed rotor (TSR 7).")

        os.unlink(temp_geo.name)
    except Exception as e:
        feedback_parts.append(f"Error analyzing geometry file: {e}")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }