#!/usr/bin/env python3
"""
Verifier for Legal Timeline Assembly task
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
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_dates_from_text(text):
    """Extract dates in MM/DD/YYYY format from text"""
    # Match dates like 06/15/2024, 07/03/2024, etc.
    date_pattern = r'\b(\d{2}/\d{2}/\d{4})\b'
    matches = re.findall(date_pattern, text)
    dates = []
    for match in matches:
        try:
            dt = datetime.strptime(match, '%m/%d/%Y')
            dates.append((match, dt))
        except:
            pass
    return dates


def check_chronological_order(dates):
    """Check if dates are in chronological order"""
    if len(dates) < 2:
        return True
    
    for i in range(len(dates) - 1):
        if dates[i][1] > dates[i+1][1]:
            return False
    return True


def verify_legal_timeline_assembly(traj, env_info, task_info):
    """
    Verify legal timeline has been properly completed and formatted.

    Checks:
    1. Draft instructions removed
    2. All required events from notes file integrated
    3. No placeholder text ([TBD], [INCOMPLETE])
    4. Key event descriptions present
    5. Table structure intact
    6. Chronological ordering (best effort)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/timeline_draft.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_timeline_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {"passed": False, "score": 0.0, "feedback": f"Document parsing failed: {error}"}

        feedback_parts = []
        score = 0.0

        # Get full document text
        doc_text = get_document_text(doc)
        doc_text_lower = doc_text.lower()

        # Check 1: Instructions removed (15 points)
        instruction_markers = ["INSTRUCTIONS FOR COMPLETION", "Remove this instruction", "[DRAFT", "INSTRUCTIONS:"]
        has_instructions = any(marker.lower() in doc_text_lower for marker in instruction_markers)
        
        if not has_instructions:
            score += 15
            feedback_parts.append("✅ Draft instructions removed")
        else:
            feedback_parts.append("❌ Draft instructions still present")

        # Check 2: Table exists (5 points)
        num_tables = count_tables(doc)
        if num_tables >= 1:
            score += 5
            feedback_parts.append("✅ Timeline table present")
            
            table = doc.tables[0]
            num_rows = len(table.rows)
            
            # Check table has sufficient entries (original 7 + header + 5 new = at least 13 rows)
            if num_rows >= 12:
                score += 5
                feedback_parts.append(f"✅ Timeline has sufficient entries ({num_rows} rows)")
            else:
                feedback_parts.append(f"⚠️ Timeline may be incomplete ({num_rows} rows, expected ≥12)")
        else:
            feedback_parts.append("❌ Timeline table missing")

        # Check 3: Required events from notes file present (30 points)
        # These are the 5 events that should be added from additional_events.txt
        required_events = [
            ("07/03/2024", "first water leak"),
            ("07/20/2024", "second.*leak"),  # regex pattern
            ("08/05/2024", "formal.*complaint.*certified"),
            ("08/30/2024", "landlord responded"),
            ("09/15/2024", "mold inspector.*stachybotrys")
        ]
        
        events_found = 0
        for event_date, event_desc_pattern in required_events:
            # Check if both date and description pattern are in document
            if event_date in doc_text:
                # Check for description pattern (case insensitive, flexible matching)
                if re.search(event_desc_pattern, doc_text_lower, re.IGNORECASE | re.DOTALL):
                    events_found += 1
        
        event_score = (events_found / len(required_events)) * 30
        score += event_score
        
        if events_found == len(required_events):
            feedback_parts.append(f"✅ All required events integrated ({events_found}/{len(required_events)})")
        elif events_found >= 3:
            feedback_parts.append(f"⚠️ Most events integrated ({events_found}/{len(required_events)})")
        else:
            feedback_parts.append(f"❌ Missing many events ({events_found}/{len(required_events)} found)")

        # Check 4: No placeholder text (15 points)
        placeholders = ["[TBD]", "[INCOMPLETE", "TBD - Add", "[Add", "XXXX"]
        has_placeholders = any(p in doc_text for p in placeholders)
        
        if not has_placeholders:
            score += 15
            feedback_parts.append("✅ No placeholder text remains")
        else:
            feedback_parts.append("❌ Placeholder text still present")

        # Check 5: Completed entries (15 points)
        # August 10 should now say "landlord conducted property inspection"
        aug_10_complete = "08/10/2024" in doc_text and "landlord" in doc_text_lower and "inspection" in doc_text_lower
        # September 20 should have Exhibit E-2
        sep_20_complete = "09/20/2024" in doc_text and "exhibit e-2" in doc_text_lower
        
        completed_count = sum([aug_10_complete, sep_20_complete])
        complete_score = (completed_count / 2) * 15
        score += complete_score
        
        if completed_count == 2:
            feedback_parts.append("✅ Previously incomplete entries completed")
        elif completed_count == 1:
            feedback_parts.append("⚠️ Some entries still incomplete")
        else:
            feedback_parts.append("❌ Incomplete entries not filled in")

        # Check 6: Exhibit references present (10 points)
        exhibit_count = doc_text.count("Exhibit")
        if exhibit_count >= 12:  # Should have many exhibit references
            score += 10
            feedback_parts.append(f"✅ Exhibit references present ({exhibit_count} found)")
        elif exhibit_count >= 8:
            score += 5
            feedback_parts.append(f"⚠️ Some exhibit references ({exhibit_count} found)")
        else:
            feedback_parts.append(f"❌ Missing exhibit references ({exhibit_count} found)")

        # Check 7: Chronological ordering (10 points)
        dates = extract_dates_from_text(doc_text)
        if len(dates) >= 10:
            is_chronological = check_chronological_order(dates)
            if is_chronological:
                score += 10
                feedback_parts.append("✅ Events in chronological order")
            else:
                feedback_parts.append("❌ Events not in chronological order")
        else:
            feedback_parts.append("⚠️ Could not verify chronological order (insufficient dates)")

        # Normalize score to 0-1 range
        final_score = score / 100.0
        passed = score >= 70

        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0.0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_temp_dir(temp_dir)