#!/usr/bin/env python3
"""
Verifier for import_legal_references task.

Verification strategy:
1. Read exported JSON from the VM via copy_from_env
2. Check that the library has ≥5 new items after starting empty
3. Check that at least 2 of the 3 expected case names are present

Scoring (100 points):
- Library has ≥5 items: 50 pts
- Library has ≥8 items: +20 pts bonus
- Brown v. Board present: 10 pts
- Miranda v. Arizona present: 10 pts
- Marbury v. Madison present: 10 pts

Pass threshold: 50 points (items exist in library)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_import_legal_references(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the RIS file was imported and items appear in the library."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/import_legal_references_result.json", temp.name)
            with open(temp.name) as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp.name):
                os.unlink(temp.name)
    except Exception as e:
        logger.error(f"Failed to retrieve result: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve export result: {e}. Was the task completed?",
        }

    if "error" in result:
        return {"passed": False, "score": 0, "feedback": result["error"]}

    score = 0
    feedback = []

    item_count = result.get("item_count", 0)
    brown = result.get("case_brown_v_board", 0)
    miranda = result.get("case_miranda_v_arizona", 0)
    marbury = result.get("case_marbury_v_madison", 0)

    logger.info(f"item_count={item_count}, brown={brown}, miranda={miranda}, marbury={marbury}")

    # Item count scoring
    if item_count >= 5:
        score += 50
        feedback.append(f"Library has {item_count} items (+50)")
        if item_count >= 8:
            score += 20
            feedback.append(f"Library has >=8 items (+20 bonus)")
    else:
        feedback.append(
            f"Library has only {item_count} items — import may have failed (need >=5). "
            "Use File > Import to import /home/ga/Documents/supreme_court_cases.ris"
        )

    # Expected cases present
    if brown > 0:
        score += 10
        feedback.append("Brown v. Board of Education found (+10)")
    else:
        feedback.append("Brown v. Board of Education NOT found")

    if miranda > 0:
        score += 10
        feedback.append("Miranda v. Arizona found (+10)")
    else:
        feedback.append("Miranda v. Arizona NOT found")

    if marbury > 0:
        score += 10
        feedback.append("Marbury v. Madison found (+10)")
    else:
        feedback.append("Marbury v. Madison NOT found")

    passed = score >= 50
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": result,
    }
