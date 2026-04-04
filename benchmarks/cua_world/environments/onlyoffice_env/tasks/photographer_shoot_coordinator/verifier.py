#!/usr/bin/env python3
"""
Verifier for Photographer Shoot Coordinator task

Verifies both spreadsheet coordination and client-facing document creation
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_cell_value,
    get_sheet_data,
    get_document_text,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_photographer_coordination(traj, env_info, task_info):
    """
    Verify photographer shoot coordination task completion.
    
    Checks SPREADSHEET:
    1. Martinez Wedding time updated to 11:00 AM (from 2:00 PM)
    2. Equipment conflict resolved (70-200mm either duplicated or substituted)
    3. Taylor Engagement rental cost updated to ~$175 (from $125)
    4. Chen Family assistant status shows need for backup
    5. Cost calculations present and reasonable
    
    Checks CLIENT DOCUMENT:
    6. chen_family_shoot_plan.docx exists
    7. Contains professional header with Chen Family name
    8. Contains timeline with specific times
    9. Contains weather backup plan mentioning Lakeside Park
    10. Document is substantial (shows professionalism)
    
    Scoring: 4 categories, each 25%
    - Spreadsheet Data Updates (3 criteria)
    - Spreadsheet Problem Solving (2 criteria)
    - Document Exists and Structure (3 criteria)
    - Document Content Quality (2 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    spreadsheet_path = "/home/ga/Documents/Photography/shoot_master_schedule.xlsx"
    document_path = "/home/ga/Documents/Photography/chen_family_shoot_plan.docx"
    temp_dir = tempfile.mkdtemp(prefix='photographer_verify_')

    try:
        # ===== PART 1: SPREADSHEET VERIFICATION =====
        success_sheet, wb, error_sheet = copy_and_parse_document(
            spreadsheet_path, copy_from_env, 'xlsx'
        )

        if not success_sheet:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to load spreadsheet: {error_sheet}"
            }

        sheet_name = wb.sheetnames[0]  # Usually "Shoots"
        
        # Get all data as 2D array for easier searching
        sheet_data = get_sheet_data(wb, sheet_name, max_rows=20, max_cols=10)
        
        feedback_parts = []
        criteria_passed = 0
        total_criteria = 10
        
        # Helper function to find data in sheet
        def find_in_sheet(keyword):
            """Find rows containing keyword (case-insensitive)"""
            matches = []
            for row_idx, row in enumerate(sheet_data):
                row_text = ' '.join([str(cell).lower() if cell else '' for cell in row])
                if keyword.lower() in row_text:
                    matches.append((row_idx, row))
            return matches
        
        # CRITERION 1: Martinez Wedding time updated to 11:00 AM
        martinez_rows = find_in_sheet("martinez")
        martinez_time_updated = False
        
        if martinez_rows:
            for row_idx, row in martinez_rows:
                # Time is usually in column 3 (index 3)
                time_value = str(row[3]).lower() if len(row) > 3 else ""
                # Check for 11:00 AM variations
                if any(x in time_value for x in ["11:00", "11 am", "11am", "11 00"]):
                    martinez_time_updated = True
                    criteria_passed += 1
                    feedback_parts.append("✅ Martinez wedding time updated to 11:00 AM")
                    break
        
        if not martinez_time_updated:
            feedback_parts.append("❌ Martinez wedding time not updated to 11:00 AM")
        
        # CRITERION 2: Equipment conflict addressed
        # Check if 70-200mm appears with resolution indicators
        equipment_resolved = False
        
        # Look for evidence of conflict resolution:
        # - Two entries of 70-200mm (rented twice)
        # - OR substitute lens mentioned (85mm, etc.)
        # - OR updated cost that reflects resolution
        
        equipment_mentions = []
        for row_idx, row in sheet_data:
            equipment_text = ' '.join([str(cell).lower() if cell else '' for cell in row])
            if '70-200' in equipment_text or '70mm-200mm' in equipment_text:
                equipment_mentions.append(equipment_text)
        
        # Check for duplicate rental or substitution
        if len(equipment_mentions) >= 2:  # If mentioned twice, likely rented twice
            equipment_resolved = True
        elif any(x in ' '.join([str(c) for row in sheet_data for c in row]).lower() 
                for x in ['85mm', '85 mm', 'substitute', 'backup lens', 'second 70-200']):
            equipment_resolved = True
        
        # Also check if Chen Family rental cost increased (indicating resolution)
        chen_rows = find_in_sheet("chen")
        if chen_rows and not equipment_resolved:
            for row_idx, row in chen_rows:
                rental_cost = row[6] if len(row) > 6 else None
                if rental_cost and isinstance(rental_cost, (int, float)):
                    # Original was $75, if increased to ~$125-150, conflict resolved
                    if rental_cost >= 100:
                        equipment_resolved = True
        
        if equipment_resolved:
            criteria_passed += 1
            feedback_parts.append("✅ Equipment conflict resolved (70-200mm lens)")
        else:
            feedback_parts.append("❌ Equipment conflict not resolved (70-200mm still double-booked)")
        
        # CRITERION 3: Taylor Engagement rental cost updated to ~$175
        taylor_rows = find_in_sheet("taylor")
        taylor_cost_updated = False
        
        if taylor_rows:
            for row_idx, row in taylor_rows:
                rental_cost = row[6] if len(row) > 6 else None
                if rental_cost:
                    # Convert to number if string
                    try:
                        if isinstance(rental_cost, str):
                            rental_cost = float(rental_cost.replace('$', '').replace(',', ''))
                        if 165 <= rental_cost <= 185:  # Allow $165-$185 range
                            taylor_cost_updated = True
                            criteria_passed += 1
                            feedback_parts.append(f"✅ Taylor rental cost updated to ${rental_cost}")
                            break
                    except:
                        pass
        
        if not taylor_cost_updated:
            feedback_parts.append("❌ Taylor rental cost not updated to ~$175")
        
        # CRITERION 4: Chen Family assistant status shows unavailable/need backup
        chen_assistant_flagged = False
        
        if chen_rows:
            for row_idx, row in chen_rows:
                assistant_status = str(row[7]).lower() if len(row) > 7 else ""
                # Look for keywords indicating problem
                if any(x in assistant_status for x in [
                    "unavailable", "need", "backup", "find", "rachel", 
                    "not available", "no", "contact", "unavail"
                ]):
                    chen_assistant_flagged = True
                    criteria_passed += 1
                    feedback_parts.append("✅ Chen Family assistant issue marked")
                    break
        
        if not chen_assistant_flagged:
            feedback_parts.append("❌ Chen Family assistant availability not flagged")
        
        # CRITERION 5: Cost calculation updated (summary section)
        # Check if total rental cost is reasonable (should be 350-425 range after updates)
        total_rental_calculated = False
        
        # Look for total/summary cells
        for row_idx, row in enumerate(sheet_data):
            row_text = ' '.join([str(cell).lower() if cell else '' for cell in row])
            if 'total' in row_text and 'rental' in row_text:
                # Next cell or same row should have the total
                for cell in row:
                    if isinstance(cell, (int, float)) and 300 <= cell <= 450:
                        total_rental_calculated = True
                        criteria_passed += 1
                        feedback_parts.append(f"✅ Total rental cost calculated: ${cell}")
                        break
                if total_rental_calculated:
                    break
        
        if not total_rental_calculated:
            feedback_parts.append("❌ Total rental cost not properly calculated")
        
        # ===== PART 2: CLIENT DOCUMENT VERIFICATION =====
        success_doc, doc, error_doc = copy_and_parse_document(
            document_path, copy_from_env, 'docx'
        )

        if not success_doc:
            feedback_parts.append("❌ Client document (chen_family_shoot_plan.docx) not created")
            # Document criteria: 0/5
        else:
            # CRITERION 6: Document exists (already counted by successful load)
            criteria_passed += 1
            feedback_parts.append("✅ Client document created")
            
            # Get document text
            doc_text = get_document_text(doc)
            doc_text_lower = doc_text.lower()
            
            # CRITERION 7: Contains Chen Family name and professional header
            has_chen_name = "chen" in doc_text_lower and "family" in doc_text_lower
            has_professional_header = any(x in doc_text_lower for x in [
                "shoot plan", "session", "timeline", "portrait", "prepared by"
            ])
            
            if has_chen_name and has_professional_header:
                criteria_passed += 1
                feedback_parts.append("✅ Document has professional header with client name")
            else:
                feedback_parts.append("❌ Document missing professional header or client name")
            
            # CRITERION 8: Contains timeline with specific times
            has_timeline = False
            # Look for time patterns like "5:00", "5:00 PM", "5:10", etc.
            time_pattern = r'\d{1,2}:\d{2}'
            times_found = re.findall(time_pattern, doc_text)
            
            if len(times_found) >= 3:  # Should have multiple time entries in timeline
                has_timeline = True
                criteria_passed += 1
                feedback_parts.append(f"✅ Document contains timeline with {len(times_found)} time entries")
            else:
                feedback_parts.append("❌ Document missing detailed timeline")
            
            # CRITERION 9: Contains weather backup plan with specific location
            has_weather_backup = False
            weather_keywords = ["weather", "backup", "rain", "contingency", "alternative"]
            location_keywords = ["lakeside", "park", "pavilion", "covered"]
            
            has_weather_mention = any(x in doc_text_lower for x in weather_keywords)
            has_location_mention = any(x in doc_text_lower for x in location_keywords)
            
            if has_weather_mention and has_location_mention:
                has_weather_backup = True
                criteria_passed += 1
                feedback_parts.append("✅ Document includes weather backup plan with location")
            else:
                feedback_parts.append("❌ Document missing weather backup plan or location")
            
            # CRITERION 10: Document is substantial (shows professionalism)
            word_count = len(doc_text.split())
            is_substantial = word_count >= 100
            
            if is_substantial:
                criteria_passed += 1
                feedback_parts.append(f"✅ Document is substantial ({word_count} words)")
            else:
                feedback_parts.append(f"❌ Document too brief ({word_count} words, need 100+)")
        
        # Calculate final score
        score = int((criteria_passed / total_criteria) * 100)
        passed = score >= 75
        
        feedback = " | ".join(feedback_parts)
        
        # Add summary
        feedback = f"Score: {criteria_passed}/{total_criteria} criteria met. " + feedback

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)