#!/usr/bin/env python3
"""
Verifier for Court Exhibit List task

Verifies that a formal small claims court exhibit list was created correctly
with proper structure, all required exhibits in chronological order, and
accurate descriptions.
"""

import sys
import os
import logging
import tempfile
import re
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# Expected exhibits with key information
EXPECTED_EXHIBITS = [
    {
        "letter": "A",
        "date": "01/15/2025",
        "date_obj": datetime(2025, 1, 15),
        "keywords": ["contract", "renovation", "bathroom", "signed", "both parties"],
        "required_keywords": ["contract"]
    },
    {
        "letter": "B",
        "date": "01/15/2025",
        "date_obj": datetime(2025, 1, 15),
        "keywords": ["invoice", "1047", "3500", "3,500", "$3,500", "deposit", "payment"],
        "required_keywords": ["invoice", "deposit"]
    },
    {
        "letter": "C",
        "date": "01/16/2025",
        "date_obj": datetime(2025, 1, 16),
        "keywords": ["bank", "statement", "check", "2891", "cleared", "3500", "3,500", "$3,500"],
        "required_keywords": ["bank", "check"]
    },
    {
        "letter": "D",
        "date": "01/22/2025",
        "date_obj": datetime(2025, 1, 22),
        "keywords": ["text", "message", "defendant", "work", "begin", "january", "24"],
        "required_keywords": ["text", "message"]
    },
    {
        "letter": "E",
        "date": "01/30/2025",
        "date_obj": datetime(2025, 1, 30),
        "keywords": ["email", "plaintiff", "requesting", "status", "update"],
        "required_keywords": ["email"]
    },
    {
        "letter": "F",
        "date": "02/03/2025",
        "date_obj": datetime(2025, 2, 3),
        "keywords": ["text", "message", "defendant", "family", "emergency", "return", "week"],
        "required_keywords": ["text", "family emergency"]
    },
    {
        "letter": "G",
        "date": "02/18/2025",
        "date_obj": datetime(2025, 2, 18),
        "keywords": ["certified", "mail", "receipt", "demand", "letter", "defendant"],
        "required_keywords": ["certified", "demand"]
    },
    {
        "letter": "H",
        "date": "02/20/2025",
        "date_obj": datetime(2025, 2, 20),
        "keywords": ["photo", "photos", "bathroom", "unfinished", "exposed", "plumbing"],
        "required_keywords": ["photo"]
    }
]


def parse_date_flexible(date_str):
    """
    Try to parse date in various common formats
    Returns datetime object or None
    """
    if not date_str or not isinstance(date_str, str):
        return None
    
    date_str = date_str.strip()
    
    # Common formats to try
    formats = [
        "%m/%d/%Y",      # 01/15/2025
        "%m/%d/%y",      # 01/15/25
        "%m-%d-%Y",      # 01-15-2025
        "%Y-%m-%d",      # 2025-01-15
        "%B %d, %Y",     # January 15, 2025
        "%b %d, %Y",     # Jan 15, 2025
    ]
    
    for fmt in formats:
        try:
            return datetime.strptime(date_str, fmt)
        except:
            continue
    
    # Try regex extraction for flexible formats
    match = re.search(r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})', date_str)
    if match:
        try:
            month, day, year = int(match.group(1)), int(match.group(2)), int(match.group(3))
            return datetime(year, month, day)
        except:
            pass
    
    return None


def extract_exhibit_letter(text):
    """
    Extract exhibit letter (A-H) from text
    """
    text_upper = text.upper().strip()
    
    # Look for "Exhibit A", "EXHIBIT A", "A", etc.
    match = re.search(r'EXHIBIT\s*([A-H])|^([A-H])$|^([A-H])\s|EXHI?BI?T?\s*([A-H])', text_upper)
    if match:
        for group in match.groups():
            if group and group in 'ABCDEFGH':
                return group
    
    return None


def check_description_keywords(description, exhibit_info):
    """
    Check if description contains required keywords for the exhibit
    Returns (score, matched_keywords)
    """
    desc_lower = description.lower()
    
    # Remove common punctuation for better matching
    desc_lower = re.sub(r'[^\w\s]', ' ', desc_lower)
    
    matched = []
    for keyword in exhibit_info["keywords"]:
        if keyword.lower() in desc_lower:
            matched.append(keyword)
    
    # Check required keywords
    required_matched = sum(1 for kw in exhibit_info["required_keywords"] 
                          if any(kw.lower() in m.lower() for m in matched))
    
    required_count = len(exhibit_info["required_keywords"])
    
    if required_matched >= required_count:
        return 1.0, matched
    elif required_matched > 0:
        return 0.5, matched
    else:
        return 0.0, matched


def verify_court_exhibit_list(traj, env_info, task_info):
    """
    Verify that the court exhibit list was created correctly.
    
    Verification Criteria:
    1. Document exists and can be parsed
    2. Contains case number SC-2025-04157
    3. Contains document title "EXHIBIT LIST"
    4. Has a table with 3 columns
    5. All 8 exhibits (A-H) are present
    6. Exhibits are in chronological order
    7. Descriptions contain key identifying information
    8. Table has appropriate structure (8-9 rows including header)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/Exhibit_List_SC-2025-04157.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_court_')

    try:
        # 1. Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"Failed to load document: {error}"
            }

        feedback_parts = []
        scores = {
            "structure": 0.0,
            "case_info": 0.0,
            "table_structure": 0.0,
            "exhibits_present": 0.0,
            "chronological_order": 0.0,
            "descriptions": 0.0
        }

        # 2. Check document header content
        full_text = get_document_text(doc)
        full_text_upper = full_text.upper()

        # Check for case number
        has_case_number = "SC-2025-04157" in full_text
        has_exhibit_list_title = "EXHIBIT LIST" in full_text_upper
        has_parties = "MITCHELL" in full_text_upper and "RENOVATIONS" in full_text_upper

        if has_case_number:
            scores["case_info"] += 0.4
        if has_exhibit_list_title:
            scores["case_info"] += 0.3
        if has_parties:
            scores["case_info"] += 0.3
        
        if scores["case_info"] >= 0.7:
            feedback_parts.append("✅ Case header present (case #, title, parties)")
        elif scores["case_info"] >= 0.4:
            feedback_parts.append("⚠️  Case header partially present")
        else:
            feedback_parts.append("❌ Missing case header information")

        # 3. Verify table exists
        if len(doc.tables) == 0:
            feedback_parts.append("❌ No table found - exhibit list requires table structure")
            return {
                "passed": False,
                "score": int(scores["case_info"] * 20),
                "feedback": " | ".join(feedback_parts)
            }

        table = doc.tables[0]

        # 4. Check table structure (should have 3 columns)
        num_columns = len(table.columns)
        if num_columns == 3:
            scores["table_structure"] = 1.0
            feedback_parts.append("✅ Table has correct 3-column structure")
        else:
            scores["table_structure"] = 0.3
            feedback_parts.append(f"❌ Table has {num_columns} columns (expected 3)")

        # 5. Extract table data
        table_data = []
        for i, row in enumerate(table.rows):
            cells = [cell.text.strip() for cell in row.cells]
            table_data.append(cells)

        if len(table_data) < 2:
            feedback_parts.append("❌ Table has insufficient rows")
            return {
                "passed": False,
                "score": int((scores["case_info"] + scores["table_structure"]) * 10),
                "feedback": " | ".join(feedback_parts)
            }

        # Skip header row (first row)
        data_rows = table_data[1:]

        # 6. Find and verify exhibits
        found_exhibits = []
        missing_exhibits = []
        
        for expected in EXPECTED_EXHIBITS:
            found = False
            best_match = None
            best_score = 0.0
            
            for row_idx, row in enumerate(data_rows):
                if len(row) < 3:
                    continue
                
                exhibit_col = row[0]
                date_col = row[1]
                desc_col = row[2]
                
                # Check if exhibit letter matches
                exhibit_letter = extract_exhibit_letter(exhibit_col)
                
                if exhibit_letter == expected["letter"]:
                    # Check description quality
                    desc_score, matched_keywords = check_description_keywords(desc_col, expected)
                    
                    if desc_score >= best_score:
                        best_score = desc_score
                        best_match = {
                            "letter": expected["letter"],
                            "row_position": row_idx,
                            "date_str": date_col,
                            "description": desc_col,
                            "desc_score": desc_score,
                            "matched_keywords": matched_keywords
                        }
                        
                        if desc_score >= 0.5:
                            found = True
            
            if found and best_match:
                found_exhibits.append(best_match)
            else:
                missing_exhibits.append(expected["letter"])

        # Calculate exhibit presence score
        exhibit_count = len(found_exhibits)
        scores["exhibits_present"] = exhibit_count / len(EXPECTED_EXHIBITS)
        
        if exhibit_count == 8:
            feedback_parts.append(f"✅ All 8 exhibits present (A-H)")
        elif exhibit_count >= 6:
            feedback_parts.append(f"⚠️  Found {exhibit_count}/8 exhibits")
        else:
            feedback_parts.append(f"❌ Only {exhibit_count}/8 exhibits found")
        
        if missing_exhibits:
            feedback_parts.append(f"   Missing: {', '.join(missing_exhibits)}")

        # 7. Check chronological ordering
        if len(found_exhibits) >= 2:
            order_correct = True
            for i in range(len(found_exhibits) - 1):
                if found_exhibits[i]["row_position"] > found_exhibits[i+1]["row_position"]:
                    order_correct = False
                    break
            
            if order_correct:
                scores["chronological_order"] = 1.0
                feedback_parts.append("✅ Exhibits in correct chronological order")
            else:
                scores["chronological_order"] = 0.3
                feedback_parts.append("❌ Exhibits not in chronological order")
        elif len(found_exhibits) == 1:
            scores["chronological_order"] = 0.5
        else:
            scores["chronological_order"] = 0.0

        # 8. Check description quality
        if found_exhibits:
            avg_desc_score = sum(ex["desc_score"] for ex in found_exhibits) / len(found_exhibits)
            scores["descriptions"] = avg_desc_score
            
            if avg_desc_score >= 0.8:
                feedback_parts.append("✅ Descriptions accurate and complete")
            elif avg_desc_score >= 0.5:
                feedback_parts.append("⚠️  Descriptions partially complete")
            else:
                feedback_parts.append("❌ Descriptions missing key information")
        else:
            scores["descriptions"] = 0.0

        # 9. Calculate final score
        # Weighted scoring:
        # - Case info: 10%
        # - Table structure: 10%
        # - Exhibits present: 40%
        # - Chronological order: 20%
        # - Descriptions: 20%
        
        final_score = (
            scores["case_info"] * 0.10 +
            scores["table_structure"] * 0.10 +
            scores["exhibits_present"] * 0.40 +
            scores["chronological_order"] * 0.20 +
            scores["descriptions"] * 0.20
        )
        
        # Convert to percentage
        final_score_pct = final_score * 100
        
        # Pass threshold: 80%
        passed = final_score >= 0.80

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": final_score_pct,
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
