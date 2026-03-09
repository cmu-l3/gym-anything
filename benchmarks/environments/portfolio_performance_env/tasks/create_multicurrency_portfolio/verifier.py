#!/usr/bin/env python3
"""
Verifier for create_multicurrency_portfolio task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_multicurrency_portfolio(traj, env_info, task_info):
    """
    Verify the creation of a multi-currency portfolio.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_securities = metadata.get('securities', [])
    expected_deposits = metadata.get('deposits', [])
    expected_buys = metadata.get('buys', [])

    # Get result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Validity (12 points)
    if result.get("file_exists"):
        score += 6
        if result.get("file_modified_during_task"):
            score += 6
            feedback_parts.append("File created correctly.")
        else:
            feedback_parts.append("File exists but was not created during task time.")
    else:
        return {"passed": False, "score": 0, "feedback": "Portfolio file not found at expected path."}

    if "error" in result:
        return {"passed": False, "score": score, "feedback": f"Invalid XML file: {result['error']}"}

    # 2. Base Currency (5 points)
    if result.get("base_currency") == "EUR":
        score += 5
        feedback_parts.append("Base currency is EUR.")
    else:
        feedback_parts.append(f"Incorrect base currency: {result.get('base_currency')}.")

    # 3. Accounts Structure (14 points)
    accounts = result.get("accounts", [])
    has_eur_acc = any("EUR" in a.get("name", "").upper() and a.get("currency") == "EUR" for a in accounts)
    has_usd_acc = any("USD" in a.get("name", "").upper() and a.get("currency") == "USD" for a in accounts)
    
    if has_eur_acc: score += 7
    if has_usd_acc: score += 7
    
    if has_eur_acc and has_usd_acc:
        feedback_parts.append("Cash accounts created correctly.")
    else:
        feedback_parts.append("Missing or incorrect cash accounts.")

    # 4. Portfolios Structure (10 points)
    portfolios = result.get("portfolios", [])
    has_eur_port = any("EUR" in p.get("name", "").upper() for p in portfolios)
    has_usd_port = any("USD" in p.get("name", "").upper() for p in portfolios)
    
    if has_eur_port: score += 5
    if has_usd_port: score += 5

    # 5. Securities (14 points)
    securities = result.get("securities", [])
    found_isins = [s.get("isin") for s in securities]
    
    # Check Allianz (EUR)
    allianz = next((s for s in securities if s.get("isin") == "DE0008404005"), None)
    if allianz:
        if allianz.get("currency") == "EUR":
            score += 7
            feedback_parts.append("Allianz SE security correct.")
        else:
            score += 3
            feedback_parts.append("Allianz SE found but wrong currency.")
    else:
        feedback_parts.append("Allianz SE not found.")

    # Check Apple (USD)
    apple = next((s for s in securities if s.get("isin") == "US0378331005"), None)
    if apple:
        if apple.get("currency") == "USD":
            score += 7
            feedback_parts.append("Apple Inc security correct.")
        else:
            score += 3
            feedback_parts.append("Apple Inc found but wrong currency.")
    else:
        feedback_parts.append("Apple Inc not found.")

    # 6. Deposit Transactions (14 points)
    deposits = result.get("deposit_txns", [])
    
    # Check EUR Deposit
    eur_dep = next((d for d in deposits if d.get("amount") == 10000.0 and d.get("currency") == "EUR"), None)
    if eur_dep:
        score += 7
        feedback_parts.append("EUR deposit recorded.")
    else:
        feedback_parts.append("EUR deposit missing or incorrect amount.")

    # Check USD Deposit
    usd_dep = next((d for d in deposits if d.get("amount") == 10000.0 and d.get("currency") == "USD"), None)
    if usd_dep:
        score += 7
        feedback_parts.append("USD deposit recorded.")
    else:
        feedback_parts.append("USD deposit missing or incorrect amount.")

    # 7. Buy Transactions (31 points)
    buys = result.get("buy_txns", [])
    
    # Allianz Buy: 20 shares, ~4850 EUR
    # Note: shares_raw from XML might be scaled. 20 shares usually comes out as 2000000000 or similar
    # We check rough amount and ISIN primarily
    allianz_buy = next((b for b in buys if b.get("isin") == "DE0008404005"), None)
    
    if allianz_buy:
        # Check Amount: 20 * 242.50 = 4850.00
        amount = allianz_buy.get("amount", 0)
        fees = allianz_buy.get("fees", 0)
        
        # Total debit usually includes fees, but XML stores gross amount and fees separately often
        # Gross amount check
        if 4800 <= amount <= 4900: 
            score += 10
            feedback_parts.append("Allianz buy amount correct.")
        else:
            feedback_parts.append(f"Allianz buy amount {amount} out of range.")
            
        if 9.0 <= fees <= 11.0:
            score += 5
            feedback_parts.append("Allianz fees correct.")
            
        # Check Date
        if "2024-01-15" in allianz_buy.get("date", ""):
            score += 1  # Bonus check
            
    else:
        feedback_parts.append("Allianz buy transaction not found.")

    # Apple Buy: 25 shares, ~4625 USD
    apple_buy = next((b for b in buys if b.get("isin") == "US0378331005"), None)
    
    if apple_buy:
        # Check Amount: 25 * 185.00 = 4625.00
        amount = apple_buy.get("amount", 0)
        fees = apple_buy.get("fees", 0)
        
        if 4600 <= amount <= 4700:
            score += 10
            feedback_parts.append("Apple buy amount correct.")
        else:
             feedback_parts.append(f"Apple buy amount {amount} out of range.")
             
        if 4.0 <= fees <= 6.0:
            score += 5
            feedback_parts.append("Apple fees correct.")
            
        # Check Date
        if "2024-01-15" in apple_buy.get("date", ""):
            score += 1 # Bonus check
            
    else:
        feedback_parts.append("Apple buy transaction not found.")

    # Final tally
    passed = score >= 60 and result.get("file_modified_during_task")
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " ".join(feedback_parts)
    }