#!/usr/bin/env python3
"""
Verifier for Pet Emergency Campaign task
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
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_numbers_from_text(text):
    """
    Extract all dollar amounts from text in various formats.
    Returns list of integers (in dollars).
    
    Handles: $2,800  $2800  2,800  2800
    """
    # Pattern to match dollar amounts with or without $ and commas
    pattern = r'\$?\s*(\d{1,3}(?:,\d{3})*(?:\.\d{2})?)'
    matches = re.findall(pattern, text)
    
    numbers = []
    for match in matches:
        # Remove commas and convert to integer
        clean_num = match.replace(',', '')
        # Handle decimal (convert $2800.00 to 2800)
        if '.' in clean_num:
            clean_num = clean_num.split('.')[0]
        try:
            numbers.append(int(clean_num))
        except ValueError:
            continue
    
    return numbers


def verify_pet_emergency_campaign(traj, env_info, task_info):
    """
    Verify pet emergency crowdfunding campaign document.
    
    Checks:
    1. Document exists and is valid DOCX (25 points)
    2. Contains required content elements (25 points)
       - Mentions Maxie
       - References accident/emergency/surgery
       - Mentions pelvic fracture
       - Has substantial story (≥300 chars)
    3. Budget breakdown table exists (30 points)
       - Has table with adequate rows
       - Contains key dollar amounts
    4. Correct calculations (20 points)
       - $6,200 total needed
       - $9,000 total cost
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/maxie_campaign.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_campaign_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Document not found or invalid: {error}"
            }

        score = 0
        max_score = 100
        feedback_parts = []

        # Check 1: Document exists and is valid DOCX (25 points)
        score += 25
        feedback_parts.append("✅ Document exists and is valid DOCX format (25/25)")

        # Check 2: Contains required content elements (25 points)
        text = get_document_text(doc)
        text_lower = text.lower()
        
        content_checks = {
            "maxie": "maxie" in text_lower,
            "accident": any(keyword in text_lower for keyword in ["accident", "hit", "car", "emergency", "injured", "surgery"]),
            "pelvis": any(keyword in text_lower for keyword in ["pelvis", "pelvic", "fracture"]),
            "length": len(text) >= 300
        }
        
        content_score = 0
        
        if content_checks["maxie"]:
            content_score += 7
            feedback_parts.append("  ✅ Contains dog's name 'Maxie'")
        else:
            feedback_parts.append("  ❌ Missing dog's name 'Maxie'")
        
        if content_checks["accident"]:
            content_score += 6
            feedback_parts.append("  ✅ Describes accident/emergency/surgery")
        else:
            feedback_parts.append("  ❌ Missing accident/emergency description")
        
        if content_checks["pelvis"]:
            content_score += 6
            feedback_parts.append("  ✅ Mentions pelvic fracture")
        else:
            feedback_parts.append("  ❌ Missing pelvic fracture detail")
        
        if content_checks["length"]:
            content_score += 6
            feedback_parts.append(f"  ✅ Substantial story content ({len(text)} chars, ≥300)")
        else:
            feedback_parts.append(f"  ⚠️ Story too brief ({len(text)} chars, need ≥300)")
        
        score += content_score
        feedback_parts.append(f"Content elements score: {content_score}/25")
        
        # Check 3: Table exists with budget information (30 points)
        num_tables = count_tables(doc)
        
        if num_tables == 0:
            feedback_parts.append("❌ No table found - budget breakdown missing (0/30)")
            table_score = 0
        else:
            table_score = 10  # Base points for having a table
            feedback_parts.append(f"  ✅ Document contains {num_tables} table(s)")
            
            # Check table has enough rows
            table = doc.tables[0]
            num_rows = len(table.rows)
            
            if num_rows >= 8:
                table_score += 10
                feedback_parts.append(f"  ✅ Table has {num_rows} rows (≥8 for all line items)")
            elif num_rows >= 5:
                table_score += 5
                feedback_parts.append(f"  ⚠️ Table has {num_rows} rows (expected ≥8)")
            else:
                feedback_parts.append(f"  ❌ Table has only {num_rows} rows (too few)")
            
            # Extract all numbers from document
            numbers = extract_numbers_from_text(text)
            
            # Check for required dollar amounts
            required_amounts = {
                2800: "$2,800 (emergency care paid)",
                3800: "$3,800 (surgery)",
                6200: "$6,200 (total needed)",
                9000: "$9,000 (total cost)"
            }
            
            amounts_found = 0
            for amount, description in required_amounts.items():
                if amount in numbers:
                    amounts_found += 1
                    feedback_parts.append(f"    ✅ Found {description}")
                else:
                    feedback_parts.append(f"    ❌ Missing {description}")
            
            # Allocate remaining 10 points based on amounts found
            table_score += (amounts_found / len(required_amounts)) * 10
            
        score += table_score
        feedback_parts.append(f"Budget table score: {table_score:.1f}/30")
        
        # Check 4: Correct calculations (20 points)
        calc_score = 0
        numbers = extract_numbers_from_text(text)
        
        # Check for key totals
        if 6200 in numbers:
            calc_score += 10
            feedback_parts.append("  ✅ Correct 'total needed' calculation: $6,200")
        else:
            feedback_parts.append("  ❌ Missing or incorrect 'total needed' ($6,200)")
            # Check if they have the individual items that sum to 6200
            items_needed = [3800, 650, 900, 180, 85, 420, 165]
            items_found = sum(1 for item in items_needed if item in numbers)
            if items_found >= 5:
                calc_score += 5
                feedback_parts.append(f"    ⚠️ Found {items_found}/7 individual line items")
        
        if 9000 in numbers:
            calc_score += 10
            feedback_parts.append("  ✅ Correct 'total cost' calculation: $9,000")
        else:
            feedback_parts.append("  ❌ Missing or incorrect 'total cost' ($9,000)")
            # Give partial credit if they have 2800 and 6200 separately
            if 2800 in numbers and 6200 in numbers:
                calc_score += 5
                feedback_parts.append("    ⚠️ Has components ($2,800 and $6,200) but missing total")
        
        score += calc_score
        feedback_parts.append(f"Calculations score: {calc_score}/20")
        
        # Additional check: verify some key line items are present
        key_items = [3800, 650, 900, 180, 85, 420, 165]
        items_present = sum(1 for item in key_items if item in numbers)
        feedback_parts.append(f"  📊 Individual line items found: {items_present}/7")
        
        # Final assessment
        normalized_score = score / max_score
        passed = score >= 70  # 70% threshold
        
        # Build final feedback
        final_feedback = "\n".join(feedback_parts)
        final_feedback += f"\n\n{'='*60}"
        final_feedback += f"\n📊 TOTAL SCORE: {score:.1f}/{max_score} ({normalized_score*100:.1f}%)"
        final_feedback += f"\n{'='*60}"
        
        if passed:
            final_feedback += "\n✅ PASSED - Campaign document is ready for fundraising platform"
        else:
            final_feedback += "\n❌ FAILED - Document needs significant improvements"
            if num_tables == 0:
                final_feedback += "\n   💡 Hint: Create a table for the budget breakdown"
            if not content_checks["maxie"]:
                final_feedback += "\n   💡 Hint: Make sure to mention Maxie's name in the story"
            if not (6200 in numbers and 9000 in numbers):
                final_feedback += "\n   💡 Hint: Calculate and include total amounts ($6,200 needed, $9,000 total)"
        
        return {
            "passed": passed,
            "score": float(normalized_score),
            "feedback": final_feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
