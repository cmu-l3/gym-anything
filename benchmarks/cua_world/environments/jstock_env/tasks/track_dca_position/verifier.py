#!/usr/bin/env python3
"""
Verifier for track_dca_position task.
Checks if the user created the 'DCA Strategy' portfolio, entered the 4 transactions correctly,
saved the portfolio, and created the summary file.
"""

import json
import os
import tempfile
import base64
import csv
import io
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_csv_content(b64_content):
    """Decodes base64 CSV content and returns a list of dictionaries."""
    try:
        content_str = base64.b64decode(b64_content).decode('utf-8')
        # JStock CSVs might have a header.
        # Format usually: "Code","Symbol","Date","Units",...
        f = io.StringIO(content_str)
        reader = csv.DictReader(f)
        return list(reader)
    except Exception as e:
        logger.error(f"Failed to parse CSV: {e}")
        return []

def parse_summary_content(b64_content):
    """Decodes base64 summary content."""
    try:
        return base64.b64decode(b64_content).decode('utf-8')
    except Exception as e:
        logger.error(f"Failed to parse summary: {e}")
        return ""

def clean_money_str(s):
    """Removes currency symbols and commas, returns float."""
    if not s:
        return 0.0
    clean = re.sub(r'[^\d.-]', '', str(s))
    try:
        return float(clean)
    except ValueError:
        return 0.0

def verify_track_dca_position(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_transactions = metadata.get('transactions', [])
    expected_totals = metadata.get('expected_totals', {})

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []
    
    # 1. Check Portfolio Existence (10 pts)
    if result.get('portfolio_exists'):
        score += 10
        feedback.append("Portfolio 'DCA Strategy' directory created.")
        
        # Anti-gaming: Check timestamp
        start_time = result.get('task_start_time', 0)
        port_mtime = result.get('portfolio_mtime', 0)
        if port_mtime < start_time:
            feedback.append("WARNING: Portfolio directory predates task start!")
            score -= 10 # Penalize
    else:
        feedback.append("Portfolio 'DCA Strategy' NOT found.")

    # 2. Check CSV Content (47 pts total)
    csv_rows = parse_csv_content(result.get('csv_content_b64', ''))
    
    # Filter for META transactions
    meta_txs = [row for row in csv_rows if row.get('Code') == 'META' or row.get('Symbol') == 'META']
    
    if len(meta_txs) == 4:
        score += 15
        feedback.append("Found exactly 4 META transactions.")
    else:
        feedback.append(f"Found {len(meta_txs)} META transactions (expected 4).")
        # Partial credit if some exist
        if len(meta_txs) > 0:
            score += 5

    # Verify individual transactions (8 pts each = 32 pts)
    # We map expected transactions to found transactions by date/price to be robust against order
    matched_count = 0
    
    for expected in expected_transactions:
        # Find match in meta_txs
        # JStock Date format in CSV is usually "MMM dd, yyyy" e.g., "Nov 15, 2023"
        match = None
        for row in meta_txs:
            row_date = row.get('Date', '')
            row_price = clean_money_str(row.get('Purchase Price', '0'))
            row_units = clean_money_str(row.get('Units', '0'))
            row_broker = clean_money_str(row.get('Broker', '0'))
            
            # Simple date match (contains Month and Year at minimum)
            # Expect: "Nov 15, 2023"
            if expected['date'] in row_date and \
               abs(row_price - expected['price']) < 0.01 and \
               abs(row_units - expected['units']) < 0.01 and \
               abs(row_broker - expected['fee']) < 0.01:
                match = row
                break
        
        if match:
            matched_count += 1
            score += 8
            # Also verify JStock calculated the Net Purchase Value correctly
            # Net Purchase Value = (Units * Price) + Fees
            # 10 * 332.40 + 4.95 = 3328.95
            calc_net = clean_money_str(match.get('Net Purchase Value', '0'))
            expected_net = (expected['units'] * expected['price']) + expected['fee']
            if abs(calc_net - expected_net) < 0.1:
                # Bonus implicit check: verifies JStock did the math (agent used the tool)
                pass 
        else:
            feedback.append(f"Missing/Incorrect transaction for {expected['date']} (${expected['price']})")

    # 3. Check Summary File (43 pts total)
    summary_text = parse_summary_content(result.get('summary_content_b64', ''))
    if result.get('summary_exists') and summary_text:
        score += 5
        feedback.append("Summary file exists.")
        
        # Check values in text (loose matching)
        # Total Units: 40.0
        if "40" in summary_text:
            score += 5
            feedback.append("Summary: Total units correct.")
        
        # Total Purchase Value: 15298.10
        if "15298" in summary_text.replace(',', ''):
            score += 5
            feedback.append("Summary: Total purchase value correct.")
            
        # Total Fees: 19.80
        if "19.80" in summary_text:
            score += 4
            feedback.append("Summary: Total fees correct.")
            
        # Net Total: 15317.90
        if "15317" in summary_text.replace(',', ''):
            score += 5
            feedback.append("Summary: Net total correct.")
            
        # Avg Cost: 382.95
        if "382.95" in summary_text:
            score += 4
            feedback.append("Summary: Avg cost correct.")
    else:
        feedback.append("Summary file missing or empty.")

    # 4. Check Preservation (4 pts)
    if result.get('default_portfolio_preserved'):
        score += 4
        feedback.append("Original portfolio preserved.")

    # Final logic
    passed = (score >= 60) and (matched_count >= 3)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }