#!/usr/bin/env python3
"""
Verifier for environmental_impact_summary task.

Criteria:
1. File exists and is substantial (>5KB) (Gate)
2. Structure: TOC, Headings (H1/H2), Tables
3. formatting: Page numbers in footer
4. Content: Keywords present indicating data synthesis
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_environmental_impact_summary(traj, env_info, task_info):
    """Verify the EIA document creation."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    min_h1 = metadata.get('required_h1_min', 7)
    min_h2 = metadata.get('required_h2_min', 8)
    min_tables = metadata.get('required_tables_min', 3)
    min_paras = metadata.get('required_paragraph_min', 25)

    # Fetch result
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

    # GATE: File existence and size
    if not result.get("file_exists") or result.get("file_size", 0) < 5000:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file missing or empty (<5KB). Task failed."
        }

    score = 0
    feedback = []

    # 1. Structure: Headings (35 pts total)
    h1 = result.get("heading1_count", 0)
    h2 = result.get("heading2_count", 0)
    
    if h1 >= min_h1:
        score += 20
        feedback.append(f"Heading 1: Pass ({h1})")
    elif h1 > 0:
        score += 10
        feedback.append(f"Heading 1: Partial ({h1}/{min_h1})")
    else:
        feedback.append("Heading 1: Fail (0)")

    if h2 >= min_h2:
        score += 15
        feedback.append(f"Heading 2: Pass ({h2})")
    elif h2 > 0:
        score += 7
        feedback.append(f"Heading 2: Partial ({h2}/{min_h2})")
    else:
        feedback.append("Heading 2: Fail (0)")

    # 2. Structure: Tables (15 pts)
    tables = result.get("table_count", 0)
    if tables >= min_tables:
        score += 15
        feedback.append(f"Tables: Pass ({tables})")
    elif tables > 0:
        score += 7
        feedback.append(f"Tables: Partial ({tables}/{min_tables})")
    else:
        feedback.append("Tables: Fail (None found)")

    # 3. Structure: TOC (15 pts)
    if result.get("has_toc"):
        score += 15
        feedback.append("TOC: Present")
    else:
        feedback.append("TOC: Missing")

    # 4. Formatting: Page Numbers (10 pts)
    if result.get("has_page_numbers"):
        score += 10
        feedback.append("Footer/PageNum: Present")
    else:
        feedback.append("Footer/PageNum: Missing")

    # 5. Content: Keywords & Length (25 pts)
    keywords = result.get("keywords_found", [])
    paras = result.get("paragraph_count", 0)
    
    # Length check
    if paras >= min_paras:
        score += 10
        feedback.append(f"Length: Good ({paras} paras)")
    else:
        feedback.append(f"Length: Short ({paras}/{min_paras})")

    # Keyword check (need at least 3)
    if len(keywords) >= 3:
        score += 15
        feedback.append(f"Content: Verified ({len(keywords)} keywords)")
    else:
        score += 5 * len(keywords)
        feedback.append(f"Content: Weak ({len(keywords)} keywords)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }