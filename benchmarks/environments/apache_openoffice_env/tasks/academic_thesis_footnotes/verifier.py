#!/usr/bin/env python3
"""
Verifier for academic_thesis_footnotes task.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logger = logging.getLogger(__name__)

def verify_academic_thesis_footnotes(traj, env_info, task_info):
    """
    Verify the thesis document formatting.
    Criteria:
    1. File exists (10 pts)
    2. Footnote mechanism used (>=5 text:note elements) (30 pts)
    3. Citation content accuracy (25 pts)
    4. Bibliography hanging indent (15 pts)
    5. Headings applied (10 pts)
    6. Page numbers applied (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. File exists
    if result.get("file_exists"):
        score += 10
        feedback.append("File created successfully (+10)")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # 2. Footnotes Used
    count = result.get("footnote_count", 0)
    if count >= 5:
        score += 30
        feedback.append(f"Correct number of footnotes found ({count}) (+30)")
    elif count > 0:
        score += 15
        feedback.append(f"Some footnotes found ({count}/5) (+15)")
    else:
        feedback.append("No semantic footnotes found (did you use Insert > Footnote?)")

    # 3. Content Accuracy
    # Check if the extracted footnote text contains key strings from the source
    contents = " ".join(result.get("footnote_contents", [])).lower()
    citations_found = 0
    # Key phrases to look for (from citation_source.json)
    checks = [
        "bernstein, wedding of the waters",
        "sheriff, the artificial river",
        "shaw, erie water west",
        "albion, the rise of new york port",
        "bernstein, wedding of the waters, 112"
    ]
    
    for check in checks:
        if check in contents:
            citations_found += 1
    
    if citations_found == 5:
        score += 25
        feedback.append("All citations matched correctly (+25)")
    else:
        pts = citations_found * 5
        score += pts
        feedback.append(f"Matched {citations_found}/5 citations (+{pts})")

    # 4. Bibliography Formatting
    if result.get("bibliography_hanging_indent"):
        score += 15
        feedback.append("Bibliography hanging indent applied (+15)")
    else:
        feedback.append("Bibliography does not appear to have hanging indent")

    # 5. Headings
    headings = result.get("headings_found", [])
    # Look for "Chapter" and "Bibliography" in Heading 1
    has_chap = any("chapter" in h.lower() for h in headings)
    has_bib = any("bibliography" in h.lower() for h in headings)
    
    if has_chap and has_bib:
        score += 10
        feedback.append("Headings applied correctly (+10)")
    elif has_chap or has_bib:
        score += 5
        feedback.append("Some headings applied (+5)")
    else:
        feedback.append("Heading 1 style not found on expected text")

    # 6. Page Numbers
    if result.get("page_numbers_present"):
        score += 10
        feedback.append("Page numbers found (+10)")
    else:
        feedback.append("Page numbers missing")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback)
    }