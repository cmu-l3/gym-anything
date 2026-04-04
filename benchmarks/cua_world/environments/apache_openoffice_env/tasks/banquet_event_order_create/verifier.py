#!/usr/bin/env python3
"""
Verifier for banquet_event_order_create task.

Verifies:
1. File creation (Gateway)
2. Professional formatting (Headers/Footers, Tables)
3. Content accuracy (Menu items, AV needs, Event details)

Scoring:
- File Exists: 10 pts (Gateway)
- Event Header Info: 15 pts
- Table Structure (>= 2 tables): 20 pts
- Content Accuracy (Menus/AV): 40 pts
- Footer/Page Num: 15 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_banquet_event_order(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result from VM
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result: {e}"}
    finally:
        if os.path.exists(temp_path):
            os.unlink(temp_path)

    # 1. Gateway: File Existence
    if not result.get("file_exists"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "BEO file was not created at the expected path."
        }

    score = 10
    feedback = ["File created (+10)."]
    
    # 2. Header Info (15 pts)
    # Checks for BEO number and Date
    checks = result.get("content_check", {})
    if result.get("has_header_info"):
        score += 15
        feedback.append("Header info (Date/BEO#) found (+15).")
    elif checks.get("beo_number") or checks.get("date"):
        score += 7
        feedback.append("Partial header info found (+7).")
    else:
        feedback.append("Missing Event Header info (BEO# or Date).")

    # 3. Table Structure (20 pts)
    # Expecting at least 2 tables (Summary + Schedule)
    table_count = result.get("table_count", 0)
    if table_count >= 2:
        score += 20
        feedback.append(f"Document structure correct ({table_count} tables found) (+20).")
    elif table_count == 1:
        score += 10
        feedback.append("Partial structure: Only 1 table found (expected Summary + Schedule) (+10).")
    else:
        feedback.append("No tables found. BEO requires tabular format.")

    # 4. Content Accuracy (40 pts)
    # 4 specific items * 10 pts each
    content_points = 0
    items = [
        ("menu_item_1", "Smoked Salmon"),
        ("menu_item_2", "Chia Parfaits"),
        ("av_item_1", "Wireless Lav"),
        ("av_item_2", "4K Projector")
    ]
    
    found_items = []
    missing_items = []
    
    for key, label in items:
        if checks.get(key):
            content_points += 10
            found_items.append(label)
        else:
            missing_items.append(label)
            
    score += content_points
    if found_items:
        feedback.append(f"Content found: {', '.join(found_items)} (+{content_points}).")
    if missing_items:
        feedback.append(f"Missing specific content: {', '.join(missing_items)}.")

    # 5. Footer (15 pts)
    if result.get("has_footer"):
        score += 15
        feedback.append("Footer with page numbers/text found (+15).")
    else:
        feedback.append("Footer missing or incorrect.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }