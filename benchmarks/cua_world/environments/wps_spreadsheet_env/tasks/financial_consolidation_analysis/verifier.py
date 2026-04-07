#!/usr/bin/env python3
"""Verifier for financial_consolidation_analysis task."""

import sys
import os
import json
import logging

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp,
    get_spreadsheet_text,
    get_cell_value,
    check_cell_formatting,
    vlm_verify_screenshot,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _find_value_in_sheet(sheet, account_name, value_col_offset=1):
    """Find a value in a sheet by searching for account_name in column A."""
    for row in sheet.iter_rows(min_col=1, max_col=1):
        for cell in row:
            if cell.value and isinstance(cell.value, str):
                if account_name.lower() in cell.value.lower():
                    val_cell = sheet.cell(row=cell.row, column=cell.column + value_col_offset)
                    return val_cell.value
    return None


def _check_formula_references(sheet, target_sheets):
    """Check if formulas in a sheet reference other sheets."""
    refs_found = set()
    for row in sheet.iter_rows():
        for cell in row:
            if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                formula = cell.value
                for ts in target_sheets:
                    if ts in formula or ts.replace(' ', '_') in formula:
                        refs_found.add(ts)
    return refs_found


def _resolve_value(val):
    """Try to get a numeric value, handling formulas gracefully."""
    if val is None:
        return None
    if isinstance(val, (int, float)):
        return float(val)
    if isinstance(val, str) and val.startswith('='):
        return None  # Formula - can't evaluate without Excel engine
    try:
        return float(str(val).replace(',', '').replace('$', ''))
    except (ValueError, TypeError):
        return None


def verify_financial_consolidation(traj, env_info, task_info):
    """
    Verify financial consolidation analysis.

    SCORING (100 points total):
    1. Consolidated sheet exists with correct structure (15 pts)
    2. Consolidated values correct (IC eliminations applied) (20 pts)
    3. Financial Ratios sheet with correct ratio formulas (20 pts)
    4. Variance Analysis sheet with dollar and % variance (15 pts)
    5. Conditional formatting on variance sheet (15 pts)
    6. Dashboard chart exists (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load ground truth
    gt = task_info.get('metadata', {}).get('ground_truth', {})
    gt_file = None
    try:
        gt_file_path = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'tmp_gt.json')
        # Try to copy GT from env
        try:
            copy_from_env('/tmp/financial_consolidation_gt.json', gt_file_path)
            with open(gt_file_path) as f:
                gt = json.load(f)
        except Exception:
            pass
    except Exception:
        pass

    container_paths = [
        "/home/ga/Documents/meridian_holdings_consolidation.xlsx",
    ]
    # Also search for any consolidation-related file
    try:
        docs_list_path = os.path.join(os.path.dirname(__file__), '..', '..', '..', 'tmp_docs.txt')
        copy_from_env('/tmp/financial_consolidation_result.json', docs_list_path)
        with open(docs_list_path) as f:
            result_data = json.load(f)
        if result_data.get('found_path'):
            container_paths.insert(0, result_data['found_path'])
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
        sheets_lower = {s.lower(): s for s in wb.sheetnames}
        starter_sheets = {"alpha_inc", "beta_corp", "gamma_llc", "intercompany", "prior_year"}

        # ================================================================
        # Criterion 1: Consolidated sheet exists with correct structure (15 pts)
        # ================================================================
        consol_sheet_name = None
        for s in wb.sheetnames:
            if 'consolidat' in s.lower():
                consol_sheet_name = s
                break

        if consol_sheet_name:
            consol = wb[consol_sheet_name]
            # Check it has revenue, COGS, net income rows
            has_revenue = False
            has_cogs = False
            has_net_income = False
            for row in consol.iter_rows(min_col=1, max_col=1):
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        val_lower = cell.value.lower()
                        if 'revenue' in val_lower:
                            has_revenue = True
                        if 'cost of goods' in val_lower or 'cogs' in val_lower:
                            has_cogs = True
                        if 'net income' in val_lower:
                            has_net_income = True

            if has_revenue and has_net_income:
                score += 15
                feedback_parts.append("Consolidated sheet: complete structure")
            elif has_revenue or has_net_income:
                score += 8
                feedback_parts.append("Consolidated sheet: partial structure")
            else:
                score += 3
                feedback_parts.append("Consolidated sheet: exists but incomplete")
        else:
            feedback_parts.append("Consolidated sheet: NOT FOUND")

        # ================================================================
        # Criterion 2: Consolidated values correct with IC elimination (20 pts)
        # ================================================================
        if consol_sheet_name:
            consol = wb[consol_sheet_name]

            # Check for cross-sheet formula references (evidence of proper consolidation)
            refs = _check_formula_references(consol, ['Alpha_Inc', 'Beta_Corp', 'Gamma_LLC', 'Intercompany'])
            has_cross_refs = len(refs) >= 2

            # Try to find consolidated revenue value
            consol_rev = _find_value_in_sheet(consol, 'Revenue')
            consol_rev_val = _resolve_value(consol_rev)

            consol_ni = _find_value_in_sheet(consol, 'Net Income')
            consol_ni_val = _resolve_value(consol_ni)

            expected_rev = gt.get('consolidated_revenue', 96500000)
            expected_ni = gt.get('consolidated_net_income', 8493000)

            points_2 = 0

            # Cross-sheet references indicate proper formula-based consolidation
            if has_cross_refs:
                points_2 += 8
                feedback_parts.append(f"Cross-sheet refs: {refs}")
            elif consol_rev and isinstance(consol_rev, str) and consol_rev.startswith('='):
                points_2 += 5
                feedback_parts.append("Has formulas but unclear cross-refs")

            # Check if values are correct (if we can resolve them)
            if consol_rev_val is not None:
                tolerance = expected_rev * 0.08  # 8% tolerance
                if abs(consol_rev_val - expected_rev) <= tolerance:
                    points_2 += 7
                    feedback_parts.append(f"Revenue correct: {consol_rev_val:,.0f}")
                elif consol_rev_val < (49200000 + 34300000 + 18500000) * 1.01:
                    # Revenue is less than simple sum - some elimination applied
                    points_2 += 4
                    feedback_parts.append(f"Revenue partially correct: {consol_rev_val:,.0f}")
                else:
                    feedback_parts.append(f"Revenue incorrect: {consol_rev_val:,.0f} (expected ~{expected_rev:,.0f})")

            if consol_ni_val is not None:
                tolerance = expected_ni * 0.10
                if abs(consol_ni_val - expected_ni) <= tolerance:
                    points_2 += 5
                    feedback_parts.append(f"Net Income correct: {consol_ni_val:,.0f}")
                else:
                    feedback_parts.append(f"Net Income: {consol_ni_val:,.0f} (expected ~{expected_ni:,.0f})")
            elif consol_ni and isinstance(consol_ni, str) and consol_ni.startswith('='):
                points_2 += 3
                feedback_parts.append("Net Income has formula (can't evaluate)")

            score += min(points_2, 20)
        else:
            feedback_parts.append("Consolidation values: skipped (no sheet)")

        # ================================================================
        # Criterion 3: Financial Ratios sheet (20 pts)
        # ================================================================
        ratios_sheet_name = None
        for s in wb.sheetnames:
            if 'ratio' in s.lower():
                ratios_sheet_name = s
                break

        if ratios_sheet_name:
            ratios = wb[ratios_sheet_name]
            # Check for ratio names
            ratio_names_found = set()
            ratio_keywords = {
                'current_ratio': ['current ratio'],
                'quick_ratio': ['quick ratio'],
                'debt_equity': ['debt-to-equity', 'debt to equity', 'debt/equity', 'd/e'],
                'gross_margin': ['gross margin'],
                'operating_margin': ['operating margin'],
                'net_margin': ['net margin'],
                'roe': ['return on equity', 'roe'],
                'roa': ['return on assets', 'roa'],
            }

            for row in ratios.iter_rows():
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        cell_lower = cell.value.lower()
                        for key, keywords in ratio_keywords.items():
                            for kw in keywords:
                                if kw in cell_lower:
                                    ratio_names_found.add(key)

            # Check for formulas referencing consolidated sheet
            has_consol_refs = bool(_check_formula_references(ratios, [consol_sheet_name] if consol_sheet_name else []))

            points_3 = 0
            ratio_count = len(ratio_names_found)

            if ratio_count >= 7:
                points_3 += 12
            elif ratio_count >= 5:
                points_3 += 8
            elif ratio_count >= 3:
                points_3 += 5
            elif ratio_count >= 1:
                points_3 += 2

            if has_consol_refs:
                points_3 += 8
            else:
                # Check if there are any formulas at all
                formula_count = sum(1 for row in ratios.iter_rows() for cell in row
                                   if cell.value and isinstance(cell.value, str) and cell.value.startswith('='))
                if formula_count > 0:
                    points_3 += 4

            score += min(points_3, 20)
            feedback_parts.append(f"Ratios: {ratio_count}/8 found, consol_refs={has_consol_refs}")
        else:
            feedback_parts.append("Financial Ratios sheet: NOT FOUND")

        # ================================================================
        # Criterion 4: Variance Analysis sheet (15 pts)
        # ================================================================
        variance_sheet_name = None
        for s in wb.sheetnames:
            if 'variance' in s.lower() or 'var_' in s.lower():
                variance_sheet_name = s
                break

        if variance_sheet_name:
            var_sheet = wb[variance_sheet_name]
            # Check for dollar variance and % variance columns
            has_dollar_var = False
            has_pct_var = False
            has_py_refs = bool(_check_formula_references(var_sheet, ['Prior_Year']))
            has_consol_refs = bool(_check_formula_references(var_sheet, [consol_sheet_name] if consol_sheet_name else []))

            for row in var_sheet.iter_rows(max_row=3):
                for cell in row:
                    if cell.value and isinstance(cell.value, str):
                        val_lower = cell.value.lower()
                        if 'dollar' in val_lower or '$ var' in val_lower or 'amount' in val_lower:
                            has_dollar_var = True
                        if '%' in str(cell.value) or 'percent' in val_lower or 'pct' in val_lower:
                            has_pct_var = True

            # Also check number formats for %
            for row in var_sheet.iter_rows(min_row=2):
                for cell in row:
                    if cell.number_format and '%' in str(cell.number_format):
                        has_pct_var = True
                        break

            points_4 = 0
            if has_dollar_var or has_pct_var:
                points_4 += 5
            if has_dollar_var and has_pct_var:
                points_4 += 3
            if has_py_refs or has_consol_refs:
                points_4 += 7
            elif sum(1 for row in var_sheet.iter_rows() for cell in row
                     if cell.value and isinstance(cell.value, str) and cell.value.startswith('=')) > 3:
                points_4 += 4

            score += min(points_4, 15)
            feedback_parts.append(f"Variance: dollar={has_dollar_var}, pct={has_pct_var}, refs={has_py_refs or has_consol_refs}")
        else:
            feedback_parts.append("Variance Analysis sheet: NOT FOUND")

        # ================================================================
        # Criterion 5: Conditional formatting on variance (15 pts)
        # ================================================================
        has_cf = False
        cf_on_variance = False

        if variance_sheet_name:
            var_sheet = wb[variance_sheet_name]
            if var_sheet.conditional_formatting:
                has_cf = True
                cf_on_variance = True

        # Also check any sheet for conditional formatting
        if not has_cf:
            for sn in wb.sheetnames:
                if sn.lower() not in starter_sheets:
                    sheet = wb[sn]
                    if sheet.conditional_formatting:
                        has_cf = True
                        break

        if cf_on_variance:
            score += 15
            feedback_parts.append("Conditional formatting: on variance sheet")
        elif has_cf:
            score += 8
            feedback_parts.append("Conditional formatting: found (not on variance sheet)")
        else:
            feedback_parts.append("Conditional formatting: NOT FOUND")

        # ================================================================
        # Criterion 6: Dashboard chart (15 pts)
        # ================================================================
        has_chart = False
        chart_on_dashboard = False

        dashboard_sheet_name = None
        for s in wb.sheetnames:
            if 'dashboard' in s.lower() or 'chart' in s.lower():
                dashboard_sheet_name = s
                break

        if dashboard_sheet_name:
            dash = wb[dashboard_sheet_name]
            if hasattr(dash, '_charts') and len(dash._charts) > 0:
                has_chart = True
                chart_on_dashboard = True

        # Check all new sheets for charts
        if not has_chart:
            for sn in wb.sheetnames:
                if sn.lower() not in starter_sheets:
                    sheet = wb[sn]
                    if hasattr(sheet, '_charts') and len(sheet._charts) > 0:
                        has_chart = True
                        break

        if chart_on_dashboard:
            score += 15
            feedback_parts.append("Dashboard chart: present on Dashboard sheet")
        elif has_chart:
            score += 8
            feedback_parts.append("Dashboard chart: found (not on Dashboard sheet)")
        elif dashboard_sheet_name:
            score += 3
            feedback_parts.append("Dashboard sheet exists but no chart")
        else:
            feedback_parts.append("Dashboard chart: NOT FOUND")

        # Final result
        passed = score >= 55
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
