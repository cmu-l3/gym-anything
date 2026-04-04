#!/usr/bin/env python3
"""
Verifier for board_meeting_minutes task.
Checks the structural and content validity of the ODT file created by the agent.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_board_meeting_minutes(traj, env_info, task_info):
    """
    Verify that the Board Meeting Minutes document was created correctly.
    
    Scoring Breakdown (100 pts total):
    1. File Existence & Validity (5 pts)
    2. Document Structure (Headings) (25 pts)
       - Heading 1 used >= 6 times (15 pts)
       - Heading 2 used >= 5 times (10 pts)
    3. Navigation & Formatting (25 pts)
       - Table of Contents present (15 pts)
       - Page Numbers in footer (10 pts)
    4. Data Presentation (Tables) (15 pts)
       - At least 2 tables (Motions, Action Items) (15 pts)
    5. Content Verification (25 pts)
       - Financials correct (10 pts)
       - Names present (10 pts)
       - Vote terminology (5 pts)
    6. Substantial Content (Paragraphs) (5 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected metadata
    metadata = task_info.get('metadata', {})
    
    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get("analysis", {})
    score = 0
    feedback = []
    
    # 1. File Existence (5 pts)
    if analysis.get("file_exists") and analysis.get("file_size", 0) > 1000:
        score += 5
        feedback.append("File exists and is not empty (+5)")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found or empty (Gate failure)"}
    
    if not analysis.get("is_valid_zip"):
        return {"passed": False, "score": 5, "feedback": "File exists but is not a valid ODT/Zip file"}

    # 2. Document Structure (25 pts)
    h1_count = analysis.get("heading1_count", 0)
    h2_count = analysis.get("heading2_count", 0)
    
    if h1_count >= 6:
        score += 15
        feedback.append(f"Heading 1 structure good ({h1_count} sections) (+15)")
    elif h1_count >= 3:
        score += 7
        feedback.append(f"Heading 1 structure partial ({h1_count}/6) (+7)")
    else:
        feedback.append(f"Missing Heading 1 styles (found {h1_count}, need 6)")

    if h2_count >= 5:
        score += 10
        feedback.append(f"Heading 2 structure good ({h2_count} subsections) (+10)")
    elif h2_count >= 2:
        score += 5
        feedback.append(f"Heading 2 structure partial ({h2_count}/5) (+5)")
    else:
        feedback.append(f"Missing Heading 2 styles (found {h2_count}, need 5)")

    # 3. Navigation & Formatting (25 pts)
    if analysis.get("has_toc"):
        score += 15
        feedback.append("Table of Contents found (+15)")
    else:
        feedback.append("Table of Contents missing")
        
    if analysis.get("has_page_numbers"):
        score += 10
        feedback.append("Page numbers found (+10)")
    else:
        feedback.append("Page numbers missing")

    # 4. Tables (15 pts)
    table_count = analysis.get("table_count", 0)
    if table_count >= 2:
        score += 15
        feedback.append(f"Tables found ({table_count}) (+15)")
    elif table_count == 1:
        score += 7
        feedback.append("Only 1 table found (need 2) (+7)")
    else:
        feedback.append("No tables found")

    # 5. Content Verification (25 pts)
    plain_text = analysis.get("plain_text", "")
    
    # Financials (10 pts)
    financials = ["47.2", "44.8", "198.4", "890"]
    fin_found = sum(1 for f in financials if f in plain_text or f.replace('.', ',') in plain_text)
    if fin_found >= 3:
        score += 10
        feedback.append("Financial data verified (+10)")
    elif fin_found >= 1:
        score += 5
        feedback.append("Partial financial data found (+5)")
    else:
        feedback.append("Key financial figures missing")

    # Names (10 pts)
    names = ["hollingsworth", "dietrich", "chen", "okafor", "fredricksen"]
    names_found = sum(1 for n in names if n in plain_text)
    if names_found >= 4:
        score += 10
        feedback.append("Key personnel names verified (+10)")
    elif names_found >= 2:
        score += 5
        feedback.append("Partial names found (+5)")
    else:
        feedback.append("Key personnel names missing")
        
    # Vote/Motion terms (5 pts)
    vote_terms = ["unanimous", "6-0", "5-1"]
    if any(t in plain_text for t in vote_terms):
        score += 5
        feedback.append("Vote tallies/terminology found (+5)")
    else:
        feedback.append("Vote tallies (e.g., '6-0') missing")

    # 6. Paragraph Count (5 pts)
    if analysis.get("paragraph_count", 0) >= 25:
        score += 5
        feedback.append("Document length adequate (+5)")
    else:
        feedback.append("Document too short")

    # Anti-gaming: Check timestamp vs file creation
    # (Implied by file existence check, but can be stricter if needed)
    
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }