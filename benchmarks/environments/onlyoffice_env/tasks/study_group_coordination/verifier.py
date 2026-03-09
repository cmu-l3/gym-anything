#!/usr/bin/env python3
"""
Verifier for Study Group Coordination task

This verifies that the agent created a comprehensive study group coordination document
with proper structure, table, meeting schedule, and topic assignments.
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
    count_paragraphs,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_study_group_coordination(traj, env_info, task_info):
    """
    Verify the study group coordination document.
    
    Scoring breakdown (100 points total):
    - Document parseable and has content: 20 points
    - Title and structure: 15 points
    - Table with member data: 25 points
    - Meeting schedule present: 15 points
    - Topic assignments clear: 15 points
    - Formatted list present: 10 points
    
    Pass threshold: 75/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False, 
            "score": 0.0, 
            "feedback": "Copy function not available in environment"
        }

    container_path = "/home/ga/Documents/TextDocuments/study_group_plan.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_study_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(
            container_path,
            copy_from_env,
            'docx'
        )

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Could not parse document: {error}"
            }

        # Initialize scoring
        score = 0
        feedback_parts = []
        
        # Extract document text for analysis
        text = get_document_text(doc).lower()
        text_length = len(text.strip())
        
        # ============================================================
        # CRITERION 1: Document exists and is parseable (20 points)
        # ============================================================
        if text_length > 100:  # Ensure document has substantial content
            score += 20
            feedback_parts.append(f"✅ Document parsed successfully ({text_length} chars)")
        elif text_length > 20:
            score += 10
            feedback_parts.append(f"⚠️ Document parsed but minimal content ({text_length} chars)")
        else:
            feedback_parts.append(f"❌ Document nearly empty ({text_length} chars)")
        
        # ============================================================
        # CRITERION 2: Title and structure (15 points)
        # ============================================================
        para_count = count_paragraphs(doc)
        
        # Check for title keywords in first 200 characters
        title_keywords = [
            "study group", "coordination", "biology", 
            "exam", "final", "plan", "schedule"
        ]
        has_title = any(keyword in text[:200] for keyword in title_keywords)
        
        # Check for bold text in first few paragraphs (indicates title formatting)
        has_formatted_title = False
        for i, para in enumerate(doc.paragraphs[:3]):
            if para.text.strip():
                for run in para.runs:
                    if run.bold and len(run.text.strip()) > 5:
                        has_formatted_title = True
                        break
                if has_formatted_title:
                    break
        
        structure_score = 0
        if has_title:
            structure_score += 8
        if has_formatted_title:
            structure_score += 4
        if para_count >= 4:
            structure_score += 3
        
        structure_score = min(15, structure_score)
        score += structure_score
        
        if structure_score >= 12:
            feedback_parts.append(f"✅ Document has title and structure ({para_count} paragraphs)")
        else:
            feedback_parts.append(f"⚠️ Document structure incomplete ({para_count} paragraphs, title: {has_title})")
        
        # ============================================================
        # CRITERION 3: Table with member data (25 points)
        # ============================================================
        table_count = count_tables(doc)
        table_score = 0
        
        if table_count > 0:
            table = doc.tables[0]
            row_count = len(table.rows)
            col_count = len(table.columns)
            
            # Extract all table text
            table_text = ""
            for row in table.rows:
                for cell in row.cells:
                    table_text += " " + cell.text.lower()
            
            # Check for member names
            member_names = ["alex", "jordan", "sam", "casey", "morgan"]
            names_found = sum([name in table_text for name in member_names])
            
            # Check for availability keywords
            availability_keywords = [
                "evening", "morning", "afternoon", "monday", "tuesday", 
                "wednesday", "thursday", "friday", "available", "free"
            ]
            availability_found = sum([kw in table_text for kw in availability_keywords])
            
            # Scoring for table
            if col_count >= 2:
                table_score += 5
            if row_count >= 5:  # At least 5 members
                table_score += 5
            
            # Score based on how many members are found
            table_score += min(10, names_found * 2)
            
            # Score based on availability info
            if availability_found >= 2:
                table_score += 5
            
            table_score = min(25, table_score)
            score += table_score
            
            if table_score >= 20:
                feedback_parts.append(
                    f"✅ Table complete: {row_count} rows, {col_count} cols, "
                    f"{names_found}/5 members, {availability_found} availability notes"
                )
            elif table_score >= 10:
                feedback_parts.append(
                    f"⚠️ Table incomplete: {row_count} rows, {col_count} cols, "
                    f"{names_found}/5 members"
                )
            else:
                feedback_parts.append(f"❌ Table exists but lacks member data")
        else:
            feedback_parts.append("❌ No table found - member information should be in a table")
        
        # ============================================================
        # CRITERION 4: Meeting schedule (15 points)
        # ============================================================
        # Check for date indicators
        date_keywords = [
            "may", "tuesday", "thursday", "monday", "wednesday", "friday",
            "2nd", "4th", "8th", "1st", "3rd", "5th", "6th", "7th"
        ]
        dates_found = sum([kw in text for kw in date_keywords])
        
        # Check for time indicators
        time_keywords = [
            "4:00", "3:30", "6:00", "pm", "p.m.", "a.m.", "am",
            "morning", "afternoon", "evening"
        ]
        times_found = sum([kw in text for kw in time_keywords])
        
        # Check for location indicators
        location_keywords = [
            "library", "student center", "room 204", "room", "center", "building"
        ]
        locations_found = sum([kw in text for kw in location_keywords])
        
        # Check for "session" mentions (indicates structured meeting schedule)
        session_count = text.count("session")
        
        meeting_score = 0
        if dates_found >= 2:
            meeting_score += 5
        elif dates_found >= 1:
            meeting_score += 2
        
        if times_found >= 2:
            meeting_score += 5
        elif times_found >= 1:
            meeting_score += 2
        
        if locations_found >= 1:
            meeting_score += 3
        
        if session_count >= 2:
            meeting_score += 2
        
        meeting_score = min(15, meeting_score)
        score += meeting_score
        
        if meeting_score >= 12:
            feedback_parts.append(
                f"✅ Meeting schedule complete (dates: {dates_found}, times: {times_found}, locations: {locations_found})"
            )
        else:
            feedback_parts.append(
                f"⚠️ Meeting schedule incomplete (dates: {dates_found}/2, times: {times_found}/2)"
            )
        
        # ============================================================
        # CRITERION 5: Topic assignments (15 points)
        # ============================================================
        # Check for biology topics
        biology_topics = [
            "cell", "dna", "photosynthesis", "genetics", "mitosis", 
            "meiosis", "evolution", "ecology", "respiration", "protein",
            "organelle", "replication", "synthesis", "mendelian"
        ]
        topics_found = sum([topic in text for topic in biology_topics])
        
        # Check for assignment language
        assignment_keywords = [
            "responsible", "covering", "assigned", "assignment", 
            "cover", "prepare", "practice"
        ]
        has_assignments = sum([kw in text for kw in assignment_keywords])
        
        # Check if member names appear near topic words (indicates assignment)
        member_near_topic = False
        for name in ["alex", "jordan", "sam", "casey", "morgan"]:
            if name in text:
                # Find position of name
                name_pos = text.find(name)
                # Check if a topic word appears within 100 chars
                context = text[max(0, name_pos-50):min(len(text), name_pos+100)]
                if any(topic in context for topic in biology_topics):
                    member_near_topic = True
                    break
        
        assignment_score = 0
        if topics_found >= 3:
            assignment_score += 7
        elif topics_found >= 1:
            assignment_score += 3
        
        if has_assignments >= 2 or member_near_topic:
            assignment_score += 5
        elif has_assignments >= 1:
            assignment_score += 2
        
        if member_near_topic:
            assignment_score += 3
        
        assignment_score = min(15, assignment_score)
        score += assignment_score
        
        if assignment_score >= 12:
            feedback_parts.append(
                f"✅ Topic assignments clear ({topics_found} topics, clear assignments)"
            )
        else:
            feedback_parts.append(
                f"⚠️ Topic assignments unclear ({topics_found} topics, need clearer assignments)"
            )
        
        # ============================================================
        # CRITERION 6: Formatted list (10 points)
        # ============================================================
        # Check for bullet point or numbered list indicators in text
        has_text_bullets = any([
            "•" in text,
            text.count("\n-") >= 3,
            text.count("\n*") >= 3,
        ])
        
        # Check for numbered list patterns
        has_numbered = bool(re.search(r'\n\s*[0-9]+[\.\)]\s+', text))
        
        # Check document structure for actual list elements
        list_count = 0
        list_items_with_topics = 0
        
        for para in doc.paragraphs:
            para_text = para.text.strip()
            if not para_text:
                continue
                
            # Check style name
            style_name = para.style.name.lower() if para.style else ""
            
            # Check if it's a list style or starts with list markers
            is_list = (
                "list" in style_name or
                para_text.startswith(("•", "-", "*")) or
                re.match(r'^[0-9]+[\.\)]\s+', para_text)
            )
            
            if is_list:
                list_count += 1
                # Check if list item contains a biology topic
                if any(topic in para_text.lower() for topic in biology_topics):
                    list_items_with_topics += 1
        
        list_score = 0
        if list_count >= 3:
            list_score += 5
            if list_items_with_topics >= 3:
                list_score += 5
            elif list_items_with_topics >= 1:
                list_score += 3
        elif list_count >= 1 or has_text_bullets or has_numbered:
            list_score += 3
        
        list_score = min(10, list_score)
        score += list_score
        
        if list_score >= 8:
            feedback_parts.append(
                f"✅ Formatted list present ({list_count} items, {list_items_with_topics} with topics)"
            )
        elif list_score >= 5:
            feedback_parts.append(f"⚠️ List present but minimal ({list_count} items)")
        else:
            feedback_parts.append("❌ No formatted list found - topics should be in bullet/numbered list")
        
        # ============================================================
        # FINAL ASSESSMENT
        # ============================================================
        passed = score >= 75  # Need 75/100 to pass
        normalized_score = score / 100.0
        
        feedback = " | ".join(feedback_parts)
        feedback += f" | TOTAL: {score}/100"
        
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
