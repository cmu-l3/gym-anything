#!/usr/bin/env python3
"""
Verifier for tutor_session_ledger@1

Checks that the tutoring session ledger properly tracks sessions, 
calculates totals, and identifies billing issues.
"""

import sys
import os
import logging
import tempfile
from pathlib import Path

# Add utils to path
sys.path.insert(0, '/workspace/utils')
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    get_sheet_data,
    copy_and_parse_document,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_tutor_session_ledger(traj, env_info, task_info):
    """
    Verify the tutoring session ledger spreadsheet
    
    Checks:
    1. Proper session tracking structure (columns for student, date, hours, rate, etc.)
    2. Student names present (Alex, Jamie, Taylor, Morgan, Casey, Riley)
    3. Substantial numeric data (hours, rates, amounts, payments)
    4. Calculations present (formulas or correct totals)
    5. Student summary section exists
    6. Business totals calculated
    7. Billing issues identified
    
    Returns:
        dict: {"passed": bool, "score": float, "feedback": str}
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    filepath = "/home/ga/Documents/Spreadsheets/session_ledger.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_tutor_')
    
    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(
            filepath,
            copy_from_env,
            file_format='xlsx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to parse spreadsheet: {error}"
            }
        
        # Get the main sheet
        sheet_names = wb.sheetnames
        if not sheet_names:
            return {
                "passed": False,
                "score": 0,
                "feedback": "No sheets found in workbook"
            }
        
        ws = wb[sheet_names[0]]
        data = get_sheet_data(wb, sheet_names[0], max_rows=150, max_cols=20)
        
        # Convert data to text for searching
        all_text = '\n'.join([
            ' '.join([str(cell) if cell else '' for cell in row])
            for row in data
        ])
        all_text_lower = all_text.lower()
        
        feedback_parts = []
        score = 0.0
        max_score = 10.0
        
        # === CRITERION 1: Session tracking columns exist (1.5 points) ===
        required_columns = ['student', 'date', 'hour', 'rate', 'amount', 'paid', 'balance', 'bill']
        columns_found = sum(1 for col in required_columns if col in all_text_lower)
        
        if columns_found >= 6:
            score += 1.5
            feedback_parts.append(f"✅ Session tracking structure present ({columns_found}/8 key terms)")
        elif columns_found >= 4:
            score += 0.8
            feedback_parts.append(f"⚠️ Partial session structure ({columns_found}/8 key terms)")
        else:
            feedback_parts.append(f"❌ Missing session tracking structure (found {columns_found}/8)")
        
        # === CRITERION 2: Student names present (1.5 points) ===
        students = ['alex', 'jamie', 'taylor', 'morgan', 'casey', 'riley']
        students_found = sum(1 for student in students if student in all_text_lower)
        
        if students_found >= 6:
            score += 1.5
            feedback_parts.append(f"✅ All student names tracked ({students_found}/6 students)")
        elif students_found >= 4:
            score += 1.0
            feedback_parts.append(f"⚠️ Most students tracked ({students_found}/6 students)")
        else:
            feedback_parts.append(f"❌ Missing students (found {students_found}/6)")
        
        # === CRITERION 3: Numeric data present - sessions data (2 points) ===
        numeric_cells = []
        for row in data:
            for cell in row:
                if isinstance(cell, (int, float)) and cell > 0:
                    numeric_cells.append(cell)
        
        # Should have many numeric entries (hours, rates, amounts)
        # Expected: ~40 sessions × 3-4 numeric values = 120-160 values minimum
        if len(numeric_cells) >= 80:
            score += 2.0
            feedback_parts.append(f"✅ Comprehensive numeric data ({len(numeric_cells)} values)")
        elif len(numeric_cells) >= 40:
            score += 1.2
            feedback_parts.append(f"⚠️ Moderate numeric data ({len(numeric_cells)} values)")
        elif len(numeric_cells) >= 20:
            score += 0.6
            feedback_parts.append(f"⚠️ Limited numeric data ({len(numeric_cells)} values)")
        else:
            feedback_parts.append(f"❌ Insufficient numeric data ({len(numeric_cells)} values)")
        
        # === CRITERION 4: Rate values present (1 point) ===
        # Should have rates: 55, 60, 65, 70 (per hour)
        rate_values = [v for v in numeric_cells if 50 <= v <= 75]
        
        if len(rate_values) >= 15:  # Multiple sessions with rates
            score += 1.0
            feedback_parts.append(f"✅ Hourly rates tracked ({len(rate_values)} rate entries)")
        elif len(rate_values) >= 8:
            score += 0.5
            feedback_parts.append(f"⚠️ Some rates tracked ({len(rate_values)} rate entries)")
        else:
            feedback_parts.append(f"❌ Rates not properly tracked ({len(rate_values)} entries)")
        
        # === CRITERION 5: Summary calculations present (2 points) ===
        # Look for plausible totals
        # Expected totals based on notes:
        # - Total hours: ~60-70 hours total
        # - Total revenue: ~$4000-4500
        # - Outstanding: $300-500
        
        large_values = [v for v in numeric_cells if v > 500]
        
        has_plausible_revenue = any(3500 <= v <= 5500 for v in large_values)
        has_total_indicators = 'total' in all_text_lower or 'sum' in all_text_lower
        has_summary_section = any(word in all_text_lower for word in ['summary', 'business', 'overall', 'grand'])
        
        summary_score = 0
        if has_plausible_revenue:
            summary_score += 1.0
        if has_total_indicators:
            summary_score += 0.5
        if has_summary_section:
            summary_score += 0.5
        
        summary_score = min(summary_score, 2.0)
        score += summary_score
        
        if summary_score >= 1.5:
            feedback_parts.append("✅ Summary calculations present")
        elif summary_score >= 0.8:
            feedback_parts.append("⚠️ Partial summary calculations")
        else:
            feedback_parts.append("❌ Missing summary calculations")
        
        # === CRITERION 6: Business metrics section (1 point) ===
        business_keywords = ['total hours', 'total revenue', 'total billed', 'outstanding', 
                            'total paid', 'balance', 'total income']
        business_metrics_count = sum(1 for keyword in business_keywords 
                                     if keyword in all_text_lower)
        
        if business_metrics_count >= 3:
            score += 1.0
            feedback_parts.append(f"✅ Business metrics section present ({business_metrics_count} metrics)")
        elif business_metrics_count >= 2:
            score += 0.5
            feedback_parts.append(f"⚠️ Some business metrics ({business_metrics_count} metrics)")
        else:
            feedback_parts.append(f"❌ Business metrics incomplete ({business_metrics_count} metrics)")
        
        # === CRITERION 7: Billing issues identified (1 point) ===
        # Look for mentions of issues: Taylor (undercharging), Casey (large balance), 
        # or problem indicators
        
        taylor_mentioned = 'taylor' in all_text_lower
        casey_mentioned = 'casey' in all_text_lower
        
        issue_indicators = ['undercharg', 'error', 'incorrect', 'owe', 'outstanding', 
                           'unpaid', 'discrepanc', 'issue', 'problem', 'note']
        issues_count = sum(1 for indicator in issue_indicators if indicator in all_text_lower)
        
        # Check if there's a notes/issues section
        has_notes_section = any(word in all_text_lower for word in ['note', 'issue', 'problem', 'billing'])
        
        issue_score = 0
        if taylor_mentioned and casey_mentioned:
            issue_score += 0.4
        if issues_count >= 3:
            issue_score += 0.4
        if has_notes_section:
            issue_score += 0.2
        
        issue_score = min(issue_score, 1.0)
        score += issue_score
        
        if issue_score >= 0.7:
            feedback_parts.append("✅ Billing issues/discrepancies identified")
        elif issue_score >= 0.3:
            feedback_parts.append("⚠️ Some issue tracking present")
        else:
            feedback_parts.append("❌ Billing issues not clearly identified")
        
        # === ADDITIONAL CHECK: Data organization quality ===
        # Check if data is organized (not just dumped)
        # Look for consistent structure - multiple rows with similar patterns
        non_empty_rows = [row for row in data if any(cell for cell in row if cell)]
        has_organization = len(non_empty_rows) >= 15  # At least 15 rows of data
        
        if has_organization and columns_found >= 5:
            # Bonus: well-organized data
            feedback_parts.append("ℹ️ Data appears well-organized")
        
        # Determine if passed (need at least 6/10 points)
        passed = score >= 6.0
        
        # Normalize score to 0-100
        final_score = int((score / max_score) * 100)
        
        # Build final feedback
        summary = f"Score: {score:.1f}/{max_score:.1f} ({final_score}%) | "
        if passed:
            summary += "Session ledger successfully organized with tracking and calculations."
        else:
            summary += "Session ledger needs more complete tracking and calculations."
        
        feedback = summary + " | " + " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
