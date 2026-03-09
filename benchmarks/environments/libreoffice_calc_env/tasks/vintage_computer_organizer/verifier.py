#!/usr/bin/env python3
"""
Verifier for Vintage Computer Collection Organizer task.
Checks formula presence, calculation correctness, conditional formatting, sort order, and data integrity.
"""

import sys
import os
import logging
import re
import zipfile
from xml.etree import ElementTree as ET
from typing import Dict, List, Tuple, Optional, Any

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
    parse_ods_file,
    parse_xlsx_file,
    parse_csv_file
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def calculate_expected_priority(rarity: int, condition: str, parts: str, year: Optional[int]) -> float:
    """
    Calculate expected priority score based on task formula.
    Formula: (Rarity * 2) + Condition_Points + Parts_Points - Age_Penalty
    """
    # Condition mapping
    condition_map = {
        'Excellent': 5, 'excellent': 5,
        'Good': 3, 'good': 3,
        'Fair': 2, 'fair': 2,
        'Poor': 1, 'poor': 1,
        'Unknown': 0, 'unknown': 0,
        '': 0, None: 0
    }
    
    # Parts availability mapping
    parts_map = {
        'Easy': 3, 'easy': 3,
        'Moderate': 2, 'moderate': 2,
        'Hard': 1, 'hard': 1,
        'Impossible': 0, 'impossible': 0,
        '': 0, None: 0
    }
    
    # Calculate components
    rarity_score = rarity * 2
    condition_points = condition_map.get(condition, 0)
    parts_points = parts_map.get(parts, 0)
    
    # Age penalty: (2024 - Year) / 10, rounded down
    # Use 1985 as default for missing years
    year_to_use = year if year else 1985
    age_penalty = int((2024 - year_to_use) / 10)
    
    priority = rarity_score + condition_points + parts_points - age_penalty
    
    logger.debug(f"Priority calc: R={rarity}*2={rarity_score}, C={condition}={condition_points}, "
                 f"P={parts}={parts_points}, Year={year_to_use} Age={age_penalty} => {priority}")
    
    return priority


def extract_conditional_formatting_colors(filepath: str) -> Dict[str, List[str]]:
    """
    Extract conditional formatting information from ODS file.
    Returns dict mapping cell ranges to their background colors.
    """
    colors_by_range = {}
    
    try:
        if not filepath.endswith('.ods'):
            return colors_by_range
        
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return colors_by_range
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # ODS namespace definitions
            namespaces = {
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
            }
            
            # Look for table cells with styles that have background colors
            # This is a simplified check - full conditional formatting parsing is complex
            cells = root.findall('.//table:table-cell', namespaces)
            
            cell_colors = []
            for cell in cells:
                style_name = cell.get('{urn:oasis:names:tc:opendocument:xmlns:table:1.0}style-name')
                if style_name:
                    # Try to find the style definition
                    # This is simplified - in reality would need to traverse automatic-styles
                    cell_colors.append(style_name)
            
            # For now, just check if there are multiple style names (indicator of formatting)
            if len(set(cell_colors)) > 1:
                colors_by_range['detected'] = list(set(cell_colors))
                logger.info(f"Detected multiple cell styles: {len(set(cell_colors))} unique styles")
        
    except Exception as e:
        logger.debug(f"Could not extract conditional formatting: {e}")
    
    return colors_by_range


def check_cell_background_color(filepath: str, sheet_name: str, col: int, row: int) -> Optional[str]:
    """
    Check if a specific cell has a background color applied.
    Returns color hex or None.
    """
    try:
        if not filepath.endswith('.ods'):
            return None
        
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return None
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # This is complex in ODS - simplified check
            # Just return "formatted" if we detect style attributes
            return "formatted"
    
    except Exception as e:
        logger.debug(f"Could not check cell color: {e}")
        return None


def verify_vintage_computer_organizer(traj, env_info, task_info):
    """
    Verify vintage computer collection organizer task.
    
    Checks:
    1. Formula present in Priority_Score column
    2. Calculations correct (spot-check 2-3 rows)
    3. Conditional formatting applied
    4. Data sorted by priority descending
    5. Row data integrity maintained
    6. Dataset complete (original + new entries)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file paths and formats
    file_paths = [
        ('ods', '/home/ga/Documents/vintage_computer_collection.ods'),
        ('csv', '/home/ga/Documents/vintage_computers.csv'),
        ('ods', '/home/ga/Documents/vintage_computers.ods'),
        ('xlsx', '/home/ga/Documents/vintage_computer_collection.xlsx'),
    ]
    
    success = False
    file_info = None
    temp_dir = None
    
    for file_format, container_path in file_paths:
        success, file_info, error = setup_calc_verification(
            copy_from_env, 
            container_path, 
            [file_format]
        )
        if success:
            logger.info(f"Successfully loaded: {container_path}")
            temp_dir = file_info.get('temp_dir')
            break
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Could not load spreadsheet file. Tried multiple paths. Last error: {error}"
        }
    
    try:
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())
        
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        sheet_data = data['sheets'][sheet_name]
        
        criteria_met = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Identify columns by header row
        if not sheet_data or len(sheet_data) == 0:
            return {"passed": False, "score": 0, "feedback": "Sheet is empty"}
        
        headers = []
        for cell in sheet_data[0]:
            val = cell.get('value') if isinstance(cell, dict) else cell
            headers.append(str(val).strip() if val else '')
        
        logger.info(f"Headers found: {headers}")
        
        # Find column indices
        model_col = None
        rarity_col = None
        condition_col = None
        parts_col = None
        year_col = None
        priority_col = None
        
        for idx, header in enumerate(headers):
            h_lower = header.lower()
            if 'model' in h_lower:
                model_col = idx
            elif 'rarity' in h_lower:
                rarity_col = idx
            elif 'condition' in h_lower:
                condition_col = idx
            elif 'parts' in h_lower or 'availability' in h_lower:
                parts_col = idx
            elif 'year' in h_lower and 'acquisition' not in h_lower:
                year_col = idx
            elif 'priority' in h_lower or 'score' in h_lower:
                priority_col = idx
        
        # Check if Priority_Score column exists
        if priority_col is None:
            feedback_parts.append("❌ Priority_Score column not found")
            subscores['formula_present'] = False
        else:
            # Criterion 1: Formula present (check a few cells in Priority_Score column)
            formulas_found = 0
            for row_idx in range(1, min(6, len(sheet_data))):  # Check first 5 data rows
                if row_idx < len(sheet_data) and priority_col < len(sheet_data[row_idx]):
                    cell = sheet_data[row_idx][priority_col]
                    formula = cell.get('formula') if isinstance(cell, dict) else None
                    if formula:
                        formulas_found += 1
                        logger.debug(f"Row {row_idx} formula: {formula}")
            
            if formulas_found >= 2:
                criteria_met += 1
                feedback_parts.append(f"✅ Formulas present in Priority_Score column ({formulas_found} found)")
                subscores['formula_present'] = True
            else:
                feedback_parts.append(f"❌ Priority_Score appears hardcoded (only {formulas_found} formulas found)")
                subscores['formula_present'] = False
        
        # Criterion 2: Calculations correct (spot-check)
        if None not in [model_col, rarity_col, condition_col, parts_col, year_col, priority_col]:
            correct_calculations = 0
            checked_rows = 0
            
            # Check up to 3 rows with complete data
            for row_idx in range(1, min(6, len(sheet_data))):
                if row_idx >= len(sheet_data):
                    break
                
                row = sheet_data[row_idx]
                if len(row) <= max(rarity_col, condition_col, parts_col, year_col, priority_col):
                    continue
                
                # Extract values
                rarity_cell = row[rarity_col]
                condition_cell = row[condition_col]
                parts_cell = row[parts_col]
                year_cell = row[year_col]
                priority_cell = row[priority_col]
                
                rarity_val = rarity_cell.get('value') if isinstance(rarity_cell, dict) else rarity_cell
                condition_val = condition_cell.get('value') if isinstance(condition_cell, dict) else condition_cell
                parts_val = parts_cell.get('value') if isinstance(parts_cell, dict) else parts_cell
                year_val = year_cell.get('value') if isinstance(year_cell, dict) else year_cell
                priority_val = priority_cell.get('value') if isinstance(priority_cell, dict) else priority_cell
                
                # Skip if key values missing
                if not rarity_val or not condition_val or not parts_val:
                    continue
                
                try:
                    rarity_int = int(rarity_val)
                    year_int = int(year_val) if year_val and str(year_val).strip() else None
                    priority_actual = float(priority_val) if priority_val else None
                    
                    if priority_actual is None:
                        continue
                    
                    # Calculate expected priority
                    expected_priority = calculate_expected_priority(
                        rarity_int, 
                        str(condition_val), 
                        str(parts_val), 
                        year_int
                    )
                    
                    # Allow tolerance of ±1 (rounding differences)
                    if abs(priority_actual - expected_priority) <= 1:
                        correct_calculations += 1
                    else:
                        logger.warning(f"Row {row_idx}: Expected priority ~{expected_priority}, got {priority_actual}")
                    
                    checked_rows += 1
                    
                    if checked_rows >= 3:
                        break
                
                except (ValueError, TypeError) as e:
                    logger.debug(f"Could not verify row {row_idx}: {e}")
                    continue
            
            if checked_rows > 0 and correct_calculations >= 2:
                criteria_met += 1
                feedback_parts.append(f"✅ Priority calculations correct ({correct_calculations}/{checked_rows} checked)")
                subscores['calculations_correct'] = True
            elif checked_rows > 0:
                feedback_parts.append(f"❌ Priority calculations incorrect ({correct_calculations}/{checked_rows} correct)")
                subscores['calculations_correct'] = False
            else:
                feedback_parts.append("⚠️ Could not verify calculations (insufficient data)")
                subscores['calculations_correct'] = False
        else:
            feedback_parts.append("⚠️ Missing required columns for calculation verification")
            subscores['calculations_correct'] = False
        
        # Criterion 3: Conditional formatting (simplified check)
        # For ODS files, check if there are style variations
        # For CSV/XLSX, this may not be detectable
        formatting_detected = False
        if file_info.get('format') == 'ods':
            colors = extract_conditional_formatting_colors(file_info['file_path'])
            if colors:
                criteria_met += 1
                feedback_parts.append("✅ Conditional formatting detected (multiple cell styles)")
                subscores['conditional_formatting'] = True
                formatting_detected = True
        
        if not formatting_detected:
            # Give partial credit if we can't definitively check
            feedback_parts.append("⚠️ Conditional formatting not verifiable in this format")
            subscores['conditional_formatting'] = False
        
        # Criterion 4: Sorted descending by priority
        if priority_col is not None:
            priority_values = []
            for row_idx in range(1, len(sheet_data)):
                if row_idx < len(sheet_data) and priority_col < len(sheet_data[row_idx]):
                    cell = sheet_data[row_idx][priority_col]
                    val = cell.get('value') if isinstance(cell, dict) else cell
                    if val is not None and str(val).strip():
                        try:
                            priority_values.append(float(val))
                        except (ValueError, TypeError):
                            pass
            
            if len(priority_values) >= 3:
                is_sorted_desc = all(
                    priority_values[i] >= priority_values[i+1] 
                    for i in range(len(priority_values)-1)
                )
                
                if is_sorted_desc:
                    criteria_met += 1
                    feedback_parts.append(f"✅ Data sorted by priority descending ({len(priority_values)} rows)")
                    subscores['sorted_descending'] = True
                else:
                    feedback_parts.append(f"❌ Data not sorted correctly (priority values: {priority_values[:5]}...)")
                    subscores['sorted_descending'] = False
            else:
                feedback_parts.append("⚠️ Insufficient priority values to verify sort order")
                subscores['sorted_descending'] = False
        else:
            feedback_parts.append("❌ Cannot verify sort order without Priority_Score column")
            subscores['sorted_descending'] = False
        
        # Criterion 5: Data integrity (check that model names are unique or if duplicates exist, they match their scores)
        # Simplified: just check that there are distinct model names
        if model_col is not None:
            model_names = []
            for row_idx in range(1, len(sheet_data)):
                if row_idx < len(sheet_data) and model_col < len(sheet_data[row_idx]):
                    cell = sheet_data[row_idx][model_col]
                    val = cell.get('value') if isinstance(cell, dict) else cell
                    if val and str(val).strip():
                        model_names.append(str(val).strip())
            
            unique_models = len(set(model_names))
            total_models = len(model_names)
            
            # If most models are unique, data integrity is likely maintained
            if unique_models >= total_models * 0.8:  # At least 80% unique
                criteria_met += 1
                feedback_parts.append(f"✅ Data integrity maintained ({unique_models} unique models)")
                subscores['data_integrity'] = True
            else:
                feedback_parts.append(f"⚠️ Possible data integrity issue ({unique_models}/{total_models} unique)")
                subscores['data_integrity'] = False
        else:
            feedback_parts.append("⚠️ Cannot verify data integrity without Model column")
            subscores['data_integrity'] = False
        
        # Criterion 6: Dataset complete (original 10 + new entries)
        data_row_count = len(sheet_data) - 1  # Exclude header
        
        if data_row_count >= 13:  # 10 original + 3 new minimum
            criteria_met += 1
            feedback_parts.append(f"✅ Dataset complete ({data_row_count} total entries, {data_row_count - 10} new)")
            subscores['dataset_complete'] = True
        elif data_row_count >= 10:
            feedback_parts.append(f"⚠️ Some new entries may be missing ({data_row_count} total, expected 13+)")
            subscores['dataset_complete'] = False
        else:
            feedback_parts.append(f"❌ Original data incomplete ({data_row_count} rows, expected 13+)")
            subscores['dataset_complete'] = False
        
        # Calculate final score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 80  # 5/6 criteria = 83%
        
        # Add summary
        if passed and score >= 95:
            feedback_parts.append("🎉 Excellent collection organization!")
        elif passed:
            feedback_parts.append("✅ Collection organized successfully")
        else:
            feedback_parts.append("❌ Collection organization incomplete")
        
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
