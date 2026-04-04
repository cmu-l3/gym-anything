#!/usr/bin/env python3
"""
Verifier for Subscription Audit task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_header_positions(sheet, max_row=5):
    """
    Find column positions for key headers by searching first few rows.
    Returns dict with header names mapped to column indices (1-based).
    """
    header_map = {}
    keywords = {
        'service': ['service', 'name', 'subscription'],
        'category': ['category', 'type'],
        'billing': ['billing', 'cycle', 'frequency', 'period'],
        'amount': ['amount', 'charged', 'cost', 'price'],
        'monthly': ['monthly', 'month'],
        'value': ['value', 'usage', 'rating', 'priority'],
        'savings': ['savings', 'save', 'annual']
    }
    
    # Search first few rows for headers
    for row_idx in range(1, max_row + 1):
        row_values = []
        for col_idx in range(1, 20):  # Check first 20 columns
            cell_value = sheet.cell(row_idx, col_idx).value
            if cell_value:
                row_values.append((col_idx, str(cell_value).lower()))
        
        # Check if this row contains headers
        matched_count = 0
        temp_map = {}
        
        for col_idx, cell_text in row_values:
            for key, possible_words in keywords.items():
                if key not in temp_map:  # Only map once per key
                    if any(word in cell_text for word in possible_words):
                        temp_map[key] = col_idx
                        matched_count += 1
        
        # If we matched at least 4 key headers, consider this the header row
        if matched_count >= 4:
            header_map = temp_map
            header_map['header_row'] = row_idx
            break
    
    return header_map


def normalize_billing_cycle(cycle_text):
    """Normalize billing cycle text to standard format."""
    if not cycle_text:
        return None
    
    cycle_lower = str(cycle_text).lower()
    if 'month' in cycle_lower and 'annual' not in cycle_lower:
        return 'monthly'
    elif 'annual' in cycle_lower or 'year' in cycle_lower:
        return 'annual'
    elif 'quarter' in cycle_lower:
        return 'quarterly'
    elif 'week' in cycle_lower:
        return 'weekly'
    return None


def calculate_expected_monthly(charged_amount, billing_cycle):
    """Calculate expected monthly cost based on billing cycle."""
    if not charged_amount or not isinstance(charged_amount, (int, float)):
        return None
    
    cycle = normalize_billing_cycle(billing_cycle)
    if cycle == 'monthly':
        return charged_amount
    elif cycle == 'annual':
        return charged_amount / 12
    elif cycle == 'quarterly':
        return charged_amount / 3
    elif cycle == 'weekly':
        return charged_amount * 4.33
    return None


def verify_subscription_audit(traj, env_info, task_info):
    """
    Verify that subscription audit spreadsheet was created correctly.

    Checks:
    1. File exists and can be parsed
    2. Headers are present
    3. At least 6 subscription entries
    4. Data completeness (all required fields filled)
    5. Monthly cost calculations present and accurate
    6. Annual savings calculations present
    7. Total savings summary with conditional logic (SUMIF for Low value items)
    8. Overall financial accuracy
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/subscription_audit.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_subscription_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        # Try to get the active sheet (could be named differently)
        sheet = wb.active
        
        score = 0
        feedback_parts = []
        
        # Find header positions dynamically
        header_map = find_header_positions(sheet)
        
        if not header_map or len(header_map) < 4:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not find proper headers in spreadsheet. Expected: Service Name, Category, Billing Cycle, Charged Amount, Monthly Cost, Usage Value, Annual Savings"
            }
        
        header_row = header_map.get('header_row', 1)
        service_col = header_map.get('service')
        category_col = header_map.get('category')
        billing_col = header_map.get('billing')
        amount_col = header_map.get('amount')
        monthly_col = header_map.get('monthly')
        value_col = header_map.get('value')
        savings_col = header_map.get('savings')
        
        # Check that we found the critical columns
        critical_cols = [service_col, billing_col, amount_col, monthly_col, value_col, savings_col]
        if not all(critical_cols):
            feedback_parts.append("⚠️ Some required columns not found")
            score += 5
        else:
            feedback_parts.append("✅ Proper headers present")
            score += 15
        
        # Count data rows (rows after header with service name)
        data_rows = []
        for row_idx in range(header_row + 1, header_row + 30):  # Check up to 30 rows after header
            if service_col:
                service_value = sheet.cell(row_idx, service_col).value
                # Skip instruction/example rows
                if service_value and not str(service_value).lower().startswith('enter'):
                    # Check if this looks like a summary row
                    service_lower = str(service_value).lower()
                    if 'total' in service_lower or 'summary' in service_lower or 'potential' in service_lower:
                        continue  # Skip summary rows for data counting
                    data_rows.append(row_idx)
        
        num_subscriptions = len(data_rows)
        
        if num_subscriptions >= 6:
            score += 20
            feedback_parts.append(f"✅ {num_subscriptions} subscriptions entered (≥6 required)")
        elif num_subscriptions >= 4:
            score += 10
            feedback_parts.append(f"⚠️ Only {num_subscriptions} subscriptions (need 6)")
        else:
            feedback_parts.append(f"❌ Only {num_subscriptions} subscriptions (need 6)")
        
        # Check data completeness
        if num_subscriptions > 0 and all(critical_cols):
            complete_rows = 0
            for row_idx in data_rows:
                row_complete = True
                # Check service name
                if not sheet.cell(row_idx, service_col).value:
                    row_complete = False
                # Check billing cycle
                if billing_col and not sheet.cell(row_idx, billing_col).value:
                    row_complete = False
                # Check charged amount
                if amount_col:
                    amount = sheet.cell(row_idx, amount_col).value
                    if not amount or not isinstance(amount, (int, float)) or amount <= 0:
                        row_complete = False
                # Check usage value
                if value_col and not sheet.cell(row_idx, value_col).value:
                    row_complete = False
                
                if row_complete:
                    complete_rows += 1
            
            completeness_ratio = complete_rows / num_subscriptions if num_subscriptions > 0 else 0
            if completeness_ratio >= 0.8:
                score += 15
                feedback_parts.append(f"✅ {complete_rows}/{num_subscriptions} rows have complete data")
            elif completeness_ratio >= 0.5:
                score += 8
                feedback_parts.append(f"⚠️ Only {complete_rows}/{num_subscriptions} rows complete")
            else:
                feedback_parts.append(f"❌ Only {complete_rows}/{num_subscriptions} rows complete")
        
        # Check Monthly Cost calculations
        if monthly_col and num_subscriptions > 0:
            monthly_calculations = 0
            accurate_calculations = 0
            
            for row_idx in data_rows[:min(num_subscriptions, 10)]:  # Check first 10
                monthly_value = sheet.cell(row_idx, monthly_col).value
                if monthly_value and isinstance(monthly_value, (int, float)) and monthly_value > 0:
                    monthly_calculations += 1
                    
                    # Verify accuracy if we have billing cycle and amount
                    if billing_col and amount_col:
                        billing_cycle = sheet.cell(row_idx, billing_col).value
                        charged_amount = sheet.cell(row_idx, amount_col).value
                        
                        expected = calculate_expected_monthly(charged_amount, billing_cycle)
                        if expected and abs(monthly_value - expected) < 1.0:
                            accurate_calculations += 1
            
            if monthly_calculations >= min(num_subscriptions, 4):
                score += 20
                if accurate_calculations >= min(num_subscriptions - 1, 3):
                    feedback_parts.append(f"✅ Monthly cost calculations present and accurate ({monthly_calculations} rows)")
                else:
                    feedback_parts.append(f"✅ Monthly cost calculations present ({monthly_calculations} rows)")
            elif monthly_calculations >= 2:
                score += 10
                feedback_parts.append(f"⚠️ Only {monthly_calculations} monthly cost calculations")
            else:
                feedback_parts.append("❌ Missing monthly cost calculations")
        
        # Check Annual Savings calculations
        if savings_col and monthly_col and num_subscriptions > 0:
            savings_calculations = 0
            accurate_savings = 0
            
            for row_idx in data_rows[:min(num_subscriptions, 10)]:
                savings_value = sheet.cell(row_idx, savings_col).value
                if savings_value and isinstance(savings_value, (int, float)) and savings_value > 0:
                    savings_calculations += 1
                    
                    # Check if it's approximately monthly × 12
                    monthly_value = sheet.cell(row_idx, monthly_col).value
                    if monthly_value and isinstance(monthly_value, (int, float)):
                        expected_savings = monthly_value * 12
                        if abs(savings_value - expected_savings) < 2.0:
                            accurate_savings += 1
            
            if savings_calculations >= min(num_subscriptions, 4):
                score += 15
                if accurate_savings >= min(num_subscriptions - 1, 3):
                    feedback_parts.append(f"✅ Annual savings calculated accurately ({savings_calculations} rows)")
                else:
                    feedback_parts.append(f"✅ Annual savings calculated ({savings_calculations} rows)")
            elif savings_calculations >= 2:
                score += 8
                feedback_parts.append(f"⚠️ Only {savings_calculations} annual savings calculations")
            else:
                feedback_parts.append("❌ Missing annual savings calculations")
        
        # Check for Total/Summary row with conditional logic
        found_total = False
        total_value = None
        
        # Search for total row after the data rows
        if data_rows:
            search_start = max(data_rows) + 1
            search_end = min(search_start + 10, sheet.max_row + 1)
            
            for row_idx in range(search_start, search_end):
                # Check first few columns for "total" keyword
                for col_idx in range(1, 8):
                    cell_value = sheet.cell(row_idx, col_idx).value
                    if cell_value:
                        cell_lower = str(cell_value).lower()
                        if 'total' in cell_lower or 'savings' in cell_lower or 'potential' in cell_lower:
                            # Look for a numeric value in the savings column
                            if savings_col:
                                total_candidate = sheet.cell(row_idx, savings_col).value
                                if total_candidate and isinstance(total_candidate, (int, float)) and total_candidate > 0:
                                    found_total = True
                                    total_value = total_candidate
                                    break
                if found_total:
                    break
        
        if found_total:
            score += 15
            feedback_parts.append(f"✅ Total savings summary present: ${total_value:.2f}")
            
            # Optionally verify it's summing only Low value items
            # This is hard without parsing formulas, so we'll just check reasonableness
            if value_col and savings_col and data_rows:
                low_sum = 0
                for row_idx in data_rows:
                    value_rating = sheet.cell(row_idx, value_col).value
                    if value_rating and 'low' in str(value_rating).lower():
                        savings_value = sheet.cell(row_idx, savings_col).value
                        if savings_value and isinstance(savings_value, (int, float)):
                            low_sum += savings_value
                
                # Check if total is close to low_sum (within 10% or $50)
                if low_sum > 0:
                    if abs(total_value - low_sum) < max(low_sum * 0.1, 50):
                        feedback_parts.append("✅ Total appears to sum only Low value items (conditional logic)")
                    else:
                        feedback_parts.append(f"⚠️ Total (${total_value:.2f}) doesn't match Low items sum (${low_sum:.2f})")
        else:
            feedback_parts.append("❌ Missing total savings summary row")
        
        # Final score capping
        score = min(score, 100)
        passed = score >= 70

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)
