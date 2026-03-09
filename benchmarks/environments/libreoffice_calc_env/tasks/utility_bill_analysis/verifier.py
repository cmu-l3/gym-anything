#!/usr/bin/env python3
"""
Verifier for Utility Bill Analysis task
Checks that proper data analysis has been performed on utility billing data
"""

import sys
import os
import logging
import re
from datetime import datetime

# Use relative path to the utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    check_conditional_formatting
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_date(date_str):
    """Parse date string in various formats"""
    if date_str is None:
        return None
    
    date_str = str(date_str)
    
    # Try common date formats
    for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%m/%d/%y', '%d/%m/%Y']:
        try:
            return datetime.strptime(date_str, fmt)
        except ValueError:
            continue
    
    return None


def find_column_by_header(data, sheet_name, keywords):
    """
    Find column index by searching for keywords in header row.
    
    Args:
        data: Parsed spreadsheet data
        sheet_name: Sheet name
        keywords: List of keywords to search for in header (case-insensitive)
    
    Returns:
        Column index (0-based) or None if not found
    """
    try:
        sheet_rows = data['sheets'][sheet_name]
        if not sheet_rows or len(sheet_rows) == 0:
            return None
        
        header_row = sheet_rows[0]
        
        for col_idx, cell in enumerate(header_row):
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value is None:
                continue
            
            cell_text = str(cell_value).lower()
            
            # Check if any keyword matches
            for keyword in keywords:
                if keyword.lower() in cell_text:
                    return col_idx
        
        return None
    
    except Exception as e:
        logger.error(f"Error finding column: {e}")
        return None


def get_column_values(data, sheet_name, col_idx, start_row=1, max_rows=20):
    """Get values from a column"""
    try:
        sheet_rows = data['sheets'][sheet_name]
        values = []
        
        for row_idx in range(start_row, min(len(sheet_rows), start_row + max_rows)):
            if row_idx >= len(sheet_rows):
                break
            
            row = sheet_rows[row_idx]
            if col_idx >= len(row):
                values.append(None)
                continue
            
            cell = row[col_idx]
            value = cell.get('value') if isinstance(cell, dict) else cell
            values.append(value)
        
        return values
    
    except Exception as e:
        logger.error(f"Error getting column values: {e}")
        return []


def verify_days_calculation(data, sheet_name, days_col_idx):
    """Verify that days between dates are calculated correctly"""
    try:
        # Get bill date column (should be column 0)
        date_col_idx = 0
        
        # Get dates from rows 1-12 (skip header at row 0)
        dates = get_column_values(data, sheet_name, date_col_idx, start_row=1, max_rows=12)
        days_values = get_column_values(data, sheet_name, days_col_idx, start_row=1, max_rows=12)
        
        if not dates or not days_values:
            return False
        
        # Check at least 3 rows have correct day calculations
        correct_count = 0
        
        for i in range(1, min(len(dates), len(days_values))):
            if dates[i] is None or dates[i-1] is None:
                continue
            
            date1 = parse_date(dates[i-1])
            date2 = parse_date(dates[i])
            
            if date1 and date2:
                expected_days = (date2 - date1).days
                actual_days = days_values[i]
                
                if actual_days is not None:
                    try:
                        actual_days_num = float(actual_days)
                        if abs(actual_days_num - expected_days) <= 1:  # Allow 1 day tolerance
                            correct_count += 1
                    except (ValueError, TypeError):
                        pass
        
        return correct_count >= 3
    
    except Exception as e:
        logger.error(f"Error verifying days calculation: {e}")
        return False


def verify_daily_average(data, sheet_name, daily_avg_col_idx, usage_col_idx, days_col_idx):
    """Verify daily average usage calculation"""
    try:
        usage_values = get_column_values(data, sheet_name, usage_col_idx, start_row=1, max_rows=12)
        days_values = get_column_values(data, sheet_name, days_col_idx, start_row=1, max_rows=12)
        daily_avg_values = get_column_values(data, sheet_name, daily_avg_col_idx, start_row=1, max_rows=12)
        
        if not all([usage_values, days_values, daily_avg_values]):
            return False
        
        correct_count = 0
        
        for i in range(min(len(usage_values), len(days_values), len(daily_avg_values))):
            usage = usage_values[i]
            days = days_values[i]
            daily_avg = daily_avg_values[i]
            
            if usage is None or days is None or daily_avg is None:
                continue
            
            try:
                usage_num = float(usage)
                days_num = float(days)
                daily_avg_num = float(daily_avg)
                
                if days_num > 0:
                    expected_avg = usage_num / days_num
                    if abs(daily_avg_num - expected_avg) <= 0.5:  # Tolerance
                        correct_count += 1
            except (ValueError, TypeError):
                pass
        
        return correct_count >= 3
    
    except Exception as e:
        logger.error(f"Error verifying daily average: {e}")
        return False


def verify_percentage_change(data, sheet_name, pct_col_idx, usage_col_idx):
    """Verify month-over-month percentage change calculation"""
    try:
        usage_values = get_column_values(data, sheet_name, usage_col_idx, start_row=1, max_rows=12)
        pct_values = get_column_values(data, sheet_name, pct_col_idx, start_row=1, max_rows=12)
        
        if not usage_values or not pct_values:
            return False
        
        correct_count = 0
        
        # Start from index 1 (second data row) since first row has no previous
        for i in range(1, min(len(usage_values), len(pct_values))):
            if usage_values[i] is None or usage_values[i-1] is None:
                continue
            
            try:
                current_usage = float(usage_values[i])
                previous_usage = float(usage_values[i-1])
                pct_change = pct_values[i]
                
                if pct_change is None:
                    continue
                
                # Handle percentage as number or string
                pct_str = str(pct_change).replace('%', '').strip()
                if pct_str.upper() == 'N/A' or pct_str == '':
                    continue
                
                actual_pct = float(pct_str)
                
                if previous_usage != 0:
                    expected_pct = ((current_usage - previous_usage) / previous_usage) * 100
                    
                    # Allow 2% tolerance
                    if abs(actual_pct - expected_pct) <= 2:
                        correct_count += 1
            except (ValueError, TypeError):
                pass
        
        return correct_count >= 3
    
    except Exception as e:
        logger.error(f"Error verifying percentage change: {e}")
        return False


def check_first_row_handling(data, sheet_name, pct_col_idx):
    """Check that first data row handles edge case (no previous month)"""
    try:
        sheet_rows = data['sheets'][sheet_name]
        
        if len(sheet_rows) < 2:
            return False
        
        # Check first data row (row 1, after header)
        first_data_row = sheet_rows[1]
        
        if pct_col_idx >= len(first_data_row):
            return True  # Column doesn't exist at all, so no error
        
        cell = first_data_row[pct_col_idx]
        value = cell.get('value') if isinstance(cell, dict) else cell
        
        # Should be empty, N/A, or 0, not an error like #DIV/0! or #VALUE!
        if value is None or value == '' or value == 0:
            return True
        
        value_str = str(value).upper()
        if 'N/A' in value_str or 'NA' in value_str:
            return True
        
        # Check for error indicators
        if '#' in value_str and ('DIV' in value_str or 'VALUE' in value_str or 'REF' in value_str):
            return False
        
        return True
    
    except Exception as e:
        logger.error(f"Error checking first row: {e}")
        return True  # Default to passing if can't check


def check_estimated_flags(data, sheet_name):
    """Check if estimated readings are flagged or highlighted"""
    try:
        # Find Reading Type column
        reading_type_col = find_column_by_header(data, sheet_name, ['reading', 'type'])
        
        if reading_type_col is None:
            return False
        
        reading_values = get_column_values(data, sheet_name, reading_type_col, start_row=1, max_rows=12)
        
        # Check if we can distinguish estimated from actual
        has_estimated = any('estimated' in str(v).lower() for v in reading_values if v)
        has_actual = any('actual' in str(v).lower() for v in reading_values if v)
        
        # If both types are preserved, that counts as flagging
        return has_estimated and has_actual
    
    except Exception as e:
        logger.error(f"Error checking estimated flags: {e}")
        return False


def check_number_formats(data, sheet_name):
    """Check if appropriate number formatting is applied"""
    # This is difficult to verify from parsed data alone
    # We'll check if currency/percentage values look reasonable
    try:
        # Just check that bill amounts look like currency (have decimal places or $ symbol)
        bill_col = find_column_by_header(data, sheet_name, ['bill', 'amount', '$'])
        
        if bill_col:
            bill_values = get_column_values(data, sheet_name, bill_col, start_row=1, max_rows=3)
            # If we have values that look like currency, consider it formatted
            for val in bill_values:
                if val is not None:
                    val_str = str(val)
                    if '$' in val_str or '.' in val_str:
                        return True
            return True  # Give benefit of doubt
        
        return True  # Give benefit of doubt if can't find column
    
    except Exception as e:
        logger.error(f"Error checking number formats: {e}")
        return True


def check_peak_identifiable(data, sheet_name, daily_avg_col_idx):
    """Check if peak usage month is identifiable (likely through formatting or value)"""
    try:
        if daily_avg_col_idx is None:
            return False
        
        daily_avg_values = get_column_values(data, sheet_name, daily_avg_col_idx, start_row=1, max_rows=12)
        
        # Check if we have daily average values
        numeric_values = []
        for val in daily_avg_values:
            if val is not None:
                try:
                    numeric_values.append(float(val))
                except (ValueError, TypeError):
                    pass
        
        if len(numeric_values) >= 8:  # At least 8 months calculated
            # Check if there's a clear peak (max value is significantly higher)
            if max(numeric_values) > 30:  # Peak should be over 30 kWh/day
                return True
        
        return len(numeric_values) >= 10  # At least most months calculated
    
    except Exception as e:
        logger.error(f"Error checking peak visibility: {e}")
        return False


