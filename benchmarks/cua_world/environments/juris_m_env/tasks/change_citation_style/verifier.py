#!/usr/bin/env python3
"""
Verifier for change_citation_style task.

Verification strategy:
1. Read exported JSON from VM via copy_from_env
2. Check that Jurism's prefs.js references OSCOLA as a Quick Copy / default style

Scoring (100 points):
- OSCOLA appears in Jurism citation style preferences: 100 pts

Pass threshold: 100 points (OSCOLA must be explicitly set)
"""

import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_change_citation_style(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Verify that the citation style was changed to OSCOLA."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        temp.close()
        try:
            copy_from_env("/tmp/change_citation_style_result.json", temp.name)
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

    oscola_in_prefs = result.get("oscola_in_prefs", False)
    quick_copy = result.get("quick_copy_setting", "")

    logger.info(f"oscola_in_prefs={oscola_in_prefs}, quick_copy={quick_copy!r}")

    # Primary check: OSCOLA appears in prefs.js citation preferences
    if oscola_in_prefs or "oscola" in quick_copy.lower():
        return {
            "passed": True,
            "score": 100,
            "feedback": "OSCOLA citation style is set as the active style in Jurism preferences",
            "details": result,
        }

    return {
        "passed": False,
        "score": 0,
        "feedback": (
            "OSCOLA not found in Jurism citation style preferences. "
            "Open Edit > Preferences > Cite, select 'JM OSCOLA' in the Style Manager list, "
            "then set it as the Quick Copy default format and click OK."
        ),
        "details": result,
    }
