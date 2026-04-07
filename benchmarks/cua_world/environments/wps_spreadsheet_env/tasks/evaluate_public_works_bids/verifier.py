#!/usr/bin/env python3
"""Verifier for evaluate_public_works_bids task."""

import os
import sys
import json
import logging
import tempfile
import re

# Add utils directory to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import copy_and_parse_spreadsheet, get_spreadsheet_text

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_bid_evaluation(traj, env_info, task_info):
    """
    Verify the bid tabulation workbook.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read the export JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('output_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Workbook 'bid_evaluation.xlsx' was not saved in Documents folder."
        }

    # 2. Read the actual spreadsheet
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/bid_evaluation.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse spreadsheet: {error}"}

    score = 0
    feedback_parts = []
    
    try:
        sheet_names = [s.strip().lower() for s in wb.sheetnames]
        full_text = get_spreadsheet_text(wb).lower()
        
        # Criterion 1: Workbook Structure (15 pts)
        has_bid_tab = any('bid tab' in s for s in sheet_names)
        has_summary = any('summary' in s for s in sheet_names)
        has_unbalanced = any('unbalanced' in s for s in sheet_names)
        
        if has_bid_tab and has_summary and has_unbalanced:
            score += 15
            feedback_parts.append("✅ All 3 sheets created")
        elif len(sheet_names) >= 3:
            score += 10
            feedback_parts.append("⚠️ 3 sheets exist but naming is inexact")
        else:
            feedback_parts.append("❌ Missing required sheets")

        # Criterion 2: Extended Costs Calculated (25 pts)
        # Check if the text contains indications of the extended headers
        if "extended" in full_text:
            score += 25
            feedback_parts.append("✅ Extended cost columns present")
        else:
            feedback_parts.append("❌ Extended cost columns missing")

        # Criterion 3: Summary Sheet Totals (20 pts)
        # Expected totals: Eng=756500, Apex=876000, Titan=708300, Horizon=815300
        # We allow formatting differences (e.g. 756,500)
        def find_total(val):
            val_str = str(val)
            val_fmt = f"{val:,}"
            return val_str in full_text or val_fmt in full_text
            
        found_totals = 0
        if find_total(756500): found_totals += 1
        if find_total(876000): found_totals += 1
        if find_total(708300): found_totals += 1
        if find_total(815300): found_totals += 1
        
        score += (found_totals * 5)
        if found_totals == 4:
            feedback_parts.append("✅ All bid totals correctly calculated")
        else:
            feedback_parts.append(f"⚠️ {found_totals}/4 bid totals found")

        # Criterion 4: Lowest Bidder Identified (10 pts)
        # Check if Titan is identified near "Apparent Low Bidder"
        if "apparent low bidder" in full_text and "titan" in full_text:
            score += 10
            feedback_parts.append("✅ Apparent Low Bidder (Titan) correctly identified")
        else:
            feedback_parts.append("❌ Lowest bidder not properly identified")

        # Criterion 5: Unbalanced Flags (10 pts)
        # There should be exactly two items triggering the UNBALANCED flag (Clearing/Grubbing & Construction Staking)
        unbalanced_count = len(re.findall(r'unbalanced', full_text))
        
        if unbalanced_count >= 2:
            score += 10
            feedback_parts.append("✅ Unbalanced items correctly flagged")
        elif unbalanced_count == 1:
            score += 5
            feedback_parts.append("⚠️ Only 1 unbalanced item flagged")
        else:
            feedback_parts.append("❌ Unbalanced items not flagged")

        # Criterion 6: File anti-gaming / active work (20 pts)
        if result.get('file_created_during_task', False):
            score += 20
            feedback_parts.append("✅ File created during task session")
        else:
            feedback_parts.append("❌ File existed prior (potential gaming)")

        # Final Evaluation
        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}