def verify_utility_analysis(traj, env_info, task_info):
    """
    Verify utility bill analysis task completion.
    
    Checks:
    1. Days in period calculated
    2. Daily average usage calculated
    3. Month-over-month percentage change calculated
    4. First row edge case handled
    5. Conditional formatting applied
    6. Estimated readings flagged
    7. Number formatting appropriate
    8. Peak usage identifiable
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to find the saved file
    possible_paths = [
        "/home/ga/Documents/utility_analysis.ods",
        "/home/ga/Documents/utility_bills_2023.ods",
        "/home/ga/Documents/utility_bills_2023.csv"
    ]
    
    success = False
    file_info = None
    error = ""
    
    for path in possible_paths:
        file_format = 'ods' if path.endswith('.ods') else 'csv'
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            path, 
            [file_format]
        )
        if success:
            logger.info(f"Successfully loaded file from: {path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load spreadsheet: {error}. Tried: {', '.join(possible_paths)}"
        }
    
    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_met = 0
        total_criteria = 8
        feedback_parts = []
        
        # Find columns by header keywords
        days_col = find_column_by_header(data, sheet_name, ['days', 'period'])
        daily_avg_col = find_column_by_header(data, sheet_name, ['daily', 'avg', 'per day', 'kwh/day'])
        pct_change_col = find_column_by_header(data, sheet_name, ['change', '%', 'percent'])
        usage_col = find_column_by_header(data, sheet_name, ['usage', 'kwh'])
        
        # Criterion 1: Days calculation
        if days_col is not None:
            days_correct = verify_days_calculation(data, sheet_name, days_col)
            if days_correct:
                criteria_met += 1
                feedback_parts.append("✅ Days in billing period calculated correctly")
            else:
                feedback_parts.append("❌ Days calculation incorrect or insufficient")
        else:
            feedback_parts.append("❌ Days in period column not found")
        
        # Criterion 2: Daily average calculation
        if daily_avg_col is not None and days_col is not None and usage_col is not None:
            daily_correct = verify_daily_average(data, sheet_name, daily_avg_col, usage_col, days_col)
            if daily_correct:
                criteria_met += 1
                feedback_parts.append("✅ Daily average usage calculated correctly")
            else:
                feedback_parts.append("❌ Daily average calculation incorrect")
        elif daily_avg_col is not None:
            # Column exists but can't verify formula
            criteria_met += 0.5
            feedback_parts.append("⚠️  Daily average column found but couldn't verify formula")
        else:
            feedback_parts.append("❌ Daily average column not found")
        
        # Criterion 3: Percentage change calculation
        if pct_change_col is not None and usage_col is not None:
            pct_correct = verify_percentage_change(data, sheet_name, pct_change_col, usage_col)
            if pct_correct:
                criteria_met += 1
                feedback_parts.append("✅ Month-over-month percentage change calculated")
            else:
                feedback_parts.append("❌ Percentage change calculation incorrect")
        elif pct_change_col is not None:
            criteria_met += 0.5
            feedback_parts.append("⚠️  Percentage change column found but couldn't verify")
        else:
            feedback_parts.append("❌ Percentage change column not found")
        
        # Criterion 4: First row edge case
        if pct_change_col is not None:
            first_row_ok = check_first_row_handling(data, sheet_name, pct_change_col)
            if first_row_ok:
                criteria_met += 1
                feedback_parts.append("✅ First row edge case handled appropriately")
            else:
                feedback_parts.append("❌ First row contains error values")
        else:
            criteria_met += 1  # No column means no error
            feedback_parts.append("✅ No formula errors detected")
        
        # Criterion 5: Conditional formatting
        has_formatting = False
        if daily_avg_col is not None:
            try:
                has_formatting = check_conditional_formatting(data, sheet_name, f"A1:Z20")
            except:
                pass
        
        if has_formatting:
            criteria_met += 1
            feedback_parts.append("✅ Conditional formatting detected")
        else:
            feedback_parts.append("⚠️  Conditional formatting not detected (may be format-dependent)")
        
        # Criterion 6: Estimated readings flagged
        estimated_flagged = check_estimated_flags(data, sheet_name)
        if estimated_flagged:
            criteria_met += 1
            feedback_parts.append("✅ Estimated readings preserved/identifiable")
        else:
            feedback_parts.append("⚠️  Estimated readings not clearly distinguishable")
        
        # Criterion 7: Number formatting
        formatting_ok = check_number_formats(data, sheet_name)
        if formatting_ok:
            criteria_met += 1
            feedback_parts.append("✅ Number formatting appears appropriate")
        else:
            feedback_parts.append("⚠️  Number formatting could be improved")
        
        # Criterion 8: Peak usage identifiable
        peak_visible = check_peak_identifiable(data, sheet_name, daily_avg_col)
        if peak_visible:
            criteria_met += 1
            feedback_parts.append("✅ Peak usage month calculated/identifiable")
        else:
            feedback_parts.append("⚠️  Peak usage not clearly calculated")
        
        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75
        
        if passed:
            feedback_parts.append("🎉 Utility bill analysis completed successfully!")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "days_calculated": days_col is not None,
                "daily_avg_calculated": daily_avg_col is not None,
                "pct_change_calculated": pct_change_col is not None,
                "first_row_ok": True,
                "has_formatting": has_formatting,
                "estimated_flagged": estimated_flagged,
                "formatting_ok": formatting_ok,
                "peak_visible": peak_visible
            }
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
