#!/usr/bin/env python3
"""Verifier for movie_roi_analysis task."""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_spreadsheet,
    cleanup_verification_temp
)
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_movie_roi_analysis(traj, env_info, task_info):
    """Verify movie ROI analysis workbook creation and formatting."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # ================================================================
    # 1. Read the export_result.json
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not export_data.get("file_exists", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file 'Movie_ROI_Analysis.xlsx' was not found. Agent must save the file exactly as specified."
        }

    # ================================================================
    # 2. Parse the spreadsheet
    # ================================================================
    success, wb, error, temp_dir = copy_and_parse_spreadsheet(
        "/home/ga/Documents/Movie_ROI_Analysis.xlsx", copy_from_env, file_format='xlsx'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse XLSX file: {error}"}

    try:
        score = 0
        feedback_parts = []
        
        # Anti-gaming: Ensure file was created during the task
        if export_data.get("file_created_during_task", False):
            score += 10
            feedback_parts.append("File properly saved as XLSX (10/10)")
        else:
            feedback_parts.append("File timestamp violation (0/10)")

        # Identify sheets
        sheets = wb.sheetnames
        main_sheet_name = sheets[0] # Assuming first sheet is the main data
        summary_sheet_name = None
        for s in sheets:
            if "summary" in s.lower() or "genre" in s.lower():
                summary_sheet_name = s
                break

        main_sheet = wb[main_sheet_name]
        
        # ================================================================
        # 3. Structural & Formatting Checks
        # ================================================================
        # Check Top Row Frozen
        is_frozen = False
        if hasattr(main_sheet, 'views') and main_sheet.views and main_sheet.views.sheetView:
            pane = main_sheet.views.sheetView[0].pane
            if pane and getattr(pane, 'ySplit', 0) > 0:
                is_frozen = True
                
        # Check Bold Headers
        has_bold_headers = False
        for cell in main_sheet[1]:
            if cell.font and cell.font.bold:
                has_bold_headers = True
                break
                
        if is_frozen and has_bold_headers:
            score += 10
            feedback_parts.append("Formatting applied (Frozen+Bold) (10/10)")
        elif is_frozen or has_bold_headers:
            score += 5
            feedback_parts.append("Partial formatting applied (5/10)")
        else:
            feedback_parts.append("Formatting not found (0/10)")

        # ================================================================
        # 4. Formula Checks (Profit, ROI, Runtime_Category)
        # ================================================================
        has_profit = False
        has_roi = False
        has_roi_error_handling = False
        has_runtime_nested_if = False
        
        expected_cats = ["Short", "Feature", "Epic", "Unknown"]

        for row in main_sheet.iter_rows(min_row=2, max_row=10):
            for cell in row:
                if cell.value and isinstance(cell.value, str) and cell.value.startswith('='):
                    formula = cell.value.upper()
                    
                    # Profit: usually subtraction e.g., =D2-C2
                    if '-' in formula and not 'IF' in formula:
                        has_profit = True
                        
                    # ROI: Division + Error handling
                    if '/' in formula and ('IFERROR' in formula or 'IF(' in formula):
                        has_roi = True
                        if 'IFERROR' in formula or '""' in formula or 'BLANK' in formula:
                            has_roi_error_handling = True
                            
                    # Runtime Category: Nested IFs
                    if 'IF(' in formula and any(cat.upper() in formula for cat in expected_cats):
                        matched_cats = sum(1 for cat in expected_cats if f'"{cat.upper()}"' in formula)
                        if matched_cats >= 2: # At least two categories handled in the formula
                            has_runtime_nested_if = True

        if has_profit:
            score += 10
            feedback_parts.append("Profit formula correct (10/10)")
            
        if has_roi and has_roi_error_handling:
            score += 15
            feedback_parts.append("ROI formula with error handling correct (15/15)")
        elif has_roi:
            score += 5
            feedback_parts.append("ROI formula lacks error handling (5/15)")
            
        if has_runtime_nested_if:
            score += 15
            feedback_parts.append("Runtime nested IF logic correct (15/15)")
            
        # ================================================================
        # 5. Summary Sheet Checks
        # ================================================================
        has_averageif = False
        has_percentage = False
        has_currency = False
        
        if summary_sheet_name:
            summary_sheet = wb[summary_sheet_name]
            # Check formulas and formatting
            for row in summary_sheet.iter_rows():
                for cell in row:
                    # Check formulas
                    if cell.value and isinstance(cell.value, str):
                        formula = cell.value.upper()
                        if 'AVERAGEIF' in formula:
                            has_averageif = True
                    # Check formatting
                    if cell.number_format:
                        fmt = str(cell.number_format).upper()
                        if '%' in fmt or 'PERCENTAGE' in fmt:
                            has_percentage = True
                        if '$' in fmt or 'CURRENCY' in fmt or '\"$\"' in fmt:
                            has_currency = True

            if has_averageif:
                score += 20
                feedback_parts.append("Genre summary aggregation successful (20/20)")
            else:
                feedback_parts.append("Genre summary missing AVERAGEIF formulas (0/20)")
                
            if has_percentage and has_currency:
                score += 10
                feedback_parts.append("Number formats applied (10/10)")
            elif has_percentage or has_currency:
                score += 5
                feedback_parts.append("Partial number formats applied (5/10)")
                
        else:
            feedback_parts.append("Genre_Summary sheet not found (0/30)")

        # ================================================================
        # 6. Chart Verification via VLM (Trajectory Frames)
        # ================================================================
        chart_score = 0
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images_to_check = frames + ([final_frame] if final_frame else [])
            
            prompt = """
            Analyze these screenshots of a WPS Spreadsheet workflow.
            Answer in JSON format:
            {
                "created_chart": true/false,
                "chart_is_bar_or_column": true/false
            }
            Did the user successfully create a Bar or Column chart to visualize the summary data?
            """
            vlm_result = query_vlm(prompt=prompt, images=images_to_check)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("created_chart") and parsed.get("chart_is_bar_or_column"):
                    chart_score = 10
                    feedback_parts.append("Chart visualization confirmed via VLM (10/10)")
                elif parsed.get("created_chart"):
                    chart_score = 5
                    feedback_parts.append("Chart created but type unspecified/wrong via VLM (5/10)")
                else:
                    # Fallback to programmatic check
                    if summary_sheet_name and len(wb[summary_sheet_name]._charts) > 0:
                        chart_score = 10
                        feedback_parts.append("Chart detected programmatically (10/10)")
                    else:
                        feedback_parts.append("Chart not detected (0/10)")
        else:
            # Fallback if VLM is unavailable
            if summary_sheet_name and len(wb[summary_sheet_name]._charts) > 0:
                chart_score = 10
                feedback_parts.append("Chart detected programmatically (10/10)")
            
        score += chart_score

        # ================================================================
        # Final Score Evaluation
        # ================================================================
        # Check critical pass conditions
        passed = score >= 70 and has_averageif and has_roi_error_handling

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)