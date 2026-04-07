#!/usr/bin/env python3
"""
Verifier for register_bank_account task in iDempiere.

This verifier checks:
1. Bank record creation (Name, Routing No)
2. Bank Account creation (Name, Number, Type, Currency)
3. Proper linkage between Bank and Account
4. Timestamps/Anti-gaming (implicit via cleanup in setup)
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_register_bank_account(traj, env_info, task_info):
    """
    Verify that the bank and bank account were correctly registered.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected values from metadata
    metadata = task_info.get('metadata', {})
    exp_bank_name = metadata.get('expected_bank_name', 'Metro City Bank')
    exp_routing = metadata.get('expected_routing_no', '021000021')
    exp_acct_name = metadata.get('expected_account_name', 'Payroll Checking')
    exp_acct_no = metadata.get('expected_account_no', '888999000')
    exp_acct_type = metadata.get('expected_account_type', 'C') # 'C' is typically Checking in iDempiere
    exp_currency = metadata.get('expected_currency_iso', 'USD')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # Criterion 1: Bank Record Created (30 pts)
    # ----------------------------------------------------------------
    bank_found = result.get('bank_found', False)
    bank_data = result.get('bank', {})
    
    if bank_found:
        name_match = bank_data.get('name') == exp_bank_name
        routing_match = bank_data.get('routing_no') == exp_routing
        
        if name_match and routing_match:
            score += 30
            feedback_parts.append(f"Bank '{exp_bank_name}' created with correct routing.")
        elif name_match:
            score += 15
            feedback_parts.append(f"Bank '{exp_bank_name}' created but routing number incorrect.")
        else:
            score += 0
            feedback_parts.append(f"Bank created but name mismatch (Found: {bank_data.get('name')}).")
    else:
        feedback_parts.append("Bank record NOT found.")

    # ----------------------------------------------------------------
    # Criterion 2: Account Record Created & Linked (30 pts)
    # ----------------------------------------------------------------
    account_found = result.get('account_found', False)
    account_data = result.get('account', {})
    
    if account_found:
        # If we found the account via the LEFT JOIN in export_result.sh, 
        # it is guaranteed to be linked to the bank we queried.
        score += 30
        feedback_parts.append("Bank Account created and linked to Bank.")
    else:
        feedback_parts.append("Bank Account record NOT found or not linked to the correct Bank.")

    # ----------------------------------------------------------------
    # Criterion 3: Account Details (20 pts)
    # ----------------------------------------------------------------
    if account_found:
        acct_no_match = account_data.get('account_no') == exp_acct_no
        acct_name_match = account_data.get('name') == exp_acct_name
        
        if acct_no_match and acct_name_match:
            score += 20
            feedback_parts.append("Account number and name correct.")
        elif acct_no_match:
            score += 10
            feedback_parts.append("Account number correct, name mismatch.")
        elif acct_name_match:
            score += 10
            feedback_parts.append("Account name correct, number mismatch.")
        else:
            feedback_parts.append("Account details incorrect.")

    # ----------------------------------------------------------------
    # Criterion 4: Account Attributes (Type & Currency) (20 pts)
    # ----------------------------------------------------------------
    if account_found:
        # Check Account Type ('C' for Checking usually, agent might see 'Checking' in UI)
        # We accept 'C' or 'Checking' just in case the query returned the display name vs value
        # The export script returns the raw DB value. In iDempiere DB, 'C' = Checking.
        act_type = account_data.get('type', '')
        # Check Currency
        act_curr = account_data.get('currency', '')
        
        type_ok = (act_type == 'C' or act_type == 'Checking')
        curr_ok = (act_curr == exp_currency)
        
        if type_ok and curr_ok:
            score += 20
            feedback_parts.append("Account type and currency correct.")
        elif type_ok:
            score += 10
            feedback_parts.append("Account type correct, currency mismatch.")
        elif curr_ok:
            score += 10
            feedback_parts.append("Currency correct, account type mismatch.")
        else:
            feedback_parts.append(f"Attributes incorrect (Type: {act_type}, Curr: {act_curr}).")

    # ----------------------------------------------------------------
    # VLM / Anti-Gaming Sanity Check
    # ----------------------------------------------------------------
    # If score is high, ensure the trajectory shows actual work
    if score >= 60:
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=5)
            final_scr = get_final_screenshot(traj)
            
            prompt = (
                "The user is supposed to be using iDempiere ERP to create a Bank and Bank Account. "
                "Look at these screenshots. "
                "1. Is the iDempiere interface visible? "
                "2. Is there a form for 'Bank' or 'Bank Account'? "
                "3. Do you see 'Metro City Bank' or 'Payroll Checking' typed anywhere?"
            )
            
            try:
                vlm_resp = query_vlm(images=frames + [final_scr], prompt=prompt)
                # We won't deduct points automatically unless we're sure, but we log it
                logger.info(f"VLM verification: {vlm_resp}")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")

    # Final Score Calculation
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }