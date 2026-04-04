#!/usr/bin/env python3
"""
Verifier for Plant Care Handoff task (plant_care_handoff@1)

Validates emergency plant care instructions document has:
- Proper title and date information
- Summary table with 6 plants
- Detailed sections with appropriate headings
- Emergency contact information
- Sufficient detail and formatting
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


def verify_plant_care_handoff(traj, env_info, task_info):
    """
    Verify plant care instruction document meets requirements.
    
    Scoring criteria (10 points total):
    1. Document exists and is parseable (prerequisite)
    2. Has title with "Emergency" and "Plant Care" (1 pt)
    3. Contains date range information (1 pt)
    4. Has summary table with sufficient rows (1 pt)
    5. Table has proper column structure (1 pt)
    6. Has 6 detailed plant sections with Heading 2 style (1 pt)
    7. Contains adequate watering instructions (1 pt)
    8. Has emergency contact section (1 pt)
    9. Has bold "EMERGENCY" text for emphasis (1 pt)
    10. Document is substantial (>3000 characters) (1 pt)
    11. Shows variety in care instructions (1 pt - bonus if >10 points)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/plant_care_instructions.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_plant_')

    try:
        # Copy and parse document
        success, doc, error = copy_and_parse_document(
            container_path,
            copy_from_env,
            file_format='docx'
        )
        
        if not success or doc is None:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Failed to parse document: {error}"
            }
        
        # Extract text and structure
        full_text = get_document_text(doc)
        text_lower = full_text.lower()
        
        criteria_passed = 0
        max_criteria = 10
        feedback_parts = []
        
        # CRITERION 1: Document has substantial content (>3000 chars)
        char_count = len(full_text)
        if char_count > 3000:
            criteria_passed += 1
            feedback_parts.append(f"✅ Document has substantial content ({char_count} chars)")
        else:
            feedback_parts.append(f"❌ Document too short ({char_count} chars, need >3000)")
        
        # CRITERION 2: Title with "Emergency" and "Plant Care"
        has_title = False
        title_text = ""
        for para in doc.paragraphs:
            # Check if it's a heading or title style
            style_name = para.style.name.lower()
            if 'heading' in style_name or 'title' in style_name:
                para_lower = para.text.lower()
                if 'emergency' in para_lower and 'plant' in para_lower and 'care' in para_lower:
                    has_title = True
                    title_text = para.text
                    break
        
        if has_title:
            criteria_passed += 1
            feedback_parts.append("✅ Document has proper title heading with 'Emergency Plant Care'")
        else:
            feedback_parts.append("❌ Missing title heading with 'Emergency Plant Care Instructions'")
        
        # CRITERION 3: Date range information
        # Look for month names or year
        date_patterns = [
            r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)',
            r'(january|february|march|april|may|june|july|august|september|october|november|december)',
            r'(202[3-9]|203[0-9])',  # Years 2023-2039
            r'\d{1,2}[-/]\d{1,2}[-/]\d{2,4}'  # Date formats like 1/15/2024
        ]
        
        has_date = any(re.search(pattern, text_lower) for pattern in date_patterns)
        
        if has_date:
            criteria_passed += 1
            feedback_parts.append("✅ Contains date range information")
        else:
            feedback_parts.append("❌ Missing date range (e.g., 'Jan 15 - Feb 5, 2024')")
        
        # CRITERION 4: Has summary table with sufficient rows
        table_count = count_tables(doc)
        has_proper_table = False
        table_row_count = 0
        
        if table_count >= 1:
            table = doc.tables[0]
            table_row_count = len(table.rows)
            
            if table_row_count >= 7:  # Header + 6 plants
                criteria_passed += 1
                has_proper_table = True
                feedback_parts.append(f"✅ Summary table has sufficient rows ({table_row_count} rows)")
            else:
                feedback_parts.append(f"❌ Table has only {table_row_count} rows, need 7+ (header + 6 plants)")
        else:
            feedback_parts.append("❌ No summary table found")
        
        # CRITERION 5: Table has proper column structure
        if has_proper_table:
            header_row = table.rows[0]
            header_text = ' '.join([cell.text.lower() for cell in header_row.cells])
            
            has_plant_col = 'plant' in header_text or 'name' in header_text
            has_location_col = 'location' in header_text or 'where' in header_text
            has_water_col = 'water' in header_text or 'frequency' in header_text
            has_notes_col = 'note' in header_text or 'special' in header_text or 'warning' in header_text
            
            required_cols = sum([has_plant_col, has_location_col, has_water_col])
            
            if required_cols >= 3:
                criteria_passed += 1
                feedback_parts.append("✅ Table has required columns (Plant, Location, Water)")
            else:
                feedback_parts.append(f"❌ Table missing required headers ({required_cols}/3 found)")
        
        # CRITERION 6: Has 6 detailed plant sections with Heading 2
        heading2_count = 0
        heading2_texts = []
        
        for para in doc.paragraphs:
            style_name = para.style.name
            if 'Heading 2' in style_name or style_name == 'Heading 2':
                heading2_count += 1
                heading2_texts.append(para.text)
        
        # Be lenient - allow Heading 1 or Heading 3 if Heading 2 not used
        if heading2_count < 6:
            # Check for other heading levels
            other_headings = 0
            for para in doc.paragraphs:
                style_name = para.style.name
                if 'Heading' in style_name and para.text.strip():
                    # Exclude main title
                    if not ('emergency' in para.text.lower() and 'plant care' in para.text.lower()):
                        other_headings += 1
            
            if other_headings >= 6:
                heading2_count = other_headings
        
        if heading2_count >= 6:
            criteria_passed += 1
            feedback_parts.append(f"✅ Has {heading2_count} detailed plant sections with headings")
        else:
            feedback_parts.append(f"❌ Only {heading2_count} plant sections found, need 6 (use Heading 2 style)")
        
        # CRITERION 7: Adequate watering instructions
        water_mentions = text_lower.count('water')
        watering_mentions = text_lower.count('watering')
        total_water_refs = water_mentions + watering_mentions
        
        # Should have at least 2 mentions per plant (12 total for 6 plants)
        if total_water_refs >= 12:
            criteria_passed += 1
            feedback_parts.append(f"✅ Contains detailed watering instructions ({total_water_refs} water mentions)")
        else:
            feedback_parts.append(f"❌ Insufficient watering details ({total_water_refs} mentions, need 12+)")
        
        # CRITERION 8: Emergency contact section
        has_emergency_contact = (
            ('emergency' in text_lower or 'urgent' in text_lower) and 
            ('contact' in text_lower or 'phone' in text_lower or 'call' in text_lower or 'number' in text_lower)
        )
        
        if has_emergency_contact:
            criteria_passed += 1
            feedback_parts.append("✅ Contains emergency contact information")
        else:
            feedback_parts.append("❌ Missing emergency contact section")
        
        # CRITERION 9: Bold "EMERGENCY" text for emphasis
        has_bold_emergency = False
        for para in doc.paragraphs:
            for run in para.runs:
                if run.bold and 'emergency' in run.text.lower():
                    has_bold_emergency = True
                    break
            if has_bold_emergency:
                break
        
        if has_bold_emergency:
            criteria_passed += 1
            feedback_parts.append("✅ Has bold-formatted 'EMERGENCY' text")
        else:
            feedback_parts.append("❌ Missing bold 'EMERGENCY' text (for visibility)")
        
        # CRITERION 10: Shows variety in care instructions
        # Check for indicators of different care needs
        variety_indicators = [
            ('dry' in text_lower or 'drought' in text_lower),  # Drought-tolerant plants
            ('moist' in text_lower or 'humid' in text_lower),  # Moisture-loving plants
            ('daily' in text_lower or 'every day' in text_lower),  # Frequent watering
            ('week' in text_lower and 'every' in text_lower),  # Weekly care
            ('toxic' in text_lower or 'poison' in text_lower or 'warning' in text_lower),  # Warnings
            ('bright' in text_lower or 'sun' in text_lower or 'light' in text_lower),  # Light needs
        ]
        
        variety_count = sum(variety_indicators)
        
        if variety_count >= 4:
            criteria_passed += 1
            feedback_parts.append(f"✅ Shows variety in plant care needs ({variety_count} different care types)")
        else:
            feedback_parts.append(f"⚠️ Limited variety in care instructions ({variety_count} types, suggest 4+)")
        
        # Calculate final score (0-100)
        score = int((criteria_passed / max_criteria) * 100)
        passed = score >= 70  # Need 7/10 criteria to pass
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": f"Score: {criteria_passed}/{max_criteria} | {feedback}"
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)