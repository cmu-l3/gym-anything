#!/usr/bin/env python3
"""
Verifier for Apartment Sublet Handoff task
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
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sublet_handoff(traj, env_info, task_info):
    """
    Verify the apartment sublet handoff document.
    
    Checks:
    1. All 6 required sections present
    2. Specific required content (names, address, amounts, dates)
    3. Minimum content items (conditions, contacts, rules)
    4. Document structure and length
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/sublet_handoff.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_sublet_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load document: {error}"
            }

        # Extract all text (case-insensitive for matching)
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()

        # Remove instruction text if present
        if "delete these instructions" in full_text_lower:
            # Try to find where actual content starts
            parts = full_text_lower.split("delete these instructions")
            if len(parts) > 1:
                full_text_lower = parts[1]
                full_text = full_text[full_text.lower().find("delete these instructions") + len("delete these instructions"):]

        # Check for instruction remnants (penalize if not removed)
        has_instructions = "task: create a comprehensive" in full_text_lower

        score = 0.0
        max_score = 100.0
        feedback_parts = []

        # Count paragraphs (excluding empty ones)
        para_count = len([p for p in doc.paragraphs if p.text.strip()])
        
        if para_count < 5:
            feedback_parts.append(f"❌ Document too sparse ({para_count} paragraphs)")
            return {
                "passed": False,
                "score": 0.0,
                "feedback": " | ".join(feedback_parts)
            }

        # === SECTION 1: Check for required sections (30 points) ===
        sections_to_find = [
            (["parties", "property"], "Parties & Property section"),
            (["financial", "arrangement", "payment", "rent"], "Financial Arrangements section"),
            (["condition", "damage", "pre-existing", "apartment condition"], "Condition Documentation section"),
            (["practical", "information", "wifi", "utilities"], "Practical Information section"),
            (["contact", "emergency"], "Important Contacts section"),
            (["rules", "expectation", "policy"], "Rules & Expectations section")
        ]
        
        sections_found = 0
        for keywords, section_name in sections_to_find:
            if any(keyword in full_text_lower for keyword in keywords):
                sections_found += 1
                feedback_parts.append(f"✅ {section_name} found")
            else:
                feedback_parts.append(f"❌ {section_name} missing")
        
        section_score = (sections_found / 6.0) * 30
        score += section_score

        # === SECTION 2: Check for specific required content (40 points) ===
        content_checks = {
            "sarah chen": "Primary tenant name (Sarah Chen)",
            "marcus rodriguez": "Subletter name (Marcus Rodriguez)",
            "742 maple street": "Property address (742 Maple Street)",
        }
        
        # More flexible checks for amounts and dates
        has_rent = bool(re.search(r'\$?\s*1,?450|\$1450|1450\s*dollar', full_text_lower))
        has_deposit = bool(re.search(r'\$?\s*800|800\s*dollar', full_text_lower))
        has_dates = (("june" in full_text_lower or "6/1" in full_text_lower or "06/01" in full_text_lower) and 
                     ("august" in full_text_lower or "8/31" in full_text_lower or "08/31" in full_text_lower))
        
        content_score = 0.0
        required_content_found = 0
        
        # Check text-based requirements
        for search_text, description in content_checks.items():
            if search_text in full_text_lower:
                required_content_found += 1
                feedback_parts.append(f"✅ {description} found")
            else:
                feedback_parts.append(f"❌ {description} missing")
        
        # Check numeric/date requirements
        if has_rent:
            required_content_found += 1
            feedback_parts.append("✅ Rent amount ($1,450) found")
        else:
            feedback_parts.append("❌ Rent amount ($1,450) missing")
            
        if has_deposit:
            required_content_found += 1
            feedback_parts.append("✅ Security deposit ($800) found")
        else:
            feedback_parts.append("❌ Security deposit ($800) missing")
            
        if has_dates:
            required_content_found += 1
            feedback_parts.append("✅ Sublet dates found")
        else:
            feedback_parts.append("❌ Sublet dates (June 1 - August 31, 2024) missing")
        
        content_score = (required_content_found / 6.0) * 40
        score += content_score

        # === SECTION 3: Check for minimum content items (20 points) ===
        # Count potential conditions (look for patterns like "kitchen:", "bathroom:", etc.)
        condition_keywords = ["kitchen", "bathroom", "living room", "bedroom", "wall", "floor", "window", 
                             "door", "chip", "scratch", "stain", "crack", "scuff", "discolor", "damage"]
        condition_count = sum(1 for keyword in condition_keywords if keyword in full_text_lower)
        condition_count = min(condition_count, 5)  # Cap at reasonable number
        
        # Count contacts (look for phone/email patterns or contact-related words)
        contact_indicators = ["phone", "email", "contact", "@", "call", "reach", "landlord", 
                            "manager", "maintenance", "emergency"]
        contact_count = sum(1 for indicator in contact_indicators if indicator in full_text_lower)
        contact_count = min(contact_count, 6)  # Cap at reasonable number
        
        # Count rules (look for rule-related keywords)
        rule_keywords = ["no smoking", "guest", "pet", "noise", "quiet", "parking", 
                        "alcohol", "party", "overnight", "visitor", "rule", "policy"]
        rule_count = sum(1 for keyword in rule_keywords if keyword in full_text_lower)
        rule_count = min(rule_count, 6)  # Cap at reasonable number
        
        item_score = 0.0
        
        if condition_count >= 3:
            item_score += 7
            feedback_parts.append(f"✅ Condition documentation adequate ({condition_count} items)")
        else:
            feedback_parts.append(f"⚠️ Condition documentation sparse ({condition_count} items, need 3+)")
        
        if contact_count >= 3:
            item_score += 7
            feedback_parts.append(f"✅ Contact information adequate ({contact_count} items)")
        else:
            feedback_parts.append(f"⚠️ Contact information sparse ({contact_count} items, need 3+)")
        
        if rule_count >= 3:
            item_score += 6
            feedback_parts.append(f"✅ Rules & expectations adequate ({rule_count} items)")
        else:
            feedback_parts.append(f"⚠️ Rules & expectations sparse ({rule_count} items, need 3+)")
        
        score += item_score

        # === SECTION 4: Document structure (10 points) ===
        structure_score = 0.0
        
        # Check for reasonable document length
        word_count = len(full_text.split())
        if word_count >= 200:
            structure_score += 5
            feedback_parts.append(f"✅ Document has substantial content ({word_count} words)")
        else:
            feedback_parts.append(f"⚠️ Document seems short ({word_count} words)")
        
        # Check for proper structure (multiple paragraphs)
        if para_count >= 10:
            structure_score += 5
            feedback_parts.append(f"✅ Document well-structured ({para_count} paragraphs)")
        elif para_count >= 5:
            structure_score += 2
            feedback_parts.append(f"⚠️ Document structure basic ({para_count} paragraphs)")
        
        score += structure_score

        # Penalize if instructions not removed
        if has_instructions:
            score = max(0, score - 10)
            feedback_parts.append("⚠️ Template instructions not removed (-10 points)")

        # Normalize score
        final_score = min(100.0, max(0.0, score))
        passed = final_score >= 70.0

        # Prepare final feedback
        if passed:
            feedback_parts.insert(0, f"✅ Sublet handoff document meets requirements (Score: {final_score:.0f}/100)")
        else:
            feedback_parts.insert(0, f"❌ Document incomplete or missing key elements (Score: {final_score:.0f}/100)")

        return {
            "passed": passed,
            "score": final_score / 100.0,
            "feedback": " | ".join(feedback_parts)
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
