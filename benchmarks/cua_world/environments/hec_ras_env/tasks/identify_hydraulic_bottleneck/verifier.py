#!/usr/bin/env python3
"""
Verifier for identify_hydraulic_bottleneck task.
Compares agent's text report against ground truth calculated from HDF5 files.
"""

import json
import os
import tempfile
import base64
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_identify_hydraulic_bottleneck(traj, env_info, task_info):
    """
    Verify the hydraulic bottleneck analysis.
    
    Criteria:
    1. Report file exists and was created during task.
    2. Critical Upstream Station matches ground truth.
    3. Critical Downstream Station matches ground truth.
    4. Calculated Slope is within 5% tolerance.
    5. Head Loss and Reach Length are reasonably correct.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # --- 1. Fetch Agent Results ---
    agent_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                agent_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)

    # --- 2. Fetch Ground Truth ---
    ground_truth = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env("/tmp/ground_truth.json", tmp.name)
            with open(tmp.name, 'r') as f:
                ground_truth = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ground truth: {e}"}
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
                
    if not ground_truth.get("success", False):
        return {"passed": False, "score": 0, "feedback": f"Ground truth generation failed: {ground_truth.get('error')}"}

    # --- 3. Evaluate ---
    score = 0
    feedback_parts = []
    
    # A. File Existence (10 pts)
    if not agent_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Report file not found at expected path."}
    
    score += 10
    
    # B. Created During Task (Anti-gaming)
    if not agent_result.get("file_created_during_task", False):
        feedback_parts.append("Warning: File timestamp suggests it wasn't created during this session.")
        # We don't fail immediately but this is suspicious
    
    # C. Parse Content
    content_b64 = agent_result.get("output_content_b64", "")
    try:
        content = base64.b64decode(content_b64).decode('utf-8', errors='ignore')
    except:
        return {"passed": False, "score": score, "feedback": "Could not decode file content."}
    
    # Regex extraction
    # Patterns to match lines like "Critical Upstream Station: 15600.23"
    patterns = {
        "upstream": r"Critical Upstream Station\s*:\s*([^\n\r]+)",
        "downstream": r"Critical Downstream Station\s*:\s*([^\n\r]+)",
        "length": r"Reach Length\s*:\s*([\d\.]+)",
        "head_loss": r"Head Loss\s*:\s*([\d\.]+)",
        "slope": r"Max Energy Slope\s*:\s*([\d\.eE\-\+]+)"
    }
    
    extracted = {}
    for key, pat in patterns.items():
        match = re.search(pat, content, re.IGNORECASE)
        if match:
            val = match.group(1).strip()
            # Clean up units if present (e.g., "100 ft")
            val_clean = re.sub(r"[a-zA-Z]", "", val).strip()
            extracted[key] = val
            extracted[f"{key}_clean"] = val_clean
    
    gt_up = ground_truth["upstream_station"]
    gt_down = ground_truth["downstream_station"]
    gt_slope = ground_truth["max_slope"]
    gt_len = ground_truth["reach_length"]
    gt_loss = ground_truth["head_loss"]
    
    # D. Compare Stations (20 pts each)
    # Upstream
    agent_up = extracted.get("upstream", "")
    if agent_up == gt_up:
        score += 20
        feedback_parts.append(f"Correct upstream station ({gt_up})")
    else:
        feedback_parts.append(f"Incorrect upstream station (Expected: {gt_up}, Got: {agent_up})")
        
    # Downstream
    agent_down = extracted.get("downstream", "")
    if agent_down == gt_down:
        score += 20
        feedback_parts.append(f"Correct downstream station ({gt_down})")
    else:
        feedback_parts.append(f"Incorrect downstream station (Expected: {gt_down}, Got: {agent_down})")

    # E. Compare Slope (25 pts)
    # Use 5% tolerance
    try:
        agent_slope = float(extracted.get("slope_clean", 0))
        if gt_slope != 0:
            diff = abs(agent_slope - gt_slope) / abs(gt_slope)
            if diff <= 0.05:
                score += 25
                feedback_parts.append(f"Correct slope ({agent_slope})")
            else:
                feedback_parts.append(f"Slope mismatch (Expected: {gt_slope:.5f}, Got: {agent_slope}, Diff: {diff:.1%})")
        else:
            feedback_parts.append("Ground truth slope is zero (error)")
    except ValueError:
        feedback_parts.append("Could not parse slope value")

    # F. Compare Length (10 pts)
    try:
        agent_len = float(extracted.get("length_clean", 0))
        if abs(agent_len - gt_len) < 1.0: # 1 ft tolerance
            score += 10
        else:
            feedback_parts.append(f"Length mismatch (Expected: {gt_len}, Got: {agent_len})")
    except:
        pass

    # G. Compare Head Loss (15 pts)
    try:
        agent_loss = float(extracted.get("head_loss_clean", 0))
        if abs(agent_loss - gt_loss) < 0.1: # 0.1 ft tolerance
            score += 15
        else:
            feedback_parts.append(f"Head loss mismatch (Expected: {gt_loss:.2f}, Got: {agent_loss})")
    except:
        pass
        
    # Calculate pass status
    # Must get stations correct (40pts) + file (10pts) + at least one value correct (length, loss, or slope)
    # Threshold 60 is reasonable
    passed = score >= 60 and (extracted.get("upstream") == gt_up)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }