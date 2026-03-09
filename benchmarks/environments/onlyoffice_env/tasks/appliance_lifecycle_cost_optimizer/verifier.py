#!/usr/bin/env python3
"""
Verifier for Appliance Lifecycle Cost Optimizer task

This verifies that the user has:
1. Created a functional comparison matrix
2. Used formulas (not hardcoded values)
3. Analyzed all three appliances (washer, dryer, dishwasher)
4. Calculated 10-year total costs correctly
5. Provided recommendations
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_appliance_lifecycle_cost_optimizer(traj, env_info, task_info):
    """
    Verify that appliance lifecycle cost comparison was created correctly.

    Checks:
    1. File exists and is readable
    2. "Comparison Matrix" sheet exists
    3. Input parameters are present (10 years, $0.13/kWh, $0.008/gal)
    4. Multiple formulas are used (at least 12)
    5. Washer analysis section with 3 options
    6. At least 2 other appliances analyzed
    7. Summary/recommendation section exists
    8. Calculations are in reasonable ranges
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/appliance_decision.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_appliance_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0.0, "feedback": f"Failed to load spreadsheet: {error}"}

        feedback_parts = []
        score = 0.0
        max_score = 10.0  # Will normalize to 0-1 at the end

        # ====================================================================
        # Criterion 1: Check that "Comparison Matrix" sheet exists
        # ====================================================================
        sheet_names_lower = [s.lower() for s in wb.sheetnames]
        if 'comparison matrix' not in sheet_names_lower:
            feedback_parts.append("❌ Sheet 'Comparison Matrix' not found")
            return {
                "passed": False,
                "score": 0.0,
                "feedback": " | ".join(feedback_parts)
            }

        # Get the sheet (handle case-insensitive)
        sheet = None
        for sname in wb.sheetnames:
            if sname.lower() == 'comparison matrix':
                sheet = wb[sname]
                break

        if sheet is None:
            return {"passed": False, "score": 0.0, "feedback": "Could not access Comparison Matrix sheet"}

        feedback_parts.append("✅ Sheet 'Comparison Matrix' found")
        score += 1.0

        # ====================================================================
        # Criterion 2: Count formulas (should have at least 12)
        # ====================================================================
        formula_count = 0
        formula_cells = []

        for row_idx, row in enumerate(sheet.iter_rows(max_row=100, max_col=20), start=1):
            for col_idx, cell in enumerate(row, start=1):
                if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                    formula_count += 1
                    formula_cells.append(f"{chr(64+col_idx)}{row_idx}")

        if formula_count >= 12:
            feedback_parts.append(f"✅ Found {formula_count} formulas (need 12+)")
            score += 2.0
        elif formula_count >= 8:
            feedback_parts.append(f"⚠️ Found {formula_count} formulas (need 12+)")
            score += 1.0
        else:
            feedback_parts.append(f"❌ Only {formula_count} formulas found (need 12+)")

        # ====================================================================
        # Criterion 3: Check for input parameters (10, 0.13, 0.008)
        # ====================================================================
        found_years = False
        found_elec_rate = False
        found_water_rate = False

        for row in sheet.iter_rows(max_row=30, max_col=10):
            for cell in row:
                if cell.value is not None:
                    val = cell.value
                    # Check for analysis period (10 years)
                    if isinstance(val, (int, float)) and val == 10:
                        found_years = True
                    # Check for electricity rate (0.13)
                    if isinstance(val, (int, float)) and abs(val - 0.13) < 0.001:
                        found_elec_rate = True
                    # Check for water rate (0.008)
                    if isinstance(val, (int, float)) and abs(val - 0.008) < 0.0001:
                        found_water_rate = True

        params_found = sum([found_years, found_elec_rate, found_water_rate])
        if params_found == 3:
            feedback_parts.append("✅ All input parameters present (10 years, $0.13/kWh, $0.008/gal)")
            score += 1.5
        elif params_found >= 2:
            feedback_parts.append(f"⚠️ {params_found}/3 input parameters found")
            score += 0.7
        else:
            feedback_parts.append(f"❌ Input parameters missing ({params_found}/3 found)")

        # ====================================================================
        # Criterion 4: Check for appliance sections (Washer, Dryer, Dishwasher)
        # ====================================================================
        sheet_text = ""
        for row in sheet.iter_rows(max_row=100, max_col=20):
            for cell in row:
                if cell.value:
                    sheet_text += str(cell.value).lower() + " "

        appliances_found = []
        if 'washer' in sheet_text:
            appliances_found.append('Washer')
        if 'dryer' in sheet_text:
            appliances_found.append('Dryer')
        if 'dishwasher' in sheet_text:
            appliances_found.append('Dishwasher')

        if len(appliances_found) >= 3:
            feedback_parts.append(f"✅ All 3 appliances analyzed: {', '.join(appliances_found)}")
            score += 1.5
        elif len(appliances_found) == 2:
            feedback_parts.append(f"⚠️ 2 appliances analyzed: {', '.join(appliances_found)}")
            score += 1.0
        else:
            feedback_parts.append(f"❌ Insufficient appliance analyses ({len(appliances_found)}/3)")

        # ====================================================================
        # Criterion 5: Check for comparison options (repair, standard, efficient)
        # ====================================================================
        has_repair_option = 'repair' in sheet_text
        has_standard_option = 'standard' in sheet_text
        has_efficient_option = 'efficient' in sheet_text

        options_found = sum([has_repair_option, has_standard_option, has_efficient_option])
        if options_found >= 2:
            feedback_parts.append(f"✅ Multiple comparison options present ({options_found}/3)")
            score += 1.0
        else:
            feedback_parts.append(f"⚠️ Few comparison options found ({options_found}/3)")
            score += 0.3

        # ====================================================================
        # Criterion 6: Check for reasonable cost calculations
        # ====================================================================
        reasonable_cost_values = []
        very_large_values = []

        for row in sheet.iter_rows(max_row=100, max_col=20):
            for cell in row:
                if isinstance(cell.value, (int, float)):
                    val = float(cell.value)
                    # Look for values that could be 10-year totals ($100 - $10,000)
                    if 100 <= val <= 10000:
                        reasonable_cost_values.append(val)
                    # Also note if there are very large unreasonable values
                    if val > 50000:
                        very_large_values.append(val)

        # We expect around 9-12 total cost calculations (3 options × 3 appliances)
        if len(reasonable_cost_values) >= 9 and len(very_large_values) == 0:
            feedback_parts.append(f"✅ Realistic cost calculations present ({len(reasonable_cost_values)} values)")
            score += 1.5
        elif len(reasonable_cost_values) >= 6:
            feedback_parts.append(f"⚠️ Some cost calculations present ({len(reasonable_cost_values)} values)")
            score += 0.8
        else:
            feedback_parts.append(f"❌ Few cost calculations found ({len(reasonable_cost_values)} values)")

        # ====================================================================
        # Criterion 7: Check for summary/recommendation section
        # ====================================================================
        has_summary = 'summary' in sheet_text or 'recommendation' in sheet_text
        has_savings = 'saving' in sheet_text

        if has_summary or has_savings:
            feedback_parts.append("✅ Summary/recommendation section present")
            score += 1.0
        else:
            feedback_parts.append("⚠️ Summary section not clearly identified")
            score += 0.3

        # ====================================================================
        # Criterion 8: Check for cost components (energy, water, repairs)
        # ====================================================================
        has_energy_calc = 'energy' in sheet_text
        has_water_calc = 'water' in sheet_text
        has_repair_calc = 'repair' in sheet_text

        cost_components = sum([has_energy_calc, has_water_calc, has_repair_calc])
        if cost_components >= 2:
            feedback_parts.append(f"✅ Cost components identified ({cost_components}/3)")
            score += 0.5
        else:
            feedback_parts.append(f"⚠️ Few cost components ({cost_components}/3)")

        # ====================================================================
        # Final scoring
        # ====================================================================
        # Normalize score to 0-1 range
        final_score = min(1.0, score / max_score)
        passed = final_score >= 0.70

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
