#!/usr/bin/env python3
"""
Verifier for Symptom Pattern Analyzer task.
Validates helper columns, formulas, and summary statistics.
"""

import sys
import os
import logging
import datetime
import re

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_date(date_val):
    """Parse various date formats to datetime.date object."""
    if isinstance(date_val, datetime.date):
        return date_val
    if isinstance(date_val, datetime.datetime):
        return date_val.date()
    
    # Try parsing string formats
    if isinstance(date_val, str):
        for fmt in ["%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%d-%m-%Y"]:
            try:
                return datetime.datetime.strptime(date_val, fmt).date()
            except ValueError:
                continue
    
    return None


def calculate_expected_statistics(workbook, sheet_name):
    """
    Independently calculate expected summary statistics from raw data.
    
    Returns dict with expected values.
    """
    try:
        sheet_data = workbook['sheets'][sheet_name]
        
        dates = []
        severities = []
        
        # Parse data rows (skip header at row 0)
        for row_idx, row in enumerate(sheet_data[1:], start=1):  # Start from row 1 (second row)
            if row_idx > 20:  # Only look at first 20 data rows
                break
            
            # Date in column A (index 0)
            date_cell = row[0] if len(row) > 0 else {}
            date_val = date_cell.get('value') if isinstance(date_cell, dict) else date_cell
            
            if date_val:
                parsed_date = parse_date(date_val)
                if parsed_date:
                    dates.append(parsed_date)
                    
                    # Severity in column C (index 2)
                    if len(row) > 2:
                        severity_cell = row[2]
                        severity_val = severity_cell.get('value') if isinstance(severity_cell, dict) else severity_cell
                        
                        if severity_val not in [None, '', ' ']:
                            try:
                                severities.append(float(severity_val))
                            except (ValueError, TypeError):
                                pass
        
        if not dates:
            return None
        
        # Calculate metrics
        total_episodes = len(dates)
        avg_severity = sum(severities) / len(severities) if severities else 0
        days_covered = (max(dates) - min(dates)).days if len(dates) > 1 else 0
        
        # Calculate intervals between consecutive dates
        sorted_dates = sorted(dates)
        intervals = []
        for i in range(1, len(sorted_dates)):
            interval = (sorted_dates[i] - sorted_dates[i-1]).days
            if interval > 0:  # Exclude zero intervals (same day)
                intervals.append(interval)
        
        avg_days_between = sum(intervals) / len(intervals) if intervals else 0
        
        # Weekend counting
        weekend_count = sum(1 for d in dates if d.weekday() >= 5)  # Sat=5, Sun=6
        weekday_count = len(dates) - weekend_count
        
        return {
            'total_episodes': total_episodes,
            'avg_severity': avg_severity,
            'days_covered': days_covered,
            'avg_days_between': avg_days_between,
            'weekend_count': weekend_count,
            'weekday_count': weekday_count,
        }
        
    except Exception as e:
        logger.error(f"Error calculating expected statistics: {e}", exc_info=True)
        return None


def check_column_exists(workbook, sheet_name, header_text, start_col='F'):
    """
    Check if a column with given header exists.
    
    Returns (column_letter, row_count) or (None, 0) if not found.
    """
    try:
        sheet_data = workbook['sheets'][sheet_name]
        header_row = sheet_data[0] if sheet_data else []
        
        # Check columns F, G, H, I, J for the header
        col_mapping = {'F': 5, 'G': 6, 'H': 7, 'I': 8, 'J': 9, 'K': 10, 'L': 11}
        
        for col_letter, col_idx in col_mapping.items():
            if col_idx < len(header_row):
                cell = header_row[col_idx]
                cell_value = cell.get('value') if isinstance(cell, dict) else cell
                
                if cell_value and isinstance(cell_value, str):
                    # Flexible matching (normalize spaces, case)
                    normalized_header = header_text.lower().replace('_', ' ').replace('-', ' ')
                    normalized_cell = cell_value.lower().replace('_', ' ').replace('-', ' ')
                    
                    if normalized_header in normalized_cell or normalized_cell in normalized_header:
                        # Count non-empty cells in this column
                        non_empty = 0
                        for row in sheet_data[1:15]:  # Check first 14 data rows
                            if col_idx < len(row):
                                val = row[col_idx].get('value') if isinstance(row[col_idx], dict) else row[col_idx]
                                if val not in [None, '', ' ']:
                                    non_empty += 1
                        
                        return col_letter, non_empty
        
        return None, 0
        
    except Exception as e:
        logger.error(f"Error checking column: {e}", exc_info=True)
        return None, 0


def check_formula_usage(workbook, sheet_name, cell_ref):
    """Check if a cell contains a formula (not just a value)."""
    formula = get_cell_formula(workbook, sheet_name, cell_ref)
    if formula and formula.strip().startswith('='):
        return True
    return False


def find_summary_statistics(workbook, sheet_name):
    """
    Search for summary statistics in the spreadsheet.
    
    Returns dict with found values and their cell references.
    """
    try:
        sheet_data = workbook['sheets'][sheet_name]
        
        summary_stats = {
            'total_episodes': None,
            'avg_severity': None,
            'days_covered': None,
            'avg_days_between': None,
            'weekend_count': None,
            'weekday_count': None,
        }
        
        # Search through cells for summary statistics
        # Typically would be below data, so start from row 15+
        for row_idx in range(14, min(40, len(sheet_data))):
            row = sheet_data[row_idx] if row_idx < len(sheet_data) else []
            
            for col_idx in range(10):  # Check first 10 columns
                if col_idx >= len(row):
                    continue
                
                label_cell = row[col_idx]
                label_val = label_cell.get('value') if isinstance(label_cell, dict) else label_cell
                
                if not label_val or not isinstance(label_val, str):
                    continue
                
                label_lower = label_val.lower()
                
                # Check next cell for value
                value_col_idx = col_idx + 1
                if value_col_idx >= len(row):
                    continue
                
                value_cell = row[value_col_idx]
                value_val = value_cell.get('value') if isinstance(value_cell, dict) else value_cell
                
                # Match labels to metrics
                if 'total' in label_lower and 'episode' in label_lower:
                    summary_stats['total_episodes'] = value_val
                elif 'average' in label_lower and 'severity' in label_lower:
                    summary_stats['avg_severity'] = value_val
                elif 'days' in label_lower and 'covered' in label_lower:
                    summary_stats['days_covered'] = value_val
                elif 'average' in label_lower and ('between' in label_lower or 'interval' in label_lower):
                    summary_stats['avg_days_between'] = value_val
                elif 'weekend' in label_lower and ('count' in label_lower or 'episode' in label_lower):
                    summary_stats['weekend_count'] = value_val
                elif 'weekday' in label_lower and ('count' in label_lower or 'episode' in label_lower):
                    summary_stats['weekday_count'] = value_val
        
        return summary_stats
        
    except Exception as e:
        logger.error(f"Error finding summary statistics: {e}", exc_info=True)
        return {}


def verify_symptom_analyzer(traj, env_info, task_info):
    """
    Verify symptom pattern analyzer task completion.
    
    Checks:
    1. Day_of_Week column present with formulas
    2. Days_Since_Last column present with calculations
    3. Is_Weekend column present with classification
    4. Summary statistics accurate (within tolerance)
    5. Formulas used (not hardcoded values)
    6. Original data preserved
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/symptom_log.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get sheet name
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        
        # Criterion 1: Day_of_Week column exists
        day_col, day_count = check_column_exists(workbook, sheet_name, "Day_of_Week")
        if day_col and day_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Day_of_Week column present ({day_count} entries)")
        else:
            feedback_parts.append("❌ Day_of_Week column missing or incomplete")
        
        # Criterion 2: Days_Since_Last column exists
        interval_col, interval_count = check_column_exists(workbook, sheet_name, "Days_Since_Last")
        if interval_col and interval_count >= 4:  # First row will be blank/N/A
            criteria_passed += 1
            feedback_parts.append(f"✅ Days_Since_Last column present ({interval_count} entries)")
        else:
            feedback_parts.append("❌ Days_Since_Last column missing or incomplete")
        
        # Criterion 3: Is_Weekend column exists
        weekend_col, weekend_count = check_column_exists(workbook, sheet_name, "Is_Weekend")
        if weekend_col and weekend_count >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Is_Weekend column present ({weekend_count} entries)")
        else:
            feedback_parts.append("❌ Is_Weekend column missing or incomplete")
        
        # Calculate expected statistics independently
        expected_stats = calculate_expected_statistics(workbook, sheet_name)
        
        # Find summary statistics in spreadsheet
        found_stats = find_summary_statistics(workbook, sheet_name)
        
        # Criterion 4: Summary statistics accurate
        stats_correct = 0
        stats_total = 0
        
        if expected_stats and found_stats:
            tolerance_map = {
                'total_episodes': 0,  # Exact match
                'avg_severity': 0.5,  # 0.5 tolerance
                'days_covered': 1,  # 1 day tolerance
                'avg_days_between': 0.5,  # 0.5 day tolerance
                'weekend_count': 0,  # Exact match
                'weekday_count': 0,  # Exact match
            }
            
            for key, expected_val in expected_stats.items():
                if expected_val is None:
                    continue
                
                found_val = found_stats.get(key)
                if found_val is None:
                    continue
                
                stats_total += 1
                
                try:
                    tolerance = tolerance_map.get(key, 0.1)
                    if abs(float(found_val) - float(expected_val)) <= tolerance:
                        stats_correct += 1
                except (ValueError, TypeError):
                    pass
            
            if stats_total > 0 and stats_correct >= stats_total * 0.7:  # 70% of stats correct
                criteria_passed += 1
                feedback_parts.append(f"✅ Summary statistics accurate ({stats_correct}/{stats_total} metrics)")
            else:
                feedback_parts.append(f"❌ Summary statistics inaccurate or missing ({stats_correct}/{stats_total} correct)")
        else:
            feedback_parts.append("❌ Could not verify summary statistics")
        
        # Criterion 5: Formulas used (check a few summary cells for formulas)
        formulas_found = 0
        formulas_checked = 0
        
        # Check cells in summary area for formulas
        sheet_data = workbook['sheets'][sheet_name]
        for row_idx in range(14, min(30, len(sheet_data))):
            row = sheet_data[row_idx] if row_idx < len(sheet_data) else []
            for col_idx in range(10):
                if col_idx >= len(row):
                    continue
                
                cell = row[col_idx]
                cell_val = cell.get('value') if isinstance(cell, dict) else cell
                cell_formula = cell.get('formula') if isinstance(cell, dict) else None
                
                # If cell has a numeric value, check if it has a formula
                if cell_val is not None and isinstance(cell_val, (int, float)):
                    formulas_checked += 1
                    if cell_formula and '=' in str(cell_formula):
                        formulas_found += 1
        
        if formulas_checked > 0 and formulas_found >= 3:  # At least 3 formulas found
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas used in calculations ({formulas_found} found)")
        else:
            feedback_parts.append(f"⚠️ Few or no formulas detected ({formulas_found}/{formulas_checked})")
        
        # Criterion 6: Original data preserved (check first data row)
        original_preserved = True
        first_data_row = sheet_data[1] if len(sheet_data) > 1 else []
        
        # Check that first 5 columns (A-E) have data
        if len(first_data_row) >= 5:
            for col_idx in range(5):
                cell = first_data_row[col_idx]
                val = cell.get('value') if isinstance(cell, dict) else cell
                if val is None or val == '':
                    original_preserved = False
                    break
        else:
            original_preserved = False
        
        if original_preserved:
            criteria_passed += 1
            feedback_parts.append("✅ Original data columns preserved")
        else:
            feedback_parts.append("❌ Original data may be corrupted or missing")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold (4/6 criteria)
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "day_of_week_column": day_count >= 5 if day_col else False,
                "days_since_last_column": interval_count >= 4 if interval_col else False,
                "is_weekend_column": weekend_count >= 5 if weekend_col else False,
                "summary_stats_accurate": stats_correct >= stats_total * 0.7 if stats_total > 0 else False,
                "formulas_used": formulas_found >= 3,
                "data_preserved": original_preserved,
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(temp_dir)
