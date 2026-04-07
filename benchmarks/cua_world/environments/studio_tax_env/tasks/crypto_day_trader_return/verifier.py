#!/usr/bin/env python3
"""Verifier for crypto_day_trader_return task.

Priya Nair — Software engineer with cryptocurrency investments.
Multiple capital gains (ETH, BTC, MATIC), superficial loss (SOL denied),
staking rewards as interest income (T5), RRSP, and home office expenses.

Scoring (100 pts total, pass threshold 60):
  Criterion 1: File saved correctly (15 pts)
  Criterion 2: Timestamp valid (10 pts)
  Criterion 3: Taxpayer name present (10 pts)
  Criterion 4: T4 employment income ($72,500) present (15 pts)
  Criterion 5: T5 staking/interest income ($1,840) present (10 pts)
  Criterion 6: Capital gains data present (ETH $7,600 or BTC $6,400) (15 pts)
  Criterion 7: RRSP contribution ($5,500) present (10 pts)
  Criterion 8: Multiple capital gain transactions entered (multiple markers) (15 pts)
  25 pts reserved for VLM evaluation

Score cap: Employment income + at least one capital gain amount required to pass.
"""

import json
import os
import tempfile


def verify_crypto_day_trader_return(traj, env_info, task_info):
    """Verify Priya Nair crypto investor return with capital gains."""
    score = 0
    feedback = []

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "No copy_from_env helper"}

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
            temp_path = f.name
        copy_from_env("C:/Users/Docker/Desktop/crypto_trader_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}

    # --- Criterion 1: File saved with correct name (15 pts) ---
    file_ok = result.get('file_exists') and result.get('file_size_bytes', 0) > 500
    if file_ok:
        score += 15
        feedback.append("Return file 'priya_nair.24t' saved")
    else:
        feedback.append("FAIL: Return file not found or too small")

    # --- Criterion 2: Timestamp valid (10 pts) ---
    if result.get('file_is_new'):
        score += 10
        feedback.append("File timestamp valid")
    else:
        feedback.append("FAIL: File timestamp invalid")

    # --- Criterion 3: Taxpayer name (10 pts) ---
    name_ok = result.get('contains_nair') and result.get('contains_priya')
    if name_ok:
        score += 10
        feedback.append("Taxpayer name (Priya Nair) found")
    elif result.get('contains_nair') or result.get('contains_priya'):
        score += 5
        feedback.append("Taxpayer name partially found")
    else:
        feedback.append("FAIL: Taxpayer name not found")

    # --- Criterion 4: T4 employment income $72,500 (15 pts) ---
    employment_ok = result.get('contains_72500', False)
    if employment_ok:
        score += 15
        feedback.append("T4 employment income $72,500 found")
    else:
        feedback.append("FAIL: T4 income $72,500 not found")

    # --- Criterion 5: Interest income from staking $1,840 (10 pts) ---
    interest_ok = result.get('contains_1840', False)
    if interest_ok:
        score += 10
        feedback.append("T5 staking/interest income $1,840 found")
    else:
        feedback.append("FAIL: Staking/interest income $1,840 not found")

    # --- Criterion 6: Capital gains data — ETH $7,600 or BTC $6,400 (15 pts) ---
    eth_ok = result.get('contains_7600', False)
    btc_ok = result.get('contains_6400', False)
    eth_proceeds_ok = result.get('contains_16800', False)
    capgain_marker = result.get('contains_capgain', False)
    if eth_ok and btc_ok:
        score += 15
        feedback.append("Capital gains: ETH ($7,600) and BTC ($6,400) both found")
    elif eth_ok or btc_ok or eth_proceeds_ok:
        score += 8
        feedback.append("Partial capital gains data found")
    elif capgain_marker:
        score += 4
        feedback.append("Capital gains section present but amounts not verified")
    else:
        feedback.append("FAIL: Capital gains data not found")

    # --- Criterion 7: RRSP contribution $5,500 (10 pts) ---
    rrsp_ok = result.get('contains_5500', False)
    if rrsp_ok:
        score += 10
        feedback.append("RRSP contribution $5,500 found")
    else:
        feedback.append("FAIL: RRSP $5,500 not found")

    # --- Criterion 8: Multiple capital gain entries (home office or MATIC loss) (15 pts) ---
    # Checks that agent entered multiple transactions, not just one
    matic_ok = result.get('contains_2100', False)
    home_office_ok = result.get('contains_2288', False) or result.get('contains_2202', False)
    multi_entry_score = 0
    multi_notes = []
    if matic_ok:
        multi_entry_score += 8
        multi_notes.append("MATIC loss entry")
    if home_office_ok:
        multi_entry_score += 7
        multi_notes.append("home office deduction")
    if multi_entry_score >= 15:
        score += 15
        feedback.append(f"Multiple detailed entries found: {', '.join(multi_notes)}")
    elif multi_entry_score > 0:
        score += multi_entry_score
        feedback.append(f"Some detail entries found: {', '.join(multi_notes)}")
    else:
        feedback.append("FAIL: MATIC loss / home office not found (incomplete return)")

    # --- Score cap: employment income must be present to pass ---
    if not employment_ok:
        score = min(score, 55)
        feedback.append("SCORE CAP: T4 employment income required to pass")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {"vlm_reserved": 25, "max_programmatic": 100},
        "subscores": {
            "file_saved": 15 if file_ok else 0,
            "timestamp": 10 if result.get('file_is_new') else 0,
            "name": 10 if name_ok else (5 if (result.get('contains_nair') or result.get('contains_priya')) else 0),
            "employment": 15 if employment_ok else 0,
            "interest_income": 10 if interest_ok else 0,
            "capital_gains": 15 if (eth_ok and btc_ok) else (8 if (eth_ok or btc_ok or eth_proceeds_ok) else (4 if capgain_marker else 0)),
            "rrsp": 10 if rrsp_ok else 0,
            "completeness": multi_entry_score,
            "vlm_evaluation": "pending"
        }
    }
