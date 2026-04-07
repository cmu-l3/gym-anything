#!/usr/bin/env python3
"""
Verifier for the Public Library Collection Turnover task.

Programmatically evaluates:
1. Valid file presence (anti-gaming via creation timestamps).
2. ~10,000 records imported successfully.
3. Complex conditional logic accuracy (Circulation Rate and Weeding criteria).
4. Cross-sheet aggregation via COUNTIF and averages.
5. VLM trajectory fallback to verify GUI usage.
"""

import sys
import os
import json
import logging
import tempfile

# Pathing assumes onlyoffice_verification_utils is present in the container/host path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_library_turnover(traj, env_info, task_info):
    """
    Scoring Breakdown (10 points total):
      - 1.0: Wrong-target gate (file exists, created during task, basic content)
      - 1.5: Data Imported (>9500 rows present)
      - 2.0: Circulation Rate calculation verified mathematically across sampled rows
      - 2.0: Weed logic (IF/AND) verified conditionally across sampled rows
      - 2.0: Summary KPIs accurate (Total items, checkouts, weeds, avg circ)
      - 1.5: Item Breakdown correct (COUNTIF aggregations)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/library_collection_analysis.xlsx"
    
    # 1. Retrieve metadata / results
    result_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/task_result.json", result_temp.name)
        with open(result_temp.name, 'r') as f:
            export_meta = json.load(f)
            
        copy_from_env("/tmp/ground_truth.json", gt_temp.name)
        with open(gt_temp.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to retrieve metadata: {e}"}
    finally:
        if os.path.exists(result_temp.name): os.unlink(result_temp.name)
        if os.path.exists(gt_temp.name): os.unlink(gt_temp.name)

    # Verify anti-gaming
    if not export_meta.get("output_file_exists", False):
        return {"passed": False, "score": 0.0, "feedback": "Output file was not found."}
    
    if not export_meta.get("file_created_during_task", False):
        return {"passed": False, "score": 0.0, "feedback": "Output file existed prior to task execution (anti-gaming trigger)."}

    # 2. Parse the spreadsheet
    success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')
    if not success:
        return {"passed": False, "score": 0.0, "feedback": f"Failed to load spreadsheet: {error}"}

    feedback_parts = []
    score = 0.0

    # Count overall content density to prevent completely sparse submissions
    total_cells = sum(1 for sn in wb.sheetnames for row in wb[sn].iter_rows(max_col=30) for cell in row if cell.value is not None)
    if total_cells < 50:
        return {"passed": False, "score": 0.0, "feedback": "Wrong-target gate: File has insufficient content"}

    score += 1.0
    feedback_parts.append("Valid file created with content (1.0/1.0)")

    # 3. Identify sheets (robust indexing based on size rather than strict naming)
    data_sheet = None
    summary_sheet = None
    
    for sn in wb.sheetnames:
        row_count = wb[sn].max_row
        if row_count > 5000:
            data_sheet = wb[sn]
        elif 0 < row_count < 5000:
            summary_sheet = wb[sn]

    if not data_sheet:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | Catalog data sheet missing or truncated."}

    data_rows = data_sheet.max_row
    data_imported = False
    if data_rows >= 9500:
        score += 1.5
        data_imported = True
        feedback_parts.append("Dataset successfully imported (1.5/1.5)")

    # 4. Verify Calculations row-by-row (Sampling rows 2-100 to check logic)
    weed_correct = 0
    circ_correct = 0
    rows_checked = 0

    headers = [str(c.value).lower().strip() if c.value else "" for c in data_sheet[1]]
    
    # Try dynamic column resolution; fallback to rigid indices
    try:
        type_idx = headers.index("itemtype")
        year_idx = headers.index("publicationyear")
        chk_idx = headers.index("checkoutcount_ytd")
        days_idx = headers.index("daysincatalog")
    except ValueError:
        type_idx, year_idx, chk_idx, days_idx = 4, 3, 6, 7

    for row in data_sheet.iter_rows(min_row=2, max_row=100, max_col=30):
        vals = [c.value for c in row]
        if len(vals) <= max(type_idx, year_idx, chk_idx, days_idx): continue

        i_type = str(vals[type_idx])
        try: i_year = int(vals[year_idx])
        except: continue
        try: i_chk = int(vals[chk_idx])
        except: continue
        try: i_days = int(vals[days_idx])
        except: continue

        # Ground truth logic calculation
        expected_weed = (i_type == "Book" and i_year < 2014 and i_chk < 2)
        expected_circ = i_chk / (i_days / 365.0)

        row_strs = [str(v).lower().strip() for v in vals if v is not None]
        row_nums = [v for v in vals if isinstance(v, (int, float))]

        weed_str = "yes" if expected_weed else "no"
        if weed_str in row_strs or str(int(expected_weed)) in row_strs:
            weed_correct += 1

        for n in row_nums:
            if abs(n - expected_circ) < 0.05:
                circ_correct += 1
                break

        rows_checked += 1

    if rows_checked > 0:
        if circ_correct / rows_checked > 0.6:
            score += 2.0
            feedback_parts.append("Circulation Rate formula logic verified (2.0/2.0)")
        if weed_correct / rows_checked > 0.6:
            score += 2.0
            feedback_parts.append("Weed Candidate IF/AND logic verified (2.0/2.0)")

    # 5. Verify Summary Sheet Aggregations
    if summary_sheet:
        summary_nums = []
        for row in summary_sheet.iter_rows(max_row=100, max_col=20):
            for cell in row:
                if isinstance(cell.value, (int, float)):
                    summary_nums.append(cell.value)

        # Global KPIs
        kpi_points = 0.0
        if any(abs(n - gt['total_items']) < 1 for n in summary_nums):
            kpi_points += 0.5
        if any(abs(n - gt['total_checkouts']) < 1 for n in summary_nums):
            kpi_points += 0.5
        if any(abs(n - gt['total_weed']) < 1 for n in summary_nums):
            kpi_points += 0.5
        if any(abs(n - gt['avg_circ_rate']) < 0.1 for n in summary_nums):
            kpi_points += 0.5

        if kpi_points > 0:
            score += kpi_points
            feedback_parts.append(f"Summary KPIs found ({kpi_points:.1f}/2.0)")

        # Item Type Breakdowns
        type_points = 0.0
        for t, count in gt['type_counts'].items():
            if any(abs(n - count) < 1 for n in summary_nums):
                type_points += (1.5 / 4.0)

        if type_points > 0:
            score += type_points
            feedback_parts.append(f"Type breakdown counts found ({type_points:.1f}/1.5)")
    else:
        feedback_parts.append("Collection_Summary sheet missing or empty.")

    # VLM Trajectory Check - Did they actually use the GUI?
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """You are verifying if a computer agent used a Spreadsheet GUI (like ONLYOFFICE).
Look at these sequence of screenshots. Did the agent actively interact with the spreadsheet application UI to import data, edit cells, or write formulas?
Respond in JSON format:
{
    "spreadsheet_gui_used": true/false
}
"""
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get('parsed', {}).get('spreadsheet_gui_used'):
                feedback_parts.append("VLM visual verification confirmed GUI usage.")
            else:
                feedback_parts.append("VLM visual verification could not confirm GUI usage.")
    except Exception as e:
        logger.warning(f"VLM verification skipped or failed: {e}")

    # Final logic
    key_criteria_met = (total_cells >= 50 and data_imported)
    passed = (score >= 5.0) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }