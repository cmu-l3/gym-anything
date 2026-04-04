#!/usr/bin/env python3
"""
Verifier for sequence_invoice_system task.
"""

import json
import tempfile
import os
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_sequence_invoice_system(traj, env_info, task_info):
    """
    Verifies the creation of sequences, class, index, and data insertion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Extract data
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    seq1_val = result.get('seq1_val', 'NOTFOUND')
    seq2_val = result.get('seq2_val', 'NOTFOUND')
    schema = result.get('schema', {})
    records = result.get('records', [])
    record_count = result.get('record_count', 0)
    initial_count = result.get('initial_count', 0)

    # --- Anti-gaming: Time Elapsed (5 pts) ---
    elapsed = task_end - task_start
    if elapsed >= 10:
        score += 5
        feedback_parts.append(f"Time elapsed OK ({elapsed}s)")
    else:
        feedback_parts.append(f"Task completed too quickly ({elapsed}s)")

    # --- Check 1: invoiceIdSeq exists (10 pts) ---
    if seq1_val != "NOTFOUND":
        score += 10
        feedback_parts.append("invoiceIdSeq exists")
        # --- Check 2: invoiceIdSeq value (5 pts) ---
        # Should be 1004 (or 1004.0) after 5 inserts starting at 1000
        try:
            val = float(seq1_val)
            if val == 1004.0:
                score += 5
                feedback_parts.append("invoiceIdSeq current value correct (1004)")
            else:
                feedback_parts.append(f"invoiceIdSeq value incorrect: {val} (expected 1004)")
        except ValueError:
            feedback_parts.append("invoiceIdSeq value invalid")
    else:
        feedback_parts.append("invoiceIdSeq MISSING")

    # --- Check 3: receiptSeq exists (10 pts) ---
    if seq2_val != "NOTFOUND":
        score += 10
        feedback_parts.append("receiptSeq exists")
    else:
        feedback_parts.append("receiptSeq MISSING")

    # --- Check 4: Invoices class exists (8 pts) ---
    invoices_class = None
    classes = schema.get('classes', [])
    for cls in classes:
        if cls.get('name') == 'Invoices':
            invoices_class = cls
            break
    
    if invoices_class:
        score += 8
        feedback_parts.append("Invoices class exists")
        
        # --- Check 5: Properties (7 pts) ---
        props = {p.get('name') for p in invoices_class.get('properties', [])}
        required_props = {'InvoiceId', 'CustomerEmail', 'Amount', 'Currency', 'IssuedDate', 'Description', 'Status'}
        missing = required_props - props
        
        if not missing:
            score += 7
            feedback_parts.append("All properties present")
        else:
            partial = max(0, 7 - len(missing))
            score += partial
            feedback_parts.append(f"Missing properties: {', '.join(missing)}")
            
        # --- Check 9: UNIQUE Index on InvoiceId (10 pts) ---
        # Indexes can be on the class or in the global indexes list
        index_found = False
        is_unique = False
        
        # Check class-level index definitions
        for idx in invoices_class.get('indexes', []):
            fields = idx.get('fields', [])
            if 'InvoiceId' in fields:
                index_found = True
                if idx.get('type', '').upper() == 'UNIQUE':
                    is_unique = True
                break
        
        if index_found and is_unique:
            score += 10
            feedback_parts.append("UNIQUE Index on InvoiceId found")
        elif index_found:
            score += 5
            feedback_parts.append("Index on InvoiceId found but NOT UNIQUE")
        else:
            feedback_parts.append("Index on InvoiceId MISSING")

    else:
        feedback_parts.append("Invoices class MISSING")

    # --- Check 6: Record Count (10 pts) ---
    if record_count == 5:
        score += 10
        feedback_parts.append("Correct number of records (5)")
    elif record_count > 0:
        score += 3
        feedback_parts.append(f"Incorrect record count: {record_count} (expected 5)")
    else:
        feedback_parts.append("No records found")

    # --- Check 7 & 8: Data Correctness & Sequential IDs (20 pts) ---
    # Expected data
    expected_data = [
        (1000, 'john.smith@example.com', 450.0, 'EUR', 'paid'),
        (1001, 'maria.garcia@example.com', 1250.0, 'EUR', 'paid'),
        (1002, 'david.jones@example.com', 875.5, 'GBP', 'pending'),
        (1003, 'sophie.martin@example.com', 2100.0, 'USD', 'paid'),
        (1004, 'luca.rossi@example.com', 580.0, 'EUR', 'overdue'),
    ]
    
    correct_records = 0
    sequential_ids = True
    ids_found = []

    for i, rec in enumerate(records):
        try:
            iid = int(rec.get('InvoiceId', -1))
            ids_found.append(iid)
            
            if i < len(expected_data):
                exp = expected_data[i]
                
                # Check fields
                match = True
                if iid != exp[0]: match = False
                if rec.get('CustomerEmail') != exp[1]: match = False
                if abs(float(rec.get('Amount', 0)) - exp[2]) > 0.1: match = False
                if rec.get('Currency') != exp[3]: match = False
                if rec.get('Status') != exp[4]: match = False
                
                if match:
                    correct_records += 1
        except Exception:
            sequential_ids = False

    # Check IDs are exactly 1000, 1001, 1002, 1003, 1004
    if ids_found != [1000, 1001, 1002, 1003, 1004]:
        sequential_ids = False

    # Award points for correct records (2 pts each -> 10 pts max)
    score += (correct_records * 2)
    feedback_parts.append(f"Correct records: {correct_records}/5")

    # Award points for sequential IDs (10 pts)
    if sequential_ids and len(ids_found) == 5:
        score += 10
        feedback_parts.append("IDs are sequential (1000-1004)")
    else:
        feedback_parts.append(f"IDs not sequential or incorrect: {ids_found}")

    # --- Anti-gaming: New records created (5 pts) ---
    if record_count > initial_count:
        score += 5
        feedback_parts.append("New records confirmed")
    else:
        feedback_parts.append("No new records created")

    # Check 10: Descriptions (10 pts)
    # Simple check if description contains key words
    desc_correct = 0
    desc_keywords = {
        1000: 'Artemide',
        1001: 'Crillon',
        1002: 'Savoy',
        1003: 'Plaza',
        1004: 'Artemide'
    }
    for rec in records:
        try:
            iid = int(rec.get('InvoiceId', -1))
            desc = rec.get('Description', '')
            if iid in desc_keywords and desc_keywords[iid] in desc:
                desc_correct += 1
        except: pass
    
    score += (desc_correct * 2)
    feedback_parts.append(f"Descriptions correct: {desc_correct}/5")

    passed = (score >= 60 and invoices_class is not None and record_count >= 3)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }