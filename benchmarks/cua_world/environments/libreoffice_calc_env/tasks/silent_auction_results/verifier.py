#!/usr/bin/env python3
"""
Verifier for Silent Auction Results task.

Checks:
1. Highest Bid column calculated correctly (MAX formula)
2. Winning Bidder identified correctly
3. Sale Status follows reserve price rules
4. Final Price calculated correctly
5. Summary statistics present and accurate
"""

import sys
import os
import logging
from typing import Dict, Any, Tuple, List, Optional

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def clean_currency_value(value: Any) -> float:
    """Convert currency string or number to float, handling $ symbols and text."""
    if value is None or value == '':
        return 0.0
    
    if isinstance(value, (int, float)):
        return float(value)
    
    if isinstance(value, str):
        # Remove $, commas, spaces
        cleaned = value.replace('$', '').replace(',', '').strip()
        if cleaned == '':
            return 0.0
        try:
            return float(cleaned)
        except ValueError:
            return 0.0
    
    return 0.0


def get_bid_columns() -> List[str]:
    """Return column letters for Bid 1-5 (E, G, I, K, M)."""
    return ['E', 'G', 'I', 'K', 'M']


def get_bidder_columns() -> List[str]:
    """Return column letters for Bidder 1-5 (F, H, J, L, N)."""
    return ['F', 'H', 'J', 'L', 'N']


def calculate_expected_highest_bid(data: Dict, sheet_name: str, row_idx: int) -> float:
    """Calculate the expected highest bid for a given row."""
    bid_cols = get_bid_columns()
    bids = []
    
    for col in bid_cols:
        cell_val = get_cell_value(data, sheet_name, f"{col}{row_idx}")
        bid_amount = clean_currency_value(cell_val)
        bids.append(bid_amount)
    
    return max(bids) if bids else 0.0


def find_expected_winner(data: Dict, sheet_name: str, row_idx: int, highest_bid: float) -> Optional[str]:
    """Find which bidder submitted the highest bid."""
    if highest_bid == 0:
        return None
    
    bid_cols = get_bid_columns()
    bidder_cols = get_bidder_columns()
    
    for bid_col, bidder_col in zip(bid_cols, bidder_cols):
        bid_val = get_cell_value(data, sheet_name, f"{bid_col}{row_idx}")
        bid_amount = clean_currency_value(bid_val)
        
        if abs(bid_amount - highest_bid) < 0.01:  # Match found
            winner = get_cell_value(data, sheet_name, f"{bidder_col}{row_idx}")
            return str(winner) if winner else None
    
    return None


def determine_expected_status(highest_bid: float, reserve_price: float) -> str:
    """Determine expected sale status based on reserve price rules."""
    if highest_bid == 0:
        return "NO BIDS"
    elif highest_bid >= reserve_price:
        return "SOLD"
    else:
        return "NOT SOLD"


def verify_highest_bid_accuracy(data: Dict, sheet_name: str, 
                                result_col: str = 'O') -> Tuple[bool, List[str], int]:
    """
    Verify that Highest Bid column contains correct values.
    
    Returns: (passed, errors, correct_count)
    """
    errors = []
    correct_count = 0
    total_rows = 20
    
    for row_idx in range(2, 22):  # Rows 2-21 (20 items)
        expected_max = calculate_expected_highest_bid(data, sheet_name, row_idx)
        
        actual_val = get_cell_value(data, sheet_name, f"{result_col}{row_idx}")
        actual_max = clean_currency_value(actual_val)
        
        if abs(actual_max - expected_max) <= 0.01:
            correct_count += 1
        else:
            errors.append(f"Row {row_idx}: Expected highest bid ${expected_max:.2f}, got ${actual_max:.2f}")
    
    accuracy = correct_count / total_rows
    passed = accuracy >= 0.95
    
    return passed, errors[:3], correct_count  # Return first 3 errors only


def verify_winner_determination(data: Dict, sheet_name: str,
                                highest_bid_col: str = 'O',
                                winner_col: str = 'P') -> Tuple[bool, List[str], int]:
    """
    Verify that Winning Bidder column contains correct bidder IDs.
    
    Returns: (passed, errors, correct_count)
    """
    errors = []
    correct_count = 0
    total_rows = 20
    
    for row_idx in range(2, 22):
        highest_bid_val = get_cell_value(data, sheet_name, f"{highest_bid_col}{row_idx}")
        highest_bid = clean_currency_value(highest_bid_val)
        
        expected_winner = find_expected_winner(data, sheet_name, row_idx, highest_bid)
        actual_winner = get_cell_value(data, sheet_name, f"{winner_col}{row_idx}")
        
        # Normalize comparison
        expected_str = str(expected_winner).strip().upper() if expected_winner else ""
        actual_str = str(actual_winner).strip().upper() if actual_winner else ""
        
        # Handle no-bid cases
        if highest_bid == 0:
            # Should be blank or indicate no bidder
            if actual_str in ["", "NO BIDDER", "N/A", "NONE", "NO BID"]:
                correct_count += 1
            else:
                errors.append(f"Row {row_idx}: No bids, but winner shows '{actual_winner}'")
        else:
            # Should match expected winner
            if expected_str == actual_str:
                correct_count += 1
            else:
                errors.append(f"Row {row_idx}: Expected winner '{expected_winner}', got '{actual_winner}'")
    
    accuracy = correct_count / total_rows
    passed = accuracy >= 0.90
    
    return passed, errors[:3], correct_count


def verify_sale_status_logic(data: Dict, sheet_name: str,
                             highest_bid_col: str = 'O',
                             reserve_col: str = 'D',
                             status_col: str = 'Q') -> Tuple[bool, List[str], int]:
    """
    Verify that Sale Status follows reserve price rules.
    
    Returns: (passed, errors, correct_count)
    """
    errors = []
    correct_count = 0
    total_rows = 20
    
    for row_idx in range(2, 22):
        highest_bid_val = get_cell_value(data, sheet_name, f"{highest_bid_col}{row_idx}")
        highest_bid = clean_currency_value(highest_bid_val)
        
        reserve_val = get_cell_value(data, sheet_name, f"{reserve_col}{row_idx}")
        reserve_price = clean_currency_value(reserve_val)
        
        status_val = get_cell_value(data, sheet_name, f"{status_col}{row_idx}")
        status = str(status_val).strip().upper() if status_val else ""
        
        expected_status = determine_expected_status(highest_bid, reserve_price)
        
        # Check if status matches expected
        correct = False
        if expected_status == "NO BIDS":
            if status in ["NO BIDS", "NO BID", "N/A", "NONE", ""]:
                correct = True
        elif expected_status == "SOLD":
            if status in ["SOLD", "SALE", "YES", "SUCCESS"]:
                correct = True
        elif expected_status == "NOT SOLD":
            if status in ["NOT SOLD", "NO SALE", "RESERVE NOT MET", "FAILED", "NOT SOLD"]:
                correct = True
        
        if correct:
            correct_count += 1
        else:
            errors.append(f"Row {row_idx}: Expected '{expected_status}', got '{status}' (bid=${highest_bid:.0f}, reserve=${reserve_price:.0f})")
    
    accuracy = correct_count / total_rows
    passed = accuracy >= 0.95
    
    return passed, errors[:3], correct_count


def verify_final_price_calculation(data: Dict, sheet_name: str,
                                   highest_bid_col: str = 'O',
                                   status_col: str = 'Q',
                                   final_price_col: str = 'R') -> Tuple[bool, List[str], float]:
    """
    Verify that Final Price is correct (highest bid if SOLD, else 0).
    
    Returns: (passed, errors, total_revenue)
    """
    errors = []
    total_revenue = 0.0
    expected_revenue = 0.0
    
    for row_idx in range(2, 22):
        highest_bid_val = get_cell_value(data, sheet_name, f"{highest_bid_col}{row_idx}")
        highest_bid = clean_currency_value(highest_bid_val)
        
        status_val = get_cell_value(data, sheet_name, f"{status_col}{row_idx}")
        status = str(status_val).strip().upper() if status_val else ""
        
        final_price_val = get_cell_value(data, sheet_name, f"{final_price_col}{row_idx}")
        final_price = clean_currency_value(final_price_val)
        
        # Determine expected final price
        if status in ["SOLD", "SALE", "YES", "SUCCESS"]:
            expected_final = highest_bid
            expected_revenue += highest_bid
        else:
            expected_final = 0.0
        
        # Check if final price matches expected
        if abs(final_price - expected_final) <= 0.01:
            total_revenue += final_price
        else:
            errors.append(f"Row {row_idx}: Expected final price ${expected_final:.2f}, got ${final_price:.2f}")
            total_revenue += final_price  # Still count it
    
    revenue_matches = abs(total_revenue - expected_revenue) <= 1.0
    passed = revenue_matches and len(errors) <= 1
    
    return passed, errors[:3], total_revenue


def check_summary_statistics(data: Dict, sheet_name: str) -> Tuple[int, Dict[str, Any]]:
    """
    Check for presence of summary statistics in the spreadsheet.
    
    Returns: (criteria_met_count, stats_info)
    """
    criteria_met = 0
    stats_info = {}
    
    # Search for summary statistics in rows 23-35 (below the data)
    # Look for keywords and associated values
    
    found_stats = {
        'revenue': False,
        'sold_count': False,
        'not_sold_count': False,
        'highest_price': False
    }
    
    for row_idx in range(23, 36):
        for col in ['A', 'B', 'C', 'D', 'E', 'F']:
            cell_val = get_cell_value(data, sheet_name, f"{col}{row_idx}")
            if not cell_val:
                continue
            
            cell_str = str(cell_val).upper()
            
            # Check adjacent cell for value
            value_cell = None
            for offset_col in [chr(ord(col) + 1), chr(ord(col) + 2)]:
                if offset_col <= 'Z':
                    value_cell = get_cell_value(data, sheet_name, f"{offset_col}{row_idx}")
                    if value_cell is not None and value_cell != '':
                        break
            
            # Look for revenue/total
            if any(keyword in cell_str for keyword in ['REVENUE', 'TOTAL', 'RAISED']):
                if value_cell is not None:
                    found_stats['revenue'] = True
                    stats_info['revenue'] = clean_currency_value(value_cell)
            
            # Look for items sold count
            if any(keyword in cell_str for keyword in ['SOLD', 'SUCCESS']) and 'NOT' not in cell_str:
                if value_cell is not None:
                    found_stats['sold_count'] = True
                    stats_info['sold_count'] = clean_currency_value(value_cell)
            
            # Look for items not sold count
            if any(keyword in cell_str for keyword in ['NOT SOLD', 'UNSOLD', 'FAILED']):
                if value_cell is not None:
                    found_stats['not_sold_count'] = True
                    stats_info['not_sold_count'] = clean_currency_value(value_cell)
            
            # Look for highest price
            if any(keyword in cell_str for keyword in ['HIGHEST', 'MAX', 'TOP']):
                if value_cell is not None:
                    found_stats['highest_price'] = True
                    stats_info['highest_price'] = clean_currency_value(value_cell)
    
    criteria_met = sum(found_stats.values())
    return criteria_met, stats_info


def verify_auction_results(traj, env_info, task_info):
    """
    Main verifier function for Silent Auction Results task.
    
    Checks:
    1. Highest Bid calculated correctly (≥95% accuracy)
    2. Winners determined correctly (≥90% accuracy)
    3. Reserve Price logic applied correctly (≥95% accuracy)
    4. Revenue calculated correctly (within $1.00)
    5. Required columns present
    6. Summary statistics present (at least 2 of 4)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file paths
    file_paths = [
        "/home/ga/Documents/auction_results.ods",
        "/home/ga/Documents/auction_items.ods"
    ]
    
    success = False
    file_info = None
    error = ""
    
    for container_path in file_paths:
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            ['ods']
        )
        if success:
            logger.info(f"Successfully loaded file from: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load auction file: {error}. Tried paths: {', '.join(file_paths)}"
        }
    
    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Highest Bid Calculated (Column O exists and accurate)
        highest_bid_present = get_cell_value(data, sheet_name, 'O2') is not None
        
        if highest_bid_present:
            highest_bid_passed, hb_errors, hb_correct = verify_highest_bid_accuracy(data, sheet_name, 'O')
            if highest_bid_passed:
                criteria_passed += 1
                feedback_parts.append(f"✅ Highest Bid calculated correctly ({hb_correct}/20 items)")
            else:
                feedback_parts.append(f"⚠️ Highest Bid has errors ({hb_correct}/20 correct). Examples: {'; '.join(hb_errors[:2])}")
                if hb_correct >= 17:  # 85% correct
                    criteria_passed += 0.75
            subscores['highest_bid_accuracy'] = hb_correct / 20
        else:
            feedback_parts.append("❌ Highest Bid column (O) not found or empty")
            subscores['highest_bid_accuracy'] = 0
        
        # Criterion 2: Winners Determined (Column P exists and mostly accurate)
        winner_present = get_cell_value(data, sheet_name, 'P2') is not None
        
        if winner_present and highest_bid_present:
            winner_passed, winner_errors, winner_correct = verify_winner_determination(data, sheet_name, 'O', 'P')
            if winner_passed:
                criteria_passed += 1
                feedback_parts.append(f"✅ Winners determined correctly ({winner_correct}/20 items)")
            else:
                feedback_parts.append(f"⚠️ Winner determination has errors ({winner_correct}/20 correct)")
                if winner_correct >= 16:  # 80% correct
                    criteria_passed += 0.5
            subscores['winner_accuracy'] = winner_correct / 20
        else:
            feedback_parts.append("❌ Winning Bidder column (P) not found or empty")
            subscores['winner_accuracy'] = 0
        
        # Criterion 3: Reserve Price Logic (Column Q exists and accurate)
        status_present = get_cell_value(data, sheet_name, 'Q2') is not None
        
        if status_present and highest_bid_present:
            status_passed, status_errors, status_correct = verify_sale_status_logic(data, sheet_name, 'O', 'D', 'Q')
            if status_passed:
                criteria_passed += 1
                feedback_parts.append(f"✅ Sale status logic correct ({status_correct}/20 items)")
            else:
                feedback_parts.append(f"⚠️ Sale status has errors ({status_correct}/20 correct). Examples: {'; '.join(status_errors[:2])}")
                if status_correct >= 17:  # 85% correct
                    criteria_passed += 0.75
            subscores['status_accuracy'] = status_correct / 20
        else:
            feedback_parts.append("❌ Sale Status column (Q) not found or empty")
            subscores['status_accuracy'] = 0
        
        # Criterion 4: Revenue Calculated (Column R exists and accurate)
        final_price_present = get_cell_value(data, sheet_name, 'R2') is not None
        
        if final_price_present and status_present and highest_bid_present:
            revenue_passed, revenue_errors, total_revenue = verify_final_price_calculation(data, sheet_name, 'O', 'Q', 'R')
            if revenue_passed:
                criteria_passed += 1
                feedback_parts.append(f"✅ Final prices calculated correctly (Total: ${total_revenue:.2f})")
            else:
                feedback_parts.append(f"⚠️ Final price calculation has errors. Total revenue: ${total_revenue:.2f}")
                if len(revenue_errors) <= 2:
                    criteria_passed += 0.5
            subscores['revenue_accurate'] = revenue_passed
        else:
            feedback_parts.append("❌ Final Price column (R) not found or empty")
            subscores['revenue_accurate'] = False
        
        # Criterion 5: Required Columns Present
        all_columns_present = all([
            highest_bid_present,
            winner_present,
            status_present,
            final_price_present
        ])
        
        if all_columns_present:
            criteria_passed += 1
            feedback_parts.append("✅ All required columns present (O, P, Q, R)")
        else:
            missing = []
            if not highest_bid_present:
                missing.append('O:Highest Bid')
            if not winner_present:
                missing.append('P:Winner')
            if not status_present:
                missing.append('Q:Status')
            if not final_price_present:
                missing.append('R:Final Price')
            feedback_parts.append(f"❌ Missing columns: {', '.join(missing)}")
        
        subscores['columns_present'] = all_columns_present
        
        # Criterion 6: Summary Statistics Present
        stats_count, stats_info = check_summary_statistics(data, sheet_name)
        
        if stats_count >= 2:
            criteria_passed += 1
            feedback_parts.append(f"✅ Summary statistics found ({stats_count}/4 metrics)")
        elif stats_count == 1:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Partial summary statistics ({stats_count}/4 metrics)")
        else:
            feedback_parts.append("❌ Summary statistics not found or incomplete")
        
        subscores['summary_stats_count'] = stats_count
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Need 4.2/6 criteria (70%)
        
        # Add final message
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent! Auction results processed successfully!")
        elif passed:
            feedback_parts.append("✅ Auction results task completed")
        else:
            feedback_parts.append("❌ Auction results incomplete - missing key calculations")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        cleanup_verification_temp(file_info.get('temp_dir') if file_info else None)
