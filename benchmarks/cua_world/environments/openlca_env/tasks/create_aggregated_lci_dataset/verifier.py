#!/usr/bin/env python3
"""
Verifier for Create Aggregated LCI Dataset task.

The agent must:
1. Import USLCI database.
2. Create a Product System for "Cement, Portland".
3. Generate a "System Process" (aggregated LCI) from it.
4. Rename it to "IP-Protected Cement LCI".
5. Export it as JSON-LD.

Scoring (100 points total):
  Programmatic:
    - (10 pts) Database imported (DB size > 15MB).
    - (20 pts) Product system created (ps_count >= 1).
    - (20 pts) Target process created (found by name).
    - (40 pts) Aggregation confirmed (exchange_count > 100).
    - (10 pts) Export file exists and is valid.
  VLM:
    - (Bonus/Validation) Check trajectory for "Save as LCI result" or "Create System Process" dialog.

Pass threshold: 70 points (Must achieve aggregation to pass).
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TRAJECTORY_PROMPT = """You are reviewing screenshots of an agent using openLCA to create an aggregated LCI dataset.

The expected workflow includes:
1. Importing a database (USLCI).
2. Creating a Product System for a process (e.g., Cement).
3. Using a function like "Save as LCI result", "Create System Process", or "Save as System Process".
   - This often appears in the Calculation results view or right-click menu.
4. Exporting the resulting process to a file.

Assess:
- DATABASE_IMPORTED: Evidence of data being imported.
- PRODUCT_SYSTEM_BUILT: Evidence of a product system (model graph) being created.
- AGGREGATION_ACTION: Evidence of creating a system process or saving LCI results (look for "System process" or "LCI result" text).
- EXPORT_ACTION: Evidence of exporting data.

Return JSON:
{
  "database_imported": true/false,
  "product_system_built": true/false,
  "aggregation_action": true/false,
  "export_action": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "brief description"
}"""

FINAL_FRAME_PROMPT = """This is the final screenshot from an agent creating an aggregated LCI process.

A successful final state might show:
- A new process named "IP-Protected Cement LCI" (or similar) in the navigation tree.
- An open process editor showing a long list of elementary flows (inputs/outputs).
- A notification that the export was successful.

Check:
- NEW_PROCESS_VISIBLE: Is the target process visible?
- HIGH_COMPLEXITY_VISIBLE: If an editor is open, does it show many exchanges?
- TASK_COMPLETE: Does the state look like the work is done?

Return JSON:
{
  "new_process_visible": true/false,
  "high_complexity_visible": true/false,
  "task_complete": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "description of what you see"
}"""


def _vlm_query(query_vlm, prompt, image=None, images=None):
    if not query_vlm:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result and result.get("success"):
            return result.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM error: {e}")
    return None


def verify_create_aggregated_lci_dataset(traj, env_info, task_info):
    """Verify aggregated LCI dataset creation task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name) as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Cannot read result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []
    
    # ── Criterion 1: Database imported (10 pts) ────────────────────────────────
    db_ok = result.get('db_found') and result.get('db_size_mb', 0) > 15
    if db_ok:
        score += 10
        feedback.append(f"Database imported ({result.get('db_size_mb')}MB)")
    else:
        feedback.append("Database not found or empty")

    # ── Criterion 2: Product System Created (20 pts) ───────────────────────────
    if result.get('ps_count', 0) >= 1:
        score += 20
        feedback.append("Product system created")
    else:
        feedback.append("No product system found")

    # ── Criterion 3: Target Process Created (20 pts) ───────────────────────────
    if result.get('process_found'):
        score += 20
        feedback.append("Target process 'IP-Protected Cement LCI' found")
    else:
        feedback.append("Target process name not found")

    # ── Criterion 4: Aggregation Confirmed (40 pts) ────────────────────────────
    # This is the core of the task - checking exchange count
    exchange_count = result.get('exchange_count', 0)
    is_aggregated = result.get('is_aggregated', False)
    
    if is_aggregated or exchange_count > 100:
        score += 40
        feedback.append(f"Aggregation verified ({exchange_count} exchanges)")
    elif exchange_count > 0:
        feedback.append(f"Process found but seems to be a Unit Process, not System Process (only {exchange_count} exchanges)")
    else:
        feedback.append("No exchanges found for target process")

    # ── Criterion 5: Export File (10 pts) ──────────────────────────────────────
    if result.get('file_exists') and result.get('file_size', 0) > 100:
        score += 10
        feedback.append("Export file found")
    else:
        feedback.append("Export file missing")

    # ── Final Score Calculation ────────────────────────────────────────────────
    passed = score >= 70 and (is_aggregated or exchange_count > 100)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": result
    }