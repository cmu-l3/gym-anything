#!/usr/bin/env python3
"""Verifier for production_capacity_planning task."""

import sys
import os
import json
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
    get_spreadsheet_text,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_production_capacity(traj, env_info, task_info):
    """
    Verify production capacity planning workbook.

    SCORING (100 points total):
    1. Schedule sheet exists with order allocations (20 pts)
    2. Schedule has date calculations and line assignments (20 pts)
    3. Utilization sheet with weekly percentages (20 pts)
    4. Conditional formatting on utilization (15 pts)
    5. Revenue/cost analysis sheet (15 pts)
    6. Stacked bar chart (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_paths = ["/home/ga/Documents/production_capacity_plan.xlsx"]
    try:
        result_path = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'tmp_prod_result.json')
        copy_from_env('/tmp/production_capacity_result.json', result_path)
        with open(result_path) as f:
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
        starter_sheets = {"production_lines", "orders", "calendar"}

        # ================================================================
        # Criterion 1: Schedule sheet exists with order allocations (20 pts)
        # ================================================================
        schedule_name = None
        for s in wb.sheetnames:
            if 'schedule' in s.lower() or 'alloc' in s.lower():
                schedule_name = s
                break

        if schedule_name:
            sched = wb[schedule_name]
            # Count rows with data (orders should be allocated)
            data_rows = 0
            has_order_ids = False
            has_line_refs = False
            for row in sched.iter_rows(min_row=2):
                has_data = any(cell.value is not None for cell in row)
                if has_data:
                    data_rows += 1
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        if 'ORD-' in str(cell.value):
                            has_order_ids = True
                        if cell.value in ('L1', 'L2', 'L3', 'L4') or 'Assembly' in str(cell.value) or 'Fabrication' in str(cell.value) or 'Packaging' in str(cell.value):
                            has_line_refs = True

            points_1 = 0
            if data_rows >= 10:
                points_1 += 10
            elif data_rows >= 5:
                points_1 += 6
            elif data_rows >= 1:
                points_1 += 3

            if has_order_ids:
                points_1 += 5
            if has_line_refs:
                points_1 += 5

            score += min(points_1, 20)
            feedback_parts.append(f"Schedule: {data_rows} rows, orders={has_order_ids}, lines={has_line_refs}")
        else:
            feedback_parts.append("Schedule sheet: NOT FOUND")

        # ================================================================
        # Criterion 2: Schedule has date calculations (20 pts)
        # ================================================================
        if schedule_name:
            sched = wb[schedule_name]
            has_dates = False
            has_date_formulas = False
            has_slack = False

            for row in sched.iter_rows():
                for cell in row:
                    # Check for date values
                    if cell.value and hasattr(cell.value, 'year'):
                        has_dates = True
                    # Check for date-related formulas
                    if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                        formula_upper = cell.value.upper()
                        if any(kw in formula_upper for kw in ['DATE', 'WORKDAY', 'NETWORKDAYS', 'TODAY', 'DAY']):
                            has_date_formulas = True
                    # Check for slack column header
                    if cell.value and isinstance(cell.value, str):
                        if 'slack' in cell.value.lower() or 'buffer' in cell.value.lower() or 'days remaining' in cell.value.lower():
                            has_slack = True

            # Check for formulas in general
            formula_count = sum(1 for row in sched.iter_rows() for cell in row
                              if cell.value and isinstance(cell.value, str) and cell.value.startswith('='))

            points_2 = 0
            if has_dates or has_date_formulas:
                points_2 += 8
            if has_date_formulas:
                points_2 += 5
            if has_slack:
                points_2 += 4
            if formula_count >= 10:
                points_2 += 3

            score += min(points_2, 20)
            feedback_parts.append(f"Dates: dates={has_dates}, date_formulas={has_date_formulas}, slack={has_slack}")
        else:
            feedback_parts.append("Date calculations: skipped")

        # ================================================================
        # Criterion 3: Utilization sheet with weekly percentages (20 pts)
        # ================================================================
        util_name = None
        for s in wb.sheetnames:
            if 'utiliz' in s.lower() or 'capacity' in s.lower():
                util_name = s
                break

        if util_name:
            util_sheet = wb[util_name]
            has_weekly_structure = False
            has_line_names = False
            has_percentages = False
            has_formulas = False

            for row in util_sheet.iter_rows(max_row=5):
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        if 'week' in cell.value.lower() or 'w1' in cell.value.lower() or 'jan' in cell.value.lower():
                            has_weekly_structure = True
                        if any(ln in cell.value for ln in ['L1', 'L2', 'L3', 'L4', 'Alpha', 'Beta', 'Fabrication', 'Packaging']):
                            has_line_names = True

            for row in util_sheet.iter_rows():
                for cell in row:
                    if cell.number_format and '%' in str(cell.number_format):
                        has_percentages = True
                    if cell.value and isinstance(cell.value, (int, float)) and 0 < cell.value <= 200:
                        has_percentages = True
                    if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                        has_formulas = True

            points_3 = 0
            if has_weekly_structure:
                points_3 += 6
            if has_line_names:
                points_3 += 5
            if has_percentages:
                points_3 += 5
            if has_formulas:
                points_3 += 4

            score += min(points_3, 20)
            feedback_parts.append(f"Utilization: weekly={has_weekly_structure}, lines={has_line_names}, pct={has_percentages}")
        else:
            feedback_parts.append("Utilization sheet: NOT FOUND")

        # ================================================================
        # Criterion 4: Conditional formatting on utilization (15 pts)
        # ================================================================
        has_cf = False
        cf_sheets = []

        for sn in wb.sheetnames:
            if sn.lower() not in starter_sheets:
                sheet = wb[sn]
                if sheet.conditional_formatting:
                    has_cf = True
                    cf_sheets.append(sn)

        cf_on_util = util_name in cf_sheets if util_name else False

        if cf_on_util:
            score += 15
            feedback_parts.append("Conditional formatting: on utilization sheet")
        elif has_cf:
            score += 8
            feedback_parts.append(f"Conditional formatting: found on {cf_sheets}")
        else:
            feedback_parts.append("Conditional formatting: NOT FOUND")

        # ================================================================
        # Criterion 5: Revenue/cost analysis (15 pts)
        # ================================================================
        rev_name = None
        for s in wb.sheetnames:
            if any(kw in s.lower() for kw in ['revenue', 'profit', 'cost', 'analysis', 'financial']):
                rev_name = s
                break

        if rev_name:
            rev_sheet = wb[rev_name]
            has_revenue_calc = False
            has_cost_calc = False
            has_margin = False

            for row in rev_sheet.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        val_lower = cell.value.lower()
                        if 'revenue' in val_lower or 'sales' in val_lower:
                            has_revenue_calc = True
                        if 'cost' in val_lower:
                            has_cost_calc = True
                        if 'margin' in val_lower or 'profit' in val_lower:
                            has_margin = True

            formula_count = sum(1 for row in rev_sheet.iter_rows() for cell in row
                              if cell.value and isinstance(cell.value, str) and cell.value.startswith('='))

            points_5 = 0
            if has_revenue_calc:
                points_5 += 5
            if has_cost_calc:
                points_5 += 4
            if has_margin:
                points_5 += 3
            if formula_count >= 5:
                points_5 += 3

            score += min(points_5, 15)
            feedback_parts.append(f"Revenue analysis: rev={has_revenue_calc}, cost={has_cost_calc}, margin={has_margin}")
        else:
            feedback_parts.append("Revenue analysis sheet: NOT FOUND")

        # ================================================================
        # Criterion 6: Stacked bar chart (10 pts)
        # ================================================================
        has_chart = False
        chart_sheet = None

        for sn in wb.sheetnames:
            if sn.lower() not in starter_sheets:
                sheet = wb[sn]
                if hasattr(sheet, '_charts') and len(sheet._charts) > 0:
                    has_chart = True
                    chart_sheet = sn
                    break

        if has_chart:
            score += 10
            feedback_parts.append(f"Chart: found on {chart_sheet}")
        else:
            feedback_parts.append("Chart: NOT FOUND")

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
