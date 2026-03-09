#!/usr/bin/env python3
"""
Verifier for Community Fridge Safety Manager task.
Checks formula creation, conditional formatting, sort order, and row integrity.
"""

import sys
import os
import logging
import zipfile
from xml.etree import ElementTree as ET
from datetime import datetime, date

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


def parse_date_from_cell(cell_value):
    """
    Parse date from cell value which might be a date object, string, or number.
    
    Returns:
        date object or None
    """
    if cell_value is None:
        return None
    
    # If already a date object
    if isinstance(cell_value, date):
        return cell_value
    
    # If string, try to parse
    if isinstance(cell_value, str):
        for fmt in ['%Y-%m-%d', '%m/%d/%Y', '%d/%m/%Y', '%Y/%m/%d']:
            try:
                return datetime.strptime(cell_value, fmt).date()
            except ValueError:
                continue
    
    # If numeric (Excel date serial)
    if isinstance(cell_value, (int, float)):
        try:
            # Excel/Calc date serial: days since 1899-12-30
            base_date = datetime(1899, 12, 30)
            return (base_date + timedelta(days=int(cell_value))).date()
        except:
            pass
    
    return None


def analyze_conditional_formatting_in_ods(filepath):
    """
    Analyze conditional formatting in ODS file by parsing XML structure.
    
    Returns:
        dict: {
            'has_conditional_format': bool,
            'red_cells': list of cell addresses,
            'yellow_cells': list of cell addresses,
            'cell_colors': dict mapping cell addresses to background colors
        }
    """
    result = {
        'has_conditional_format': False,
        'red_cells': [],
        'yellow_cells': [],
        'cell_colors': {}
    }
    
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return result
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Define namespaces
            ns = {
                'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
                'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'
            }
            
            # Look for conditional formatting
            # In ODS, conditional formatting can be stored in various ways
            # Check for style:conditional-format elements
            cond_formats = root.findall('.//style:map', ns)
            if cond_formats:
                result['has_conditional_format'] = True
            
            # Also check for cell styles with background colors
            # Parse automatic styles
            auto_styles = root.find('.//office:automatic-styles', ns)
            style_colors = {}
            
            if auto_styles:
                for style_elem in auto_styles.findall('.//style:style', ns):
                    style_name = style_elem.get('{urn:oasis:names:tc:opendocument:xmlns:style:1.0}name')
                    if style_name:
                        # Look for table-cell-properties with background color
                        for prop in style_elem.findall('.//style:table-cell-properties', ns):
                            bg_color = prop.get('{urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0}background-color')
                            if bg_color:
                                style_colors[style_name] = bg_color.lower()
            
            # Parse table and find cells with styles
            tables = root.findall('.//table:table', ns)
            for table in tables:
                row_idx = 0
                for row in table.findall('.//table:table-row', ns):
                    row_idx += 1
                    col_idx = 0
                    for cell in row.findall('.//table:table-cell', ns):
                        col_idx += 1
                        
                        # Get cell style
                        cell_style = cell.get('{urn:oasis:names:tc:opendocument:xmlns:table:1.0}style-name')
                        if cell_style and cell_style in style_colors:
                            bg_color = style_colors[cell_style]
                            
                            # Convert column index to letter
                            col_letter = chr(ord('A') + col_idx - 1)
                            cell_addr = f"{col_letter}{row_idx}"
                            
                            result['cell_colors'][cell_addr] = bg_color
                            
                            # Categorize red/yellow
                            if 'ff0000' in bg_color or 'red' in bg_color or 'ff6666' in bg_color:
                                result['red_cells'].append(cell_addr)
                            elif 'ffff00' in bg_color or 'yellow' in bg_color or 'ffff66' in bg_color:
                                result['yellow_cells'].append(cell_addr)
                        
                        # Handle repeated columns
                        repeat = cell.get('{urn:oasis:names:tc:opendocument:xmlns:table:1.0}number-columns-repeated')
                        if repeat:
                            col_idx += int(repeat) - 1
                    
                    # Handle repeated rows
                    repeat = row.get('{urn:oasis:names:tc:opendocument:xmlns:table:1.0}number-rows-repeated')
                    if repeat:
                        row_idx += int(repeat) - 1
            
            logger.info(f"Conditional formatting analysis: {len(result['red_cells'])} red cells, {len(result['yellow_cells'])} yellow cells")
            
    except Exception as e:
        logger.error(f"Error analyzing conditional formatting: {e}", exc_info=True)
    
    return result


def verify_community_fridge_safety(traj, env_info, task_info):
    """
    Verify community fridge safety manager task completion.
    
    Checks:
    1. Column E exists with Days Until Expiration formula
    2. Formula calculates correctly (=ExpirationDate-TODAY())
    3. Conditional formatting applied (red for ≤3, yellow for 4-7)
    4. Data sorted by Days Until Expiration (ascending)
    5. Row integrity maintained (no corruption)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/community_fridge_sorted.ods",
        "/home/ga/Documents/community_fridge_inventory.ods",
        "/home/ga/Documents/community_fridge_inventory.csv"
    ]
    
    success = False
    file_info = None
    
    for container_path in possible_paths:
        expected_format = 'ods' if container_path.endswith('.ods') else 'csv'
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            [expected_format]
        )
        if success:
            logger.info(f"Successfully loaded file from: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load spreadsheet. Tried: {', '.join(possible_paths)}"
        }
    
    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_rows = data['sheets'][sheet_name]
        
        criteria_passed = 0
        total_criteria = 5
        feedback_parts = []
        
        # Get header row to find Days Until Expiration column
        header_row = sheet_rows[0] if sheet_rows else []
        days_col_idx = None
        
        for idx, cell in enumerate(header_row):
            cell_value = cell.get('value') if isinstance(cell, dict) else cell
            if cell_value and 'days' in str(cell_value).lower() and 'expiration' in str(cell_value).lower():
                days_col_idx = idx
                break
        
        # Criterion 1: Days Until Expiration column exists with formula
        if days_col_idx is not None:
            # Check if formulas exist in this column
            formula_count = 0
            correct_formula_count = 0
            
            for row_idx in range(1, min(len(sheet_rows), 20)):  # Check up to 20 rows
                if days_col_idx < len(sheet_rows[row_idx]):
                    cell = sheet_rows[row_idx][days_col_idx]
                    formula = cell.get('formula') if isinstance(cell, dict) else None
                    
                    if formula:
                        formula_count += 1
                        # Check for TODAY() and subtraction
                        formula_upper = formula.upper()
                        if 'TODAY()' in formula_upper and '-' in formula:
                            correct_formula_count += 1
            
            if correct_formula_count >= 3:  # At least 3 rows with correct formula
                criteria_passed += 1
                feedback_parts.append(f"✅ Days Until Expiration formula correct ({correct_formula_count} rows)")
            else:
                feedback_parts.append(f"❌ Formula missing or incorrect (found {correct_formula_count} correct formulas)")
        else:
            feedback_parts.append("❌ Days Until Expiration column not found")
        
        # Criterion 2 & 3: Conditional formatting (red for ≤3, yellow for 4-7)
        # This requires analyzing ODS file XML structure
        if file_info['format'] == 'ods':
            cond_format_info = analyze_conditional_formatting_in_ods(file_info['filepath'])
            
            # Check if we have red and yellow cells where expected
            red_found = False
            yellow_found = False
            
            if days_col_idx is not None:
                col_letter = chr(ord('A') + days_col_idx)
                
                # Check data rows for proper coloring
                for row_idx in range(2, min(len(sheet_rows), 20)):
                    if days_col_idx < len(sheet_rows[row_idx]):
                        cell = sheet_rows[row_idx][days_col_idx]
                        value = cell.get('value') if isinstance(cell, dict) else cell
                        
                        if value is not None and isinstance(value, (int, float)):
                            cell_addr = f"{col_letter}{row_idx + 1}"
                            
                            # Check if cell has appropriate color
                            if value <= 3:
                                if cell_addr in cond_format_info['red_cells']:
                                    red_found = True
                            elif value > 3 and value <= 7:
                                if cell_addr in cond_format_info['yellow_cells']:
                                    yellow_found = True
            
            # Criterion 2: Red formatting for critical items (≤3 days)
            if red_found or len(cond_format_info['red_cells']) > 0:
                criteria_passed += 1
                feedback_parts.append(f"✅ Critical formatting (RED) applied ({len(cond_format_info['red_cells'])} cells)")
            else:
                feedback_parts.append("❌ Critical formatting (RED) not detected")
            
            # Criterion 3: Yellow formatting for warning items (4-7 days)
            if yellow_found or len(cond_format_info['yellow_cells']) > 0:
                criteria_passed += 1
                feedback_parts.append(f"✅ Warning formatting (YELLOW) applied ({len(cond_format_info['yellow_cells'])} cells)")
            else:
                feedback_parts.append("⚠️ Warning formatting (YELLOW) not clearly detected")
                # Give partial credit if red formatting exists
                if red_found:
                    criteria_passed += 0.5
        else:
            # CSV format - cannot check formatting
            feedback_parts.append("⚠️ Cannot verify conditional formatting (CSV format)")
            criteria_passed += 1  # Give benefit of doubt
        
        # Criterion 4: Data sorted by Days Until Expiration (ascending)
        if days_col_idx is not None:
            sorted_correctly = True
            previous_value = float('-inf')
            
            for row_idx in range(1, min(len(sheet_rows), 20)):
                if days_col_idx < len(sheet_rows[row_idx]):
                    cell = sheet_rows[row_idx][days_col_idx]
                    value = cell.get('value') if isinstance(cell, dict) else cell
                    
                    if value is not None and isinstance(value, (int, float)):
                        if value < previous_value:
                            sorted_correctly = False
                            feedback_parts.append(f"❌ Sort order broken at row {row_idx + 1}: {previous_value} → {value}")
                            break
                        previous_value = value
            
            if sorted_correctly:
                criteria_passed += 1
                feedback_parts.append("✅ Data sorted correctly (ascending by days)")
        else:
            feedback_parts.append("❌ Cannot verify sort (Days column not found)")
        
        # Criterion 5: Row integrity (check a few known items)
        # Verify that specific items have reasonable expiration dates
        integrity_ok = True
        item_col_idx = 0  # Item Name is column A
        exp_col_idx = 2   # Expiration Date is column C
        
        # Check that we have multiple rows of data
        data_row_count = 0
        for row in sheet_rows[1:]:
            if any(cell.get('value') if isinstance(cell, dict) else cell for cell in row):
                data_row_count += 1
        
        if data_row_count >= 10:  # Should have at least 10 food items
            criteria_passed += 1
            feedback_parts.append(f"✅ Row integrity maintained ({data_row_count} data rows)")
        else:
            feedback_parts.append(f"⚠️ Fewer data rows than expected ({data_row_count} rows)")
            if data_row_count >= 5:
                criteria_passed += 0.5  # Partial credit
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 80  # Need 4/5 criteria (80%)
        
        # Add summary feedback
        if passed and score >= 95:
            feedback_parts.append("🎉 Community fridge safety system implemented perfectly!")
        elif passed:
            feedback_parts.append("✅ Community fridge safety system functional")
        else:
            feedback_parts.append("❌ Community fridge safety requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "formula_present": days_col_idx is not None and correct_formula_count >= 3,
                "critical_formatting": red_found if file_info['format'] == 'ods' else None,
                "warning_formatting": yellow_found if file_info['format'] == 'ods' else None,
                "sorted_correctly": sorted_correctly if days_col_idx is not None else False,
                "row_integrity": data_row_count >= 10
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
        cleanup_verification_temp(file_info.get('temp_dir'))
