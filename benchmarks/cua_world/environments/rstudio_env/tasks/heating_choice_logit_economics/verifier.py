#!/usr/bin/env python3
"""
Verifier for heating_choice_logit_economics task.

Task: Estimate a Conditional Logit model to determine consumer trade-offs
between installation cost and operating cost for heating systems.

Scoring (100 points total):
  1. Package Installation (10 pts)
     - `mlogit` installed successfully
  2. Model Coefficients CSV (30 pts)
     - CSV exists and is new (10 pts)
     - `ic` and `oc` are both negative (10 pts)
     - `ic` and `oc` values are accurate within expected ranges (10 pts)
  3. Economic Analysis / Trade-off Ratio CSV (30 pts)
     - CSV exists and is new (10 pts)
     - Trade-off ratio matches expected calculation and range [0.50, 0.95] (20 pts)
  4. Visualization (30 pts)
     - PNG exists, is new, and has substantial size >10KB (10 pts)
     - VLM verification: trajectory shows R code writing/execution (20 pts)

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames

logger = logging.getLogger(__name__)

# Expected ranges from the mlogit::Heating dataset
EXPECTED_IC_RANGE = [-0.008, -0.004]  # Truth is approx -0.0062
EXPECTED_OC_RANGE = [-0.006, -0.003]  # Truth is approx -0.0045
EXPECTED_RATIO_RANGE = [0.50, 0.95]   # Truth is approx 0.73


TRAJECTORY_PROMPT = """You are evaluating an AI agent's performance in RStudio.
The task was to write an R script to fit a conditional logit model using the `mlogit` package.

Review these trajectory frames and determine:
1. Did the agent actually write R code in the editor pane (not just use GUI menus)?
2. Is there evidence that the code was executed (e.g., console output showing model summaries or errors)?
3. Did the agent create a bar plot (visible in the Plots pane or viewer)?

Respond ONLY in valid JSON format:
{
    "wrote_r_code": true/false,
    "executed_code": true/false,
    "plot_visible": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_heating_choice(traj, env_info, task_info):
    """Verify discrete choice modeling task."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Retrieve parsed data
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        except FileNotFoundError:
            return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run properly"}
        except json.JSONDecodeError as e:
            return {"passed": False, "score": 0, "feedback": f"Result JSON malformed: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []

    # 1. Package Installation
    if result.get("mlogit_installed"):
        score += 10
        feedback.append("mlogit package installed (+10)")
    else:
        feedback.append("mlogit package NOT installed (0)")

    # 2. Coefficients CSV
    if result.get("coefs_csv_exists") and result.get("coefs_csv_new"):
        score += 10
        feedback.append("Coefficients CSV created (+10)")
        
        ic_coef = result.get("ic_coef")
        oc_coef = result.get("oc_coef")
        
        if ic_coef is not None and oc_coef is not None:
            if ic_coef < 0 and oc_coef < 0:
                score += 10
                feedback.append(f"Cost coefficients are correctly negative (ic={ic_coef:.4f}, oc={oc_coef:.4f}) (+10)")
            else:
                feedback.append("Cost coefficients should be negative (0)")
                
            ic_valid = EXPECTED_IC_RANGE[0] <= ic_coef <= EXPECTED_IC_RANGE[1]
            oc_valid = EXPECTED_OC_RANGE[0] <= oc_coef <= EXPECTED_OC_RANGE[1]
            if ic_valid and oc_valid:
                score += 10
                feedback.append("Coefficients are mathematically accurate (+10)")
            else:
                feedback.append("Coefficients are outside expected accuracy bounds (0)")
        else:
            feedback.append("Could not extract 'ic' or 'oc' coefficients from CSV (0)")
    elif result.get("coefs_csv_exists"):
        feedback.append("Coefficients CSV exists but predates task (0)")
    else:
        feedback.append("Coefficients CSV missing (0)")

    # 3. Trade-off Ratio CSV
    if result.get("econ_csv_exists") and result.get("econ_csv_new"):
        score += 10
        feedback.append("Economics CSV created (+10)")
        
        ratio = result.get("tradeoff_ratio")
        if ratio is not None:
            if EXPECTED_RATIO_RANGE[0] <= ratio <= EXPECTED_RATIO_RANGE[1]:
                score += 20
                feedback.append(f"Trade-off ratio ({ratio:.3f}) is accurate and in range [0.5, 0.95] (+20)")
            else:
                feedback.append(f"Trade-off ratio ({ratio:.3f}) outside expected range (0)")
        else:
            feedback.append("Could not find a valid trade-off ratio in Economics CSV (0)")
    elif result.get("econ_csv_exists"):
        feedback.append("Economics CSV exists but predates task (0)")
    else:
        feedback.append("Economics CSV missing (0)")

    # 4. Visualization & Process (VLM)
    if result.get("plot_exists") and result.get("plot_new"):
        size_kb = result.get("plot_size_kb", 0)
        if size_kb > 10:
            score += 10
            feedback.append(f"Market shares plot generated ({size_kb:.1f} KB) (+10)")
        else:
            feedback.append(f"Market shares plot generated but file size too small ({size_kb:.1f} KB) (0)")
    else:
        feedback.append("Market shares plot missing or not new (0)")

    # VLM verification of trajectory
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            vlm_res = query_vlm(prompt=TRAJECTORY_PROMPT, images=frames)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                wrote = parsed.get("wrote_r_code", False)
                executed = parsed.get("executed_code", False)
                if wrote and executed:
                    score += 20
                    feedback.append("VLM verified R code writing and execution (+20)")
                else:
                    feedback.append("VLM did not detect strong evidence of R coding/execution (0)")
            else:
                feedback.append("VLM query failed during verification")
        else:
            feedback.append("No trajectory frames available for VLM verification")
    else:
        feedback.append("VLM query function not available")

    # Pass threshold is 60. Must have computed at least something relevant.
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }