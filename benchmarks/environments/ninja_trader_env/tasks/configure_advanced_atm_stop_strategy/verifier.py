#!/usr/bin/env python3
"""
Verifier for configure_advanced_atm_stop_strategy task.

Criteria:
1. Template file exists and was created during task (20 pts)
2. Basic ATM parameters (Stop Loss 20, Profit Target 40) (20 pts)
3. Auto-Breakeven configured (Trigger 10, Plus 1) (30 pts)
4. Auto-Trail configured (Trigger 15, Stop 5) (30 pts)

Pass threshold: 70 points (Must get at least one advanced strategy correct)
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_advanced_atm_stop_strategy(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expected values from metadata
    metadata = task_info.get('metadata', {})
    exp_sl = metadata.get('stop_loss', 20)
    exp_pt = metadata.get('profit_target', 40)
    
    be_cfg = metadata.get('auto_breakeven', {})
    exp_be_trigger = be_cfg.get('trigger', 10)
    exp_be_plus = be_cfg.get('plus', 1)
    
    at_cfg = metadata.get('auto_trail', {})
    exp_at_trigger = at_cfg.get('trigger', 15)
    exp_at_stop = at_cfg.get('stop', 5)

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/Users/Docker/Desktop/NinjaTraderTasks/configure_advanced_atm_stop_strategy_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Criterion 1: Template Created (20 pts)
    if result.get('template_exists') and result.get('file_created_during_task'):
        score += 20
        feedback.append("Template file created successfully (+20)")
    elif result.get('template_exists'):
        # Existed but timestamp wrong (unlikely with setup script cleaning it, but possible if agent loaded old one)
        score += 5
        feedback.append("Template exists but timestamp check failed (+5)")
    else:
        return {"passed": False, "score": 0, "feedback": "Template 'Scalp_Protector' not found. Ensure you saved the ATM strategy template with the exact name."}

    # Helper for XML raw search if JSON extraction was fuzzy
    raw_xml = result.get('raw_xml_snippet', '')
    
    # Criterion 2: Basic Params (20 pts)
    # Check Stop Loss
    sl_found = result.get('stop_loss')
    if sl_found == exp_sl:
        score += 10
        feedback.append(f"Stop Loss correct: {exp_sl} (+10)")
    else:
        # Fallback regex on raw xml
        if re.search(f'StopLoss.*?{exp_sl}', raw_xml) or re.search(f'value="{exp_sl}".*?StopLoss', raw_xml):
            score += 10
            feedback.append(f"Stop Loss found in XML: {exp_sl} (+10)")
        else:
            feedback.append(f"Stop Loss mismatch or not found (Expected {exp_sl})")

    # Check Profit Target
    pt_found = result.get('profit_target')
    if pt_found == exp_pt:
        score += 10
        feedback.append(f"Profit Target correct: {exp_pt} (+10)")
    else:
        if re.search(f'ProfitTarget.*?{exp_pt}', raw_xml):
            score += 10
            feedback.append(f"Profit Target found in XML: {exp_pt} (+10)")
        else:
            feedback.append(f"Profit Target mismatch (Expected {exp_pt})")

    # Criterion 3: Auto-Breakeven (30 pts)
    be_score = 0
    if result.get('breakeven_enabled'):
        be_score += 10
        # Check params
        # Note: XML parsing in PS1 might be imperfect. We use liberal matching here.
        # Trigger
        if result.get('breakeven_trigger') == exp_be_trigger:
            be_score += 10
        elif re.search(f'ProfitTrigger.*?{exp_be_trigger}', raw_xml):
            be_score += 10
            
        # Plus
        if result.get('breakeven_plus') == exp_be_plus:
            be_score += 10
        elif re.search(f'Plus.*?{exp_be_plus}', raw_xml):
            be_score += 10
            
    # Check raw XML for BE enablement if PS1 missed it
    elif "AutoBreakeven" in raw_xml and "true" in raw_xml:
        # If enabled but specific parsing failed, give partial credit if values exist in text
        if str(exp_be_trigger) in raw_xml and str(exp_be_plus) in raw_xml:
            be_score += 20
            feedback.append("Auto-Breakeven detected via text match")

    score += be_score
    if be_score > 0:
        feedback.append(f"Auto-Breakeven config score: {be_score}/30")
    else:
        feedback.append("Auto-Breakeven not enabled")

    # Criterion 4: Auto-Trail (30 pts)
    at_score = 0
    if result.get('autotrail_enabled'):
        at_score += 10
        # Trigger
        if result.get('autotrail_trigger') == exp_at_trigger:
            at_score += 10
        elif re.search(f'{exp_at_trigger}', raw_xml): # Loose match for 15
            at_score += 10
            
        # Stop
        if result.get('autotrail_stop') == exp_at_stop:
            at_score += 10
        elif re.search(f'{exp_at_stop}', raw_xml): # Loose match for 5
            at_score += 10
            
    elif "AutoTrail" in raw_xml and "true" in raw_xml:
        if str(exp_at_trigger) in raw_xml and str(exp_at_stop) in raw_xml:
            at_score += 20
            feedback.append("Auto-Trail detected via text match")

    score += at_score
    if at_score > 0:
        feedback.append(f"Auto-Trail config score: {at_score}/30")
    else:
        feedback.append("Auto-Trail not enabled")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }