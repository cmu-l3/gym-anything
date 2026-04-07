#!/usr/bin/env python3
"""Verifier for compensation_equity_analysis task."""

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


def verify_compensation_equity(traj, env_info, task_info):
    """
    Verify compensation equity analysis workbook.

    SCORING (100 points total):
    1. Compa_Ratio sheet with lookup formulas (25 pts)
    2. Equity_Summary with statistical breakdowns (20 pts)
    3. Flagged_Employees sheet with adjustment calc (15 pts)
    4. Conditional formatting on compa ratios (15 pts)
    5. Scatter chart tenure vs compa-ratio (15 pts)
    6. Cross-sheet formula references (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_paths = ["/home/ga/Documents/compensation_equity_review.xlsx"]
    try:
        rp = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'tmp_comp_result.json')
        copy_from_env('/tmp/compensation_equity_result.json', rp)
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
        starter_sheets = {"employees", "market_benchmarks"}

        # ================================================================
        # Criterion 1: Compa_Ratio sheet with lookup formulas (25 pts)
        # ================================================================
        compa_name = None
        for s in wb.sheetnames:
            if 'compa' in s.lower() or 'ratio' in s.lower():
                compa_name = s
                break

        if compa_name:
            compa_sheet = wb[compa_name]
            has_lookup_formulas = False
            has_compa_values = False
            data_rows = 0
            formula_types = set()

            for row in compa_sheet.iter_rows():
                has_data = any(cell.value is not None for cell in row)
                if has_data:
                    data_rows += 1
                for cell in row:
                    if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                        formula_upper = cell.value.upper()
                        if 'VLOOKUP' in formula_upper:
                            has_lookup_formulas = True
                            formula_types.add('VLOOKUP')
                        if 'INDEX' in formula_upper and 'MATCH' in formula_upper:
                            has_lookup_formulas = True
                            formula_types.add('INDEX-MATCH')
                        if 'XLOOKUP' in formula_upper:
                            has_lookup_formulas = True
                            formula_types.add('XLOOKUP')
                    # Check for compa-ratio values (typically 0.7 - 1.3)
                    if cell.value and isinstance(cell.value, (int, float)):
                        if 0.5 < cell.value < 1.5:
                            has_compa_values = True

            points_1 = 0
            if data_rows >= 30:
                points_1 += 8
            elif data_rows >= 15:
                points_1 += 5
            elif data_rows >= 1:
                points_1 += 2

            if has_lookup_formulas:
                points_1 += 12
                feedback_parts.append(f"Lookup formulas: {formula_types}")
            elif has_compa_values:
                points_1 += 5
                feedback_parts.append("Compa values present (no lookup formulas detected)")
            else:
                feedback_parts.append("No lookup formulas found")

            # Check for employee references
            has_emp_refs = False
            for row in compa_sheet.iter_rows(max_row=5):
                for cell in row:
                    if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                        if 'Employees' in cell.value or 'Market' in cell.value:
                            has_emp_refs = True
            if has_emp_refs:
                points_1 += 5

            score += min(points_1, 25)
            feedback_parts.append(f"Compa sheet: {data_rows} rows, lookups={has_lookup_formulas}")
        else:
            feedback_parts.append("Compa_Ratio sheet: NOT FOUND")

        # ================================================================
        # Criterion 2: Equity_Summary with statistics (20 pts)
        # ================================================================
        equity_name = None
        for s in wb.sheetnames:
            if any(kw in s.lower() for kw in ['equity', 'summary', 'stat', 'analysis']):
                if s.lower() not in starter_sheets:
                    equity_name = s
                    break

        if equity_name:
            eq_sheet = wb[equity_name]
            has_gender_breakdown = False
            has_ethnicity_breakdown = False
            has_stat_formulas = False
            stat_formula_types = set()

            for row in eq_sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        val_lower = cell.value.lower()
                        if any(g in val_lower for g in ['male', 'female', 'gender', 'm', 'f']):
                            has_gender_breakdown = True
                        if any(e in val_lower for e in ['asian', 'white', 'black', 'hispanic', 'ethnicity', 'race']):
                            has_ethnicity_breakdown = True
                        if cell.value.startswith('='):
                            formula_upper = cell.value.upper()
                            for fn in ['AVERAGE', 'MEDIAN', 'STDEV', 'COUNT', 'MIN', 'MAX', 'AVERAGEIFS', 'COUNTIFS']:
                                if fn in formula_upper:
                                    stat_formula_types.add(fn)
                                    has_stat_formulas = True

            points_2 = 0
            if has_gender_breakdown:
                points_2 += 6
            if has_ethnicity_breakdown:
                points_2 += 4
            if has_stat_formulas:
                points_2 += 6
                if len(stat_formula_types) >= 3:
                    points_2 += 4

            score += min(points_2, 20)
            feedback_parts.append(f"Equity: gender={has_gender_breakdown}, ethnicity={has_ethnicity_breakdown}, stats={stat_formula_types}")
        else:
            feedback_parts.append("Equity Summary sheet: NOT FOUND")

        # ================================================================
        # Criterion 3: Flagged_Employees with adjustment calc (15 pts)
        # ================================================================
        flagged_name = None
        for s in wb.sheetnames:
            if any(kw in s.lower() for kw in ['flag', 'outlier', 'exception', 'action', 'adjust']):
                flagged_name = s
                break

        if flagged_name:
            flag_sheet = wb[flagged_name]
            has_employees = False
            has_adjustment = False
            data_rows = 0

            for row in flag_sheet.iter_rows():
                has_data = any(cell.value is not None for cell in row)
                if has_data:
                    data_rows += 1
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        if 'E1' in cell.value:
                            has_employees = True
                        val_lower = cell.value.lower()
                        if 'adjust' in val_lower or 'correction' in val_lower or 'delta' in val_lower:
                            has_adjustment = True

            # Check for formulas
            has_formulas = any(
                cell.value and isinstance(cell.value, str) and cell.value.startswith('=')
                for row in flag_sheet.iter_rows() for cell in row
            )

            points_3 = 0
            if data_rows >= 3:
                points_3 += 5
            elif data_rows >= 1:
                points_3 += 3
            if has_employees:
                points_3 += 3
            if has_adjustment:
                points_3 += 4
            if has_formulas:
                points_3 += 3

            score += min(points_3, 15)
            feedback_parts.append(f"Flagged: {data_rows} rows, employees={has_employees}, adjustment={has_adjustment}")
        else:
            feedback_parts.append("Flagged Employees sheet: NOT FOUND")

        # ================================================================
        # Criterion 4: Conditional formatting (15 pts)
        # ================================================================
        has_cf = False
        cf_on_compa = False

        if compa_name:
            compa_sheet = wb[compa_name]
            if compa_sheet.conditional_formatting:
                has_cf = True
                cf_on_compa = True

        if not has_cf:
            for sn in wb.sheetnames:
                if sn.lower() not in starter_sheets:
                    sheet = wb[sn]
                    if sheet.conditional_formatting:
                        has_cf = True
                        break

        if cf_on_compa:
            score += 15
            feedback_parts.append("Conditional formatting: on compa-ratio sheet")
        elif has_cf:
            score += 8
            feedback_parts.append("Conditional formatting: found (not on compa sheet)")
        else:
            feedback_parts.append("Conditional formatting: NOT FOUND")

        # ================================================================
        # Criterion 5: Scatter chart (15 pts)
        # ================================================================
        has_chart = False
        chart_sheet_name = None

        for sn in wb.sheetnames:
            if sn.lower() not in starter_sheets:
                sheet = wb[sn]
                if hasattr(sheet, '_charts') and len(sheet._charts) > 0:
                    has_chart = True
                    chart_sheet_name = sn
                    break

        if has_chart:
            score += 15
            feedback_parts.append(f"Chart: found on {chart_sheet_name}")
        else:
            feedback_parts.append("Chart: NOT FOUND")

        # ================================================================
        # Criterion 6: Cross-sheet references (10 pts)
        # ================================================================
        cross_ref_count = 0
        for sn in wb.sheetnames:
            if sn.lower() not in starter_sheets:
                sheet = wb[sn]
                for row in sheet.iter_rows():
                    for cell in row:
                        if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                            if 'Employees' in cell.value or 'Market' in cell.value or 'Benchmark' in cell.value:
                                cross_ref_count += 1

        if cross_ref_count >= 20:
            score += 10
            feedback_parts.append(f"Cross-refs: {cross_ref_count}")
        elif cross_ref_count >= 5:
            score += 6
            feedback_parts.append(f"Cross-refs: {cross_ref_count} (partial)")
        elif cross_ref_count >= 1:
            score += 3
            feedback_parts.append(f"Cross-refs: {cross_ref_count} (minimal)")
        else:
            feedback_parts.append("Cross-refs: none detected")

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
