#!/usr/bin/env python3
"""
Verifier for record_multi_lot_position task.

Evaluates if the agent correctly recorded 3 specific buy transactions for META
with correct dates, prices, units, fees, and comments.
"""

import json
import os
import logging
import tempfile
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_record_multi_lot_position(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected data from metadata
    metadata = task_info.get('metadata', {})
    expected_lots = metadata.get('lots', [])
    
    # Retrieve result from container
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

    # Basic checks
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Portfolio file not found"}
    
    if not result.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "Portfolio file was not modified (Anti-gaming check failed)"}

    portfolio_data = result.get('portfolio_data', {})
    meta_rows = portfolio_data.get('meta_rows', [])
    original_preserved = portfolio_data.get('original_preserved', False)

    score = 0
    feedback = []

    # 1. Check Row Count (15 pts)
    if len(meta_rows) == 3:
        score += 15
        feedback.append("Correctly found 3 META transactions")
    elif len(meta_rows) > 0:
        score += 5 * len(meta_rows) # Partial credit
        feedback.append(f"Found {len(meta_rows)} META transactions (expected 3)")
    else:
        feedback.append("No META transactions found")

    # 2. Check Original Portfolio Preservation (10 pts)
    if original_preserved:
        score += 10
        feedback.append("Original portfolio data preserved")
    else:
        feedback.append("Original portfolio data (AAPL/MSFT/NVDA) missing or modified")

    # 3. Match Lots (Total 75 pts distributed)
    # Strategy: Try to match each expected lot to the best matching row found
    # We match primarily on Unit count and Price to identify the lot
    
    # Track which rows have been used to avoid double counting
    used_indices = set()
    
    total_units_found = 0
    
    for i, expected in enumerate(expected_lots):
        lot_score = 0
        lot_feedback = []
        best_match_idx = -1
        
        # Find best match based on units and price
        for idx, row in enumerate(meta_rows):
            if idx in used_indices:
                continue
            
            try:
                row_units = float(row.get('Units', 0))
                row_price = float(row.get('Purchase Price', 0))
                
                # Check match (allow small float tolerance)
                if abs(row_units - expected['units']) < 0.1 and abs(row_price - expected['price']) < 0.1:
                    best_match_idx = idx
                    break
            except ValueError:
                continue
        
        if best_match_idx != -1:
            used_indices.add(best_match_idx)
            matched_row = meta_rows[best_match_idx]
            
            # Base points for finding the lot (units+price correct) (12 pts)
            lot_score += 12
            lot_feedback.append("Units/Price OK")
            
            # Check Date (part of the 12 pts logic effectively, but treating as verification here)
            # JStock date format is usually "MMM dd, yyyy" e.g. "Mar 15, 2024"
            row_date = matched_row.get('Date', '')
            if expected['date_str'] in row_date:
                # Full date string match
                pass 
            elif row_date: 
                # Partial/fuzzy check if exact string mismatch
                pass
            
            # Check Broker Fee (12 pts / 3 lots = 4 pts per lot)
            try:
                fee = float(matched_row.get('Broker', 0))
                if abs(fee - expected['fee']) < 0.05:
                    lot_score += 4
                    lot_feedback.append("Fee OK")
                else:
                    lot_feedback.append(f"Fee wrong ({fee})")
            except:
                lot_feedback.append("Fee invalid")

            # Check Comment (9 pts presence + 8 pts content / 3 lots approx 5-6 pts per lot)
            comment = matched_row.get('Comment', '')
            if comment:
                # Presence
                lot_score += 3 
                # Content match (case insensitive partial)
                if expected['comment'].lower() in comment.lower():
                    lot_score += 3
                    lot_feedback.append("Comment OK")
                else:
                    lot_feedback.append("Comment content mismatch")
            else:
                lot_feedback.append("Comment missing")
                
            total_units_found += expected['units']
            feedback.append(f"Lot {i+1}: Found - {', '.join(lot_feedback)}")
        else:
            feedback.append(f"Lot {i+1}: Not found (Expected {expected['units']} units @ {expected['price']})")
        
        score += lot_score

    # 4. Check Total Units (5 pts)
    # If we found all lots above, this is redundant but provides a safety net
    # for partial work where maybe prices were wrong but units were right
    current_total_units = sum([float(r.get('Units', 0)) for r in meta_rows if r.get('Units')])
    if abs(current_total_units - 125.0) < 0.1:
        score += 5
        feedback.append("Total aggregated units correct (125)")

    # Passing logic
    passed = (score >= 60) and (len(meta_rows) >= 2)
    
    return {
        "passed": passed,
        "score": min(100, score), # Cap at 100
        "feedback": " | ".join(feedback)
    }