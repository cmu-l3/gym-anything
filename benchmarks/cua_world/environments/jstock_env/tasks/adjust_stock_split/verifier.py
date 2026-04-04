#!/usr/bin/env python3
import json
import os
import csv
import logging
import tempfile
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_adjust_stock_split(traj, env_info, task_info):
    """
    Verifies that the AAPL buy transaction was correctly adjusted for a 2-for-1 split.
    
    Criteria:
    1. AAPL Units doubled (100 -> 200).
    2. AAPL Price halved (185.2 -> 92.6).
    3. AAPL Total Value preserved (~18520).
    4. MSFT and NVDA rows remain unchanged.
    5. File was modified during task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Define targets
    EXPECTED_AAPL = metadata.get('expected_aapl', {'units': 200.0, 'price': 92.60, 'value': 18520.0})
    EXPECTED_MSFT = metadata.get('expected_msft', {'units': 50.0, 'price': 374.5, 'value': 18725.0})
    EXPECTED_NVDA = metadata.get('expected_nvda', {'units': 25.0, 'price': 615.3, 'value': 15382.5})
    
    # 1. Retrieve Result Metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_meta.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Portfolio file was deleted or not found."}

    # 2. Retrieve Portfolio CSV
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(result_meta.get('csv_export_path', '/tmp/buyportfolio_export.csv'), temp_csv.name)
        
        # Parse CSV
        transactions = {}
        with open(temp_csv.name, 'r', newline='') as csvfile:
            # JStock CSVs often have quoted fields
            reader = csv.DictReader(csvfile)
            for row in reader:
                code = row.get('Code', '').strip()
                if code:
                    transactions[code] = row
                    
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse portfolio CSV: {str(e)}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # 3. Verify Data
    score = 0
    feedback_parts = []
    
    # --- Check Modification Time (10 pts) ---
    if result_meta.get('file_modified_during_task'):
        score += 10
        feedback_parts.append("File modified successfully.")
    else:
        feedback_parts.append("Warning: File timestamp indicates no save occurred.")

    # --- Check AAPL (50 pts total) ---
    aapl = transactions.get('AAPL')
    if not aapl:
        feedback_parts.append("FAIL: AAPL transaction missing.")
    else:
        try:
            units = float(aapl.get('Units', 0))
            price = float(aapl.get('Purchase Price', 0))
            value = float(aapl.get('Purchase Value', 0))
            
            # Check Units (20 pts)
            if math.isclose(units, EXPECTED_AAPL['units'], abs_tol=0.1):
                score += 20
                feedback_parts.append("AAPL Units correct (200).")
            else:
                feedback_parts.append(f"FAIL: AAPL Units {units} != 200.")

            # Check Price (20 pts)
            if math.isclose(price, EXPECTED_AAPL['price'], abs_tol=0.01):
                score += 20
                feedback_parts.append("AAPL Price correct (92.60).")
            else:
                feedback_parts.append(f"FAIL: AAPL Price {price} != 92.60.")

            # Check Value Consistency (10 pts)
            if math.isclose(value, EXPECTED_AAPL['value'], abs_tol=1.0):
                score += 10
                feedback_parts.append("AAPL Total Value preserved.")
            else:
                feedback_parts.append(f"FAIL: AAPL Value {value} != {EXPECTED_AAPL['value']}.")
                
        except ValueError:
            feedback_parts.append("FAIL: Invalid numeric data in AAPL row.")

    # --- Check MSFT Integrity (20 pts) ---
    msft = transactions.get('MSFT')
    if msft:
        try:
            m_units = float(msft.get('Units', 0))
            m_price = float(msft.get('Purchase Price', 0))
            if math.isclose(m_units, EXPECTED_MSFT['units']) and math.isclose(m_price, EXPECTED_MSFT['price']):
                score += 20
                feedback_parts.append("MSFT row unchanged (Correct).")
            else:
                feedback_parts.append("FAIL: MSFT data modified incorrectly.")
        except:
            feedback_parts.append("FAIL: Error parsing MSFT data.")
    else:
        feedback_parts.append("FAIL: MSFT transaction deleted.")

    # --- Check NVDA Integrity (20 pts) ---
    nvda = transactions.get('NVDA')
    if nvda:
        try:
            n_units = float(nvda.get('Units', 0))
            n_price = float(nvda.get('Purchase Price', 0))
            if math.isclose(n_units, EXPECTED_NVDA['units']) and math.isclose(n_price, EXPECTED_NVDA['price']):
                score += 20
                feedback_parts.append("NVDA row unchanged (Correct).")
            else:
                feedback_parts.append("FAIL: NVDA data modified incorrectly.")
        except:
            feedback_parts.append("FAIL: Error parsing NVDA data.")
    else:
        feedback_parts.append("FAIL: NVDA transaction deleted.")

    # Determine Pass/Fail
    # Must get full points on AAPL units/price and reasonable integrity on others
    passed = (score >= 90)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }