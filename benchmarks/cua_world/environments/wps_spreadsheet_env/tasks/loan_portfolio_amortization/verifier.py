#!/usr/bin/env python3
"""Verifier for loan_portfolio_amortization task."""

import sys
import os
import json
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_loan_portfolio(traj, env_info, task_info):
    """
    Verify loan portfolio amortization model.

    SCORING (100 points total):
    1. Individual amortization schedules exist (min 4 of 6 loans) (20 pts)
    2. Financial formulas (PMT/IPMT/PPMT) used correctly (20 pts)
    3. Variable rate and special loan handling (15 pts)
    4. Portfolio_Summary sheet (15 pts)
    5. Covenant_Compliance with DSCR calculations (15 pts)
    6. Sensitivity_Analysis and conditional formatting (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_paths = ["/home/ga/Documents/loan_portfolio_model.xlsx"]
    try:
        rp = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'tmp_loan_result.json')
        copy_from_env('/tmp/loan_portfolio_result.json', rp)
        with open(rp) as f:
            rd = json.load(f)
        if rd.get('found_path'):
            container_paths.insert(0, rd['found_path'])
    except Exception:
        pass

    success = False
    wb = None
    temp_dir = None
    for cp in container_paths:
        success, wb, error, temp_dir = copy_and_parse_spreadsheet(cp, copy_from_env, file_format='xlsx')
        if success:
            break

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Could not open workbook: {error}"}

    try:
        score = 0
        feedback_parts = []
        starter_sheets = {"loan_terms", "rate_curve", "property_noi"}
        loan_ids = ['LOAN-001', 'LOAN-002', 'LOAN-003', 'LOAN-004', 'LOAN-005', 'LOAN-006']

        # ================================================================
        # Criterion 1: Amortization schedules exist (20 pts)
        # ================================================================
        amort_sheets = []
        for s in wb.sheetnames:
            if any(lid in s for lid in loan_ids) or 'amort' in s.lower():
                amort_sheets.append(s)

        amort_count = len(amort_sheets)
        # Also check for a single combined schedule sheet
        combined_schedule = False
        for s in wb.sheetnames:
            if s.lower() not in starter_sheets and ('schedule' in s.lower() or 'amort' in s.lower()):
                sheet = wb[s]
                # Check if it contains multiple loan references
                loan_refs = set()
                for row in sheet.iter_rows(max_row=20, max_col=5):
                    for cell in row:
                        if cell.value and isinstance(cell.value, str):
                            for lid in loan_ids:
                                if lid in cell.value:
                                    loan_refs.add(lid)
                if len(loan_refs) >= 3:
                    combined_schedule = True
                    amort_count = max(amort_count, len(loan_refs))

        points_1 = 0
        if amort_count >= 6:
            points_1 = 20
        elif amort_count >= 4:
            points_1 = 15
        elif amort_count >= 2:
            points_1 = 10
        elif amort_count >= 1 or combined_schedule:
            points_1 = 5

        score += points_1
        feedback_parts.append(f"Amortization sheets: {amort_count} found ({amort_sheets[:6]})")

        # ================================================================
        # Criterion 2: Financial formulas PMT/IPMT/PPMT (20 pts)
        # ================================================================
        has_pmt = False
        has_ipmt = False
        has_ppmt = False
        has_balance_calc = False
        financial_formula_count = 0

        for sn in wb.sheetnames:
            if sn.lower() in starter_sheets:
                continue
            sheet = wb[sn]
            for row in sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                        fu = cell.value.upper()
                        if 'PMT' in fu:
                            if 'IPMT' in fu:
                                has_ipmt = True
                                financial_formula_count += 1
                            elif 'PPMT' in fu:
                                has_ppmt = True
                                financial_formula_count += 1
                            else:
                                has_pmt = True
                                financial_formula_count += 1
                    # Check for balance calculations
                    if cell.value and isinstance(cell.value, str):
                        val_lower = cell.value.lower()
                        if 'balance' in val_lower or 'principal' in val_lower:
                            has_balance_calc = True

        points_2 = 0
        if has_pmt:
            points_2 += 8
        if has_ipmt:
            points_2 += 4
        if has_ppmt:
            points_2 += 4
        if financial_formula_count >= 10:
            points_2 += 4
        elif financial_formula_count >= 3:
            points_2 += 2

        # If no explicit PMT but has balance calculations with formulas
        if not has_pmt and has_balance_calc:
            formula_count = sum(1 for sn in amort_sheets for row in wb[sn].iter_rows() for cell in row
                              if cell.value and isinstance(cell.value, str) and cell.value.startswith('='))
            if formula_count >= 20:
                points_2 = max(points_2, 10)

        score += min(points_2, 20)
        feedback_parts.append(f"Financial formulas: PMT={has_pmt}, IPMT={has_ipmt}, PPMT={has_ppmt}, count={financial_formula_count}")

        # ================================================================
        # Criterion 3: Variable rate and special loan handling (15 pts)
        # ================================================================
        has_rate_curve_ref = False
        has_balloon_handling = False
        has_io_handling = False

        for sn in wb.sheetnames:
            if sn.lower() in starter_sheets:
                continue
            sheet = wb[sn]
            for row in sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        if cell.value.startswith('=') and 'Rate_Curve' in cell.value:
                            has_rate_curve_ref = True
                        val_lower = cell.value.lower()
                        if 'balloon' in val_lower:
                            has_balloon_handling = True
                        if 'interest only' in val_lower or 'interest-only' in val_lower or 'i/o' in val_lower:
                            has_io_handling = True

        # Check LOAN-004 sheet for rate curve references
        for sn in wb.sheetnames:
            if '004' in sn:
                sheet = wb[sn]
                for row in sheet.iter_rows():
                    for cell in row:
                        if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                            if 'Rate' in cell.value or 'SOFR' in cell.value or 'rate' in cell.value.lower():
                                has_rate_curve_ref = True

        points_3 = 0
        if has_rate_curve_ref:
            points_3 += 6
        if has_balloon_handling:
            points_3 += 5
        if has_io_handling:
            points_3 += 4

        score += min(points_3, 15)
        feedback_parts.append(f"Special: variable={has_rate_curve_ref}, balloon={has_balloon_handling}, IO={has_io_handling}")

        # ================================================================
        # Criterion 4: Portfolio_Summary (15 pts)
        # ================================================================
        summary_name = None
        for s in wb.sheetnames:
            sl = s.lower()
            if ('portfolio' in sl or 'summary' in sl) and sl not in starter_sheets:
                summary_name = s
                break

        if summary_name:
            summ = wb[summary_name]
            has_loan_refs = False
            has_balance = False
            has_weighted_avg = False
            formula_count = 0

            for row in summ.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        if any(lid in cell.value for lid in loan_ids):
                            has_loan_refs = True
                        val_lower = cell.value.lower()
                        if 'balance' in val_lower or 'outstanding' in val_lower:
                            has_balance = True
                        if 'weighted' in val_lower or 'wavg' in val_lower or 'w.avg' in val_lower:
                            has_weighted_avg = True
                        if cell.value.startswith('='):
                            formula_count += 1

            points_4 = 0
            if has_loan_refs:
                points_4 += 4
            if has_balance:
                points_4 += 4
            if has_weighted_avg:
                points_4 += 4
            if formula_count >= 5:
                points_4 += 3

            score += min(points_4, 15)
            feedback_parts.append(f"Portfolio: loans={has_loan_refs}, balance={has_balance}, wavg={has_weighted_avg}")
        else:
            feedback_parts.append("Portfolio Summary: NOT FOUND")

        # ================================================================
        # Criterion 5: Covenant_Compliance with DSCR (15 pts)
        # ================================================================
        covenant_name = None
        for s in wb.sheetnames:
            sl = s.lower()
            if any(kw in sl for kw in ['covenant', 'dscr', 'compliance']):
                covenant_name = s
                break

        if covenant_name:
            cov = wb[covenant_name]
            has_dscr = False
            has_noi_ref = False
            has_flag = False
            formula_count = 0

            for row in cov.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        val_lower = cell.value.lower()
                        if 'dscr' in val_lower or 'debt service coverage' in val_lower:
                            has_dscr = True
                        if 'noi' in val_lower or 'net operating' in val_lower:
                            has_noi_ref = True
                        if 'flag' in val_lower or 'breach' in val_lower or 'violation' in val_lower or 'fail' in val_lower:
                            has_flag = True
                        if cell.value.startswith('='):
                            formula_count += 1
                            if 'Property_NOI' in cell.value:
                                has_noi_ref = True

            points_5 = 0
            if has_dscr:
                points_5 += 5
            if has_noi_ref:
                points_5 += 4
            if has_flag:
                points_5 += 3
            if formula_count >= 5:
                points_5 += 3

            score += min(points_5, 15)
            feedback_parts.append(f"Covenant: DSCR={has_dscr}, NOI={has_noi_ref}, flag={has_flag}")
        else:
            feedback_parts.append("Covenant Compliance: NOT FOUND")

        # ================================================================
        # Criterion 6: Sensitivity + Conditional formatting (15 pts)
        # ================================================================
        sens_name = None
        for s in wb.sheetnames:
            sl = s.lower()
            if any(kw in sl for kw in ['sensitiv', 'scenario', 'what-if', 'stress']):
                sens_name = s
                break

        has_sensitivity = sens_name is not None
        has_cf = False
        for sn in wb.sheetnames:
            if sn.lower() not in starter_sheets:
                sheet = wb[sn]
                if sheet.conditional_formatting:
                    has_cf = True
                    break

        points_6 = 0
        if has_sensitivity:
            # Check for rate scenario references
            sens_sheet = wb[sens_name]
            has_scenarios = False
            for row in sens_sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        val_lower = cell.value.lower()
                        if any(kw in val_lower for kw in ['scenario', 'increase', 'decrease', 'base', 'bps', 'basis point', '+100', '-100']):
                            has_scenarios = True
            if has_scenarios:
                points_6 += 8
            else:
                points_6 += 4

        if has_cf:
            points_6 += 7

        score += min(points_6, 15)
        feedback_parts.append(f"Sensitivity={has_sensitivity}, Conditional formatting={has_cf}")

        passed = score >= 50
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)
