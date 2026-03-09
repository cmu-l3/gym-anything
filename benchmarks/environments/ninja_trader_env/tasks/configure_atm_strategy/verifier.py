#!/usr/bin/env python3
"""
Verifier for configure_atm_strategy task.

Criteria:
1. Template file 'SPY_Scalp.xml' exists.
2. File was created/modified during the task session.
3. Stop Loss is configured to 3 points (or equivalent ticks).
4. Two Profit Targets exist.
5. Profit Targets are configured to ~2 and ~5 points.
6. VLM Verification of UI interaction (trajectory).
"""

import json
import tempfile
import os
import re
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected values
EXPECTED_STOP = 3.0
EXPECTED_T1 = 2.0
EXPECTED_T2 = 5.0
# Tick conversion: SPY is 0.01 usually, so 3 points = 300 ticks. 
# But in some contexts 3 points = 3.0 value.
# We accept: 3, 3.0, 300 (0.01 tick), 12 (0.25 tick), 120 (generic)
VALID_STOP_VALUES = [3, 3.0, 300, 12, 120]
VALID_T1_VALUES = [2, 2.0, 200, 8, 80]
VALID_T2_VALUES = [5, 5.0, 500, 20, 200]

def check_value_match(actual, valid_list):
    """Check if actual value (string or number) matches any valid representation."""
    try:
        val = float(actual)
        return any(abs(val - v) < 0.01 for v in valid_list)
    except:
        return False

def verify_configure_atm_strategy(traj, env_info, task_info):
    """
    Verify ATM strategy creation via file artifacts and VLM trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    result_path = task_info.get('metadata', {}).get('result_path', r"C:\Users\Docker\Desktop\NinjaTraderTasks\configure_atm_strategy_result.json")
    
    # 1. Retrieve programmatic result
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # We need to map Windows path to what copy_from_env expects? 
        # Usually copy_from_env expects absolute path in container.
        # The env is Windows, so paths are C:\...
        copy_from_env(result_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Failed to retrieve verification data (template file not found or export failed)."
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # --- Programmatic Verification (65 points) ---

    # Criterion 1: File Exists (20 pts)
    if result.get('template_exists'):
        score += 20
        feedback.append("ATM Template file created.")
    else:
        feedback.append("ATM Template file 'SPY_Scalp' NOT found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Criterion 2: Anti-Gaming / Freshness (10 pts)
    if result.get('file_created_during_task'):
        score += 10
        feedback.append("Template was created during the task session.")
    else:
        feedback.append("Warning: Template file timestamp is old (pre-task).")
        # We don't fail immediately but penalize heavily
    
    # Criterion 3: Parameters (Stop Loss, Targets) (35 pts)
    # We parse the XML content dumped in the JSON if direct fields failed or need regex
    xml_content = result.get('xml_content', "")
    
    # Simple regex parsing on XML string because structure varies
    # Looking for <StopLoss>value</StopLoss> or parameter="StopLoss" value="3"
    
    # Check Stop Loss
    sl_match = False
    # Regex for <StopLoss>3</StopLoss> or value="3" inside a stop loss node
    # Simplifying: look for numeric patterns associated with StopLoss
    sl_patterns = re.findall(r'StopLoss.*?(\d+(?:\.\d+)?)', xml_content, re.IGNORECASE)
    # Also check raw value from powershell export
    raw_sl = result.get('stop_loss_value')
    
    found_sl_vals = []
    if raw_sl: found_sl_vals.append(raw_sl)
    found_sl_vals.extend(sl_patterns)
    
    if any(check_value_match(v, VALID_STOP_VALUES) for v in found_sl_vals):
        score += 15
        feedback.append("Stop Loss configured correctly (3 pts/ticks).")
        sl_match = True
    else:
        feedback.append(f"Stop Loss incorrect or not found. Found values: {found_sl_vals}")

    # Check Profit Targets
    # Need 2 targets
    # Regex for ProfitTarget tags
    pt_matches = re.findall(r'ProfitTarget.*?(\d+(?:\.\d+)?)', xml_content, re.IGNORECASE)
    
    # We expect values matching ~2 and ~5
    has_t1 = any(check_value_match(v, VALID_T1_VALUES) for v in pt_matches)
    has_t2 = any(check_value_match(v, VALID_T2_VALUES) for v in pt_matches)
    
    if has_t1 and has_t2:
        score += 20
        feedback.append("Both Profit Targets (2 and 5) configured correctly.")
    elif has_t1 or has_t2:
        score += 10
        feedback.append("Only one correct Profit Target found.")
    else:
        feedback.append(f"Profit Targets incorrect. Found: {pt_matches}")

    # --- VLM Verification (35 points) ---
    
    # We sample frames to verify the workflow
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    Analyze these screenshots of NinjaTrader 8. The user is supposed to create an ATM Strategy.
    Look for:
    1. An 'ATM Strategy' dropdown or dialog box.
    2. Configuration of 'Stop Loss' and 'Profit Target'.
    3. Values entered like 3, 2, 5.
    4. Saving a template named 'SPY_Scalp'.
    
    Return JSON:
    {
        "atm_dialog_seen": boolean,
        "values_entered": boolean,
        "template_saved": boolean,
        "confidence": "low/medium/high"
    }
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
    
    vlm_score = 0
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        if parsed.get('atm_dialog_seen'):
            vlm_score += 15
            feedback.append("VLM: ATM configuration dialog detected.")
        if parsed.get('values_entered'):
            vlm_score += 10
            feedback.append("VLM: Parameter entry detected.")
        if parsed.get('template_saved'):
            vlm_score += 10
            feedback.append("VLM: Template save action detected.")
            
    score += vlm_score

    # Final Pass Determination
    # Must have file, must have reasonable score
    passed = (score >= 60) and result.get('template_exists')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }