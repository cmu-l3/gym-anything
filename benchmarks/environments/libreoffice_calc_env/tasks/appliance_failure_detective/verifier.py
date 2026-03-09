#!/usr/bin/env python3
"""
Verifier for Appliance Failure Detective task.
Validates data cleaning, statistical analysis, and pattern identification.
"""

import sys
import os
import logging
from datetime import datetime
from typing import Dict, List, Tuple, Any, Optional

# Use relative path to utils folder (runs on host, not container)
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


def parse_date_flexible(date_str: str) -> Optional[datetime]:
    """
    Parse dates in various formats.
    
    Args:
        date_str: Date string in various formats
        
    Returns:
        datetime object or None if parsing fails
    """
    if not date_str:
        return None
    
    date_str = str(date_str).strip()
    
    # Try multiple date formats
    formats = [
        '%m/%d/%Y',     # 3/15/2024
        '%m/%d/%y',     # 03/16/24
        '%m-%d-%Y',     # 3-17-2024
        '%B %d %Y',     # March 19 2024
        '%Y-%m-%d',     # 2024-03-15
        '%d/%m/%Y',     # 15/03/2024
        '%d-%m-%Y',     # 15-03-2024
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except (ValueError, TypeError):
            continue
    
    return None


def extract_raw_data(workbook: Dict, sheet_name: str) -> List[Dict[str, Any]]:
    """
    Extract raw failure log data from spreadsheet.
    
    Returns:
        List of row dictionaries with keys: date, cycle_type, load_size, water_temp, drainage_success
    """
    rows = workbook['sheets'][sheet_name]
    data = []
    
    # Find header row (look for "Cycle Type" or "Date" columns)
    header_row_idx = None
    date_col = cycle_col = load_col = temp_col = drainage_col = None
    
    for idx, row in enumerate(rows[:10]):  # Check first 10 rows
        row_values = [str(cell.get('value', '') if isinstance(cell, dict) else cell).lower() 
                     for cell in row]
        
        if 'date' in row_values:
            header_row_idx = idx
            date_col = row_values.index('date')
            
            # Find other columns
            if 'cycle type' in row_values or 'cycle' in row_values:
                cycle_col = next((i for i, v in enumerate(row_values) if 'cycle' in v), None)
            if 'load size' in row_values or 'load' in row_values:
                load_col = next((i for i, v in enumerate(row_values) if 'load' in v), None)
            if 'water temp' in row_values or 'temp' in row_values:
                temp_col = next((i for i, v in enumerate(row_values) 
                               if 'temp' in v or 'water' in v), None)
            if 'drainage success' in row_values or 'drainage' in row_values or 'success' in row_values:
                drainage_col = next((i for i, v in enumerate(row_values) 
                                   if 'drainage' in v or 'success' in v), None)
            break
    
    if header_row_idx is None or date_col is None:
        logger.warning("Could not find header row or date column")
        return []
    
    # Extract data rows
    for row in rows[header_row_idx + 1:]:
        if len(row) <= max(filter(None, [date_col, cycle_col, load_col, temp_col, drainage_col])):
            continue
        
        date_val = row[date_col].get('value', '') if isinstance(row[date_col], dict) else row[date_col]
        
        if not date_val or date_val == '':
            continue
        
        row_data = {
            'date': str(date_val),
            'cycle_type': str(row[cycle_col].get('value', '') if isinstance(row[cycle_col], dict) 
                            else row[cycle_col]) if cycle_col is not None else '',
            'load_size': str(row[load_col].get('value', '') if isinstance(row[load_col], dict) 
                           else row[load_col]) if load_col is not None else '',
            'water_temp': str(row[temp_col].get('value', '') if isinstance(row[temp_col], dict) 
                            else row[temp_col]) if temp_col is not None else '',
            'drainage_success': str(row[drainage_col].get('value', '') if isinstance(row[drainage_col], dict) 
                                  else row[drainage_col]) if drainage_col is not None else ''
        }
        
        data.append(row_data)
    
    return data


def calculate_expected_failure_rates(raw_data: List[Dict]) -> Dict[str, Dict[str, float]]:
    """
    Calculate expected failure rates from raw data.
    
    Returns:
        Dict with categories and their failure rates
    """
    rates = {}
    
    # Calculate by Cycle Type
    cycle_counts = {'Normal': [0, 0], 'Heavy': [0, 0], 'Quick': [0, 0]}  # [total, failures]
    for row in raw_data:
        cycle = row['cycle_type'].strip()
        if cycle in cycle_counts:
            cycle_counts[cycle][0] += 1
            if row['drainage_success'].strip().lower() in ['no', 'n', 'false', '0']:
                cycle_counts[cycle][1] += 1
    
    rates['cycle_type'] = {
        k: (v[1] / v[0] * 100 if v[0] > 0 else 0) 
        for k, v in cycle_counts.items()
    }
    
    # Calculate by Load Size
    load_counts = {'Light': [0, 0], 'Medium': [0, 0], 'Full': [0, 0]}
    for row in raw_data:
        load = row['load_size'].strip()
        if load in load_counts:
            load_counts[load][0] += 1
            if row['drainage_success'].strip().lower() in ['no', 'n', 'false', '0']:
                load_counts[load][1] += 1
    
    rates['load_size'] = {
        k: (v[1] / v[0] * 100 if v[0] > 0 else 0) 
        for k, v in load_counts.items()
    }
    
    # Calculate by Water Temp
    temp_counts = {'Cold': [0, 0], 'Warm': [0, 0], 'Hot': [0, 0]}
    for row in raw_data:
        temp = row['water_temp'].strip()
        if temp in temp_counts:
            temp_counts[temp][0] += 1
            if row['drainage_success'].strip().lower() in ['no', 'n', 'false', '0']:
                temp_counts[temp][1] += 1
    
    rates['water_temp'] = {
        k: (v[1] / v[0] * 100 if v[0] > 0 else 0) 
        for k, v in temp_counts.items()
    }
    
    return rates


def check_dates_standardized_and_sorted(raw_data: List[Dict]) -> Tuple[bool, str]:
    """
    Check if dates appear to be standardized and sorted chronologically.
    
    Returns:
        (is_valid, feedback_message)
    """
    parsed_dates = []
    
    for row in raw_data[:10]:  # Check first 10 dates
        date_obj = parse_date_flexible(row['date'])
        if date_obj:
            parsed_dates.append(date_obj)
    
    if len(parsed_dates) < 3:
        return False, "Could not parse enough dates to verify sorting"
    
    # Check if dates are in ascending order
    is_sorted = all(parsed_dates[i] <= parsed_dates[i+1] for i in range(len(parsed_dates)-1))
    
    if is_sorted:
        return True, "Dates appear standardized and sorted chronologically"
    else:
        return False, "Dates not properly sorted chronologically"


def find_analysis_section(workbook: Dict, sheet_name: str) -> Optional[Tuple[int, int]]:
    """
    Find the analysis section in the spreadsheet.
    Looks for keywords like "ANALYSIS", "FAILURE RATE", "BY CYCLE", etc.
    
    Returns:
        (start_row, start_col) or None if not found
    """
    rows = workbook['sheets'][sheet_name]
    
    keywords = ['analysis', 'failure rate', 'by cycle', 'cycle type', 'summary']
    
    for row_idx, row in enumerate(rows):
        for col_idx, cell in enumerate(row):
            cell_value = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
            if any(keyword in cell_value for keyword in keywords):
                return (row_idx, col_idx)
    
    return None


def verify_formulas_used(workbook: Dict, sheet_name: str, analysis_start: Tuple[int, int]) -> Tuple[bool, str]:
    """
    Verify that formulas (COUNTIFS, COUNT, etc.) are used in analysis section.
    
    Returns:
        (has_formulas, feedback)
    """
    rows = workbook['sheets'][sheet_name]
    start_row, start_col = analysis_start
    
    formula_count = 0
    countifs_count = 0
    
    # Check 20 rows and 10 columns from analysis start
    for row_idx in range(start_row, min(start_row + 20, len(rows))):
        if row_idx >= len(rows):
            break
        row = rows[row_idx]
        
        for col_idx in range(start_col, min(start_col + 10, len(row))):
            if col_idx >= len(row):
                break
            
            cell = row[col_idx]
            formula = cell.get('formula', '') if isinstance(cell, dict) else ''
            
            if formula:
                formula_count += 1
                if 'COUNTIF' in formula.upper():
                    countifs_count += 1
    
    if countifs_count >= 3:
        return True, f"Found {countifs_count} COUNTIF formulas in analysis section"
    elif formula_count >= 3:
        return True, f"Found {formula_count} formulas (may use alternative counting methods)"
    else:
        return False, f"Insufficient formulas found in analysis section (found {formula_count})"


def extract_calculated_rates(workbook: Dict, sheet_name: str, 
                             analysis_start: Tuple[int, int]) -> Dict[str, Dict[str, float]]:
    """
    Extract calculated failure rates from analysis section.
    
    Returns:
        Dict with categories and calculated rates
    """
    rows = workbook['sheets'][sheet_name]
    start_row, start_col = analysis_start
    
    rates = {'cycle_type': {}, 'load_size': {}, 'water_temp': {}}
    
    # Search for rates in analysis section
    category_keywords = {
        'cycle_type': ['normal', 'heavy', 'quick'],
        'load_size': ['light', 'medium', 'full'],
        'water_temp': ['cold', 'warm', 'hot']
    }
    
    for row_idx in range(start_row, min(start_row + 30, len(rows))):
        if row_idx >= len(rows):
            break
        row = rows[row_idx]
        
        for col_idx in range(max(0, start_col - 2), min(start_col + 10, len(row))):
            if col_idx >= len(row):
                break
            
            cell_value = str(row[col_idx].get('value', '') if isinstance(row[col_idx], dict) 
                           else row[col_idx]).lower()
            
            # Check if this cell contains a category label
            for category, keywords in category_keywords.items():
                for keyword in keywords:
                    if keyword in cell_value and cell_value.strip() == keyword:
                        # Look for percentage value in adjacent cells
                        for offset in range(1, 5):
                            if col_idx + offset < len(row):
                                adj_cell = row[col_idx + offset]
                                adj_value = adj_cell.get('value', '') if isinstance(adj_cell, dict) else adj_cell
                                
                                try:
                                    # Try to parse as percentage
                                    if isinstance(adj_value, (int, float)):
                                        rate = float(adj_value)
                                        # If value is between 0-1, assume it's decimal form of percentage
                                        if 0 <= rate <= 1:
                                            rate *= 100
                                        rates[category][keyword.capitalize()] = rate
                                        break
                                    elif '%' in str(adj_value):
                                        rate = float(str(adj_value).replace('%', '').strip())
                                        rates[category][keyword.capitalize()] = rate
                                        break
                                except (ValueError, TypeError):
                                    continue
    
    return rates


def verify_appliance_failure_analysis(traj, env_info, task_info):
    """
    Verify appliance failure analysis task completion.
    
    Checks:
    1. Dates standardized and sorted chronologically
    2. Analysis structure present (separate summary section)
    3. Formulas correct (uses COUNTIFS or equivalent)
    4. Statistical accuracy (rates match expected within 2%)
    5. Highest risk condition identified
    6. Warranty timeline calculated (days since first failure)
    7. Visual clarity (percentage formatting, conditional formatting)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try to copy and parse the spreadsheet
    container_paths = [
        "/home/ga/Documents/dishwasher_failure_analysis.ods",
        "/home/ga/Documents/dishwasher_log.ods",
        "/home/ga/Documents/dishwasher_log.csv"
    ]
    
    success = False
    workbook = None
    temp_dir = None
    
    for path in container_paths:
        file_format = 'csv' if path.endswith('.csv') else 'ods'
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            path, copy_from_env, file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet: {error}"
        }
    
    try:
        # Get first sheet
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        subscores = {}
        
        # Extract raw data
        raw_data = extract_raw_data(workbook, sheet_name)
        if len(raw_data) < 40:
            feedback_parts.append(f"⚠️ Only {len(raw_data)} data rows found (expected ~46)")
        
        # Criterion 1: Dates standardized and sorted
        dates_ok, dates_msg = check_dates_standardized_and_sorted(raw_data)
        if dates_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ {dates_msg}")
        else:
            feedback_parts.append(f"❌ {dates_msg}")
        subscores['dates_standardized'] = dates_ok
        
        # Criterion 2: Analysis structure present
        analysis_start = find_analysis_section(workbook, sheet_name)
        has_analysis = analysis_start is not None
        if has_analysis:
            criteria_passed += 1
            feedback_parts.append("✅ Analysis section found")
        else:
            feedback_parts.append("❌ No analysis section found")
        subscores['analysis_structure'] = has_analysis
        
        # Criterion 3: Formulas correct
        formulas_ok = False
        if has_analysis:
            formulas_ok, formula_msg = verify_formulas_used(workbook, sheet_name, analysis_start)
            if formulas_ok:
                criteria_passed += 1
                feedback_parts.append(f"✅ {formula_msg}")
            else:
                feedback_parts.append(f"❌ {formula_msg}")
        else:
            feedback_parts.append("❌ Cannot verify formulas without analysis section")
        subscores['formulas_correct'] = formulas_ok
        
        # Criterion 4: Statistical accuracy
        expected_rates = calculate_expected_failure_rates(raw_data)
        
        accuracy_ok = False
        if has_analysis:
            calculated_rates = extract_calculated_rates(workbook, sheet_name, analysis_start)
            
            # Compare rates (spot-check at least 3 categories)
            matches = 0
            checks = 0
            tolerance = 2.0  # 2% tolerance
            
            for category in ['cycle_type', 'load_size', 'water_temp']:
                for subcategory, expected_rate in expected_rates[category].items():
                    if subcategory in calculated_rates[category]:
                        checks += 1
                        calculated_rate = calculated_rates[category][subcategory]
                        if abs(calculated_rate - expected_rate) <= tolerance:
                            matches += 1
                        else:
                            logger.debug(f"{category}/{subcategory}: expected {expected_rate:.1f}%, got {calculated_rate:.1f}%")
            
            if checks >= 3 and matches >= 3:
                criteria_passed += 1
                accuracy_ok = True
                feedback_parts.append(f"✅ Statistical accuracy verified ({matches}/{checks} rates correct)")
            elif checks > 0:
                feedback_parts.append(f"⚠️ Some rates inaccurate ({matches}/{checks} correct within ±{tolerance}%)")
            else:
                feedback_parts.append("❌ Could not extract calculated rates for verification")
        else:
            feedback_parts.append("❌ Cannot verify accuracy without analysis section")
        subscores['statistical_accuracy'] = accuracy_ok
        
        # Criterion 5: Highest risk identified
        highest_risk_found = False
        if has_analysis:
            # Look for text mentioning "highest", "risk", "maximum", etc.
            rows = workbook['sheets'][sheet_name]
            for row_idx in range(analysis_start[0], min(analysis_start[0] + 30, len(rows))):
                if row_idx >= len(rows):
                    break
                row = rows[row_idx]
                
                for cell in row:
                    cell_value = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
                    if any(keyword in cell_value for keyword in ['highest', 'maximum', 'max', 'risk', 'conclusion']):
                        highest_risk_found = True
                        break
                if highest_risk_found:
                    break
            
            if highest_risk_found:
                criteria_passed += 1
                feedback_parts.append("✅ Highest risk condition identified")
            else:
                feedback_parts.append("❌ Highest risk condition not clearly identified")
        else:
            feedback_parts.append("❌ Cannot verify highest risk without analysis section")
        subscores['highest_risk_identified'] = highest_risk_found
        
        # Criterion 6: Warranty timeline (days since first failure)
        timeline_found = False
        if has_analysis:
            # Look for "days" or "timeline" or specific number of days
            rows = workbook['sheets'][sheet_name]
            for row_idx in range(analysis_start[0], min(analysis_start[0] + 30, len(rows))):
                if row_idx >= len(rows):
                    break
                row = rows[row_idx]
                
                for cell in row:
                    cell_value = str(cell.get('value', '') if isinstance(cell, dict) else cell).lower()
                    if 'day' in cell_value and any(char.isdigit() for char in cell_value):
                        timeline_found = True
                        break
                if timeline_found:
                    break
            
            if timeline_found:
                criteria_passed += 1
                feedback_parts.append("✅ Days since first failure calculated")
            else:
                feedback_parts.append("❌ Days since first failure not found")
        else:
            feedback_parts.append("❌ Cannot verify timeline without analysis section")
        subscores['timeline_calculated'] = timeline_found
        
        # Criterion 7: Visual clarity (percentage formatting)
        formatting_found = False
        if has_analysis:
            # Look for percentage values (cells with % or values formatted as percentages)
            rows = workbook['sheets'][sheet_name]
            percent_count = 0
            
            for row_idx in range(analysis_start[0], min(analysis_start[0] + 20, len(rows))):
                if row_idx >= len(rows):
                    break
                row = rows[row_idx]
                
                for cell in row:
                    cell_value = str(cell.get('value', '') if isinstance(cell, dict) else cell)
                    if '%' in cell_value:
                        percent_count += 1
            
            if percent_count >= 3:
                criteria_passed += 1
                formatting_found = True
                feedback_parts.append(f"✅ Percentage formatting applied ({percent_count} percentages found)")
            else:
                feedback_parts.append("⚠️ Limited percentage formatting detected")
        else:
            feedback_parts.append("❌ Cannot verify formatting without analysis section")
        subscores['visual_clarity'] = formatting_found
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Need 5/7 criteria (70%)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Excellent failure pattern analysis!")
        elif passed:
            feedback_parts.append("✅ Failure analysis completed adequately")
        else:
            feedback_parts.append("❌ Analysis incomplete or insufficient")
        
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
        cleanup_verification_temp(temp_dir)
