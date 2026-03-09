#!/usr/bin/env python3
"""
Verifier for exhibit_catalog_create task.
Verifies the creation of a structured ODT museum catalog document.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_exhibit_catalog(traj, env_info, task_info):
    """
    Verify the exhibition catalog ODT file.
    
    Criteria:
    1. File exists and was created during task (Gate)
    2. Document Structure (Headings, TOC, Tables)
    3. Content (Artists, specific terms)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Metadata / Thresholds
    metadata = task_info.get('metadata', {})
    min_h1 = metadata.get('min_h1', 5)
    min_h2 = metadata.get('min_h2', 8)
    
    # 1. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve validation data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Gate: File Existence
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Output file 'Light_in_Motion_Catalog.odt' not found."
        }
        
    if not result.get("file_created_during_task", False):
         # If file exists but wasn't modified/created now, that's suspicious (though setup deletes it)
         return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Output file timestamp is invalid (not modified during task)."
        }

    score = 0
    feedback_parts = []
    
    # 3. Base Score for File Creation (5 pts)
    if result.get("file_size_bytes", 0) > 5000:
        score += 5
        feedback_parts.append("File created and has content")
    else:
        feedback_parts.append("File created but seems empty/too small")

    # 4. Heading Structure (30 pts)
    # Heading 1 (Major sections)
    h1_count = result.get("h1_count", 0)
    if h1_count >= min_h1:
        score += 15
        feedback_parts.append(f"Heading 1 structure good ({h1_count} sections)")
    elif h1_count > 0:
        score += 5
        feedback_parts.append(f"Insufficient Heading 1 sections ({h1_count}/{min_h1})")
    else:
        feedback_parts.append("No Heading 1 styles found")

    # Heading 2 (Artwork entries)
    h2_count = result.get("h2_count", 0)
    if h2_count >= min_h2:
        score += 15
        feedback_parts.append(f"Heading 2 structure good ({h2_count} entries)")
    elif h2_count > 0:
        score += 5
        feedback_parts.append(f"Insufficient Heading 2 entries ({h2_count}/{min_h2})")
    else:
        feedback_parts.append("No Heading 2 styles found")

    # 5. Navigation & Formatting (35 pts)
    # Table of Contents
    if result.get("has_toc", False):
        score += 15
        feedback_parts.append("Table of Contents present")
    else:
        feedback_parts.append("Missing Table of Contents")

    # Inventory Table
    if result.get("has_table", False):
        score += 10
        feedback_parts.append("Inventory table present")
    else:
        feedback_parts.append("Missing Inventory table")

    # Page Numbers
    if result.get("has_page_numbers", False):
        score += 10
        feedback_parts.append("Page numbers detected")
    else:
        feedback_parts.append("Missing page numbers")

    # 6. Content Verification (30 pts)
    # Artists (2 pts each, max 16)
    found_artists = result.get("artists_found", [])
    artist_score = len(found_artists) * 2
    score += artist_score
    if len(found_artists) == 8:
        feedback_parts.append("All 8 artists found")
    else:
        feedback_parts.append(f"Found {len(found_artists)}/8 artists")

    # Key Terms (max 9 pts)
    # 3 pts each for "impression", "oil on canvas", "catalog"
    found_terms = result.get("terms_found", [])
    # We look for unique terms to avoid double counting "catalog"/"catalogue"
    unique_term_concepts = set()
    for t in found_terms:
        if "impression" in t: unique_term_concepts.add("impression")
        if "oil" in t: unique_term_concepts.add("medium")
        if "catalog" in t: unique_term_concepts.add("catalog")
    
    term_score = len(unique_term_concepts) * 3
    # Check Paragraph count bonus (5 pts)
    if result.get("paragraph_count", 0) >= 25:
        term_score += 5
        feedback_parts.append("Document length sufficient")
        
    score += term_score

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }