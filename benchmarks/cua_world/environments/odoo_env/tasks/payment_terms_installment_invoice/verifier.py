#!/usr/bin/env python3
import json
import logging
import os
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_payment_terms_installment_invoice(traj, env_info, task_info):
    """
    Verifies that the user created the correct 3-installment payment term
    and applied it to a posted invoice for Pinnacle Industries.
    """
    
    # 1. Retrieve Result Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy failed"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Odoo connection error: {result['error']}"}

    score = 0
    feedback = []
    
    # --- Criteria 1: Payment Term Configuration (40 pts) ---
    terms = result.get('payment_terms_found', [])
    correct_term = None
    
    # Look for the specific term configuration
    for term in terms:
        name = term.get('name', '')
        lines = term.get('lines', [])
        
        # Check name loose match
        if "3-Installment" in name:
            
            # Check lines
            # Expecting: 30% (0 days), 40% (30 days), Balance (60 days)
            # Odoo lines: value='percent', value_amount=30.0
            
            has_30_immediate = False
            has_40_30days = False
            has_bal_60days = False
            
            for line in lines:
                val_type = line.get('value')
                amount = float(line.get('value_amount', 0.0))
                days = int(line.get('days', 0))
                
                if val_type == 'percent' and abs(amount - 30.0) < 0.1 and days == 0:
                    has_30_immediate = True
                elif val_type == 'percent' and abs(amount - 40.0) < 0.1 and days == 30:
                    has_40_30days = True
                elif val_type == 'balance' and days == 60:
                    has_bal_60days = True
            
            if has_30_immediate and has_40_30days and has_bal_60days:
                correct_term = term
                break
    
    if correct_term:
        score += 40
        feedback.append("Payment Term '3-Installment (30/40/30)' created correctly.")
    elif any("3-Installment" in t.get('name', '') for t in terms):
        score += 20
        feedback.append("Payment Term created but lines configuration is incorrect.")
    else:
        feedback.append("Payment Term not found.")

    # --- Criteria 2: Invoice Created (15 pts) ---
    invoice = result.get('invoice_found')
    if invoice:
        score += 15
        feedback.append("Invoice for Pinnacle Industries created.")
        
        # --- Criteria 3: Invoice Posted & Term Applied (15 pts) ---
        state = invoice.get('state')
        term_id = invoice.get('invoice_payment_term_id') # returns [id, name] or False
        
        # Check if term matches
        term_match = False
        if term_id and isinstance(term_id, list) and correct_term:
            if term_id[0] == correct_term['id']:
                term_match = True
        
        if state == 'posted':
            score += 10
            feedback.append("Invoice is posted.")
        else:
            feedback.append(f"Invoice state is '{state}' (expected 'posted').")
            
        if term_match:
            score += 5
            feedback.append("Correct Payment Term applied to invoice.")
        else:
            feedback.append("Incorrect or default payment term on invoice.")
            
        # --- Criteria 4: Receivable Schedule / Journal Items (30 pts) ---
        # Total expected: 12500. Splits: 3750, 5000, 3750.
        receivables = result.get('receivables_lines', [])
        
        # Filter for credits or debits matching total (receivable is usually debit for customer invoice)
        total_rec = sum(l.get('debit', 0) for l in receivables)
        
        if abs(total_rec - 12500.0) < 1.0:
            feedback.append("Invoice total is correct ($12,500).")
            
            # Check individual splits
            amounts = sorted([float(l.get('debit', 0)) for l in receivables])
            expected_amounts = sorted([3750.0, 5000.0, 3750.0])
            
            # Allow slight rounding diffs
            amounts_match = True
            if len(amounts) != 3:
                amounts_match = False
            else:
                for a, e in zip(amounts, expected_amounts):
                    if abs(a - e) > 1.0:
                        amounts_match = False
            
            if amounts_match:
                score += 30
                feedback.append("Receivable installment splits are correct.")
            else:
                score += 10 # Partial credit for correct total but wrong split
                feedback.append(f"Receivable splits incorrect. Found: {amounts}, Expected: {expected_amounts}")
        else:
            feedback.append(f"Invoice total incorrect. Found: {total_rec}, Expected: 12500.0")
            
    else:
        feedback.append("Invoice not found.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }