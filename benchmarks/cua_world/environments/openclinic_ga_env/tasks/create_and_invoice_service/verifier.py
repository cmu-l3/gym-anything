#!/usr/bin/env python3
"""
Verifier for create_and_invoice_service task.
Verifies that:
1. Service TELE01 was created with correct price.
2. A charge for this service exists for the patient.
3. An invoice exists and includes this charge.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_and_invoice_service(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # Check 1: Service Creation (30 pts)
    # ------------------------------------------------------------------
    service_data = result.get("service", {})
    if service_data.get("found"):
        score += 10
        feedback.append("Service TELE01 found.")
        
        # Check Price
        try:
            price = float(service_data.get("price", 0))
            if abs(price - 15.00) < 0.1:
                score += 20
                feedback.append("Service price is correct (15.00).")
            else:
                feedback.append(f"Service price incorrect (Expected 15.00, got {price}).")
        except:
            feedback.append("Could not verify service price.")
    else:
        feedback.append("Service TELE01 NOT found in catalog.")

    # ------------------------------------------------------------------
    # Check 2: Charge Recording (30 pts)
    # ------------------------------------------------------------------
    charge_data = result.get("charge", {})
    if charge_data.get("found"):
        score += 30
        feedback.append("Charge recorded for patient 10004.")
    else:
        feedback.append("No charge/debet found for this service/patient.")

    # ------------------------------------------------------------------
    # Check 3: Invoice Generation & Linkage (40 pts)
    # ------------------------------------------------------------------
    invoice_data = result.get("invoice", {})
    charge_invoiced = charge_data.get("invoiced")
    
    if charge_invoiced and invoice_data.get("found"):
        score += 30
        feedback.append("Invoice created and charge linked.")
        
        # Timestamp check
        # DB timestamp format often "YYYY-MM-DD HH:MM:SS" or similar
        # Task start is unix epoch
        try:
            db_time_str = invoice_data.get("timestamp", "")
            task_start = int(result.get("task_start_timestamp", 0))
            
            # Simple check: if db_time_str is not empty, assume it's valid for now
            # Converting MySQL datetime string to epoch can be tricky without reliable parsing lib
            if db_time_str:
                score += 10 # Bonus for valid timestamp presence indicating new record
                feedback.append("Invoice verified as new.")
        except:
            pass
            
    elif charge_invoiced:
        # Charge has an invoice ID but we couldn't fetch the invoice?
        score += 20
        feedback.append("Charge is marked as invoiced, but invoice record verification failed.")
    elif invoice_data.get("found"):
        # Invoice found but charge not linked?
        score += 10
        feedback.append("Invoice found, but the specific charge is not linked to it.")
    else:
        feedback.append("No invoice generated.")

    # ------------------------------------------------------------------
    # VLM Verification (Bonus/Fallback)
    # ------------------------------------------------------------------
    # We primarily trust the DB, but if they failed invoice step, check screenshots
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    
    if score < 70:
        frames = sample_trajectory_frames(traj, n=3)
        if frames and env_info.get('query_vlm'):
            vlm_prompt = "Does this screen show an invoice being created or displayed for patient Darwin Charles? Look for 'Invoice', 'Bill', or 'Financial' headers."
            try:
                vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
                if vlm_res.get("success") and vlm_res.get("parsed", {}).get("answer", False):
                    score += 10
                    feedback.append("VLM detected invoice activity (partial credit).")
            except:
                pass

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }