#!/usr/bin/env python3
"""
Verifier for Copper POS Regional Settings configuration.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_regional_settings(traj, env_info, task_info):
    """
    Verify that Regional Settings (Currency, Date, Tax) were correctly configured.
    
    Verification Strategy:
    1. Check Registry Dump: Look for specific values (£, dd/MM/yyyy, VAT) in the
       exported registry data from NCH Copper.
    2. VLM Trajectory: Verify the agent navigated to the Options/Preferences menu.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Extract data
    reg_data = result.get('registry_data', {})
    dump_text = reg_data.get('all_settings_dump', '') + str(reg_data.get('tax_name', ''))
    
    # Metadata expectations
    metadata = task_info.get('metadata', {})
    exp_currency = metadata.get('expected_currency_symbol', '£')
    exp_date = metadata.get('expected_date_format', 'dd/MM/yyyy')
    exp_tax = metadata.get('expected_tax_name', 'VAT')

    score = 0
    feedback_parts = []
    
    # 1. Currency Check (40 pts)
    # Check specific field if parsed, otherwise search dump
    currency_val = reg_data.get('currency_symbol', '')
    if exp_currency in str(currency_val) or (exp_currency in dump_text):
        score += 40
        feedback_parts.append(f"Currency set to {exp_currency}")
    else:
        feedback_parts.append(f"Currency symbol '{exp_currency}' not found in settings")

    # 2. Tax Name Check (30 pts)
    # Tax names usually appear in the tax config
    if exp_tax in dump_text:
        score += 30
        feedback_parts.append(f"Tax name '{exp_tax}' found")
    else:
        feedback_parts.append(f"Tax name '{exp_tax}' not found in settings")

    # 3. Date Format Check (20 pts)
    date_val = reg_data.get('date_format', '')
    # Check for exact format or close equivalent
    if exp_date in str(date_val) or (exp_date in dump_text):
        score += 20
        feedback_parts.append(f"Date format set to {exp_date}")
    else:
        feedback_parts.append(f"Date format '{exp_date}' not found")

    # 4. VLM Navigation Check (10 pts)
    # Use the trajectory to see if "Options" or "Preferences" window was opened
    # This acts as proof of work (anti-gaming)
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_resp = query_vlm(
            images=frames,
            prompt="Analyze these screenshots of Copper POS. Does the user open an 'Options', 'Preferences', or 'Settings' window? Look for a dialog with tabs like 'General', 'Regional', or 'Tax'. Answer YES or NO."
        )
        if vlm_resp and vlm_resp.get('success'):
            ans = vlm_resp.get('response', '').upper()
            if "YES" in ans:
                score += 10
                feedback_parts.append("Navigation verified via VLM")
            else:
                feedback_parts.append("VLM did not detect Options window")
        else:
            # Fallback if VLM fails: give points if registry checks passed (benefit of doubt)
            if score >= 50:
                score += 10
    
    # Pass threshold: 70 points
    # Must get at least Currency and Tax correct, or Currency+Date+Nav
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }