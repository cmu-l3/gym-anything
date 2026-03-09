#!/usr/bin/env python3
"""Verifier for add_tags_to_items task."""

import json
import tempfile
import os

def verify_add_tags_to_items(traj, env_info, task_info):
    """Verify that tags were added to items in Zotero library."""

    # Get copy function from framework
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_min_tags = metadata.get('expected_min_tags', 3)
    expected_min_tagged_items = metadata.get('expected_min_tagged_items', 2)

    # Copy result file from container
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

    # Evaluate results
    score = 0
    feedback_parts = []

    tags_added = result.get('tags_added', 0)
    tagged_items_added = result.get('tagged_items_added', 0)
    all_tags = result.get('all_tags', '')  # Changed from sample_tags to all_tags

    # Criterion 1: Tags were added (40 points)
    if tags_added >= expected_min_tags:
        score += 40
        feedback_parts.append(f"Sufficient tags added ({tags_added} tags)")
    elif tags_added > 0:
        partial_score = int(40 * tags_added / expected_min_tags)
        score += partial_score
        feedback_parts.append(f"Some tags added ({tags_added}, expected {expected_min_tags}+)")
    else:
        feedback_parts.append("No tags added")

    # Criterion 2: Items were tagged (40 points)
    if tagged_items_added >= expected_min_tagged_items:
        score += 40
        feedback_parts.append(f"Items tagged ({tagged_items_added} items)")
    elif tagged_items_added > 0:
        partial_score = int(40 * tagged_items_added / expected_min_tagged_items)
        score += partial_score
        feedback_parts.append(f"Some items tagged ({tagged_items_added}, expected {expected_min_tagged_items}+)")
    else:
        feedback_parts.append("No items tagged")

    # Criterion 3: Tag quality (20 points)
    # Check if tags are meaningful (not just generic like "tag1", "tag2")
    # Domain-agnostic: accept any reasonable research tags
    import re

    # Generic/lazy tags that should NOT count as quality tags
    lazy_patterns = [
        r'^tag\d*$',           # tag, tag1, tag2
        r'^test\d*$',          # test, test1
        r'^item\d*$',          # item, item1
        r'^paper\d*$',         # paper, paper1
        r'^untitled\d*$',      # untitled
        r'^new\s*tag\d*$',     # new tag, new tag 1
        r'^\d+$',              # just numbers
        r'^[a-z]$'             # single letters
    ]

    tags_list = [t.strip() for t in all_tags.split(',') if t.strip()]
    quality_tags = 0

    for tag in tags_list:
        tag_lower = tag.lower()
        # Check if it's NOT a lazy tag
        is_lazy = any(re.match(pattern, tag_lower, re.IGNORECASE) for pattern in lazy_patterns)
        # Quality tag: >2 chars, not lazy, contains letters
        if len(tag) > 2 and not is_lazy and re.search(r'[a-zA-Z]', tag):
            quality_tags += 1

    if tags_added >= expected_min_tags and quality_tags >= expected_min_tags:
        score += 20
        feedback_parts.append(f"Quality tags added ({quality_tags} meaningful tags)")
    elif tags_added > 0 and quality_tags >= 2:
        score += 15
        feedback_parts.append(f"Some quality tags ({quality_tags} meaningful tags)")
    elif tags_added > 0 and quality_tags >= 1:
        score += 10
        feedback_parts.append(f"Minimal quality tags ({quality_tags} meaningful tags)")
    elif tags_added > 0:
        score += 5
        feedback_parts.append("Tags added (low quality - use descriptive names)")

    # Task passes if score >= 60
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": {
            "tags_added": tags_added,
            "tagged_items_added": tagged_items_added
        }
    }
