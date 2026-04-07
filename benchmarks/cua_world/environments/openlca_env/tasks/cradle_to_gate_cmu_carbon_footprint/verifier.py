#!/usr/bin/env python3
"""
Verifier for Cradle-to-Gate CMU Carbon Footprint task.

Stub verifier — full verification will use vlm_checklist_verifier.
This provides basic programmatic checks from the export_result.sh JSON.

Scoring:
  Database created:            10 pts
  Processes found (4 names):   20 pts (5 each)
  Elementary CO2 flow:         10 pts
  Product system exists:       10 pts
  Result CSV exists + timing:  15 pts
  CSV contains GWP keywords:   15 pts
  VLM trajectory (stub):       20 pts
  Total:                      100 pts
  Pass threshold:              60 pts
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_cmu_carbon_footprint(traj, env_info, task_info):
    """Verify CMU carbon footprint task completion."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result JSON from environment
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []

    # 1. Database created (10 pts)
    if result.get('db_found'):
        score += 10
        feedback.append("Database found.")
    else:
        feedback.append("No database found.")

    # 2. Process names (20 pts, 5 each)
    proc_dump = result.get('process_names_dump', '').lower()
    process_keywords = {
        "Cement Production": "cement",
        "Aggregate Processing": "aggregate",
        "Concrete Mixing": ["concrete", "mixing"],
        "Block Molding": ["molding", "block"],
    }
    for name, kw in process_keywords.items():
        keywords = kw if isinstance(kw, list) else [kw]
        if any(k in proc_dump for k in keywords):
            score += 5
            feedback.append(f"Process '{name}' found.")
        else:
            feedback.append(f"Process '{name}' NOT found.")

    # 3. Elementary CO2 flow (10 pts)
    if result.get('elementary_flow_found'):
        score += 10
        feedback.append("Elementary flow 'Carbon Dioxide' found.")
    else:
        feedback.append("Elementary flow 'Carbon Dioxide' NOT found.")

    # 4. Product system exists (10 pts)
    if result.get('product_system_count', 0) >= 1:
        score += 10
        feedback.append("Product system created.")
    else:
        feedback.append("No product system found.")

    # 5. Result CSV exists and created during task (15 pts)
    if result.get('file_exists') and result.get('file_created_during_task'):
        score += 15
        feedback.append("Result CSV created during task.")
    elif result.get('file_exists'):
        score += 5
        feedback.append("Result CSV exists but timestamp suspect.")
    else:
        feedback.append("No result CSV found.")

    # 6. CSV contains GWP data (15 pts)
    if result.get('content_has_gwp'):
        score += 15
        feedback.append("CSV contains GWP/Global Warming data.")
    else:
        feedback.append("CSV missing GWP keywords.")

    # 7. VLM trajectory verification (20 pts) — stub, deferred to vlm_checklist_verifier
    # Placeholder: award partial credit if the agent created most of the model
    if score >= 50:
        score += 10
        feedback.append("Partial VLM credit (stub).")

    passed = score >= 60

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " ".join(feedback),
    }
