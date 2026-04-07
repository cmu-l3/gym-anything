#!/usr/bin/env python3
"""
Verifier for Timber Cruise Inventory Analysis task.

The agent must compile a 30-plot, BAF-20 timber cruise dataset of ~500 trees.
Requires calculation of TPA expansion factors, lookup of gross volume,
calculation of net volume, and aggregation by species and DBH class,
culminating in a tract-level total for 240 acres.

Expected values:
- Tree count: ~470-520
- TPA per tree: varies by DBH (e.g., DBH=8 -> TPA=~57.3)
- Tract Acreage = 240
- Total Volume ~ 5-10 MMBF (5,000,000 - 10,000,000 board feet)
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Key forestry terms and species
EXPECTED_SPECIES = ["DF", "WH", "WRC", "RA", "BM"]
FORESTRY_TERMS = ["baf", "tpa", "basal area", "scribner", "mbf", "bf", "gross", "net", "defect", "acre"]


def extract_all_text(wb):
    """Extract all text from all cells in all sheets."""
    all_text = []
    for sheet_name in wb.sheetnames:
        sheet = wb[sheet_name]
        for row in sheet.iter_rows(max_row=min(sheet.max_row, 1000),
                                    max_col=min(sheet.max_column, 30)):
            for cell in row:
                if cell.value is not None:
                    all_text.append(str(cell.value).lower())
    return " ".join(all_text)


def extract_all_numbers(wb):
    """Extract all numeric values across all sheets."""
    numbers = []
    for sn in wb.sheetnames:
        sheet = wb[sn]
        for row in sheet.iter_rows(max_row=min(sheet.max_row, 1000),
                                    max_col=min(sheet.max_column, 30)):
            for cell in row:
                if isinstance(cell.value, (int, float)) and cell.value != 0:
                    numbers.append(cell.value)
    return numbers


def verify_timber_inventory(traj, env_info, task_info):
    """
    Verify the completed timber cruise inventory workbook.
    Returns score out of 100.
    Pass threshold: 50.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/elk_creek_inventory.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_timber_')

    try:
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Gate failed: Could not load elk_creek_inventory.xlsx: {error}"
            }

        feedback_parts = []
        raw_score = 0.0

        all_text = extract_all_text(wb)
        all_numbers = extract_all_numbers(wb)
        num_sheets = len(wb.sheetnames)

        # Count total filled cells
        total_cells = 0
        for sn in wb.sheetnames:
            sheet = wb[sn]
            for row in sheet.iter_rows(max_row=min(sheet.max_row, 1000),
                                        max_col=min(sheet.max_column, 30)):
                for cell in row:
                    if cell.value is not None:
                        total_cells += 1

        if total_cells < 50:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Gate failed: Workbook contains insufficient data (< 50 cells)"
            }

        # CHECK 1: Data import completeness (1.0 pt)
        # We expect a lot of numbers since there are ~500 trees * 8 columns
        if len(all_numbers) > 1000:
            raw_score += 1.0
            feedback_parts.append("Data import successful (>1000 numeric values)")
        elif len(all_numbers) > 200:
            raw_score += 0.5
            feedback_parts.append("Partial data import detected")
        else:
            feedback_parts.append("Raw data missing or incomplete")

        # CHECK 2: Per-tree expansion factors (2.0 pts)
        # Look for the constant 0.005454, BAF 20, or numbers in the typical TPA range (1.0 - 60.0)
        ba_constant_present = "0.00545" in all_text or "5454" in all_text or 0.005454 in all_numbers
        tpa_range_vals = [n for n in all_numbers if 1.0 < n < 60.0]
        
        if ba_constant_present and len(tpa_range_vals) > 50:
            raw_score += 2.0
            feedback_parts.append("Expansion factors (TPA) correctly calculated")
        elif len(tpa_range_vals) > 50:
            raw_score += 1.0
            feedback_parts.append("Expansion factors approximated/calculated without clear constant")
        else:
            feedback_parts.append("Expansion factor (TPA) calculations not detected")

        # CHECK 3: Species-level summary (2.0 pts)
        species_found = sum(1 for sp in EXPECTED_SPECIES if sp.lower() in all_text)
        if species_found >= 4:
            raw_score += 2.0
            feedback_parts.append(f"Species summary present ({species_found}/5 species)")
        elif species_found >= 2:
            raw_score += 1.0
            feedback_parts.append(f"Partial species summary ({species_found}/5 species)")
        else:
            feedback_parts.append("Species summary missing")

        # CHECK 4: Diameter class distribution (1.5 pts)
        # Look for DBH classes like 10, 12, 14, 16, 18 near each other or frequently
        dbh_classes = [10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30]
        classes_found = sum(1 for c in dbh_classes if str(c) in all_text or c in all_numbers)
        if classes_found >= 6:
            raw_score += 1.5
            feedback_parts.append("DBH class aggregation present")
        elif classes_found >= 3:
            raw_score += 0.5
            feedback_parts.append("Partial DBH class aggregation")
        else:
            feedback_parts.append("DBH class aggregation missing")

        # CHECK 5: Net volume calculation (1.5 pts)
        has_gross = "gross" in all_text
        has_net = "net" in all_text
        has_defect = "defect" in all_text
        if has_gross and has_net and has_defect:
            raw_score += 1.5
            feedback_parts.append("Net volume calculations (Gross vs Net/Defect) present")
        elif has_gross or has_net:
            raw_score += 0.5
            feedback_parts.append("Volume headers present but incomplete net/gross distinction")
        else:
            feedback_parts.append("Volume calculation headers missing")

        # CHECK 6: Tract-level totals (1.0 pt)
        # Plausible tract volume for 240 acres is roughly 2-15 MMBF (2,000,000 - 15,000,000 BF)
        # or 2,000 - 15,000 MBF
        has_multiplier = 240 in all_numbers or "240" in all_text
        plausible_volume = any(2000 < n < 15000 for n in all_numbers) or any(2000000 < n < 15000000 for n in all_numbers)
        
        if has_multiplier and plausible_volume:
            raw_score += 1.0
            feedback_parts.append("Tract-level volume extrapolated correctly (240 acres)")
        elif has_multiplier or plausible_volume:
            raw_score += 0.5
            feedback_parts.append("Partial tract-level extrapolation (multiplier or plausible total found)")
        else:
            feedback_parts.append("Tract total volume extrapolation missing")

        # CHECK 7: Professional structure & terminology (1.0 pt)
        terms_found = sum(1 for t in FORESTRY_TERMS if t in all_text)
        if num_sheets >= 2 and terms_found >= 4:
            raw_score += 1.0
            feedback_parts.append("Professional structure with correct forestry terminology")
        elif terms_found >= 2:
            raw_score += 0.5
            feedback_parts.append("Basic forestry terminology present")
        else:
            feedback_parts.append("Forestry terminology lacking")

        # Calculate final 0-100 score
        final_score = int((raw_score / 10.0) * 100)
        passed = final_score >= 50

        return {
            "passed": passed,
            "score": final_score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error verifying timber inventory: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)