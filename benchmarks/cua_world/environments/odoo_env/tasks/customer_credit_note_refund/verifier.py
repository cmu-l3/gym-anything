#!/usr/bin/env python3
import json
import os
import tempfile

def verify_customer_credit_note_refund(traj, env_info, task_info):
    """
    Verifies that a credit note was correctly created, amounts adjusted, posted, and paid.
    """
    # 1. Retrieve result data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment access failed"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check for errors in export
    if result.get('error'):
        return {"passed": False, "score": 0, "feedback": f"Setup/Export error: {result['error']}"}

    score = 0
    feedback = []
    
    # 3. Verify Credit Note Existence
    if not result.get('credit_note_found') or not result.get('credit_note'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No credit note found for Northstar Industrial Solutions created during this session."
        }
    
    cn = result['credit_note']
    score += 10
    feedback.append("Credit note created.")

    # 4. Verify Total Amount (Should be 744.00)
    # Expected: (8 * 45) + (12 * 32) = 360 + 384 = 744
    expected_total = 744.00
    actual_total = cn.get('amount_total', 0.0)
    
    if abs(actual_total - expected_total) < 1.0:
        score += 25
        feedback.append(f"Correct refund amount: ${actual_total:.2f}.")
    else:
        feedback.append(f"Incorrect refund amount: ${actual_total:.2f} (Expected ${expected_total:.2f}).")
        # Check if they did a full refund (1860)
        if abs(actual_total - 1860.00) < 1.0:
            feedback.append("It appears a full refund was issued instead of a partial one.")

    # 5. Verify Line Items (Quantity Check)
    # We look for specific quantities for the products
    lines = cn.get('lines', [])
    helmet_ok = False
    vest_ok = False
    
    for line in lines:
        name = line.get('product_name', '')
        qty = line.get('quantity', 0)
        
        if 'Helmet' in name:
            if abs(qty - 8) < 0.1:
                helmet_ok = True
            else:
                feedback.append(f"Helmet quantity incorrect: {qty} (Expected 8).")
        elif 'Vest' in name:
            if abs(qty - 12) < 0.1:
                vest_ok = True
            else:
                feedback.append(f"Vest quantity incorrect: {qty} (Expected 12).")

    if helmet_ok: score += 10
    if vest_ok: score += 10

    # 6. Verify Status (Posted)
    state = cn.get('state', '')
    if state == 'posted':
        score += 20
        feedback.append("Credit note is posted.")
    else:
        feedback.append(f"Credit note is in '{state}' state (should be 'posted').")

    # 7. Verify Payment (Paid/In Payment)
    pay_state = cn.get('payment_state', '')
    if pay_state in ['paid', 'in_payment']:
        score += 25
        feedback.append("Refund payment registered.")
    else:
        feedback.append(f"Payment not registered (Status: {pay_state}).")

    # 8. Final Assessment
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }