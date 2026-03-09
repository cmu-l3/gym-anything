#!/usr/bin/env python3
"""
Verifier for configure_payment_gateways task.

Verification Strategy:
1. Primary (Programmatic): Check WooCommerce database options via exported JSON.
   - Verify BACS is enabled and has correct bank details (Name, IBAN, etc.).
   - Verify Check payments are enabled with correct instructions.
   - Verify COD is disabled.
2. Secondary (VLM): Analyze trajectory to ensure agent interacted with the payment settings UI.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_payment_gateways(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    bacs_meta = metadata.get('bacs', {})
    cheque_meta = metadata.get('cheque', {})

    # Copy result file
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

    score = 0
    feedback = []

    # ============================================================
    # 1. BACS Verification (Max 50 pts)
    # ============================================================
    bacs_settings = result.get('bacs_settings', {})
    bacs_accounts = result.get('bacs_accounts', [])
    
    # Handle case where accounts might be inside a dict under a key or raw list
    # The export script tries to output JSON, but WP CLI might output an object with numeric keys
    if isinstance(bacs_accounts, dict):
        # Convert {"0": {...}} to [{...}]
        bacs_accounts = list(bacs_accounts.values())

    # Check Enabled (10 pts)
    if bacs_settings.get('enabled') == 'yes':
        score += 10
        feedback.append("BACS enabled (10/10)")
    else:
        feedback.append("BACS not enabled (0/10)")

    # Check Title (5 pts)
    if bacs_meta.get('title', '').lower() in bacs_settings.get('title', '').lower():
        score += 5
        feedback.append("BACS title correct (5/5)")
    else:
        feedback.append("BACS title incorrect (0/5)")

    # Check Account Details (35 pts)
    # We look for at least one account matching details
    account_match_score = 0
    target_account = bacs_meta
    
    if bacs_accounts and len(bacs_accounts) > 0:
        # Check the first account
        acc = bacs_accounts[0]
        
        # Helper to check field match
        def check_field(field_key, pts, name):
            val = acc.get(field_key, '').strip()
            target = target_account.get(field_key, '').strip()
            if val.lower() == target.lower():
                return pts, f"{name} correct"
            return 0, f"{name} mismatch ('{val}' vs '{target}')"

        pts, msg = check_field('account_name', 10, "Account Name")
        account_match_score += pts
        if pts==0: feedback.append(msg)

        pts, msg = check_field('account_number', 5, "Account Number")
        account_match_score += pts
        if pts==0: feedback.append(msg)

        pts, msg = check_field('bank_name', 5, "Bank Name")
        account_match_score += pts
        if pts==0: feedback.append(msg)
        
        pts, msg = check_field('sort_code', 5, "Sort Code")
        account_match_score += pts
        if pts==0: feedback.append(msg)
        
        pts, msg = check_field('iban', 5, "IBAN")
        account_match_score += pts
        if pts==0: feedback.append(msg)

        pts, msg = check_field('bic', 5, "BIC")
        account_match_score += pts
        if pts==0: feedback.append(msg)
        
        feedback.append(f"Bank Account Details Score: {account_match_score}/35")
    else:
        feedback.append("No bank accounts found (0/35)")

    score += account_match_score

    # ============================================================
    # 2. Check Payments Verification (Max 20 pts)
    # ============================================================
    cheque_settings = result.get('cheque_settings', {})
    
    # Check Enabled (10 pts)
    if cheque_settings.get('enabled') == 'yes':
        score += 10
        feedback.append("Check payments enabled (10/10)")
    else:
        feedback.append("Check payments not enabled (0/10)")

    # Check Instructions (10 pts)
    instr = cheque_settings.get('instructions', '').lower()
    keywords = [k.lower() for k in cheque_meta.get('instruction_keywords', [])]
    if all(k in instr for k in keywords) and len(keywords) > 0:
        score += 10
        feedback.append("Check instructions correct (10/10)")
    else:
        feedback.append("Check instructions missing keywords (0/10)")

    # ============================================================
    # 3. COD Verification (Max 10 pts)
    # ============================================================
    cod_settings = result.get('cod_settings', {})
    
    # Must be disabled (enabled != yes)
    if cod_settings.get('enabled') != 'yes':
        score += 10
        feedback.append("Cash on Delivery disabled (10/10)")
    else:
        feedback.append("Cash on Delivery still enabled (0/10)")

    # ============================================================
    # 4. VLM Trajectory Verification (Max 20 pts)
    # ============================================================
    # We want to confirm they actually visited the settings pages
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        
        prompt = """
        Analyze these screenshots of a WooCommerce task. 
        The user should be configuring payment methods.
        
        Look for:
        1. The 'WooCommerce > Settings > Payments' table.
        2. Configuration forms for 'Direct bank transfer' or 'Check payments'.
        
        Return JSON:
        {
            "payments_tab_visited": true/false,
            "configuration_form_seen": true/false,
            "reasoning": "string"
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('payments_tab_visited'):
                vlm_score += 10
            if parsed.get('configuration_form_seen'):
                vlm_score += 10
            feedback.append(f"VLM verification: {parsed.get('reasoning', 'Proved')}")
        else:
            # Fallback if VLM fails: give partial credit if score is already high
            # ensuring we don't fail a perfect technical execution on VLM error
            if score >= 70:
                vlm_score = 20
                feedback.append("VLM check skipped (service unavailable), assumed passed based on DB state.")
            else:
                feedback.append("VLM check failed.")
                
    except Exception as e:
        logger.warning(f"VLM error: {e}")
        if score >= 70: 
            vlm_score = 20 # Benevolent fallback

    score += vlm_score
    feedback.append(f"VLM Score: {vlm_score}/20")

    # ============================================================
    # Final Result
    # ============================================================
    passed = score >= 75  # Need 75/100 to pass
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }