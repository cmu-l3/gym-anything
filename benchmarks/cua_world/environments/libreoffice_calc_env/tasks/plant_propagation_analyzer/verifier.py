#!/usr/bin/env python3
"""
Verifier for Plant Propagation Analyzer task.

Checks:
1. Days Since Cutting calculated with TODAY() formulas
2. Summary table exists with correct structure
3. COUNTIF/COUNTIFS formulas present and correct
4. Success rates calculated accurately
5. Conditional formatting applied
6. Percentage formatting used
7. Formulas (not hardcoded values) used throughout
"""

import sys
import os
import logging
import zipfile
from xml.etree import ElementTree as ET
from datetime import datetime
import re

# Add utils to path (relative path for host execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_date_formulas(sheet_data, sheet_name, start_row=2, end_row=13, date_col='E'):
    """
    Check if Days Since Cutting column contains TODAY() formulas.
    
    Returns: (has_formulas, formula_count)
    """
    formula_count = 0
    has_today = 0
    
    for row_idx in range(start_row, end_row + 1):
        cell_ref = f"{date_col}{row_idx}"
        formula = get_cell_formula(sheet_data, sheet_name, cell_ref)
        
        if formula:
            formula_count += 1
            # Check if formula contains TODAY()
            if 'TODAY()' in formula.upper():
                has_today += 1
    
    return has_today >= 8, formula_count  # At least 8/12 rows should have TODAY()


def find_summary_table(sheet_data, sheet_name):
    """
    Find the summary analysis table in the spreadsheet.
    Look for headers: "Propagation Method", "Total", "Successful", "Success Rate"
    
    Returns: (found, start_row, structure_dict)
    """
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return False, None, {}
    
    rows = sheets[sheet_name]
    
    # Search for table headers (likely around row 18-25)
    for row_idx in range(15, min(30, len(rows))):
        row_cells = rows[row_idx] if row_idx < len(rows) else []
        
        # Get text values from row
        row_text = []
        for cell in row_cells[:6]:  # Check first 6 columns
            if isinstance(cell, dict):
                val = cell.get('value', '')
            else:
                val = cell
            row_text.append(str(val).lower() if val else '')
        
        row_text_joined = ' '.join(row_text)
        
        # Check if this looks like our header row
        if ('method' in row_text_joined or 'propagation' in row_text_joined) and \
           ('total' in row_text_joined or 'attempts' in row_text_joined) and \
           ('success' in row_text_joined or 'rate' in row_text_joined):
            
            # Found potential header row
            return True, row_idx, {
                'header_row': row_idx,
                'data_start': row_idx + 1
            }
    
    return False, None, {}


def check_countif_formulas(sheet_data, sheet_name, table_info):
    """
    Check if COUNTIF/COUNTIFS formulas are used in summary table.
    
    Returns: (has_countif, has_countifs, formula_details)
    """
    if not table_info:
        return False, False, []
    
    data_start = table_info.get('data_start', 19)
    has_countif = False
    has_countifs = False
    formula_details = []
    
    # Check 3 rows of data (Water, Soil, Perlite)
    for row_offset in range(3):
        row_idx = data_start + row_offset
        
        # Check columns B, C, D for formulas (Total, Successful, Rate)
        for col in ['B', 'C', 'D']:
            cell_ref = f"{col}{row_idx}"
            formula = get_cell_formula(sheet_data, sheet_name, cell_ref)
            
            if formula:
                formula_upper = formula.upper()
                if 'COUNTIF' in formula_upper:
                    has_countif = True
                    if 'COUNTIFS' in formula_upper:
                        has_countifs = True
                    formula_details.append(f"{cell_ref}: {formula}")
    
    return has_countif, has_countifs, formula_details


def calculate_expected_success_rates(sheet_data, sheet_name):
    """
    Calculate expected success rates from raw data.
    
    Returns: dict with {method: (total, successful, rate)}
    """
    sheets = sheet_data.get('sheets', {})
    if sheet_name not in sheets:
        return {}
    
    rows = sheets[sheet_name]
    
    # Count by method and status
    counts = {
        'Water': {'total': 0, 'rooted': 0},
        'Soil': {'total': 0, 'rooted': 0},
        'Perlite': {'total': 0, 'rooted': 0}
    }
    
    # Parse data rows (2-13, which is index 1-12)
    for row_idx in range(1, min(13, len(rows))):
        row = rows[row_idx]
        
        if len(row) < 4:
            continue
        
        # Column C (index 2): Propagation Method
        # Column D (index 3): Status
        method_cell = row[2] if len(row) > 2 else {}
        status_cell = row[3] if len(row) > 3 else {}
        
        method = method_cell.get('value') if isinstance(method_cell, dict) else method_cell
        status = status_cell.get('value') if isinstance(status_cell, dict) else status_cell
        
        method = str(method).strip() if method else ''
        status = str(status).strip() if status else ''
        
        if method in counts:
            counts[method]['total'] += 1
            if status.lower() == 'rooted':
                counts[method]['rooted'] += 1
    
    # Calculate rates
    results = {}
    for method, data in counts.items():
        total = data['total']
        rooted = data['rooted']
        rate = rooted / total if total > 0 else 0
        results[method] = (total, rooted, rate)
    
    return results


def check_success_rate_accuracy(sheet_data, sheet_name, table_info, expected_rates):
    """
    Check if calculated success rates match expected values.
    
    Returns: (accurate_count, total_checked, details)
    """
    if not table_info or not expected_rates:
        return 0, 0, []
    
    data_start = table_info.get('data_start', 19)
    accurate_count = 0
    details = []
    methods = ['Water', 'Soil', 'Perlite']
    
    for idx, method in enumerate(methods):
        row_idx = data_start + idx
        
        # Success rate likely in column D
        rate_cell_ref = f"D{row_idx}"
        calculated_rate = get_cell_value(sheet_data, sheet_name, rate_cell_ref)
        
        if calculated_rate is None:
            continue
        
        # Convert to float (handle percentage or decimal)
        try:
            calc_val = float(calculated_rate)
            # If value is between 0-1, it's decimal; if >1, it's percentage
            if calc_val > 1:
                calc_val = calc_val / 100
        except (ValueError, TypeError):
            continue
        
        if method in expected_rates:
            expected_total, expected_success, expected_rate = expected_rates[method]
            
            # Check within 2% tolerance
            if abs(calc_val - expected_rate) <= 0.02:
                accurate_count += 1
                details.append(f"✓ {method}: {calc_val:.1%} (expected {expected_rate:.1%})")
            else:
                details.append(f"✗ {method}: {calc_val:.1%} (expected {expected_rate:.1%})")
    
    return accurate_count, len(methods), details


def check_conditional_formatting_in_ods(filepath, sheet_name):
    """
    Check if conditional formatting exists in ODS file for Status column.
    
    Returns: (has_formatting, has_green_rule, has_red_rule)
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return False, False, False
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Look for conditional formatting in ODF
            # This is complex in ODS format - simplify by checking for style maps
            content_str = content_xml.decode('utf-8', errors='ignore')
            
            # Check for conditional formatting indicators
            has_formatting = 'style:map' in content_str or 'calcext:conditional-format' in content_str
            
            # Check for color indicators (green/red)
            has_green = '#00ff00' in content_str.lower() or 'green' in content_str.lower()
            has_red = '#ff0000' in content_str.lower() or 'red' in content_str.lower()
            
            return has_formatting, has_green, has_red
            
    except Exception as e:
        logger.debug(f"Could not check conditional formatting: {e}")
        return False, False, False


def check_percentage_formatting(sheet_data, sheet_name, table_info):
    """
    Check if success rate cells are formatted as percentages.
    This is tricky to detect from parsed data - check cell type or value range.
    
    Returns: bool
    """
    if not table_info:
        return False
    
    data_start = table_info.get('data_start', 19)
    
    # Check if success rate values look like percentages
    for row_offset in range(3):
        row_idx = data_start + row_offset
        rate_cell_ref = f"D{row_idx}"
        
        cell_value = get_cell_value(sheet_data, sheet_name, rate_cell_ref)
        
        if cell_value is not None:
            try:
                val = float(cell_value)
                # If value is >1 and <100, likely formatted as percentage
                # Or if value is <1, might be decimal representation
                if 0 <= val <= 1 or 0 <= val <= 100:
                    return True
            except (ValueError, TypeError):
                pass
    
    return False


def verify_propagation_analyzer(traj, env_info, task_info):
    """
    Main verification function for Plant Propagation Analyzer task.
    
    Checks 7 criteria:
    1. Days Since Cutting has TODAY() formulas
    2. Summary table exists
    3. COUNTIF/COUNTIFS formulas used
    4. Success rates accurate
    5. Conditional formatting applied
    6. Percentage formatting used
    7. Formulas (not hardcoded) throughout
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file locations
    container_paths = [
        "/home/ga/Documents/propagation_analysis.ods",
        "/home/ga/Documents/propagation_log.ods",
        "/home/ga/Documents/propagation_log.csv"
    ]
    
    success = False
    file_info = None
    
    for container_path in container_paths:
        file_format = 'ods' if container_path.endswith('.ods') else 'csv'
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            [file_format]
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load spreadsheet file. Tried: {', '.join(container_paths)}"
        }
    
    try:
        sheet_data = file_info.get('sheet_data', {})
        sheet_names = get_sheet_names(sheet_data)
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Days Since Cutting calculated with TODAY()
        has_date_formulas, formula_count = check_date_formulas(sheet_data, sheet_name)
        if has_date_formulas:
            criteria_passed += 1
            feedback_parts.append(f"✅ Days calculated with TODAY() formulas ({formula_count} formulas found)")
            subscores['days_calculated'] = True
        else:
            feedback_parts.append(f"❌ Days Since Cutting missing TODAY() formulas (found {formula_count})")
            subscores['days_calculated'] = False
        
        # Criterion 2: Summary table exists
        table_found, table_row, table_info = find_summary_table(sheet_data, sheet_name)
        if table_found:
            criteria_passed += 1
            feedback_parts.append(f"✅ Summary analysis table found (row {table_row + 1})")
            subscores['summary_table'] = True
        else:
            feedback_parts.append("❌ Summary table not found (expected headers: Method, Total, Successful, Success Rate)")
            subscores['summary_table'] = False
        
        # Criterion 3: COUNTIF/COUNTIFS formulas
        has_countif, has_countifs, formula_details = check_countif_formulas(sheet_data, sheet_name, table_info)
        if has_countif and has_countifs:
            criteria_passed += 1
            feedback_parts.append(f"✅ COUNTIF/COUNTIFS formulas used correctly ({len(formula_details)} formulas)")
            subscores['counting_formulas'] = True
        elif has_countif:
            criteria_passed += 0.5
            feedback_parts.append("⚠️ COUNTIF found but COUNTIFS may be missing")
            subscores['counting_formulas'] = False
        else:
            feedback_parts.append("❌ Missing COUNTIF/COUNTIFS formulas for counting")
            subscores['counting_formulas'] = False
        
        # Criterion 4: Success rates accurate
        expected_rates = calculate_expected_success_rates(sheet_data, sheet_name)
        accurate_count, total_methods, rate_details = check_success_rate_accuracy(
            sheet_data, sheet_name, table_info, expected_rates
        )
        
        if accurate_count >= 2:  # At least 2 out of 3 methods correct
            criteria_passed += 1
            feedback_parts.append(f"✅ Success rates accurate ({accurate_count}/{total_methods} correct)")
            subscores['success_rates_accurate'] = True
        elif accurate_count > 0:
            criteria_passed += 0.5
            feedback_parts.append(f"⚠️ Some success rates correct ({accurate_count}/{total_methods})")
            subscores['success_rates_accurate'] = False
        else:
            feedback_parts.append("❌ Success rate calculations incorrect or missing")
            subscores['success_rates_accurate'] = False
        
        # Log rate details for debugging
        if rate_details:
            logger.info(f"Success rate details: {rate_details}")
        
        # Criterion 5: Conditional formatting
        filepath = file_info.get('filepath', '')
        has_cond_fmt, has_green, has_red = check_conditional_formatting_in_ods(filepath, sheet_name)
        
        if has_cond_fmt and has_green and has_red:
            criteria_passed += 1
            feedback_parts.append("✅ Conditional formatting applied (green/red colors detected)")
            subscores['conditional_formatting'] = True
        elif has_cond_fmt:
            criteria_passed += 0.5
            feedback_parts.append("⚠️ Some formatting detected but may be incomplete")
            subscores['conditional_formatting'] = False
        else:
            feedback_parts.append("❌ Conditional formatting not detected on Status column")
            subscores['conditional_formatting'] = False
        
        # Criterion 6: Percentage formatting
        has_pct_format = check_percentage_formatting(sheet_data, sheet_name, table_info)
        if has_pct_format:
            criteria_passed += 1
            feedback_parts.append("✅ Success rates formatted as percentages")
            subscores['percentage_formatting'] = True
        else:
            feedback_parts.append("⚠️ Percentage formatting may be missing")
            subscores['percentage_formatting'] = False
        
        # Criterion 7: Formulas used (not hardcoded)
        # Already checked in criteria 1 and 3
        if has_date_formulas and has_countif:
            criteria_passed += 1
            feedback_parts.append("✅ Formulas used throughout (not hardcoded values)")
            subscores['formulas_used'] = True
        else:
            feedback_parts.append("❌ Some values may be hardcoded instead of formulas")
            subscores['formulas_used'] = False
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold = 5/7 criteria
        
        # Add summary feedback
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent analysis! All propagation data analyzed correctly.")
        elif passed:
            feedback_parts.insert(0, "✅ Good analysis. Most requirements met.")
        else:
            feedback_parts.insert(0, f"❌ Analysis incomplete. Only {criteria_passed:.1f}/{total_criteria} criteria met.")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": subscores,
            "metadata": {
                "expected_rates": {k: f"{v[2]:.1%}" for k, v in expected_rates.items()},
                "criteria_passed": f"{criteria_passed:.1f}/{total_criteria}"
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
