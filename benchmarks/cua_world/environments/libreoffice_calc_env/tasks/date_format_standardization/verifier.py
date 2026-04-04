#!/usr/bin/env python3
"""
Verifier for Date Format Standardization task.
Checks that all dates are converted to YYYY-MM-DD format with proper validation.
"""

import sys
import os
import re
import logging
from datetime import datetime
from typing import Tuple, List, Dict, Any

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_date_standardization(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify that all dates are standardized to YYYY-MM-DD format.
    
    Checks:
    1. All dates match YYYY-MM-DD regex pattern (ISO format)
    2. All dates are valid and parsable
    3. Dates follow reasonable chronological progression
    4. No data loss (row count maintained)
    5. Correct value interpretation (no month/day swaps)
    
    Args:
        traj: Trajectory information (unused)
        env_info: Environment info with copy_from_env function
        task_info: Task information (unused)
    
    Returns:
        Dict with passed, score, feedback, and subscores
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    # Try multiple possible file locations and formats
    temp_dir = None
    success = False
    workbook = None
    
    for file_format, file_path in [
        ('ods', '/home/ga/Documents/sales_data_standardized.ods'),
        ('csv', '/home/ga/Documents/sales_data_standardized.csv'),
        ('ods', '/home/ga/Documents/sales_data_mixed.ods'),
        ('csv', '/home/ga/Documents/sales_data_mixed.csv'),
    ]:
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            file_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {file_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook.get('sheets', {}).keys())
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        sheet_name = sheet_names[0]
        sheet_data = workbook['sheets'][sheet_name]
        
        # Analyze dates in Column A (index 0)
        result = analyze_date_column(sheet_data, date_column_index=0)
        
        # Calculate final score
        score = result['score']
        passed = score >= 75
        
        # Generate feedback
        feedback_parts = []
        
        # Criterion 1: ISO Format
        if result['iso_format_count'] == result['total_dates']:
            feedback_parts.append(f"✅ All dates in ISO format ({result['total_dates']}/{result['total_dates']})")
        else:
            feedback_parts.append(f"❌ Not all dates in ISO format ({result['iso_format_count']}/{result['total_dates']})")
        
        # Criterion 2: Valid Dates
        if result['valid_dates'] == result['total_dates']:
            feedback_parts.append(f"✅ All dates valid ({result['valid_dates']}/{result['total_dates']})")
        else:
            feedback_parts.append(f"⚠️  Some invalid dates ({result['valid_dates']}/{result['total_dates']})")
        
        # Criterion 3: Chronological Logic
        if result['chronological_score'] >= 90:
            feedback_parts.append(f"✅ Chronological logic good ({result['chronological_score']:.0f}%)")
        elif result['chronological_score'] >= 70:
            feedback_parts.append(f"⚠️  Minor chronological issues ({result['chronological_score']:.0f}%)")
        else:
            feedback_parts.append(f"❌ Chronological problems detected ({result['chronological_score']:.0f}%)")
        
        # Criterion 4: Data Completeness
        if result['total_dates'] >= 20:
            feedback_parts.append(f"✅ All rows preserved ({result['total_dates']} dates)")
        else:
            feedback_parts.append(f"⚠️  Missing data ({result['total_dates']} dates, expected 20+)")
        
        # Add error details if present
        if result['errors'] and len(result['errors']) <= 3:
            feedback_parts.append(f"Issues: {'; '.join(result['errors'][:3])}")
        elif result['errors']:
            feedback_parts.append(f"{len(result['errors'])} issues detected (first 3 shown)")
            for error in result['errors'][:3]:
                feedback_parts.append(f"  • {error}")
        
        # Success message
        if passed and score >= 95:
            feedback_parts.append("🎉 Excellent date standardization!")
        elif passed:
            feedback_parts.append("✅ Date standardization completed")
        else:
            feedback_parts.append("❌ Date standardization incomplete")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "all_iso_format": result['iso_format_count'] == result['total_dates'],
                "all_valid_dates": result['valid_dates'] == result['total_dates'],
                "chronological_logic": result['chronological_score'] >= 70,
                "data_preserved": result['total_dates'] >= 20,
                "format_percentage": (result['iso_format_count'] / max(result['total_dates'], 1)) * 100,
                "validity_percentage": (result['valid_dates'] / max(result['total_dates'], 1)) * 100
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
        if temp_dir:
            cleanup_verification_temp(temp_dir)


def analyze_date_column(sheet_data: List[List], date_column_index: int = 0) -> Dict[str, Any]:
    """
    Analyze date column for format consistency, validity, and chronological logic.
    
    Args:
        sheet_data: List of rows from parsed sheet
        date_column_index: Index of the date column (default 0 for Column A)
    
    Returns:
        Dict with analysis results including score, counts, and errors
    """
    # ISO date pattern: YYYY-MM-DD
    iso_pattern = re.compile(r'^\d{4}-\d{2}-\d{2}$')
    
    total_dates = 0
    iso_format_count = 0
    valid_dates = 0
    date_values: List[Tuple[int, datetime, str]] = []  # (row_num, date_obj, date_str)
    errors: List[str] = []
    
    # Skip header row (row 0)
    for row_idx, row in enumerate(sheet_data[1:], start=2):
        if date_column_index >= len(row):
            continue
        
        cell = row[date_column_index]
        value = cell.get('value') if isinstance(cell, dict) else cell
        
        # Skip empty cells
        if value is None or str(value).strip() == '':
            continue
        
        total_dates += 1
        value_str = str(value).strip()
        
        # Check if matches ISO format pattern
        if iso_pattern.match(value_str):
            iso_format_count += 1
            
            # Verify it's a valid date
            try:
                date_obj = datetime.strptime(value_str, '%Y-%m-%d')
                
                # Additional validation: check reasonable year range
                if 2020 <= date_obj.year <= 2025:
                    valid_dates += 1
                    date_values.append((row_idx, date_obj, value_str))
                else:
                    errors.append(f"Row {row_idx}: Date year out of expected range ({value_str})")
            
            except ValueError as e:
                errors.append(f"Row {row_idx}: Invalid date '{value_str}' ({str(e)})")
        else:
            # Not in ISO format
            errors.append(f"Row {row_idx}: Non-ISO format '{value_str}'")
            
            # Try to parse it anyway to see if it's a valid date in wrong format
            try:
                # Try common formats
                for fmt in ['%m/%d/%Y', '%d-%m-%Y', '%d/%m/%Y', '%Y/%m/%d']:
                    try:
                        date_obj = datetime.strptime(value_str, fmt)
                        # Don't count as valid since it's not in correct format
                        break
                    except ValueError:
                        continue
            except:
                pass
    
    # Calculate metrics
    if total_dates == 0:
        return {
            'score': 0,
            'total_dates': 0,
            'iso_format_count': 0,
            'valid_dates': 0,
            'chronological_score': 0,
            'errors': ['No dates found in spreadsheet'],
            'date_values': []
        }
    
    format_score = (iso_format_count / total_dates) * 100
    validity_score = (valid_dates / total_dates) * 100
    
    # Check chronological logic
    chronological_score = 100
    chronological_errors = []
    
    if len(date_values) > 1:
        major_reversals = 0
        minor_issues = 0
        
        for i in range(len(date_values) - 1):
            curr_row, curr_date, curr_str = date_values[i]
            next_row, next_date, next_str = date_values[i + 1]
            
            days_diff = (next_date - curr_date).days
            
            # Major reversal: more than 30 days backward
            if days_diff < -30:
                major_reversals += 1
                chronological_errors.append(
                    f"Major reversal between rows {curr_row} and {next_row}: "
                    f"{curr_str} → {next_str} ({days_diff} days)"
                )
            # Minor issue: small backward jump (might indicate month/day swap)
            elif days_diff < -5:
                minor_issues += 1
                chronological_errors.append(
                    f"Minor reversal between rows {curr_row} and {next_row}: "
                    f"{curr_str} → {next_str} ({days_diff} days)"
                )
        
        # Penalize major reversals heavily, minor issues less so
        chronological_score = max(0, 100 - (major_reversals * 30) - (minor_issues * 10))
        
        # Add chronological errors to main error list (limited)
        errors.extend(chronological_errors[:3])
    
    # Composite score with weighted components
    # Format: 50%, Validity: 30%, Chronological: 20%
    final_score = (format_score * 0.5) + (validity_score * 0.3) + (chronological_score * 0.2)
    
    return {
        'score': final_score,
        'total_dates': total_dates,
        'iso_format_count': iso_format_count,
        'valid_dates': valid_dates,
        'chronological_score': chronological_score,
        'format_score': format_score,
        'validity_score': validity_score,
        'errors': errors,
        'date_values': date_values
    }
