#!/usr/bin/env python3
"""
Verifier for Solar Farm Performance Analysis task.

Evaluates the agent's ability to compute solar KPIs and identify physical anomalies
from raw hourly generation data (capacity factor, performance ratio, degradation).

Scoring (10.0 points total, pass threshold 5.0):
1. Wrong-target gate: file exists with sufficient content (0 if not)
2. Energy production summaries (daily or monthly, 4+ arrays) (2.0 pts)
3. Capacity factor calculation (15-28%, 3+ arrays) (1.5 pts)
4. Performance ratio or specific yield calculated (1.5 pts)
5. Underperformer identification (INV-004) (2.0 pts)
6. Outage detection (INV-002, days 35-39) (1.5 pts)
7. Professional structure & terminology (1.5 pts)
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_all_text(wb):
    all_text = []
    for sheet_name in wb.sheetnames:
        sheet = wb[sheet_name]
        for row in sheet.iter_rows(max_row=min(sheet.max_row, 500),
                                    max_col=min(sheet.max_column, 30)):
            for cell in row:
                if cell.value is not None:
                    all_text.append(str(cell.value).lower())
    return " ".join(all_text)

def extract_all_numbers(wb):
    numbers = []
    for sn in wb.sheetnames:
        sheet = wb[sn]
        for row in sheet.iter_rows(max_row=min(sheet.max_row, 500),
                                    max_col=min(sheet.max_column, 30)):
            for cell in row:
                if isinstance(cell.value, (int, float)) and cell.value != 0:
                    numbers.append(cell.value)
    return numbers

def verify_solar_performance(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/solar_performance_report.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_solar_')

    try:
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Wrong-target gate: Failed to load solar_performance_report.xlsx: {error}"
            }

        feedback_parts = []
        score = 0.0

        all_text = extract_all_text(wb)
        all_numbers = extract_all_numbers(wb)
        
        # Check cells
        total_cells = 0
        for sn in wb.sheetnames:
            sheet = wb[sn]
            for row in sheet.iter_rows(max_row=min(sheet.max_row, 500),
                                        max_col=min(sheet.max_column, 30)):
                for cell in row:
                    if cell.value is not None:
                        total_cells += 1

        if total_cells < 20:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Wrong-target gate: File has insufficient content"
            }

        # 1. Energy production summaries (2.0 pts)
        has_energy_units = "mwh" in all_text or "kwh" in all_text or "energy" in all_text or "production" in all_text
        energy_values = [n for n in all_numbers if 1500 <= n <= 3500 or 1500000 <= n <= 3500000 or 250 <= n <= 600]
        if has_energy_units and len(energy_values) >= 2:
            score += 2.0
            feedback_parts.append("Energy production summaries present (+2.0)")
        elif has_energy_units:
            score += 1.0
            feedback_parts.append("Partial energy production summaries (+1.0)")
            
        # 2. Capacity factor calculation (1.5 pts)
        has_cf_term = "capacity factor" in all_text or "cf" in all_text
        cf_values = [n for n in all_numbers if (0.15 <= n <= 0.28) or (15 <= n <= 28)]
        if has_cf_term and len(cf_values) >= 3:
            score += 1.5
            feedback_parts.append("Capacity factor calculated (+1.5)")
        elif has_cf_term or len(cf_values) >= 1:
            score += 0.5
            feedback_parts.append("Partial capacity factor analysis (+0.5)")

        # 3. Performance ratio or specific yield (1.5 pts)
        has_pr_term = "performance ratio" in all_text or "pr" in all_text or "specific yield" in all_text or "yield" in all_text
        pr_values = [n for n in all_numbers if (0.60 <= n <= 0.90) or (60 <= n <= 90) or (300 <= n <= 500)]
        if has_pr_term and len(pr_values) >= 1:
            score += 1.5
            feedback_parts.append("Performance ratio/yield calculated (+1.5)")
        elif has_pr_term:
            score += 0.5
            feedback_parts.append("Partial performance ratio mentioned (+0.5)")

        # 4. Underperformer identification (INV-004) (2.0 pts)
        has_inv4 = "inv-004" in all_text or "inv004" in all_text or "array 4" in all_text
        has_degraded = "degrad" in all_text or "underperform" in all_text or "low" in all_text or "deficit" in all_text or "issue" in all_text
        if has_inv4 and has_degraded:
            score += 2.0
            feedback_parts.append("INV-004 identified as underperformer (+2.0)")
        elif has_inv4:
            score += 1.0
            feedback_parts.append("INV-004 mentioned (+1.0)")

        # 5. Outage detection (INV-002, days 35-39) (1.5 pts)
        has_inv2 = "inv-002" in all_text or "inv002" in all_text or "array 2" in all_text
        has_outage = "outage" in all_text or "zero" in all_text or "offline" in all_text or "down" in all_text or "missing" in all_text
        if has_inv2 and has_outage:
            score += 1.5
            feedback_parts.append("INV-002 outage identified (+1.5)")
        elif has_inv2:
            score += 0.5
            feedback_parts.append("INV-002 mentioned (+0.5)")

        # 6. Professional structure & terminology (1.5 pts)
        industry_terms = ["irradiance", "nameplate", "kwp", "poa", "module", "ambient", "inverter", "sma"]
        term_count = sum(1 for term in industry_terms if term in all_text)
        
        if len(wb.sheetnames) >= 2 and term_count >= 3:
            score += 1.5
            feedback_parts.append("Professional structure and terminology (+1.5)")
        elif len(wb.sheetnames) >= 2 or term_count >= 2:
            score += 0.5
            feedback_parts.append("Basic structure/terminology (+0.5)")

        passed = score >= 5.0
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Error during verification: {str(e)}")
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Error during verification: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)