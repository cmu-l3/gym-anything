#!/usr/bin/env python3
"""
Verifier for tag_and_search_pipeline task.

Task: Triage 20 systems papers in "Reading Queue":
  - Priority papers from before 2010 get tagged "review-now" (4 papers)
  - Priority papers from 2010+ get tagged "review-later" (2 papers)
  - Create saved search "Review Now" showing review-now items
  - Export that search as BibTeX to /home/ga/Desktop/review_now.bib

Scoring (100 points):
  - 4 pre-2010 priority papers tagged "review-now": 30 pts (7.5 each)
  - 2 post-2010 priority papers tagged "review-later": 20 pts (10 each)
  - Saved search "Review Now" exists: 20 pts
  - Saved search has "review-now" condition: 10 pts
  - BibTeX file exists and is non-empty: 20 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PRE2010_TITLES = [
    "The UNIX Time-Sharing System",
    "End-to-End Arguments in System Design",
    "The Google File System",
    "Chord: A Scalable Peer-to-peer Lookup Service for Internet Applications",
]
POST2010_TITLES = [
    "Raft: In Search of an Understandable Consensus Algorithm",
    "TiKV: A Distributed Transactional Key-Value Database",
]


def verify_tag_and_search_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/tag_and_search_pipeline_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script may have failed"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Copy/parse error: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    priority_tags = result.get("priority_paper_tags", {})
    review_now = set(result.get("review_now_items", []))
    review_later = set(result.get("review_later_items", []))

    # Criterion 1: Pre-2010 priority papers tagged "review-now" (30 pts, 7.5 each)
    pre2010_correct = 0
    for title in PRE2010_TITLES:
        if title in review_now:
            pre2010_correct += 1
    pts = int(pre2010_correct * 7.5)
    score += pts
    subscores["pre2010_review_now"] = f"{pre2010_correct}/4"
    if pre2010_correct == 4:
        feedback_parts.append("All 4 pre-2010 priority papers tagged 'review-now'")
    else:
        feedback_parts.append(f"Pre-2010 review-now: {pre2010_correct}/4 correct")

    # Criterion 2: Post-2010 priority papers tagged "review-later" (20 pts, 10 each)
    post2010_correct = 0
    for title in POST2010_TITLES:
        if title in review_later:
            post2010_correct += 1
    pts2 = post2010_correct * 10
    score += pts2
    subscores["post2010_review_later"] = f"{post2010_correct}/2"
    if post2010_correct == 2:
        feedback_parts.append("Both post-2010 priority papers tagged 'review-later'")
    else:
        feedback_parts.append(f"Post-2010 review-later: {post2010_correct}/2 correct")

    # Criterion 3: Saved search "Review Now" exists (20 pts)
    if result.get("saved_search_exists"):
        score += 20
        subscores["saved_search_exists"] = True
        feedback_parts.append("Saved search 'Review Now' exists")
    else:
        subscores["saved_search_exists"] = False
        feedback_parts.append("Saved search 'Review Now' NOT found")

    # Criterion 4: Saved search has tag condition for "review-now" (10 pts)
    conditions = result.get("saved_search_conditions", [])
    has_review_now_condition = any(
        c.get("condition") == "tag" and "review-now" in c.get("value", "")
        for c in conditions
    )
    if result.get("saved_search_exists") and has_review_now_condition:
        score += 10
        subscores["saved_search_condition"] = True
        feedback_parts.append("Saved search filters by 'review-now' tag")
    else:
        subscores["saved_search_condition"] = False
        if result.get("saved_search_exists"):
            feedback_parts.append("Saved search exists but condition is not 'review-now'")

    # Criterion 5: BibTeX file exists and non-empty (20 pts)
    bib_size = result.get("bib_file_size", 0)
    if result.get("bib_file_exists") and bib_size > 50:
        score += 20
        subscores["bib_file"] = True
        entry_count = result.get("bib_entry_count", 0)
        feedback_parts.append(f"BibTeX file exported ({bib_size} bytes, ~{entry_count} entries)")
    else:
        subscores["bib_file"] = False
        feedback_parts.append("BibTeX /home/ga/Desktop/review_now.bib not found or empty")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
