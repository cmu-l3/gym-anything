#!/usr/bin/env python3
"""
Verifier for Intermittent Appliance Diagnosis task
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
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_intermittent_appliance_diagnosis(traj, env_info, task_info):
    """
    Verify the washing machine diagnostic spreadsheet.

    Checks:
    1. Sheet 1 "Incident Log" - structured data with required columns
    2. Sheet 2 "Pattern Analysis" - frequency analysis and statistics
    3. Sheet 3 "Technician Summary" - one-page report for technician
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/washer_notes_raw.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_washer_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Could not open washer_notes_raw.xlsx: {error}"
            }

        feedback_parts = []
        score = 0.0
        
        # Get all sheet names
        sheet_names = wb.sheetnames
        logger.info(f"Found sheets: {sheet_names}")

        # =====================================================================
        # Check Sheet 1: Incident Log
        # =====================================================================
        sheet1_name = None
        for name in sheet_names:
            name_lower = name.lower()
            if "incident" in name_lower and "log" in name_lower:
                sheet1_name = name
                break
        
        if not sheet1_name:
            # Try alternative names
            for name in sheet_names:
                name_lower = name.lower()
                if "incident" in name_lower or "log" in name_lower or "structured" in name_lower:
                    sheet1_name = name
                    break
        
        if not sheet1_name:
            feedback_parts.append("❌ Missing 'Incident Log' sheet")
        else:
            sheet1 = wb[sheet1_name]
            data = get_sheet_data(wb, sheet1_name, max_rows=50, max_cols=15)
            
            if not data or len(data) < 2:
                feedback_parts.append("❌ Incident Log sheet is empty")
            else:
                # Count non-empty data rows (excluding header)
                non_empty_rows = 0
                for row in data[1:]:
                    if any(cell is not None and str(cell).strip() != "" for cell in row):
                        non_empty_rows += 1
                
                logger.info(f"Incident Log has {non_empty_rows} data rows")
                
                # Check row count
                if non_empty_rows < 10:
                    feedback_parts.append(f"❌ Incident Log has only {non_empty_rows} incidents, expected at least 10")
                elif non_empty_rows > 25:
                    feedback_parts.append(f"⚠️ Incident Log has {non_empty_rows} rows - should filter out 'ran fine' entries")
                    score += 0.15
                else:
                    feedback_parts.append(f"✅ Incident Log has {non_empty_rows} incidents (good filtering)")
                    score += 0.25
                
                # Check for required columns (case-insensitive header search)
                headers = []
                if data:
                    for cell in data[0]:
                        if cell is not None:
                            headers.append(str(cell).lower())
                        else:
                            headers.append("")
                
                logger.info(f"Headers found: {headers}")
                
                # Check for "Days Since Last Incident" column
                has_days_between = False
                days_col_idx = -1
                for i, h in enumerate(headers):
                    if ("days" in h and ("since" in h or "between" in h or "last" in h)) or \
                       ("time" in h and ("since" in h or "between" in h)):
                        has_days_between = True
                        days_col_idx = i
                        break
                
                if has_days_between:
                    feedback_parts.append("✅ Has 'Days Since Last Incident' column")
                    score += 0.15
                    
                    # Check if column has numeric values (indicating calculation)
                    has_numeric_values = False
                    numeric_count = 0
                    for row_idx in range(1, min(15, len(data))):
                        if row_idx < len(data) and days_col_idx < len(data[row_idx]):
                            cell_value = data[row_idx][days_col_idx]
                            if cell_value is not None and isinstance(cell_value, (int, float)):
                                has_numeric_values = True
                                numeric_count += 1
                    
                    if numeric_count >= 3:
                        feedback_parts.append(f"✅ 'Days Since' column has calculated values ({numeric_count} numeric entries)")
                        score += 0.10
                    else:
                        feedback_parts.append("⚠️ 'Days Since' column appears empty or not calculated")
                else:
                    feedback_parts.append("❌ Missing 'Days Since Last Incident' column")
                
                # Check for "Problem Category" or similar
                has_category = False
                for h in headers:
                    if ("category" in h or "problem" in h or "type" in h or "issue" in h) and \
                       ("problem" in h or "category" in h or "type" in h):
                        has_category = True
                        break
                
                if has_category:
                    feedback_parts.append("✅ Has 'Problem Category' column")
                    score += 0.10
                else:
                    feedback_parts.append("❌ Missing 'Problem Category' column")
                
                # Check for "Severity" column
                has_severity = False
                for h in headers:
                    if "severity" in h or "priority" in h or "level" in h:
                        has_severity = True
                        break
                
                if has_severity:
                    feedback_parts.append("✅ Has 'Severity' column")
                    score += 0.10
                else:
                    feedback_parts.append("❌ Missing 'Severity' column")
                
                # Check that "ran fine" entries are excluded
                ran_fine_count = 0
                for row in data[1:]:
                    for cell in row:
                        if cell is not None:
                            cell_text = str(cell).lower()
                            if ("ran fine" in cell_text or "worked fine" in cell_text or 
                                "made it through" in cell_text or "fine all week" in cell_text):
                                ran_fine_count += 1
                                break
                
                if ran_fine_count > 3:
                    feedback_parts.append(f"⚠️ Found {ran_fine_count} 'ran fine' entries - should filter these out")
                else:
                    feedback_parts.append("✅ Correctly filtered out 'ran fine' entries")
                    score += 0.05

        # =====================================================================
        # Check Sheet 2: Pattern Analysis
        # =====================================================================
        sheet2_name = None
        for name in sheet_names:
            name_lower = name.lower()
            if "pattern" in name_lower or "analysis" in name_lower:
                sheet2_name = name
                break
        
        if not sheet2_name:
            feedback_parts.append("❌ Missing 'Pattern Analysis' sheet")
        else:
            data2 = get_sheet_data(wb, sheet2_name, max_rows=100, max_cols=15)
            
            # Combine all text from the sheet
            all_text = []
            for row in data2:
                for cell in row:
                    if cell is not None:
                        all_text.append(str(cell))
            
            all_text_combined = " ".join(all_text).lower()
            logger.info(f"Pattern Analysis text length: {len(all_text_combined)} characters")
            
            # Check for frequency analysis
            has_frequency = ("frequency" in all_text_combined or "count" in all_text_combined) and \
                          ("problem" in all_text_combined or "category" in all_text_combined or "issue" in all_text_combined)
            
            if has_frequency:
                feedback_parts.append("✅ Contains frequency/count analysis")
                score += 0.10
            else:
                feedback_parts.append("❌ Missing frequency analysis table")
            
            # Check for average days calculation
            has_average = ("average" in all_text_combined and "days" in all_text_combined) or \
                         ("avg" in all_text_combined and "days" in all_text_combined) or \
                         ("mean" in all_text_combined and "days" in all_text_combined)
            
            if has_average:
                feedback_parts.append("✅ Contains average days calculation")
                score += 0.10
            else:
                feedback_parts.append("⚠️ Missing average days between incidents")
            
            # Check for pattern observations section
            has_patterns_section = ("pattern" in all_text_combined and 
                                   ("investigate" in all_text_combined or "observation" in all_text_combined or 
                                    "finding" in all_text_combined or "note" in all_text_combined))
            
            # Count substantive words (more than 2 characters, not numbers)
            words = all_text_combined.split()
            substantive_words = [w for w in words if len(w) > 2 and not w.isdigit()]
            word_count = len(substantive_words)
            
            logger.info(f"Pattern Analysis word count: {word_count}")
            
            if has_patterns_section and word_count >= 30:
                feedback_parts.append(f"✅ Contains pattern observations section with analysis ({word_count} words)")
                score += 0.10
            elif word_count >= 20:
                feedback_parts.append(f"⚠️ Has some analysis but missing clear pattern observations section ({word_count} words)")
                score += 0.05
            else:
                feedback_parts.append(f"❌ Pattern observations section insufficient ({word_count} words, need 30+)")

        # =====================================================================
        # Check Sheet 3: Technician Summary
        # =====================================================================
        sheet3_name = None
        for name in sheet_names:
            name_lower = name.lower()
            if "technician" in name_lower or "summary" in name_lower or "report" in name_lower:
                sheet3_name = name
                break
        
        if not sheet3_name:
            feedback_parts.append("❌ Missing 'Technician Summary' sheet")
        else:
            data3 = get_sheet_data(wb, sheet3_name, max_rows=100, max_cols=15)
            
            # Combine all text from the sheet
            all_text = []
            for row in data3:
                for cell in row:
                    if cell is not None:
                        all_text.append(str(cell))
            
            all_text_combined = " ".join(all_text).lower()
            logger.info(f"Technician Summary text length: {len(all_text_combined)} characters")
            
            # Check for proper title
            has_title = (("washing" in all_text_combined or "washer" in all_text_combined) and 
                        ("issue" in all_text_combined or "problem" in all_text_combined or 
                         "report" in all_text_combined or "diagnostic" in all_text_combined))
            
            if has_title:
                feedback_parts.append("✅ Has proper report title")
                score += 0.05
            else:
                feedback_parts.append("❌ Missing clear report title (should mention washing machine)")
            
            # Count substantive words
            words = all_text_combined.split()
            substantive_words = [w for w in words if len(w) > 2 and not w.isdigit()]
            word_count = len(substantive_words)
            
            logger.info(f"Technician Summary word count: {word_count}")
            
            if word_count >= 50:
                feedback_parts.append(f"✅ Technician summary has substantial content ({word_count} words)")
                score += 0.10
            elif word_count >= 30:
                feedback_parts.append(f"⚠️ Technician summary is brief ({word_count} words, recommended 50+)")
                score += 0.05
            else:
                feedback_parts.append(f"❌ Technician summary too brief ({word_count} words, need 50+)")
            
            # Check for observations/findings (look for multiple distinct points)
            # Count sentences or bullet point indicators
            sentence_markers = all_text_combined.count('.') + all_text_combined.count('\n') + \
                             all_text_combined.count('•') + all_text_combined.count('-') + \
                             all_text_combined.count('*')
            
            # Also look for keywords indicating observations
            has_observations = ("frequent" in all_text_combined or "common" in all_text_combined or 
                              "most" in all_text_combined or "pattern" in all_text_combined or
                              "observation" in all_text_combined or "finding" in all_text_combined)
            
            if sentence_markers >= 5 and has_observations:
                feedback_parts.append("✅ Contains multiple observations/bullet points")
                score += 0.05
            elif has_observations:
                feedback_parts.append("⚠️ Has observations but formatting could be clearer")
                score += 0.02
            else:
                feedback_parts.append("⚠️ Should have at least 3 distinct observations about patterns")

        # =====================================================================
        # Cross-sheet validation
        # =====================================================================
        sheets_created = sum([sheet1_name is not None, sheet2_name is not None, sheet3_name is not None])
        
        if sheets_created == 3:
            feedback_parts.append("✅ All 3 required sheets present")
            score += 0.05
        elif sheets_created == 2:
            feedback_parts.append("⚠️ Only 2 of 3 required sheets present")
        else:
            feedback_parts.append("❌ Missing multiple required sheets")

        # =====================================================================
        # Final scoring
        # =====================================================================
        passed = score >= 0.7
        feedback = " | ".join(feedback_parts)
        
        logger.info(f"Final score: {score:.2f}, Passed: {passed}")
        
        return {
            "passed": passed,
            "score": round(score, 2),
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)