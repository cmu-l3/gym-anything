#!/usr/bin/env python3
"""
Verifier for medication_reference_sheet@1
Checks document structure, table presence, warnings, and formatting
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


def verify_medication_reference(traj, env_info, task_info):
    """
    Verify medication reference document has:
    1. Proper title with formatting (Margaret Chen, Medication Reference)
    2. Table with medication information
    3. All 5 required medications present
    4. Bold warnings about grapefruit and empty stomach
    5. Warnings section with heading
    6. Emergency contact section
    
    Scoring breakdown (100 points):
    - Title present and formatted: 15 points
    - Table exists: 15 points
    - All 5 medications in table: 25 points (5 each)
    - Grapefruit warning (bold): 15 points
    - Empty stomach warning: 10 points
    - Warnings section heading (bold): 10 points
    - Emergency contacts: 10 points
    
    Pass threshold: 70 points
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    doc_path = "/home/ga/Documents/TextDocuments/medication_reference.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_med_')
    
    feedback_parts = []
    score = 0
    max_score = 100
    
    try:
        # Copy and parse document
        success, doc, error = copy_and_parse_document(
            doc_path, 
            copy_from_env, 
            'docx'
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to parse document: {error}"
            }
        
        # Get full document text for content checking
        full_text = get_document_text(doc).lower()
        
        # === CRITERION 1: Title present and contains required text (15 points) ===
        has_med_reference = "medication reference" in full_text
        has_patient_name = "margaret chen" in full_text or "margaret" in full_text
        
        if has_med_reference and has_patient_name:
            score += 15
            feedback_parts.append("✅ Title includes 'Medication Reference' and patient name")
        elif has_med_reference or has_patient_name:
            score += 8
            feedback_parts.append("⚠️ Title partially present (missing 'Medication Reference' or 'Margaret Chen')")
        else:
            feedback_parts.append("❌ Missing proper title ('Medication Reference - Margaret Chen')")
        
        # === CRITERION 2: Table exists (15 points) ===
        table_count = count_tables(doc)
        table_text = ""
        
        if table_count >= 1:
            score += 15
            feedback_parts.append(f"✅ Document contains table ({table_count} found)")
            
            # Extract table text for medication checking
            try:
                table = doc.tables[0]
                for row in table.rows:
                    for cell in row.cells:
                        table_text += " " + cell.text.lower()
            except Exception as e:
                logger.warning(f"Could not extract table text: {e}")
        else:
            feedback_parts.append("❌ No table found - medications should be in a table")
            # If no table, check if medications are at least mentioned in text
            table_text = full_text
        
        # === CRITERION 3: Required medications present (25 points - 5 each) ===
        required_meds = {
            "metformin": ["metformin"],
            "lisinopril": ["lisinopril"],
            "atorvastatin": ["atorvastatin"],
            "levothyroxine": ["levothyroxine"],
            "aspirin": ["aspirin"]
        }
        
        meds_found = []
        meds_missing = []
        
        # Check in table text first (preferred), then full document
        search_text = table_text if table_text else full_text
        
        for med_key, med_variants in required_meds.items():
            found = any(variant in search_text for variant in med_variants)
            if found:
                meds_found.append(med_key)
                score += 5
            else:
                meds_missing.append(med_key)
        
        if len(meds_found) == 5:
            feedback_parts.append("✅ All 5 required medications present")
        elif len(meds_found) >= 3:
            feedback_parts.append(f"⚠️ Found {len(meds_found)}/5 medications (missing: {', '.join(meds_missing)})")
        else:
            feedback_parts.append(f"❌ Only {len(meds_found)}/5 medications found (missing: {', '.join(meds_missing)})")
        
        # === CRITERION 4: Grapefruit warning (15 points) ===
        has_grapefruit_mention = "grapefruit" in full_text
        
        if has_grapefruit_mention:
            # Check if warning is bold or emphasized
            grapefruit_bold = (
                check_text_formatting(doc, "grapefruit", bold=True) or
                check_text_formatting(doc, "no grapefruit", bold=True) or
                check_text_formatting(doc, "avoid grapefruit", bold=True) or
                check_text_formatting(doc, "do not", bold=True)
            )
            
            # Check for warning language
            has_warning_language = any(phrase in full_text for phrase in [
                "no grapefruit", "avoid grapefruit", "do not consume grapefruit",
                "don't eat grapefruit", "dangerous"
            ])
            
            if grapefruit_bold or has_warning_language:
                score += 15
                feedback_parts.append("✅ Grapefruit interaction warning present and emphasized")
            else:
                score += 8
                feedback_parts.append("⚠️ Grapefruit mentioned but warning not sufficiently emphasized")
        else:
            feedback_parts.append("❌ Missing critical grapefruit interaction warning")
        
        # === CRITERION 5: Empty stomach warning for Levothyroxine (10 points) ===
        empty_stomach_patterns = [
            "empty stomach",
            "before breakfast",
            "before eating",
            "without food",
            "on an empty stomach"
        ]
        
        has_empty_stomach_warning = any(pattern in full_text for pattern in empty_stomach_patterns)
        
        if has_empty_stomach_warning:
            score += 10
            feedback_parts.append("✅ Empty stomach instruction for Levothyroxine present")
        else:
            feedback_parts.append("❌ Missing empty stomach instruction for Levothyroxine")
        
        # === CRITERION 6: Warnings section heading (10 points) ===
        warning_heading_patterns = [
            "important warning",
            "warning",
            "critical warning",
            "drug interaction",
            "caution"
        ]
        
        has_warning_section = any(pattern in full_text for pattern in warning_heading_patterns)
        
        if has_warning_section:
            # Check for bold heading
            has_bold_heading = (
                check_text_formatting(doc, "warning", bold=True) or
                check_text_formatting(doc, "important", bold=True) or
                check_text_formatting(doc, "caution", bold=True)
            )
            
            if has_bold_heading:
                score += 10
                feedback_parts.append("✅ Warnings section with bold heading present")
            else:
                score += 5
                feedback_parts.append("⚠️ Warning section present but heading not bold")
        else:
            feedback_parts.append("❌ No warnings section heading found")
        
        # === CRITERION 7: Emergency contacts (10 points) ===
        has_daughter = "sarah" in full_text or "daughter" in full_text
        has_pharmacist = "pharmacy" in full_text or "pharmacist" in full_text
        has_phone = "555" in full_text or "(" in full_text or "phone" in full_text or "contact" in full_text
        
        contact_score = sum([has_daughter, has_pharmacist, has_phone])
        
        if contact_score >= 2:
            score += 10
            feedback_parts.append("✅ Emergency contact information included")
        elif contact_score == 1:
            score += 5
            feedback_parts.append("⚠️ Partial emergency contact information present")
        else:
            feedback_parts.append("❌ Missing emergency contact information")
        
        # === DETERMINE PASS/FAIL ===
        passed = score >= 70  # Need 70% to pass
        normalized_score = score / max_score
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        feedback += f" | Final Score: {score}/{max_score}"
        
        return {
            "passed": passed,
            "score": normalized_score,
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


# Entry point for gym-anything
def verify_task(traj, env_info, task_info):
    """Entry point wrapper for gym-anything framework"""
    return verify_medication_reference(traj, env_info, task_info)