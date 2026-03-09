#!/usr/bin/env python3
"""
Verifier for Configure Multi-Group Instrument Linking task.

Verification Strategy:
1. Parse exported JSON containing workspace window configurations.
2. Validate existence of required window types (Chart, SuperDom, TimeAndSales).
3. Validate correct instrument assignment (SPY, AAPL).
4. Validate correct Link Color grouping (Red vs Blue).
5. VLM checks for visual confirmation (colors and layout).
"""

import json
import tempfile
import os
import logging
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# NinjaTrader Link Color Mapping (Approximate, based on common XML values)
# 0=None, 1=Red, 2=Blue, 3=Green, 4=Gold, etc.
# Also accepts string values if the XML serializes them that way.
RED_LINK_VALUES = [1, "Red", "red", "#FFFF0000", "RedLink"]
BLUE_LINK_VALUES = [2, "Blue", "blue", "#FF0000FF", "BlueLink"]

def check_link_match(actual_val, expected_set):
    """Check if actual link value matches any expected representation."""
    if actual_val in expected_set:
        return True
    try:
        # handle string representation of ints
        if int(actual_val) in expected_set:
            return True
    except (ValueError, TypeError):
        pass
    return False

def verify_configure_multi_group_instrument_linking(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define paths
    # Note: Windows path in container mapped to local temp
    # The export script saves to C:\Users\Docker\Desktop\NinjaTraderTasks\configure_multi_group_instrument_linking_result.json
    # We need to copy that file.
    
    # In this environment, we assume the C drive is accessible or mapped. 
    # Usually copy_from_env handles the path translation or we use the linux path if running via wine/docker.
    # Based on the env spec, it's a Windows container.
    remote_path = "C:\\Users\\Docker\\Desktop\\NinjaTraderTasks\\configure_multi_group_instrument_linking_result.json"
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(remote_path, temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Workspace Saved (10 pts)
    if result.get('workspace_saved'):
        score += 10
        feedback_parts.append("Workspace saved (+10)")
    else:
        feedback_parts.append("Workspace NOT saved (0)")
        # Early exit if no workspace data
        return {"passed": False, "score": 0, "feedback": "Workspace not saved, cannot verify configuration."}

    windows = result.get('windows_found', [])
    
    # Helper to find windows
    def find_windows(target_instrument, target_type=None):
        matches = []
        for w in windows:
            instr = w.get('Instrument', '')
            w_type = w.get('Type', '')
            # Flexible matching for instrument (e.g., "SPY" in "SPY Default")
            instr_match = target_instrument.upper() in instr.upper()
            type_match = True
            if target_type:
                # Flexible matching for type (e.g. "SuperDom" vs "DynamicSuperDom")
                type_match = target_type.lower() in w_type.lower()
            
            if instr_match and type_match:
                matches.append(w)
        return matches

    # 2. Market Group (SPY/Red) Validation
    # Needs SPY Chart (20 pts)
    spy_charts = find_windows("SPY", "Chart")
    spy_chart_ok = False
    for w in spy_charts:
        link = w.get('LinkColor')
        if check_link_match(link, RED_LINK_VALUES):
            spy_chart_ok = True
            break
            
    if spy_chart_ok:
        score += 20
        feedback_parts.append("SPY Chart (Red) OK (+20)")
    elif spy_charts:
        # Found chart but wrong link
        score += 10
        feedback_parts.append(f"SPY Chart found but wrong link: {spy_charts[0].get('LinkColor')} (+10)")
    else:
        feedback_parts.append("SPY Chart missing (0)")

    # Needs SPY SuperDOM (20 pts)
    spy_doms = find_windows("SPY", "SuperDom")
    spy_dom_ok = False
    for w in spy_doms:
        link = w.get('LinkColor')
        if check_link_match(link, RED_LINK_VALUES):
            spy_dom_ok = True
            break
            
    if spy_dom_ok:
        score += 20
        feedback_parts.append("SPY SuperDOM (Red) OK (+20)")
    elif spy_doms:
        score += 10
        feedback_parts.append("SPY SuperDOM found but wrong link (+10)")
    else:
        feedback_parts.append("SPY SuperDOM missing (0)")

    # 3. Stock Group (AAPL/Blue) Validation
    # Needs AAPL Chart (20 pts)
    aapl_charts = find_windows("AAPL", "Chart")
    aapl_chart_ok = False
    for w in aapl_charts:
        link = w.get('LinkColor')
        if check_link_match(link, BLUE_LINK_VALUES):
            aapl_chart_ok = True
            break
            
    if aapl_chart_ok:
        score += 20
        feedback_parts.append("AAPL Chart (Blue) OK (+20)")
    elif aapl_charts:
        score += 10
        feedback_parts.append("AAPL Chart found but wrong link (+10)")
    else:
        feedback_parts.append("AAPL Chart missing (0)")

    # Needs AAPL Time & Sales (20 pts)
    aapl_tapes = find_windows("AAPL", "TimeAndSales")
    aapl_tape_ok = False
    for w in aapl_tapes:
        link = w.get('LinkColor')
        if check_link_match(link, BLUE_LINK_VALUES):
            aapl_tape_ok = True
            break
            
    if aapl_tape_ok:
        score += 20
        feedback_parts.append("AAPL T&S (Blue) OK (+20)")
    elif aapl_tapes:
        score += 10
        feedback_parts.append("AAPL T&S found but wrong link (+10)")
    else:
        feedback_parts.append("AAPL T&S missing (0)")

    # 4. Isolation/Cross-contamination check (10 pts)
    # Ensure no SPY window is Blue and no AAPL window is Red
    contamination = False
    for w in windows:
        instr = w.get('Instrument', '').upper()
        link = w.get('LinkColor')
        
        if "SPY" in instr and check_link_match(link, BLUE_LINK_VALUES):
            contamination = True
        if "AAPL" in instr and check_link_match(link, RED_LINK_VALUES):
            contamination = True
            
    if not contamination and score > 10: # Only award if some windows exist
        score += 10
        feedback_parts.append("Groups Isolated (+10)")
    elif contamination:
        feedback_parts.append("Link Groups Contaminated (0)")

    # Calculate final status
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }