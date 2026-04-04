#!/usr/bin/env python3
"""
Verifier for tenant_complaint_letter@1

Checks if the formal complaint letter meets all requirements:
- Proper business letter format (addresses, date, salutation)
- Timeline documentation table with 4+ rows
- Required phrases and formatting (bold, underline)
- Professional structure and closing
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


def verify_complaint_letter(traj, env_info, task_info):
    """
    Verify the tenant complaint letter meets all requirements.
    
    Scoring breakdown (10 criteria, each worth 1 point):
    1. Tenant address present (427 Oak Street)
    2. Landlord address present (Mr. Robert Chen)
    3. Formal salutation (Dear Mr. Chen)
    4. "Formal notice" phrase with bold formatting
    5. Timeline table with 4+ rows
    6. Heating issue documented
    7. Deadline with formatting emphasis
    8. Professional closing with name
    9. Legal/tenant rights reference
    10. Good document structure
    
    Pass threshold: 70% (7/10 points)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "Copy function not available in environment"
        }

    container_path = "/home/ga/Documents/TextDocuments/complaint_letter.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_complaint_')

    try:
        # Parse document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to parse document: {error}. Ensure document was saved properly."
            }
        
        feedback_parts = []
        score = 0.0
        max_score = 10.0
        
        # Get full document text
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        logger.info(f"Document length: {len(full_text)} characters")
        logger.info(f"Document preview (first 300 chars): {full_text[:300]}")
        
        # Basic document content check
        if len(full_text) < 100:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Document is too short ({len(full_text)} chars). Expected detailed complaint letter with addresses, table, and multiple paragraphs."
            }
        
        # ============================================================
        # Criterion 1: Tenant address (427 Oak Street, Apt 3B)
        # ============================================================
        has_tenant_address = False
        if "427" in full_text and "oak" in full_text_lower:
            if "street" in full_text_lower or "st" in full_text_lower:
                has_tenant_address = True
                score += 1.0
                feedback_parts.append("✅ Tenant address present (427 Oak Street)")
        
        if not has_tenant_address:
            feedback_parts.append("❌ Missing tenant address (should include: 427 Oak Street, Apt 3B, Portland, OR 97214)")
        
        # ============================================================
        # Criterion 2: Landlord address (Mr. Robert Chen, 1550)
        # ============================================================
        has_landlord_address = False
        has_chen = "chen" in full_text_lower
        has_robert = "robert" in full_text_lower
        has_property_mgmt = "1550" in full_text or "property management" in full_text_lower
        
        if has_chen and (has_robert or has_property_mgmt):
            has_landlord_address = True
            score += 1.0
            feedback_parts.append("✅ Landlord address present (Mr. Robert Chen / 1550 Property Management)")
        
        if not has_landlord_address:
            feedback_parts.append("❌ Missing complete landlord address (should include: Mr. Robert Chen, 1550 Property Management LLC)")
        
        # ============================================================
        # Criterion 3: Formal salutation (Dear Mr. Chen)
        # ============================================================
        has_salutation = False
        salutation_patterns = [
            r"dear\s+mr\.?\s+chen",
            r"dear\s+robert\s+chen"
        ]
        
        for pattern in salutation_patterns:
            if re.search(pattern, full_text_lower):
                has_salutation = True
                break
        
        if has_salutation:
            score += 1.0
            feedback_parts.append("✅ Proper formal salutation (Dear Mr. Chen)")
        else:
            feedback_parts.append("❌ Missing formal salutation (should be: Dear Mr. Chen,)")
        
        # ============================================================
        # Criterion 4: "Formal notice" phrase with bold formatting
        # ============================================================
        has_formal_notice_text = ("formal" in full_text_lower and "notice" in full_text_lower) or \
                                 ("formal" in full_text_lower and "written" in full_text_lower)
        
        formal_notice_bold = False
        if has_formal_notice_text:
            # Check if any of these key words are bolded
            formal_notice_bold = (check_text_formatting(doc, "formal", bold=True) or 
                                 check_text_formatting(doc, "notice", bold=True) or
                                 check_text_formatting(doc, "written notice", bold=True))
        
        if has_formal_notice_text and formal_notice_bold:
            score += 1.0
            feedback_parts.append("✅ 'Formal written notice' phrase present and properly bolded")
        elif has_formal_notice_text:
            score += 0.5
            feedback_parts.append("⚠️  'Formal notice' phrase present but not bolded (should be bold for emphasis)")
        else:
            feedback_parts.append("❌ Missing 'formal written notice' phrase in opening paragraph")
        
        # ============================================================
        # Criterion 5: Timeline table with 4+ rows
        # ============================================================
        num_tables = count_tables(doc)
        has_good_table = False
        
        if num_tables > 0:
            table = doc.tables[0]
            num_rows = len(table.rows)
            
            logger.info(f"Table found with {num_rows} rows")
            
            # Extract table text for content checking
            table_text = ""
            for row in table.rows:
                row_text = []
                for cell in row.cells:
                    row_text.append(cell.text)
                table_text += " ".join(row_text) + "\n"
            
            table_text_lower = table_text.lower()
            logger.info(f"Table content preview: {table_text[:200]}")
            
            # Check for timeline keywords
            has_dates = any(month in table_text_lower for month in ["jan", "january", "1/", "01/"]) or \
                       any(str(i) in table_text for i in range(1, 32))
            has_contact_methods = any(method in table_text_lower for method in 
                                     ["phone", "text", "email", "call", "message", "in-person", "in person", "visit"])
            has_response_col = any(resp in table_text_lower for resp in 
                                  ["no answer", "no response", "no reply", "response", "answer", "reply", "none"])
            
            if num_rows >= 4:
                if has_dates and has_contact_methods:
                    has_good_table = True
                    score += 1.5
                    feedback_parts.append(f"✅ Timeline table present with {num_rows} rows and proper content (dates, contact methods)")
                else:
                    score += 1.0
                    feedback_parts.append(f"⚠️  Table present with {num_rows} rows but missing clear dates or contact methods")
            elif num_rows >= 2:
                score += 0.5
                feedback_parts.append(f"⚠️  Table present but only {num_rows} rows (need at least 4: header + 3+ contact attempts)")
            else:
                feedback_parts.append(f"❌ Table too small ({num_rows} row) - need header + 4+ data rows")
        else:
            feedback_parts.append("❌ Missing timeline documentation table (should show Date | Contact Method | Response)")
        
        # ============================================================
        # Criterion 6: Heating issue mentioned
        # ============================================================
        heating_keywords = ["heat", "heating", "heater", "hvac", "temperature", "cold", "freezing"]
        has_heating_mention = any(keyword in full_text_lower for keyword in heating_keywords)
        
        if has_heating_mention:
            score += 1.0
            feedback_parts.append("✅ Heating system failure documented")
        else:
            feedback_parts.append("❌ Missing mention of heating/heater issue (core complaint)")
        
        # ============================================================
        # Criterion 7: Deadline with formatting emphasis
        # ============================================================
        deadline_keywords = ["72 hours", "72-hours", "three days", "deadline", "within", "immediately", "urgent"]
        has_deadline_text = any(keyword in full_text_lower for keyword in deadline_keywords) or \
                           re.search(r'\b72\b', full_text)
        
        deadline_formatted = False
        if has_deadline_text:
            # Check if deadline-related words have bold or underline formatting
            deadline_check_words = ["72", "hours", "deadline", "immediately", "urgent", "within"]
            for word in deadline_check_words:
                if word in full_text_lower or word in full_text:
                    if check_text_formatting(doc, word, bold=True) or \
                       check_text_formatting(doc, word, underline=True):
                        deadline_formatted = True
                        break
        
        if has_deadline_text and deadline_formatted:
            score += 1.0
            feedback_parts.append("✅ Clear deadline present with emphasis (bold/underline)")
        elif has_deadline_text:
            score += 0.5
            feedback_parts.append("⚠️  Deadline mentioned but not emphasized with bold/underline formatting")
        else:
            feedback_parts.append("❌ Missing clear deadline for repair (should specify: within 72 hours, bold + underlined)")
        
        # ============================================================
        # Criterion 8: Professional closing with name (Jessica Martinez)
        # ============================================================
        closing_phrases = ["sincerely", "respectfully", "regards", "yours truly"]
        has_closing = any(phrase in full_text_lower for phrase in closing_phrases)
        
        has_name = "jessica" in full_text_lower or "martinez" in full_text_lower
        
        if has_closing and has_name:
            score += 1.0
            feedback_parts.append("✅ Professional closing with signature (Jessica Martinez)")
        elif has_closing or has_name:
            score += 0.5
            feedback_parts.append("⚠️  Partial closing (missing signature name 'Jessica Martinez' or closing phrase like 'Sincerely,')")
        else:
            feedback_parts.append("❌ Missing professional closing with your name (should end with: Sincerely, Jessica Martinez, (503) 555-0147)")
        
        # ============================================================
        # Criterion 9: Legal/tenant rights reference
        # ============================================================
        legal_keywords = ["tenant rights", "landlord", "tenant act", "housing", "legal", 
                         "code", "law", "residential", "oregon", "authority", "violation"]
        has_legal_reference = sum(1 for keyword in legal_keywords if keyword in full_text_lower) >= 2
        
        if has_legal_reference:
            score += 1.0
            feedback_parts.append("✅ Legal/tenant rights context included (strengthens letter)")
        else:
            score += 0.5
            feedback_parts.append("⚠️  Could strengthen with explicit tenant rights reference (e.g., Oregon Residential Landlord-Tenant Act)")
        
        # ============================================================
        # Criterion 10: Document structure and length
        # ============================================================
        num_paragraphs = len([p for p in doc.paragraphs if p.text.strip() and len(p.text.strip()) > 10])
        
        logger.info(f"Document has {num_paragraphs} substantial paragraphs")
        
        has_good_structure = False
        if num_paragraphs >= 4 and len(full_text) >= 400:
            has_good_structure = True
            score += 1.0
            feedback_parts.append(f"✅ Document well-structured ({num_paragraphs} paragraphs, {len(full_text)} characters)")
        elif num_paragraphs >= 3 and len(full_text) >= 250:
            score += 0.5
            feedback_parts.append(f"⚠️  Document structure adequate but could be more detailed ({num_paragraphs} paragraphs, {len(full_text)} chars)")
        else:
            feedback_parts.append(f"❌ Document too short or poorly structured ({num_paragraphs} paragraphs, {len(full_text)} chars). Need at least 4 substantial paragraphs.")
        
        # ============================================================
        # Calculate final score and determine pass/fail
        # ============================================================
        score_ratio = score / max_score
        passed = score_ratio >= 0.70  # Need 70% to pass (7/10 points)
        
        # Build final feedback
        feedback = " | ".join(feedback_parts)
        feedback += f" || TOTAL SCORE: {score:.1f}/{max_score} ({score_ratio*100:.0f}%)"
        
        if passed:
            feedback += " || ✅ PASSED - Complaint letter meets requirements"
        else:
            feedback += f" || ❌ FAILED - Need {0.70*max_score:.1f} points to pass"
        
        logger.info(f"Verification complete: {score:.1f}/{max_score} - {'PASS' if passed else 'FAIL'}")
        
        return {
            "passed": passed,
            "score": score_ratio,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"Verification error: {str(e)}. Check that document was saved properly and is not corrupted."
        }
    
    finally:
        cleanup_temp_dir(temp_dir)
