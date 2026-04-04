#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_document_portfolio_thesis(traj, env_info, task_info):
    """
    Verifies that comments were added to AAPL and MSFT buy transactions
    while preserving the original financial data.
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Requirements from metadata
    meta = task_info.get('metadata', {})
    EXPECTED_AAPL_COMMENT = meta.get('aapl_comment', "Long term ecosystem compounder")
    EXPECTED_MSFT_COMMENT = meta.get('msft_comment', "Cloud infrastructure leader")
    
    # Check modification
    if not result.get('file_modified_during_task', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Portfolio file was not modified. Ensure you saved changes or closed JStock properly."
        }

    data = result.get('portfolio_data', [])
    if not data:
        return {"passed": False, "score": 0, "feedback": "Portfolio file is empty or invalid."}

    score = 10
    feedback = []
    
    # Flags
    aapl_found = False
    msft_found = False
    aapl_correct = False
    msft_correct = False
    aapl_preserved = False
    msft_preserved = False

    for row in data:
        code = row.get('Code', '')
        
        # Check AAPL
        if code == 'AAPL':
            aapl_found = True
            comment = row.get('Comment', '').strip()
            units = row.get('Units', '')
            price = row.get('Purchase Price', '')
            
            # Check comment
            if EXPECTED_AAPL_COMMENT.lower() in comment.lower():
                aapl_correct = True
                score += 25
                feedback.append("AAPL comment added correctly.")
            else:
                feedback.append(f"AAPL comment incorrect. Expected '{EXPECTED_AAPL_COMMENT}', got '{comment}'.")
            
            # Check data preservation
            if float(units) == 100.0 and float(price) == 185.2:
                aapl_preserved = True
                score += 15
                feedback.append("AAPL financial data preserved.")
            else:
                feedback.append(f"AAPL data modified! Units: {units} (exp 100.0), Price: {price} (exp 185.2)")

        # Check MSFT
        elif code == 'MSFT':
            msft_found = True
            comment = row.get('Comment', '').strip()
            units = row.get('Units', '')
            price = row.get('Purchase Price', '')
            
            # Check comment
            if EXPECTED_MSFT_COMMENT.lower() in comment.lower():
                msft_correct = True
                score += 25
                feedback.append("MSFT comment added correctly.")
            else:
                feedback.append(f"MSFT comment incorrect. Expected '{EXPECTED_MSFT_COMMENT}', got '{comment}'.")
            
            # Check data preservation
            if float(units) == 50.0 and float(price) == 374.5:
                msft_preserved = True
                score += 15
                feedback.append("MSFT financial data preserved.")
            else:
                feedback.append(f"MSFT data modified! Units: {units} (exp 50.0), Price: {price} (exp 374.5)")

        # Check NVDA (should be untouched, specifically not deleted)
        elif code == 'NVDA':
            score += 10 # Points for not deleting other data

    if not aapl_found:
        feedback.append("AAPL holding not found in portfolio.")
    if not msft_found:
        feedback.append("MSFT holding not found in portfolio.")

    passed = (score >= 80) and aapl_correct and msft_correct and aapl_preserved and msft_preserved

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }