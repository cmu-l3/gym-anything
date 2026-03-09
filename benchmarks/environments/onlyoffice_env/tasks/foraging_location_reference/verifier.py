#!/usr/bin/env python3
"""
Verifier for Foraging Location Reference task
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
    check_paragraph_alignment,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_foraging_reference(traj, env_info, task_info):
    """
    Verify that foraging reference document was properly formatted.

    Scoring criteria (100 points total):
    1. Title formatting (20 points): Bold, centered, 16pt+, contains "Foraging Reference Guide"
    2. Location structure (30 points): All 3 locations with bold headers
    3. GPS standardization (10 points): Coordinates in decimal format
    4. Table creation (25 points): Seasonal availability table with proper structure
    5. Safety warning formatting (15 points): Critical warnings are bolded
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/foraging_notes.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_foraging_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"Failed to load document: {error}"}

        points_earned = 0
        max_points = 100
        feedback_parts = []

        # Get full document text for analysis
        doc_text = get_document_text(doc)
        doc_text_lower = doc_text.lower()

        # ===== CRITERION 1: Title Formatting (20 points) =====
        title_points = 0
        title_found = False
        title_bold = False
        title_centered = False
        title_large = False

        # Check if title exists in first few paragraphs
        if "foraging reference guide" in doc_text_lower[:300]:
            title_found = True
            title_points += 5
            feedback_parts.append("✅ Title text found")

            # Check if title is bold
            if check_text_formatting(doc, "Foraging Reference Guide", bold=True) or \
               check_text_formatting(doc, "Fall Foraging Reference", bold=True) or \
               check_text_formatting(doc, "Marcus's Fall Foraging", bold=True):
                title_bold = True
                title_points += 5
                feedback_parts.append("✅ Title is bold")
            else:
                feedback_parts.append("❌ Title is not bold")

            # Check if title is centered
            if check_paragraph_alignment(doc, "Foraging Reference Guide", "center") or \
               check_paragraph_alignment(doc, "Fall Foraging Reference", "center") or \
               check_paragraph_alignment(doc, "Marcus", "center"):
                title_centered = True
                title_points += 5
                feedback_parts.append("✅ Title is centered")
            else:
                feedback_parts.append("❌ Title is not centered")

            # Check if title has large font (16pt or more)
            if check_text_formatting(doc, "Foraging Reference Guide", font_size=16) or \
               check_text_formatting(doc, "Foraging Reference Guide", font_size=18) or \
               check_text_formatting(doc, "Foraging Reference Guide", font_size=20) or \
               check_text_formatting(doc, "Fall Foraging Reference", font_size=16) or \
               check_text_formatting(doc, "Fall Foraging Reference", font_size=18):
                title_large = True
                title_points += 5
                feedback_parts.append("✅ Title has large font (≥16pt)")
            else:
                feedback_parts.append("⚠️ Title font size unclear (may be <16pt)")
                title_points += 2  # Partial credit
        else:
            feedback_parts.append("❌ Title 'Foraging Reference Guide' not found")

        points_earned += title_points

        # ===== CRITERION 2: Location Structure (30 points) =====
        location_points = 0
        locations_found = 0

        # Check for Oak Ridge Trail
        if "oak ridge" in doc_text_lower:
            locations_found += 1
            if check_text_formatting(doc, "Oak Ridge", bold=True):
                location_points += 10
                feedback_parts.append("✅ Oak Ridge Trail formatted as bold header")
            else:
                location_points += 4
                feedback_parts.append("⚠️ Oak Ridge Trail found but not bolded")
        else:
            feedback_parts.append("❌ Oak Ridge Trail location missing")

        # Check for Riverside Conservation Area
        if "riverside" in doc_text_lower:
            locations_found += 1
            if check_text_formatting(doc, "Riverside", bold=True):
                location_points += 10
                feedback_parts.append("✅ Riverside Conservation formatted as bold header")
            else:
                location_points += 4
                feedback_parts.append("⚠️ Riverside Conservation found but not bolded")
        else:
            feedback_parts.append("❌ Riverside Conservation location missing")

        # Check for Meadowbrook Park
        if "meadowbrook" in doc_text_lower:
            locations_found += 1
            if check_text_formatting(doc, "Meadowbrook", bold=True):
                location_points += 10
                feedback_parts.append("✅ Meadowbrook Park formatted as bold header")
            else:
                location_points += 4
                feedback_parts.append("⚠️ Meadowbrook Park found but not bolded")
        else:
            feedback_parts.append("❌ Meadowbrook Park location missing")

        points_earned += location_points

        # ===== CRITERION 3: GPS Coordinate Standardization (10 points) =====
        gps_points = 0

        # Check for decimal format GPS coordinates (e.g., 42.3601, -71.0589)
        decimal_gps_pattern = r'42\.\d{4}.*?-?71\.\d{4}'
        decimal_matches = re.findall(decimal_gps_pattern, doc_text)

        if len(decimal_matches) >= 2:
            gps_points = 10
            feedback_parts.append(f"✅ GPS coordinates standardized to decimal format ({len(decimal_matches)} found)")
        elif len(decimal_matches) == 1:
            gps_points = 5
            feedback_parts.append("⚠️ Only 1 GPS coordinate in decimal format (need 3)")
        else:
            # Check if any standardization attempt was made
            if "42." in doc_text and "71." in doc_text:
                gps_points = 3
                feedback_parts.append("⚠️ GPS coordinates present but not fully standardized")
            else:
                feedback_parts.append("❌ GPS coordinates not standardized to decimal format")

        points_earned += gps_points

        # ===== CRITERION 4: Table Creation (25 points) =====
        table_points = 0
        table_count = count_tables(doc)

        if table_count >= 1:
            table_points += 10
            feedback_parts.append(f"✅ Table created ({table_count} table(s) found)")

            # Check table structure
            try:
                table = doc.tables[0]
                row_count = len(table.rows)
                col_count = len(table.columns) if len(table.rows) > 0 else 0

                # Table should have at least 3 columns (Location + at least 2 seasons)
                if col_count >= 3:
                    table_points += 8
                    feedback_parts.append(f"✅ Table has proper structure ({row_count} rows × {col_count} cols)")
                else:
                    table_points += 3
                    feedback_parts.append(f"⚠️ Table has too few columns ({col_count}, expected ≥3)")

                # Check if table contains seasonal keywords
                table_text = ""
                for row in table.rows:
                    for cell in row.cells:
                        table_text += cell.text.lower() + " "

                seasonal_keywords = ["spring", "summer", "fall", "april", "may", "june", "july", "august", "september"]
                seasonal_found = sum(1 for kw in seasonal_keywords if kw in table_text)

                if seasonal_found >= 3:
                    table_points += 7
                    feedback_parts.append(f"✅ Table contains seasonal information")
                elif seasonal_found >= 1:
                    table_points += 3
                    feedback_parts.append(f"⚠️ Table has some seasonal info but incomplete")
                else:
                    feedback_parts.append("❌ Table missing seasonal information")

            except Exception as e:
                logger.warning(f"Error analyzing table structure: {e}")
                feedback_parts.append("⚠️ Table structure could not be fully verified")
        else:
            feedback_parts.append("❌ No table created for seasonal availability")

        points_earned += table_points

        # ===== CRITERION 5: Safety Warning Formatting (15 points) =====
        safety_points = 0
        
        # Keywords that should be bold for safety
        safety_keywords = [
            ("poisonous", "poisonous look-alike warning"),
            ("bear", "bear warning"),
            ("contaminated", "contamination warning"),
            ("do not", "prohibition warning"),
            ("thoroughly", "cooking safety"),
            ("100% positive", "identification requirement"),
            ("never eat", "eating prohibition")
        ]

        bold_safety_count = 0
        for keyword, description in safety_keywords:
            if keyword in doc_text_lower:
                if check_text_formatting(doc, keyword, bold=True):
                    bold_safety_count += 1

        if bold_safety_count >= 3:
            safety_points = 15
            feedback_parts.append(f"✅ Safety warnings properly bolded ({bold_safety_count} critical terms)")
        elif bold_safety_count >= 2:
            safety_points = 10
            feedback_parts.append(f"⚠️ Some safety warnings bolded ({bold_safety_count}/3+ needed)")
        elif bold_safety_count >= 1:
            safety_points = 5
            feedback_parts.append(f"⚠️ Few safety warnings bolded ({bold_safety_count})")
        else:
            feedback_parts.append("❌ Safety warnings not properly emphasized with bold")

        # Check if safety section exists near end
        doc_length = len(doc_text)
        last_third = doc_text[int(doc_length * 0.6):].lower()
        
        if ("safety" in last_third or "identification rules" in last_third) and \
           ("100% positive" in last_third or "when in doubt" in last_third):
            # Bonus points for having a dedicated safety section
            if safety_points < 15:
                safety_points = min(15, safety_points + 3)
            feedback_parts.append("✅ Dedicated safety section found at end")

        points_earned += safety_points

        # ===== FINAL SCORING =====
        score = int((points_earned / max_points) * 100)
        passed = score >= 75

        feedback = " | ".join(feedback_parts)
        
        # Add summary
        summary = f"Score: {points_earned}/{max_points} points. "
        if passed:
            summary += "Document properly formatted with safety emphasis."
        else:
            summary += "Document needs more formatting improvements."

        return {
            "passed": passed,
            "score": score,
            "feedback": f"{summary} | {feedback}"
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)