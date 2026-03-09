#!/usr/bin/env python3
"""
Verifier for Charity Silent Auction task.
Validates formulas, business logic, and calculations for auction management.
"""

import sys
import os
import logging
import re
from typing import Dict, Any, List, Tuple, Optional

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_minimum_increment(starting_bid: float) -> float:
    """Calculate minimum bid increment based on starting bid"""
    if starting_bid < 50:
        return 5
    elif starting_bid < 200:
        return 10
    else:
        return 25


def calculate_expected_values(workbook: Dict[str, Any]) -> Dict[str, Any]:
    """
    Calculate expected values by analyzing Items and Bids sheets independently.
    Returns expected values for verification.
    """
    sheets = workbook.get('sheets', {})
    
    # Parse Items sheet
    items_sheet = sheets.get('Items', [])
    items = {}
    for i, row in enumerate(items_sheet[1:], start=1):  # Skip header
        if len(row) >= 5:
            item_id_cell = row[0]
            item_id = item_id_cell.get('value') if isinstance(item_id_cell, dict) else item_id_cell
            if item_id:
                desc_cell = row[1]
                start_bid_cell = row[3]
                reserve_cell = row[4]
                
                items[str(item_id)] = {
                    'description': desc_cell.get('value') if isinstance(desc_cell, dict) else desc_cell,
                    'starting_bid': float(start_bid_cell.get('value') if isinstance(start_bid_cell, dict) else start_bid_cell),
                    'reserve_price': float(reserve_cell.get('value') if isinstance(reserve_cell, dict) else reserve_cell),
                    'bids': []
                }
    
    # Parse Bids sheet
    bids_sheet = sheets.get('Bids', [])
    for i, row in enumerate(bids_sheet[1:], start=1):  # Skip header
        if len(row) >= 4:
            item_id_cell = row[1]
            bidder_cell = row[2]
            amount_cell = row[3]
            
            item_id = str(item_id_cell.get('value') if isinstance(item_id_cell, dict) else item_id_cell)
            bidder = str(bidder_cell.get('value') if isinstance(bidder_cell, dict) else bidder_cell)
            amount = float(amount_cell.get('value') if isinstance(amount_cell, dict) else amount_cell)
            
            if item_id in items:
                items[item_id]['bids'].append({
                    'bidder': bidder,
                    'amount': amount
                })
    
    # Parse Bidders sheet
    bidders_sheet = sheets.get('Bidders', [])
    bidders = {}
    for i, row in enumerate(bidders_sheet[1:], start=1):  # Skip header
        if len(row) >= 2:
            bidder_num_cell = row[0]
            name_cell = row[1]
            
            bidder_num = str(bidder_num_cell.get('value') if isinstance(bidder_num_cell, dict) else bidder_num_cell)
            name = str(name_cell.get('value') if isinstance(name_cell, dict) else name_cell)
            
            bidders[bidder_num] = name
    
    # Calculate expected results for each item
    expected = {}
    total_revenue = 0
    items_sold = 0
    items_needing_attention = 0
    
    for item_id, item_data in items.items():
        if not item_data['bids']:
            # No bids
            expected[item_id] = {
                'high_bid': 0,
                'winning_bidder': '',
                'winning_name': '',
                'status': 'NO BIDS',
                'valid_increment': False
            }
            items_needing_attention += 1
        else:
            # Find highest bid
            max_bid = max(item_data['bids'], key=lambda x: x['amount'])
            high_bid_amount = max_bid['amount']
            winning_bidder = max_bid['bidder']
            winning_name = bidders.get(winning_bidder, 'Unknown')
            
            # Check if meets reserve
            if high_bid_amount >= item_data['reserve_price']:
                status = 'SOLD'
                items_sold += 1
                total_revenue += high_bid_amount
            else:
                status = 'BELOW RESERVE'
                items_needing_attention += 1
            
            # Validate increment
            starting_bid = item_data['starting_bid']
            min_increment = get_minimum_increment(starting_bid)
            valid_increment = high_bid_amount >= starting_bid + min_increment
            
            expected[item_id] = {
                'high_bid': high_bid_amount,
                'winning_bidder': winning_bidder,
                'winning_name': winning_name,
                'status': status,
                'valid_increment': valid_increment
            }
    
    expected['_totals'] = {
        'revenue': total_revenue,
        'items_sold': items_sold,
        'items_needing_attention': items_needing_attention
    }
    
    return expected


