#!/usr/bin/env python3
"""
Verifier for Order Radiology Procedure task in OpenEMR

Verifies that a Chest X-Ray procedure order was correctly created for patient Ruben Bayer (pid=4)
with appropriate clinical indication for pneumonia evaluation.

Uses copy_from_env to read pre-exported verification data from the container.
The export_result.sh script queries the database and saves results to JSON.

Scoring (100 points total):
- Patient identified correctly: 15 points
- Procedure order created: 25 points
- Correct procedure (chest x-ray): 20 points
- Clinical indication documented: 20 points
- Order created during task (timestamp): 10 points
- Order is active/pending (not cancelled): 10 points

Passing threshold: 60 points with procedure order created as mandatory
"""

import sys
import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_order_radiology_procedure(traj, env_info, task_info):
    """
    Verify that a radiology procedure order was correctly created.
    
    Args:
        traj: Trajectory data with frames and steps
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
    
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Copy function not available for verification"
        }
    
    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_pid = metadata.get('patient_pid', 4)
    expected_fname = metadata.get('patient_fname', 'Ruben')
    expected_lname = metadata.get('patient_lname', 'Bayer')
    cpt_codes = metadata.get('procedure_cpt_codes', ['71045', '71046', '71047', '71048'])
    indication_keywords = metadata.get('clinical_indication_keywords', 
        ['pneumonia', 'cough', 'fever', 'dyspnea', 'respiratory', 'chest', 'lung'])
    
    scoring_weights = metadata.get('scoring_weights', {
        'patient_identified': 15,
        'procedure_order_created': 25,
        'correct_procedure': 20,
        'clinical_indication': 20,
        'timestamp_valid': 10,
        'order_active': 10
    })
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/radiology_order_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "patient_identified": False,
            "procedure_order_created": False,
            "correct_procedure": False,
            "clinical_indication": False,
            "timestamp_valid": False,
            "order_active": False
        }
        
        # Extract data from result
        patient_pid = result.get('patient_pid', 0)
        task_start = result.get('task_start_timestamp', 0)
        task_end = result.get('task_end_timestamp', 0)
        
        initial_counts = result.get('initial_counts', {})
        current_counts = result.get('current_counts', {})
        
        proc_order = result.get('procedure_order', {})
        billing_order = result.get('billing_order', {})
        validation = result.get('validation', {})
        
        initial_proc = initial_counts.get('procedure_orders', 0)
        current_proc = current_counts.get('procedure_orders', 0)
        initial_billing = initial_counts.get('billing_entries', 0)
        current_billing = current_counts.get('billing_entries', 0)
        
        logger.info(f"Patient PID: {patient_pid}, Expected: {expected_pid}")
        logger.info(f"Procedure orders: {initial_proc} -> {current_proc}")
        logger.info(f"Billing entries: {initial_billing} -> {current_billing}")
        
        # ===== CRITERION 1: Patient Identified (15 points) =====
        if patient_pid == expected_pid:
            score += scoring_weights['patient_identified']
            subscores['patient_identified'] = True
            feedback_parts.append(f"✓ Correct patient (pid={expected_pid}, {expected_fname} {expected_lname})")
        else:
            feedback_parts.append(f"✗ Wrong patient: expected pid={expected_pid}, got {patient_pid}")
            # Critical failure - wrong patient
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Order created for wrong patient. Expected pid={expected_pid} ({expected_fname} {expected_lname})",
                "subscores": subscores
            }
        
        # ===== CRITERION 2: Procedure Order Created (25 points) =====
        new_proc_order = current_proc > initial_proc
        new_billing = current_billing > initial_billing
        order_created = new_proc_order or new_billing or proc_order.get('found', False) or billing_order.get('found', False)
        
        if order_created:
            score += scoring_weights['procedure_order_created']
            subscores['procedure_order_created'] = True
            if new_proc_order:
                feedback_parts.append(f"✓ Procedure order created (count: {initial_proc} -> {current_proc})")
            elif new_billing:
                feedback_parts.append(f"✓ Billing/fee sheet entry created (count: {initial_billing} -> {current_billing})")
            else:
                feedback_parts.append("✓ Order entry detected")
        else:
            feedback_parts.append("✗ No new procedure order or billing entry detected")
            # This is mandatory - fail if no order
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + " | No procedure order was created.",
                "subscores": subscores
            }
        
        # ===== CRITERION 3: Correct Procedure - Chest X-Ray (20 points) =====
        chest_xray_found = validation.get('chest_xray_found', False)
        
        # Additional checks for chest x-ray
        proc_codes_raw = result.get('procedure_codes_raw', '').lower()
        billing_code = billing_order.get('code', '').lower()
        proc_clinical_hx = proc_order.get('clinical_hx', '').lower()
        proc_diagnosis = proc_order.get('diagnosis', '').lower()
        
        # Check for chest x-ray CPT codes
        for code in cpt_codes:
            if code in billing_code or code in proc_codes_raw:
                chest_xray_found = True
                break
        
        # Check for chest x-ray keywords in text
        xray_keywords = ['chest', 'x-ray', 'xray', 'radiograph', 'cxr', 'pa ', 'lateral']
        all_text = f"{proc_codes_raw} {proc_clinical_hx} {proc_diagnosis} {billing_code}"
        
        for keyword in xray_keywords:
            if keyword in all_text:
                chest_xray_found = True
                break
        
        if chest_xray_found:
            score += scoring_weights['correct_procedure']
            subscores['correct_procedure'] = True
            feedback_parts.append("✓ Chest X-Ray procedure identified")
        else:
            feedback_parts.append("✗ Chest X-Ray not clearly identified in order")
        
        # ===== CRITERION 4: Clinical Indication Documented (20 points) =====
        clinical_indication_found = validation.get('clinical_indication_found', False)
        
        # Additional checks for clinical indication
        clinical_text = f"{proc_clinical_hx} {proc_diagnosis} {billing_order.get('justify', '')}".lower()
        
        keywords_found = []
        for keyword in indication_keywords:
            if keyword.lower() in clinical_text:
                keywords_found.append(keyword)
                clinical_indication_found = True
        
        if clinical_indication_found:
            score += scoring_weights['clinical_indication']
            subscores['clinical_indication'] = True
            if keywords_found:
                feedback_parts.append(f"✓ Clinical indication documented (keywords: {', '.join(keywords_found[:3])})")
            else:
                feedback_parts.append("✓ Clinical indication documented")
        else:
            feedback_parts.append("✗ Clinical indication not documented (should mention pneumonia/cough/fever/dyspnea)")
        
        # ===== CRITERION 5: Order Created During Task (10 points) =====
        # Check timestamp if available
        order_date = proc_order.get('date', '')
        timestamp_valid = False
        
        if task_start > 0 and task_end > 0:
            # Check if any new entries were created
            if new_proc_order or new_billing:
                timestamp_valid = True
        
        # If we have a procedure order date, verify it's recent
        if order_date:
            from datetime import datetime, timedelta
            try:
                # Try to parse the date
                if 'T' in order_date:
                    order_dt = datetime.fromisoformat(order_date.replace('Z', '+00:00'))
                else:
                    order_dt = datetime.strptime(order_date.split()[0], '%Y-%m-%d')
                
                now = datetime.now()
                # Order should be from today
                if order_dt.date() == now.date():
                    timestamp_valid = True
                elif (now - order_dt).days <= 1:
                    timestamp_valid = True
            except Exception as e:
                logger.warning(f"Could not parse order date: {order_date}, error: {e}")
        
        if timestamp_valid:
            score += scoring_weights['timestamp_valid']
            subscores['timestamp_valid'] = True
            feedback_parts.append("✓ Order created during task session")
        else:
            feedback_parts.append("✗ Could not verify order was created during task")
        
        # ===== CRITERION 6: Order is Active/Pending (10 points) =====
        order_status = proc_order.get('status', '').lower()
        order_active = True  # Default to true unless explicitly cancelled
        
        if 'cancel' in order_status or 'void' in order_status:
            order_active = False
        
        if order_active:
            score += scoring_weights['order_active']
            subscores['order_active'] = True
            if order_status:
                feedback_parts.append(f"✓ Order is active (status: {order_status})")
            else:
                feedback_parts.append("✓ Order is active")
        else:
            feedback_parts.append(f"✗ Order was cancelled (status: {order_status})")
        
        # ===== DETERMINE PASS/FAIL =====
        # Must have order created (mandatory) and score >= 60
        passed = subscores['procedure_order_created'] and score >= 60
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        feedback += f" | Total score: {score}/100"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "details": {
                "patient_pid": patient_pid,
                "initial_proc_orders": initial_proc,
                "current_proc_orders": current_proc,
                "initial_billing": initial_billing,
                "current_billing": current_billing,
                "proc_order_found": proc_order.get('found', False),
                "billing_order_found": billing_order.get('found', False),
                "chest_xray_found": chest_xray_found,
                "clinical_indication_found": clinical_indication_found,
                "keywords_found": keywords_found if 'keywords_found' in dir() else []
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run correctly",
            "subscores": {
                "patient_identified": False,
                "procedure_order_created": False,
                "correct_procedure": False,
                "clinical_indication": False,
                "timestamp_valid": False,
                "order_active": False
            }
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {str(e)}",
            "subscores": {
                "patient_identified": False,
                "procedure_order_created": False,
                "correct_procedure": False,
                "clinical_indication": False,
                "timestamp_valid": False,
                "order_active": False
            }
        }
    except Exception as e:
        logger.error(f"Verification error: {str(e)}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}",
            "subscores": {
                "patient_identified": False,
                "procedure_order_created": False,
                "correct_procedure": False,
                "clinical_indication": False,
                "timestamp_valid": False,
                "order_active": False
            }
        }


if __name__ == "__main__":
    # Test mode - print verification function info
    print("Order Radiology Procedure Verifier")
    print("=" * 50)
    print("Expected patient: Ruben Bayer (pid=4)")
    print("Expected procedure: Chest X-Ray (CPT: 71045-71048)")
    print("Expected indication: Pneumonia evaluation")
    print("")
    print("Scoring:")
    print("  - Patient identified: 15 pts")
    print("  - Procedure order created: 25 pts")
    print("  - Correct procedure: 20 pts")
    print("  - Clinical indication: 20 pts")
    print("  - Timestamp valid: 10 pts")
    print("  - Order active: 10 pts")
    print("  - Total: 100 pts (pass >= 60 with order created)")