#!/usr/bin/env python3
"""
Verifier for Relationship Contact Log task (relationship_contact_log@1)

Verifies that the agent successfully transformed scattered conversation notes
into a structured multi-sheet contact log spreadsheet.
"""

import sys
import os
import logging
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_sheet_data,
    get_cell_value,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def normalize_sheet_name(name):
    """Normalize sheet names for comparison (lowercase, strip spaces)"""
    if name:
        return name.lower().strip()
    return ""


def find_sheet_by_name(wb, target_name):
    """Find sheet by name (case-insensitive, partial match)"""
    target_normalized = normalize_sheet_name(target_name)
    for sheet_name in wb.sheetnames:
        if target_normalized in normalize_sheet_name(sheet_name):
            return sheet_name
    return None


def check_keywords_in_data(data, keywords, min_matches=1):
    """Check if data contains specified keywords"""
    all_text = " ".join([
        str(cell).lower() 
        for row in data 
        for cell in row 
        if cell is not None
    ])
    
    matches = sum(1 for keyword in keywords if keyword.lower() in all_text)
    return matches >= min_matches, matches


def count_non_empty_rows(data, skip_header=True):
    """Count rows that have at least one non-empty cell"""
    start_idx = 1 if skip_header else 0
    count = 0
    for row in data[start_idx:]:
        if any(cell is not None and str(cell).strip() != "" for cell in row):
            count += 1
    return count


def verify_relationship_contact_log(traj, env_info, task_info):
    """
    Verify the relationship contact log task.
    
    Checks for:
    1. File exists and can be parsed
    2. Has 4 required sheets (or at least 3)
    3. Contact Log sheet with appropriate structure and data
    4. Action Items sheet with appropriate structure and data
    5. Follow-Up Concerns sheet with appropriate structure and data
    6. Important Dates sheet with appropriate structure and data
    7. Data quality and completeness
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/Spreadsheets/martha_contact_log.xlsx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_contact_log_')

    try:
        # Copy and parse the spreadsheet
        success, wb, error = copy_and_parse_document(container_path, copy_from_env, 'xlsx')

        if not success:
            return {
                "passed": False, 
                "score": 0, 
                "feedback": f"Failed to load spreadsheet: {error}"
            }

        score = 0
        max_score = 25
        feedback_parts = []

        # Get sheet names
        sheet_names = wb.sheetnames
        logger.info(f"Found sheets: {sheet_names}")

        # Check 1: File structure (3 points)
        required_sheets = ["contact log", "action items", "follow-up concerns", "important dates"]
        sheets_found = []
        
        for required in required_sheets:
            found_sheet = find_sheet_by_name(wb, required)
            if found_sheet:
                sheets_found.append(required)
        
        sheets_found_count = len(sheets_found)
        
        if sheets_found_count == 4:
            score += 3
            feedback_parts.append(f"✅ All 4 required sheets present")
        elif sheets_found_count == 3:
            score += 2
            feedback_parts.append(f"⚠️ Found 3/4 required sheets: {', '.join(sheets_found)}")
        elif sheets_found_count >= 2:
            score += 1
            feedback_parts.append(f"⚠️ Found {sheets_found_count}/4 required sheets")
        else:
            feedback_parts.append(f"❌ Missing required sheets. Found: {', '.join(sheet_names)}")

        # Check 2: Contact Log sheet (4 points)
        contact_sheet_name = find_sheet_by_name(wb, "contact log")
        if contact_sheet_name:
            contact_data = get_sheet_data(wb, contact_sheet_name, max_rows=50, max_cols=10)
            
            # Check headers (look for date, type, summary keywords)
            header_row = [str(cell).lower() if cell else "" for cell in contact_data[0]]
            has_date = any("date" in h for h in header_row)
            has_type = any("type" in h for h in header_row)
            has_summary = any("summary" in h or "note" in h for h in header_row)
            has_mood = any("mood" in h or "energy" in h for h in header_row)
            
            header_score = sum([has_date, has_type, has_summary or has_mood])
            if header_score >= 3:
                score += 1
                feedback_parts.append("✅ Contact Log has appropriate headers")
            elif header_score >= 2:
                score += 0.5
                feedback_parts.append("⚠️ Contact Log headers incomplete")
            
            # Count entries (should have ~6-10 based on raw notes)
            entries = count_non_empty_rows(contact_data)
            if entries >= 6:
                score += 2
                feedback_parts.append(f"✅ Contact Log has {entries} entries (6+ expected)")
            elif entries >= 3:
                score += 1
                feedback_parts.append(f"⚠️ Contact Log has {entries} entries (6+ expected)")
            else:
                feedback_parts.append(f"❌ Contact Log has only {entries} entries")
            
            # Check for date formatting
            date_col_data = [str(row[0]) if row and len(row) > 0 else "" for row in contact_data[1:8]]
            dates_formatted = sum(1 for d in date_col_data if d and ('/' in d or '-' in d or '3/' in d or '4/' in d))
            
            if dates_formatted >= 3:
                score += 1
                feedback_parts.append("✅ Dates properly formatted")
            elif dates_formatted >= 1:
                score += 0.5
                feedback_parts.append("⚠️ Some dates formatted")
        else:
            feedback_parts.append("❌ Contact Log sheet missing (0/4 points)")

        # Check 3: Action Items sheet (5 points)
        action_sheet_name = find_sheet_by_name(wb, "action items")
        if action_sheet_name:
            action_data = get_sheet_data(wb, action_sheet_name, max_rows=30, max_cols=10)
            
            # Check headers
            header_row = [str(cell).lower() if cell else "" for cell in action_data[0]]
            has_task = any("task" in h for h in header_row)
            has_date = any("date" in h for h in header_row)
            has_status = any("status" in h for h in header_row)
            
            header_score = sum([has_task, has_date, has_status])
            if header_score >= 2:
                score += 1
                feedback_parts.append("✅ Action Items has appropriate headers")
            
            # Count action items (should have ~5-7 based on raw notes)
            actions = count_non_empty_rows(action_data)
            if actions >= 5:
                score += 2
                feedback_parts.append(f"✅ Action Items has {actions} items (5+ expected)")
            elif actions >= 3:
                score += 1
                feedback_parts.append(f"⚠️ Action Items has {actions} items (5+ expected)")
            else:
                feedback_parts.append(f"❌ Action Items has only {actions} items")
            
            # Check for key action items from the notes
            key_actions = ["handyman", "cookbook", "mail", "landlord", "blood sugar", "youtube", "video", "tutorial", "medicare"]
            has_actions, action_count = check_keywords_in_data(action_data, key_actions, min_matches=3)
            
            if action_count >= 4:
                score += 1
                feedback_parts.append(f"✅ Found {action_count} expected action items")
            elif action_count >= 2:
                score += 0.5
                feedback_parts.append(f"⚠️ Found {action_count} expected action items")
            
            # Check for status column usage
            status_keywords = ["overdue", "not started", "pending", "done", "complete", "in progress"]
            has_status_data, _ = check_keywords_in_data(action_data, status_keywords, min_matches=1)
            
            if has_status_data:
                score += 1
                feedback_parts.append("✅ Status tracking implemented")
        else:
            feedback_parts.append("❌ Action Items sheet missing (0/5 points)")

        # Check 4: Follow-Up Concerns sheet (4 points)
        concerns_sheet_name = find_sheet_by_name(wb, "follow-up concerns") or find_sheet_by_name(wb, "concerns")
        if concerns_sheet_name:
            concerns_data = get_sheet_data(wb, concerns_sheet_name, max_rows=30, max_cols=10)
            
            # Check headers
            header_row = [str(cell).lower() if cell else "" for cell in concerns_data[0]]
            has_category = any("category" in h or "type" in h for h in header_row)
            has_details = any("detail" in h or "concern" in h or "issue" in h for h in header_row)
            
            if has_category or has_details:
                score += 1
                feedback_parts.append("✅ Follow-Up Concerns has appropriate headers")
            
            # Count concerns (should have ~4-6)
            concerns = count_non_empty_rows(concerns_data)
            if concerns >= 4:
                score += 1
                feedback_parts.append(f"✅ Follow-Up Concerns has {concerns} items (4+ expected)")
            elif concerns >= 2:
                score += 0.5
                feedback_parts.append(f"⚠️ Follow-Up Concerns has {concerns} items")
            
            # Check for key concerns from notes
            key_concerns = ["ceiling", "leak", "bathroom", "sleep", "knee", "stairs", "a1c", "blood sugar", "glucose", "church"]
            has_concerns, concern_count = check_keywords_in_data(concerns_data, key_concerns, min_matches=2)
            
            if concern_count >= 3:
                score += 1
                feedback_parts.append(f"✅ Found {concern_count} key concerns")
            elif concern_count >= 1:
                score += 0.5
            
            # Check for category usage
            category_keywords = ["health", "home", "social", "financial"]
            has_categories, _ = check_keywords_in_data(concerns_data, category_keywords, min_matches=1)
            
            if has_categories:
                score += 1
                feedback_parts.append("✅ Concerns properly categorized")
        else:
            feedback_parts.append("❌ Follow-Up Concerns sheet missing (0/4 points)")

        # Check 5: Important Dates sheet (3 points)
        dates_sheet_name = find_sheet_by_name(wb, "important dates") or find_sheet_by_name(wb, "dates")
        if dates_sheet_name:
            dates_data = get_sheet_data(wb, dates_sheet_name, max_rows=20, max_cols=10)
            
            # Count date entries (should have ~3-4)
            date_entries = count_non_empty_rows(dates_data)
            if date_entries >= 3:
                score += 1
                feedback_parts.append(f"✅ Important Dates has {date_entries} entries (3+ expected)")
            elif date_entries >= 2:
                score += 0.5
            
            # Check for key dates from notes
            key_dates = ["april 8", "4/8", "april 28", "4/28", "birthday", "doctor", "appointment", "lunch"]
            has_dates, date_count = check_keywords_in_data(dates_data, key_dates, min_matches=2)
            
            if date_count >= 2:
                score += 1
                feedback_parts.append("✅ Key dates captured")
            elif date_count >= 1:
                score += 0.5
            
            # Check for date formatting
            first_col = [str(row[0]) if row and len(row) > 0 else "" for row in dates_data[1:6]]
            dates_formatted = sum(1 for d in first_col if d and ('/' in d or '-' in d or 'april' in d.lower()))
            
            if dates_formatted >= 2:
                score += 1
                feedback_parts.append("✅ Dates properly formatted")
        else:
            feedback_parts.append("❌ Important Dates sheet missing (0/3 points)")

        # Check 6: Data synthesis quality (3 points)
        # Check if contact log has substantive entries
        if contact_sheet_name:
            contact_data = get_sheet_data(wb, contact_sheet_name, max_rows=20, max_cols=10)
            
            # Look for summary-like content (cells with reasonable length)
            cell_lengths = []
            for row in contact_data[1:8]:
                for cell in row[1:]:  # Skip first column (likely dates)
                    if cell and isinstance(cell, str) and len(cell) > 10:
                        cell_lengths.append(len(cell))
            
            avg_length = sum(cell_lengths) / len(cell_lengths) if cell_lengths else 0
            
            if avg_length > 20:  # Substantive summaries
                score += 2
                feedback_parts.append("✅ Contact summaries are substantive")
            elif avg_length > 10:
                score += 1
                feedback_parts.append("⚠️ Contact summaries could be more detailed")
            
            # Check for mood/energy observations
            mood_words = ["tired", "worried", "excited", "stressed", "happy", "overwhelmed", "cheerful", "frustrated", "loves", "brightens"]
            has_mood, _ = check_keywords_in_data(contact_data, mood_words, min_matches=1)
            
            if has_mood:
                score += 1
                feedback_parts.append("✅ Mood/energy observations included")

        # Check 7: Practical usability (3 points)
        # Award points for having well-organized structure
        if sheets_found_count >= 3:
            score += 1
            feedback_parts.append("✅ Spreadsheet is well-organized")
        
        # Check for reasonable data distribution
        total_data_rows = 0
        if contact_sheet_name:
            contact_data = get_sheet_data(wb, contact_sheet_name, max_rows=50, max_cols=10)
            total_data_rows += count_non_empty_rows(contact_data)
        if action_sheet_name:
            action_data = get_sheet_data(wb, action_sheet_name, max_rows=30, max_cols=10)
            total_data_rows += count_non_empty_rows(action_data)
        
        if total_data_rows >= 10:
            score += 1
            feedback_parts.append("✅ Comprehensive data extraction")
        elif total_data_rows >= 6:
            score += 0.5
        
        # Check if the spreadsheet shows effort (file size proxy)
        if sheets_found_count >= 3 and total_data_rows >= 8:
            score += 1
            feedback_parts.append("✅ Task completed with thoroughness")

        # Ensure score doesn't exceed max
        score = min(score, max_score)
        
        # Determine pass/fail (72% threshold = 18/25)
        passed = score >= 18
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "max_score": max_score,
            "feedback": f"Score: {score}/{max_score} | {feedback}"
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


# Entry point for task verification
def verify(copy_from_env_fn) -> dict:
    """Entry point called by the verification system"""
    # The verification system passes the copy function directly
    # We need to wrap it in the expected format
    env_info = {'copy_from_env': copy_from_env_fn}
    return verify_relationship_contact_log(None, env_info, None)