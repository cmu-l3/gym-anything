#!/usr/bin/env python3
"""
Verifier for NinjaTrader Hot Keys configuration task.

Verifies:
1. XML Config files were modified during the task.
2. Specific hot key patterns exist in the modified config data.
3. Functional verification: Did the agent successfully open the windows?
4. VLM verification: Did the agent navigate the Hot Key Manager UI?
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_hot_keys(traj, env_info, task_info):
    """
    Verify hot key configuration.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: Configuration Persistence (15 pts)
    # ---------------------------------------------------------
    config_modified = result.get('config_modified', False)
    if config_modified:
        score += 15
        feedback_parts.append("Config files modified (+15)")
    else:
        feedback_parts.append("No config changes detected (0)")

    # ---------------------------------------------------------
    # Criterion 2: Hot Key Bindings in Config (60 pts)
    # ---------------------------------------------------------
    findings = result.get('hot_key_findings', [])
    findings_text = " ".join(findings).lower()
    
    # Check for Chart binding (Ctrl+Shift+C)
    # Looking for combinations of "chart" and "c" and "shift" within the findings snippets
    # This is a heuristic since we are parsing grep output from the PS script
    chart_success = False
    if "chart" in findings_text and "shift" in findings_text and ("key=\"c\"" in findings_text or "key='c'" in findings_text or " c " in findings_text):
        chart_success = True
        score += 20
        feedback_parts.append("Chart hotkey found (+20)")
    else:
        feedback_parts.append("Chart hotkey missing")

    # Check for Strategy Analyzer (Ctrl+Shift+A)
    strat_success = False
    if "strategyanalyzer" in findings_text and "shift" in findings_text and ("key=\"a\"" in findings_text or "key='a'" in findings_text or " a " in findings_text):
        strat_success = True
        score += 20
        feedback_parts.append("Strategy Analyzer hotkey found (+20)")
    else:
        feedback_parts.append("Strategy Analyzer hotkey missing")

    # Check for Market Analyzer (Ctrl+Shift+M)
    market_success = False
    if "marketanalyzer" in findings_text and "shift" in findings_text and ("key=\"m\"" in findings_text or "key='m'" in findings_text or " m " in findings_text):
        market_success = True
        score += 20
        feedback_parts.append("Market Analyzer hotkey found (+20)")
    else:
        feedback_parts.append("Market Analyzer hotkey missing")

    # ---------------------------------------------------------
    # Criterion 3: Functional Verification (10 pts)
    # ---------------------------------------------------------
    windows = result.get('windows_detected', {})
    any_window_opened = windows.get('chart') or windows.get('strategy_analyzer') or windows.get('market_analyzer')
    
    if any_window_opened:
        score += 10
        feedback_parts.append("Functional test passed: Window opened (+10)")
    else:
        feedback_parts.append("No target windows detected open (0)")

    # ---------------------------------------------------------
    # Criterion 4: Confirmation File (10 pts)
    # ---------------------------------------------------------
    if result.get('text_file_exists'):
        content = result.get('text_content', "").lower()
        if "ctrl" in content and "shift" in content:
            score += 10
            feedback_parts.append("Confirmation file valid (+10)")
        else:
            score += 5
            feedback_parts.append("Confirmation file exists but content vague (+5)")
    else:
        feedback_parts.append("Confirmation file missing (0)")

    # ---------------------------------------------------------
    # Criterion 5: VLM Process Verification (5 pts)
    # ---------------------------------------------------------
    # Check if the agent actually interacted with the Hot Keys menu
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        prompt = """
        Review these screenshots of a NinjaTrader user session.
        Look for the 'Hot Key Manager' dialog or 'Tools > Hot Keys' menu being open.
        Also look for any evidence of assigning keys like 'Ctrl+Shift+C'.
        
        Respond JSON: {"hot_key_menu_seen": true/false, "confidence": "low/high"}
        """
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('hot_key_menu_seen'):
                    vlm_score = 5
                    feedback_parts.append("VLM confirmed menu navigation (+5)")
        except Exception:
            pass # Fail silently on VLM error
            
    score += vlm_score

    # ---------------------------------------------------------
    # Final Score Calculation
    # ---------------------------------------------------------
    # Threshold: 70 points
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }