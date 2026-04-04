#!/usr/bin/env python3
"""
Verifier for Freelance Contract Comparison task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_freelance_contract_comparison(traj, env_info, task_info):
    """
    Verify the freelance contract comparison spreadsheet
    
    Checks:
    1. File exists and is parseable (15 points)
    2. Proper structure: at least 5 rows, 6 columns (20 points)
    3. Required column headers present (20 points)
    4. Data completeness: all four clients with complete data (15 points)
    5. Formula usage: Total Revenue uses formulas (20 points)
    6. Calculation accuracy: values match expectations (10 points)
    
    Pass threshold: 70/100 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    filepath = "/home/ga/Documents/Spreadsheets/contract_comparison.xlsx"
    score = 0
    max_score = 100
    feedback_parts = []
    
    # Expected calculations
    expected_totals = {
        'techstart': 85 * 15 * 12,  # $15,300
        'morrison': 95 * 10 * 8,     # $7,600
        'bluesky': 75 * 20 * 16,     # $24,000
        'localtech': 80 * 12 * 10    # $9,600
    }
    
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_contract_')
    
    try:
        # ===== CRITERION 1: File exists and parseable (15 points) =====
        success, workbook, error = copy_and_parse_document(filepath, copy_from_env, 'xlsx')
        
        if not success:
            feedback_parts.append(f"❌ File error: {error}")
            return {
                "passed": False,
                "score": 0.0,
                "feedback": " | ".join(feedback_parts)
            }
        
        score += 15
        feedback_parts.append("✅ File exists and is valid XLSX")
        
        # Get data from first sheet
        sheet_name = workbook.sheetnames[0]
        data = get_sheet_data(workbook, sheet_name, max_rows=25, max_cols=15)
        
        if not data or len(data) < 2:
            feedback_parts.append("❌ Spreadsheet appears empty or has insufficient data")
            return {
                "passed": False,
                "score": score / max_score,
                "feedback": " | ".join(feedback_parts)
            }
        
        # ===== CRITERION 2: Proper structure (20 points) =====
        # Count non-empty rows
        num_rows = len([row for row in data if any(cell for cell in row)])
        num_cols = max(len(row) for row in data) if data else 0
        
        if num_rows >= 5 and num_cols >= 6:
            score += 20
            feedback_parts.append(f"✅ Proper table structure: {num_rows} rows, {num_cols} columns")
        elif num_rows >= 4 and num_cols >= 5:
            score += 12
            feedback_parts.append(f"⚠️ Partial structure: {num_rows} rows, {num_cols} columns (expected ≥5 rows, ≥6 cols)")
        elif num_rows >= 3:
            score += 6
            feedback_parts.append(f"⚠️ Minimal structure: {num_rows} rows, {num_cols} columns")
        else:
            feedback_parts.append(f"❌ Insufficient rows: {num_rows} (need header + 4 data rows)")
        
        # Get header row (assume first row)
        headers = [str(cell).lower() if cell else "" for cell in data[0]]
        
        # ===== CRITERION 3: Required column headers (20 points) =====
        required_headers = {
            'client': ['client', 'company', 'name', 'vendor', 'offer'],
            'rate': ['rate', 'hourly', 'hour', '$/hr', 'pay', 'wage', 'price'],
            'hours': ['hours', 'hrs', 'weekly', 'per week', 'time', 'h/week'],
            'duration': ['duration', 'weeks', 'length', 'term', 'period', 'contract length'],
            'total': ['total', 'revenue', 'expected', 'earnings', 'income', 'payment', 'amount']
        }
        
        found_headers = {}
        for key, variations in required_headers.items():
            for idx, header in enumerate(headers):
                if any(var in header for var in variations):
                    found_headers[key] = idx
                    break
        
        headers_found = len(found_headers)
        if headers_found == 5:
            score += 20
            feedback_parts.append("✅ All required headers present")
        elif headers_found >= 4:
            score += 15
            feedback_parts.append(f"⚠️ Most headers present ({headers_found}/5)")
        elif headers_found >= 3:
            score += 8
            feedback_parts.append(f"⚠️ Some headers missing ({headers_found}/5)")
        else:
            feedback_parts.append(f"❌ Missing critical headers ({headers_found}/5)")
        
        # ===== CRITERION 4: Data completeness (15 points) =====
        client_names_found = []
        complete_rows = 0
        data_rows = []
        
        for row_idx in range(1, min(len(data), 15)):  # Check up to 15 rows
            row = data[row_idx]
            if not any(cell for cell in row):
                continue
                
            # Check if row has data in key columns
            has_client = False
            has_rate = False
            has_hours = False
            has_duration = False
            
            row_info = {}
            
            if 'client' in found_headers and found_headers['client'] < len(row):
                client_val = row[found_headers['client']]
                if client_val:
                    has_client = True
                    client_names_found.append(str(client_val).lower())
                    row_info['client'] = str(client_val).lower()
            
            if 'rate' in found_headers and found_headers['rate'] < len(row):
                rate_val = row[found_headers['rate']]
                if rate_val is not None and rate_val != "":
                    has_rate = True
                    try:
                        # Handle currency symbols and convert to float
                        rate_str = str(rate_val).replace('$', '').replace(',', '').strip()
                        row_info['rate'] = float(rate_str)
                    except:
                        pass
            
            if 'hours' in found_headers and found_headers['hours'] < len(row):
                hours_val = row[found_headers['hours']]
                if hours_val is not None and hours_val != "":
                    has_hours = True
                    try:
                        row_info['hours'] = float(str(hours_val).replace(',', '').strip())
                    except:
                        pass
            
            if 'duration' in found_headers and found_headers['duration'] < len(row):
                duration_val = row[found_headers['duration']]
                if duration_val is not None and duration_val != "":
                    has_duration = True
                    try:
                        row_info['duration'] = float(str(duration_val).replace(',', '').strip())
                    except:
                        pass
            
            if has_client and has_rate and has_hours and has_duration:
                complete_rows += 1
                data_rows.append(row_info)
        
        # Check if all four clients are mentioned
        expected_clients = ['techstart', 'morrison', 'bluesky', 'localtech']
        clients_present = []
        for expected in expected_clients:
            found = False
            for name in client_names_found:
                if expected in name or expected.replace('tech', '') in name:
                    found = True
                    clients_present.append(expected)
                    break
            # Additional checks for variations
            if not found:
                if expected == 'techstart' and any('tech' in n and 'start' in n for n in client_names_found):
                    clients_present.append(expected)
                elif expected == 'morrison' and any('morris' in n for n in client_names_found):
                    clients_present.append(expected)
                elif expected == 'bluesky' and any('blue' in n or 'sky' in n for n in client_names_found):
                    clients_present.append(expected)
                elif expected == 'localtech' and any('local' in n for n in client_names_found):
                    clients_present.append(expected)
        
        clients_count = len(clients_present)
        
        if complete_rows >= 4 and clients_count >= 4:
            score += 15
            feedback_parts.append("✅ All four contracts included with complete data")
        elif complete_rows >= 3 and clients_count >= 3:
            score += 10
            feedback_parts.append(f"⚠️ Most contracts present: {clients_count}/4 clients, {complete_rows} complete rows")
        elif complete_rows >= 2 or clients_count >= 2:
            score += 5
            feedback_parts.append(f"⚠️ Partial data: {clients_count}/4 clients, {complete_rows} complete rows")
        else:
            feedback_parts.append(f"❌ Incomplete data: only {clients_count}/4 clients found")
        
        # ===== CRITERION 5: Formula usage (20 points) =====
        formulas_found = 0
        formulas_with_multiplication = 0
        
        # Need to reload workbook to check for formulas (not data_only mode)
        try:
            from openpyxl import load_workbook as openpyxl_load
            temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx', dir=temp_dir)
            copy_from_env(filepath, temp_file.name)
            
            workbook_formulas = openpyxl_load(temp_file.name, data_only=False)
            sheet_formulas = workbook_formulas[sheet_name]
            
            if 'total' in found_headers:
                total_col_idx = found_headers['total']
                # Convert column index to letter (0->A, 1->B, etc.)
                total_col_letter = chr(65 + total_col_idx) if total_col_idx < 26 else 'A'
                
                for row_num in range(2, min(len(data) + 1, 15)):  # Check rows 2-14
                    cell_ref = f"{total_col_letter}{row_num}"
                    try:
                        cell = sheet_formulas[cell_ref]
                        if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                            formulas_found += 1
                            # Check if formula contains multiplication
                            if '*' in cell.value:
                                formulas_with_multiplication += 1
                    except:
                        pass
            
            os.unlink(temp_file.name)
            
        except Exception as e:
            logger.warning(f"Could not check formulas: {e}")
        
        if formulas_with_multiplication >= 3:
            score += 20
            feedback_parts.append(f"✅ Formulas correctly used in Total Revenue column ({formulas_with_multiplication}/4 with multiplication)")
        elif formulas_with_multiplication >= 2:
            score += 13
            feedback_parts.append(f"⚠️ Some formulas present ({formulas_with_multiplication}/4 with multiplication)")
        elif formulas_found >= 2:
            score += 7
            feedback_parts.append(f"⚠️ Formulas found but may not use multiplication ({formulas_found}/4)")
        elif formulas_found >= 1:
            score += 4
            feedback_parts.append(f"⚠️ Few formulas found ({formulas_found}/4)")
        else:
            feedback_parts.append("❌ No formulas detected in Total column")
        
        # ===== CRITERION 6: Calculation accuracy (10 points) =====
        accurate_calcs = 0
        calc_feedback = []
        
        if 'total' in found_headers:
            for row in data_rows:
                if 'client' not in row:
                    continue
                
                client = row['client']
                
                # Try to find matching expected total
                for key, expected in expected_totals.items():
                    if key in client or key.replace('tech', '') in client:
                        # Try to get the total value from the row
                        row_idx = client_names_found.index(client) + 1  # +1 for header
                        if row_idx < len(data):
                            total_val = data[row_idx][found_headers['total']] if found_headers['total'] < len(data[row_idx]) else None
                            
                            if total_val:
                                try:
                                    total_num = float(str(total_val).replace('$', '').replace(',', '').strip())
                                    tolerance = expected * 0.05  # 5% tolerance
                                    if abs(total_num - expected) <= tolerance:
                                        accurate_calcs += 1
                                        calc_feedback.append(f"{key.title()}=${int(total_num):,}")
                                except:
                                    pass
                        break
        
        if accurate_calcs >= 3:
            score += 10
            feedback_parts.append(f"✅ Calculated totals accurate: {', '.join(calc_feedback)}")
        elif accurate_calcs >= 2:
            score += 6
            feedback_parts.append(f"⚠️ Some calculations correct: {', '.join(calc_feedback)}")
        elif accurate_calcs >= 1:
            score += 3
            feedback_parts.append(f"⚠️ One calculation correct: {', '.join(calc_feedback)}")
        else:
            feedback_parts.append("⚠️ Could not verify calculation accuracy")
        
        # ===== Determine pass/fail =====
        passed = score >= 70
        normalized_score = score / max_score
        
        if passed:
            feedback_parts.append(f"\n✅ PASSED ({score}/{max_score}): Excellent comparison spreadsheet! You can now make an informed decision about which contracts to accept. BlueSky offers the highest total revenue at $24,000.")
        else:
            feedback_parts.append(f"\n❌ FAILED ({score}/{max_score}): The spreadsheet needs all four offers with proper structure and formulas to calculate expected revenue. Remember: Total Revenue = Hourly Rate × Hours per Week × Duration in Weeks")
        
        return {
            "passed": passed,
            "score": normalized_score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        feedback_parts.append(f"Verification error: {str(e)}")
        return {
            "passed": False,
            "score": score / max_score,
            "feedback": " | ".join(feedback_parts)
        }
    finally:
        cleanup_temp_dir(temp_dir)


# Entry point for gym-anything
def verify_task(traj, env_info, task_info):
    return verify_freelance_contract_comparison(traj, env_info, task_info)
