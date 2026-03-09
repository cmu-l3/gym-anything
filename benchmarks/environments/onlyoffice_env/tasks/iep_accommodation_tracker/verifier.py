#!/usr/bin/env python3
"""
Verifier for IEP Accommodation Tracker task
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


def verify_iep_accommodation_tracker(traj, env_info, task_info):
    """
    Verify that 504 accommodation tracking document was organized correctly.

    Checks:
    1. Document structure with bold headings (30 points)
    2. Accommodations section has bullet points (20 points)
    3. Incidents table exists with proper structure (30 points)
    4. Requested modifications as bullets (15 points)
    5. Teacher names are bold (5 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/504_review_prep.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_504_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0.0, "feedback": f"Failed to load document: {error}"}

        score = 0
        max_score = 100
        feedback_parts = []

        full_text = get_document_text(doc).lower()

        # ===== CRITERION 1: Document structure with bold headings (30 points) =====
        structure_score = 0
        
        has_accommodations_heading = False
        has_concerns_heading = False
        has_modifications_heading = False

        for para in doc.paragraphs:
            para_text = para.text.strip()
            if not para_text:
                continue
                
            para_text_lower = para_text.lower()
            
            # Check if paragraph has bold runs
            has_bold = any(run.bold for run in para.runs if run.text.strip())
            
            # Check for accommodations heading
            if has_bold:
                if ("current" in para_text_lower and "accommodation" in para_text_lower) or \
                   ("504" in para_text_lower and "accommodation" in para_text_lower):
                    has_accommodations_heading = True
                
                # Check for concerns heading
                if any(word in para_text_lower for word in ["implementation", "concern", "problem", "issue"]):
                    has_concerns_heading = True
                
                # Check for modifications heading
                if ("request" in para_text_lower or "proposed" in para_text_lower or "new" in para_text_lower) and \
                   ("modification" in para_text_lower or "accommodation" in para_text_lower):
                    has_modifications_heading = True

        if has_accommodations_heading:
            structure_score += 10
            feedback_parts.append("✓ Current accommodations heading found")
        else:
            feedback_parts.append("✗ Missing bold 'Current Accommodations' heading")

        if has_concerns_heading:
            structure_score += 10
            feedback_parts.append("✓ Implementation concerns heading found")
        else:
            feedback_parts.append("✗ Missing bold 'Concerns/Problems' heading")

        if has_modifications_heading:
            structure_score += 10
            feedback_parts.append("✓ Requested modifications heading found")
        else:
            feedback_parts.append("✗ Missing bold 'Requested Modifications' heading")

        score += structure_score

        # ===== CRITERION 2: Accommodations section has bullet points (20 points) =====
        accommodations_score = 0
        
        # Count bullet-style paragraphs or list-formatted paragraphs
        bullet_count = 0
        list_paragraphs = []
        
        for para in doc.paragraphs:
            para_text = para.text.strip()
            if not para_text:
                continue
            
            # Check various bullet indicators
            is_bullet = False
            
            # Check for Word list style
            if para.style and para.style.name and 'List' in para.style.name:
                is_bullet = True
            
            # Check for bullet characters
            if para_text.startswith('•') or para_text.startswith('-') or para_text.startswith('*'):
                is_bullet = True
            
            # Check for numbered list
            if re.match(r'^\d+[\.\)]\s', para_text):
                is_bullet = True
            
            if is_bullet:
                bullet_count += 1
                list_paragraphs.append(para_text.lower())

        if bullet_count >= 4:
            accommodations_score += 5
            feedback_parts.append(f"✓ Found {bullet_count} bullet points")
        else:
            feedback_parts.append(f"✗ Only {bullet_count} bullet points (need 4+)")

        # Check for specific accommodations mentioned
        if "extended time" in full_text or "extra time" in full_text:
            accommodations_score += 5
            feedback_parts.append("✓ Extended time mentioned")
        else:
            feedback_parts.append("✗ Missing extended time accommodation")

        if "preferential seating" in full_text or ("seating" in full_text and "front" in full_text):
            accommodations_score += 5
            feedback_parts.append("✓ Seating accommodation mentioned")
        else:
            feedback_parts.append("✗ Missing seating accommodation")

        if "break" in full_text:
            accommodations_score += 5
            feedback_parts.append("✓ Breaks accommodation mentioned")
        else:
            feedback_parts.append("✗ Missing breaks accommodation")

        score += accommodations_score

        # ===== CRITERION 3: Incidents table (30 points) =====
        table_score = 0
        table_count = count_tables(doc)

        if table_count >= 1:
            table_score += 10
            feedback_parts.append(f"✓ Found {table_count} table(s)")

            # Examine first table
            table = doc.tables[0]
            row_count = len(table.rows)
            
            if row_count >= 1:
                # Extract all table text
                table_text = ""
                for row in table.rows:
                    for cell in row.cells:
                        table_text += cell.text.lower() + " "

                # Check for data rows (at least 3 incidents)
                if row_count >= 4:  # 1 header + 3 data rows
                    table_score += 5
                    feedback_parts.append(f"✓ Table has {row_count-1} data rows")
                else:
                    feedback_parts.append(f"✗ Table only has {row_count-1} rows (need 3+ incidents)")

                # Check for specific teacher names in table
                if "harrison" in table_text:
                    table_score += 5
                    feedback_parts.append("✓ Harrison incident documented")
                else:
                    feedback_parts.append("✗ Harrison incident missing from table")

                if "williams" in table_text:
                    table_score += 5
                    feedback_parts.append("✓ Williams incident documented")
                else:
                    feedback_parts.append("✗ Williams incident missing from table")

                # Check for dates (various formats)
                has_dates = bool(re.search(r'(oct|october|nov|november|\d{1,2}/\d{1,2})', table_text))
                if has_dates:
                    table_score += 5
                    feedback_parts.append("✓ Dates present in table")
                else:
                    feedback_parts.append("✗ Missing dates in table")
        else:
            feedback_parts.append("✗ No table found for tracking incidents")

        score += table_score

        # ===== CRITERION 4: Requested modifications as bullets (15 points) =====
        modifications_score = 0

        if "headphone" in full_text or "noise cancel" in full_text:
            modifications_score += 5
            feedback_parts.append("✓ Headphones requested")
        else:
            feedback_parts.append("✗ Missing headphones request")

        if "fidget" in full_text:
            modifications_score += 5
            feedback_parts.append("✓ Fidget tools requested")
        else:
            feedback_parts.append("✗ Missing fidget tools request")

        if "type" in full_text or "typing" in full_text or "keyboard" in full_text:
            modifications_score += 5
            feedback_parts.append("✓ Typing accommodation requested")
        else:
            feedback_parts.append("✗ Missing typing accommodation request")

        score += modifications_score

        # ===== CRITERION 5: Teacher names are bold (5 points) =====
        formatting_score = 0
        
        # Check for bold teacher names
        bold_teacher_count = 0
        teacher_names = ["harrison", "williams", "patel", "rodriguez"]
        
        for para in doc.paragraphs:
            for run in para.runs:
                if run.bold and run.text.strip():
                    run_text_lower = run.text.lower()
                    for name in teacher_names:
                        if name in run_text_lower:
                            bold_teacher_count += 1
                            break  # Count this paragraph once
                    
        # Also check table cells for bold teacher names
        for table in doc.tables:
            for row in table.rows:
                for cell in row.cells:
                    for para in cell.paragraphs:
                        for run in para.runs:
                            if run.bold and run.text.strip():
                                run_text_lower = run.text.lower()
                                for name in teacher_names:
                                    if name in run_text_lower:
                                        bold_teacher_count += 1
                                        break

        if bold_teacher_count >= 2:
            formatting_score += 5
            feedback_parts.append(f"✓ Teacher names formatted with bold")
        else:
            feedback_parts.append(f"✗ Teacher names should be bold (found {bold_teacher_count})")

        score += formatting_score

        # Determine pass/fail
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": float(score) / max_score,
            "feedback": f"Score: {score}/{max_score} | {feedback}"
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0.0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)