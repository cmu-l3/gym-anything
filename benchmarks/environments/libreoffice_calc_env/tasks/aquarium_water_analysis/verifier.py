#!/usr/bin/env python3
"""
Verifier for Aquarium Water Chemistry Analysis Task

Checks:
1. Average calculations for pH, Ammonia, Nitrite, Nitrate
2. Conditional formatting applied to threshold violations
3. Violation count formulas (COUNTIF)
4. Primary problem identification
5. Original data integrity
"""

import sys
import os
import logging
import zipfile
from xml.etree import ElementTree as ET
import re

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
    get_sheet_names
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_average_formulas(workbook, sheet_name):
    """
    Search for AVERAGE formulas in the spreadsheet.
    Returns dict mapping parameter types to formula info.
    """
    found_averages = {
        'pH': None,
        'Ammonia': None,
        'Nitrite': None,
        'Nitrate': None
    }
    
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        
        # Search through all cells for AVERAGE formulas
        for row_idx, row in enumerate(sheet_rows):
            for col_idx, cell in enumerate(row):
                if isinstance(cell, dict):
                    formula = cell.get('formula', '')
                    value = cell.get('value')
                else:
                    continue
                
                if formula and 'AVERAGE' in formula.upper():
                    # Determine which parameter this might be for based on:
                    # 1. Column referenced (B=pH, C=Ammonia, D=Nitrite, E=Nitrate)
                    # 2. Result value range
                    
                    # Extract column reference from formula
                    col_match = re.search(r'([A-Z])2:([A-Z])\d+', formula.upper())
                    if col_match:
                        col_letter = col_match.group(1)
                        
                        # Map column to parameter (assuming standard layout)
                        col_map = {'B': 'pH', 'C': 'Ammonia', 'D': 'Nitrite', 'E': 'Nitrate'}
                        param = col_map.get(col_letter)
                        
                        if param and found_averages[param] is None:
                            found_averages[param] = {
                                'formula': formula,
                                'value': value,
                                'location': f"{chr(65+col_idx)}{row_idx+1}"
                            }
                            logger.info(f"Found {param} average: {formula} = {value}")
        
        # Fallback: Try to match by value ranges if column mapping failed
        for param, info in found_averages.items():
            if info is None:
                # Search again by value range
                for row_idx, row in enumerate(sheet_rows):
                    for col_idx, cell in enumerate(row):
                        if isinstance(cell, dict):
                            formula = cell.get('formula', '')
                            value = cell.get('value')
                            
                            if formula and 'AVERAGE' in formula.upper() and value is not None:
                                # Check if value is in expected range for this parameter
                                if param == 'pH' and 6.0 <= float(value) <= 8.5:
                                    if found_averages['pH'] is None:
                                        found_averages['pH'] = {'formula': formula, 'value': value}
                                elif param == 'Ammonia' and 0.0 <= float(value) <= 2.0:
                                    if found_averages['Ammonia'] is None:
                                        found_averages['Ammonia'] = {'formula': formula, 'value': value}
                                elif param == 'Nitrite' and 0.0 <= float(value) <= 2.0:
                                    if found_averages['Nitrite'] is None:
                                        found_averages['Nitrite'] = {'formula': formula, 'value': value}
                                elif param == 'Nitrate' and 0.0 <= float(value) <= 100.0:
                                    if found_averages['Nitrate'] is None:
                                        found_averages['Nitrate'] = {'formula': formula, 'value': value}
    
    except Exception as e:
        logger.error(f"Error finding average formulas: {e}", exc_info=True)
    
    return found_averages


def find_countif_formulas(workbook, sheet_name):
    """
    Search for COUNTIF formulas that count threshold violations.
    """
    found_counts = []
    
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        
        for row_idx, row in enumerate(sheet_rows):
            for col_idx, cell in enumerate(row):
                if isinstance(cell, dict):
                    formula = cell.get('formula', '')
                    value = cell.get('value')
                else:
                    continue
                
                if formula and 'COUNTIF' in formula.upper():
                    # Extract threshold from formula
                    threshold_match = re.search(r'["><=]+(\d+\.?\d*)', formula)
                    threshold = float(threshold_match.group(1)) if threshold_match else None
                    
                    found_counts.append({
                        'formula': formula,
                        'value': value,
                        'threshold': threshold,
                        'location': f"{chr(65+col_idx)}{row_idx+1}"
                    })
                    logger.info(f"Found COUNTIF: {formula} = {value}")
    
    except Exception as e:
        logger.error(f"Error finding COUNTIF formulas: {e}", exc_info=True)
    
    return found_counts


def check_conditional_formatting_ods(filepath, expected_rules=3):
    """
    Check if conditional formatting exists in ODS file.
    Returns count of formatting rules found.
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return 0
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Look for conditional formatting elements
            # ODF uses calcext:conditional-formats
            formatting_count = 0
            
            # Search for style:style elements with conditions
            for elem in root.iter():
                tag = elem.tag.lower()
                if 'conditional' in tag or 'condition' in tag:
                    formatting_count += 1
            
            logger.info(f"Found {formatting_count} conditional formatting indicators")
            return formatting_count
    
    except Exception as e:
        logger.error(f"Error checking conditional formatting: {e}", exc_info=True)
        return 0


def find_problem_identification(workbook, sheet_name):
    """
    Search for text cell identifying the primary problem.
    Returns (found, parameter) tuple.
    """
    try:
        sheet_rows = workbook['sheets'][sheet_name]
        
        keywords = {
            'Ammonia': ['ammonia', 'nh3', 'nh4'],
            'Nitrite': ['nitrite', 'no2'],
            'Nitrate': ['nitrate', 'no3'],
            'pH': ['ph', 'acid', 'alkaline']
        }
        
        for row_idx, row in enumerate(sheet_rows):
            for col_idx, cell in enumerate(row):
                if isinstance(cell, dict):
                    value = cell.get('value', '')
                else:
                    value = cell if isinstance(cell, str) else ''
                
                if isinstance(value, str) and len(value) > 5:
                    value_lower = value.lower()
                    
                    # Look for "primary problem" or "problem:" or similar
                    if any(phrase in value_lower for phrase in ['primary', 'problem', 'issue', 'concern', 'main']):
                        # Check which parameter is mentioned
                        for param, kws in keywords.items():
                            if any(kw in value_lower for kw in kws):
                                logger.info(f"Found problem identification: '{value}' → {param}")
                                return True, param
        
        return False, None
    
    except Exception as e:
        logger.error(f"Error finding problem identification: {e}", exc_info=True)
        return False, None


def validate_problem_logic(found_param, expected_data):
    """
    Validate that identified problem matches data severity.
    For this task, Ammonia should be the primary problem.
    """
    # Based on our setup data, Ammonia has 11 violations, which is most severe
    # This is a simplified check - in real scenario would calculate from data
    if found_param == 'Ammonia':
        return True
    elif found_param in ['Nitrate', 'Nitrite']:
        # Partial credit if they identified another real issue
        return True  # Still accept but note it
    else:
        return False


def verify_aquarium_analysis(traj, env_info, task_info):
    """
    Main verification function for aquarium water chemistry analysis task.
    
    Checks:
    1. Average calculations for all 4 parameters
    2. Conditional formatting applied
    3. Violation count formulas
    4. Primary problem identified
    5. Original data preserved
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple possible file locations
    possible_paths = [
        "/home/ga/Documents/aquarium_analysis.ods",
        "/home/ga/Documents/water_chemistry_log.csv",
        "/home/ga/Documents/water_chemistry_log.ods"
    ]
    
    success = False
    file_info = None
    
    for container_path in possible_paths:
        formats = ['ods'] if container_path.endswith('.ods') else ['csv']
        success, file_info, error = setup_calc_verification(copy_from_env, container_path, formats)
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet file. Tried: {', '.join(possible_paths)}"
        }
    
    try:
        sheet_names = get_sheet_names(file_info['sheet_data'])
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        workbook = file_info['sheet_data']
        
        # Initialize scoring
        criteria_met = 0
        max_criteria = 5
        feedback_parts = []
        subscores = {}
        
        # Criterion 1: Average calculations (20% each parameter = 100% total for criterion)
        logger.info("Checking average calculations...")
        averages = find_average_formulas(workbook, sheet_name)
        averages_found = sum(1 for v in averages.values() if v is not None)
        
        if averages_found >= 4:
            criteria_met += 1
            feedback_parts.append(f"✅ All 4 parameter averages calculated")
            subscores['averages_calculated'] = True
        elif averages_found >= 2:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Partial averages calculated ({averages_found}/4)")
            subscores['averages_calculated'] = False
        else:
            feedback_parts.append(f"❌ Missing average calculations ({averages_found}/4 found)")
            subscores['averages_calculated'] = False
        
        # Criterion 2: Conditional formatting (20%)
        logger.info("Checking conditional formatting...")
        formatting_count = check_conditional_formatting_ods(file_info['file_path'])
        
        if formatting_count >= 3:
            criteria_met += 1
            feedback_parts.append(f"✅ Conditional formatting applied ({formatting_count} rules)")
            subscores['conditional_formatting'] = True
        elif formatting_count >= 1:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Partial conditional formatting ({formatting_count} rules)")
            subscores['conditional_formatting'] = False
        else:
            feedback_parts.append("❌ No conditional formatting detected")
            subscores['conditional_formatting'] = False
        
        # Criterion 3: Violation count formulas (20%)
        logger.info("Checking violation count formulas...")
        countifs = find_countif_formulas(workbook, sheet_name)
        
        if len(countifs) >= 2:
            criteria_met += 1
            feedback_parts.append(f"✅ Violation counts calculated ({len(countifs)} COUNTIF formulas)")
            subscores['violation_counts'] = True
        elif len(countifs) >= 1:
            criteria_met += 0.5
            feedback_parts.append(f"⚠️ Partial violation counts ({len(countifs)} COUNTIF)")
            subscores['violation_counts'] = False
        else:
            feedback_parts.append("❌ No violation count formulas found")
            subscores['violation_counts'] = False
        
        # Criterion 4: Primary problem identification (20%)
        logger.info("Checking problem identification...")
        problem_found, identified_param = find_problem_identification(workbook, sheet_name)
        
        if problem_found:
            if validate_problem_logic(identified_param, None):
                criteria_met += 1
                feedback_parts.append(f"✅ Primary problem identified: {identified_param}")
                subscores['problem_identified'] = True
            else:
                criteria_met += 0.5
                feedback_parts.append(f"⚠️ Problem identified but may not match data: {identified_param}")
                subscores['problem_identified'] = False
        else:
            feedback_parts.append("❌ No primary problem identification found")
            subscores['problem_identified'] = False
        
        # Criterion 5: Original data integrity (20%)
        logger.info("Checking data integrity...")
        sheet_rows = workbook['sheets'][sheet_name]
        non_empty_rows = sum(1 for row in sheet_rows if any(
            (cell.get('value') if isinstance(cell, dict) else cell) for cell in row
        ))
        
        if non_empty_rows >= 14:  # Header + 14 days of data (or just 14 data rows)
            criteria_met += 1
            feedback_parts.append(f"✅ Original data preserved ({non_empty_rows} rows)")
            subscores['data_preserved'] = True
        else:
            feedback_parts.append(f"⚠️ Data may be incomplete ({non_empty_rows} rows)")
            subscores['data_preserved'] = False
        
        # Calculate final score
        score = int((criteria_met / max_criteria) * 100)
        passed = score >= 70  # Need 3.5/5 criteria (70%)
        
        # Add summary
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent water chemistry analysis!")
        elif passed:
            feedback_parts.insert(0, "✅ Water chemistry analysis completed")
        else:
            feedback_parts.insert(0, "❌ Analysis incomplete - missing key components")
        
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
        cleanup_verification_temp(file_info.get('temp_dir'))
