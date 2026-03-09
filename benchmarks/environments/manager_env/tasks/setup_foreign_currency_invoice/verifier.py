#!/usr/bin/env python3
"""
Verifier for setup_foreign_currency_invoice task.

Criteria:
1. Base Currency is USD.
2. Foreign Currency EUR exists with rate ~1.08.
3. Customer 'Alfreds Futterkiste' uses EUR.
4. Sales Invoice created for Alfreds with correct details (Amount, Date, Ref).
5. VLM verification of workflow.
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_foreign_currency_invoice(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load programmatic result
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
    feedback_parts = []
    
    # 1. Base Currency (10 pts)
    # Note: Manager often defaults to base currency if not set, but explicit setting is requested.
    # The scraping script tries to find evidence of USD.
    if result.get("base_currency_set"):
        score += 10
        feedback_parts.append("Base currency USD set.")
    else:
        feedback_parts.append("Base currency USD not verified.")

    # 2. Foreign Currency EUR (20 pts)
    if result.get("foreign_currency_exists"):
        score += 20
        feedback_parts.append("EUR currency added.")
        
        # Rate check (10 pts)
        rate = result.get("exchange_rate", 0)
        if 1.0 < rate < 1.15: # Allow tolerance around 1.08
            score += 10
            feedback_parts.append(f"Exchange rate {rate} is correct.")
        else:
            feedback_parts.append(f"Exchange rate {rate} is outside expected range (1.08).")
    else:
        feedback_parts.append("EUR currency not found.")

    # 3. Customer Currency (20 pts)
    if result.get("customer_currency_set"):
        score += 20
        feedback_parts.append("Customer currency set to EUR.")
    else:
        feedback_parts.append("Customer currency update not verified.")

    # 4. Sales Invoice (30 pts)
    # Must be new (count increased) AND have correct details
    inv_exists = result.get("invoice_exists")
    init_count = result.get("initial_invoice_count", 0)
    final_count = result.get("final_invoice_count", 0)
    new_invoice_created = final_count > init_count

    if inv_exists and new_invoice_created:
        score += 20
        feedback_parts.append("EUR Invoice created.")
        
        details = result.get("invoice_details", {})
        if details.get("date_correct"):
            score += 5
            feedback_parts.append("Invoice date correct.")
        
        if details.get("currency_symbol_found"):
            score += 5
            feedback_parts.append("Invoice appears to be in EUR.")
    elif inv_exists:
         # Exists but count didn't increase? Maybe modified existing? Less points.
         score += 10
         feedback_parts.append("Invoice found but may not be new.")
    else:
         feedback_parts.append("Required invoice not found.")

    # 5. VLM Verification (10 pts)
    # Check for visual evidence of Settings and Invoice creation
    try:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = """
            Analyze these screenshots of a user using Manager.io accounting software.
            I am looking for a workflow where the user:
            1. Goes to Settings > Currencies.
            2. Edits a Customer (Alfreds Futterkiste).
            3. Creates a Sales Invoice.
            
            Do you see evidence of at least TWO of these distinct activities?
            Respond 'YES' or 'NO' with a brief reason.
            """
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                # Simple keyword check if parsing isn't structured
                resp_text = str(parsed).upper() if parsed else str(vlm_res.get("response", "")).upper()
                
                if "YES" in resp_text:
                    score += 10
                    feedback_parts.append("VLM verified workflow.")
                else:
                    feedback_parts.append("VLM could not clearly verify workflow.")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }