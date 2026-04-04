#!/usr/bin/env python3
"""
Verifier for Snow Removal Equity Tracker task.

Checks:
1. COUNTIF formulas present in column B
2. Contribution counts accurate (Johnson=6, Smith=5, Patel=4, Lee=2, Garcia=1, O'Brien=0)
3. Fair share calculated correctly (3 per household)
4. Deficits calculated correctly (actual - fair share)
5. Makeup shifts calculated correctly (ABS of negative deficits only)
6. Conservation law satisfied (sum of deficits = 0)
7. Total validation (sum of contributions = 18)
"""

import sys
import os
import logging
import re

# Add utils to path - use relative path for host machine
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value,
    get_cell_formula,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_snow_removal_equity(traj, env_info, task_info):
    """
    Verify snow removal equity tracker completion.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/snow_equity.ods"
    success, file_info, error = setup_calc_verification(
        copy_from_env,
        container_path,
        expected_formats=['ods']
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load file: {error}"}

    try:
        data = file_info['sheet_data']
        
        # Find the Household Summary sheet
        summary_sheet = None
        for sheet_name in data.get('sheets', {}).keys():
            if 'summary' in sheet_name.lower() or 'household' in sheet_name.lower():
                summary_sheet = sheet_name
                break
        
        if not summary_sheet:
            # Try second sheet by index
            sheet_names = list(data.get('sheets', {}).keys())
            if len(sheet_names) >= 2:
                summary_sheet = sheet_names[1]
            else:
                return {"passed": False, "score": 0, "feedback": "Could not find Household Summary sheet"}

        logger.info(f"Using sheet: {summary_sheet}")

        criteria_passed = 0
        total_criteria = 7
        feedback_parts = []

        # Expected data based on seeded snow events
        expected_counts = {
            "johnson": 6,
            "smith": 5,
            "patel": 4,
            "lee": 2,
            "garcia": 1,
            "o'brien": 0,
            "obrien": 0  # Handle variations
        }
        
        expected_fair_share = 3  # 18 events ÷ 6 households
        
        # Track data for validation
        actual_counts = {}
        formulas_present = {}
        fair_shares = {}
        deficits = {}
        makeups = {}
        
        # Parse rows 2-7 (households)
        for row_idx in range(2, 8):  # A2:A7 (rows 2-7, 0-indexed would be 1-6 in data structure)
            household = get_cell_value(data, summary_sheet, f'A{row_idx}')
            if not household or household.lower() == 'total':
                continue
            
            household_key = household.lower().replace("'", "").strip()
            
            # Column B: Times Shoveled (should have COUNTIF formula)
            times_shoveled = get_cell_value(data, summary_sheet, f'B{row_idx}')
            formula_b = get_cell_formula(data, summary_sheet, f'B{row_idx}')
            
            # Column C: Fair Share
            fair_share = get_cell_value(data, summary_sheet, f'C{row_idx}')
            
            # Column D: Deficit/Surplus
            deficit = get_cell_value(data, summary_sheet, f'D{row_idx}')
            
            # Column E: Makeup Shifts
            makeup = get_cell_value(data, summary_sheet, f'E{row_idx}')
            
            # Store values
            if times_shoveled is not None:
                actual_counts[household_key] = float(times_shoveled) if times_shoveled != '' else None
            if formula_b:
                formulas_present[household_key] = formula_b
            if fair_share is not None:
                fair_shares[household_key] = float(fair_share) if fair_share != '' else None
            if deficit is not None:
                deficits[household_key] = float(deficit) if deficit != '' else None
            if makeup is not None:
                makeups[household_key] = float(makeup) if makeup != '' else None

        # Criterion 1: COUNTIF formulas present
        countif_present = 0
        for household_key, formula in formulas_present.items():
            if formula and 'COUNTIF' in formula.upper():
                countif_present += 1
        
        if countif_present >= 5:  # At least 5 out of 6 households
            criteria_passed += 1
            feedback_parts.append(f"✅ COUNTIF formulas present ({countif_present} households)")
        else:
            feedback_parts.append(f"❌ Missing COUNTIF formulas (found {countif_present}, need 5+)")

        # Criterion 2: Counts accurate
        counts_correct = 0
        counts_total = 0
        for household_key, expected in expected_counts.items():
            if household_key in actual_counts:
                counts_total += 1
                actual = actual_counts[household_key]
                if actual is not None and abs(actual - expected) < 0.1:
                    counts_correct += 1
                else:
                    logger.info(f"Count mismatch for {household_key}: expected {expected}, got {actual}")
        
        if counts_correct >= 5:  # At least 5 out of 6 correct
            criteria_passed += 1
            feedback_parts.append(f"✅ Contribution counts accurate ({counts_correct}/{counts_total})")
        else:
            feedback_parts.append(f"❌ Contribution counts incorrect ({counts_correct}/{counts_total} correct)")

        # Criterion 3: Fair share correct
        fair_share_correct = sum(1 for fs in fair_shares.values() if fs is not None and abs(fs - expected_fair_share) < 0.1)
        
        if fair_share_correct >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Fair share correct (3 per household)")
        else:
            feedback_parts.append(f"❌ Fair share incorrect (found {fair_share_correct} correct)")

        # Criterion 4: Deficits calculated correctly
        deficits_correct = 0
        for household_key in actual_counts.keys():
            if household_key in actual_counts and household_key in fair_shares and household_key in deficits:
                expected_deficit = actual_counts[household_key] - fair_shares[household_key]
                actual_deficit = deficits[household_key]
                if actual_deficit is not None and abs(actual_deficit - expected_deficit) < 0.1:
                    deficits_correct += 1

        if deficits_correct >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Deficits calculated correctly")
        else:
            feedback_parts.append(f"❌ Deficit calculations incorrect ({deficits_correct} correct)")

        # Criterion 5: Makeup shifts calculated correctly
        makeups_correct = 0
        for household_key in deficits.keys():
            if household_key in deficits and household_key in makeups:
                deficit_val = deficits[household_key]
                makeup_val = makeups[household_key]
                
                if deficit_val is not None and makeup_val is not None:
                    if deficit_val < 0:
                        # Should have makeup equal to absolute value of deficit
                        expected_makeup = abs(deficit_val)
                        if abs(makeup_val - expected_makeup) < 0.1:
                            makeups_correct += 1
                    else:
                        # Should have makeup of 0
                        if makeup_val == 0 or abs(makeup_val) < 0.1:
                            makeups_correct += 1

        if makeups_correct >= 5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Makeup shifts calculated correctly")
        else:
            feedback_parts.append(f"❌ Makeup shift calculations incorrect ({makeups_correct} correct)")

        # Criterion 6: Conservation law (sum of deficits = 0)
        total_deficit = sum(d for d in deficits.values() if d is not None)
        
        if abs(total_deficit) < 0.5:  # Allow small floating point error
            criteria_passed += 1
            feedback_parts.append(f"✅ Conservation law satisfied (total deficit = {total_deficit:.1f})")
        else:
            feedback_parts.append(f"❌ Conservation law violated (total deficit = {total_deficit:.1f}, should be 0)")

        # Criterion 7: Total validation (sum of contributions = 18)
        total_contributions = sum(c for c in actual_counts.values() if c is not None)
        
        if abs(total_contributions - 18) < 0.5:
            criteria_passed += 1
            feedback_parts.append(f"✅ Total contributions = 18")
        else:
            feedback_parts.append(f"❌ Total contributions incorrect (got {total_contributions}, expected 18)")

        # Calculate score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 85  # Need 6/7 criteria (85%+)
        
        # Add summary
        if passed and score >= 95:
            feedback_parts.append("🎉 Perfect equity analysis!")
        elif passed:
            feedback_parts.append("✅ Equity tracker completed successfully")
        else:
            feedback_parts.append("❌ Equity tracker requirements not fully met")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "countif_formulas": countif_present >= 5,
                "counts_accurate": counts_correct >= 5,
                "fair_share_correct": fair_share_correct >= 5,
                "deficits_correct": deficits_correct >= 5,
                "makeups_correct": makeups_correct >= 5,
                "conservation_law": abs(total_deficit) < 0.5,
                "total_validation": abs(total_contributions - 18) < 0.5
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(file_info.get('temp_dir'))
