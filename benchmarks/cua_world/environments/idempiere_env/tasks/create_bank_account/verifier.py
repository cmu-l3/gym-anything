#!/usr/bin/env python3
import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_bank_account(traj, env_info, task_info):
    """
    Verify the creation of Bank and Bank Account records in iDempiere.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_bank_name = metadata.get("expected_bank_name", "Chase Bank NA")
    expected_routing = metadata.get("expected_routing", "021000021")
    expected_swift = metadata.get("expected_swift", "CHASUS33")
    expected_account_no = metadata.get("expected_account_no", "8877665544")
    expected_account_name = metadata.get("expected_account_name", "Chase Payroll Operating")
    expected_account_type = metadata.get("expected_account_type", "C") # C for Checking
    expected_currency = metadata.get("expected_currency", "USD")

    # Load result from container
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
    
    task_start = result.get("task_start", 0)
    bank_record = result.get("bank_record")
    account_record = result.get("account_record")

    # --- Verify Bank Record ---
    if bank_record:
        score += 20
        feedback_parts.append("Bank record found.")
        
        # Check Name
        if bank_record.get("name") == expected_bank_name:
            # Score included in existence check essentially, but good validation
            pass
        else:
            feedback_parts.append(f"Bank name mismatch: {bank_record.get('name')}")

        # Check Routing
        if bank_record.get("routingno") == expected_routing:
            score += 10
            feedback_parts.append("Routing Number correct.")
        else:
            feedback_parts.append(f"Routing No mismatch: got {bank_record.get('routingno')}")

        # Check Swift
        if bank_record.get("swiftcode") == expected_swift:
            score += 10
            feedback_parts.append("Swift Code correct.")
        else:
            feedback_parts.append(f"Swift Code mismatch: got {bank_record.get('swiftcode')}")
            
        # Check Timestamp (Anti-gaming)
        created_epoch = bank_record.get("created_epoch", 0)
        if created_epoch > task_start:
            # Points for creating it NOW, not using old data
            score += 5
            feedback_parts.append("Bank created during task.")
        else:
            feedback_parts.append("Bank record seems pre-existing.")

        # Check Address City (Optional/Bonus)
        city_found = result.get("address_city", "")
        if "New York" in city_found:
             feedback_parts.append("Address city verified.")
             # No specific points allocated in rubric but confirms quality
    else:
        feedback_parts.append("Bank record NOT found.")

    # --- Verify Bank Account Record ---
    if account_record:
        score += 20
        feedback_parts.append("Bank Account record found.")

        # Check Account No
        if account_record.get("accountno") == expected_account_no:
            score += 10
            feedback_parts.append("Account Number correct.")
        else:
             feedback_parts.append(f"Account No mismatch: {account_record.get('accountno')}")

        # Check Name
        if account_record.get("name") == expected_account_name:
            score += 10
            feedback_parts.append("Account Name correct.")
        else:
            feedback_parts.append(f"Account Name mismatch: {account_record.get('name')}")
            
        # Check Type
        # iDempiere usually stores 'C' for Checking, 'S' for Savings. 
        # The agent selects "Checking" in UI, DB stores 'C'.
        acct_type = account_record.get("bankaccounttype", "")
        if acct_type == expected_account_type:
            score += 10
            feedback_parts.append("Account Type correct.")
        else:
            feedback_parts.append(f"Account Type mismatch: got '{acct_type}'")

        # Check Currency
        curr = account_record.get("currency_iso", "")
        if curr == expected_currency:
            score += 10
            feedback_parts.append("Currency correct.")
        else:
             feedback_parts.append(f"Currency mismatch: got {curr}")
             
        # Check Parent Link
        if account_record.get("bank_name") == expected_bank_name:
             score += 5 # Bonus for correct linking
             feedback_parts.append("Account correctly linked to Bank.")
        else:
             feedback_parts.append("Account not linked to correct Bank.")

    else:
        feedback_parts.append("Bank Account record NOT found.")

    # Cap score at 100
    score = min(score, 100)
    
    # Pass threshold: Need at least the records to exist (40) plus some correctness details
    passed = (score >= 70) and (bank_record is not None) and (account_record is not None)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }