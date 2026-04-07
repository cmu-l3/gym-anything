#!/usr/bin/env python3
"""Verifier for hotel_cancellation_analysis task."""

import sys
import os
import json
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_is_formula(value):
    """Check if a cell value is a spreadsheet formula."""
    return isinstance(value, str) and value.startswith('=')

def verify_hotel_analysis(traj, env_info, task_info):
    """
    Verify the hotel cancellation analysis operations were applied correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata results from export_result.sh
    temp_result = "/tmp/task_result.json"
    host_temp_result = "/tmp/wps_result_eval.json"
    
    file_modified = False
    try:
        copy_from_env(temp_result, host_temp_result)
        with open(host_temp_result, 'r') as f:
            res_json = json.load(f)
            file_modified = res_json.get('file_modified_during_task', False)
        os.unlink(host_temp_result)
    except Exception as e:
        logger.warning(f"Could not read task result metadata: {e}")

    # Parse the spreadsheet
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/resort_hotel_bookings.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to open file: {error}"}

    try:
        score = 0
        feedback_parts = []
        
        # Anti-gaming: Ensure the file was actually saved
        if not file_modified:
            feedback_parts.append("Warning: File was not modified/saved during task window")

        # Define sheet names (handle minor case variations)
        sheet_names = wb.sheetnames
        bookings_name = next((s for s in sheet_names if s.lower() == 'bookings'), None)
        segment_name = next((s for s in sheet_names if s.lower() in ['segment_analysis', 'segment analysis']), None)

        # ==========================================
        # 1. Row-level Arithmetic (15 pts)
        # ==========================================
        arithmetic_passed = False
        if bookings_name:
            ws_book = wb[bookings_name]
            
            # Check headers
            j1 = str(ws_book['J1'].value).lower() if ws_book['J1'].value else ""
            k1 = str(ws_book['K1'].value).lower() if ws_book['K1'].value else ""
            
            # Check formulas in row 2
            j2_val = ws_book['J2'].value
            k2_val = ws_book['K2'].value
            
            has_headers = 'nights' in j1 and 'revenue' in k1
            is_j2_form = check_is_formula(j2_val)
            is_k2_form = check_is_formula(k2_val)
            
            if has_headers and is_j2_form and is_k2_form:
                score += 15
                arithmetic_passed = True
                feedback_parts.append("Row arithmetic: Correct (+15)")
            else:
                feedback_parts.append(f"Row arithmetic: Missing or invalid formulas in Bookings J2/K2")
        else:
            feedback_parts.append("Bookings sheet not found")

        # ==========================================
        # 2. Nested IF Logic (20 pts)
        # ==========================================
        if bookings_name:
            ws_book = wb[bookings_name]
            l1 = str(ws_book['L1'].value).lower() if ws_book['L1'].value else ""
            l2_val = ws_book['L2'].value
            
            is_l2_form = check_is_formula(l2_val)
            has_if = is_l2_form and 'IF' in l2_val.upper()
            has_thresholds = is_l2_form and ('30' in l2_val) and ('90' in l2_val)
            
            if has_if and has_thresholds:
                score += 20
                feedback_parts.append("Nested logic (Lead Time): Correct (+20)")
            elif is_l2_form:
                score += 10
                feedback_parts.append("Nested logic: Partial (Formula present but lacks thresholds) (+10)")
            else:
                feedback_parts.append("Nested logic: Missing or hardcoded")

        # ==========================================
        # 3. Sheet & Structure (10 pts)
        # ==========================================
        segments_found = []
        target_segments = ['Online TA', 'Offline TA/TO', 'Direct', 'Corporate', 'Groups']
        
        if segment_name:
            ws_seg = wb[segment_name]
            
            # Look for segments in column A (A2:A10 to be safe)
            for row in range(2, 11):
                val = ws_seg[f'A{row}'].value
                if val and str(val).strip() in target_segments:
                    segments_found.append(str(val).strip())
            
            if len(set(segments_found)) >= 4:  # Allowing 1 typo
                score += 10
                feedback_parts.append(f"Segment Structure: Correct ({len(set(segments_found))}/5 segments) (+10)")
            else:
                feedback_parts.append(f"Segment Structure: Missing target segments (found {len(segments_found)})")
        else:
            feedback_parts.append("Segment_Analysis sheet not found")

        # ==========================================
        # 4. Count Aggregations (20 pts)
        # ==========================================
        count_passed = False
        if segment_name:
            ws_seg = wb[segment_name]
            b2_val = ws_seg['B2'].value
            c2_val = ws_seg['C2'].value
            
            is_b2_count = check_is_formula(b2_val) and 'COUNTIF' in b2_val.upper()
            is_c2_count = check_is_formula(c2_val) and 'COUNTIF' in c2_val.upper()
            
            if is_b2_count and is_c2_count:
                score += 20
                count_passed = True
                feedback_parts.append("Count aggregations: Correct (+20)")
            elif is_b2_count or is_c2_count:
                score += 10
                feedback_parts.append("Count aggregations: Partial (+10)")
            else:
                feedback_parts.append("Count aggregations: Missing or hardcoded")

        # ==========================================
        # 5. Sum Aggregation (25 pts)
        # ==========================================
        if segment_name:
            ws_seg = wb[segment_name]
            e2_val = ws_seg['E2'].value
            
            is_e2_sum = check_is_formula(e2_val) and 'SUMIF' in e2_val.upper()
            
            if is_e2_sum:
                score += 25
                feedback_parts.append("Sum aggregation (Lost Revenue): Correct (+25)")
            else:
                feedback_parts.append("Sum aggregation: Missing or hardcoded")

        # ==========================================
        # 6. Formatting (10 pts)
        # ==========================================
        if segment_name:
            ws_seg = wb[segment_name]
            d2_fmt = ws_seg['D2'].number_format if ws_seg['D2'] else ""
            e2_fmt = ws_seg['E2'].number_format if ws_seg['E2'] else ""
            
            has_pct = '%' in str(d2_fmt)
            has_currency = '$' in str(e2_fmt) or '0.00' in str(e2_fmt) or 'Accounting' in str(e2_fmt)
            
            if has_pct and has_currency:
                score += 10
                feedback_parts.append("Formatting: Correct (+10)")
            elif has_pct or has_currency:
                score += 5
                feedback_parts.append("Formatting: Partial (+5)")
            else:
                feedback_parts.append("Formatting: Missing")

        # Final Evaluation
        passed = score >= 75 and arithmetic_passed and count_passed

        if not file_modified and score > 0:
            passed = False
            feedback_parts.append("FAIL: Spreadsheet was not saved (Ctrl+S).")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)