#!/usr/bin/env python3
"""
Verifier for perform_backlog_triage task.
"""

import json
import logging
import os
import tempfile
from datetime import datetime

logger = logging.getLogger(__name__)

def verify_perform_backlog_triage(traj, env_info, task_info):
    """
    Verify that the agent correctly triaged the 8 backlog items.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Define Ground Truth (Title Keyword -> Expected Properties)
    # Rules:
    # 1. Stability (Crash, 500, Exception) -> P1, Tag:Stability, Area:TailwindTraders
    # 2. Performance (Slow, Timeout) -> P2, Tag:Performance, Area:TailwindTraders\Platform
    # 3. UI (Typo, Color, Align) -> P3, Tag:UI, Area:TailwindTraders\Website
    
    # We map unique substrings to expectations.
    # The 'Crash caused by CSS typo' case is Priority 1 (Crash > Typo).
    ground_truth_map = [
        {"key": "500 Error", "p": 1, "tag": "Stability", "area": "TailwindTraders"},
        {"key": "alignment", "p": 3, "tag": "UI", "area": "TailwindTraders\\Website"},
        {"key": "timeout", "p": 2, "tag": "Performance", "area": "TailwindTraders\\Platform"},
        {"key": "NullReferenceException", "p": 1, "tag": "Stability", "area": "TailwindTraders"},
        {"key": "footer copyright", "p": 3, "tag": "UI", "area": "TailwindTraders\\Website"},
        {"key": "slow", "p": 2, "tag": "Performance", "area": "TailwindTraders\\Platform"},
        {"key": "crash caused by CSS", "p": 1, "tag": "Stability", "area": "TailwindTraders"},
        {"key": "button color", "p": 3, "tag": "UI", "area": "TailwindTraders\\Website"},
    ]

    # Retrieve Result File
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    
    # Try multiple path variants for Windows
    possible_paths = [
        "C:/Users/Docker/task_results/triage_result.json",
        r"C:\Users\Docker\task_results\triage_result.json"
    ]
    
    file_found = False
    for path in possible_paths:
        try:
            copy_from_env(path, tmp.name)
            file_found = True
            break
        except Exception:
            continue
            
    if not file_found:
        return {"passed": False, "score": 0, "feedback": "Result file not found in environment."}

    try:
        with open(tmp.name, "r") as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Corrupt result file: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    items = result_data.get("items", [])
    if not items:
        return {"passed": False, "score": 0, "feedback": "No work items returned in result."}

    score = 0
    max_score = 100
    # 8 items, approx 12.5 pts each.
    # Per item: Priority(4), Tag(4), Area(4.5)
    
    feedback_details = []
    correct_count = 0

    for item in items:
        title = item.get("title", "")
        actual_p = item.get("priority", 0)
        actual_tags = item.get("tags", "") or ""
        actual_area = item.get("areaPath", "")

        # Find matching ground truth
        matched_gt = None
        for gt in ground_truth_map:
            if gt["key"].lower() in title.lower():
                matched_gt = gt
                break
        
        if not matched_gt:
            continue # Should not happen given setup

        item_score = 0
        mistakes = []

        # Check Priority
        if actual_p == matched_gt["p"]:
            item_score += 4
        else:
            mistakes.append(f"Priority {actual_p}!= {matched_gt['p']}")

        # Check Tag (contains)
        if matched_gt["tag"].lower() in actual_tags.lower():
            item_score += 4
        else:
            mistakes.append(f"Tag missing '{matched_gt['tag']}'")

        # Check Area
        # Normalize slashes
        norm_actual = actual_area.replace("/", "\\")
        norm_expected = matched_gt["area"].replace("/", "\\")
        if norm_actual == norm_expected:
            item_score += 4.5
        else:
            mistakes.append(f"Area '{norm_actual}'!='{norm_expected}'")

        score += item_score
        if not mistakes:
            correct_count += 1
        else:
            feedback_details.append(f"Item '{title[:20]}...': " + ", ".join(mistakes))

    # Anti-gaming check: Did they actually change anything?
    # Setup creates them with Priority 2, Area Root, No Tags.
    # If score is high but 'changedDate' is close to start, good.
    # Actually, simplistic verification is enough here as setup values are wrong for >60% of cases.

    passed = score >= 75
    
    feedback = f"Processed {len(items)} items. {correct_count}/8 fully correct."
    if feedback_details:
        feedback += " Errors: " + "; ".join(feedback_details[:3])
        if len(feedback_details) > 3:
            feedback += "..."

    return {
        "passed": passed,
        "score": min(100, int(score)),
        "feedback": feedback
    }