#!/usr/bin/env python3
"""
Verifier for Traffic Safety Testimony task

This verifier checks that the agent created a properly structured City Council
testimony document with header, evidence table, community support, solutions, and closing.
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


def verify_traffic_safety_testimony(traj, env_info, task_info):
    """
    Verify the traffic safety testimony document.
    
    Scoring breakdown:
    - Header information (15 pts): Name, location, meeting type, bold formatting
    - Table structure (25 pts): Table exists, proper columns/rows, header formatting
    - Specific evidence (20 pts): Cat incident, bicycle incident, speed data, elderly incident
    - Community support (15 pts): 23 households mentioned with bold formatting
    - Solutions section (15 pts): Bulleted list with 3+ items including speed bumps and signage
    - Professional closing (10 pts): Call to action, respectful tone, contact info
    
    Pass threshold: 70/100 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/oak_street_testimony.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_testimony_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load testimony document: {error}"
            }

        # Extract full text for searching
        full_text = get_document_text(doc).lower()
        
        # Initialize scoring
        score = 0
        feedback_parts = []

        # ===================================================================
        # CRITERION 1: Header Information (15 points)
        # ===================================================================
        header_points = 0
        
        # Check for Jordan Chen
        if "jordan chen" in full_text:
            header_points += 5
            feedback_parts.append("✅ Speaker name 'Jordan Chen' present")
        else:
            feedback_parts.append("❌ Speaker name 'Jordan Chen' not found")
        
        # Check for Oak Street
        if "oak street" in full_text:
            header_points += 3
            # Don't add separate feedback, combined below
        
        # Check for City Council or Public Comment
        if "city council" in full_text or "public comment" in full_text:
            header_points += 3
            # Don't add separate feedback, combined below
        
        # Check for bold formatting on name
        if check_text_formatting(doc, "Jordan Chen", bold=True):
            header_points += 4
            feedback_parts.append("✅ 'Jordan Chen' is bold")
        else:
            # Try variations
            if check_text_formatting(doc, "Jordan", bold=True) or check_text_formatting(doc, "Chen", bold=True):
                header_points += 2
                feedback_parts.append("⚠️ Name partially bold")
            else:
                feedback_parts.append("❌ Speaker name not bold")
        
        score += header_points
        if header_points < 15:
            feedback_parts.append(f"Header: {header_points}/15 pts")
        else:
            feedback_parts.append(f"✅ Header: {header_points}/15 pts")

        # ===================================================================
        # CRITERION 2: Table Structure (25 points)
        # ===================================================================
        table_points = 0
        num_tables = count_tables(doc)
        
        if num_tables == 0:
            feedback_parts.append("❌ No evidence table found (0/25 pts)")
        else:
            # Table exists
            table_points += 5
            
            table = doc.tables[0]
            num_cols = len(table.columns)
            num_rows = len(table.rows)
            
            # Check columns (should have at least 4)
            if num_cols >= 4:
                table_points += 5
            elif num_cols >= 3:
                table_points += 3
            
            # Check rows (should have at least 5: 1 header + 4 data rows)
            if num_rows >= 5:
                table_points += 5
            elif num_rows >= 4:
                table_points += 3
            elif num_rows >= 3:
                table_points += 1
            
            # Check header row content
            if num_rows > 0:
                header_row_text = ' '.join([cell.text.lower() for cell in table.rows[0].cells])
                has_date = "date" in header_row_text
                has_incident = "incident" in header_row_text or "type" in header_row_text
                has_details = "details" in header_row_text or "description" in header_row_text
                
                if has_date and has_incident:
                    table_points += 5
                elif has_date or has_incident:
                    table_points += 2
            
            # Check if header row is bold
            if num_rows > 0:
                header_has_bold = False
                for cell in table.rows[0].cells:
                    for para in cell.paragraphs:
                        for run in para.runs:
                            if run.bold:
                                header_has_bold = True
                                break
                        if header_has_bold:
                            break
                    if header_has_bold:
                        break
                
                if header_has_bold:
                    table_points += 5
                else:
                    table_points += 0
            
            score += table_points
            feedback_parts.append(f"Evidence table: {table_points}/25 pts ({num_rows} rows, {num_cols} cols)")

        # ===================================================================
        # CRITERION 3: Specific Evidence (20 points)
        # ===================================================================
        evidence_points = 0
        
        # Check for cat/pet fatality incident (5 pts)
        if any(word in full_text for word in ["cat", "pet"]) and \
           any(word in full_text for word in ["killed", "fatality", "death", "died"]):
            evidence_points += 5
        elif any(word in full_text for word in ["cat", "pet", "animal"]):
            evidence_points += 2
        
        # Check for bicycle/child near-miss incident (5 pts)
        if any(word in full_text for word in ["bicycle", "bike", "child", "kid"]) and \
           any(phrase in full_text for phrase in ["near-miss", "near miss", "nearly hit", "almost hit", "close call"]):
            evidence_points += 5
        elif any(word in full_text for word in ["bicycle", "bike", "child", "kid"]):
            evidence_points += 2
        
        # Check for specific speed data (5 pts)
        has_speed_number = any(speed in full_text for speed in ["40", "42", "43", "44", "45"])
        has_mph = "mph" in full_text or "speed" in full_text
        if has_speed_number and has_mph:
            evidence_points += 5
        elif has_speed_number or has_mph:
            evidence_points += 2
        
        # Check for elderly/mailbox incident (5 pts)
        if any(word in full_text for word in ["elderly", "senior", "older"]) and \
           any(word in full_text for word in ["mailbox", "mail"]):
            evidence_points += 5
        elif any(word in full_text for word in ["elderly", "senior", "mailbox"]):
            evidence_points += 2
        
        score += evidence_points
        feedback_parts.append(f"Specific evidence: {evidence_points}/20 pts")

        # ===================================================================
        # CRITERION 4: Community Support (15 points)
        # ===================================================================
        community_points = 0
        
        # Check for "23 households" or similar
        has_23 = "23" in full_text or "twenty-three" in full_text or "twenty three" in full_text
        has_household = "household" in full_text or "families" in full_text or "family" in full_text or "resident" in full_text
        
        if has_23 and has_household:
            community_points += 7
        elif has_23:
            community_points += 3
        
        # Check for bold formatting on "23 households" or just "23"
        if check_text_formatting(doc, "23 households", bold=True):
            community_points += 5
        elif check_text_formatting(doc, "23", bold=True):
            community_points += 4
        
        # Check for signatures/support mention
        if any(word in full_text for word in ["signature", "support", "signed", "petition"]):
            community_points += 3
        
        score += community_points
        feedback_parts.append(f"Community support: {community_points}/15 pts")

        # ===================================================================
        # CRITERION 5: Solutions Section (15 points)
        # ===================================================================
        solutions_points = 0
        
        # Check for list items (bullets or numbers)
        has_list = False
        list_count = 0
        for para in doc.paragraphs:
            # Check if paragraph is part of a list style
            if para.style.name and ('List' in para.style.name or 'list' in para.style.name.lower()):
                has_list = True
                if para.text.strip():
                    list_count += 1
            # Also check for manual bullets
            elif para.text.strip().startswith('•') or para.text.strip().startswith('-'):
                has_list = True
                list_count += 1
            # Check for numbered lists
            elif re.match(r'^\d+[\.\)]\s+', para.text.strip()):
                has_list = True
                list_count += 1
        
        if has_list:
            solutions_points += 5
        
        # Count distinct solution mentions
        has_speed_bumps = "speed bump" in full_text or "speed hump" in full_text or "bump" in full_text
        has_signage = ("sign" in full_text or "signage" in full_text) and \
                      any(word in full_text for word in ["enhanced", "warning", "children", "feedback", "speed"])
        has_third_solution = any(word in full_text for word in [
            "crosswalk", "enforcement", "patrol", "camera", "radar", "study", "traffic study"
        ])
        
        solution_count = sum([has_speed_bumps, has_signage, has_third_solution])
        
        if solution_count >= 3:
            solutions_points += 10
        elif solution_count == 2:
            solutions_points += 6
        elif solution_count == 1:
            solutions_points += 3
        
        score += solutions_points
        feedback_parts.append(f"Solutions: {solutions_points}/15 pts ({solution_count} distinct solutions)")

        # ===================================================================
        # CRITERION 6: Professional Closing (10 points)
        # ===================================================================
        closing_points = 0
        
        # Check for respectful/professional tone
        if any(word in full_text for word in ["respectfully", "urge", "request", "ask"]):
            closing_points += 3
        
        # Check for email (contains @)
        if "@" in full_text:
            closing_points += 3
        
        # Check for phone number (various formats)
        if re.search(r'\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}', full_text):
            closing_points += 4
        elif any(pattern in full_text for pattern in ["555", "phone:", "call:", "contact:"]):
            closing_points += 2
        
        score += closing_points
        feedback_parts.append(f"Closing: {closing_points}/10 pts")

        # ===================================================================
        # FINAL SCORING
        # ===================================================================
        passed = score >= 70
        normalized_score = score / 100.0
        
        # Create comprehensive feedback
        summary = f"Score: {score}/100 points. "
        if passed:
            summary += "✅ PASSED. "
        else:
            summary += "❌ FAILED. "
        
        summary += " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": normalized_score,
            "feedback": summary
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