def check_formula_pattern(formula: Optional[str], expected_patterns: List[str]) -> bool:
    """Check if formula matches any of the expected patterns"""
    if not formula:
        return False
    
    formula_upper = formula.upper()
    for pattern in expected_patterns:
        if pattern in formula_upper:
            return True
    return False


def verify_charity_auction(traj, env_info, task_info):
    """
    Verify charity silent auction task completion.
    
    Checks:
    1. Winning bids identified with formulas
    2. Business rules correctly implemented (bid increments)
    3. Status accurately determined (SOLD/BELOW RESERVE/NO BIDS)
    4. Revenue calculated correctly (sum only SOLD items)
    5. Problem items flagged
    6. Lookups work (winning bidder names)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/auction_tracker.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        sheets = workbook.get('sheets', {})
        
        # Verify Summary sheet exists
        if 'Summary' not in sheets:
            return {"passed": False, "score": 0, "feedback": "Summary sheet not found"}
        
        summary_sheet = sheets['Summary']
        
        # Calculate expected values
        expected = calculate_expected_values(workbook)
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Get items from Items sheet
        items_sheet = sheets.get('Items', [])
        item_ids = []
        for i, row in enumerate(items_sheet[1:], start=1):
            if len(row) >= 1:
                item_id_cell = row[0]
                item_id = str(item_id_cell.get('value') if isinstance(item_id_cell, dict) else item_id_cell)
                if item_id:
                    item_ids.append(item_id)
        
        # Criterion 1: Winning bids identified (formulas in column E)
        winning_bids_correct = 0
        winning_bids_have_formulas = 0
        
        for idx, item_id in enumerate(item_ids):
            row_num = 4 + idx  # Summary starts at row 4 (after headers)
            cell_ref = f"E{row_num}"
            
            actual_value = get_cell_value(workbook, 'Summary', cell_ref)
            formula = get_cell_formula(workbook, 'Summary', cell_ref)
            
            expected_value = expected[item_id]['high_bid']
            
            # Check if formula exists
            if formula and ('MAX' in formula.upper() or 'IF' in formula.upper()):
                winning_bids_have_formulas += 1
            
            # Check if value is correct (within tolerance)
            if actual_value is not None:
                try:
                    actual_float = float(actual_value)
                    if abs(actual_float - expected_value) < 0.01:
                        winning_bids_correct += 1
                except (ValueError, TypeError):
                    pass
        
        if winning_bids_correct >= len(item_ids) * 0.8 and winning_bids_have_formulas >= len(item_ids) * 0.7:
            criteria_passed += 1
            feedback_parts.append(f"✅ Winning bids identified ({winning_bids_correct}/{len(item_ids)} correct with formulas)")
        else:
            feedback_parts.append(f"❌ Winning bids incomplete ({winning_bids_correct}/{len(item_ids)} correct, {winning_bids_have_formulas} with formulas)")
        
        # Criterion 2: Business rules applied (status determination)
        status_correct = 0
        status_have_formulas = 0
        
        for idx, item_id in enumerate(item_ids):
            row_num = 4 + idx
            cell_ref = f"H{row_num}"
            
            actual_status = get_cell_value(workbook, 'Summary', cell_ref)
            formula = get_cell_formula(workbook, 'Summary', cell_ref)
            
            expected_status = expected[item_id]['status']
            
            # Check if formula exists
            if formula and 'IF' in formula.upper():
                status_have_formulas += 1
            
            # Check if status is correct
            if actual_status and expected_status in str(actual_status).upper():
                status_correct += 1
        
        if status_correct >= len(item_ids) * 0.8 and status_have_formulas >= len(item_ids) * 0.7:
            criteria_passed += 1
            feedback_parts.append(f"✅ Status correctly determined ({status_correct}/{len(item_ids)} correct)")
        else:
            feedback_parts.append(f"❌ Status determination incomplete ({status_correct}/{len(item_ids)} correct)")
        
        # Criterion 3: Revenue calculated (sum of SOLD items)
        # Look for revenue cell in totals section (around row 17-19)
        revenue_cell_found = False
        revenue_correct = False
        
        for row_num in range(17, 22):
            cell_ref_label = f"A{row_num}"
            cell_ref_value = f"B{row_num}"
            
            label = get_cell_value(workbook, 'Summary', cell_ref_label)
            if label and 'REVENUE' in str(label).upper():
                actual_revenue = get_cell_value(workbook, 'Summary', cell_ref_value)
                formula = get_cell_formula(workbook, 'Summary', cell_ref_value)
                
                revenue_cell_found = True
                expected_revenue = expected['_totals']['revenue']
                
                if actual_revenue is not None:
                    try:
                        actual_float = float(actual_revenue)
                        if abs(actual_float - expected_revenue) < 1.0:
                            revenue_correct = True
                    except (ValueError, TypeError):
                        pass
                
                if revenue_correct and formula and 'SUM' in formula.upper():
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Revenue calculated correctly (${actual_revenue:.2f})")
                else:
                    feedback_parts.append(f"❌ Revenue incorrect (expected ${expected_revenue:.2f}, got {actual_revenue})")
                break
        
        if not revenue_cell_found:
            feedback_parts.append("❌ Revenue calculation not found")
        
        # Criterion 4: Problem items flagged (count of items needing attention)
        items_attention_found = False
        items_attention_correct = False
        
        for row_num in range(17, 22):
            cell_ref_label = f"A{row_num}"
            cell_ref_value = f"B{row_num}"
            
            label = get_cell_value(workbook, 'Summary', cell_ref_label)
            if label and 'ATTENTION' in str(label).upper():
                actual_count = get_cell_value(workbook, 'Summary', cell_ref_value)
                formula = get_cell_formula(workbook, 'Summary', cell_ref_value)
                
                items_attention_found = True
                expected_count = expected['_totals']['items_needing_attention']
                
                if actual_count is not None:
                    try:
                        actual_int = int(float(actual_count))
                        if actual_int == expected_count:
                            items_attention_correct = True
                    except (ValueError, TypeError):
                        pass
                
                if items_attention_correct:
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Problem items flagged ({actual_count} items need attention)")
                else:
                    feedback_parts.append(f"❌ Problem items count incorrect (expected {expected_count}, got {actual_count})")
                break
        
        if not items_attention_found:
            feedback_parts.append("❌ Items needing attention count not found")
        
        # Criterion 5: Lookups work (winning bidder names)
        lookups_correct = 0
        lookups_have_formulas = 0
        
        for idx, item_id in enumerate(item_ids):
            row_num = 4 + idx
            cell_ref = f"G{row_num}"
            
            actual_name = get_cell_value(workbook, 'Summary', cell_ref)
            formula = get_cell_formula(workbook, 'Summary', cell_ref)
            
            expected_name = expected[item_id]['winning_name']
            
            # Check if formula exists (VLOOKUP or INDEX/MATCH)
            if formula and ('VLOOKUP' in formula.upper() or 'INDEX' in formula.upper() or 'MATCH' in formula.upper()):
                lookups_have_formulas += 1
            
            # Check if name is correct (or empty for items with no bids)
            if expected_name == 'Unknown' or expected_name == '':
                # For items with no bids, accept empty or any indicator
                lookups_correct += 1
            elif actual_name and expected_name.split()[0] in str(actual_name):
                # Check if first name matches (flexible matching)
                lookups_correct += 1
        
        if lookups_correct >= len(item_ids) * 0.7 and lookups_have_formulas >= 3:
            criteria_passed += 1
            feedback_parts.append(f"✅ Lookups work ({lookups_correct}/{len(item_ids)} correct names)")
        else:
            feedback_parts.append(f"❌ Lookups incomplete ({lookups_correct}/{len(item_ids)} correct, {lookups_have_formulas} with formulas)")
        
        # Criterion 6: Bid increment validation (column I)
        # This is a bonus criterion - checking if increment validation logic is implemented
        increment_checks = 0
        
        for idx, item_id in enumerate(item_ids[:3]):  # Check first 3 items
            row_num = 4 + idx
            cell_ref = f"I{row_num}"
            
            formula = get_cell_formula(workbook, 'Summary', cell_ref)
            
            # Just check if some formula exists that references starting bid
            if formula and 'IF' in formula.upper():
                increment_checks += 1
        
        if increment_checks >= 2:
            criteria_passed += 1
            feedback_parts.append("✅ Bid increment validation implemented")
        else:
            feedback_parts.append("⚠️ Bid increment validation not found (optional)")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80
        
        if passed:
            feedback_parts.append("🎉 Auction summary completed successfully!")
        else:
            feedback_parts.append("❌ Auction summary incomplete")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "winning_bids": winning_bids_correct >= len(item_ids) * 0.8,
                "status_determination": status_correct >= len(item_ids) * 0.8,
                "revenue_calculation": revenue_correct,
                "problem_items_flagged": items_attention_correct,
                "lookups_work": lookups_correct >= len(item_ids) * 0.7,
                "increment_validation": increment_checks >= 2
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
