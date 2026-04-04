#!/usr/bin/env python3
"""
Verifier for Real Estate CMA Report task.
Verifies the existence, structure, and content of the generated ODT file.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_real_estate_cma_report(traj, env_info, task_info):
    """
    Verify the CMA Report task.
    
    Criteria:
    1. File Existence & Validity (Gate): File exists, >5KB, created during task.
    2. Document Structure (40 pts):
       - TOC (10)
       - Heading 1 usage (10)
       - Heading 2 usage (5)
       - Tables (10)
       - Page Numbers (5)
    3. Content Accuracy (60 pts):
       - Subject Property Address (10)
       - Comparable Sales (at least 4 found) (20)
       - Price Range Correct (10)
       - Agent Name (10)
       - Document Length (>20 paragraphs) (10)
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # --- Gate Checks ---
    if not result.get('file_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if not result.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "File timestamp indicates it was not created during this task session."}

    file_size = result.get('file_size', 0)
    if file_size < 5000:
        return {"passed": False, "score": 0, "feedback": f"File too small ({file_size} bytes). Expected substantial document > 5KB."}

    analysis = result.get('odt_analysis', {})
    if not analysis.get('valid_odt'):
        return {"passed": False, "score": 0, "feedback": "File is not a valid ODT document or could not be parsed."}

    score = 0
    feedback = []
    
    # --- Structure Scoring (40 pts) ---
    
    # TOC (10 pts)
    if analysis.get('has_toc'):
        score += 10
        feedback.append("Table of Contents found (+10)")
    else:
        feedback.append("Missing Table of Contents")

    # Heading 1 (10 pts)
    h1_count = analysis.get('h1_count', 0)
    if h1_count >= 5:
        score += 10
        feedback.append(f"Structure: {h1_count} Heading 1 sections (+10)")
    elif h1_count >= 3:
        score += 5
        feedback.append(f"Structure: {h1_count} Heading 1 sections (Partial +5)")
    else:
        feedback.append(f"Structure: Only {h1_count} Heading 1 sections (Need 5+)")

    # Heading 2 (5 pts)
    h2_count = analysis.get('h2_count', 0)
    if h2_count >= 4:
        score += 5
        feedback.append(f"Structure: {h2_count} Heading 2 subsections (+5)")
    else:
        feedback.append("Structure: Insufficient Heading 2 subsections")

    # Tables (10 pts)
    table_count = analysis.get('table_count', 0)
    if table_count >= 2:
        score += 10
        feedback.append(f"Structure: {table_count} tables found (+10)")
    elif table_count == 1:
        score += 5
        feedback.append("Structure: Only 1 table found (Partial +5)")
    else:
        feedback.append("Structure: No tables found")

    # Page Numbers (5 pts)
    if analysis.get('has_footer_pagenum'):
        score += 5
        feedback.append("Structure: Page numbers detected (+5)")
    else:
        feedback.append("Structure: Missing page numbers")

    # --- Content Scoring (60 pts) ---
    
    text_content = analysis.get('text_content', "").lower()
    
    # Subject Address (10 pts)
    if "4815 ridgeview" in text_content or "ridgeview trail" in text_content:
        score += 10
        feedback.append("Content: Subject address found (+10)")
    else:
        feedback.append("Content: Subject address missing")

    # Comparable Sales (20 pts)
    comps = ["greystone", "mesa", "highland", "balcones", "shoal creek", "far west"]
    comps_found = sum(1 for c in comps if c in text_content)
    
    if comps_found >= 4:
        score += 20
        feedback.append(f"Content: {comps_found}/6 comparables found (+20)")
    elif comps_found >= 2:
        score += 10
        feedback.append(f"Content: {comps_found}/6 comparables found (Partial +10)")
    else:
        feedback.append(f"Content: Only {comps_found} comparables found")

    # Price Range (10 pts)
    # Flexible matching for 685,000 or 710,000 formats
    if ("685,000" in text_content or "685000" in text_content) and \
       ("710,000" in text_content or "710000" in text_content):
        score += 10
        feedback.append("Content: Correct price range found (+10)")
    else:
        feedback.append("Content: Price range values missing or incorrect")

    # Agent Name (10 pts)
    if "sarah chen" in text_content:
        score += 10
        feedback.append("Content: Agent name found (+10)")
    else:
        feedback.append("Content: Agent name missing")

    # Length/Effort (10 pts)
    para_count = analysis.get('paragraph_count', 0)
    if para_count >= 20:
        score += 10
        feedback.append(f"Content: Substantial length ({para_count} paragraphs) (+10)")
    elif para_count >= 10:
        score += 5
        feedback.append(f"Content: Moderate length ({para_count} paragraphs) (Partial +5)")
    else:
        feedback.append("Content: Document too short")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback)
    }