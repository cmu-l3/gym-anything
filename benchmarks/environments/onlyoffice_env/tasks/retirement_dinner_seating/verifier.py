#!/usr/bin/env python3
"""
Verifier for retirement_dinner_seating@1

Verifies that the seating chart document:
1. Contains all 40 guests
2. Respects mandatory seating constraints:
   - Dorothy Martinez at Table 1
   - Dr. Patricia Adams at Table 1
   - Robert Chen and Susan Chen at same table
   - Michael Torres and Lisa Wong at DIFFERENT tables
   - Emma Garcia, Noah Johnson, Lily Patel all at Table 5
3. Is formatted professionally (reasonable document structure)
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
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_guest_table(guest_name, full_text):
    """
    Find which table a guest is assigned to by looking for table numbers near their name.
    
    Strategy: Find the guest name, then look backwards to find the most recent "Table X" mention.
    Handles various formats: "Table 1", "TABLE 1", "Table 1:", "Table 1 -", etc.
    
    Args:
        guest_name: Name to search for
        full_text: Full document text
    
    Returns:
        Table number (1-5) or None if not found
    """
    text_lower = full_text.lower()
    guest_lower = guest_name.lower()
    
    # Find all occurrences of the guest name
    guest_positions = []
    start = 0
    while True:
        pos = text_lower.find(guest_lower, start)
        if pos == -1:
            break
        guest_positions.append(pos)
        start = pos + 1
    
    if not guest_positions:
        return None
    
    # For each occurrence, find the nearest table number before it
    table_assignments = []
    
    for guest_pos in guest_positions:
        before_text = text_lower[:guest_pos]
        
        # Look for "table 1" through "table 5" patterns
        best_table = None
        best_pos = -1
        
        for table_num in [1, 2, 3, 4, 5]:
            # Try various patterns
            patterns = [
                f'table {table_num}',
                f'table{table_num}',
                f'table #{table_num}',
                f'table-{table_num}',
                f'#{table_num}',
            ]
            
            for pattern in patterns:
                pos = before_text.rfind(pattern)
                if pos > best_pos:
                    best_pos = pos
                    best_table = table_num
        
        if best_table is not None:
            # Check that this table mention is reasonably close (within 500 chars)
            if guest_pos - best_pos < 500:
                table_assignments.append(best_table)
    
    # Return the most common table assignment, or the last one if tied
    if table_assignments:
        return table_assignments[-1]  # Use last occurrence (most likely the actual assignment)
    
    return None


def verify_retirement_seating(traj, env_info, task_info):
    """
    Verify the retirement dinner seating chart.
    
    Scoring:
    - 15 points: All 40 guests present
    - 20 points: Dorothy Martinez at Table 1
    - 15 points: Dr. Patricia Adams at Table 1
    - 15 points: Robert & Susan Chen at same table
    - 15 points: Michael Torres & Lisa Wong at different tables
    - 20 points: All 3 children at Table 5
    
    Total: 100 points
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "❌ Copy function not available in environment"
        }

    container_path = "/home/ga/Documents/TextDocuments/retirement_seating_chart.docx"
    temp_dir = None

    try:
        temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_seating_')
        
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
                "feedback": f"❌ Could not parse seating chart document: {error}"
            }

        # Extract full text
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()

        # Check document has substantial content
        if len(full_text.strip()) < 200:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Document appears nearly empty ({len(full_text)} characters). Expected a complete seating chart."
            }

        # All 40 guests (with some name variations to be flexible)
        all_guests = [
            "Dorothy Martinez", "James Rodriguez", "Maria Santos", "Robert Chen",
            "Susan Chen", "Michael Torres", "Lisa Wong", "Patricia Adams",  # Can match "Dr. Patricia Adams"
            "David Kim", "Jennifer Lee", "Carlos Mendoza", "Amanda White",
            "Thomas Brown", "Sarah Johnson", "Kevin O'Brien", "Michelle Nguyen",
            "Daniel Park", "Emily Davis", "Christopher Miller", "Jessica Taylor",
            "Matthew Wilson", "Ashley Martinez", "Andrew Garcia", "Emma Garcia",
            "Rachel Anderson", "Noah Johnson", "Brandon Thomas", "Stephanie Moore",
            "Justin Jackson", "Lauren Martin", "Ryan Thompson", "Lily Patel",
            "Nicole Harris", "Eric Clark", "Megan Lewis", "Tyler Robinson",
            "Samantha Walker", "Jonathan Hall", "Rebecca Allen", "Nicholas Young"
        ]

        score = 0.0
        feedback_parts = []

        # ===== CRITERION 1: All guests present (15 points) =====
        missing_guests = []
        for guest in all_guests:
            # Also check with common title variations
            guest_variations = [guest, guest.lower()]
            if guest == "Patricia Adams":
                guest_variations.extend(["dr. patricia adams", "dr patricia adams", "dr.patricia adams"])
            
            found = any(var in full_text_lower for var in guest_variations)
            if not found:
                missing_guests.append(guest)

        guests_present = len(all_guests) - len(missing_guests)
        guest_score = (guests_present / len(all_guests)) * 15
        score += guest_score

        if len(missing_guests) == 0:
            feedback_parts.append(f"✅ All 40 guests present")
        elif len(missing_guests) <= 3:
            feedback_parts.append(f"⚠️  {len(missing_guests)} guest(s) missing: {', '.join(missing_guests)}")
        else:
            feedback_parts.append(f"❌ {len(missing_guests)} guests missing (showing first 3): {', '.join(missing_guests[:3])}")

        # ===== CRITERION 2: Dorothy Martinez at Table 1 (20 points) =====
        dorothy_table = find_guest_table("Dorothy Martinez", full_text)
        if dorothy_table == 1:
            score += 20
            feedback_parts.append("✅ Dorothy Martinez at Table 1 (guest of honor)")
        elif dorothy_table is not None:
            feedback_parts.append(f"❌ Dorothy Martinez at Table {dorothy_table} instead of Table 1")
        else:
            feedback_parts.append("❌ Dorothy Martinez table assignment not found")

        # ===== CRITERION 3: Dr. Patricia Adams at Table 1 (15 points) =====
        patricia_table = find_guest_table("Patricia Adams", full_text)
        if patricia_table is None:
            patricia_table = find_guest_table("Dr. Patricia Adams", full_text)
        if patricia_table is None:
            patricia_table = find_guest_table("Dr Patricia Adams", full_text)
        
        if patricia_table == 1:
            score += 15
            feedback_parts.append("✅ Dr. Patricia Adams at Table 1")
        elif patricia_table is not None:
            feedback_parts.append(f"❌ Dr. Patricia Adams at Table {patricia_table} instead of Table 1")
        else:
            feedback_parts.append("❌ Dr. Patricia Adams table assignment not found")

        # ===== CRITERION 4: Robert & Susan Chen at same table (15 points) =====
        robert_table = find_guest_table("Robert Chen", full_text)
        susan_table = find_guest_table("Susan Chen", full_text)

        if robert_table is not None and susan_table is not None:
            if robert_table == susan_table:
                score += 15
                feedback_parts.append(f"✅ Robert & Susan Chen together at Table {robert_table}")
            else:
                feedback_parts.append(f"❌ Robert Chen (Table {robert_table}) & Susan Chen (Table {susan_table}) at different tables - must be together")
        else:
            feedback_parts.append(f"❌ Chen couple table assignments not clear (Robert: {robert_table}, Susan: {susan_table})")

        # ===== CRITERION 5: Michael Torres & Lisa Wong at DIFFERENT tables (15 points) =====
        michael_table = find_guest_table("Michael Torres", full_text)
        lisa_table = find_guest_table("Lisa Wong", full_text)

        if michael_table is not None and lisa_table is not None:
            if michael_table != lisa_table:
                score += 15
                feedback_parts.append(f"✅ Michael Torres (Table {michael_table}) & Lisa Wong (Table {lisa_table}) at different tables")
            else:
                feedback_parts.append(f"❌ Michael Torres & Lisa Wong both at Table {michael_table} - must be separated")
        else:
            feedback_parts.append(f"❌ Torres/Wong table assignments not clear (Michael: {michael_table}, Lisa: {lisa_table})")

        # ===== CRITERION 6: All 3 children at Table 5 (20 points) =====
        emma_table = find_guest_table("Emma Garcia", full_text)
        noah_table = find_guest_table("Noah Johnson", full_text)
        lily_table = find_guest_table("Lily Patel", full_text)

        kids_at_table_5 = sum([
            emma_table == 5,
            noah_table == 5,
            lily_table == 5
        ])

        if kids_at_table_5 == 3:
            score += 20
            feedback_parts.append("✅ All 3 children (Emma, Noah, Lily) at Table 5")
        elif kids_at_table_5 == 2:
            score += 10
            kids_status = f"Emma: T{emma_table}, Noah: T{noah_table}, Lily: T{lily_table}"
            feedback_parts.append(f"⚠️  Only 2/3 children at Table 5 ({kids_status})")
        else:
            kids_status = f"Emma: T{emma_table}, Noah: T{noah_table}, Lily: T{lily_table}"
            feedback_parts.append(f"❌ Children not all at Table 5 ({kids_status})")

        # Calculate final score and pass/fail
        score = round(min(100.0, score), 1)
        passed = (score >= 70.0)

        # Compile feedback
        feedback = " | ".join(feedback_parts)

        return {
            "passed": passed,
            "score": score,
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
        if temp_dir:
            cleanup_temp_dir(temp_dir)


# Entry point for gym-anything framework
def verify(traj, env_info, task_info):
    """Main entry point called by gym-anything"""
    return verify_retirement_seating(traj, env_info, task_info)