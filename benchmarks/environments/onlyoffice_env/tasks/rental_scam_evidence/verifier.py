#!/usr/bin/env python3
"""
Verifier for Rental Scam Evidence task

Verifies that the user created a properly structured fraud evidence report
with timeline, financial calculations, and next steps.
"""

import sys
import os
import re
import logging
import tempfile
from typing import Dict, Any, List, Tuple

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    check_text_formatting,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_dates_from_text(text: str) -> List[Tuple[int, str]]:
    """
    Extract dates from text and return as list of (day_number, original_match)
    
    Args:
        text: Text to search
        
    Returns:
        List of tuples (day, original_text)
    """
    text_lower = text.lower()
    dates = []
    
    # Pattern 1: "march 15", "march 16", etc.
    pattern1 = re.finditer(r'march\s+(\d{1,2})', text_lower)
    for match in pattern1:
        day = int(match.group(1))
        dates.append((day, match.group(0)))
    
    # Pattern 2: "3/15", "3/16", etc.
    pattern2 = re.finditer(r'3[/-](\d{1,2})', text_lower)
    for match in pattern2:
        day = int(match.group(1))
        dates.append((day, match.group(0)))
    
    # Pattern 3: "mar. 15", "mar 16", etc.
    pattern3 = re.finditer(r'mar\.?\s+(\d{1,2})', text_lower)
    for match in pattern3:
        day = int(match.group(1))
        dates.append((day, match.group(0)))
    
    return dates


def check_chronological_order(dates: List[Tuple[int, str]], window_size: int = 6) -> bool:
    """
    Check if dates are in chronological order
    
    Args:
        dates: List of (day, text) tuples
        window_size: Number of dates to check
        
    Returns:
        True if dates are in order
    """
    if len(dates) < 2:
        return False
    
    # Check first N dates
    check_dates = [d[0] for d in dates[:window_size]]
    
    # Allow for some flexibility - dates should generally increase or stay same
    for i in range(len(check_dates) - 1):
        if check_dates[i] > check_dates[i + 1]:
            # Allow small jumps backwards (e.g., if date mentioned in different context)
            if check_dates[i] - check_dates[i + 1] > 1:
                return False
    
    return True


def count_sections(doc: Any) -> Tuple[int, int]:
    """
    Count sections and bold headers in document
    
    Args:
        doc: Document object
        
    Returns:
        Tuple of (total_sections, bold_headers)
    """
    section_count = 0
    bold_header_count = 0
    
    # Keywords that indicate section headers
    section_keywords = [
        'timeline', 'evidence', 'financial', 'loss', 'contact', 
        'next steps', 'action', 'scammer', 'case', 'header',
        'overview', 'summary', 'information', 'detail', 'calculation',
        'inventory', 'checklist', 'to do', 'follow up'
    ]
    
    for para in doc.paragraphs:
        text = para.text.strip()
        if not text or len(text) > 150:  # Skip empty or very long paragraphs
            continue
        
        text_lower = text.lower()
        
        # Check if paragraph has bold formatting
        has_bold = any(run.bold for run in para.runs if run.text.strip())
        
        # Check if it looks like a section header
        is_section = any(keyword in text_lower for keyword in section_keywords)
        
        # Also consider short lines with colons as headers (e.g., "Timeline:")
        looks_like_header = (len(text) < 50 and ':' in text) or (len(text) < 30)
        
        if has_bold and (is_section or looks_like_header):
            bold_header_count += 1
            section_count += 1
        elif is_section:
            section_count += 1
    
    return section_count, bold_header_count


def verify_rental_scam_evidence(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify rental scam evidence document
    
    Checks:
    - Document structure (sections, headers, formatting)
    - Content completeness (timeline, amounts, contact info)
    - Chronological order of events
    - Correct financial calculation
    - Next steps section
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "❌ Copy function not available in environment"
        }
    
    doc_path = "/home/ga/Documents/TextDocuments/rental_scam_evidence.docx"
    temp_dir = None
    
    try:
        temp_dir = tempfile.mkdtemp(prefix='rental_scam_verify_')
        
        # Parse document
        success, doc, error = copy_and_parse_document(doc_path, copy_from_env, 'docx')
        
        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Document not found or invalid: {error}"
            }
        
        score = 0
        feedback_parts = []
        max_score = 100
        
        # Extract full text
        full_text = get_document_text(doc)
        text_lower = full_text.lower()
        
        # Quick sanity check - document should have reasonable content
        if len(full_text.strip()) < 100:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Document is too short ({len(full_text)} chars). Expected structured report with multiple sections."
            }
        
        # ========== STRUCTURAL REQUIREMENTS (40 pts) ==========
        
        # Document exists (already verified)
        score += 10
        feedback_parts.append("✅ Document exists and is valid DOCX (10 pts)")
        
        # Count sections and headers
        section_count, bold_header_count = count_sections(doc)
        
        if section_count >= 5:
            score += 15
            feedback_parts.append(f"✅ Contains {section_count} distinct sections (15 pts)")
        elif section_count >= 3:
            partial = 10
            score += partial
            feedback_parts.append(f"⚠️ Contains {section_count} sections, expected 5+ (partial: {partial} pts)")
        else:
            feedback_parts.append(f"❌ Only {section_count} sections found, expected 5+ (0 pts)")
        
        if bold_header_count >= 3:
            score += 15
            feedback_parts.append(f"✅ At least 3 bold headers found ({bold_header_count} total, 15 pts)")
        elif bold_header_count >= 1:
            partial = 8
            score += partial
            feedback_parts.append(f"⚠️ {bold_header_count} bold header(s) found, expected 3+ (partial: {partial} pts)")
        else:
            feedback_parts.append(f"❌ No bold headers found (0 pts)")
        
        # ========== CONTENT REQUIREMENTS (35 pts) ==========
        
        # Extract dates
        dates_found = extract_dates_from_text(full_text)
        unique_dates = len(set(d[0] for d in dates_found))
        
        if unique_dates >= 5:
            score += 10
            feedback_parts.append(f"✅ Timeline with {unique_dates} dated events (10 pts)")
        elif unique_dates >= 3:
            partial = 6
            score += partial
            feedback_parts.append(f"⚠️ Timeline with {unique_dates} dated events, expected 5+ (partial: {partial} pts)")
        else:
            feedback_parts.append(f"❌ Only {unique_dates} dated events found, expected 5+ (0 pts)")
        
        # Check chronological order
        if len(dates_found) >= 3:
            is_chronological = check_chronological_order(dates_found)
            
            if is_chronological:
                score += 10
                feedback_parts.append("✅ Events in chronological order (10 pts)")
            else:
                feedback_parts.append(f"❌ Events not in chronological order (0 pts)")
        else:
            feedback_parts.append("❌ Cannot verify chronological order - insufficient dates (0 pts)")
        
        # Check for loss components ($1200, $15, $270)
        has_1200 = bool(re.search(r'[\$]?\s*1[,\s]?200', text_lower) or '1200' in text_lower)
        has_15 = bool(re.search(r'[\$]?\s*15(?!\d)', text_lower))  # $15 but not $150
        has_270 = bool(re.search(r'[\$]?\s*270', text_lower) or '270' in text_lower)
        
        loss_components = sum([has_1200, has_15, has_270])
        
        if loss_components >= 3:
            score += 10
            feedback_parts.append("✅ All three loss components mentioned: $1,200 + $15 + $270 (10 pts)")
        elif loss_components >= 2:
            partial = 6
            score += partial
            feedback_parts.append(f"⚠️ {loss_components}/3 loss components found (partial: {partial} pts)")
        else:
            feedback_parts.append(f"❌ Only {loss_components}/3 loss components found (0 pts)")
        
        # Check for scammer contact info
        has_email = 'david' in text_lower and ('@gmail.com' in text_lower or '@yahoo.com' in text_lower or 'email' in text_lower or 'gmail' in text_lower or 'yahoo' in text_lower)
        has_phone = ('415' in text_lower or '555-0147' in text_lower or 'phone' in text_lower)
        has_name = 'david' in text_lower and ('martinez' in text_lower or 'name' in text_lower)
        
        contact_info_count = sum([has_email, has_phone, has_name])
        
        if contact_info_count >= 2:
            score += 5
            feedback_parts.append(f"✅ Scammer contact information included ({contact_info_count}/3 elements, 5 pts)")
        elif contact_info_count >= 1:
            partial = 3
            score += partial
            feedback_parts.append(f"⚠️ Partial scammer info ({contact_info_count}/3 elements, partial: {partial} pts)")
        else:
            feedback_parts.append("❌ Missing scammer contact information (0 pts)")
        
        # ========== CALCULATION ACCURACY (15 pts) ==========
        
        # Check for correct total: $1,485
        has_total_correct = bool(re.search(r'[\$]?\s*1[,\s]?485', text_lower))
        
        # Also check for any total calculation
        total_pattern = re.search(r'total.*?[\$]?\s*(\d{1,4})', text_lower, re.IGNORECASE)
        has_any_total = total_pattern is not None
        
        if has_total_correct:
            score += 15
            feedback_parts.append("✅ Correct total loss calculation: $1,485 (15 pts)")
        elif has_any_total:
            partial = 7
            score += partial
            extracted_total = total_pattern.group(1) if total_pattern else "unknown"
            feedback_parts.append(f"⚠️ Total mentioned ({extracted_total}) but incorrect, expected $1,485 (partial: {partial} pts)")
        else:
            feedback_parts.append("❌ No total loss calculation found (0 pts)")
        
        # ========== NEXT STEPS SECTION (10 pts) ==========
        
        # Check for next steps section
        next_steps_keywords = ['next steps', 'action items', 'to do', 'todo', 'what to do', 
                               'follow up', 'checklist', 'action plan', 'steps to take']
        has_next_steps = any(keyword in text_lower for keyword in next_steps_keywords)
        
        if has_next_steps:
            score += 5
            feedback_parts.append("✅ Next steps section present (5 pts)")
            
            # Count action items (look for action keywords)
            action_keywords = ['file', 'report', 'submit', 'contact', 'dispute', 
                             'call', 'notify', 'cancel', 'warn', 'police', 'bank']
            action_mentions = sum(1 for keyword in action_keywords if keyword in text_lower)
            
            if action_mentions >= 3:
                score += 5
                feedback_parts.append(f"✅ Multiple action items listed ({action_mentions} action keywords found, 5 pts)")
            elif action_mentions >= 1:
                partial = 3
                score += partial
                feedback_parts.append(f"⚠️ Some action items ({action_mentions} keywords, partial: {partial} pts)")
            else:
                feedback_parts.append("❌ No clear action items listed (0 pts)")
        else:
            feedback_parts.append("❌ No next steps section found (0 pts)")
        
        # ========== FINAL ASSESSMENT ==========
        
        passed = score >= 70
        normalized_score = score / max_score
        
        feedback = " | ".join(feedback_parts)
        feedback += f"\n\n📊 TOTAL SCORE: {score}/{max_score} points"
        
        if passed:
            feedback += "\n✅ PASSED: Document meets requirements for fraud evidence report"
            feedback += "\n   Ready for bank dispute submission and police report"
        else:
            points_needed = 70 - score
            feedback += f"\n❌ FAILED: Need {points_needed} more points to pass (threshold: 70/100)"
            feedback += "\n   Missing or incomplete sections. Review task requirements."
        
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
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        if temp_dir:
            cleanup_temp_dir(temp_dir)