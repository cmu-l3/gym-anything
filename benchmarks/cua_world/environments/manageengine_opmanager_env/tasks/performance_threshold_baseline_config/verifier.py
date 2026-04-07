#!/usr/bin/env python3
"""
verifier.py — Configuring Performance Monitor Thresholds per Baseline Policy

Scoring (100 pts total, pass at 60):
  - CPU Warning 75 & Critical 90  (15 pts + 15 pts = 30 pts)
  - Mem Warning 80 & Critical 92  (15 pts + 15 pts = 30 pts)
  - Disk Warning 70 & Critical 85 (10 pts + 10 pts = 20 pts)
  - VLM Trajectory Check: Agent opened threshold/monitor configuration windows (20 pts)
  
Pass threshold requires at least 4 of 6 numeric thresholds to be correctly set.
"""
import json
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- VLM Verification Prompt ---
TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent configuring performance monitor thresholds in ManageEngine OpManager.

Look closely at the screenshots (ordered chronologically) and determine:
1. Did the agent navigate to a device's details/monitors page?
2. Did the agent open a configuration window/dialog specifically for setting thresholds (e.g., fields for 'Warning', 'Critical', 'Threshold', etc. for CPU, Memory, or Disk)?

Respond in the following JSON format ONLY:
{
    "device_page_accessed": true/false,
    "threshold_dialog_opened": true/false,
    "confidence": "low/medium/high",
    "observations": "brief explanation of what is visible"
}"""


def _find_threshold_in_text(text: str, metric_keywords: list, warn_val: int, crit_val: int) -> dict:
    """
    Search a raw text dump for evidence that a specific metric has the specified warning and critical values.
    Uses a proximity window to ensure the values appear near the metric keyword.
    """
    text_lower = text.lower()
    
    found_warn = False
    found_crit = False
    
    # We will search for occurrences of the metric keyword
    for keyword in metric_keywords:
        kw_lower = keyword.lower()
        idx = 0
        while True:
            idx = text_lower.find(kw_lower, idx)
            if idx == -1:
                break
                
            # Define a proximity window (e.g., 500 chars before and after the keyword)
            start_idx = max(0, idx - 500)
            end_idx = min(len(text_lower), idx + len(kw_lower) + 500)
            window = text_lower[start_idx:end_idx]
            
            # Use regex to find the numbers as distinct tokens
            warn_pattern = re.compile(rf"\b{warn_val}\b")
            crit_pattern = re.compile(rf"\b{crit_val}\b")
            
            if warn_pattern.search(window):
                found_warn = True
            if crit_pattern.search(window):
                found_crit = True
                
            if found_warn and found_crit:
                return {"warn": True, "crit": True}
                
            idx += len(kw_lower)
            
    return {"warn": found_warn, "crit": found_crit}


def verify_performance_threshold_baseline_config(traj, env_info, task_info):
    """Main verifier entry point."""
    result_file = task_info.get("metadata", {}).get("result_file", "/tmp/performance_threshold_result.json")
    local_path = "/tmp/threshold_verify_result.json"
    
    score = 0
    feedback_parts = []
    
    # -----------------------------------------------------------------------
    # 1. Retrieve the result file
    # -----------------------------------------------------------------------
    if not env_info.get("copy_from_env"):
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        env_info["copy_from_env"](result_file, local_path)
        with open(local_path) as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve or parse result file: {e}"
        }

    db_dump = data.get("db_dump", "")
    api_dump = json.dumps(data.get("api_dump", {}))
    combined_text = db_dump + "\n" + api_dump
    
    # -----------------------------------------------------------------------
    # 2. Extract Metadata Expectations
    # -----------------------------------------------------------------------
    meta = task_info.get("metadata", {})
    cpu_warn = meta.get("cpu_warning", 75)
    cpu_crit = meta.get("cpu_critical", 90)
    mem_warn = meta.get("mem_warning", 80)
    mem_crit = meta.get("mem_critical", 92)
    disk_warn = meta.get("disk_warning", 70)
    disk_crit = meta.get("disk_critical", 85)
    
    thresholds_met = 0

    # -----------------------------------------------------------------------
    # 3. Check CPU Thresholds
    # -----------------------------------------------------------------------
    cpu_res = _find_threshold_in_text(combined_text, ["cpu", "processor"], cpu_warn, cpu_crit)
    if cpu_res["warn"]:
        score += 15
        thresholds_met += 1
        feedback_parts.append(f"CPU Warning ({cpu_warn}%) found")
    else:
        feedback_parts.append(f"CPU Warning ({cpu_warn}%) NOT found")
        
    if cpu_res["crit"]:
        score += 15
        thresholds_met += 1
        feedback_parts.append(f"CPU Critical ({cpu_crit}%) found")
    else:
        feedback_parts.append(f"CPU Critical ({cpu_crit}%) NOT found")

    # -----------------------------------------------------------------------
    # 4. Check Memory Thresholds
    # -----------------------------------------------------------------------
    mem_res = _find_threshold_in_text(combined_text, ["memory", "ram", "physical"], mem_warn, mem_crit)
    if mem_res["warn"]:
        score += 15
        thresholds_met += 1
        feedback_parts.append(f"Memory Warning ({mem_warn}%) found")
    else:
        feedback_parts.append(f"Memory Warning ({mem_warn}%) NOT found")
        
    if mem_res["crit"]:
        score += 15
        thresholds_met += 1
        feedback_parts.append(f"Memory Critical ({mem_crit}%) found")
    else:
        feedback_parts.append(f"Memory Critical ({mem_crit}%) NOT found")

    # -----------------------------------------------------------------------
    # 5. Check Disk Thresholds
    # -----------------------------------------------------------------------
    disk_res = _find_threshold_in_text(combined_text, ["disk", "partition", " / ", "drive"], disk_warn, disk_crit)
    if disk_res["warn"]:
        score += 10
        thresholds_met += 1
        feedback_parts.append(f"Disk Warning ({disk_warn}%) found")
    else:
        feedback_parts.append(f"Disk Warning ({disk_warn}%) NOT found")
        
    if disk_res["crit"]:
        score += 10
        thresholds_met += 1
        feedback_parts.append(f"Disk Critical ({disk_crit}%) found")
    else:
        feedback_parts.append(f"Disk Critical ({disk_crit}%) NOT found")
        
    # -----------------------------------------------------------------------
    # 6. VLM Trajectory Verification
    # -----------------------------------------------------------------------
    query_vlm = env_info.get("query_vlm")
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            # Sample 4 frames across the trajectory
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_result = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("threshold_dialog_opened", False):
                        score += 20
                        feedback_parts.append("VLM confirmed threshold dialog accessed")
                    else:
                        feedback_parts.append("VLM did NOT see threshold dialog accessed")
                else:
                    logger.warning("VLM query failed or format incorrect")
            else:
                logger.warning("Could not sample trajectory frames")
        except Exception as e:
            logger.warning(f"Error during VLM verification: {e}")
            feedback_parts.append("VLM verification skipped due to error")
    else:
        logger.warning("query_vlm function not provided in env_info")
        # If VLM is unavailable, we proportionally scale the DB score to 100 if all 6 criteria are met
        if thresholds_met == 6:
            score += 20
            feedback_parts.append("VLM skipped (auto-awarded full points for perfect DB match)")

    # -----------------------------------------------------------------------
    # Final Result
    # -----------------------------------------------------------------------
    # Pass requires at least 4 out of 6 thresholds correctly set, ensuring base functionality
    passed = (thresholds_met >= 4) and (score >= 60)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }