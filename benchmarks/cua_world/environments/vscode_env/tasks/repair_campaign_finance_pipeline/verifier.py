#!/usr/bin/env python3
"""
Verifier for repair_campaign_finance_pipeline task.

Uses a bulletproof anti-gaming approach: The agent's modified Python script
was executed against a hidden ground-truth dataset that the agent cannot see.
We verify the logical fixes by strictly parsing the output generated from
the hidden dataset.

Hidden Dataset Test Cases:
1. "DATE, TEST" - Month 10. (Fails to parse if %d%m%Y is used).
2. "SMITH, JANE" - Has a $3500 contribution and a $-500 refund. (Flagged if >0 filter left in).
3. "WILLIAMS, TOM" - Split across different cases/zips ($2000 each). (NOT flagged if unnormalized).
4. "JOHNSON, ANN" - Has $2500 in P2024 and $2500 in G2024. (Flagged if election scoping is missing).
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_campaign_finance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/campaign_finance_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    run_exit_code = result.get('run_exit_code', 1)
    monthly_trends = result.get('secret_monthly_trends', '')
    flagged_violators = result.get('secret_flagged_violators', '').upper()
    script_content = result.get('script_content', '')

    score = 0
    feedback_parts = []
    
    # Baseline validation: Did the script crash or produce empty outputs?
    has_output = bool(monthly_trends.strip()) and bool(flagged_violators.strip())
    
    if run_exit_code != 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Python script crashed or failed to run (Exit Code {run_exit_code}). Make sure syntax is valid."
        }
    if not has_output:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Script executed but failed to produce the required CSV outputs."
        }
        
    # We require the script to at least show it isn't outputting an empty file to bypass negative checks
    # WILLIAMS is the ONLY true violator in the dataset if logic is perfect. 
    # If the output is totally empty, williams_flagged will be False, but we shouldn't award points for absence.
    is_empty_violators = len(flagged_violators.split('\n')) <= 2 and 'WILLIAMS' not in flagged_violators and 'SMITH' not in flagged_violators and 'JOHNSON' not in flagged_violators

    if is_empty_violators:
        feedback_parts.append("WARNING: Output files are virtually empty. Logic may be completely filtering out valid rows.")

    # -------------------------------------------------------------------------
    # Criterion 1: Date Parsing (25 pts)
    # The MMDDYYYY fix ensures month 10 is correctly parsed.
    # -------------------------------------------------------------------------
    has_month_10 = bool(re.search(r'^10(?:\.0)?\s*,', monthly_trends, re.MULTILINE))
    if has_month_10:
        score += 25
        feedback_parts.append("[+] Date Parsing: October dates correctly processed.")
    else:
        feedback_parts.append("[-] Date Parsing: Missing late months (date format still likely %d%m%Y).")

    # -------------------------------------------------------------------------
    # Criterion 2: Net Amounts (25 pts)
    # If the > 0 filter is removed, SMITH's $3500 is offset by $-500 to equal $3000 (Safe).
    # If left in, SMITH is flagged at $3500.
    # -------------------------------------------------------------------------
    smith_flagged = 'SMITH' in flagged_violators
    if not smith_flagged and not is_empty_violators:
        score += 25
        feedback_parts.append("[+] Net Amounts: Refunds are correctly offsetting contributions.")
    else:
        feedback_parts.append("[-] Net Amounts: Refunds are being ignored, causing false positives.")

    # -------------------------------------------------------------------------
    # Criterion 3: Donor Normalization (25 pts)
    # If names/zips are normalized, WILLIAMS combines 2000+2000=4000 (Flagged).
    # If not, WILLIAMS remains split and safe.
    # -------------------------------------------------------------------------
    williams_flagged = 'WILLIAMS' in flagged_violators
    if williams_flagged:
        score += 25
        feedback_parts.append("[+] Donor Normalization: Different name casings and zip lengths successfully merged.")
    else:
        feedback_parts.append("[-] Donor Normalization: Variations in donor names/zips are splitting records.")

    # -------------------------------------------------------------------------
    # Criterion 4: Election Scoping (25 pts)
    # If grouped by election, JOHNSON has P2024(2500) and G2024(2500) (Safe).
    # If not, JOHNSON combines to 5000 (Flagged).
    # -------------------------------------------------------------------------
    johnson_flagged = 'JOHNSON' in flagged_violators
    if not johnson_flagged and not is_empty_violators:
        score += 25
        feedback_parts.append("[+] Election Scoping: Contributions correctly separated by Primary/General.")
    else:
        feedback_parts.append("[-] Election Scoping: Contributions falsely merged across different elections.")

    pass_threshold = task_info.get('metadata', {}).get('pass_threshold', 75)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }