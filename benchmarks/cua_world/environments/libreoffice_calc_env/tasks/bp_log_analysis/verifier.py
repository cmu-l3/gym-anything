#!/usr/bin/env python3
"""
Verifier for Blood Pressure Log Analysis task.

Checks:
1. Overall averages calculated (systolic, diastolic, pulse)
2. Morning/evening time-based averages
3. Status column with correct categorization
4. Counts of readings by status
5. Formulas present (not hardcoded values)
6. No formula errors
"""

import sys
import os
import logging
from typing import Dict, Any, Tuple, Optional, List

# Use relative path to utils folder
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    verify_cell_value,
    cleanup_verification_temp,
    setup_calc_verification
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_time_to_hour(time_str: Any) -> Optional[int]:
    """Parse time string to hour integer."""
    if not time_str:
        return None
    
    time_str = str(time_str).strip()
    
    # Handle various time formats
    if ':' in time_str:
        try:
            hour = int(time_str.split(':')[0])
            return hour
        except:
            return None
    
    return None


def categorize_bp_reading(systolic: Any, diastolic: Any) -> str:
    """Categorize BP reading according to medical guidelines."""
    if systolic is None or diastolic is None:
        return ""
    
    try:
        sys_val = float(systolic)
        dia_val = float(diastolic)
    except (ValueError, TypeError):
        return ""
    
    # Medical categorization
    if sys_val > 180 or dia_val > 120:
        return "Crisis"
    elif sys_val >= 140 or dia_val >= 90:
        return "Stage 2"
    elif sys_val >= 130 or dia_val >= 80:
        return "Stage 1"
    elif sys_val >= 120 and dia_val < 80:
        return "Elevated"
    else:
        return "Normal"


def extract_bp_readings(workbook: Dict, sheet_name: str) -> List[Dict]:
    """Extract BP readings from sheet data."""
    readings = []
    sheet_rows = workbook['sheets'][sheet_name]
    
    # Skip header row (row 0)
    for row_idx in range(1, len(sheet_rows)):
        row = sheet_rows[row_idx]
        
        if len(row) < 5:
            continue
        
        # Extract values
        date_val = row[0].get('value') if isinstance(row[0], dict) else row[0]
        time_val = row[1].get('value') if isinstance(row[1], dict) else row[1]
        systolic = row[2].get('value') if isinstance(row[2], dict) else row[2]
        diastolic = row[3].get('value') if isinstance(row[3], dict) else row[3]
        pulse = row[4].get('value') if isinstance(row[4], dict) else row[4]
        
        # Only include rows with actual BP data
        if systolic is not None and diastolic is not None:
            hour = parse_time_to_hour(time_val)
            
            readings.append({
                'row': row_idx,
                'date': date_val,
                'time': time_val,
                'hour': hour,
                'systolic': systolic,
                'diastolic': diastolic,
                'pulse': pulse
            })
    
    return readings


def calculate_expected_averages(readings: List[Dict]) -> Dict[str, float]:
    """Calculate expected average values from readings."""
    if not readings:
        return {}
    
    # Overall averages
    systolic_values = [float(r['systolic']) for r in readings]
    diastolic_values = [float(r['diastolic']) for r in readings]
    pulse_values = [float(r['pulse']) for r in readings if r['pulse'] is not None]
    
    overall_sys = sum(systolic_values) / len(systolic_values)
    overall_dia = sum(diastolic_values) / len(diastolic_values)
    overall_pulse = sum(pulse_values) / len(pulse_values) if pulse_values else 0
    
    # Morning averages (before 12:00)
    morning_readings = [r for r in readings if r['hour'] is not None and r['hour'] < 12]
    morning_sys = sum(float(r['systolic']) for r in morning_readings) / len(morning_readings) if morning_readings else 0
    morning_dia = sum(float(r['diastolic']) for r in morning_readings) / len(morning_readings) if morning_readings else 0
    
    # Evening averages (after 18:00 / 6 PM)
    evening_readings = [r for r in readings if r['hour'] is not None and r['hour'] >= 18]
    evening_sys = sum(float(r['systolic']) for r in evening_readings) / len(evening_readings) if evening_readings else 0
    evening_dia = sum(float(r['diastolic']) for r in evening_readings) / len(evening_readings) if evening_readings else 0
    
    # Counts by status
    status_counts = {'Normal': 0, 'Elevated': 0, 'Stage 1': 0, 'Stage 2': 0, 'Crisis': 0}
    for r in readings:
        status = categorize_bp_reading(r['systolic'], r['diastolic'])
        if status in status_counts:
            status_counts[status] += 1
    
    return {
        'overall_systolic': overall_sys,
        'overall_diastolic': overall_dia,
        'overall_pulse': overall_pulse,
        'morning_systolic': morning_sys,
        'morning_diastolic': morning_dia,
        'evening_systolic': evening_sys,
        'evening_diastolic': evening_dia,
        'count_normal': status_counts['Normal'],
        'count_elevated': status_counts['Elevated'],
        'count_stage1': status_counts['Stage 1'],
        'count_stage2': status_counts['Stage 2'],
        'count_crisis': status_counts['Crisis']
    }


def verify_bp_log_analysis(traj, env_info, task_info):
    """
    Verify BP log analysis task completion.
    
    Checks:
    1. Overall averages calculated
    2. Morning/evening averages calculated
    3. Status column created with correct categorizations
    4. Counts by status calculated
    5. Formulas used (not hardcoded)
    6. No formula errors
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try multiple file paths
    temp_dir = None
    success = False
    workbook = None
    
    for container_path in [
        "/home/ga/Documents/bp_analysis_complete.ods",
        "/home/ga/Documents/bp_readings_3weeks.ods",
        "/home/ga/Documents/bp_readings_3weeks.csv"
    ]:
        file_format = 'ods' if container_path.endswith('.ods') else 'csv'
        success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
            container_path,
            copy_from_env,
            file_format=file_format
        )
        if success:
            logger.info(f"Successfully loaded file: {container_path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load BP analysis file: {error}"
        }
    
    try:
        # Get sheet name
        sheet_names = list(workbook['sheets'].keys())
        if not sheet_names:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}
        
        sheet_name = sheet_names[0]
        logger.info(f"Analyzing sheet: {sheet_name}")
        
        # Extract readings and calculate expected values
        readings = extract_bp_readings(workbook, sheet_name)
        logger.info(f"Found {len(readings)} valid BP readings")
        
        if len(readings) < 30:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Insufficient data: found {len(readings)} readings, expected 30+"
            }
        
        expected = calculate_expected_averages(readings)
        logger.info(f"Expected values: {expected}")
        
        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []
        subscores = {}
        
        # Tolerance for floating point comparisons (±2 mmHg)
        tolerance = 2.0
        
        # Criterion 1: Overall averages calculated (H2, H3, H4)
        overall_avg_correct = True
        
        h2_val = get_cell_value(workbook, sheet_name, 'H2')
        h2_formula = get_cell_formula(workbook, sheet_name, 'H2')
        
        if h2_val is not None:
            try:
                h2_float = float(h2_val)
                if abs(h2_float - expected['overall_systolic']) <= tolerance:
                    if h2_formula and ('AVERAGE' in h2_formula.upper() or 'SUM' in h2_formula.upper()):
                        feedback_parts.append(f"✅ Overall systolic average correct: {h2_float:.1f}")
                    else:
                        overall_avg_correct = False
                        feedback_parts.append(f"⚠️ H2 value correct but no formula detected")
                else:
                    overall_avg_correct = False
                    feedback_parts.append(f"❌ Overall systolic incorrect: got {h2_float:.1f}, expected {expected['overall_systolic']:.1f}")
            except (ValueError, TypeError):
                overall_avg_correct = False
                feedback_parts.append(f"❌ H2 invalid value: {h2_val}")
        else:
            overall_avg_correct = False
            feedback_parts.append("❌ H2 (overall systolic) missing")
        
        h3_val = get_cell_value(workbook, sheet_name, 'H3')
        if h3_val is not None:
            try:
                h3_float = float(h3_val)
                if abs(h3_float - expected['overall_diastolic']) > tolerance:
                    overall_avg_correct = False
            except:
                overall_avg_correct = False
        else:
            overall_avg_correct = False
        
        if overall_avg_correct:
            criteria_passed += 1
            subscores['overall_averages'] = True
        else:
            subscores['overall_averages'] = False
        
        # Criterion 2: Morning averages (H6, H7)
        morning_avg_correct = True
        
        h6_val = get_cell_value(workbook, sheet_name, 'H6')
        h6_formula = get_cell_formula(workbook, sheet_name, 'H6')
        
        if h6_val is not None and expected['morning_systolic'] > 0:
            try:
                h6_float = float(h6_val)
                if abs(h6_float - expected['morning_systolic']) <= tolerance:
                    if h6_formula and 'AVERAGEIF' in h6_formula.upper():
                        feedback_parts.append(f"✅ Morning systolic average correct: {h6_float:.1f}")
                    else:
                        # Still give credit if value is correct
                        feedback_parts.append(f"⚠️ H6 value correct but AVERAGEIF not detected")
                else:
                    morning_avg_correct = False
                    feedback_parts.append(f"❌ Morning systolic incorrect: got {h6_float:.1f}, expected {expected['morning_systolic']:.1f}")
            except:
                morning_avg_correct = False
        else:
            morning_avg_correct = False
            feedback_parts.append("❌ H6 (morning systolic) missing")
        
        h7_val = get_cell_value(workbook, sheet_name, 'H7')
        if h7_val is not None and expected['morning_diastolic'] > 0:
            try:
                h7_float = float(h7_val)
                if abs(h7_float - expected['morning_diastolic']) > tolerance:
                    morning_avg_correct = False
            except:
                morning_avg_correct = False
        else:
            morning_avg_correct = False
        
        if morning_avg_correct:
            criteria_passed += 1
            subscores['morning_averages'] = True
        else:
            subscores['morning_averages'] = False
        
        # Criterion 3: Evening averages (H9, H10)
        evening_avg_correct = True
        
        h9_val = get_cell_value(workbook, sheet_name, 'H9')
        if h9_val is not None and expected['evening_systolic'] > 0:
            try:
                h9_float = float(h9_val)
                if abs(h9_float - expected['evening_systolic']) <= tolerance:
                    feedback_parts.append(f"✅ Evening systolic average correct: {h9_float:.1f}")
                else:
                    evening_avg_correct = False
            except:
                evening_avg_correct = False
        else:
            evening_avg_correct = False
            feedback_parts.append("❌ H9 (evening systolic) missing")
        
        h10_val = get_cell_value(workbook, sheet_name, 'H10')
        if h10_val is not None and expected['evening_diastolic'] > 0:
            try:
                h10_float = float(h10_val)
                if abs(h10_float - expected['evening_diastolic']) > tolerance:
                    evening_avg_correct = False
            except:
                evening_avg_correct = False
        else:
            evening_avg_correct = False
        
        if evening_avg_correct:
            criteria_passed += 1
            subscores['evening_averages'] = True
        else:
            subscores['evening_averages'] = False
        
        # Criterion 4: Status column created (column G)
        status_correct = True
        status_errors = 0
        
        for reading in readings[:10]:  # Check first 10 readings
            row_num = reading['row'] + 1  # Convert to 1-based
            cell_ref = f"G{row_num}"
            status_val = get_cell_value(workbook, sheet_name, cell_ref)
            
            expected_status = categorize_bp_reading(reading['systolic'], reading['diastolic'])
            
            if status_val:
                status_str = str(status_val).strip()
                # Allow flexible matching
                if expected_status == "Normal" and "Normal" in status_str:
                    continue
                elif expected_status == "Elevated" and "Elevated" in status_str:
                    continue
                elif expected_status == "Stage 1" and ("Stage 1" in status_str or "Stage1" in status_str):
                    continue
                elif expected_status == "Stage 2" and ("Stage 2" in status_str or "Stage2" in status_str):
                    continue
                elif expected_status == "Crisis" and "Crisis" in status_str:
                    continue
                else:
                    status_errors += 1
            else:
                status_errors += 1
        
        if status_errors <= 2:  # Allow up to 2 errors in first 10
            criteria_passed += 1
            subscores['status_column'] = True
            feedback_parts.append(f"✅ Status column created with correct categorizations")
        else:
            subscores['status_column'] = False
            feedback_parts.append(f"❌ Status column has {status_errors} errors in first 10 rows")
        
        # Criterion 5: Counts by status (H12-H16)
        counts_correct = True
        count_tolerance = 2  # Allow small discrepancies
        
        h12_val = get_cell_value(workbook, sheet_name, 'H12')
        if h12_val is not None:
            try:
                if abs(int(h12_val) - expected['count_normal']) <= count_tolerance:
                    feedback_parts.append(f"✅ Normal count correct: {int(h12_val)}")
                else:
                    counts_correct = False
            except:
                counts_correct = False
        else:
            counts_correct = False
            feedback_parts.append("❌ H12 (count Normal) missing")
        
        # Check at least one more count
        h15_val = get_cell_value(workbook, sheet_name, 'H15')
        if h15_val is not None:
            try:
                if abs(int(h15_val) - expected['count_stage2']) > count_tolerance:
                    counts_correct = False
            except:
                counts_correct = False
        else:
            counts_correct = False
        
        if counts_correct:
            criteria_passed += 1
            subscores['status_counts'] = True
        else:
            subscores['status_counts'] = False
        
        # Criterion 6: Formulas used (not hardcoded)
        formulas_used = False
        formula_cells = ['H2', 'H3', 'H6', 'H7', 'H9', 'H10', 'H12']
        formulas_found = 0
        
        for cell in formula_cells:
            formula = get_cell_formula(workbook, sheet_name, cell)
            if formula:
                formulas_found += 1
        
        if formulas_found >= 5:  # At least 5 cells should have formulas
            criteria_passed += 1
            subscores['formulas_used'] = True
            feedback_parts.append(f"✅ Formulas used in calculations ({formulas_found} formulas found)")
        else:
            subscores['formulas_used'] = False
            feedback_parts.append(f"❌ Insufficient formulas ({formulas_found} found, expected 5+)")
        
        # Criterion 7: No formula errors
        sheet_rows = workbook['sheets'][sheet_name]
        error_count = 0
        
        for row in sheet_rows[:50]:  # Check first 50 rows
            for cell in row:
                cell_val = cell.get('value') if isinstance(cell, dict) else cell
                if cell_val and isinstance(cell_val, str):
                    if any(err in str(cell_val).upper() for err in ['#DIV/0', '#VALUE', '#REF', '#NAME', '#N/A']):
                        error_count += 1
        
        if error_count == 0:
            criteria_passed += 1
            subscores['no_errors'] = True
            feedback_parts.append("✅ No formula errors detected")
        else:
            subscores['no_errors'] = False
            feedback_parts.append(f"❌ Found {error_count} formula errors")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 70  # Pass threshold: 5 out of 7 criteria
        
        if passed and score >= 90:
            feedback_parts.insert(0, "🎉 Excellent BP analysis!")
        elif passed:
            feedback_parts.insert(0, "✅ BP analysis completed")
        else:
            feedback_parts.insert(0, f"❌ Insufficient analysis ({criteria_passed}/{total_criteria} criteria met)")
        
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
