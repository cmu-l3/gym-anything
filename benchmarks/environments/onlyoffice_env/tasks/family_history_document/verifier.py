#!/usr/bin/env python3
"""
Verifier for Family History Document task
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    check_text_formatting,
    get_document_text,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_family_history_document(traj, env_info, task_info):
    """
    Verify that family history document was created correctly.

    Checks:
    1. Title "Anderson-Martinez Family History" exists and is centered
    2. Both section headers exist (Maternal Line, Paternal Line)
    3. All four names are bold (Rosa, Carlos, James, Dorothy)
    4. Required content exists (dates, narrative)
    5. Table exists with correct structure (3 columns, at least 3 rows including header)
    6. Table contains required family relationship data
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/FamilyHistory.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_family_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        score = 0
        feedback_parts = []

        # Get full document text (case-insensitive for checks)
        full_text = get_document_text(doc).lower()

        # === Criterion 1: Title exists (5 points) ===
        if "anderson-martinez family history" in full_text or "anderson martinez family history" in full_text:
            score += 5
            feedback_parts.append("✅ Title present")
            title_found = True
        else:
            feedback_parts.append("❌ Title 'Anderson-Martinez Family History' missing")
            title_found = False

        # === Criterion 2: Title is centered (10 points) ===
        title_centered = False
        if title_found:
            for para in doc.paragraphs:
                para_text = para.text.lower()
                if "anderson" in para_text and "martinez" in para_text and "family history" in para_text:
                    # Check alignment (1 = CENTER, None or 0 = LEFT)
                    try:
                        if para.alignment == 1:
                            title_centered = True
                            score += 10
                            feedback_parts.append("✅ Title centered")
                            break
                    except:
                        pass
            if not title_centered:
                feedback_parts.append("❌ Title not centered")

        # === Criterion 3: Section headers exist (10 points each = 20 points) ===
        if "maternal line" in full_text or "martinez family" in full_text:
            score += 10
            feedback_parts.append("✅ Maternal section header present")
        else:
            feedback_parts.append("❌ Maternal section header missing")

        if "paternal line" in full_text or ("paternal" in full_text and "anderson family" in full_text):
            score += 10
            feedback_parts.append("✅ Paternal section header present")
        else:
            feedback_parts.append("❌ Paternal section header missing")

        # === Criterion 4: Four names are bold (25 points total) ===
        names_to_check = [
            ("rosa martinez", "Rosa Martinez"),
            ("carlos martinez", "Carlos Martinez"),
            ("james anderson", "James Anderson"),
            ("dorothy anderson", "Dorothy Anderson")
        ]
        bold_count = 0
        for name_lower, name_display in names_to_check:
            # Check if name appears in bold anywhere in document
            if check_text_formatting(doc, name_lower, bold=True):
                bold_count += 1

        score += int((bold_count / 4) * 25)
        if bold_count == 4:
            feedback_parts.append("✅ All 4 names bold")
        elif bold_count > 0:
            feedback_parts.append(f"⚠️ Only {bold_count}/4 names bold")
        else:
            feedback_parts.append("❌ No names in bold")

        # === Criterion 5: Required content exists (20 points) ===
        content_score = 0
        content_checks = []

        # Check for Rosa Martinez content
        if "rosa" in full_text and ("1928" in full_text or "circa 1928" in full_text):
            content_score += 5
            content_checks.append("Rosa birth year")
        if "1947" in full_text:
            content_score += 5
            content_checks.append("marriage year")

        # Check for James Anderson content
        if "james" in full_text and "1925" in full_text:
            content_score += 5
            content_checks.append("James birth year")
        if "1949" in full_text:
            content_score += 5
            content_checks.append("meeting year")

        score += content_score
        if content_score >= 15:
            feedback_parts.append(f"✅ Required content present ({', '.join(content_checks)})")
        else:
            feedback_parts.append(f"⚠️ Some content missing ({content_score}/20 points)")

        # === Criterion 6: Table exists and has correct structure (20 points) ===
        table_count = count_tables(doc)
        if table_count == 0:
            feedback_parts.append("❌ No table found")
        else:
            try:
                table = doc.tables[0]
                rows = len(table.rows)
                cols = len(table.columns)

                if cols >= 3 and rows >= 3:
                    score += 12
                    feedback_parts.append(f"✅ Table structure correct ({cols}x{rows})")

                    # Check table headers (case-insensitive)
                    try:
                        header_row = table.rows[0]
                        header_texts = [cell.text.lower() for cell in header_row.cells[:3]]
                        header_combined = ' '.join(header_texts)

                        has_person = "person" in header_combined
                        has_born = "born" in header_combined or "birth" in header_combined
                        has_relationship = "relationship" in header_combined or "relation" in header_combined

                        if has_person and has_born and has_relationship:
                            score += 4
                            feedback_parts.append("✅ Table headers correct")
                        else:
                            feedback_parts.append(f"⚠️ Table headers incomplete")

                        # Check if table contains expected data
                        table_full_text = ""
                        for row in table.rows:
                            for cell in row.cells:
                                table_full_text += cell.text.lower() + " "

                        has_rosa = "rosa" in table_full_text and "martinez" in table_full_text
                        has_james = "james" in table_full_text and "anderson" in table_full_text

                        if has_rosa and has_james:
                            score += 4
                            feedback_parts.append("✅ Table contains required family data")
                        elif has_rosa or has_james:
                            score += 2
                            feedback_parts.append("⚠️ Table missing some family data")
                        else:
                            feedback_parts.append("❌ Table missing family data")

                    except Exception as e:
                        logger.warning(f"Error checking table content: {e}")
                        feedback_parts.append("⚠️ Could not verify table content")

                else:
                    feedback_parts.append(f"❌ Table structure incorrect ({cols} cols, {rows} rows; need 3x3)")

            except Exception as e:
                logger.error(f"Error accessing table: {e}")
                feedback_parts.append("❌ Error reading table")

        # === Final scoring ===
        # Cap score at 100
        score = min(score, 100)
        passed = score >= 75

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)