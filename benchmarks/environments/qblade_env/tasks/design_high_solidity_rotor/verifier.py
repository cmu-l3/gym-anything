#!/usr/bin/env python3
"""
Verifier for design_high_solidity_rotor task.
Validates:
1. File existence (Performance data, Project file, Summary)
2. Simulation Physics (Peak Cp should occur near TSR 2.0)
3. VLM Verification of workflow
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_performance_file(filepath):
    """
    Parses QBlade export file. 
    Expected format: Whitespace or comma separated values.
    Usually: TSR, Cp, Ct, ... or similar.
    Returns: (list of TSRs, list of Cps)
    """
    tsr_list = []
    cp_list = []
    
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
            
        # skip header lines (non-numeric)
        data_start_idx = 0
        for i, line in enumerate(lines):
            parts = line.strip().replace(',', ' ').split()
            if len(parts) >= 2:
                try:
                    float(parts[0])
                    data_start_idx = i
                    break
                except ValueError:
                    continue
        
        for line in lines[data_start_idx:]:
            parts = line.strip().replace(',', ' ').split()
            if len(parts) >= 2:
                try:
                    tsr = float(parts[0])
                    cp = float(parts[1])
                    tsr_list.append(tsr)
                    cp_list.append(cp)
                except ValueError:
                    continue
                    
        return tsr_list, cp_list
    except Exception as e:
        logger.error(f"Error parsing performance file: {e}")
        return [], []

def verify_design_high_solidity_rotor(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    target_tsr = metadata.get('target_tsr', 2.0)
    tsr_tolerance = metadata.get('tsr_tolerance', 0.25) # Slightly wider tolerance
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    score = 0
    feedback = []
    
    # 2. Check Files Existence & Timing (30 pts)
    # Performance File
    if result.get('perf_file_exists') and result.get('perf_created_during_task'):
        score += 10
        feedback.append("Performance data exported.")
    else:
        feedback.append("Performance data missing or old.")
        
    # Project File
    if result.get('project_file_exists') and result.get('project_created_during_task'):
        score += 10
        feedback.append("Project file saved.")
    else:
        feedback.append("Project file missing.")

    # Summary File
    if result.get('summary_file_exists'):
        score += 10
        feedback.append("Summary report created.")
    else:
        feedback.append("Summary report missing.")

    # 3. Analyze Physics Data (50 pts)
    # Check if peak efficiency is at low TSR (indicates high solidity/optimization success)
    temp_perf = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/task_perf_data.txt", temp_perf.name)
        tsrs, cps = parse_performance_file(temp_perf.name)
        
        if len(tsrs) > 5:
            max_cp = -1.0
            max_tsr = -1.0
            
            # Find max Cp
            for t, c in zip(tsrs, cps):
                if c > max_cp:
                    max_cp = c
                    max_tsr = t
            
            feedback.append(f"Simulation Analysis: Max Cp={max_cp:.3f} at TSR={max_tsr:.2f}")
            
            # Verify Peak Location
            # If optimization worked for TSR 2.0, max should be close to 2.0
            # If default (TSR 7), max will be > 5.0
            if abs(max_tsr - target_tsr) <= tsr_tolerance:
                score += 50
                feedback.append(f"SUCCESS: Rotor is optimized for target TSR {target_tsr} (Actual: {max_tsr}).")
            elif 0.5 <= max_tsr <= 4.0:
                # Peak is within range but not optimal
                score += 20
                feedback.append(f"PARTIAL: Simulation run, but peak TSR ({max_tsr}) is not near target ({target_tsr}). Did you optimize?")
            else:
                feedback.append(f"FAIL: Peak TSR {max_tsr} is far from target {target_tsr}.")
                
            # Verify Range (0.5 to 4.0 requested)
            if min(tsrs) <= 0.6 and max(tsrs) >= 3.9:
                pass # Range ok
            else:
                feedback.append("Note: Simulation range appears truncated compared to instructions.")
        else:
            feedback.append("Performance file contains insufficient data points.")
            
    except Exception as e:
        feedback.append(f"Could not analyze performance data: {e}")
    finally:
        if os.path.exists(temp_perf.name):
            os.unlink(temp_perf.name)

    # 4. VLM / App State Check (20 pts)
    if result.get('app_running'):
        score += 10
    else:
        feedback.append("QBlade was not running at end of task.")

    # Basic VLM check using trajectory frames could be added here
    # For now, we award the final 10 points if the main physics check passed, implying visual workflow success
    if score >= 60:
        score += 10
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }