#!/usr/bin/env python3
"""Verifier for budget_variance_dashboard task."""

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


def verify_budget_variance(traj, env_info, task_info):
    """
    Verify budget variance dashboard.

    SCORING (100 points total):
    1. Monthly_Variance sheet with cross-sheet formulas (20 pts)
    2. YTD_Summary sheet with cumulative calculations (20 pts)
    3. Executive_Summary with LARGE/INDEX-MATCH analysis (20 pts)
    4. Conditional formatting (icon sets, color coding) (15 pts)
    5. Clustered bar chart (budget vs actual) (12 pts)
    6. Line trend chart (monthly variance) (13 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_paths = ["/home/ga/Documents/budget_variance_analysis.xlsx"]
    try:
        rp = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'tmp_bv_result.json')
        copy_from_env('/tmp/budget_variance_result.json', rp)
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
        starter_sheets = {"budget", "actuals"}

        # ================================================================
        # Criterion 1: Monthly_Variance sheet with cross-sheet formulas (20 pts)
        # ================================================================
        var_name = None
        for s in wb.sheetnames:
            sl = s.lower()
            if ('variance' in sl or 'var' in sl) and sl not in starter_sheets:
                var_name = s
                break

        if var_name:
            var_sheet = wb[var_name]
            has_budget_refs = False
            has_actuals_refs = False
            has_pct_variance = False
            formula_count = 0

            for row in var_sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                        formula_count += 1
                        if 'Budget' in cell.value:
                            has_budget_refs = True
                        if 'Actual' in cell.value:
                            has_actuals_refs = True
                    if cell.number_format and '%' in str(cell.number_format):
                        has_pct_variance = True
                    if cell.value and isinstance(cell.value, str):
                        if '%' in cell.value.lower() or 'percent' in cell.value.lower():
                            has_pct_variance = True

            points_1 = 0
            if has_budget_refs and has_actuals_refs:
                points_1 += 10
            elif has_budget_refs or has_actuals_refs:
                points_1 += 5
            elif formula_count > 10:
                points_1 += 3

            if has_pct_variance:
                points_1 += 5

            if formula_count >= 50:
                points_1 += 5
            elif formula_count >= 20:
                points_1 += 3

            score += min(points_1, 20)
            feedback_parts.append(f"Monthly Var: budget_refs={has_budget_refs}, actual_refs={has_actuals_refs}, formulas={formula_count}")
        else:
            feedback_parts.append("Monthly Variance sheet: NOT FOUND")

        # ================================================================
        # Criterion 2: YTD_Summary sheet (20 pts)
        # ================================================================
        ytd_name = None
        for s in wb.sheetnames:
            sl = s.lower()
            if ('ytd' in sl or 'year' in sl or 'annual' in sl) and sl not in starter_sheets:
                ytd_name = s
                break

        if ytd_name:
            ytd_sheet = wb[ytd_name]
            has_cc_names = False
            has_ytd_calcs = False
            has_trend = False
            formula_count = 0

            for row in ytd_sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        if 'CC-' in cell.value or 'Headquarters' in cell.value or 'Sales' in cell.value or 'Engineering' in cell.value:
                            has_cc_names = True
                        val_lower = cell.value.lower()
                        if 'ytd' in val_lower or 'year to date' in val_lower or 'annual' in val_lower:
                            has_ytd_calcs = True
                        if 'trend' in val_lower or 'direction' in val_lower or 'improving' in val_lower:
                            has_trend = True
                        if cell.value.startswith('='):
                            formula_count += 1

            points_2 = 0
            if has_cc_names:
                points_2 += 5
            if has_ytd_calcs:
                points_2 += 5
            if has_trend:
                points_2 += 5
            if formula_count >= 15:
                points_2 += 5
            elif formula_count >= 5:
                points_2 += 3

            score += min(points_2, 20)
            feedback_parts.append(f"YTD: cc={has_cc_names}, ytd={has_ytd_calcs}, trend={has_trend}, formulas={formula_count}")
        else:
            feedback_parts.append("YTD Summary sheet: NOT FOUND")

        # ================================================================
        # Criterion 3: Executive_Summary with advanced formulas (20 pts)
        # ================================================================
        exec_name = None
        for s in wb.sheetnames:
            sl = s.lower()
            if any(kw in sl for kw in ['exec', 'summary', 'dashboard', 'overview']) and sl not in starter_sheets:
                if var_name and s == var_name:
                    continue
                exec_name = s
                break

        if exec_name:
            exec_sheet = wb[exec_name]
            has_large_small = False
            has_index_match = False
            has_top_bottom = False
            has_total_variance = False
            formula_count = 0

            for row in exec_sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        if cell.value.startswith('='):
                            formula_count += 1
                            fu = cell.value.upper()
                            if 'LARGE' in fu or 'SMALL' in fu:
                                has_large_small = True
                            if 'INDEX' in fu and 'MATCH' in fu:
                                has_index_match = True
                        val_lower = cell.value.lower()
                        if 'top' in val_lower or 'worst' in val_lower or 'largest' in val_lower or 'best' in val_lower:
                            has_top_bottom = True
                        if 'total' in val_lower and 'variance' in val_lower:
                            has_total_variance = True

            points_3 = 0
            if has_large_small:
                points_3 += 6
            if has_index_match:
                points_3 += 6
            if has_top_bottom:
                points_3 += 4
            if has_total_variance:
                points_3 += 2
            if formula_count >= 5:
                points_3 += 2

            score += min(points_3, 20)
            feedback_parts.append(f"Executive: LARGE={has_large_small}, INDEX-MATCH={has_index_match}, top_bottom={has_top_bottom}")
        else:
            feedback_parts.append("Executive Summary sheet: NOT FOUND")

        # ================================================================
        # Criterion 4: Conditional formatting (15 pts)
        # ================================================================
        has_cf = False
        cf_sheets = []

        for sn in wb.sheetnames:
            if sn.lower() not in starter_sheets:
                sheet = wb[sn]
                if sheet.conditional_formatting:
                    has_cf = True
                    cf_sheets.append(sn)

        if len(cf_sheets) >= 2:
            score += 15
            feedback_parts.append(f"Conditional formatting: on {cf_sheets}")
        elif has_cf:
            score += 10
            feedback_parts.append(f"Conditional formatting: on {cf_sheets}")
        else:
            feedback_parts.append("Conditional formatting: NOT FOUND")

        # ================================================================
        # Criterion 5: Clustered bar chart (12 pts)
        # ================================================================
        chart_count = 0
        chart_sheets = []
        for sn in wb.sheetnames:
            if sn.lower() not in starter_sheets:
                sheet = wb[sn]
                if hasattr(sheet, '_charts') and len(sheet._charts) > 0:
                    chart_count += len(sheet._charts)
                    chart_sheets.append(sn)

        if chart_count >= 1:
            score += 12
            feedback_parts.append(f"Bar chart: found ({chart_count} charts on {chart_sheets})")
        else:
            feedback_parts.append("Bar chart: NOT FOUND")

        # ================================================================
        # Criterion 6: Line trend chart (13 pts)
        # ================================================================
        if chart_count >= 2:
            score += 13
            feedback_parts.append(f"Trend chart: found (total {chart_count} charts)")
        elif chart_count == 1:
            score += 5
            feedback_parts.append("Trend chart: only 1 chart total (need 2)")
        else:
            feedback_parts.append("Trend chart: NOT FOUND")

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
