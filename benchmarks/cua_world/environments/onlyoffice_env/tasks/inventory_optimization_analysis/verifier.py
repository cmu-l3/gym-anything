#!/usr/bin/env python3
"""
Verifier for Distribution Center Inventory Optimization Analysis task.

Evaluates the target Excel workbook for proper supply-chain analytics structure:
1. ABC Classification implementation
2. Inventory turnover ratio calculation
3. Dead stock identification
4. Reorder point & safety stock calculation
5. Summary dashboard / statistics
6. Professional spreadsheet architecture

Pass threshold: 5.0 / 10.0 points.
"""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_all_text(wb):
    """Extract all text from all cells in all sheets."""
    all_text = []
    for sheet_name in wb.sheetnames:
        sheet = wb[sheet_name]
        for row in sheet.iter_rows(max_row=min(sheet.max_row, 1000),
                                    max_col=min(sheet.max_column, 50)):
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
                                    max_col=min(sheet.max_column, 50)):
            for cell in row:
                if isinstance(cell.value, (int, float)) and cell.value != 0:
                    numbers.append(cell.value)
    return numbers


def verify_inventory_optimization(traj, env_info, task_info):
    """
    Verify inventory optimization analysis.
    
    Scoring Criteria (10 points total):
    1. ABC classification logic present (2.0 pts)
    2. Inventory turnover formulas/values (2.0 pts)
    3. Dead stock identification (1.5 pts)
    4. Reorder Point / Safety Stock calculations (2.0 pts)
    5. Summary metrics/Dashboard (1.5 pts)
    6. Multi-sheet structure (1.0 pt)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    # Anti-gaming file timestamp check
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/inventory_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
        os.unlink(temp_result.name)
        
        if not result_meta.get("output_exists", False):
            return {"passed": False, "score": 0.0, "feedback": "Output workbook was not saved."}
        if not result_meta.get("file_created_during_task", True):
            return {"passed": False, "score": 0.0, "feedback": "Anti-gaming failure: File existed before task started."}
    except Exception as e:
        logger.warning(f"Could not read metadata JSON: {e}")

    container_path = "/home/ga/Documents/Spreadsheets/inventory_optimization.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_inventory_')

    try:
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load inventory_optimization.xlsx: {error}"
            }

        feedback_parts = []
        score = 0.0

        all_text = extract_all_text(wb)
        all_numbers = extract_all_numbers(wb)
        num_sheets = len(wb.sheetnames)

        # Count total populated cells
        total_cells = 0
        for sn in wb.sheetnames:
            sheet = wb[sn]
            for row in sheet.iter_rows(max_row=min(sheet.max_row, 1000),
                                        max_col=min(sheet.max_column, 50)):
                for cell in row:
                    if cell.value is not None:
                        total_cells += 1

        # Wrong-Target Gate
        if total_cells < 50:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Wrong-target gate: File has insufficient content (< 50 cells populated)"
            }

        # CHECK 1: ABC Classification (2.0 pts)
        abc_terms = ["abc", "class a", "class b", "class c", "pareto", "80/20", "revenue rank"]
        has_abc_text = any(t in all_text for t in abc_terms)
        
        a_class_counts = [n for n in all_numbers if 15 <= n <= 50]
        has_abc_numbers = len(a_class_counts) > 0
        
        if has_abc_text and has_abc_numbers:
            score += 2.0
            feedback_parts.append("ABC Classification present (2.0/2.0)")
        elif has_abc_text:
            score += 1.0
            feedback_parts.append("ABC Classification partially present (1.0/2.0)")

        # CHECK 2: Inventory Turnover (2.0 pts)
        turnover_terms = ["turnover", "turns", "cogs", "avg inventory", "average inventory"]
        has_turnover = sum(1 for t in turnover_terms if t in all_text) >= 2
        
        # Look for values that might represent turn ratios (typically 1-30)
        turnover_vals = [n for n in all_numbers if isinstance(n, float) and 1.0 <= n <= 30.0]
        
        if has_turnover and len(turnover_vals) >= 3:
            score += 2.0
            feedback_parts.append("Inventory Turnover analyzed (2.0/2.0)")
        elif has_turnover:
            score += 1.0
            feedback_parts.append("Inventory Turnover mentioned but values unclear (1.0/2.0)")

        # CHECK 3: Dead/Slow Stock Identification (1.5 pts)
        dead_terms = ["dead", "slow", "obsolete", "no movement", "90 day", "90-day", "last ship"]
        has_dead_text = any(t in all_text for t in dead_terms)
        
        if has_dead_text:
            score += 1.5
            feedback_parts.append("Dead/Slow stock identified (1.5/1.5)")

        # CHECK 4: Reorder Point & Safety Stock (2.0 pts)
        rop_terms = ["reorder point", "rop", "safety stock", "ss", "lead time", "z score", "z-score", "1.65"]
        rop_term_count = sum(1 for t in rop_terms if t in all_text)
        
        if rop_term_count >= 3:
            score += 2.0
            feedback_parts.append("Reorder Point & Safety Stock computed (2.0/2.0)")
        elif rop_term_count >= 1:
            score += 1.0
            feedback_parts.append("Reorder Point/Safety Stock partially present (1.0/2.0)")

        # CHECK 5: Summary Metrics & Dashboard (1.5 pts)
        summary_terms = ["total revenue", "total items", "summary", "dashboard", "metrics"]
        has_summary = any(t in all_text for t in summary_terms)
        
        # Expecting to see large revenue aggregations (1M - 5M range)
        large_revenues = [n for n in all_numbers if 500000 <= n <= 5000000]
        
        if has_summary and len(large_revenues) >= 1:
            score += 1.5
            feedback_parts.append("Summary metrics/dashboard created (1.5/1.5)")
        elif has_summary or len(large_revenues) >= 1:
            score += 0.5
            feedback_parts.append("Summary metrics weak or partial (0.5/1.5)")

        # CHECK 6: Professional Structure (1.0 pt)
        if num_sheets >= 3:
            score += 1.0
            feedback_parts.append(f"Professional structure ({num_sheets} sheets) (1.0/1.0)")
        elif num_sheets == 2:
            score += 0.5
            feedback_parts.append("Adequate structure (2 sheets) (0.5/1.0)")

        passed = score >= 5.0

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Error during verification: {e}"
        }
    finally:
        cleanup_temp_dir(temp_dir)