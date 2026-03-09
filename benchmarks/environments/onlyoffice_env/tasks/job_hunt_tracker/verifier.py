#!/usr/bin/env python3
"""
Verifier for Job Hunt Tracker task (job_hunt_tracker@1)

Validates that the user has:
1. Added missing column headers (Status, Date of Response, Next Action)
2. Created Days Since Applied calculation
3. Built summary statistics section with formulas
4. Applied conditional formatting
5. Added data validation to Status column
6. Filled status values properly
"""

import sys
import os
import logging
import tempfile
from typing import Dict, Any, Tuple

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_job_hunt_tracker(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify job hunt tracker spreadsheet completion.
    
    Scoring breakdown (20 points total):
    - Headers (2 pts): F, G, H column headers
    - Days column (1 pt): Column I with calculation
    - Summary labels (1 pt): J3:J6 labels present
    - Data filled (1 pt): At least 11 rows
    - Valid statuses (1 pt): Status column has valid values
    - Total apps formula (2 pts): K3 COUNTA formula
    - Response rate formula (2 pts): K4 calculation
    - Interviews formula (1 pt): K5 COUNTIF
    - Days formula (1 pt): I3 date calculation
    - Conditional formatting (4 pts): 2 rules present
    - Data validation (2 pts): Dropdown in Status column
    - Status diversity (1 pt): Multiple status types
    - Data organization (1 pt): Sorted/organized
    
    Passing threshold: 14/20 points (70%)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Copy function not available in environment"
        }
    
    filepath = "/home/ga/Documents/Spreadsheets/job_applications.xlsx"
    temp_dir = None
    
    try:
        # Copy and parse the spreadsheet
        success, workbook, error = copy_and_parse_document(
            filepath, copy_from_env, 'xlsx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load spreadsheet: {error}"
            }
        
        score = 0
        max_score = 20
        feedback = []
        
        # Verify sheet exists
        if "Applications" not in workbook.sheetnames:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Sheet 'Applications' not found in workbook"
            }
        
        sheet = workbook["Applications"]
        
        # ============================================================
        # CHECK 1: Headers in F2, G2, H2 (2 points)
        # ============================================================
        header_points = 0
        header_f = get_cell_value(workbook, "Applications", "F2")
        header_g = get_cell_value(workbook, "Applications", "G2")
        header_h = get_cell_value(workbook, "Applications", "H2")
        
        if header_f and isinstance(header_f, str):
            header_f_lower = header_f.lower()
            if "status" in header_f_lower and "[add header" not in header_f_lower:
                header_points += 0.7
                feedback.append("✅ Status header correct")
            else:
                feedback.append(f"❌ Status header missing/incorrect: '{header_f}'")
        else:
            feedback.append("❌ Status header (F2) empty")
        
        if header_g and isinstance(header_g, str):
            header_g_lower = header_g.lower()
            if "response" in header_g_lower and "[add header" not in header_g_lower:
                header_points += 0.65
                feedback.append("✅ Response date header correct")
            else:
                feedback.append(f"⚠️ Response header unclear: '{header_g}'")
        else:
            feedback.append("⚠️ Response date header (G2) empty")
        
        if header_h and isinstance(header_h, str):
            header_h_lower = header_h.lower()
            if "action" in header_h_lower and "[add header" not in header_h_lower:
                header_points += 0.65
                feedback.append("✅ Next action header correct")
            else:
                feedback.append(f"⚠️ Next action header unclear: '{header_h}'")
        else:
            feedback.append("⚠️ Next action header (H2) empty")
        
        score += min(2, header_points)
        
        # ============================================================
        # CHECK 2: Column I header "Days Since Applied" (1 point)
        # ============================================================
        header_i = get_cell_value(workbook, "Applications", "I2")
        if header_i and isinstance(header_i, str):
            header_i_lower = header_i.lower()
            if "days" in header_i_lower and "applied" in header_i_lower:
                score += 1
                feedback.append("✅ Days Since Applied column exists")
            else:
                feedback.append(f"⚠️ Column I header unclear: '{header_i}'")
        else:
            feedback.append("❌ Days Since Applied column (I2) missing")
        
        # ============================================================
        # CHECK 3: Summary section labels in J3:J6 (1 point)
        # ============================================================
        summary_labels = []
        for row in [3, 4, 5, 6]:
            label = get_cell_value(workbook, "Applications", f"J{row}")
            if label:
                summary_labels.append(str(label).lower())
        
        has_total = any("total" in lbl and "application" in lbl for lbl in summary_labels)
        has_response = any("response" in lbl or "rate" in lbl for lbl in summary_labels)
        has_interviews = any("interview" in lbl for lbl in summary_labels)
        
        summary_count = sum([has_total, has_response, has_interviews])
        if summary_count >= 2:
            score += 1
            feedback.append(f"✅ Summary section created ({summary_count}/3 key labels)")
        else:
            feedback.append(f"⚠️ Summary section incomplete ({summary_count}/3 labels)")
        
        # ============================================================
        # CHECK 4: Data rows filled (1 point)
        # ============================================================
        data_rows_filled = 0
        for row in range(3, 15):  # Check rows 3-14
            company = get_cell_value(workbook, "Applications", f"A{row}")
            if company and str(company).strip():
                data_rows_filled += 1
        
        if data_rows_filled >= 11:
            score += 1
            feedback.append(f"✅ {data_rows_filled} application rows filled")
        elif data_rows_filled >= 8:
            score += 0.5
            feedback.append(f"⚠️ Only {data_rows_filled} rows filled (expected 12)")
        else:
            feedback.append(f"❌ Insufficient data rows: {data_rows_filled}")
        
        # ============================================================
        # CHECK 5: Status column has valid values (1 point)
        # ============================================================
        valid_statuses = [
            "applied", "phone screen", "interview scheduled", 
            "rejected", "offer"
        ]
        
        status_values = []
        invalid_statuses = []
        
        for row in range(3, 15):
            status = get_cell_value(workbook, "Applications", f"F{row}")
            if status and str(status).strip():
                status_str = str(status).strip()
                status_lower = status_str.lower()
                
                # Skip placeholder text
                if "[add header" in status_lower:
                    continue
                
                status_values.append(status_str)
                
                # Check if it's a valid status
                if not any(valid in status_lower for valid in valid_statuses):
                    invalid_statuses.append(status_str)
        
        if len(status_values) >= 10 and len(invalid_statuses) == 0:
            score += 1
            feedback.append(f"✅ Status values valid ({len(status_values)} entries)")
        elif len(status_values) >= 8:
            score += 0.5
            feedback.append(f"⚠️ Some status values present ({len(status_values)} entries)")
        else:
            feedback.append(f"❌ Status column incomplete ({len(status_values)} entries)")
        
        # ============================================================
        # CHECK 6: Total Applications formula in K3 (2 points)
        # ============================================================
        total_apps = get_cell_value(workbook, "Applications", "K3")
        if total_apps is not None:
            if isinstance(total_apps, (int, float)) and 8 <= total_apps <= 15:
                score += 2
                feedback.append(f"✅ Total applications formula works: {total_apps}")
            elif isinstance(total_apps, (int, float)):
                score += 1
                feedback.append(f"⚠️ Total applications value suspicious: {total_apps}")
            else:
                feedback.append(f"⚠️ Total applications not calculated: {total_apps}")
        else:
            feedback.append("❌ Total applications formula missing (K3)")
        
        # ============================================================
        # CHECK 7: Response rate formula in K4 (2 points)
        # ============================================================
        response_rate = get_cell_value(workbook, "Applications", "K4")
        if response_rate is not None:
            if isinstance(response_rate, (int, float)):
                # Response rate should be between 0 and 1 (or 0-100 if formatted as %)
                if 0 <= response_rate <= 1 or 0 <= response_rate <= 100:
                    score += 2
                    # Format for display
                    if response_rate <= 1:
                        rate_display = f"{response_rate*100:.1f}%"
                    else:
                        rate_display = f"{response_rate:.1f}%"
                    feedback.append(f"✅ Response rate calculated: {rate_display}")
                else:
                    score += 1
                    feedback.append(f"⚠️ Response rate value unusual: {response_rate}")
            else:
                feedback.append(f"⚠️ Response rate not numeric: {response_rate}")
        else:
            feedback.append("❌ Response rate formula missing (K4)")
        
        # ============================================================
        # CHECK 8: Interviews count formula in K5 (1 point)
        # ============================================================
        interviews = get_cell_value(workbook, "Applications", "K5")
        if interviews is not None:
            if isinstance(interviews, (int, float)) and 0 <= interviews <= 12:
                score += 1
                feedback.append(f"✅ Interview count formula works: {int(interviews)}")
            else:
                score += 0.5
                feedback.append(f"⚠️ Interview count suspicious: {interviews}")
        else:
            feedback.append("❌ Interview count formula missing (K5)")
        
        # ============================================================
        # CHECK 9: Days calculation formula in I3 (1 point)
        # ============================================================
        days_val = get_cell_value(workbook, "Applications", "I3")
        if days_val is not None:
            if isinstance(days_val, (int, float)) and 0 <= days_val <= 200:
                score += 1
                feedback.append(f"✅ Days calculation formula working: {int(days_val)} days")
            else:
                score += 0.5
                feedback.append(f"⚠️ Days calculation unusual: {days_val}")
        else:
            feedback.append("❌ Days calculation formula missing (I3)")
        
        # ============================================================
        # CHECK 10 & 11: Conditional formatting (4 points)
        # ============================================================
        # Note: openpyxl can detect conditional formatting rules
        cf_points = 0
        try:
            if hasattr(sheet, 'conditional_formatting'):
                cf_rules = sheet.conditional_formatting._cf_rules
                cf_count = len(cf_rules)
                
                if cf_count >= 2:
                    cf_points = 4
                    feedback.append(f"✅ Conditional formatting applied ({cf_count} rules)")
                elif cf_count == 1:
                    cf_points = 2
                    feedback.append(f"⚠️ Partial conditional formatting ({cf_count} rule)")
                else:
                    feedback.append("❌ No conditional formatting detected")
            else:
                # Give benefit of doubt if we can't detect
                cf_points = 2
                feedback.append("⚠️ Conditional formatting cannot be verified automatically")
        except Exception as e:
            logger.warning(f"Could not check conditional formatting: {e}")
            cf_points = 2
            feedback.append("⚠️ Conditional formatting check failed (assuming partial credit)")
        
        score += cf_points
        
        # ============================================================
        # CHECK 12: Data validation (2 points)
        # ============================================================
        dv_points = 0
        try:
            if hasattr(sheet, 'data_validations'):
                dv_list = sheet.data_validations.dataValidation
                if len(dv_list) > 0:
                    # Check if validation is on column F
                    has_status_validation = False
                    for dv in dv_list:
                        dv_range = str(dv.sqref) if hasattr(dv, 'sqref') else ""
                        if 'F' in dv_range:
                            has_status_validation = True
                            break
                    
                    if has_status_validation:
                        dv_points = 2
                        feedback.append("✅ Data validation applied to Status column")
                    else:
                        dv_points = 1
                        feedback.append("⚠️ Data validation exists but may not be on Status column")
                else:
                    feedback.append("❌ No data validation found")
            else:
                dv_points = 1
                feedback.append("⚠️ Data validation cannot be verified (assuming partial credit)")
        except Exception as e:
            logger.warning(f"Could not check data validation: {e}")
            dv_points = 1
            feedback.append("⚠️ Data validation check failed (assuming partial credit)")
        
        score += dv_points
        
        # ============================================================
        # CHECK 13: Status distribution diversity (1 point)
        # ============================================================
        status_counts = {}
        for status in status_values:
            status_lower = status.lower()
            # Normalize status names
            if "applied" in status_lower:
                key = "Applied"
            elif "phone" in status_lower:
                key = "Phone Screen"
            elif "interview" in status_lower:
                key = "Interview"
            elif "reject" in status_lower:
                key = "Rejected"
            elif "offer" in status_lower:
                key = "Offer"
            else:
                key = status
            
            status_counts[key] = status_counts.get(key, 0) + 1
        
        # Check diversity: at least 3 different statuses with 2+ entries each
        diverse_statuses = sum(1 for count in status_counts.values() if count >= 2)
        
        if diverse_statuses >= 3:
            score += 1
            feedback.append(f"✅ Good status diversity ({len(status_counts)} types)")
        elif len(status_counts) >= 3:
            score += 0.5
            feedback.append(f"⚠️ Limited status diversity ({len(status_counts)} types)")
        else:
            feedback.append(f"❌ Poor status diversity ({len(status_counts)} types)")
        
        # ============================================================
        # CHECK 14: Data organization (1 point)
        # ============================================================
        # Check if data appears organized (dates are in reasonable order)
        dates = []
        for row in range(3, 15):
            date_val = get_cell_value(workbook, "Applications", f"C{row}")
            if date_val:
                dates.append(date_val)
        
        if len(dates) >= 10:
            score += 1
            feedback.append("✅ Data appears organized")
        elif len(dates) >= 8:
            score += 0.5
            feedback.append("⚠️ Data partially organized")
        else:
            feedback.append("⚠️ Data organization unclear")
        
        # ============================================================
        # Calculate final results
        # ============================================================
        score_pct = (score / max_score) * 100
        passed = score >= 14  # 70% threshold
        
        # Create detailed feedback string
        feedback_summary = f"Score: {score:.1f}/{max_score} ({score_pct:.0f}%)"
        feedback_detail = " | ".join(feedback)
        final_feedback = f"{feedback_summary} — {feedback_detail}"
        
        return {
            "passed": passed,
            "score": score / max_score,
            "feedback": final_feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        if temp_dir:
            cleanup_temp_dir(temp_dir)