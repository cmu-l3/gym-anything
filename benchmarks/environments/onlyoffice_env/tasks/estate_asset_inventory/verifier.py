#!/usr/bin/env python3
"""
Verifier for estate_asset_inventory@1 task
Checks if the disorganized estate data was properly reorganized into a court-ready inventory
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_estate_inventory(traj, env_info, task_info):
    """
    Verify that the estate asset inventory was properly organized.
    
    Scoring breakdown (100 points total):
    - Structure & Organization: 20 points
    - Data Completeness: 15 points
    - Calculation Accuracy: 30 points
    - Formula Usage: 20 points
    - Professional Formatting: 15 points
    
    Passing threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/estate_inventory_raw.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_estate_')

    try:
        # Copy file from container to temp location
        temp_file = os.path.join(temp_dir, 'estate_inventory.xlsx')
        copy_from_env(container_path, temp_file)
        
        if not os.path.exists(temp_file) or os.path.getsize(temp_file) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ File not found or empty: estate_inventory_raw.xlsx"
            }
        
        # Parse the spreadsheet
        wb = parse_xlsx_file(temp_file)
        if wb is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Could not parse Excel file"
            }
        
        ws = wb.active
        
        # Collect all data from the sheet
        data = []
        for row in ws.iter_rows(min_row=1, max_row=100, max_col=20):
            row_data = [cell.value for cell in row]
            # Include row if it has any non-empty content
            if any(v is not None and str(v).strip() != '' for v in row_data):
                data.append(row_data)
        
        if len(data) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Spreadsheet is empty"
            }
        
        score = 0
        feedback_parts = []
        
        # === CRITERION 1: Structure & Organization (20 points) ===
        structure_score = 0
        
        # Check for header row in first 3 rows
        has_headers = False
        header_row_idx = -1
        required_header_concepts = ['description', 'gross', 'lien', 'net', 'status', 'category']
        
        for i in range(min(3, len(data))):
            row_text = ' '.join([str(v).lower() if v else '' for v in data[i]])
            matches = sum(1 for concept in required_header_concepts if concept in row_text)
            if matches >= 4:  # At least 4 of 6 required concepts
                has_headers = True
                header_row_idx = i
                structure_score += 5
                feedback_parts.append("✅ Header row present")
                break
        
        if not has_headers:
            feedback_parts.append("❌ No clear header row found")
        
        # Map column indices based on headers
        col_map = {}
        if has_headers and header_row_idx >= 0:
            header_row = data[header_row_idx]
            for idx, val in enumerate(header_row):
                if val:
                    val_lower = str(val).lower()
                    if 'description' in val_lower or 'asset' in val_lower or 'item' in val_lower:
                        col_map['description'] = idx
                    if 'gross' in val_lower and 'value' in val_lower:
                        col_map['gross'] = idx
                    if 'lien' in val_lower or 'debt' in val_lower:
                        col_map['lien'] = idx
                    if 'net' in val_lower and 'value' in val_lower:
                        col_map['net'] = idx
                    if 'status' in val_lower or 'verif' in val_lower:
                        col_map['status'] = idx
                    if 'category' in val_lower or 'type' in val_lower:
                        col_map['category'] = idx
            
            required_cols = ['description', 'gross', 'net']
            found_cols = [c for c in required_cols if c in col_map]
            
            if len(found_cols) == 3:
                structure_score += 10
                feedback_parts.append(f"✅ Required columns found ({len(col_map)}/6 total)")
            else:
                structure_score += 5
                feedback_parts.append(f"⚠️ Only {len(found_cols)}/3 core columns found")
        
        # Check for section separators (Totals, Beneficiary, Distribution, etc.)
        section_keywords = ['total', 'beneficiary', 'beneficiaries', 'distribution', 'summary', 'share']
        section_found = False
        for row in data:
            row_text = ' '.join([str(v).lower() if v else '' for v in row])
            if any(kw in row_text for kw in section_keywords):
                section_found = True
                break
        
        if section_found:
            structure_score += 5
            feedback_parts.append("✅ Totals/summary section present")
        else:
            feedback_parts.append("❌ No clear totals/summary section")
        
        score += structure_score
        
        # === CRITERION 2: Data Completeness (15 points) ===
        completeness_score = 0
        
        # Original 9 items that should be present
        original_items = [
            'bank of america checking',
            ['house', 'maple'],
            ['honda', 'cr-v', 'crv'],
            'jewelry',
            'bank of america savings',
            ['fidelity', 'ira'],
            'life insurance',
            'china cabinet',
            'credit card'
        ]
        
        all_text = ' '.join([str(val).lower() if val else '' for row in data for val in row])
        
        found_items = 0
        for item in original_items:
            if isinstance(item, list):
                if any(keyword in all_text for keyword in item):
                    found_items += 1
            else:
                if item in all_text:
                    found_items += 1
        
        completeness_score += min(9, found_items)
        if found_items == 9:
            feedback_parts.append("✅ All 9 original items present")
        else:
            feedback_parts.append(f"⚠️ {found_items}/9 original items found")
        
        # Check for categories and verification status
        has_categories = 'category' in col_map or any(
            cat in all_text for cat in ['real property', 'vehicle', 'financial account', 'personal property']
        )
        has_status = 'status' in col_map or any(
            status in all_text for status in ['confirmed', 'estimated', 'pending', 'verified']
        )
        
        if has_categories:
            completeness_score += 3
            feedback_parts.append("✅ Category information present")
        else:
            feedback_parts.append("❌ No category classification")
        
        if has_status:
            completeness_score += 3
            feedback_parts.append("✅ Verification status tracked")
        else:
            feedback_parts.append("❌ No verification status")
        
        score += completeness_score
        
        # === CRITERION 3: Calculation Accuracy (30 points) ===
        calc_score = 0
        
        # Extract all numeric values from the sheet
        all_numbers = []
        for row in data:
            for val in row:
                if isinstance(val, (int, float)) and val != 0:
                    all_numbers.append(val)
        
        # Check for house net value: $385,000 - $180,000 = $205,000
        house_net_found = any(abs(n - 205000) < 1500 for n in all_numbers)
        if house_net_found:
            calc_score += 5
            feedback_parts.append("✅ House net value correct (~$205,000)")
        else:
            feedback_parts.append("❌ House net value incorrect or missing")
        
        # Check for Honda net value: $16,500 - $4,200 = $12,300
        car_net_found = any(abs(n - 12300) < 500 for n in all_numbers)
        if car_net_found:
            calc_score += 5
            feedback_parts.append("✅ Honda net value correct (~$12,300)")
        else:
            feedback_parts.append("❌ Honda net value incorrect or missing")
        
        # Total gross assets should be around $631,520
        # (12450 + 385000 + 16500 + 8200 + 34670 + 127300 + 50000 + 1200 + 3800 = 639120)
        # Note: Credit card is debt, so excluding it: 635320
        gross_total_found = any(630000 < n < 640000 for n in all_numbers)
        if gross_total_found:
            calc_score += 5
            feedback_parts.append("✅ Total gross assets calculated")
        else:
            feedback_parts.append("⚠️ Total gross assets missing or incorrect")
        
        # Total liens/debts: $180,000 (mortgage) + $4,200 (car) + $3,800 (CC) = $188,000
        liens_total_found = any(185000 < n < 191000 for n in all_numbers)
        if liens_total_found:
            calc_score += 5
            feedback_parts.append("✅ Total liens/debts calculated")
        else:
            feedback_parts.append("⚠️ Total liens/debts missing or incorrect")
        
        # Net estate value: approximately $635,320 - $188,000 = $447,320
        # (can vary based on methodology, accepting range $440k-$450k)
        net_estate_found = False
        net_estate_value = 0
        for n in all_numbers:
            if 438000 < n < 450000:
                net_estate_found = True
                net_estate_value = n
                break
        
        if net_estate_found:
            calc_score += 5
            feedback_parts.append(f"✅ Net estate value calculated (~${net_estate_value:,.0f})")
        else:
            feedback_parts.append("⚠️ Net estate value missing or incorrect")
        
        # Per-beneficiary share: Net estate / 4
        if net_estate_found:
            expected_share = net_estate_value / 4
            share_found = any(abs(n - expected_share) < 2000 for n in all_numbers)
            if share_found:
                calc_score += 5
                feedback_parts.append(f"✅ Per-beneficiary share calculated (~${expected_share:,.0f})")
            else:
                calc_score += 2
                feedback_parts.append("⚠️ Per-beneficiary share missing or incorrect")
        else:
            # Look for any value around $110k (approximate share)
            if any(108000 < n < 114000 for n in all_numbers):
                calc_score += 3
                feedback_parts.append("⚠️ Per-beneficiary share present but may not use correct formula")
        
        # Check if "4" (number of beneficiaries) appears in the sheet
        if 4 in all_numbers or '4' in all_text:
            calc_score += 5
            feedback_parts.append("✅ Number of beneficiaries (4) specified")
        else:
            feedback_parts.append("⚠️ Number of beneficiaries not clearly stated")
        
        score += calc_score
        
        # === CRITERION 4: Formula Usage (20 points) ===
        formula_score = 0
        
        # Check for formulas in cells
        formula_count = 0
        sum_formula_count = 0
        subtraction_formula_count = 0
        division_formula_count = 0
        cell_reference_count = 0
        
        for row in ws.iter_rows(min_row=1, max_row=100):
            for cell in row:
                if cell.value and isinstance(cell.value, str):
                    cell_str = str(cell.value)
                    if cell_str.startswith('='):
                        formula_count += 1
                        cell_upper = cell_str.upper()
                        if 'SUM' in cell_upper:
                            sum_formula_count += 1
                        if '-' in cell_str:
                            subtraction_formula_count += 1
                        if '/' in cell_str:
                            division_formula_count += 1
                        # Check for cell references (letters followed by numbers)
                        if re.search(r'[A-Z]+\d+', cell_upper):
                            cell_reference_count += 1
        
        # Award points for net value formulas (subtraction)
        if subtraction_formula_count >= 2:
            formula_score += 5
            feedback_parts.append(f"✅ Net value formulas detected ({subtraction_formula_count} subtraction formulas)")
        elif subtraction_formula_count >= 1:
            formula_score += 3
            feedback_parts.append(f"⚠️ Some net value formulas found")
        else:
            feedback_parts.append("❌ No subtraction formulas for net values")
        
        # Award points for SUM formulas in totals
        if sum_formula_count >= 2:
            formula_score += 5
            feedback_parts.append(f"✅ SUM formulas used for totals ({sum_formula_count} found)")
        elif sum_formula_count >= 1:
            formula_score += 3
            feedback_parts.append(f"⚠️ Some SUM formulas present")
        else:
            feedback_parts.append("❌ No SUM formulas for totals")
        
        # Award points for division formula (beneficiary shares)
        if division_formula_count >= 1:
            formula_score += 5
            feedback_parts.append("✅ Division formula for beneficiary shares")
        else:
            feedback_parts.append("❌ No division formula for shares")
        
        # Overall formula usage
        if formula_count >= 8:
            formula_score += 5
            feedback_parts.append(f"✅ Comprehensive formula usage ({formula_count} total)")
        elif formula_count >= 5:
            formula_score += 3
            feedback_parts.append(f"⚠️ Moderate formula usage ({formula_count} total)")
        elif formula_count >= 3:
            formula_score += 1
            feedback_parts.append(f"⚠️ Limited formula usage ({formula_count} total)")
        else:
            feedback_parts.append("❌ Minimal or no formula usage - values may be hardcoded")
        
        score += formula_score
        
        # === CRITERION 5: Professional Formatting (15 points) ===
        formatting_score = 0
        
        # Check for negative values or debt tracking
        has_negative_debt = any(isinstance(v, (int, float)) and v < 0 for row in data for v in row)
        debt_keywords = ['debt', 'owed', 'liability', 'balance due', 'loan']
        has_debt_tracking = any(keyword in all_text for keyword in debt_keywords)
        
        if has_negative_debt or has_debt_tracking:
            formatting_score += 3
            feedback_parts.append("✅ Debts/liens clearly tracked")
        else:
            feedback_parts.append("⚠️ Debt handling unclear")
        
        # Check for totals section distinction
        if section_found:
            formatting_score += 4
            feedback_parts.append("✅ Totals section visually distinct")
        else:
            formatting_score += 1
        
        # Check for lien amounts tracked per asset
        lien_per_asset = False
        for row in data:
            row_text = ' '.join([str(v).lower() if v else '' for v in row])
            row_numbers = [v for v in row if isinstance(v, (int, float)) and v > 0]
            # Check if row mentions house/honda and has lien amount
            if ('house' in row_text or 'maple' in row_text) and any(175000 < n < 185000 for n in row_numbers):
                lien_per_asset = True
            if ('honda' in row_text or 'cr-v' in row_text) and any(4000 < n < 4500 for n in row_numbers):
                lien_per_asset = True
        
        if lien_per_asset or 'lien' in col_map:
            formatting_score += 4
            feedback_parts.append("✅ Liens tracked per asset")
        else:
            formatting_score += 1
            feedback_parts.append("⚠️ Liens not clearly tracked per asset")
        
        # Overall professional appearance
        # Based on having good structure, headers, and organization
        if structure_score >= 15 and has_headers:
            formatting_score += 4
            feedback_parts.append("✅ Professional overall appearance")
        elif structure_score >= 10:
            formatting_score += 2
            feedback_parts.append("⚠️ Acceptable organization, could improve")
        else:
            feedback_parts.append("⚠️ Poor organization/formatting")
        
        score += formatting_score
        
        # === FINAL ASSESSMENT ===
        passed = score >= 70
        
        # Create comprehensive feedback
        feedback = f"Score: {score}/100 | " + " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": float(score),
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
