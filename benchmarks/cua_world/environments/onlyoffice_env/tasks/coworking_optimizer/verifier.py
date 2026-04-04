#!/usr/bin/env python3
"""
Verifier for Coworking Optimizer task

This verifier checks:
1. File exists and is valid XLSX
2. Proper structure (headers, 5 data rows)
3. All 5 coworking spaces present with pricing data
4. Cost per visit calculations are accurate
5. Monthly cost calculations for 8 and 10 visits
6. Formulas are used (not hardcoded values)
"""

import sys
import os
import logging
import tempfile
import re
from typing import Dict, List, Tuple, Optional, Any

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Expected coworking spaces with their data
EXPECTED_SPACES = {
    'workhub': {
        'name_variants': ['workhub', 'work hub', 'workhub downtown', 'work hub downtown'],
        'base_price': 25,
        'pricing_type': 'day_pass',
        'expected_cost_per_visit': 25.0,
        'expected_cost_8_visits': 200.0,
        'expected_cost_10_visits': 250.0
    },
    'creative': {
        'name_variants': ['creative', 'creative collective'],
        'base_price': 200,
        'pricing_type': 'punch_card',
        'units': 10,
        'expected_cost_per_visit': 20.0,
        'expected_cost_8_visits': 160.0,
        'expected_cost_10_visits': 200.0
    },
    'flex_plaza': {
        'name_variants': ['flex', 'flex office', 'flex office plaza', 'office plaza'],
        'base_price': 150,
        'pricing_type': 'monthly_flex',
        'included_days': 6,
        'expected_cost_per_visit': 25.0,
        'expected_cost_8_visits': 200.0,  # 150 + (2 * 25)
        'expected_cost_10_visits': 250.0   # 150 + (4 * 25)
    },
    'startup': {
        'name_variants': ['startup', 'startup loft', 'loft'],
        'base_price': 180,
        'pricing_type': 'monthly_flex',
        'included_days': 8,
        'expected_cost_per_visit': 22.5,
        'expected_cost_8_visits': 180.0,   # Exactly 8 days included
        'expected_cost_10_visits': 225.0   # 180 + (2 * 22.5)
    },
    'commons': {
        'name_variants': ['commons', 'the commons'],
        'base_price': 30,
        'pricing_type': 'day_pass',
        'expected_cost_per_visit': 30.0,
        'expected_cost_8_visits': 240.0,
        'expected_cost_10_visits': 300.0
    }
}


def fuzzy_match_space_name(cell_value: Any) -> Optional[str]:
    """Match cell value to a known coworking space"""
    if not cell_value or not isinstance(cell_value, str):
        return None
    
    cell_lower = cell_value.lower().strip()
    
    for space_key, space_data in EXPECTED_SPACES.items():
        for variant in space_data['name_variants']:
            if variant in cell_lower or cell_lower in variant:
                return space_key
    
    return None


def extract_numeric_value(cell_value: Any) -> Optional[float]:
    """Extract numeric value from cell, handling strings like '$25' or '25.00'"""
    if cell_value is None:
        return None
    
    if isinstance(cell_value, (int, float)):
        return float(cell_value)
    
    if isinstance(cell_value, str):
        # Remove currency symbols and commas
        clean_str = cell_value.replace('$', '').replace(',', '').strip()
        try:
            return float(clean_str)
        except ValueError:
            return None
    
    return None


def find_header_row(sheet_data: List[List]) -> Optional[int]:
    """Find the row containing column headers"""
    for row_idx, row in enumerate(sheet_data[:5]):  # Check first 5 rows
        row_text = ' '.join([str(cell).lower() if cell else '' for cell in row])
        
        # Look for header keywords
        has_name = any(kw in row_text for kw in ['space', 'name', 'coworking'])
        has_price = any(kw in row_text for kw in ['price', 'cost', 'base'])
        has_visit = 'visit' in row_text
        
        if has_name and (has_price or has_visit):
            return row_idx
    
    return 0  # Default to first row


def find_column_indices(header_row: List) -> Dict[str, int]:
    """Find column indices for required columns"""
    columns = {
        'name': None,
        'base_price': None,
        'cost_per_visit': None,
        'cost_8_visits': None,
        'cost_10_visits': None
    }
    
    for col_idx, cell in enumerate(header_row):
        if not cell:
            continue
        
        cell_lower = str(cell).lower().strip()
        
        # Name column
        if 'name' in cell_lower or 'space' in cell_lower:
            columns['name'] = col_idx
        
        # Base price column
        elif 'base' in cell_lower and 'price' in cell_lower:
            columns['base_price'] = col_idx
        
        # Cost per visit
        elif 'per visit' in cell_lower or 'per-visit' in cell_lower or 'cost per' in cell_lower:
            columns['cost_per_visit'] = col_idx
        
        # Monthly cost @ 8
        elif '8' in cell_lower and ('visit' in cell_lower or 'monthly' in cell_lower):
            columns['cost_8_visits'] = col_idx
        
        # Monthly cost @ 10
        elif '10' in cell_lower and ('visit' in cell_lower or 'monthly' in cell_lower):
            columns['cost_10_visits'] = col_idx
    
    return columns


def check_formula_usage(workbook: Any, sheet_name: str, row_start: int, col_indices: List[int], num_rows: int = 5) -> Tuple[int, int]:
    """
    Check how many cells contain formulas vs hardcoded values
    Returns (formula_count, total_checked)
    """
    try:
        sheet = workbook[sheet_name]
        formula_count = 0
        total_checked = 0
        
        for row_offset in range(num_rows):
            row_idx = row_start + row_offset + 2  # +2 for 1-indexing and header
            
            for col_idx in col_indices:
                if col_idx is None:
                    continue
                
                # Convert 0-indexed col to Excel letter
                col_letter = chr(65 + col_idx) if col_idx < 26 else f"A{chr(65 + col_idx - 26)}"
                cell_ref = f"{col_letter}{row_idx}"
                
                try:
                    cell = sheet[cell_ref]
                    total_checked += 1
                    
                    # Check if cell contains a formula
                    if cell.data_type == 'f':  # Formula cell
                        formula_count += 1
                    elif hasattr(cell, 'value') and isinstance(cell.value, str) and cell.value.startswith('='):
                        formula_count += 1
                        
                except Exception as e:
                    logger.debug(f"Could not check cell {cell_ref}: {e}")
                    continue
        
        return formula_count, total_checked
        
    except Exception as e:
        logger.error(f"Error checking formulas: {e}")
        return 0, 0


def verify_coworking_comparison(traj, env_info, task_info):
    """
    Main verification function for coworking comparison spreadsheet
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/coworking_comparison.xlsx"
    temp_dir = None
    
    try:
        # Create temp file to copy spreadsheet
        temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_coworking_')
        local_file = os.path.join(temp_dir, 'coworking_comparison.xlsx')
        
        # Copy file from container
        try:
            copy_from_env(container_path, local_file)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy file from container: {str(e)}"}
        
        # Check file exists and has content
        if not os.path.exists(local_file):
            return {"passed": False, "score": 0, "feedback": f"File not found: {container_path}"}
        
        file_size = os.path.getsize(local_file)
        if file_size < 5000:  # Less than 5KB is suspicious
            return {"passed": False, "score": 0, "feedback": f"File too small ({file_size} bytes), may be empty or corrupt"}
        
        # Parse spreadsheet
        wb = parse_xlsx_file(local_file)
        if wb is None:
            return {"passed": False, "score": 0, "feedback": "Failed to parse XLSX file - file may be corrupt"}
        
        # Get first sheet
        sheet_name = wb.sheetnames[0]
        sheet_data = get_sheet_data(wb, sheet_name, max_rows=20, max_cols=10)
        
        if not sheet_data or len(sheet_data) < 2:
            return {"passed": False, "score": 0, "feedback": "Spreadsheet is empty or has insufficient data"}
        
        # Initialize scoring
        criteria_passed = 0
        max_criteria = 6
        feedback_parts = []
        
        # Criterion 1: Check structure (6+ rows, 7+ columns)
        num_rows = len([row for row in sheet_data if any(cell for cell in row)])
        num_cols = max(len(row) for row in sheet_data) if sheet_data else 0
        
        if num_rows >= 6 and num_cols >= 7:
            criteria_passed += 1
            feedback_parts.append(f"✅ Structure valid ({num_rows} rows, {num_cols} columns)")
        else:
            feedback_parts.append(f"❌ Structure incomplete ({num_rows} rows, {num_cols} columns - need 6+ rows, 7+ columns)")
        
        # Find header row and columns
        header_row_idx = find_header_row(sheet_data)
        header_row = sheet_data[header_row_idx] if header_row_idx < len(sheet_data) else []
        col_indices = find_column_indices(header_row)
        
        logger.info(f"Header row index: {header_row_idx}")
        logger.info(f"Column indices: {col_indices}")
        
        # Data rows start after header
        data_start_idx = header_row_idx + 1
        data_rows = sheet_data[data_start_idx:data_start_idx + 10]  # Get up to 10 data rows
        
        # Criterion 2: Check all 5 space names are present
        found_spaces = {}
        name_col = col_indices['name']
        
        if name_col is not None:
            for row_idx, row in enumerate(data_rows):
                if row_idx >= len(row) or not row:
                    continue
                
                if name_col < len(row):
                    cell_value = row[name_col]
                    space_key = fuzzy_match_space_name(cell_value)
                    
                    if space_key:
                        found_spaces[space_key] = {
                            'row_idx': row_idx,
                            'row_data': row
                        }
        
        num_spaces_found = len(found_spaces)
        if num_spaces_found >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ All 5 coworking spaces found")
        elif num_spaces_found >= 3:
            feedback_parts.append(f"⚠️ Only {num_spaces_found}/5 spaces found")
        else:
            feedback_parts.append(f"❌ Only {num_spaces_found}/5 spaces found")
        
        # Criterion 3: Check data completeness (base prices present)
        base_price_col = col_indices['base_price']
        data_complete = False
        
        if base_price_col is not None:
            prices_found = 0
            expected_prices = [25, 200, 150, 180, 30]
            
            for row in data_rows[:5]:
                if base_price_col < len(row):
                    price = extract_numeric_value(row[base_price_col])
                    if price and any(abs(price - exp) <= 5 for exp in expected_prices):
                        prices_found += 1
            
            if prices_found >= 4:
                criteria_passed += 1
                data_complete = True
                feedback_parts.append(f"✅ Pricing data complete ({prices_found}/5 prices found)")
            else:
                feedback_parts.append(f"❌ Pricing data incomplete ({prices_found}/5 prices found)")
        else:
            feedback_parts.append("❌ Base price column not found")
        
        # Criterion 4: Verify cost per visit calculations
        cost_per_visit_col = col_indices['cost_per_visit']
        cost_per_visit_accurate = 0
        cost_per_visit_total = 0
        
        if cost_per_visit_col is not None and found_spaces:
            for space_key, space_info in found_spaces.items():
                row_data = space_info['row_data']
                expected_data = EXPECTED_SPACES[space_key]
                
                if cost_per_visit_col < len(row_data):
                    actual_value = extract_numeric_value(row_data[cost_per_visit_col])
                    expected_value = expected_data['expected_cost_per_visit']
                    
                    cost_per_visit_total += 1
                    
                    if actual_value is not None and abs(actual_value - expected_value) <= 1.0:
                        cost_per_visit_accurate += 1
        
        if cost_per_visit_total > 0:
            accuracy_pct = (cost_per_visit_accurate / cost_per_visit_total) * 100
            if accuracy_pct >= 80:
                criteria_passed += 1
                feedback_parts.append(f"✅ Cost per visit accurate ({cost_per_visit_accurate}/{cost_per_visit_total} correct)")
            else:
                feedback_parts.append(f"❌ Cost per visit errors ({cost_per_visit_accurate}/{cost_per_visit_total} correct)")
        else:
            feedback_parts.append("❌ Cost per visit column not found or empty")
        
        # Criterion 5: Verify monthly costs (8 and 10 visits)
        cost_8_col = col_indices['cost_8_visits']
        cost_10_col = col_indices['cost_10_visits']
        
        monthly_costs_accurate = 0
        monthly_costs_total = 0
        
        for visit_count, col_idx in [('8', cost_8_col), ('10', cost_10_col)]:
            if col_idx is not None and found_spaces:
                for space_key, space_info in found_spaces.items():
                    row_data = space_info['row_data']
                    expected_data = EXPECTED_SPACES[space_key]
                    
                    if col_idx < len(row_data):
                        actual_value = extract_numeric_value(row_data[col_idx])
                        
                        if visit_count == '8':
                            expected_value = expected_data['expected_cost_8_visits']
                        else:
                            expected_value = expected_data['expected_cost_10_visits']
                        
                        monthly_costs_total += 1
                        
                        # More lenient tolerance for monthly flex calculations
                        tolerance = 10 if expected_data['pricing_type'] == 'monthly_flex' else 5
                        
                        if actual_value is not None and abs(actual_value - expected_value) <= tolerance:
                            monthly_costs_accurate += 1
        
        if monthly_costs_total > 0:
            accuracy_pct = (monthly_costs_accurate / monthly_costs_total) * 100
            if accuracy_pct >= 75:
                criteria_passed += 1
                feedback_parts.append(f"✅ Monthly costs mostly accurate ({monthly_costs_accurate}/{monthly_costs_total} correct)")
            else:
                feedback_parts.append(f"❌ Monthly cost errors ({monthly_costs_accurate}/{monthly_costs_total} correct)")
        else:
            feedback_parts.append("❌ Monthly cost columns not found or empty")
        
        # Criterion 6: Check formula usage
        formula_cols = [idx for idx in [cost_per_visit_col, cost_8_col, cost_10_col] if idx is not None]
        
        if formula_cols and len(found_spaces) >= 3:
            formula_count, total_checked = check_formula_usage(
                wb, sheet_name, data_start_idx, formula_cols, num_rows=len(found_spaces)
            )
            
            if total_checked > 0:
                formula_pct = (formula_count / total_checked) * 100
                
                if formula_pct >= 60:
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Formulas used ({formula_count}/{total_checked} cells, {formula_pct:.0f}%)")
                elif formula_pct >= 30:
                    feedback_parts.append(f"⚠️ Some formulas used ({formula_count}/{total_checked} cells, {formula_pct:.0f}%) - should use more")
                else:
                    feedback_parts.append(f"❌ Few formulas ({formula_count}/{total_checked} cells, {formula_pct:.0f}%) - mostly hardcoded")
            else:
                feedback_parts.append("⚠️ Could not verify formula usage")
        else:
            feedback_parts.append("⚠️ Insufficient data to check formula usage")
        
        # Calculate final score
        score = int((criteria_passed / max_criteria) * 100)
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: {criteria_passed}/{max_criteria} criteria passed, score={score}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        if temp_dir:
            cleanup_temp_dir(temp_dir)