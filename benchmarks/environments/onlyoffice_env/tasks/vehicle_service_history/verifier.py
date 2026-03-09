#!/usr/bin/env python3
"""
Verifier for Vehicle Service History task

This verifier checks that the agent:
1. Created proper column structure for vehicle maintenance tracking
2. Entered at least 8 service records (out of 10 available)
3. Used formulas (not hard-coded values) for calculations
4. Included a SUM formula for total cost
5. Formatted headers as bold
6. Formatted costs as currency
7. Sorted records chronologically by date
"""

import sys
import os
import logging
import tempfile
import re
from datetime import datetime
from typing import List, Tuple, Optional, Any

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_date_flexible(date_str: str) -> Optional[datetime]:
    """
    Parse date from various formats (MM/DD/YYYY, M/D/YY, etc.)
    """
    if not date_str:
        return None
    
    date_str = str(date_str).strip()
    
    # Common date formats
    formats = [
        "%m/%d/%Y",
        "%m/%d/%y",
        "%m-%d-%Y",
        "%m-%d-%y",
        "%Y-%m-%d",
        "%d/%m/%Y",
        "%d/%m/%y",
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except ValueError:
            continue
    
    # Try to handle dates that are already datetime objects
    if isinstance(date_str, datetime):
        return date_str
    
    return None


def find_header_row(sheet_data: List[List]) -> Tuple[int, dict]:
    """
    Find the header row and map column names to indices.
    Returns: (row_index, column_mapping)
    column_mapping keys: 'date', 'odometer', 'service', 'cost', 'provider', 'notes'
    """
    header_keywords = {
        'date': ['date', 'service date', 'when'],
        'odometer': ['odometer', 'mileage', 'miles', 'odo'],
        'service': ['service', 'service type', 'work done', 'description', 'type'],
        'cost': ['cost', 'price', 'amount', 'total', 'charge'],
        'provider': ['provider', 'shop', 'location', 'vendor', 'garage'],
        'notes': ['notes', 'note', 'comments', 'remarks', 'details'],
    }
    
    for row_idx, row in enumerate(sheet_data[:10]):  # Check first 10 rows
        if not row:
            continue
        
        column_mapping = {}
        row_lower = [str(cell).lower().strip() if cell else '' for cell in row]
        
        for col_idx, cell_value in enumerate(row_lower):
            if not cell_value:
                continue
            
            for key, keywords in header_keywords.items():
                if any(keyword in cell_value for keyword in keywords):
                    column_mapping[key] = col_idx
                    break
        
        # Valid header row should have at least date, service, and cost
        if 'date' in column_mapping and 'service' in column_mapping and 'cost' in column_mapping:
            return row_idx, column_mapping
    
    return -1, {}


def extract_numeric_value(value: Any) -> Optional[float]:
    """
    Extract numeric value from cell (handles currency formatting, strings with numbers, etc.)
    """
    if value is None:
        return None
    
    if isinstance(value, (int, float)):
        return float(value)
    
    # Remove currency symbols, commas, and extract number
    value_str = str(value).strip()
    value_str = re.sub(r'[$,€£¥\s]', '', value_str)
    
    try:
        return float(value_str)
    except ValueError:
        return None


def check_has_formulas(workbook: Any, sheet_name: str, data_rows: List[int], columns: List[int]) -> bool:
    """
    Check if any cells in the specified rows/columns contain formulas.
    This checks by looking at cell formulas directly.
    """
    try:
        sheet = workbook[sheet_name]
        
        for row_idx in data_rows:
            for col_idx in columns:
                # Convert to 1-based indexing for openpyxl
                cell = sheet.cell(row=row_idx + 1, column=col_idx + 1)
                
                # Check if cell has a formula (not just a value)
                if hasattr(cell, 'value') and cell.value:
                    # In openpyxl, formulas start with '='
                    cell_value_str = str(cell.value)
                    if cell_value_str.startswith('='):
                        return True
                
                # Alternative: check data_type
                if hasattr(cell, 'data_type') and cell.data_type == 'f':
                    return True
        
        return False
    except Exception as e:
        logger.warning(f"Error checking formulas: {e}")
        return False


def check_cell_formatting(workbook: Any, sheet_name: str, row: int, col: int, check_type: str) -> bool:
    """
    Check cell formatting (bold, currency, etc.)
    check_type: 'bold', 'currency'
    """
    try:
        sheet = workbook[sheet_name]
        cell = sheet.cell(row=row + 1, column=col + 1)  # Convert to 1-based
        
        if check_type == 'bold':
            if hasattr(cell, 'font') and cell.font and hasattr(cell.font, 'bold'):
                return cell.font.bold == True
        
        elif check_type == 'currency':
            if hasattr(cell, 'number_format') and cell.number_format:
                # Check if number format contains currency symbols
                fmt = str(cell.number_format).lower()
                return '$' in fmt or 'currency' in fmt or 'accounting' in fmt or '[$' in fmt
        
        return False
    except Exception as e:
        logger.warning(f"Error checking {check_type} formatting: {e}")
        return False


def verify_vehicle_service_history(traj, env_info, task_info):
    """
    Verify that vehicle service history spreadsheet was created correctly.

    Verification Criteria (6 total, need 4+ to pass):
    1. Proper Structure: Headers include Date, Odometer, Service Type, Cost
    2. Adequate Data Entry: At least 8 service records entered
    3. Formula Usage: At least one column uses formulas
    4. Total Calculation: SUM formula for total costs (~$1,140)
    5. Professional Formatting: Headers bold AND costs in currency format
    6. Chronological Order: Records sorted by date (oldest to newest)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/car_service_log.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_vehicle_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        criteria_passed = 0
        feedback_parts = []
        
        # Get the active sheet (or first sheet)
        sheet_name = wb.sheetnames[0] if wb.sheetnames else "Sheet1"
        
        # Extract all data from the sheet
        sheet_data = get_sheet_data(wb, sheet_name, max_rows=50, max_cols=20)
        
        # ===== CRITERION 1: Proper Structure (headers) =====
        header_row_idx, column_mapping = find_header_row(sheet_data)
        
        if header_row_idx >= 0 and len(column_mapping) >= 3:
            required_cols = ['date', 'service', 'cost']
            has_required = all(col in column_mapping for col in required_cols)
            
            if has_required:
                criteria_passed += 1
                feedback_parts.append(f"✅ Proper structure with headers: {list(column_mapping.keys())}")
            else:
                missing = [col for col in required_cols if col not in column_mapping]
                feedback_parts.append(f"❌ Missing required columns: {missing}")
        else:
            feedback_parts.append("❌ Could not find valid header row with Date, Service Type, Cost")
            # Cannot continue verification without structure
            return {
                "passed": False,
                "score": int((criteria_passed / 6) * 100),
                "feedback": " | ".join(feedback_parts)
            }
        
        # ===== CRITERION 2: Adequate Data Entry (8+ records) =====
        data_start_row = header_row_idx + 1
        service_records = []
        
        for row_idx in range(data_start_row, min(data_start_row + 30, len(sheet_data))):
            row = sheet_data[row_idx]
            
            # Check if this row has data in key columns
            has_date = column_mapping['date'] < len(row) and row[column_mapping['date']]
            has_service = column_mapping['service'] < len(row) and row[column_mapping['service']]
            
            if has_date and has_service:
                # Skip if this looks like a total/summary row
                service_text = str(row[column_mapping['service']]).lower()
                if 'total' in service_text or 'sum' in service_text or 'average' in service_text:
                    continue
                
                service_records.append({
                    'row_idx': row_idx,
                    'date': row[column_mapping['date']],
                    'service': row[column_mapping['service']],
                    'cost': row[column_mapping['cost']] if column_mapping['cost'] < len(row) else None,
                })
        
        record_count = len(service_records)
        
        if record_count >= 8:
            criteria_passed += 1
            feedback_parts.append(f"✅ Adequate data entry: {record_count} service records found")
        elif record_count >= 5:
            feedback_parts.append(f"⚠️ Partial data entry: {record_count} records (expected 8+)")
        else:
            feedback_parts.append(f"❌ Insufficient data: only {record_count} records (need 8+)")
        
        # ===== CRITERION 3: Formula Usage =====
        # Check if there are formulas in calculated columns or anywhere in data rows
        data_row_indices = [rec['row_idx'] for rec in service_records]
        all_col_indices = list(column_mapping.values())
        
        # Also check columns beyond the mapped ones (for calculated columns)
        max_col = max(all_col_indices) if all_col_indices else 0
        potential_calc_cols = list(range(max_col + 1, max_col + 5))
        
        has_formulas = check_has_formulas(
            wb, sheet_name, 
            data_row_indices[:10],  # Check first 10 data rows
            all_col_indices + potential_calc_cols
        )
        
        if has_formulas:
            criteria_passed += 1
            feedback_parts.append("✅ Formula usage detected (not just hard-coded values)")
        else:
            feedback_parts.append("❌ No formulas found - values appear to be manually typed")
        
        # ===== CRITERION 4: Total Calculation (SUM formula) =====
        # Look for a SUM formula with result near $1,140
        expected_total = 1140.03
        found_total = False
        
        # Check rows after the data records for a total
        for row_idx in range(data_start_row + record_count, min(data_start_row + record_count + 10, len(sheet_data))):
            if row_idx >= len(sheet_data):
                break
            
            row = sheet_data[row_idx]
            
            # Check if cost column has a value that looks like a total
            if column_mapping['cost'] < len(row):
                cost_val = extract_numeric_value(row[column_mapping['cost']])
                
                if cost_val and abs(cost_val - expected_total) < 50:  # Within $50 of expected
                    # Verify this cell has a formula
                    cell_has_formula = check_has_formulas(
                        wb, sheet_name,
                        [row_idx],
                        [column_mapping['cost']]
                    )
                    
                    if cell_has_formula:
                        found_total = True
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Total calculation correct: ${cost_val:.2f} (with SUM formula)")
                        break
                    else:
                        feedback_parts.append(f"⚠️ Total value found (${cost_val:.2f}) but no SUM formula detected")
                        break
        
        if not found_total:
            # Calculate actual total from entered costs
            actual_total = sum(
                extract_numeric_value(rec['cost']) or 0 
                for rec in service_records 
                if rec['cost'] is not None
            )
            feedback_parts.append(f"❌ No SUM formula for total cost found (entered data totals: ${actual_total:.2f})")
        
        # ===== CRITERION 5: Professional Formatting =====
        # Check if headers are bold
        headers_bold = False
        cost_col_currency = False
        
        if header_row_idx >= 0:
            # Check at least 2 headers for bold
            bold_count = sum(
                1 for col_idx in list(column_mapping.values())[:4]
                if check_cell_formatting(wb, sheet_name, header_row_idx, col_idx, 'bold')
            )
            headers_bold = bold_count >= 2
        
        # Check if cost column uses currency format
        if service_records and column_mapping['cost'] is not None:
            # Check first few data rows
            currency_count = sum(
                1 for rec in service_records[:5]
                if check_cell_formatting(wb, sheet_name, rec['row_idx'], column_mapping['cost'], 'currency')
            )
            cost_col_currency = currency_count >= 2
        
        if headers_bold and cost_col_currency:
            criteria_passed += 1
            feedback_parts.append("✅ Professional formatting: headers bold, costs as currency")
        elif headers_bold:
            feedback_parts.append("⚠️ Headers bold but costs not formatted as currency")
        elif cost_col_currency:
            feedback_parts.append("⚠️ Costs formatted as currency but headers not bold")
        else:
            feedback_parts.append("❌ Missing formatting: headers should be bold, costs should be currency ($)")
        
        # ===== CRITERION 6: Chronological Order =====
        # Parse dates and check if sorted
        dates_parsed = []
        for rec in service_records[:10]:  # Check first 10 records
            parsed_date = parse_date_flexible(rec['date'])
            if parsed_date:
                dates_parsed.append(parsed_date)
        
        if len(dates_parsed) >= 3:
            is_sorted = all(dates_parsed[i] <= dates_parsed[i+1] for i in range(len(dates_parsed)-1))
            
            if is_sorted:
                criteria_passed += 1
                feedback_parts.append(f"✅ Records sorted chronologically ({dates_parsed[0].strftime('%m/%d/%Y')} to {dates_parsed[-1].strftime('%m/%d/%Y')})")
            else:
                feedback_parts.append("❌ Records not sorted by date (should be oldest to newest)")
        else:
            feedback_parts.append("⚠️ Could not verify date sorting (too few valid dates)")
        
        # ===== Calculate Final Score =====
        score = int((criteria_passed / 6) * 100)
        passed = score >= 67  # Need 4/6 criteria
        
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
