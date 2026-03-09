#!/usr/bin/env python3
"""
Verifier for adf_unit_root_test task.

Verifies:
1. Output file creation and freshness (Anti-gaming)
2. Presence of three specific ADF tests
3. Numeric accuracy of test statistics vs ground truth
4. VLM verification of script editor usage and workflow
"""

import json
import os
import re
import tempfile
import logging
from typing import Dict, Any, List, Optional

# VLM utilities import (mock or actual based on environment)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(prompt, image=None, images=None): 
        return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_tau_statistic(text: str, variable_pattern: str, trend: bool = False) -> Optional[float]:
    """
    Extracts the ADF tau statistic for a specific variable from Gretl output.
    
    Gretl Output Format Example:
    Augmented Dickey-Fuller test for gdp
    including 4 lags of (1-L)gdp
    (max was 4, criterion modified AIC)
    sample size 101
    unit-root null hypothesis: a = 1
    test with constant and trend
    model: (1-L)y = b0 + b1*t + (a-1)*y(-1) + ...
    estimated value of (a-1): -0.0456
    test statistic: tau_ct(1) = -2.345
    """
    # Normalize text
    lines = text.split('\n')
    
    # Find the block for the variable
    # We look for "Augmented Dickey-Fuller test for [variable]"
    # or "test for diff(variable)"
    block_start_idx = -1
    
    # Regex to match the variable header
    # e.g., "Augmented Dickey-Fuller test for gdp" or "test for diff(gdp)"
    header_regex = re.compile(rf"Augmented Dickey-Fuller test for .*{variable_pattern}", re.IGNORECASE)
    
    for i, line in enumerate(lines):
        if header_regex.search(line):
            block_start_idx = i
            break
            
    if block_start_idx == -1:
        return None
        
    # Search within the next 25 lines for the statistic
    # "test statistic: tau_c(4) = -1.234" or "tau_ct(4) = ..."
    # tau_c = constant, tau_ct = constant + trend, tau_nc = no constant
    
    tau_type = "tau_ct" if trend else "tau_c"
    stat_regex = re.compile(rf"test statistic: {tau_type}\(\d+\)\s*=\s*([-]?\d+\.\d+)")
    
    for i in range(block_start_idx, min(block_start_idx + 25, len(lines))):
        match = stat_regex.search(lines[i])
        if match:
            return float(match.group(1))
            
    return None

def verify_adf_unit_root_test(traj, env_info, task_info):
    """
    Verifies the ADF Unit Root Test task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env unavailable"}

    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_log = []
    
    # --- Criterion 1: File Existence & Validity (20 pts) ---
    output_exists = result.get("output_exists", False)
    file_fresh = result.get("file_created_during_task", False)
    output_content = result.get("output_content", "")
    gt_content = result.get("ground_truth_content", "")
    
    if output_exists and len(output_content) > 100:
        score += 10
        feedback_log.append("Output file created.")
        if file_fresh:
            score += 10
            feedback_log.append("Output file verified as new.")
        else:
            feedback_log.append("WARNING: Output file timestamp is old.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file missing or empty."}

    # --- Criterion 2: Numeric Accuracy (50 pts) ---
    # We compare extracted statistics from Agent Output vs Ground Truth
    
    # A. GDP Levels (Constant + Trend)
    gt_gdp = extract_tau_statistic(gt_content, "gdp", trend=True)
    agent_gdp = extract_tau_statistic(output_content, "gdp", trend=True)
    
    # B. GDP Diff (Constant)
    # Pattern for diff might be "diff(gdp)" or "d_gdp" or "(1-L)gdp"
    gt_dgdp = extract_tau_statistic(gt_content, r"(diff\(gdp\)|d_gdp|\(1-L\)gdp)", trend=False)
    agent_dgdp = extract_tau_statistic(output_content, r"(diff\(gdp\)|d_gdp|\(1-L\)gdp)", trend=False)
    
    # C. Inflation Levels (Constant)
    gt_inf = extract_tau_statistic(gt_content, "inf", trend=False)
    agent_inf = extract_tau_statistic(output_content, "inf", trend=False)

    def check_stat(name, gt, agent, pts):
        if gt is None:
            return 0, f"System Error: Could not calculate GT for {name}"
        if agent is None:
            return 0, f"Missing result for {name}"
        
        # Tolerance of 0.05 for floating point differences/version minor diffs
        if abs(gt - agent) < 0.05:
            return pts, f"{name}: Match ({agent})"
        else:
            return 0, f"{name}: Mismatch (Expected {gt}, Got {agent})"

    pts_gdp, msg_gdp = check_stat("GDP (Levels, Trend)", gt_gdp, agent_gdp, 15)
    pts_dgdp, msg_dgdp = check_stat("GDP (Diff, Const)", gt_dgdp, agent_dgdp, 15)
    pts_inf, msg_inf = check_stat("Inflation (Levels, Const)", gt_inf, agent_inf, 20)
    
    score += pts_gdp + pts_dgdp + pts_inf
    feedback_log.extend([msg_gdp, msg_dgdp, msg_inf])

    # --- Criterion 3: VLM Process Verification (30 pts) ---
    # We check if the agent actually used the script editor as requested
    
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if frames:
        vlm_prompt = """
        Review these screenshots of a user interacting with Gretl (econometrics software).
        
        Check for:
        1. SCRIPT EDITOR: Did the user open a window titled "Script" or "hansl"?
        2. CODE: Is there visible code like 'open', 'adf', or 'outfile'?
        3. EXECUTION: Did an output window titled "gretl: output" appear?
        
        Output JSON:
        {
            "script_editor_visible": boolean,
            "code_visible": boolean,
            "output_window_visible": boolean,
            "confidence": float
        }
        """
        
        vlm_response = query_vlm(prompt=vlm_prompt, images=frames + [final_screen] if final_screen else frames)
        
        if vlm_response.get("success"):
            parsed = vlm_response.get("parsed", {})
            if parsed.get("script_editor_visible") or parsed.get("code_visible"):
                score += 15
                feedback_log.append("VLM: Script editor usage verified.")
            else:
                feedback_log.append("VLM: Script editor not clearly seen.")
                
            if parsed.get("output_window_visible"):
                score += 15
                feedback_log.append("VLM: Output window execution verified.")
            else:
                # Fallback: if output file exists and is correct, we assume execution happened
                if output_exists and pts_gdp > 0:
                    score += 15
                    feedback_log.append("VLM: Output window not seen, but valid file inferred execution.")
        else:
            # Fallback if VLM fails but file is perfect
            if score >= 60: 
                score += 30
                feedback_log.append("VLM check skipped (service unavailable), trusting file output.")
    else:
        if score >= 60:
            score += 30
            feedback_log.append("Trajectory empty, trusting file output.")

    # Final Evaluation
    passed = score >= 65 and (pts_gdp + pts_dgdp + pts_inf) >= 30
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_log)
    }