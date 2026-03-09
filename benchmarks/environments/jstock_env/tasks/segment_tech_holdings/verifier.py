#!/usr/bin/env python3
import json
import base64
import csv
import io
import os
import tempfile

def verify_segment_tech_holdings(traj, env_info, task_info):
    """
    Verifies that MSFT and NVDA were moved from 'My Portfolio' to 'Tech Portfolio'
    preserving units and purchase price.
    """
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    my_port_b64 = result.get('my_portfolio_content_b64', '')
    tech_port_b64 = result.get('tech_portfolio_content_b64', '')
    tech_exists = result.get('tech_portfolio_exists', False)
    
    # Decode CSVs
    def parse_csv(b64_str):
        if not b64_str:
            return []
        try:
            content = base64.b64decode(b64_str).decode('utf-8')
            # JStock CSVs often quote everything. csv.DictReader handles this well.
            f = io.StringIO(content)
            reader = csv.DictReader(f)
            return list(reader)
        except Exception:
            return []

    my_portfolio = parse_csv(my_port_b64)
    tech_portfolio = parse_csv(tech_port_b64)

    # Helper to find stock in list
    def find_stock(rows, symbol):
        for row in rows:
            # JStock keys are usually "Code" or "Symbol"
            if row.get('Code') == symbol or row.get('Symbol') == symbol:
                return row
        return None

    # 3. Scoring Logic
    score = 0
    feedback = []

    # Criterion 1: Tech Portfolio Created (10 pts)
    if tech_exists:
        score += 10
        feedback.append("Tech Portfolio created.")
    else:
        feedback.append("Tech Portfolio NOT found.")

    # Criterion 2 & 3: MSFT Migrated (25 pts total)
    msft_tech = find_stock(tech_portfolio, 'MSFT')
    if msft_tech:
        score += 15
        feedback.append("MSFT found in Tech Portfolio.")
        
        # Check Values (Units: 50, Price: 374.5)
        try:
            units = float(msft_tech.get('Units', 0))
            price = float(msft_tech.get('Purchase Price', 0))
            if abs(units - 50.0) < 0.1:
                score += 5
            else:
                feedback.append(f"MSFT Units mismatch (Exp: 50, Got: {units})")
                
            if abs(price - 374.5) < 0.1:
                score += 5
                feedback.append("MSFT data matches exactly.")
            else:
                feedback.append(f"MSFT Price mismatch (Exp: 374.5, Got: {price})")
        except ValueError:
            feedback.append("Error parsing MSFT numeric data.")
    else:
        feedback.append("MSFT NOT found in Tech Portfolio.")

    # Criterion 4 & 5: NVDA Migrated (25 pts total)
    nvda_tech = find_stock(tech_portfolio, 'NVDA')
    if nvda_tech:
        score += 15
        feedback.append("NVDA found in Tech Portfolio.")
        
        # Check Values (Units: 25, Price: 615.3)
        try:
            units = float(nvda_tech.get('Units', 0))
            price = float(nvda_tech.get('Purchase Price', 0))
            if abs(units - 25.0) < 0.1:
                score += 5
            else:
                feedback.append(f"NVDA Units mismatch (Exp: 25, Got: {units})")
                
            if abs(price - 615.3) < 0.1:
                score += 5
                feedback.append("NVDA data matches exactly.")
            else:
                feedback.append(f"NVDA Price mismatch (Exp: 615.3, Got: {price})")
        except ValueError:
            feedback.append("Error parsing NVDA numeric data.")
    else:
        feedback.append("NVDA NOT found in Tech Portfolio.")

    # Criterion 6: AAPL Retained (10 pts)
    aapl_my = find_stock(my_portfolio, 'AAPL')
    if aapl_my:
        score += 10
        feedback.append("AAPL retained in My Portfolio.")
    else:
        feedback.append("AAPL missing from My Portfolio (should remain).")

    # Criterion 7: MSFT Removed from Source (15 pts)
    msft_my = find_stock(my_portfolio, 'MSFT')
    if not msft_my:
        score += 15
        feedback.append("MSFT removed from My Portfolio.")
    else:
        feedback.append("MSFT still present in My Portfolio (should be removed).")

    # Criterion 8: NVDA Removed from Source (15 pts)
    nvda_my = find_stock(my_portfolio, 'NVDA')
    if not nvda_my:
        score += 15
        feedback.append("NVDA removed from My Portfolio.")
    else:
        feedback.append("NVDA still present in My Portfolio (should be removed).")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }