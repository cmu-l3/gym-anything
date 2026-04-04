#!/usr/bin/env python3
"""
Verifier for ADU Zoning Variance task (adu_zoning_variance@1)

Checks that a professional zoning variance application has been properly formatted
from messy notes into a government-ready submission document.
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
    parse_docx_file,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_adu_zoning_variance(traj, env_info, task_info):
    """
    Verify that zoning variance application document is properly formatted.
    
    Verification Criteria:
    1. Title exists and is formatted correctly (bold, centered) - 15 points
    2. Property address and parcel number present - 10 points
    3. Variance type clearly stated - 10 points
    4. Two tables exist (property details + neighbor support) - 20 points
    5. Required section headers present - 15 points
    6. Justification content comprehensive - 15 points
    7. Neighbor support data documented - 10 points
    8. Professional formatting (bold headers) - 5 points
    
    Pass threshold: 70/100 points
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Copy function not available"
        }
    
    container_path = "/home/ga/Documents/TextDocuments/zoning_variance_application.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_variance_')
    
    try:
        # Copy and parse document
        success, doc, error = copy_and_parse_document(
            container_path, 
            copy_from_env, 
            file_format='docx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to parse document: {error}"
            }
        
        # Check if document is just the starter template (basically empty)
        full_text = get_document_text(doc)
        if len(full_text.strip()) < 200:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": "Document appears to be mostly empty. Please create the variance application from the notes provided."
            }
        
        # Extract full text for content checks
        full_text_lower = full_text.lower()
        
        # Scoring criteria
        score = 0.0
        max_score = 100.0
        feedback_parts = []
        
        # ============================================================
        # CRITERION 1: Title exists and is formatted (15 points)
        # ============================================================
        title_found = False
        title_formatted = False
        title_paragraph = None
        
        for para in doc.paragraphs:
            para_text_lower = para.text.lower()
            if "application" in para_text_lower and "zoning" in para_text_lower and "variance" in para_text_lower:
                title_found = True
                title_paragraph = para
                
                # Check if centered
                is_centered = (para.alignment == 1)  # WD_ALIGN_PARAGRAPH.CENTER
                
                # Check if any run is bold
                has_bold = False
                for run in para.runs:
                    if run.bold:
                        has_bold = True
                        break
                
                if is_centered or has_bold:
                    title_formatted = True
                break
        
        if title_found and title_formatted:
            score += 15
            feedback_parts.append("✅ Title present and formatted correctly")
        elif title_found:
            score += 7
            feedback_parts.append("⚠️ Title present but not properly formatted (should be bold and/or centered)")
        else:
            feedback_parts.append("❌ Title 'APPLICATION FOR ZONING VARIANCE' not found")
        
        # ============================================================
        # CRITERION 2: Property address and parcel (10 points)
        # ============================================================
        address_found = "457 maple" in full_text_lower or ("457" in full_text and "maple" in full_text_lower)
        parcel_found = "45-2891-023" in full_text or "452891023" in full_text.replace("-", "").replace(" ", "")
        
        if address_found and parcel_found:
            score += 10
            feedback_parts.append("✅ Property address and parcel number included")
        elif address_found or parcel_found:
            score += 5
            if not address_found:
                feedback_parts.append("⚠️ Property address (457 Maple Street) not found")
            if not parcel_found:
                feedback_parts.append("⚠️ Parcel number (45-2891-023) not found")
        else:
            feedback_parts.append("❌ Property address and parcel number not found")
        
        # ============================================================
        # CRITERION 3: Variance type mentioned (10 points)
        # ============================================================
        variance_keywords = [
            "rear setback" in full_text_lower,
            "setback variance" in full_text_lower,
            "setback reduction" in full_text_lower,
            ("2 feet" in full_text_lower or "2 ft" in full_text_lower or "two feet" in full_text_lower)
        ]
        variance_found = any(variance_keywords)
        
        if variance_found:
            score += 10
            feedback_parts.append("✅ Variance type clearly stated (rear setback/2 feet)")
        else:
            feedback_parts.append("❌ Variance type (rear setback reduction/2 feet) not clearly stated")
        
        # ============================================================
        # CRITERION 4: Tables exist (20 points)
        # ============================================================
        table_count = count_tables(doc)
        
        if table_count >= 2:
            score += 20
            feedback_parts.append(f"✅ Required tables present ({table_count} tables found)")
        elif table_count == 1:
            score += 10
            feedback_parts.append("⚠️ Only 1 table found (need 2: property details + neighbor support)")
        else:
            feedback_parts.append("❌ No tables found (need 2: property details + neighbor support)")
        
        # ============================================================
        # CRITERION 5: Section headers present (15 points)
        # ============================================================
        section_checks = {
            "property": "property detail" in full_text_lower or "property info" in full_text_lower,
            "justification": "justification" in full_text_lower or "reasons" in full_text_lower or "rationale" in full_text_lower,
            "neighbor": "neighbor" in full_text_lower or "adjacent" in full_text_lower
        }
        
        sections_found = sum(section_checks.values())
        section_score = (sections_found / len(section_checks)) * 15
        score += section_score
        
        if sections_found == len(section_checks):
            feedback_parts.append("✅ All required section headers present")
        else:
            missing = len(section_checks) - sections_found
            feedback_parts.append(f"⚠️ Missing {missing} required section headers (property/justification/neighbor)")
        
        # ============================================================
        # CRITERION 6: Justification content (15 points)
        # ============================================================
        justification_elements = {
            "hardship": any(kw in full_text_lower for kw in ["hardship", "necessity", "mother", "elderly", "aging", "family"]),
            "impact": any(kw in full_text_lower for kw in ["minimal impact", "neighbors", "existing", "mature", "hedge", "privacy"]),
            "intent": any(kw in full_text_lower for kw in ["intent", "character", "consistent", "purpose", "spirit"])
        }
        
        justification_found = sum(justification_elements.values())
        justification_score = (justification_found / len(justification_elements)) * 15
        score += justification_score
        
        if justification_found >= 3:
            feedback_parts.append("✅ Comprehensive justification with all three required elements")
        elif justification_found >= 2:
            feedback_parts.append("⚠️ Justification present but missing some required elements (hardship/impact/intent)")
        else:
            feedback_parts.append("❌ Justification incomplete or missing key arguments")
        
        # ============================================================
        # CRITERION 7: Neighbor support data (10 points)
        # ============================================================
        # Check for neighbor addresses
        neighbor_addresses = ["455", "459", "456", "458", "454", "460"]
        neighbors_mentioned = sum(1 for addr in neighbor_addresses if addr in full_text)
        
        # Check for support indicators
        support_keywords = ["yes", "support", "written", "verbal", "approve", "favor"]
        support_mentions = sum(1 for kw in support_keywords if kw in full_text_lower)
        
        # Check for family names
        family_names = ["johnson", "patel", "chen", "martinez", "thompson", "wilson"]
        families_mentioned = sum(1 for name in family_names if name in full_text_lower)
        
        neighbor_score = 0
        if neighbors_mentioned >= 5 and (support_mentions >= 3 or families_mentioned >= 3):
            neighbor_score = 10
            feedback_parts.append("✅ Neighbor support documented with addresses and responses")
        elif neighbors_mentioned >= 3:
            neighbor_score = 5
            feedback_parts.append("⚠️ Some neighbor information present but incomplete")
        else:
            feedback_parts.append("❌ Neighbor support documentation missing or inadequate")
        
        score += neighbor_score
        
        # ============================================================
        # CRITERION 8: Professional formatting (5 points)
        # ============================================================
        # Check if section headers are bold
        bold_headers_found = False
        for para in doc.paragraphs:
            para_text_lower = para.text.lower()
            # Check if it looks like a header
            if any(section in para_text_lower for section in ["property", "justification", "neighbor", "hardship", "impact", "support"]):
                # Check if it's bold
                for run in para.runs:
                    if run.bold and len(run.text.strip()) > 3:
                        bold_headers_found = True
                        break
                if bold_headers_found:
                    break
        
        if bold_headers_found:
            score += 5
            feedback_parts.append("✅ Professional formatting with bold headers")
        else:
            feedback_parts.append("⚠️ Section headers should be bold for professional appearance")
        
        # ============================================================
        # Additional checks for edge cases
        # ============================================================
        
        # Check if the document has reasonable length
        if len(full_text) < 500:
            feedback_parts.append("⚠️ Document seems quite short for a formal application")
        
        # Check if key measurements are included
        measurements_check = ("4 feet" in full_text_lower or "4 ft" in full_text_lower) and \
                            ("6 feet" in full_text_lower or "6 ft" in full_text_lower)
        if not measurements_check:
            feedback_parts.append("⚠️ Consider including specific setback measurements (4 feet existing, 6 feet required)")
        
        # ============================================================
        # Determine pass/fail
        # ============================================================
        passed = score >= 70.0
        
        # Create final feedback
        feedback = " | ".join(feedback_parts)
        feedback += f"\n\n📊 Final Score: {score:.1f}/{max_score}"
        
        if passed:
            feedback += "\n✅ PASS: Document meets professional standards for zoning board submission"
        else:
            feedback += "\n❌ FAIL: Document needs improvement before submission"
            feedback += "\n\nKey areas to address:"
            if score < 30:
                feedback += "\n  - Ensure document has proper title and structure"
                feedback += "\n  - Include all required information from notes file"
            elif score < 50:
                feedback += "\n  - Add or complete required tables"
                feedback += "\n  - Expand justification sections"
            else:
                feedback += "\n  - Polish formatting (bold headers, centered title)"
                feedback += "\n  - Ensure all neighbor data is included"
        
        return {
            "passed": passed,
            "score": score / max_score,
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
