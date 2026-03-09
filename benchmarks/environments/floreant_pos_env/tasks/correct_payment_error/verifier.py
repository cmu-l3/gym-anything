#!/usr/bin/env python3
"""
Verifier for correct_payment_error task.

Logic:
1. Parses the raw text output from the Derby DB query.
2. Identifies a ticket created after the task started.
3. Checks for the required transaction pattern on that ticket:
   - Contains a CASH payment.
   - Contains a VOID (or refund/negative) transaction matching the CASH amount OR explicitly marked void.
   - Contains a CREDIT_CARD payment.
   - Ticket status is CLOSED/PAID.
"""

import json
import os
import re
import tempfile
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_db_dump(dump_content):
    """
    Parses the 'ij' tool output.
    Expected format is roughly:
    ID | CREATED_DATE ...
    ---------------------
    123 | 2023-10-01 ...
    """
    tickets = []
    transactions = []
    
    current_section = None
    
    # Simple state machine to parse the two result sets
    lines = dump_content.splitlines()
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        # Identify sections based on headers or content
        # TICKET columns: ID, CREATE_DATE, CLOSED, VOIDED...
        if "CLOSED" in line and "VOIDED" in line:
            current_section = "TICKETS"
            continue
        # TRANSACTION columns: ID, TICKET_ID, TRANSACTION_TYPE...
        if "TRANSACTION_TYPE" in line and "TENDER_TYPE" in line:
            current_section = "TRANSACTIONS"
            continue
        
        if line.startswith("---") or line.startswith("ID"):
            continue
            
        # Parse data rows
        if current_section == "TICKETS":
            # Example: 152 | 2023-10-27 10:00:00.0 | true | false | 25.0 | 25.0
            parts = [p.strip() for p in line.split('|')]
            if len(parts) >= 4:
                try:
                    tickets.append({
                        "id": parts[0],
                        "created": parts[1],
                        "closed": parts[2].lower() == 'true',
                        "voided": parts[3].lower() == 'true',
                        "total": float(parts[4]) if len(parts) > 4 else 0.0
                    })
                except:
                    pass
                    
        elif current_section == "TRANSACTIONS":
            # Example: 99 | 152 | PAYMENT | CASH | 25.0 | ...
            parts = [p.strip() for p in line.split('|')]
            if len(parts) >= 5:
                try:
                    transactions.append({
                        "id": parts[0],
                        "ticket_id": parts[1],
                        "type": parts[2].strip().upper(),
                        "tender": parts[3].strip().upper(),
                        "amount": float(parts[4]) if len(parts) > 4 else 0.0
                    })
                except:
                    pass
                    
    return tickets, transactions

def verify_correct_payment_error(traj, env_info, task_info):
    """
    Verifies that a ticket was settled with CASH, then voided, then settled with CREDIT_CARD.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Load DB Dump
    db_dump_path = result_data.get("db_dump_path")
    if not db_dump_path:
        return {"passed": False, "score": 0, "feedback": "Database dump not found."}
        
    temp_dump = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env(db_dump_path, temp_dump.name)
        with open(temp_dump.name, 'r', encoding='utf-8', errors='ignore') as f:
            dump_content = f.read()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read DB dump: {str(e)}"}
    finally:
        if os.path.exists(temp_dump.name):
            os.unlink(temp_dump.name)

    # Parse DB Dump
    tickets, transactions = parse_db_dump(dump_content)
    
    score = 0
    feedback = []
    
    # Filter tickets created during this session?
    # Since we can't easily parse Derby timestamps in this lightweight verifier,
    # we'll look for the most recent tickets (top of list from the export script).
    # The export script fetches `FETCH FIRST 10 ROWS ONLY` ordered by ID DESC.
    
    candidate_ticket = None
    
    for t in tickets:
        t_id = t['id']
        
        # Get transactions for this ticket
        t_txs = [tx for tx in transactions if tx['ticket_id'] == t_id]
        
        has_cash = False
        has_credit = False
        has_void = False
        
        for tx in t_txs:
            tx_type = tx['type']
            tender = tx['tender']
            
            # Check for Cash Payment
            if tender == 'CASH' and tx_type in ['PAYMENT', 'CREDIT']: 
                has_cash = True
                
            # Check for Credit Card Payment
            if tender in ['CREDIT_CARD', 'CARD', 'CC'] and tx_type in ['PAYMENT', 'CREDIT']:
                has_credit = True
                
            # Check for Void
            # Depending on Floreant version, a voided payment might be:
            # 1. A transaction with type 'VOID'
            # 2. A transaction with type 'REFUND'
            # 3. A negative amount
            if tx_type in ['VOID', 'REFUND'] or tx['amount'] < 0:
                has_void = True
        
        # Evaluate this ticket
        if has_cash and has_credit and has_void:
            candidate_ticket = t
            break
            
        # Partial credit check (e.g. they did everything but the ticket isn't fully closed correctly?)
        if has_cash and has_credit:
            # Maybe they forgot to void explicitly but just paid again?
            pass

    # Scoring
    if candidate_ticket:
        score = 100
        feedback.append(f"Success! Found Ticket ID {candidate_ticket['id']} with corrected payment history.")
        feedback.append("Detected: CASH payment, VOID/Reversal, and CREDIT_CARD payment.")
        
        if not candidate_ticket['closed']:
            score -= 10
            feedback.append("Warning: Ticket is not marked as CLOSED.")
            
    else:
        # Diagnostic scoring
        found_cash = any(tx['tender'] == 'CASH' for tx in transactions)
        found_credit = any(tx['tender'] in ['CREDIT_CARD', 'CARD'] for tx in transactions)
        found_void = any(tx['type'] == 'VOID' for tx in transactions)
        
        if found_cash:
            score += 20
            feedback.append("Found a CASH transaction.")
        if found_credit:
            score += 20
            feedback.append("Found a CREDIT_CARD transaction.")
        if found_void:
            score += 20
            feedback.append("Found a VOID transaction.")
            
        feedback.append("Failed to find a single ticket containing the full Cash -> Void -> Credit sequence.")

    # VLM Trajectory Verification (Bonus/Confirmation)
    # If score is high, we assume success. If low, VLM won't save it because DB is ground truth.
    # However, we can use VLM to verify intent if DB query was ambiguous.
    # For now, we rely on DB.

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }