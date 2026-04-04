#!/usr/bin/env python3
"""
Verifier for Post-Incident Review Creation task.
Verifies the ODT file created by the agent for specific content and formatting.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pir_creation(traj, env_info, task_info):
    """
    Verifies the Post-Incident Review document.
    
    Criteria:
    1. File exists (10 pts)
    2. Document Structure (Headings) (20 pts)
    3. Title Formatting (10 pts)
    4. Timeline Table (15 pts)
    5. Action Items Table (15 pts)
    6. Code Formatting (Courier) (15 pts)
    7. Footer & Page Numbers (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 1. File Existence (10 pts)
    if result.get("file_exists"):
        score += 10
        feedback.append("File 'INC-4092_PIR.odt' created.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}

    # 2. Heading Structure (20 pts)
    # Expect 4 specific headings
    required_headings = ["Executive Summary", "Incident Timeline", "Root Cause Analysis", "Corrective Actions"]
    found_headings = result.get("headings_found", [])
    
    # Normalize for fuzzy matching
    found_norm = [h.strip().lower() for h in found_headings]
    matches = 0
    for req in required_headings:
        if any(req.lower() in h for h in found_norm):
            matches += 1
    
    if matches >= 4:
        score += 20
        feedback.append("All required section headings found.")
    elif matches >= 2:
        score += 10
        feedback.append(f"Found {matches}/4 section headings.")
    else:
        feedback.append(f"Missing section headings. Found: {found_headings}")

    # 3. Title Formatting (10 pts)
    # We check if the specific title text exists in headings
    title_text = "Post-Incident Review: INC-4092"
    title_found = any(title_text.lower() in h.lower() for h in found_headings)
    
    if title_found:
        score += 10
        feedback.append("Document title present in headings.")
    else:
        feedback.append("Document title missing or not styled as heading.")

    # 4. Tables (30 pts split)
    table_count = result.get("table_count", 0)
    if table_count >= 2:
        score += 30
        feedback.append(f"Found {table_count} tables (Timeline & Actions).")
    elif table_count == 1:
        score += 15
        feedback.append("Found only 1 table (expected 2).")
    else:
        feedback.append("No tables found.")

    # 5. Code Formatting (15 pts)
    # The export script sets courier_usage_count = 1 if technical terms + mono font detected
    if result.get("courier_usage_count", 0) > 0:
        score += 15
        feedback.append("Technical terms formatted with Monospace font.")
    else:
        feedback.append("Technical terms not found or not formatted in Courier.")

    # 6. Footer & Page Numbers (15 pts)
    footer_points = 0
    if result.get("footer_text_found"):
        footer_points += 10
        feedback.append("Footer text 'OmniCart Confidential' found.")
    
    if result.get("page_numbers_found"):
        footer_points += 5
        feedback.append("Page numbers found.")
    
    score += footer_points

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }