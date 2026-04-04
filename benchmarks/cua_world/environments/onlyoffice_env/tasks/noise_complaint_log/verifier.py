#!/usr/bin/env python3
"""
Verifier for Noise Complaint Log task

Comprehensive verification of a professional noise complaint document
with table creation, data entry, calculations, and formatting.
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    check_text_formatting,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_noise_complaint_log(traj, env_info, task_info):
    """
    Verify noise complaint log document creation.
    
    Verification Criteria (100 points total):
    1. Document title present & formatted (10 points)
    2. Header information complete (8 points)
    3. Table created with correct structure (20 points)
    4. Table data accuracy (15 points)
    5. Table formatting applied (8 points)
    6. Impact summary section present (12 points)
    7. Calculations correct (10 points)
    8. Opening statement professional (7 points)
    9. Closing request present (5 points)
    10. Document formatting standards (5 points)
    
    Pass threshold: 75 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/noise_complaint.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_noise_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Could not parse document: {error}"
            }

        score = 0
        max_score = 100
        feedback_parts = []

        # Get full text for content checks
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()

        # ===================================================================
        # CRITERION 1: Title check (10 points)
        # ===================================================================
        title_keywords = ["noise", "disturbance", "complaint", "log"]
        unit_mentioned = "4b" in full_text_lower[:200]
        has_title_keywords = any(kw in full_text_lower[:200] for kw in title_keywords)
        
        title_score = 0
        if has_title_keywords and unit_mentioned:
            title_score += 7
            # Check if title is bold (look in first few paragraphs)
            title_bold = False
            for para in doc.paragraphs[:3]:
                if any(kw in para.text.lower() for kw in title_keywords):
                    for run in para.runs:
                        if run.bold and any(kw in run.text.lower() for kw in title_keywords):
                            title_bold = True
                            break
            
            if title_bold:
                title_score += 3
                feedback_parts.append("✅ Title formatted correctly (bold, contains keywords)")
            else:
                feedback_parts.append("⚠️ Title present but not bold")
        else:
            feedback_parts.append("❌ Title missing or incomplete (need 'noise/disturbance/complaint' + 'Unit 4B')")
        
        score += title_score

        # ===================================================================
        # CRITERION 2: Header info (8 points)
        # ===================================================================
        has_name = "martinez" in full_text_lower[:400] or "alex" in full_text_lower[:400]
        has_dates = (("january" in full_text_lower[:400] or "jan" in full_text_lower[:400]) and 
                    ("february" in full_text_lower[:400] or "feb" in full_text_lower[:400]) and
                    "2025" in full_text[:400])
        
        header_score = 0
        if has_name:
            header_score += 4
        if has_dates:
            header_score += 4
        
        score += header_score
        if header_score >= 6:
            feedback_parts.append("✅ Header information complete (name + date range)")
        elif header_score >= 4:
            feedback_parts.append("⚠️ Header partially complete (missing name or dates)")
        else:
            feedback_parts.append("❌ Header information missing")

        # ===================================================================
        # CRITERION 3: Table structure (20 points)
        # ===================================================================
        table_count = count_tables(doc)
        table_score = 0
        
        if table_count == 0:
            feedback_parts.append("❌ CRITICAL: No table found in document")
        else:
            # Check first table structure
            table = doc.tables[0]
            col_count = len(table.columns)
            row_count = len(table.rows)
            
            # Check column count (5 required: Date, Time, Duration, Type, Impact)
            if col_count >= 5:
                table_score += 8
                if col_count == 5:
                    feedback_parts.append(f"✅ Table has correct column count (5)")
                else:
                    feedback_parts.append(f"✅ Table has sufficient columns ({col_count})")
            elif col_count >= 4:
                table_score += 4
                feedback_parts.append(f"⚠️ Table has {col_count} columns (expected 5)")
            else:
                feedback_parts.append(f"❌ Table has insufficient columns ({col_count}/5)")
            
            # Check row count (9 required: 1 header + 8 data rows)
            if row_count >= 9:
                table_score += 12
                feedback_parts.append(f"✅ Table has sufficient rows ({row_count} ≥ 9)")
            elif row_count >= 6:
                table_score += 6
                feedback_parts.append(f"⚠️ Table has some rows ({row_count}, expected ≥9)")
            elif row_count >= 3:
                table_score += 3
                feedback_parts.append(f"⚠️ Table exists but too few rows ({row_count})")
            else:
                feedback_parts.append(f"❌ Table has too few rows ({row_count})")
        
        score += table_score

        # ===================================================================
        # CRITERION 4: Table data accuracy (15 points)
        # ===================================================================
        # Check for required dates (8 incidents)
        required_dates = ["jan 15", "jan 17", "jan 19", "jan 22", "jan 25", "jan 28", "feb 1", "feb 4"]
        dates_found = 0
        for date in required_dates:
            # Try different formats
            date_variants = [
                date,
                date.replace(" ", "-"),
                date.replace(" ", "/"),
                date.replace("jan", "january").replace("feb", "february")
            ]
            if any(variant in full_text_lower for variant in date_variants):
                dates_found += 1
        
        # Score proportionally (10 points max for dates)
        date_score = min(10, int((dates_found / 8) * 10))
        score += date_score
        
        # Check for time mentions (5 points for times)
        time_patterns = ["pm", "am"]
        time_count = sum(full_text_lower.count(pattern) for pattern in time_patterns)
        # Also look for specific times
        specific_times = ["11:", "12:", "1:", "2:", "10:"]
        specific_time_count = sum(full_text.count(t) for t in specific_times)
        
        time_score = 0
        if time_count >= 8 or specific_time_count >= 6:  # Should have ~8 times
            time_score = 5
        elif time_count >= 4 or specific_time_count >= 3:
            time_score = 3
        elif time_count >= 2:
            time_score = 1
        
        score += time_score
        
        # Provide feedback on data accuracy
        if dates_found >= 7:
            feedback_parts.append(f"✅ Table data highly accurate ({dates_found}/8 dates found)")
        elif dates_found >= 5:
            feedback_parts.append(f"⚠️ Table data mostly accurate ({dates_found}/8 dates found)")
        else:
            feedback_parts.append(f"❌ Table data incomplete ({dates_found}/8 dates found)")

        # ===================================================================
        # CRITERION 5: Table formatting (8 points)
        # ===================================================================
        format_score = 0
        if table_count > 0:
            table = doc.tables[0]
            # Check if header row has bold text
            has_bold_header = False
            if len(table.rows) > 0:
                header_row = table.rows[0]
                for cell in header_row.cells:
                    for para in cell.paragraphs:
                        for run in para.runs:
                            if run.bold and len(run.text.strip()) > 0:
                                has_bold_header = True
                                break
                        if has_bold_header:
                            break
                    if has_bold_header:
                        break
            
            if has_bold_header:
                format_score += 8
                feedback_parts.append("✅ Table header properly formatted (bold)")
            else:
                # Partial credit just for having a table
                format_score += 4
                feedback_parts.append("⚠️ Table exists but header not bold")
        
        score += format_score

        # ===================================================================
        # CRITERION 6: Impact summary section (12 points)
        # ===================================================================
        has_summary_heading = "summary" in full_text_lower and "impact" in full_text_lower
        has_8_incidents = "8 incident" in full_text_lower or "eight incident" in full_text_lower or "8 occurrence" in full_text_lower or "8 disturbance" in full_text_lower
        has_18_hours = "18 hour" in full_text_lower or "eighteen hour" in full_text_lower
        has_frequency = "per week" in full_text_lower or "weekly" in full_text_lower or "/week" in full_text_lower
        
        summary_score = 0
        if has_summary_heading:
            summary_score += 3
        if has_8_incidents:
            summary_score += 3
        if has_18_hours:
            summary_score += 3
        if has_frequency:
            summary_score += 3
        
        score += summary_score
        
        if summary_score >= 9:
            feedback_parts.append("✅ Impact summary section complete with key data")
        elif summary_score >= 6:
            feedback_parts.append("⚠️ Impact summary present but incomplete")
        elif summary_score >= 3:
            feedback_parts.append("⚠️ Partial impact summary found")
        else:
            feedback_parts.append("❌ Impact summary section missing")

        # ===================================================================
        # CRITERION 7: Calculations correct (10 points)
        # ===================================================================
        calc_score = 0
        
        # Check for "8 incidents" calculation
        if has_8_incidents:
            calc_score += 4
        
        # Check for "18 hours" calculation
        if has_18_hours:
            calc_score += 4
        
        # Check for "2.7 per week" or similar average
        avg_patterns = ["2.7", "2-3", "nearly 3", "almost 3", "approximately 3", "~3"]
        has_average = any(pattern in full_text for pattern in avg_patterns)
        if has_average:
            calc_score += 2
        
        score += calc_score
        
        if calc_score >= 8:
            feedback_parts.append("✅ All calculations accurate (8 incidents, 18 hrs, 2.7/wk)")
        elif calc_score >= 4:
            feedback_parts.append("⚠️ Some calculations present but incomplete")
        else:
            feedback_parts.append("❌ Calculations missing or incorrect")

        # ===================================================================
        # CRITERION 8: Opening statement (7 points)
        # ===================================================================
        # Check first 500 characters for key professional elements
        first_500 = full_text_lower[:500]
        has_unit_ref = "5b" in first_500 or "unit 5" in first_500
        has_noise_ref = any(kw in first_500 for kw in ["noise", "disturbance", "loud", "sound"])
        has_sleep_ref = any(kw in first_500 for kw in ["sleep", "rest", "tired", "exhausted", "wake"])
        
        opening_score = 0
        if has_unit_ref:
            opening_score += 3
        if has_noise_ref:
            opening_score += 2
        if has_sleep_ref:
            opening_score += 2
        
        score += opening_score
        
        if opening_score >= 5:
            feedback_parts.append("✅ Professional opening statement (identifies source, issue, impact)")
        elif opening_score >= 3:
            feedback_parts.append("⚠️ Opening statement present but incomplete")
        else:
            feedback_parts.append("❌ Opening statement missing or unprofessional")

        # ===================================================================
        # CRITERION 9: Closing request (5 points)
        # ===================================================================
        # Check last 400 characters for professional closing
        last_400 = full_text_lower[-400:]
        has_request = any(kw in last_400 for kw in ["request", "ask", "need", "urge", "please"])
        has_action = any(kw in last_400 for kw in ["interven", "action", "address", "resolve", "discuss", "speak"])
        has_unit_closing = "5b" in last_400 or "neighbor" in last_400 or "quiet" in last_400 or "tenant" in last_400
        
        closing_score = 0
        if has_request:
            closing_score += 2
        if has_action:
            closing_score += 2
        if has_unit_closing:
            closing_score += 1
        
        score += closing_score
        
        if closing_score >= 4:
            feedback_parts.append("✅ Professional closing request present")
        elif closing_score >= 2:
            feedback_parts.append("⚠️ Closing request weak")
        else:
            feedback_parts.append("❌ Closing request missing")

        # ===================================================================
        # CRITERION 10: Document formatting standards (5 points)
        # ===================================================================
        # Check document has reasonable structure
        para_count = len(doc.paragraphs)
        
        format_standards_score = 0
        if para_count >= 10:  # Should have: header paras, intro, table area, summary sections, closing
            format_standards_score += 5
            feedback_parts.append(f"✅ Document well-structured ({para_count} paragraphs)")
        elif para_count >= 5:
            format_standards_score += 2
            feedback_parts.append(f"⚠️ Document structure adequate ({para_count} paragraphs)")
        else:
            feedback_parts.append(f"❌ Document poorly structured ({para_count} paragraphs)")
        
        score += format_standards_score

        # ===================================================================
        # FINAL SCORING
        # ===================================================================
        final_score = score / max_score
        passed = final_score >= 0.75

        # Build comprehensive feedback
        feedback = " | ".join(feedback_parts)
        feedback += f" | TOTAL: {score}/{max_score} ({final_score*100:.1f}%)"
        
        if passed:
            feedback += " | ✅ PASSED"
        else:
            feedback += " | ❌ FAILED (need ≥75%)"

        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)