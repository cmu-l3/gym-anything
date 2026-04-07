#!/usr/bin/env python3
"""
Verifier for table_sort_formula task.

Verifies:
1. File exists and was modified during the task.
2. Table data rows are sorted alphabetically by Category.
3. Total row contains 'SUM(ABOVE)' formulas.
4. Total row values are correct.
5. Total row is Bold.
"""

import json
import os
import re
import tempfile
import zipfile
import logging
from xml.etree import ElementTree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Namespace map for parsing Word XML
NS = {
    'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
}

def verify_table_sort_formula(traj, env_info, task_info):
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_order = metadata.get('expected_sort_order', [])
    expected_totals = metadata.get('expected_totals', {})

    score = 0
    feedback = []
    
    # Create temp directory for artifacts
    with tempfile.TemporaryDirectory() as tmp_dir:
        result_json_path = os.path.join(tmp_dir, "task_result.json")
        docx_path = os.path.join(tmp_dir, "quarterly_expenses.docx")

        # 2. Get Result JSON
        try:
            copy_from_env("C:\\Users\\Docker\\task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        if not result_data.get("output_exists"):
            return {"passed": False, "score": 0, "feedback": "Document 'quarterly_expenses.docx' not found."}
            
        if not result_data.get("file_created_during_task"):
            # If checking strict timestamps is tricky due to clock skew, we can rely on content
            feedback.append("Warning: File timestamp suggests no modification (or clock skew).")
        else:
            score += 10
            feedback.append("File modified during task (+10).")

        # 3. Get Document Content
        try:
            copy_from_env(result_data.get("output_path", "C:\\Users\\Docker\\Documents\\quarterly_expenses.docx"), docx_path)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to retrieve document: {str(e)}"}

        # 4. Parse Document XML
        try:
            with zipfile.ZipFile(docx_path) as zf:
                xml_content = zf.read('word/document.xml')
                tree = ElementTree.fromstring(xml_content)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Invalid DOCX file structure: {str(e)}"}

        # Find the first table
        table = tree.find('.//w:tbl', NS)
        if table is None:
            return {"passed": False, "score": score, "feedback": "No table found in document."}

        rows = table.findall('w:tr', NS)
        if len(rows) < 12:
            return {"passed": False, "score": score, "feedback": f"Table has insufficient rows ({len(rows)}), expected 12."}

        # --- Check 1: Sort Order (30 pts) ---
        # Rows 1 to 10 (indices 1 to 10, skipping header at 0 and total at 11)
        data_rows = rows[1:11] 
        extracted_categories = []
        
        for row in data_rows:
            cells = row.findall('w:tc', NS)
            if cells:
                # Extract text from first cell
                texts = cells[0].findall('.//w:t', NS)
                cell_text = "".join([t.text for t in texts if t.text]).strip()
                extracted_categories.append(cell_text)

        # Calculate sort score
        correct_positions = 0
        for i, category in enumerate(extracted_categories):
            if i < len(expected_order) and category == expected_order[i]:
                correct_positions += 1
        
        # 3 points per correct row
        sort_score = correct_positions * 3
        score += sort_score
        feedback.append(f"Sort Order: {correct_positions}/10 rows correct (+{sort_score}).")

        # --- Check 2: Total Row Formatting (Bold) (10 pts) ---
        total_row = rows[11]
        total_cells = total_row.findall('w:tc', NS)
        
        # Check if cells have bold property
        # Bold can be in paragraph properties (w:pPr) or run properties (w:rPr)
        bold_found = False
        bold_tags = total_row.findall('.//w:b', NS)
        # Often <w:b/> is enough evidence, assuming they didn't toggle it off <w:b w:val="0"/>
        valid_bolds = [b for b in bold_tags if b.get(f'{{{NS["w"]}}}val') != '0']
        
        if len(valid_bolds) >= 4: # Crude check: at least some bold tags present
            score += 10
            feedback.append("Total row formatting appears Bold (+10).")
        else:
            feedback.append("Total row missing Bold formatting.")

        # --- Check 3 & 4: Formulas and Values (50 pts total) ---
        # Columns 1 to 4 in the total row (indices 1-4, as 0 is label)
        # Expected totals map keys are col_2 to col_5
        
        formula_count = 0
        value_match_count = 0
        
        # We need to check cols 1, 2, 3, 4 (0-indexed in list implies 2nd to 5th column)
        target_cols = [1, 2, 3, 4] 
        
        for i, col_idx in enumerate(target_cols):
            if col_idx >= len(total_cells):
                break
                
            cell = total_cells[col_idx]
            xml_str = ElementTree.tostring(cell, encoding='unicode')
            
            # Check for Formula Field
            # Look for instrText containing "SUM(ABOVE)" or fldSimple with same
            has_formula = "SUM(ABOVE)" in xml_str.upper()
            if has_formula:
                formula_count += 1
            
            # Check Value
            # Extract all text and look for the expected number
            cell_text = "".join([t.text for t in cell.findall('.//w:t', NS) if t.text]).strip()
            
            # Get expected value for this column
            expected_key = f"col_{col_idx+1}"
            expected_val_str = expected_totals.get(expected_key, "0")
            
            # Normalize for comparison (remove commas, handle float diffs)
            try:
                val_float = float(cell_text.replace(',', ''))
                exp_float = float(expected_val_str.replace(',', ''))
                if abs(val_float - exp_float) < 1.0:
                    value_match_count += 1
            except ValueError:
                pass # Text parsing failed

        # Scoring Formulas (25 pts)
        # Need at least 3 formulas for full credit, scaled
        if formula_count >= 4:
            score += 25
            feedback.append("All SUM formulas present (+25).")
        elif formula_count >= 1:
            partial = formula_count * 6
            score += partial
            feedback.append(f"Found {formula_count} SUM formulas (+{partial}).")
        else:
            feedback.append("No SUM formulas found in Total row.")

        # Scoring Values (25 pts)
        if value_match_count >= 4:
            score += 25
            feedback.append("All Total values correct (+25).")
        elif value_match_count >= 1:
            partial = value_match_count * 6
            score += partial
            feedback.append(f"Found {value_match_count} correct total values (+{partial}).")
        else:
            feedback.append("Total values incorrect or missing.")

    # Final Pass/Fail
    # Pass threshold 60, but requires reasonable sorting (>=20 pts which is 7 rows)
    passed = (score >= 60) and (sort_score >= 20)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }