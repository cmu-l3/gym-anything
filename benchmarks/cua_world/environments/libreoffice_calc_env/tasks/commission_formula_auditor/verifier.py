#!/usr/bin/env python3
"""
Verifier for Commission Formula Auditor task.

Checks that the agent:
1. Identified the error in cell C2 (commission formula)
2. Documented the error in cell F1 or added a comment
3. Explained the nature of the error (missing base commission)
4. (Bonus) Corrected the formula
"""

import sys
import os
import logging
import re
import zipfile
from xml.etree import ElementTree as ET

# Add utils to path - use relative path since verification runs on host
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    copy_and_parse_spreadsheet,
    get_cell_value,
    get_cell_formula,
    cleanup_verification_temp
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_cell_comment(filepath, sheet_name, cell_ref):
    """
    Extract comment text from a specific cell in an ODS file.
    
    Args:
        filepath: Path to ODS file
        sheet_name: Name of the sheet
        cell_ref: Cell reference (e.g., "C2")
        
    Returns:
        Comment text or None if no comment exists
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return None
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Define namespaces
            namespaces = {
                'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
                'office-annotation': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'
            }
            
            # Find the sheet
            tables = root.findall('.//table:table', namespaces)
            target_table = None
            for table in tables:
                if table.get('{urn:oasis:names:tc:opendocument:xmlns:table:1.0}name') == sheet_name:
                    target_table = table
                    break
            
            if target_table is None:
                return None
            
            # Parse cell reference (e.g., "C2" -> column 2, row 1 in 0-indexed)
            col_str = ''.join(c for c in cell_ref if c.isalpha()).upper()
            row_str = ''.join(c for c in cell_ref if c.isdigit())
            
            col_idx = 0
            for char in col_str:
                col_idx = col_idx * 26 + (ord(char) - ord('A') + 1)
            col_idx -= 1
            row_idx = int(row_str) - 1
            
            # Navigate to the cell
            rows = target_table.findall('.//table:table-row', namespaces)
            if row_idx >= len(rows):
                return None
            
            target_row = rows[row_idx]
            cells = target_row.findall('.//table:table-cell', namespaces)
            
            if col_idx >= len(cells):
                return None
            
            target_cell = cells[col_idx]
            
            # Look for annotation (comment) in the cell
            annotations = target_cell.findall('.//office:annotation', namespaces)
            if not annotations:
                return None
            
            # Extract text from annotation
            comment_texts = []
            for annotation in annotations:
                paragraphs = annotation.findall('.//text:p', namespaces)
                for p in paragraphs:
                    text_content = ''.join(p.itertext())
                    if text_content:
                        comment_texts.append(text_content)
            
            return ' '.join(comment_texts) if comment_texts else None
    
    except Exception as e:
        logger.debug(f"Error extracting comment: {e}")
        return None


def verify_commission_auditor(traj, env_info, task_info):
    """
    Verify commission formula auditor task completion.
    
    Checks:
    1. Error localization: Identified C2 or "commission formula" as problematic
    2. Error explanation: Mentioned missing base commission or tiered calculation issue
    3. Status documentation: Cell F1 contains audit findings
    4. Formula correction (bonus): C2 formula fixed to implement policy correctly
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Copy and parse spreadsheet
    container_path = "/home/ga/Documents/commission_data.ods"
    success, workbook, error, temp_dir = copy_and_parse_spreadsheet(
        container_path,
        copy_from_env,
        file_format='ods'
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}

    try:
        # Get first sheet
        sheet_name = list(workbook['sheets'].keys())[0]
        filepath = workbook['filepath']

        score = 0
        feedback_parts = []
        
        # Check 1: Status cell documentation (25 points)
        status_cell = get_cell_value(workbook, sheet_name, 'F1')
        status_text = str(status_cell).upper() if status_cell else ""
        
        # Remove the default text to see if user added anything
        default_text = "AUDIT STATUS - ENTER FINDINGS HERE"
        if default_text in status_text:
            status_text = status_text.replace(default_text, "").strip()
        
        error_keywords = ['ERROR', 'WRONG', 'INCORRECT', 'MISSING', 'C2', 'BUG', 'ISSUE', 'PROBLEM']
        status_has_finding = any(keyword in status_text for keyword in error_keywords) and len(status_text) > 5
        
        if status_has_finding:
            score += 25
            feedback_parts.append("✅ Status cell (F1) documents issue")
            logger.info(f"Status cell content: {status_text[:100]}")
        else:
            feedback_parts.append("❌ Status cell (F1) not updated with findings")
        
        # Check 2: Error localization - mentions C2 or commission formula (25 points)
        c2_in_status = 'C2' in status_text or 'COMMISSION' in status_text or 'FORMULA' in status_text
        
        # Check for comment on C2
        c2_comment = extract_cell_comment(filepath, sheet_name, 'C2')
        c2_comment_text = c2_comment.upper() if c2_comment else ""
        has_c2_comment = c2_comment is not None and len(c2_comment) > 5
        
        if c2_in_status or has_c2_comment:
            score += 25
            if has_c2_comment:
                feedback_parts.append("✅ Error localized: Comment added to C2")
                logger.info(f"C2 comment: {c2_comment[:100]}")
            else:
                feedback_parts.append("✅ Error localized: C2 mentioned in status")
        else:
            feedback_parts.append("❌ Error not clearly localized to C2")
        
        # Check 3: Error explanation quality (25 points)
        # Look for keywords indicating understanding of the tiered commission issue
        explanation_keywords = [
            'BASE', 'FIRST', '10000', '10,000', 'TIER', 'BRACKET', 
            '5%', 'MISSING', 'FORGET', 'ONLY', 'EXCESS'
        ]
        
        combined_text = status_text + " " + c2_comment_text
        explanation_quality = sum(1 for kw in explanation_keywords if kw in combined_text)
        
        if explanation_quality >= 2:
            score += 25
            feedback_parts.append("✅ Error explanation shows understanding of tiered commission issue")
        elif explanation_quality >= 1:
            score += 15
            feedback_parts.append("⚠️ Basic error explanation provided")
        else:
            feedback_parts.append("❌ Error not adequately explained")
        
        # Check 4: Formula correction (25 points bonus)
        c2_formula = get_cell_formula(workbook, sheet_name, 'C2')
        c2_value = get_cell_value(workbook, sheet_name, 'C2')
        
        formula_corrected = False
        if c2_formula:
            # Normalize formula for comparison (remove spaces, case-insensitive)
            normalized_formula = c2_formula.replace(' ', '').upper()
            
            # Check if formula contains the correct pattern:
            # Should have: 10000*0.05 (base) AND (B2-10000)*0.07 (excess)
            has_base = '10000*0.05' in normalized_formula or '10000*.05' in normalized_formula
            has_excess = '(B2-10000)*0.07' in normalized_formula or '(B2-10000)*.07' in normalized_formula
            
            if has_base and has_excess:
                formula_corrected = True
                score += 25
                feedback_parts.append("✅ BONUS: Formula corrected to implement policy correctly")
                
                # Verify calculated value is now correct (~850 for Alice's $15,000)
                if c2_value:
                    try:
                        value_float = float(c2_value)
                        if abs(value_float - 850) < 1.0:
                            feedback_parts.append(f"✅ Commission value now correct: ${value_float:.2f}")
                        else:
                            feedback_parts.append(f"⚠️ Formula changed but value unexpected: ${value_float:.2f} (expected ~$850)")
                    except (ValueError, TypeError):
                        pass
            else:
                logger.info(f"Formula not fully corrected. Has base: {has_base}, Has excess: {has_excess}")
                logger.info(f"Formula: {normalized_formula}")
        
        # Ensure score doesn't exceed 100
        score = min(score, 100)
        
        # Task passes if score >= 75 (need at least 3 out of 4 criteria)
        passed = score >= 75
        
        # Add overall assessment
        if passed and formula_corrected:
            feedback_parts.insert(0, "🎉 Excellent audit work! Error identified, explained, and corrected")
        elif passed:
            feedback_parts.insert(0, "✅ Good audit: Error identified and documented")
        else:
            feedback_parts.insert(0, "❌ Audit incomplete: Error not adequately identified or documented")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "status_documented": status_has_finding,
                "error_localized": c2_in_status or has_c2_comment,
                "error_explained": explanation_quality >= 2,
                "formula_corrected": formula_corrected
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }

    finally:
        cleanup_verification_temp(temp_dir)
