#!/usr/bin/env python3
"""
Verifier for Mastodon C4 Model Task.
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mastodon_c4_model(traj, env_info, task_info):
    """
    Verifies the Mastodon C4 Model diagram task.
    
    Scoring Criteria:
    - File saved & valid (10 pts)
    - 3 Pages created (15 pts)
    - Context Level Keywords (15 pts)
    - Container Level Keywords (15 pts)
    - Component Level Keywords (15 pts)
    - Relationships/Edges drawn (10 pts)
    - Boundaries/Containers used (10 pts)
    - PNG Exported (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve metadata for expected keywords
    metadata = task_info.get('metadata', {})
    context_keys = metadata.get('context_keywords', [])
    container_keys = metadata.get('container_keywords', [])
    component_keys = metadata.get('component_keywords', [])

    # Load result from container
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

    score = 0
    feedback = []
    
    # Analysis Data
    analysis = result.get("analysis", {})
    pages = analysis.get("pages_data", [])
    all_text = " ".join(analysis.get("text_content", []))
    
    # 1. File Basics (10 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
        feedback.append("Draw.io file saved.")
    else:
        feedback.append("Draw.io file missing or not saved.")

    # 2. Page Count (15 pts)
    page_count = analysis.get("page_count", 0)
    if page_count >= 3:
        score += 15
        feedback.append(f"Correct page count ({page_count}).")
    elif page_count == 2:
        score += 10
        feedback.append(f"Partial page count ({page_count}/3).")
    elif page_count == 1:
        score += 5
        feedback.append(f"Only 1 page found (expected 3).")
    else:
        feedback.append("No pages found.")

    # 3. Context Keywords (15 pts)
    # We check the union of text across all pages (simple check) 
    # or specific pages if names match, but robustly we check if ANY page has these.
    context_hits = [k for k in context_keys if k in all_text]
    if len(context_hits) >= 4:
        score += 15
        feedback.append(f"Context layer verified ({len(context_hits)}/5 key terms).")
    elif len(context_hits) >= 2:
        score += 8
        feedback.append(f"Partial context layer ({len(context_hits)}/5 key terms).")
    else:
        feedback.append("Context layer terms missing (Mastodon, User, etc.).")

    # 4. Container Keywords (15 pts)
    container_hits = [k for k in container_keys if k in all_text]
    if len(container_hits) >= 5:
        score += 15
        feedback.append(f"Container layer verified ({len(container_hits)}/7 key terms).")
    elif len(container_hits) >= 3:
        score += 8
        feedback.append(f"Partial container layer ({len(container_hits)}/7 key terms).")
    else:
        feedback.append("Container layer terms missing (Redis, Postgres, Sidekiq...).")

    # 5. Component Keywords (15 pts)
    component_hits = [k for k in component_keys if k in all_text]
    if len(component_hits) >= 5:
        score += 15
        feedback.append(f"Component layer verified ({len(component_hits)}/8 key terms).")
    elif len(component_hits) >= 3:
        score += 8
        feedback.append(f"Partial component layer ({len(component_hits)}/8 key terms).")
    else:
        feedback.append("Component layer terms missing (Auth, API, ActivityPub...).")

    # 6. Edges/Connections (10 pts)
    total_edges = analysis.get("total_edges", 0)
    if total_edges >= 12:
        score += 10
        feedback.append(f"Sufficient connections drawn ({total_edges}).")
    elif total_edges >= 6:
        score += 5
        feedback.append(f"Few connections drawn ({total_edges}).")
    else:
        feedback.append("Diagram lacks connections.")

    # 7. Boundaries (10 pts)
    # Check for group/swimlane shapes
    boundaries = analysis.get("boundaries_found", 0)
    if boundaries >= 2:
        score += 10
        feedback.append("System boundaries/containers found.")
    else:
        feedback.append("Missing system boundaries (groups/containers).")

    # 8. PNG Export (10 pts)
    if result.get("png_exists") and result.get("png_size", 0) > 2000:
        score += 10
        feedback.append("PNG export validated.")
    else:
        feedback.append("PNG export missing or empty.")

    # Final Check
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }