#!/usr/bin/env python3
"""
Verifier for Tip Pool Distribution task.

Validates:
1. Policy split (20/80) applied correctly
2. Total reconciliation ($2,850)
3. Formula presence (not hard-coded)
4. Hours calculated correctly
5. Proportional distribution accuracy
6. No calculation errors
"""

import sys
import os
import logging
import re
from typing import Dict, List, Tuple, Optional, Any

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Expected values
TOTAL_TIPS = 2850.00
SUPPORT_POOL_PERCENT = 0.20
SERVICE_POOL_PERCENT = 0.80
EXPECTED_SUPPORT_POOL = TOTAL_TIPS * SUPPORT_POOL_PERCENT  # $570
EXPECTED_SERVICE_POOL = TOTAL_TIPS * SERVICE_POOL_PERCENT  # $2,280

TOLERANCE = 1.0  # $1 tolerance for rounding
PER_PERSON_TOLERANCE = 2.0  # $2 tolerance per person


def parse_hours(hours_str: str) -> Tuple[float, float]:
    """
    Parse hours string. Handle formats like:
    - "32" -> (32, 0) for service
    - "28" -> (28, 0) for support
    - "12 + 8" -> (12, 8) for multi-role
    
    Returns: (service_hours, support_hours)
    """
    if not hours_str:
        return (0.0, 0.0)
    
    hours_str = str(hours_str).strip()
    
    # Check for multi-role format (e.g., "12 + 8")
    if '+' in hours_str:
        parts = hours_str.split('+')
        try:
            h1 = float(parts[0].strip())
            h2 = float(parts[1].strip())
            return (h1, h2)
        except:
            return (0.0, 0.0)
    
    # Single role
    try:
        return (float(hours_str), 0.0)
    except:
        return (0.0, 0.0)


def extract_staff_data(workbook: Dict, sheet_name: str) -> Dict[str, Any]:
    """
    Extract staff data from spreadsheet.
    
    Returns dict with:
    - staff_list: List of staff records
    - support_hours_total: Total support staff hours
    - service_hours_total: Total service staff hours
    - tip_amounts: List of individual tip amounts
    - formulas_found: Count of formulas in calculation cells
    """
    staff_list = []
    support_hours = 0.0
    service_hours = 0.0
    tip_amounts = []
    formula_count = 0
    
    # Staff data is in rows 10-16 (indices 9-15)
    # Format: Name (col A), Role (col B), Hours (col C), Tip Amount (col D)
    
    staff_roles = {
        'Sarah Chen': 'service',
        'David Martinez': 'service',
        'Emma Rodriguez': 'service',
        'Marcus Johnson': 'support',
        'Keisha Williams': 'support',
        'James Lee': 'support',
        'Maria Garcia': 'multi'  # Special case
    }
    
    for row_idx in range(9, 16):  # Rows 10-16 in spreadsheet (0-indexed: 9-15)
        try:
            name = get_cell_value(workbook, sheet_name, f'A{row_idx + 1}')
            role = get_cell_value(workbook, sheet_name, f'B{row_idx + 1}')
            hours_str = get_cell_value(workbook, sheet_name, f'C{row_idx + 1}')
            tip_amount = get_cell_value(workbook, sheet_name, f'D{row_idx + 1}')
            tip_formula = get_cell_formula(workbook, sheet_name, f'D{row_idx + 1}')
            
            if name:
                staff_name = str(name).strip()
                
                # Count formulas
                if tip_formula:
                    formula_count += 1
                
                # Determine staff type
                if staff_name == 'Maria Garcia':
                    # Multi-role: parse "12 + 8" format
                    serv_h, supp_h = parse_hours(hours_str)
                    service_hours += serv_h
                    support_hours += supp_h
                    staff_list.append({
                        'name': staff_name,
                        'type': 'multi',
                        'service_hours': serv_h,
                        'support_hours': supp_h,
                        'tip_amount': tip_amount,
                        'has_formula': tip_formula is not None
                    })
                elif role and ('Server' in str(role) or 'Bartender' in str(role)):
                    # Service staff
                    hours, _ = parse_hours(hours_str)
                    service_hours += hours
                    staff_list.append({
                        'name': staff_name,
                        'type': 'service',
                        'service_hours': hours,
                        'support_hours': 0,
                        'tip_amount': tip_amount,
                        'has_formula': tip_formula is not None
                    })
                elif role and ('Busser' in str(role) or 'Food Runner' in str(role)):
                    # Support staff
                    hours, _ = parse_hours(hours_str)
                    support_hours += hours
                    staff_list.append({
                        'name': staff_name,
                        'type': 'support',
                        'service_hours': 0,
                        'support_hours': hours,
                        'tip_amount': tip_amount,
                        'has_formula': tip_formula is not None
                    })
                
                # Collect tip amounts
                if tip_amount is not None:
                    try:
                        # Handle currency strings like "$760.00"
                        tip_val = float(str(tip_amount).replace('$', '').replace(',', '').strip())
                        tip_amounts.append(tip_val)
                    except:
                        pass
        
        except Exception as e:
            logger.debug(f"Error parsing row {row_idx + 1}: {e}")
            continue
    
    return {
        'staff_list': staff_list,
        'support_hours_total': support_hours,
        'service_hours_total': service_hours,
        'tip_amounts': tip_amounts,
        'formula_count': formula_count
    }


def check_proportional_distribution(staff_data: Dict, support_rate: float, service_rate: float) -> Tuple[bool, List[str]]:
    """
    Check if individual tip amounts match expected proportional distribution.
    
    Returns: (all_correct, error_messages)
    """
    errors = []
    all_correct = True
    
    for staff in staff_data['staff_list']:
        name = staff['name']
        actual_tip = staff.get('tip_amount')
        
        if actual_tip is None:
            errors.append(f"{name}: No tip amount calculated")
            all_correct = False
            continue
        
        try:
            actual_tip = float(str(actual_tip).replace('$', '').replace(',', '').strip())
        except:
            errors.append(f"{name}: Invalid tip amount format")
            all_correct = False
            continue
        
        # Calculate expected tip
        if staff['type'] == 'multi':
            expected_tip = (staff['service_hours'] * service_rate) + (staff['support_hours'] * support_rate)
        elif staff['type'] == 'service':
            expected_tip = staff['service_hours'] * service_rate
        elif staff['type'] == 'support':
            expected_tip = staff['support_hours'] * support_rate
        else:
            continue
        
        # Check with tolerance
        if abs(actual_tip - expected_tip) > PER_PERSON_TOLERANCE:
            errors.append(f"{name}: Expected ${expected_tip:.2f}, got ${actual_tip:.2f}")
            all_correct = False
    
    return all_correct, errors


def verify_tip_distribution(traj, env_info, task_info):
    """
    Main verification function for tip pool distribution task.
    
    Checks:
    1. Policy split correct (20/80)
    2. Total reconciliation ($2,850)
    3. Formulas present (not hard-coded)
    4. Hours calculated correctly
    5. Proportional distribution accurate
    6. No calculation errors
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/tip_distribution.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        # Get sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        
        criteria_passed = 0
        total_criteria = 6
        feedback_parts = []
        subscores = {}
        
        # Extract staff data
        staff_data = extract_staff_data(workbook, sheet_name)
        
        logger.info(f"Extracted staff data: {len(staff_data['staff_list'])} staff members")
        logger.info(f"Support hours: {staff_data['support_hours_total']}")
        logger.info(f"Service hours: {staff_data['service_hours_total']}")
        logger.info(f"Tip amounts: {staff_data['tip_amounts']}")
        logger.info(f"Formulas found: {staff_data['formula_count']}")
        
        # CRITERION 1: Policy Split - Support Pool
        # Check if $570 appears anywhere (row 20, column D typically)
        support_pool_value = get_cell_value(workbook, sheet_name, 'D20')
        if support_pool_value:
            try:
                support_pool = float(str(support_pool_value).replace('$', '').replace(',', '').strip())
                if abs(support_pool - EXPECTED_SUPPORT_POOL) <= TOLERANCE:
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Support pool correct: ${support_pool:.2f}")
                    subscores['support_pool'] = True
                else:
                    feedback_parts.append(f"❌ Support pool incorrect: ${support_pool:.2f} (expected $570)")
                    subscores['support_pool'] = False
            except:
                feedback_parts.append("❌ Support pool value invalid")
                subscores['support_pool'] = False
        else:
            feedback_parts.append("❌ Support pool not calculated (cell D20)")
            subscores['support_pool'] = False
        
        # CRITERION 2: Policy Split - Service Pool
        service_pool_value = get_cell_value(workbook, sheet_name, 'D21')
        if service_pool_value:
            try:
                service_pool = float(str(service_pool_value).replace('$', '').replace(',', '').strip())
                if abs(service_pool - EXPECTED_SERVICE_POOL) <= TOLERANCE:
                    criteria_passed += 1
                    feedback_parts.append(f"✅ Service pool correct: ${service_pool:.2f}")
                    subscores['service_pool'] = True
                else:
                    feedback_parts.append(f"❌ Service pool incorrect: ${service_pool:.2f} (expected $2,280)")
                    subscores['service_pool'] = False
            except:
                feedback_parts.append("❌ Service pool value invalid")
                subscores['service_pool'] = False
        else:
            feedback_parts.append("❌ Service pool not calculated (cell D21)")
            subscores['service_pool'] = False
        
        # CRITERION 3: Total Reconciliation
        if staff_data['tip_amounts']:
            total_distributed = sum(staff_data['tip_amounts'])
            if abs(total_distributed - TOTAL_TIPS) <= TOLERANCE:
                criteria_passed += 1
                feedback_parts.append(f"✅ Total reconciles: ${total_distributed:.2f}")
                subscores['total_reconciliation'] = True
            else:
                feedback_parts.append(f"❌ Total doesn't match: ${total_distributed:.2f} ≠ $2,850")
                subscores['total_reconciliation'] = False
        else:
            feedback_parts.append("❌ No individual tip amounts found")
            subscores['total_reconciliation'] = False
        
        # CRITERION 4: Formulas Present
        if staff_data['formula_count'] >= 5:  # At least 70% of 7 staff
            criteria_passed += 1
            feedback_parts.append(f"✅ Formulas present ({staff_data['formula_count']}/7 cells)")
            subscores['formulas_present'] = True
        else:
            feedback_parts.append(f"❌ Insufficient formulas: {staff_data['formula_count']}/7 cells")
            subscores['formulas_present'] = False
        
        # CRITERION 5: Hours Calculated Correctly
        # Expected: Support = 69 hours (28+18+15+8), Service = 96 hours (32+28+24+12)
        expected_support = 69.0
        expected_service = 96.0
        
        hours_correct = True
        if abs(staff_data['support_hours_total'] - expected_support) > 1.0:
            feedback_parts.append(f"⚠️ Support hours may be incorrect: {staff_data['support_hours_total']:.1f} (expected ~69)")
            hours_correct = False
        
        if abs(staff_data['service_hours_total'] - expected_service) > 1.0:
            feedback_parts.append(f"⚠️ Service hours may be incorrect: {staff_data['service_hours_total']:.1f} (expected ~96)")
            hours_correct = False
        
        if hours_correct:
            criteria_passed += 1
            feedback_parts.append("✅ Hours calculated correctly")
            subscores['hours_calculated'] = True
        else:
            subscores['hours_calculated'] = False
        
        # CRITERION 6: Proportional Distribution
        # Calculate expected rates
        if staff_data['support_hours_total'] > 0 and staff_data['service_hours_total'] > 0:
            support_rate = EXPECTED_SUPPORT_POOL / staff_data['support_hours_total']
            service_rate = EXPECTED_SERVICE_POOL / staff_data['service_hours_total']
            
            distribution_correct, errors = check_proportional_distribution(
                staff_data, support_rate, service_rate
            )
            
            if distribution_correct:
                criteria_passed += 1
                feedback_parts.append("✅ Proportional distribution accurate")
                subscores['proportional_distribution'] = True
            else:
                feedback_parts.append(f"❌ Distribution errors: {'; '.join(errors[:2])}")
                subscores['proportional_distribution'] = False
        else:
            feedback_parts.append("❌ Cannot verify distribution (hours missing)")
            subscores['proportional_distribution'] = False
        
        # Check for formula errors
        error_cells = []
        for row_idx in range(9, 23):
            for col in ['D']:
                cell_val = get_cell_value(workbook, sheet_name, f'{col}{row_idx + 1}')
                if cell_val and isinstance(cell_val, str):
                    if '#DIV/0!' in cell_val or '#REF!' in cell_val or '#VALUE!' in cell_val or '#NAME?' in cell_val:
                        error_cells.append(f'{col}{row_idx + 1}')
        
        if error_cells:
            feedback_parts.append(f"⚠️ Formula errors in: {', '.join(error_cells)}")
        
        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 85  # Pass threshold: 85%
        
        if passed and score >= 95:
            feedback_parts.insert(0, "🎉 Excellent tip pool calculation!")
        elif passed:
            feedback_parts.insert(0, "✅ Tip pool distribution complete")
        else:
            feedback_parts.insert(0, "❌ Tip pool calculation incomplete or incorrect")
        
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
            "feedback": f"Verification error: {str(e)}",
            "subscores": {}
        }

    finally:
        cleanup_verification_temp(temp_dir)
