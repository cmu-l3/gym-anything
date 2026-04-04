#!/usr/bin/env python3
"""
Verifier for union_organizing_tracker@1
Verifies workplace organizing tracker document creation
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


def verify_union_organizing_tracker(traj, env_info, task_info):
    """
    Verify the union organizing tracker document.

    Checks:
    1. Document Structure (30 points): Title, subtitle, confidentiality note, required sections
    2. Issues Table (25 points): 5 columns, 6+ rows, appropriate categories
    3. Rights Information (15 points): Labor law references, NLRA/Section 7, NLRB contact
    4. Interest Tracker Table (15 points): 3 columns, 8+ rows, interest levels, security-conscious
    5. Action Plan (10 points): 5+ action items, dates/timeframes
    6. Overall Quality (5 points): Content quality, formatting

    Passing threshold: 75/100
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/workplace_tracker.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_union_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0, "feedback": f"❌ Could not find or parse document: {error}"}

        # Extract full text for analysis
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()

        feedback_parts = []
        score = 0

        # === 1. DOCUMENT STRUCTURE (30 points) ===
        structure_score = 0

        # Check for appropriate title
        if "workplace safety and fairness" in full_text_lower or \
           "workplace issues" in full_text_lower or \
           ("workplace" in full_text_lower and "organizing" in full_text_lower):
            structure_score += 8
            feedback_parts.append("✅ Appropriate title found")
        else:
            feedback_parts.append("❌ Missing appropriate title")

        # Check for subtitle or date
        if "documentation" in full_text_lower or "action plan" in full_text_lower or \
           re.search(r'\d{4}', full_text) or re.search(r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)', full_text_lower):
            structure_score += 4
            feedback_parts.append("✅ Subtitle/date present")
        else:
            feedback_parts.append("⚠️ Missing subtitle or date")

        # Check for confidentiality note
        if "confidential" in full_text_lower or \
           ("organizing" in full_text_lower and "purposes" in full_text_lower):
            structure_score += 5
            feedback_parts.append("✅ Confidentiality note present")
        else:
            feedback_parts.append("⚠️ No confidentiality note")

        # Check for required section headers
        required_sections = {
            "documented issues": ("issue", "incident", "problem", "documented"),
            "know your rights": ("rights", "labor", "law", "legal"),
            "interest": ("interest", "support", "tracker", "department"),
            "next steps": ("next", "action", "steps", "plan")
        }

        sections_found = 0
        for section_name, keywords in required_sections.items():
            # Check if any keyword combination appears
            if any(keyword in full_text_lower for keyword in keywords):
                sections_found += 1

        structure_score += min(sections_found * 3, 13)  # Up to 13 points for 4+ sections
        feedback_parts.append(f"✅ Found {sections_found}/4 required sections")

        score += min(structure_score, 30)

        # === 2. ISSUES TABLE (25 points) ===
        issues_score = 0
        table_count = count_tables(doc)

        if table_count >= 1:
            issues_score += 8
            feedback_parts.append(f"✅ Found {table_count} table(s)")

            # Analyze first table (should be issues table)
            if doc.tables:
                first_table = doc.tables[0]
                row_count = len(first_table.rows)
                col_count = len(first_table.columns) if first_table.rows else 0

                # Check column count
                if col_count >= 4:
                    issues_score += 5
                    feedback_parts.append(f"✅ Issues table has {col_count} columns")
                elif col_count >= 3:
                    issues_score += 3
                    feedback_parts.append(f"⚠️ Issues table has {col_count} columns (expected 5)")
                else:
                    feedback_parts.append(f"❌ Issues table has insufficient columns: {col_count}")

                # Check row count (header + at least 6 data rows)
                if row_count >= 7:
                    issues_score += 6
                    feedback_parts.append(f"✅ Issues table has {row_count-1} incident rows")
                elif row_count >= 4:
                    issues_score += 3
                    feedback_parts.append(f"⚠️ Issues table has {row_count-1} incident rows (need 6)")
                else:
                    feedback_parts.append(f"❌ Issues table has insufficient rows: {row_count}")

                # Check for appropriate categories and content
                table_text = ""
                for row in first_table.rows:
                    for cell in row.cells:
                        table_text += cell.text.lower() + " "

                category_keywords = ["safety", "wage", "break", "retaliation", "overtime", "heat", "bathroom"]
                categories_found = sum(1 for keyword in category_keywords if keyword in table_text)

                if categories_found >= 3:
                    issues_score += 6
                    feedback_parts.append(f"✅ Issues table contains {categories_found} relevant categories")
                elif categories_found >= 1:
                    issues_score += 3
                    feedback_parts.append(f"⚠️ Issues table contains {categories_found} relevant categories")
                else:
                    feedback_parts.append("❌ Issues table missing relevant categories")
        else:
            feedback_parts.append("❌ No tables found (need at least 2 tables)")

        score += min(issues_score, 25)

        # === 3. RIGHTS INFORMATION (15 points) ===
        rights_score = 0

        # Check for NLRA/Section 7 references
        if "nlra" in full_text_lower or "section 7" in full_text_lower or \
           ("national labor relations" in full_text_lower and "act" in full_text_lower):
            rights_score += 5
            feedback_parts.append("✅ References NLRA/Section 7")
        else:
            feedback_parts.append("⚠️ Missing NLRA/Section 7 reference")

        # Check for NLRB contact information
        if "nlrb" in full_text_lower or \
           ("national labor relations board" in full_text_lower) or \
           (re.search(r'\d{3}[-.]?\d{3}[-.]?\d{4}', full_text) and "labor" in full_text_lower):
            rights_score += 5
            feedback_parts.append("✅ Includes NLRB/contact information")
        else:
            feedback_parts.append("⚠️ Missing NLRB contact information")

        # Check for rights-related keywords
        rights_keywords = ["organize", "organizing", "union", "discuss wages", "can't be fired", 
                          "protected", "right to", "collective", "protected activity"]
        rights_found = sum(1 for keyword in rights_keywords if keyword in full_text_lower)

        if rights_found >= 3:
            rights_score += 5
            feedback_parts.append(f"✅ Found {rights_found} rights-related concepts")
        elif rights_found >= 1:
            rights_score += 2
            feedback_parts.append(f"⚠️ Found only {rights_found} rights-related concepts")
        else:
            feedback_parts.append("❌ Missing rights information")

        score += min(rights_score, 15)

        # === 4. INTEREST TRACKER TABLE (15 points) ===
        interest_score = 0

        if table_count >= 2:
            # Check second table (or search for interest-related table)
            interest_table = None
            for table in doc.tables:
                table_text = ""
                for row in table.rows[:3]:  # Check first few rows
                    for cell in row.cells:
                        table_text += cell.text.lower() + " "
                
                # Identify interest tracker table
                if any(keyword in table_text for keyword in ["interest", "support", "department", "shift", "undecided"]):
                    interest_table = table
                    break

            if interest_table:
                row_count = len(interest_table.rows)
                col_count = len(interest_table.columns) if interest_table.rows else 0

                # Check column count (should be 3)
                if col_count >= 3:
                    interest_score += 5
                    feedback_parts.append(f"✅ Interest tracker has {col_count} columns")
                elif col_count >= 2:
                    interest_score += 2
                    feedback_parts.append(f"⚠️ Interest tracker has {col_count} columns (expected 3)")

                # Check row count (header + at least 8 data rows)
                if row_count >= 9:
                    interest_score += 5
                    feedback_parts.append(f"✅ Interest tracker has {row_count-1} entries")
                elif row_count >= 5:
                    interest_score += 2
                    feedback_parts.append(f"⚠️ Interest tracker has {row_count-1} entries (need 8)")

                # Check for interest level categories
                table_text = ""
                for row in interest_table.rows:
                    for cell in row.cells:
                        table_text += cell.text.lower() + " "

                interest_keywords = ["support", "interested", "undecided", "opposed", "unknown", "strong"]
                interest_found = sum(1 for keyword in interest_keywords if keyword in table_text)

                if interest_found >= 2:
                    interest_score += 3
                    feedback_parts.append("✅ Interest levels categorized")
                elif interest_found >= 1:
                    interest_score += 1

                # Check for department/shift organization (security-conscious: no individual names)
                dept_keywords = ["shift", "department", "area", "team", "warehouse", "floor", "night", "day"]
                dept_found = sum(1 for keyword in dept_keywords if keyword in table_text)

                if dept_found >= 2:
                    interest_score += 2
                    feedback_parts.append("✅ Organized by department/shift (security-conscious)")
                elif dept_found >= 1:
                    interest_score += 1
            else:
                feedback_parts.append("⚠️ Could not identify interest tracker table")
                interest_score += 2  # Partial credit if table exists but not clearly identified
        else:
            feedback_parts.append("❌ Missing second table (interest tracker)")

        score += min(interest_score, 15)

        # === 5. ACTION PLAN (10 points) ===
        action_score = 0

        # Look for action-related keywords
        action_keywords = ["contact", "meeting", "meet", "documentation", "document", "gather", 
                          "research", "organize", "identify", "committee", "union organizer"]
        actions_found = sum(1 for keyword in action_keywords if keyword in full_text_lower)

        if actions_found >= 5:
            action_score += 5
            feedback_parts.append(f"✅ Found {actions_found} action-related items")
        elif actions_found >= 3:
            action_score += 3
            feedback_parts.append(f"⚠️ Found {actions_found} action-related items (need 5)")
        elif actions_found >= 1:
            action_score += 1

        # Check for dates/timeframes in action section
        date_patterns = [
            r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}',  # Date formats
            r'\d{4}-\d{2}-\d{2}',
            r'by \w+\s+\d{1,2}',  # by December 15
            r'by \w+',  # by Friday
            r'within \w+ (week|month|day)',
            r'(week|month) of \w+',
            r'(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\w* \d{1,2}',
        ]

        dates_found = 0
        for pattern in date_patterns:
            if re.search(pattern, full_text_lower):
                dates_found += 1

        if dates_found >= 3:
            action_score += 5
            feedback_parts.append("✅ Action items include target dates/timeframes")
        elif dates_found >= 1:
            action_score += 2
            feedback_parts.append("⚠️ Some action items have dates (need 3+)")

        score += min(action_score, 10)

        # === 6. OVERALL QUALITY (5 points) ===
        quality_score = 0

        # Check word count (should be substantial)
        word_count = len(full_text.split())
        if word_count > 250:
            quality_score += 2
            feedback_parts.append(f"✅ Document has substantial content ({word_count} words)")
        elif word_count > 150:
            quality_score += 1
            feedback_parts.append(f"⚠️ Document content is brief ({word_count} words)")
        else:
            feedback_parts.append(f"❌ Document content is insufficient ({word_count} words)")

        # Check that template instructions were removed/replaced
        if "[add" not in full_text_lower and "begin your document below" not in full_text_lower:
            quality_score += 2
            feedback_parts.append("✅ Template instructions removed")
        else:
            feedback_parts.append("⚠️ Template instructions still present")

        # Check for appropriate table count
        if table_count >= 2:
            quality_score += 1

        score += min(quality_score, 5)

        # === FINAL RESULT ===
        passed = score >= 75
        feedback = " | ".join(feedback_parts) + f" | **TOTAL SCORE: {score}/100**"

        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"❌ Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)