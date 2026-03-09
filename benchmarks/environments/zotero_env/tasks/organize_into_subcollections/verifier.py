#!/usr/bin/env python3
"""
Verifier for organize_into_subcollections task.

Task: Create 'Deep Learning Survey' > ['NLP Papers', 'Vision Papers'],
      place 3 NLP papers and 3 Vision papers in the correct subcollections.

Scoring (100 points):
  - 'Deep Learning Survey' collection exists:               20 pts
  - 'NLP Papers' subcollection under 'Deep Learning Survey': 15 pts
  - 'Vision Papers' subcollection under 'Deep Learning Survey': 15 pts
  - Each correct NLP paper placed:                          10 pts × 3 = 30 pts
  - Each correct Vision paper placed:                        7 pts × 3 = 21 pts (rounded to 20)
  Total = 20 + 15 + 15 + 30 + 20 = 100

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

NLP_PAPERS = [
    "Attention Is All You Need",
    "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding",
    "Language Models are Few-Shot Learners",
]
VISION_PAPERS = [
    "ImageNet Classification with Deep Convolutional Neural Networks",
    "Deep Residual Learning for Image Recognition",
    "Generative Adversarial Nets",
]


def verify_organize_into_subcollections(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env("/tmp/organize_into_subcollections_result.json", tmp.name)
            with open(tmp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Copy/parse error: {e}"}

    score = 0
    feedback_parts = []
    subscores = {}

    # Criterion 1: 'Deep Learning Survey' exists (20 pts)
    if result.get("parent_collection_found"):
        score += 20
        subscores["parent_collection"] = True
        feedback_parts.append("'Deep Learning Survey' collection created")
    else:
        subscores["parent_collection"] = False
        feedback_parts.append("'Deep Learning Survey' collection NOT found")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
        }

    # Criterion 2: 'NLP Papers' subcollection (15 pts)
    if result.get("nlp_subcollection_found"):
        score += 15
        subscores["nlp_subcollection"] = True
        feedback_parts.append("'NLP Papers' subcollection created correctly")
    else:
        subscores["nlp_subcollection"] = False
        feedback_parts.append("'NLP Papers' subcollection NOT found under 'Deep Learning Survey'")

    # Criterion 3: 'Vision Papers' subcollection (15 pts)
    if result.get("vision_subcollection_found"):
        score += 15
        subscores["vision_subcollection"] = True
        feedback_parts.append("'Vision Papers' subcollection created correctly")
    else:
        subscores["vision_subcollection"] = False
        feedback_parts.append("'Vision Papers' subcollection NOT found under 'Deep Learning Survey'")

    # Criterion 4: NLP papers placed correctly (10 pts each)
    nlp_present = result.get("nlp_papers_present", [])
    nlp_missing = result.get("nlp_papers_missing", [])
    nlp_count = len(nlp_present)
    nlp_pts = nlp_count * 10
    score += nlp_pts
    subscores["nlp_papers"] = nlp_count
    if nlp_count > 0:
        feedback_parts.append(f"NLP papers placed: {nlp_count}/3 ({nlp_pts}pts)")
    if nlp_missing:
        short_missing = [t[:40] + "..." if len(t) > 40 else t for t in nlp_missing]
        feedback_parts.append(f"NLP missing: {short_missing}")

    # Criterion 5: Vision papers placed correctly (7 pts each, max 20)
    vis_present = result.get("vision_papers_present", [])
    vis_count = len(vis_present)
    vis_pts = min(vis_count * 7, 20)
    score += vis_pts
    subscores["vision_papers"] = vis_count
    if vis_count > 0:
        feedback_parts.append(f"Vision papers placed: {vis_count}/3 ({vis_pts}pts)")

    # Need at least parent + 1 subcollection + 2 papers to pass
    passed = (
        score >= 60
        and result.get("parent_collection_found")
        and (result.get("nlp_subcollection_found") or result.get("vision_subcollection_found"))
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores,
    }
