#!/usr/bin/env python3
"""
Verifier for Property Tax Appeal task (property_tax_appeal@1)

Verifies:
1. Spreadsheet with property comparison table and formulas
2. Formal business letter with proper structure and content
"""

import sys
import os
import logging
import tempfile
import re
from typing import Dict, Any, List, Tuple

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_property_tax_appeal(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Verify property tax appeal task completion.
    
    Checks both spreadsheet and letter for correctness.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}
    
    feedback_parts = []
    score = 0
    max_score = 100
    
    spreadsheet_path = "/home/ga/Documents/Spreadsheets/property_comparison.xlsx"
    letter_path = "/home/ga/Documents/TextDocuments/tax_appeal_letter.docx"
    
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_appeal_')
    
    try:
        # ====================================================================
        # PART 1: VERIFY SPREADSHEET (60 points)
        # ====================================================================
        
        success_sheet, wb, error_sheet = copy_and_parse_document(
            spreadsheet_path, copy_from_env, 'xlsx'
        )
        
        if not success_sheet:
            feedback_parts.append(f"❌ Spreadsheet not found or invalid: {error_sheet}")
            score = 0  # Cannot proceed without spreadsheet
        else:
            # Get the active sheet
            try:
                sheet_name = wb.sheetnames[0]
                sheet = wb[sheet_name]
                
                # Extract all cell data for analysis
                all_values = []
                for row in sheet.iter_rows(min_row=1, max_row=30, max_col=10):
                    row_data = []
                    for cell in row:
                        row_data.append(cell.value)
                    all_values.append(row_data)
                
                # Criterion 1: Check for address data (10 points)
                found_addresses = []
                for row in all_values:
                    for cell in row:
                        if cell and isinstance(cell, str):
                            cell_lower = cell.lower()
                            if 'oak' in cell_lower and ('street' in cell_lower or 'st' in cell_lower):
                                found_addresses.append(cell)
                            elif 'maple' in cell_lower:
                                found_addresses.append(cell)
                            elif 'cedar' in cell_lower:
                                found_addresses.append(cell)
                
                if len(found_addresses) >= 4:
                    score += 10
                    feedback_parts.append(f"✅ Property addresses present ({len(found_addresses)} found)")
                else:
                    feedback_parts.append(f"❌ Missing property addresses (found {len(found_addresses)}, need 5)")
                
                # Criterion 2: Check for assessment values (10 points)
                expected_values = [425000, 298000, 312000, 305000, 294000]
                found_values = []
                for row in all_values:
                    for cell in row:
                        if isinstance(cell, (int, float)) and 290000 <= cell <= 430000:
                            found_values.append(int(cell))
                
                # Check if we have at least 4 of the expected values
                matching_values = sum(1 for ev in expected_values if any(abs(fv - ev) < 1000 for fv in found_values))
                
                if matching_values >= 4:
                    score += 10
                    feedback_parts.append(f"✅ Assessment values present ({matching_values}/5 correct)")
                else:
                    feedback_parts.append(f"❌ Missing assessment values (found {matching_values}/5)")
                
                # Criterion 3: Check for square footage data (5 points)
                expected_sqft = [1850, 1820, 1900, 1875, 1840]
                found_sqft = []
                for row in all_values:
                    for cell in row:
                        if isinstance(cell, (int, float)) and 1800 <= cell <= 1950:
                            found_sqft.append(int(cell))
                
                if len(found_sqft) >= 4:
                    score += 5
                    feedback_parts.append(f"✅ Square footage data present")
                else:
                    feedback_parts.append(f"❌ Missing square footage data")
                
                # Criterion 4: Check for $/sq ft calculations (15 points)
                # Should be around: 230, 164, 164, 163, 160
                calculated_values = []
                for row in all_values:
                    for cell in row:
                        if isinstance(cell, (int, float)) and 150 <= cell <= 250:
                            calculated_values.append(cell)
                
                # We expect at least 5 calculated $/sq ft values
                if len(calculated_values) >= 5:
                    score += 15
                    feedback_parts.append(f"✅ $/Sq Ft calculations present ({len(calculated_values)} values)")
                elif len(calculated_values) >= 3:
                    score += 8
                    feedback_parts.append(f"⚠️ Partial $/Sq Ft calculations ({len(calculated_values)} values)")
                else:
                    feedback_parts.append(f"❌ $/Sq Ft calculations missing or incorrect")
                
                # Criterion 5: Check for average calculation (10 points)
                # Average of comparables should be around 162-164
                found_average = False
                for row in all_values:
                    for cell in row:
                        if isinstance(cell, (int, float)) and 155 <= cell <= 170:
                            # Make sure it's not one of the individual $/sq ft values
                            # This is a heuristic - the average should be unique
                            found_average = True
                
                if found_average:
                    score += 10
                    feedback_parts.append(f"✅ Average $/Sq Ft calculation found")
                else:
                    feedback_parts.append(f"❌ Average $/Sq Ft calculation missing")
                
                # Criterion 6: Check for fair value calculation (5 points)
                # Fair value should be around 303,000 (1850 × 163.75)
                found_fair_value = False
                for row in all_values:
                    for cell in row:
                        if isinstance(cell, (int, float)) and 295000 <= cell <= 315000:
                            # Make sure it's not one of the original assessment values
                            if not any(abs(cell - ev) < 2000 for ev in [298000, 312000, 305000]):
                                found_fair_value = True
                
                if found_fair_value:
                    score += 5
                    feedback_parts.append(f"✅ Fair value calculation present")
                else:
                    feedback_parts.append(f"❌ Fair value calculation missing")
                
                # Criterion 7: Check for over-assessment amount (5 points)
                # Over-assessment should be around 122,000 (425000 - 303000)
                found_overassessment = False
                for row in all_values:
                    for cell in row:
                        if isinstance(cell, (int, float)) and 110000 <= cell <= 135000:
                            found_overassessment = True
                
                if found_overassessment:
                    score += 5
                    feedback_parts.append(f"✅ Over-assessment amount calculated")
                else:
                    feedback_parts.append(f"❌ Over-assessment amount missing")
                
            except Exception as e:
                logger.error(f"Error analyzing spreadsheet: {e}", exc_info=True)
                feedback_parts.append(f"❌ Error analyzing spreadsheet: {str(e)}")
        
        # ====================================================================
        # PART 2: VERIFY LETTER (40 points)
        # ====================================================================
        
        success_letter, doc, error_letter = copy_and_parse_document(
            letter_path, copy_from_env, 'docx'
        )
        
        if not success_letter:
            feedback_parts.append(f"❌ Letter not found or invalid: {error_letter}")
            # Don't add to score - already penalized by missing points below
        else:
            try:
                letter_text = get_document_text(doc)
                letter_lower = letter_text.lower()
                
                # Criterion 8: Check for sender address (5 points)
                has_sender_address = bool(re.search(r'123\s+oak\s+(street|st)', letter_lower))
                if has_sender_address:
                    score += 5
                    feedback_parts.append("✅ Sender address present")
                else:
                    feedback_parts.append("❌ Sender address missing")
                
                # Criterion 9: Check for recipient (5 points)
                has_recipient = bool(re.search(r'board of equalization|assessor', letter_lower))
                if has_recipient:
                    score += 5
                    feedback_parts.append("✅ Recipient address present")
                else:
                    feedback_parts.append("❌ Recipient address missing")
                
                # Criterion 10: Check for parcel number (5 points)
                has_parcel = bool(re.search(r'parcel|45-12-089', letter_text))
                if has_parcel:
                    score += 5
                    feedback_parts.append("✅ Parcel number referenced")
                else:
                    feedback_parts.append("❌ Parcel number not mentioned")
                
                # Criterion 11: Check for salutation and closing (3 points)
                has_salutation = bool(re.search(r'dear (board members|sir|madam|members)', letter_lower))
                has_closing = bool(re.search(r'sincerely|respectfully', letter_lower))
                
                if has_salutation and has_closing:
                    score += 3
                    feedback_parts.append("✅ Proper salutation and closing")
                elif has_salutation or has_closing:
                    score += 1
                    feedback_parts.append("⚠️ Partial salutation/closing")
                else:
                    feedback_parts.append("❌ Missing salutation or closing")
                
                # Criterion 12: Check for assessment value reference (5 points)
                has_assessment = bool(re.search(r'\$?\s?425,?000', letter_text))
                if has_assessment:
                    score += 5
                    feedback_parts.append("✅ References current assessment ($425,000)")
                else:
                    feedback_parts.append("❌ Doesn't mention current assessment value")
                
                # Criterion 13: Check for comparable properties mention (5 points)
                has_comparables = bool(re.search(r'comparable|similar (properties|homes)|neighborhood', letter_lower))
                if has_comparables:
                    score += 5
                    feedback_parts.append("✅ References comparable properties")
                else:
                    feedback_parts.append("❌ Doesn't reference comparable properties")
                
                # Criterion 14: Check for numerical support from analysis (5 points)
                has_numbers = (
                    bool(re.search(r'\$?\s?30[0-9],?000', letter_text)) or  # Fair value around 300k
                    bool(re.search(r'16[0-9]|164', letter_text)) or  # $/sq ft around 164
                    bool(re.search(r'38\s?%|40\s?%', letter_text))  # Percentage over-assessment
                )
                if has_numbers:
                    score += 5
                    feedback_parts.append("✅ Includes numerical data from analysis")
                else:
                    feedback_parts.append("❌ Missing numerical support from spreadsheet")
                
                # Criterion 15: Check for professional tone (4 points)
                has_request = bool(re.search(r'request|respectfully|appeal|review|ask', letter_lower))
                no_demands = not bool(re.search(r'\b(demand|insist|must|require)\b', letter_lower))
                
                if has_request and no_demands:
                    score += 4
                    feedback_parts.append("✅ Professional, respectful tone")
                elif has_request:
                    score += 2
                    feedback_parts.append("⚠️ Somewhat professional tone")
                else:
                    feedback_parts.append("❌ Lacks professional tone")
                
                # Criterion 16: Check for proper structure (3 points)
                # Count paragraphs - should have at least 4-5 body paragraphs plus addresses
                para_count = len([p for p in doc.paragraphs if p.text.strip()])
                if para_count >= 8:  # Addresses + salutation + 4-5 body paragraphs + closing
                    score += 3
                    feedback_parts.append(f"✅ Proper letter structure ({para_count} paragraphs)")
                else:
                    feedback_parts.append(f"⚠️ Letter structure could be improved ({para_count} paragraphs)")
                
            except Exception as e:
                logger.error(f"Error analyzing letter: {e}", exc_info=True)
                feedback_parts.append(f"❌ Error analyzing letter: {str(e)}")
        
        # ====================================================================
        # FINAL EVALUATION
        # ====================================================================
        
        passed = score >= 70  # Need 70% to pass
        normalized_score = score / max_score
        
        feedback = " | ".join(feedback_parts)
        feedback += f" || TOTAL: {score}/{max_score} points"
        
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
verify_task = verify_property_tax_appeal