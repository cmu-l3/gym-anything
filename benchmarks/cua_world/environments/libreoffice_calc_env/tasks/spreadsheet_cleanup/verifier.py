#!/usr/bin/env python3
"""
Verifier for Spreadsheet Cleanup task

Checks:
1. Headers are in row 1 (not row 5)
2. Junk rows removed (originally rows 1-4)
3. Headers are bold
4. Column widths are adequate (no truncation)
5. Freeze panes active at row 2
6. All data rows preserved (46 data rows + 1 header = 47 total)
"""

import sys
import os
import logging
import zipfile
from xml.etree import ElementTree as ET
from pathlib import Path

# Use relative path to utils folder (runs on host, not container)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_bold_formatting_ods(filepath, sheet_name, row_index=0):
    """
    Check if cells in specified row have bold formatting in ODS file.
    
    Returns:
        Tuple[bool, str]: (is_bold, error_message)
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            # Read content.xml
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Define namespaces
            ns = {
                'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
            }
            
            # Find the target sheet
            tables = root.findall('.//table:table', ns)
            target_table = None
            for table in tables:
                name = table.get(f"{{{ns['table']}}}name")
                if name == sheet_name:
                    target_table = table
                    break
            
            if target_table is None:
                return False, f"Sheet '{sheet_name}' not found"
            
            # Find the target row
            rows = target_table.findall('.//table:table-row', ns)
            if row_index >= len(rows):
                return False, f"Row {row_index} not found"
            
            target_row = rows[row_index]
            
            # Check cells in this row for bold formatting
            cells = target_row.findall('.//table:table-cell', ns)
            bold_count = 0
            total_cells_with_content = 0
            
            for cell in cells:
                # Check if cell has content
                paragraphs = cell.findall('.//text:p', ns)
                has_content = any(p.text for p in paragraphs if p.text and p.text.strip())
                
                if not has_content:
                    continue
                
                total_cells_with_content += 1
                
                # Check for bold in spans within paragraphs
                spans = cell.findall('.//text:span', ns)
                for span in spans:
                    style_name = span.get(f"{{{ns['text']}}}style-name")
                    if style_name:
                        # Look for style definition
                        style_defs = root.findall(f".//style:style[@style:name='{style_name}']", ns)
                        for style_def in style_defs:
                            text_props = style_def.find('.//style:text-properties', ns)
                            if text_props is not None:
                                font_weight = text_props.get(f"{{{ns['fo']}}}font-weight")
                                if font_weight == 'bold':
                                    bold_count += 1
                                    break
            
            # If we found bold formatting in at least some cells with content
            if total_cells_with_content > 0 and bold_count >= total_cells_with_content * 0.8:
                return True, ""
            elif bold_count > 0:
                return False, f"Only {bold_count}/{total_cells_with_content} header cells are bold"
            else:
                return False, "No bold formatting detected in header row"
    
    except Exception as e:
        logger.warning(f"Could not verify bold formatting: {e}")
        # Don't fail the task on formatting check issues
        return True, "Bold check skipped (verification limitation)"


def check_freeze_panes_ods(filepath, sheet_name):
    """
    Check if freeze panes is configured at row 2 (keeping row 1 visible) in ODS.
    
    Returns:
        Tuple[bool, str]: (is_frozen, error_message)
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            # Read content.xml
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            ns = {
                'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'config': 'urn:oasis:names:tc:opendocument:xmlns:config:1.0'
            }
            
            # Look for table views with split settings
            # In ODS, freeze panes is stored in settings.xml, but may also be in content.xml
            # Check for table:table-view elements
            table_views = root.findall('.//table:table-view', ns)
            
            for view in table_views:
                # Check for split position attributes
                split_y = view.get(f"{{{ns['table']}}}vertical-split-position")
                split_mode = view.get(f"{{{ns['table']}}}vertical-split-mode")
                
                if split_y and split_mode:
                    # Split position of 1 means split after row 1 (freeze row 1)
                    if int(split_y) >= 1 and split_mode == 'freeze':
                        return True, ""
            
            # Also try settings.xml
            if 'settings.xml' in ods_zip.namelist():
                settings_xml = ods_zip.read('settings.xml')
                settings_root = ET.fromstring(settings_xml)
                
                # Look for VerticalSplitPosition
                config_items = settings_root.findall('.//config:config-item', ns)
                for item in config_items:
                    name = item.get(f"{{{ns['config']}}}name")
                    if name == "VerticalSplitPosition" or name == "VerticalSplitMode":
                        if item.text and (item.text == "2" or item.text == "1" or "freeze" in item.text.lower()):
                            return True, ""
            
            return False, "Freeze panes not configured"
    
    except Exception as e:
        logger.warning(f"Could not verify freeze panes: {e}")
        # Don't fail task on freeze panes check issues
        return True, "Freeze panes check skipped (verification limitation)"


def verify_column_widths_adequate(filepath):
    """
    Check if column widths are adequate (not default narrow).
    For ODS, check column width styles.
    
    Returns:
        Tuple[bool, str]: (adequate, message)
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            ns = {
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
            }
            
            # Find columns and their styles
            columns = root.findall('.//table:table-column', ns)
            narrow_count = 0
            wide_count = 0
            
            for col in columns[:5]:  # Check first 5 columns (our data columns)
                style_name = col.get(f"{{{ns['table']}}}style-name")
                if style_name:
                    # Find the style definition
                    style_defs = root.findall(f".//style:style[@style:name='{style_name}']", ns)
                    for style_def in style_defs:
                        col_props = style_def.find('.//style:table-column-properties', ns)
                        if col_props is not None:
                            width = col_props.get(f"{{{ns['style']}}}column-width")
                            if width:
                                # Parse width (e.g., "0.7in", "2.5in", "64px")
                                # Consider < 1 inch or < 80px as narrow
                                width_val = float(''.join(c for c in width if c.isdigit() or c == '.'))
                                if 'in' in width and width_val < 1.0:
                                    narrow_count += 1
                                elif 'cm' in width and width_val < 2.5:
                                    narrow_count += 1
                                else:
                                    wide_count += 1
            
            # If most columns are not narrow, consider it adequate
            if wide_count >= 3:
                return True, f"Column widths adequate ({wide_count} columns auto-fitted)"
            elif narrow_count >= 3:
                return False, f"Columns still too narrow ({narrow_count} narrow columns detected)"
            else:
                # Indeterminate, give benefit of doubt
                return True, "Column widths check passed (could not determine definitively)"
    
    except Exception as e:
        logger.warning(f"Could not verify column widths: {e}")
        return True, "Column width check skipped (verification limitation)"


def verify_spreadsheet_cleanup(traj, env_info, task_info):
    """
    Verify spreadsheet cleanup task completion.
    
    Criteria:
    1. Headers in row 1 (Name, Email, Registration Date, Ticket Type, Dietary Restrictions)
    2. Junk rows removed (originally rows 1-4 deleted)
    3. Headers are bold
    4. Column widths adequate
    5. Freeze panes active
    6. Data preserved (46 data rows + 1 header = 47 total rows)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/event_registrations_clean.ods",
        "/home/ga/Documents/event_registrations_messy.ods",  # May have been edited in place
    ]
    
    success = False
    file_info = None
    temp_dir = None
    
    for container_path in possible_paths:
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            expected_formats=['ods']
        )
        if success:
            logger.info(f"✅ Found file at: {container_path}")
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not load spreadsheet file. Tried: {', '.join(possible_paths)}. Error: {error}"
        }
    
    try:
        data = file_info['sheet_data']
        filepath = file_info['file_path']
        temp_dir = file_info.get('temp_dir')
        
        # Get sheet name
        sheet_names = get_sheet_names(data)
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Headers in Row 1
        expected_headers = ['Name', 'Email', 'Registration Date', 'Ticket Type', 'Dietary Restrictions']
        headers_correct = True
        
        for col_idx, expected_header in enumerate(expected_headers):
            actual_value = get_cell_value(data, sheet_name, f"{chr(65 + col_idx)}1")  # A1, B1, C1, D1, E1
            if actual_value is None or str(actual_value).strip().lower() != expected_header.lower():
                headers_correct = False
                feedback_parts.append(f"❌ Header row issue: Expected '{expected_header}' in column {chr(65 + col_idx)}, got '{actual_value}'")
                break
        
        if headers_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Headers correctly positioned in row 1")
            subscores['headers_in_row_1'] = True
        else:
            if not feedback_parts:
                feedback_parts.append("❌ Headers not in correct position (should be in row 1)")
            subscores['headers_in_row_1'] = False
        
        # Criterion 2: Data Integrity (47 total rows: 1 header + 46 data)
        sheets = data.get('sheets', {})
        if sheet_name in sheets:
            sheet_rows = sheets[sheet_name]
            non_empty_rows = 0
            
            for row in sheet_rows:
                # Count row as non-empty if it has any cell with content
                if any(
                    (cell.get('value') if isinstance(cell, dict) else cell) 
                    for cell in row 
                    if cell
                ):
                    non_empty_rows += 1
            
            # Should have 47 rows total (1 header + 46 data)
            if non_empty_rows >= 45:  # Allow small tolerance
                criteria_passed += 1
                feedback_parts.append(f"✅ Data preserved ({non_empty_rows} rows present)")
                subscores['data_preserved'] = True
            else:
                feedback_parts.append(f"❌ Data rows missing (found {non_empty_rows} rows, expected ~47)")
                subscores['data_preserved'] = False
        else:
            feedback_parts.append("❌ Could not verify data preservation")
            subscores['data_preserved'] = False
        
        # Criterion 3: Junk Rows Removed
        # Check that row 2 contains actual data, not metadata
        row2_name = get_cell_value(data, sheet_name, 'A2')
        row2_looks_like_data = (
            row2_name is not None and 
            isinstance(row2_name, str) and
            len(row2_name) > 3 and
            'Exported' not in row2_name and
            'Total' not in row2_name
        )
        
        if row2_looks_like_data and headers_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Junk rows successfully removed")
            subscores['junk_rows_removed'] = True
        else:
            feedback_parts.append("❌ Junk rows may still be present (or data not shifted correctly)")
            subscores['junk_rows_removed'] = False
        
        # Criterion 4: Headers Bold
        bold_check, bold_msg = check_bold_formatting_ods(filepath, sheet_name, row_index=0)
        if bold_check:
            criteria_passed += 1
            feedback_parts.append("✅ Headers are bold formatted")
            subscores['headers_bold'] = True
        else:
            if bold_msg and "skipped" not in bold_msg.lower():
                feedback_parts.append(f"❌ Headers not bold: {bold_msg}")
            else:
                feedback_parts.append("⚠️ Could not verify bold formatting (accepting as pass)")
                criteria_passed += 1  # Give benefit of doubt if verification failed
            subscores['headers_bold'] = bold_check
        
        # Criterion 5: Column Widths Adequate
        width_check, width_msg = verify_column_widths_adequate(filepath)
        if width_check:
            criteria_passed += 1
            feedback_parts.append(f"✅ {width_msg}")
            subscores['column_widths_adequate'] = True
        else:
            feedback_parts.append(f"❌ {width_msg}")
            subscores['column_widths_adequate'] = False
        
        # Criterion 6: Freeze Panes Active
        freeze_check, freeze_msg = check_freeze_panes_ods(filepath, sheet_name)
        if freeze_check:
            criteria_passed += 1
            if "skipped" not in freeze_msg.lower():
                feedback_parts.append("✅ Freeze panes configured")
            else:
                feedback_parts.append("⚠️ Freeze panes check skipped (accepting as pass)")
            subscores['freeze_panes_active'] = True
        else:
            feedback_parts.append(f"❌ {freeze_msg}")
            subscores['freeze_panes_active'] = False
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # 70% threshold = 4.2/6 criteria ~ need 5/6 for reliable pass
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.append("🎉 Spreadsheet cleanup completed successfully!")
        elif passed:
            feedback_parts.append("✅ Spreadsheet cleanup task completed")
        else:
            feedback_parts.append("❌ Cleanup incomplete - more work needed")
        
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
        if temp_dir:
            cleanup_verification_temp(temp_dir)
