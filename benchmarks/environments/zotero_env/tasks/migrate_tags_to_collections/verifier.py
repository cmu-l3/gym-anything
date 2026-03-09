#!/usr/bin/env python3
"""
Verifier for migrate_tags_to_collections task.

Task:
1. Create collections 'dataset-mnist' and 'dataset-imagenet'.
2. Move tagged papers into these collections.
3. Delete the original tags.

Scoring (100 points):
- Collection 'dataset-mnist' created: 20 pts
- Collection 'dataset-imagenet' created: 20 pts
- Correct items in 'dataset-mnist': 20 pts
- Correct items in 'dataset-imagenet': 20 pts
- Tag 'dataset-mnist' removed: 10 pts
- Tag 'dataset-imagenet' removed: 10 pts

Pass Threshold: 80 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_migrate_tags_to_collections(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result
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
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading result: {e}"}

    score = 0
    feedback_parts = []
    
    collections = result.get("collections_created", {})
    items_moved = result.get("items_correctly_moved", {})
    tags_removed = result.get("tags_removed", {})

    # Check Dataset-MNIST (50 pts total chunk)
    mnist_score = 0
    if collections.get("dataset-mnist", False):
        mnist_score += 20
        feedback_parts.append("'dataset-mnist' collection created")
    else:
        feedback_parts.append("'dataset-mnist' collection MISSING")

    if items_moved.get("dataset-mnist", False):
        mnist_score += 20
        feedback_parts.append("MNIST papers moved")
    else:
        feedback_parts.append("MNIST papers NOT correctly moved")

    if tags_removed.get("dataset-mnist", False):
        mnist_score += 10
        feedback_parts.append("MNIST tag deleted")
    else:
        feedback_parts.append("MNIST tag still exists")
    
    score += mnist_score

    # Check Dataset-ImageNet (50 pts total chunk)
    imagenet_score = 0
    if collections.get("dataset-imagenet", False):
        imagenet_score += 20
        feedback_parts.append("'dataset-imagenet' collection created")
    else:
        feedback_parts.append("'dataset-imagenet' collection MISSING")

    if items_moved.get("dataset-imagenet", False):
        imagenet_score += 20
        feedback_parts.append("ImageNet papers moved")
    else:
        feedback_parts.append("ImageNet papers NOT correctly moved")

    if tags_removed.get("dataset-imagenet", False):
        imagenet_score += 10
        feedback_parts.append("ImageNet tag deleted")
    else:
        feedback_parts.append("ImageNet tag still exists")

    score += imagenet_score

    # Check for general errors
    if result.get("errors"):
        feedback_parts.append(f"Errors detected: {result['errors']}")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }