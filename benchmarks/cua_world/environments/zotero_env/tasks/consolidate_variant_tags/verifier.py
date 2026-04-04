#!/usr/bin/env python3
"""
Verifier for consolidate_variant_tags task.

Task: Rename 'deep-learning', 'deep learning', 'nlp' -> 'Deep Learning', 'NLP'.
      Confirm merge dialogs to consolidate items.

Criteria:
1. Variant tags ('deep-learning', 'deep learning', 'nlp') must NOT exist.
2. Canonical tags ('Deep Learning', 'NLP') MUST exist.
3. Canonical tags must have correct item counts (proving merge, not deletion).
   - Deep Learning: 6 items
   - NLP: 4 items
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_consolidate_variant_tags(traj, env_info, task_info):
    # 1. Setup
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # 2. Get Result JSON
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading result: {e}"}

    # 3. Scoring
    score = 0
    feedback_parts = []
    
    # Expected config
    expected_dl_count = 6
    expected_nlp_count = 4

    # Check Bad Tags (15 pts each -> 45 total)
    bad_tags = result.get("bad_tags_exist", {})
    bad_tags_gone = 0
    for tag, exists in bad_tags.items():
        if not exists:
            score += 15
            bad_tags_gone += 1
        else:
            feedback_parts.append(f"Tag '{tag}' still exists")
    
    if bad_tags_gone == 3:
        feedback_parts.append("All variant tags removed")

    # Check Canonical Tags Existence (15 pts total)
    canonical_exist = result.get("canonical_tags_exist", {})
    if canonical_exist.get("Deep Learning") and canonical_exist.get("NLP"):
        score += 15
        feedback_parts.append("Canonical tags exist")
    else:
        feedback_parts.append("Missing target canonical tags")

    # Check Item Counts (Merge Verification)
    # Deep Learning (20 pts)
    dl_count = result.get("canonical_tag_counts", {}).get("Deep Learning", 0)
    if dl_count == expected_dl_count:
        score += 20
        feedback_parts.append(f"'Deep Learning' has correct item count ({dl_count})")
    elif dl_count > 0:
        # Partial credit if they merged some but not all, or deleted some
        score += 5
        feedback_parts.append(f"'Deep Learning' item count incorrect: {dl_count} (expected {expected_dl_count})")
    else:
        feedback_parts.append("'Deep Learning' tag empty or missing")

    # NLP (20 pts)
    nlp_count = result.get("canonical_tag_counts", {}).get("NLP", 0)
    if nlp_count == expected_nlp_count:
        score += 20
        feedback_parts.append(f"'NLP' has correct item count ({nlp_count})")
    elif nlp_count > 0:
        score += 5
        feedback_parts.append(f"'NLP' item count incorrect: {nlp_count} (expected {expected_nlp_count})")
    else:
        feedback_parts.append("'NLP' tag empty or missing")

    # Final tally
    # Total possible: 45 (bad gone) + 15 (good exist) + 20 (dl count) + 20 (nlp count) = 100
    
    passed = score >= 75

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }