#!/usr/bin/env python3
"""
Verifier for Compost Diagnosis task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compost_diagnosis(traj, env_info, task_info):
    """
    Verify that compost troubleshooting spreadsheet was created correctly.

    Checks:
    1. File exists and is parseable (10%)
    2. Has structured headers (Date, Material, Category columns) (20%)
    3. Has sufficient data entries (at least 12 entries) (20%)
    4. Materials are correctly categorized as Green or Brown (25%)
    5. Formula present for ratio calculation (15%)
    6. Problem diagnosis is present (10%)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/compost_notes.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_compost_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

        score = 0
        max_score = 100
        feedback_parts = []

        # Try to find the main sheet
        sheet_name = wb.sheetnames[0] if wb.sheetnames else None
        if not sheet_name:
            return {"passed": False, "score": 0, "feedback": "No sheets found in workbook"}

        # Get all data from the sheet
        data = get_sheet_data(wb, sheet_name, max_rows=100, max_cols=20)

        if not data or len(data) == 0:
            return {"passed": False, "score": 0, "feedback": "Spreadsheet is empty"}

        # Check 1: File exists and parseable (10 points)
        score += 10
        feedback_parts.append("✅ Spreadsheet file created and readable")

        # Check 2: Find header row with required columns (20 points)
        header_row_idx = None
        headers = []
        
        # Look for header row in first 15 rows
        for idx, row in enumerate(data[:15]):
            row_text = ' '.join([str(cell).lower() if cell else '' for cell in row])
            # Check if this looks like a header row with relevant keywords
            keyword_count = sum([
                'date' in row_text,
                'material' in row_text or 'item' in row_text,
                'category' in row_text or 'type' in row_text,
                'green' in row_text or 'brown' in row_text,
                'volume' in row_text or 'amount' in row_text
            ])
            
            if keyword_count >= 3:  # At least 3 relevant keywords
                header_row_idx = idx
                headers = [str(cell).lower() if cell else '' for cell in row]
                break

        if header_row_idx is not None:
            has_date = any('date' in h for h in headers)
            has_material = any('material' in h or 'item' in h for h in headers)
            has_category = any('category' in h or 'type' in h or 'green' in h or 'brown' in h for h in headers)
            
            header_score = 0
            if has_date:
                header_score += 7
            if has_material:
                header_score += 7
            if has_category:
                header_score += 6
            
            score += header_score
            if header_score >= 15:
                feedback_parts.append(f"✅ Good header structure ({header_score}/20 points)")
            else:
                feedback_parts.append(f"⚠️ Incomplete headers ({header_score}/20 points)")
        else:
            feedback_parts.append("❌ No clear header row found")

        # Check 3: Sufficient data entries (20 points)
        if header_row_idx is not None:
            data_rows = data[header_row_idx + 1:]
        else:
            # Try to find data rows anyway - skip first few rows that might be titles
            data_rows = data[3:] if len(data) > 3 else data

        # Filter out empty rows and rows that look like instructions
        actual_data_rows = []
        for row in data_rows:
            if not any(cell for cell in row):
                continue
            row_text = ' '.join([str(cell).lower() if cell else '' for cell in row])
            # Skip instruction/title rows
            if any(skip_word in row_text for skip_word in ['task:', 'instruction', 'organize', 'rough notes', 'needs organization']):
                continue
            actual_data_rows.append(row)

        num_entries = len(actual_data_rows)

        if num_entries >= 15:
            score += 20
            feedback_parts.append(f"✅ Excellent data entry: {num_entries} entries")
        elif num_entries >= 12:
            score += 16
            feedback_parts.append(f"✅ Good data entry: {num_entries} entries")
        elif num_entries >= 8:
            score += 12
            feedback_parts.append(f"⚠️ Minimal data entry: {num_entries} entries")
        elif num_entries >= 5:
            score += 8
            feedback_parts.append(f"⚠️ Insufficient data: only {num_entries} entries")
        else:
            feedback_parts.append(f"❌ Very few entries: only {num_entries} entries")

        # Check 4: Categorization accuracy (25 points)
        category_col_idx = None
        material_col_idx = None

        if header_row_idx is not None and headers:
            for idx, h in enumerate(headers):
                if 'category' in h or 'type' in h:
                    category_col_idx = idx
                if 'material' in h or 'item' in h:
                    material_col_idx = idx

        if category_col_idx is not None:
            categories = []
            materials = []

            for row in actual_data_rows:
                if category_col_idx < len(row):
                    cat = str(row[category_col_idx]).lower() if row[category_col_idx] else ''
                    categories.append(cat)

                if material_col_idx is not None and material_col_idx < len(row):
                    mat = str(row[material_col_idx]).lower() if row[material_col_idx] else ''
                    materials.append(mat)

            # Check if both categories are present
            has_greens = any('green' in c or 'nitrogen' in c for c in categories)
            has_browns = any('brown' in c or 'carbon' in c for c in categories)

            if has_greens and has_browns:
                score += 10
                feedback_parts.append("✅ Both green and brown categories present")

                # Check accuracy of categorization
                green_keywords = ['kitchen', 'coffee', 'grass', 'fruit', 'vegetable', 'veggie', 'scraps', 
                                 'weed', 'clipping', 'banana', 'apple', 'orange', 'cucumber', 'salad', 
                                 'tea', 'peel', 'core', 'dinner']
                brown_keywords = ['leaves', 'leaf', 'paper', 'cardboard', 'wood', 'straw', 'sawdust', 
                                 'newspaper', 'dry']

                correct_cats = 0
                total_checked = 0

                for mat, cat in zip(materials, categories):
                    mat_lower = mat.lower()
                    is_green_material = any(gm in mat_lower for gm in green_keywords)
                    is_brown_material = any(bm in mat_lower for bm in brown_keywords)
                    
                    if is_green_material:
                        total_checked += 1
                        if 'green' in cat or 'nitrogen' in cat:
                            correct_cats += 1
                    elif is_brown_material:
                        total_checked += 1
                        if 'brown' in cat or 'carbon' in cat:
                            correct_cats += 1

                if total_checked > 0:
                    accuracy = correct_cats / total_checked
                    if accuracy >= 0.8:
                        score += 15
                        feedback_parts.append(f"✅ Accurate categorization: {correct_cats}/{total_checked} correct")
                    elif accuracy >= 0.6:
                        score += 10
                        feedback_parts.append(f"⚠️ Some categorization errors: {correct_cats}/{total_checked}")
                    else:
                        score += 5
                        feedback_parts.append(f"❌ Poor categorization accuracy: {correct_cats}/{total_checked}")
                else:
                    score += 5
                    feedback_parts.append("⚠️ Could not verify categorization accuracy")
            else:
                score += 5
                feedback_parts.append("⚠️ Missing one or both categories (green/brown)")
        else:
            feedback_parts.append("❌ No category column found")

        # Check 5: Formula presence (15 points)
        has_formula = False
        formula_count = 0

        # Check the actual sheet object for formulas
        sheet = wb[sheet_name]
        for row in sheet.iter_rows():
            for cell in row:
                if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                    has_formula = True
                    formula_count += 1

        # Also look for numeric results that could be ratios
        all_numeric_values = []
        for row in data:
            for cell in row:
                if cell is not None and isinstance(cell, (int, float)):
                    all_numeric_values.append(cell)

        # Check for ratio-like values (between 0.1 and 10)
        ratio_values = [v for v in all_numeric_values if 0.1 <= v <= 10]

        if has_formula or formula_count > 0:
            score += 15
            feedback_parts.append(f"✅ Formula present ({formula_count} formulas found)")
        elif len(ratio_values) > 0:
            score += 10
            feedback_parts.append(f"⚠️ No explicit formula detected, but ratio-like values found")
        else:
            score += 5
            feedback_parts.append("⚠️ No clear formula or calculation detected")

        # Check 6: Problem diagnosis (10 points)
        all_text = []
        for row in data:
            for cell in row:
                if cell:
                    all_text.append(str(cell).lower())

        all_text_combined = ' '.join(all_text)

        diagnosis_keywords = [
            'too many green', 'too much green', 'not enough brown',
            'excess green', 'imbalance', 'add brown', 'add leaves',
            'add paper', 'add cardboard', 'need brown', 'need more brown',
            'greens outnumber', 'too few brown', 'ratio', 'problem'
        ]

        diagnosis_count = sum(1 for keyword in diagnosis_keywords if keyword in all_text_combined)

        if diagnosis_count >= 2:
            score += 10
            feedback_parts.append("✅ Problem diagnosis or recommendation present")
        elif diagnosis_count >= 1:
            score += 5
            feedback_parts.append("⚠️ Some diagnostic text found")
        else:
            feedback_parts.append("⚠️ No clear diagnosis or recommendation found")

        # Final assessment
        passed = score >= 70
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)