#!/usr/bin/env python3
"""
Verifier for seasonal_clearance_markdown task.

The agent must:
1. Import 20 clothing items from clothing_inventory.csv into Copper
2. Apply -20% price to items with qty >= 30 (8 items)
3. Apply +15% price to items with qty <= 7 (3 items)
4. Export inventory to C:\\Users\\Docker\\Desktop\\clearance_inventory.csv

Scoring (100 points total):
  - Export file exists and is newer than task start (15 pts)
  - Sufficient rows in export file (15 pts)
  - Clearance items correctly priced at ~80% of original (5 pts each × 8 = 40 pts)
  - Premium items correctly priced at ~115% of original (10 pts each × 3 = 30 pts)

Pass threshold: >= 60 points AND export file exists and is new
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\seasonal_clearance_result.json"


def verify_seasonal_clearance_markdown(traj, env_info, task_info):
    """
    Verify seasonal clearance markdown pricing task.

    Reads result JSON produced by export_result.ps1, which contains:
      - export_file_exists: bool
      - export_file_new: bool
      - row_count: int
      - clearance_correct_count: int  (out of 8)
      - premium_correct_count: int    (out of 3)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # ----------------------------------------------------------------
    # Load result JSON from container
    # ----------------------------------------------------------------
    result = {}
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(RESULT_PATH, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
        logger.info(f"Result loaded: {result}")
    except Exception as e:
        logger.warning(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0,
                "feedback": f"Could not read result file. Export may have failed: {e}"}
    finally:
        try:
            os.unlink(temp_file.name)
        except Exception:
            pass

    # ----------------------------------------------------------------
    # Scoring
    # ----------------------------------------------------------------
    score = 0
    feedback_parts = []

    export_exists = result.get('export_file_exists', False)
    export_new = result.get('export_file_new', False)

    # Criterion 1: Export file exists and is new (15 pts)
    if export_exists and export_new:
        score += 15
        feedback_parts.append("Export file clearance_inventory.csv created successfully.")
    elif export_exists and not export_new:
        # File exists but predates task start - leftover from before
        feedback_parts.append("Export file exists but was not created during this task (stale file).")
        return {"passed": False, "score": 0,
                "feedback": "clearance_inventory.csv exists but predates task start. File was not created by the agent."}
    else:
        feedback_parts.append("Export file clearance_inventory.csv not found on Desktop.")
        return {"passed": False, "score": 0,
                "feedback": "No export file found. Agent must export inventory to C:\\Users\\Docker\\Desktop\\clearance_inventory.csv."}

    # Criterion 2: Sufficient rows in export (15 pts)
    row_count = result.get('row_count', 0)
    if row_count >= 15:
        score += 15
        feedback_parts.append(f"Export has {row_count} rows (expected >= 15).")
    elif row_count >= 8:
        score += 8
        feedback_parts.append(f"Export has only {row_count} rows (partial import).")
    else:
        feedback_parts.append(f"Export has too few rows ({row_count}), expected >= 15.")

    # Criterion 3: Clearance items correctly priced (5 pts each, 8 items = 40 pts)
    clearance_count = result.get('clearance_correct_count', 0)
    clearance_pts = clearance_count * 5
    score += clearance_pts
    feedback_parts.append(
        f"Clearance pricing (qty>=30, -20%): {clearance_count}/8 items correctly priced "
        f"({clearance_pts}/40 pts)."
    )

    # Criterion 4: Premium items correctly priced (10 pts each, 3 items = 30 pts)
    premium_count = result.get('premium_correct_count', 0)
    premium_pts = premium_count * 10
    score += premium_pts
    feedback_parts.append(
        f"Premium pricing (qty<=7, +15%): {premium_count}/3 items correctly priced "
        f"({premium_pts}/30 pts)."
    )

    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
