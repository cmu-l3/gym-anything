#!/usr/bin/env python3
"""
Verifier for Union Break Grievance task (union_break_grievance@1)

Verifies that a professional union grievance document was created from messy notes,
with proper structure, calculations, and formatting.
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
    check_text_formatting,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_union_break_grievance(traj, env_info, task_info):
    """
    Verify the union grievance document meets all requirements.
    
    Scoring breakdown (100 points):
    - File exists and valid DOCX: 10 points
    - Required text elements: 25 points
    - Table structure: 25 points
    - Word count >= 300: 10 points
    - Calculations present: 15 points
    - Professional formatting: 15 points
    
    Pass threshold: 75 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "❌ Copy function not available"}

    container_path = "/home/ga/Documents/grievance_meal_breaks.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_grievance_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Failed to load grievance_meal_breaks.docx: {error}"
            }

        feedback_parts = []
        score = 0

        # Get full document text for analysis
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        logger.info(f"Document text length: {len(full_text)} characters")
        logger.info(f"Document preview: {full_text[:200]}...")

        # ===================================================================
        # CRITERION 1: File exists and is valid DOCX (10 points)
        # ===================================================================
        score += 10
        feedback_parts.append("✅ Document exists and is valid DOCX (10pts)")

        # ===================================================================
        # CRITERION 2: Required text elements (25 points total)
        # ===================================================================
        required_elements = {
            'grv-2024-0847': ('Grievance number', 4),
            'jamal': ('Employee name', 3),
            '4521': ('Employee number', 3),
            'article 12': ('Contract article reference', 4),
            'meal break': ('Subject matter', 3),
            'grievance': ('Document type', 2),
            '22.50': ('Hourly wage', 3),
            '7.5': ('Penalty hours calculation', 3)
        }
        
        text_score = 0
        missing_elements = []
        
        for search_term, (description, points) in required_elements.items():
            # Flexible matching for numbers and text
            found = False
            if search_term in full_text_lower:
                found = True
            elif search_term.replace('.', '') in full_text_lower:
                found = True
            elif search_term == '22.50' and ('22.5' in full_text or '$22.50' in full_text):
                found = True
            elif search_term == '7.5' and ('7½' in full_text or 'seven and a half' in full_text_lower):
                found = True
            
            if found:
                text_score += points
                logger.info(f"✓ Found: {description} ({search_term})")
            else:
                missing_elements.append(f"{description}")
                logger.warning(f"✗ Missing: {description} ({search_term})")
        
        score += text_score
        
        if text_score >= 20:
            feedback_parts.append(f"✅ Contains required text elements ({text_score}/25pts)")
        elif text_score >= 15:
            feedback_parts.append(f"⚠️ Missing some text elements: {', '.join(missing_elements[:2])} ({text_score}/25pts)")
        else:
            feedback_parts.append(f"❌ Missing many required elements: {', '.join(missing_elements[:3])} ({text_score}/25pts)")
        
        # Check for proper date format (MM/DD/YYYY or similar)
        date_pattern = r'\b\d{1,2}[/-]\d{1,2}[/-]\d{4}\b'
        date_matches = re.findall(date_pattern, full_text)
        if date_matches:
            logger.info(f"✓ Found {len(date_matches)} properly formatted date(s)")
        else:
            logger.warning("✗ No dates in MM/DD/YYYY format found")

        # ===================================================================
        # CRITERION 3: Table structure (25 points)
        # ===================================================================
        num_tables = count_tables(doc)
        logger.info(f"Number of tables found: {num_tables}")
        
        table_score = 0
        
        if num_tables >= 1:
            table = doc.tables[0]
            num_rows = len(table.rows)
            num_cols = len(table.columns) if table.rows else 0
            
            logger.info(f"Table dimensions: {num_rows} rows × {num_cols} columns")
            
            # Check row count (need 5+ rows: 1 header + 4+ data rows)
            if num_rows >= 5:
                table_score += 10
                feedback_parts.append(f"✅ Table has {num_rows} rows (10pts)")
            elif num_rows >= 3:
                table_score += 5
                feedback_parts.append(f"⚠️ Table has only {num_rows} rows, need 5+ (5pts)")
            else:
                feedback_parts.append(f"❌ Table has only {num_rows} rows, need 5+ (0pts)")
            
            # Check column count (need 4+ columns)
            if num_cols >= 4:
                table_score += 8
                feedback_parts.append(f"✅ Table has {num_cols} columns (8pts)")
            elif num_cols >= 3:
                table_score += 4
                feedback_parts.append(f"⚠️ Table has only {num_cols} columns, need 4+ (4pts)")
            else:
                feedback_parts.append(f"❌ Table has only {num_cols} columns, need 4+ (0pts)")
            
            # Check for appropriate header keywords in first row
            if table.rows:
                header_text = " ".join([cell.text.lower() for cell in table.rows[0].cells])
                logger.info(f"Table header text: {header_text}")
                
                required_headers = ['date', 'break', 'time', 'witness', 'duration', 'lost']
                headers_found = sum(1 for h in required_headers if h in header_text)
                
                if headers_found >= 4:
                    table_score += 7
                    feedback_parts.append(f"✅ Table headers present ({headers_found} keywords) (7pts)")
                elif headers_found >= 2:
                    table_score += 3
                    feedback_parts.append(f"⚠️ Table headers incomplete ({headers_found} keywords) (3pts)")
                else:
                    feedback_parts.append(f"❌ Table headers missing key terms ({headers_found} keywords) (0pts)")
                
                # Check if table has actual data (dates or times in data rows)
                if num_rows >= 2:
                    has_real_data = False
                    for row_idx in range(1, min(num_rows, 4)):  # Check first few data rows
                        row_text = " ".join([cell.text for cell in table.rows[row_idx].cells]).lower()
                        # Look for date patterns or time patterns
                        if re.search(r'\d{1,2}[/-]\d{1,2}', row_text) or re.search(r'\d{1,2}:\d{2}', row_text):
                            has_real_data = True
                            break
                    
                    if has_real_data:
                        logger.info("✓ Table contains actual incident data")
                    else:
                        logger.warning("✗ Table may contain only placeholder text")
            
            score += table_score
        else:
            feedback_parts.append("❌ No table found in document (0/25pts)")
            logger.warning("✗ No table found in document")

        # ===================================================================
        # CRITERION 4: Word count (10 points)
        # ===================================================================
        word_count = len(full_text.split())
        logger.info(f"Word count: {word_count}")
        
        if word_count >= 300:
            score += 10
            feedback_parts.append(f"✅ Word count: {word_count} words (10pts)")
        elif word_count >= 200:
            score += 5
            feedback_parts.append(f"⚠️ Word count: {word_count} words (need 300) (5pts)")
        elif word_count >= 100:
            score += 2
            feedback_parts.append(f"❌ Word count too low: {word_count} words (2pts)")
        else:
            feedback_parts.append(f"❌ Word count critically low: {word_count} words (0pts)")

        # ===================================================================
        # CRITERION 5: Calculations present (15 points)
        # ===================================================================
        calc_score = 0
        
        # Check for 7.5 hours penalty calculation
        if '7.5' in full_text or '7½' in full_text or 'seven and a half' in full_text_lower:
            calc_score += 7
            logger.info("✓ Found 7.5 hours penalty calculation")
        else:
            logger.warning("✗ Missing 7.5 hours penalty calculation")
        
        # Check for 1.5 multiplier reference
        if any(term in full_text_lower for term in ['1.5', '1½', 'time-and-a-half', 'time and a half', 'one and a half']):
            calc_score += 4
            logger.info("✓ Found penalty multiplier reference")
        else:
            logger.warning("✗ Missing penalty multiplier reference")
        
        # Check for dollar amount or total calculation
        dollar_pattern = r'\$\s*\d+(?:\.\d{2})?|\d+\.\d{2}\s*dollars?'
        if re.search(dollar_pattern, full_text, re.IGNORECASE):
            calc_score += 4
            logger.info("✓ Found dollar amount calculation")
        else:
            logger.warning("✗ Missing dollar amount")
        
        score += calc_score
        
        if calc_score >= 12:
            feedback_parts.append(f"✅ Penalty calculations present (15pts)")
        elif calc_score >= 7:
            feedback_parts.append(f"⚠️ Partial calculations present ({calc_score}/15pts)")
        else:
            feedback_parts.append(f"❌ Missing calculations ({calc_score}/15pts)")

        # ===================================================================
        # CRITERION 6: Professional formatting (15 points)
        # ===================================================================
        formatting_score = 0
        
        # Check for bold text (headers, emphasis)
        has_bold = False
        bold_count = 0
        for para in doc.paragraphs:
            for run in para.runs:
                if run.bold:
                    has_bold = True
                    bold_count += 1
                    if bold_count >= 3:  # Found sufficient bold formatting
                        break
            if bold_count >= 3:
                break
        
        if has_bold:
            if bold_count >= 3:
                formatting_score += 8
                feedback_parts.append(f"✅ Uses bold formatting effectively (8pts)")
            else:
                formatting_score += 4
                feedback_parts.append(f"⚠️ Limited bold formatting ({bold_count} instances) (4pts)")
        else:
            feedback_parts.append("❌ No bold formatting detected (0pts)")
        
        # Check for proper document structure (multiple paragraphs)
        num_paragraphs = len([p for p in doc.paragraphs if p.text.strip()])
        logger.info(f"Number of paragraphs: {num_paragraphs}")
        
        if num_paragraphs >= 5:
            formatting_score += 7
            feedback_parts.append(f"✅ Well-structured document ({num_paragraphs} paragraphs) (7pts)")
        elif num_paragraphs >= 3:
            formatting_score += 4
            feedback_parts.append(f"⚠️ Basic structure ({num_paragraphs} paragraphs, need 5+) (4pts)")
        else:
            feedback_parts.append(f"❌ Poorly structured ({num_paragraphs} paragraphs) (0pts)")
        
        score += formatting_score

        # ===================================================================
        # Final scoring and feedback
        # ===================================================================
        passed = score >= 75
        
        # Compile final feedback
        feedback = " | ".join(feedback_parts)
        feedback = f"Score: {score}/100 | " + feedback
        
        if passed:
            feedback = "✅ PASSED - Professional grievance document created | " + feedback
        else:
            feedback = "❌ FAILED - Document incomplete or missing key elements | " + feedback
        
        logger.info(f"Final score: {score}/100, Passed: {passed}")

        return {
            "passed": passed,
            "score": score / 100.0,
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
        cleanup_temp_dir(temp_dir)
