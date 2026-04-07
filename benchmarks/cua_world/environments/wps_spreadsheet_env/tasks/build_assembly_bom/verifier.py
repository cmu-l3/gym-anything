#!/usr/bin/env python3
"""
Verifier for Build Assembly BOM task.

SCORING CRITERIA (100 points total, Pass threshold: 60):
1. Output file exists and was modified during task (15 pts)
2. BOM Detail Sheet: Data rows, formulas in Ext. Cost, sorted by category (30 pts)
3. Summary Sheet: Category totals, Grand total, formatting (30 pts)
4. VLM Trajectory Verification: Confirms authentic spreadsheet usage (25 pts)
"""

import json
import os
import sys
import tempfile
import logging

# Ensure utils directory is accessible
sys.path.insert(0, '/workspace/utils')
try:
    from wps_verification_utils import copy_and_parse_spreadsheet, cleanup_verification_temp
except ImportError:
    logging.warning("wps_verification_utils not found. Using fallback.")

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_assembly_bom(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Read task execution metadata
    # ---------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = export_result.get('output_exists', False)
    modified_during_task = export_result.get('file_modified_during_task', False)

    if output_exists and modified_during_task:
        score += 15
        feedback_parts.append("File exists and was created/modified during task (+15)")
    elif output_exists:
        score += 5
        feedback_parts.append("File exists but timestamp is suspicious (+5)")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file assembly_bom.xlsx not found"}

    # ---------------------------------------------------------
    # 2. Read Ground Truth
    # ---------------------------------------------------------
    temp_truth = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/var/lib/wps_ground_truth/bom_truth.json", temp_truth.name)
        with open(temp_truth.name, 'r') as f:
            truth = json.load(f)
    except Exception as e:
        truth = {}
        logger.error(f"Failed to read ground truth: {e}")
    finally:
        if os.path.exists(temp_truth.name):
            os.unlink(temp_truth.name)

    # ---------------------------------------------------------
    # 3. Parse and Evaluate Spreadsheet
    # ---------------------------------------------------------
    expected_output_path = task_info.get('metadata', {}).get('expected_output_path', '/home/ga/Documents/assembly_bom.xlsx')
    
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        expected_output_path, copy_from_env, file_format='xlsx'
    )

    if success and wb:
        sheet_names = [s.lower() for s in wb.sheetnames]
        
        # Check BOM Detail Sheet
        bom_detail_sheet = None
        for name in wb.sheetnames:
            if 'bom' in name.lower() and 'detail' in name.lower():
                bom_detail_sheet = wb[name]
                break
        if not bom_detail_sheet and 'BOM Detail' in wb.sheetnames:
            bom_detail_sheet = wb['BOM Detail']
        elif not bom_detail_sheet and len(wb.sheetnames) > 0:
            bom_detail_sheet = wb.active # Fallback to active sheet
            
        if bom_detail_sheet:
            data_rows = 0
            formulas_found = 0
            categories = []
            
            # Find columns dynamically based on headers
            headers = [str(c.value).lower().strip() for c in bom_detail_sheet[1] if c.value]
            cat_col = headers.index('category') + 1 if 'category' in headers else None
            ext_col = headers.index('extended_cost') + 1 if 'extended_cost' in headers else None
            
            # Fallbacks if exact headers missing
            if not ext_col:
                for idx, h in enumerate(headers):
                    if 'cost' in h and 'unit' not in h:
                        ext_col = idx + 1
                        
            for row in bom_detail_sheet.iter_rows(min_row=2):
                if any(c.value is not None for c in row):
                    data_rows += 1
                    
                    if cat_col:
                        cat_val = bom_detail_sheet.cell(row=row[0].row, column=cat_col).value
                        if cat_val:
                            categories.append(str(cat_val).strip())
                            
                    if ext_col:
                        cell = bom_detail_sheet.cell(row=row[0].row, column=ext_col)
                        # Openpyxl formulas usually start with '='
                        if isinstance(cell.value, str) and str(cell.value).strip().startswith('='):
                            formulas_found += 1
                        elif cell.data_type == 'f':
                            formulas_found += 1

            # Score BOM Detail
            if abs(data_rows - truth.get('row_count', 51)) <= 3:
                score += 10
                feedback_parts.append("All CSV data imported successfully (+10)")
            else:
                feedback_parts.append(f"Incomplete data import: {data_rows} rows found")
                
            if formulas_found >= (data_rows * 0.8) and data_rows > 0:
                score += 10
                feedback_parts.append("Formulas heavily utilized in Extended Cost (+10)")
            elif formulas_found > 0:
                score += 5
                feedback_parts.append("Some formulas found in Extended Cost (+5)")
                
            if categories and categories == sorted(categories, key=str.lower):
                score += 10
                feedback_parts.append("Data correctly sorted by Category (+10)")
            else:
                feedback_parts.append("Data not sorted alphabetically by Category")
                
        # Check Summary Sheet
        summary_sheet = None
        for name in wb.sheetnames:
            if 'summary' in name.lower():
                summary_sheet = wb[name]
                break
                
        if summary_sheet:
            found_grand_total = False
            found_cat_totals = 0
            expected_grand_total = truth.get('grand_total_cost', 0)
            
            for row in summary_sheet.iter_rows(values_only=False):
                row_vals = [c.value for c in row if c.value is not None]
                row_str = ' '.join(str(v).lower() for v in row_vals)
                
                # Check for Grand Total
                for cell in row:
                    if isinstance(cell.value, (int, float)):
                        if expected_grand_total > 0 and abs(cell.value - expected_grand_total) < 2.0:
                            found_grand_total = True
                            
                # Check for category aggregations
                for cat in truth.get('category_names_sorted', []):
                    if cat.lower() in row_str:
                        for cell in row:
                            if isinstance(cell.value, (int, float)):
                                expected_cat_cost = truth['categories'][cat]['total_cost']
                                if abs(cell.value - expected_cat_cost) < 1.0:
                                    found_cat_totals += 1
                                    break
                                    
            if found_cat_totals >= len(truth.get('category_names_sorted', [])) - 1:
                score += 20
                feedback_parts.append("Category totals aggregated correctly (+20)")
            elif found_cat_totals > 0:
                score += 10
                feedback_parts.append(f"Some category totals aggregated ({found_cat_totals}) (+10)")
                
            if found_grand_total:
                score += 10
                feedback_parts.append("Grand total computed correctly (+10)")
        else:
            feedback_parts.append("Summary sheet not found")
            
        if temp_dir:
            cleanup_verification_temp(temp_dir)
    else:
        feedback_parts.append(f"Spreadsheet parsing failed: {error}")

    # ---------------------------------------------------------
    # 4. VLM Trajectory Verification
    # ---------------------------------------------------------
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """
        Review these screenshots of a computer agent performing a spreadsheet task.
        The task was to import a CSV bill of materials (BOM), create formulas (e.g. Price x Quantity), and create a summary sheet with aggregations.
        
        Answer in JSON format:
        {
            "spreadsheet_app_used": true/false,
            "data_imported": true/false,
            "formulas_typed": true/false,
            "multiple_sheets_visible": true/false
        }
        """
        
        vlm_res = query_vlm(images=frames + [final], prompt=prompt)
        
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("spreadsheet_app_used"):
                score += 5
            if parsed.get("data_imported"):
                score += 5
            if parsed.get("formulas_typed"):
                score += 10
                feedback_parts.append("VLM confirmed active formula usage (+10)")
            if parsed.get("multiple_sheets_visible"):
                score += 5
    else:
        # If VLM is not available, we prorate the score (assuming the file checks pass)
        score = int(score * (100 / 75))
        feedback_parts.append("VLM check skipped - scores prorated")

    # ---------------------------------------------------------
    # Final Evaluation
    # ---------------------------------------------------------
    score = min(100, max(0, score))
    passed = score >= 60 and modified_during_task

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }