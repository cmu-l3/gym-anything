#!/usr/bin/env python3
import json
import base64
import csv
import io
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_custom_broker(traj, env_info, task_info):
    """
    Verifies that the agent configured a custom broker 'NeoTrade' correctly
    and used it to record a transaction with the calculated fee.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Metadata expectations
    meta = task_info.get('metadata', {})
    broker_name = meta.get('broker_name', 'NeoTrade')
    expected_rate = meta.get('expected_rate', 0.0015)
    expected_min = meta.get('expected_min', 5.0)
    stock_symbol = meta.get('stock_symbol', 'MSFT')
    stock_units = meta.get('stock_units', 10)
    stock_price = meta.get('stock_price', 250.0)
    expected_fee = meta.get('expected_fee', 5.0)

    # 1. Verify Configuration (40 pts)
    config_found = result.get('config_found', False)
    config_content_b64 = result.get('config_content_b64', '')
    config_mtime = result.get('config_mtime', 0)
    task_start = result.get('task_start', 0)

    if config_found and config_content_b64:
        try:
            config_xml = base64.b64decode(config_content_b64).decode('utf-8')
            # Check if NeoTrade is in the XML
            if broker_name in config_xml:
                score += 20
                feedback.append(f"Broker '{broker_name}' profile found in config.")
                
                # Check specifics (simple string check or parsing)
                # JStock XML structure varies, but we look for the values associated with the broker
                # Rate check (0.0015)
                if '0.0015' in config_xml or '0.15' in config_xml:
                    score += 10
                    feedback.append("Fee rate (0.15%) found in config.")
                else:
                    feedback.append("Fee rate 0.15% NOT found in config.")

                # Min fee check (5.0)
                if '5.0' in config_xml:
                    score += 10
                    feedback.append("Minimum fee ($5.00) found in config.")
                else:
                    feedback.append("Minimum fee $5.00 NOT found in config.")
                    
                # Timestamp check
                if config_mtime > task_start:
                    feedback.append("Configuration modified during task.")
                else:
                    feedback.append("WARNING: Configuration file timestamp is old (pre-task?).")
            else:
                feedback.append(f"Broker '{broker_name}' NOT found in the identified config file.")
        except Exception as e:
            feedback.append(f"Error parsing config: {str(e)}")
    else:
        feedback.append("No configuration file containing 'NeoTrade' was found.")

    # 2. Verify Transaction (Transaction Recorded: 20pts, Fee Logic: 20pts, Data Correct: 20pts)
    portfolio_exists = result.get('portfolio_exists', False)
    portfolio_content_b64 = result.get('portfolio_content_b64', '')
    
    transaction_found = False
    fee_correct = False
    details_correct = False

    if portfolio_exists and portfolio_content_b64:
        try:
            csv_content = base64.b64decode(portfolio_content_b64).decode('utf-8')
            f = io.StringIO(csv_content)
            reader = csv.DictReader(f)
            
            for row in reader:
                # JStock CSV columns: "Code","Symbol",...,"Units","Purchase Price",...,"Broker"
                # "Broker" column contains the fee amount
                code = row.get('Code', '')
                units = row.get('Units', '0')
                price = row.get('Purchase Price', '0')
                fee = row.get('Broker', '0') # This is the fee value
                
                if code == stock_symbol:
                    # Check units and price
                    try:
                        u = float(units)
                        p = float(price)
                        f_val = float(fee)
                        
                        if abs(u - stock_units) < 0.01 and abs(p - stock_price) < 0.01:
                            transaction_found = True
                            score += 20
                            feedback.append(f"Transaction found: {stock_symbol} {units} units @ {price}.")
                            
                            # Check fee
                            if abs(f_val - expected_fee) < 0.01:
                                fee_correct = True
                                score += 20
                                feedback.append(f"Fee correctly calculated as {fee} (matches expected minimum {expected_fee}).")
                            else:
                                feedback.append(f"Fee incorrect: got {fee}, expected {expected_fee}.")
                            
                            # Check details (implicit in finding the row, awarding points)
                            score += 20 
                            details_correct = True
                            break
                    except ValueError:
                        continue
            
            if not transaction_found:
                feedback.append(f"No transaction found for {stock_symbol} with {stock_units} units @ {stock_price}.")
                
        except Exception as e:
            feedback.append(f"Error parsing portfolio CSV: {str(e)}")
    else:
        feedback.append("Portfolio CSV not found or empty.")

    # Final logic
    passed = score >= 70 and transaction_found
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }