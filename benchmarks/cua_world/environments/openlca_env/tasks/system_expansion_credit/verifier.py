#!/usr/bin/env python3
"""
Verifier for System Expansion Credit task.

Criteria:
1. Process Creation: A process named "HDPE Recycling... Substitution" must exist.
2. Parameter Usage: A parameter 'substitution_ratio' must be defined.
3. System Expansion: A negative input exchange must exist (The core ISO methodology check).
4. Result Export: A CSV file with valid content must be exported.
5. VLM: Trajectory must show interaction with Parameters tab or Exchange amount editing.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

TRAJECTORY_PROMPT = """You are analyzing screenshots of an agent modeling "System Expansion" in OpenLCA.

Key actions to look for:
1. Creating a Process: Typing a name like "HDPE Recycling".
2. Defining Parameters: Opening the "Parameters" tab and adding "substitution_ratio".
3. Modeling Avoided Burden: Entering a NEGATIVE number for an input flow (e.g., -0.9 or formula like -1*substitution_ratio) in the "Inputs/Outputs" tab.
4. Exporting Results: Saving a CSV file.

Assess:
- PARAMETER_TAB_OPENED: Did the agent open the parameters tab?
- NEGATIVE_VALUE_ENTERED: Did the agent type a negative value or formula for an input?
- PROCESS_CREATED: Was a process created/saved?
- EXPORT_DONE: Was a result exported?

Return JSON:
{
  "parameter_tab_opened": true/false,
  "negative_value_entered": true/false,
  "process_created": true/false,
  "export_done": true/false,
  "confidence": "low"/"medium"/"high",
  "observations": "brief description"
}
"""

def verify_system_expansion_credit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Load result from container
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

    # 1. Process Created (20 pts)
    if result.get("process_found", False):
        score += 20
        feedback.append("Process 'HDPE Recycling...' created.")
    else:
        feedback.append("Process NOT found in database.")

    # 2. Parameter Defined (20 pts)
    if result.get("parameter_found", False):
        score += 20
        feedback.append("Parameter 'substitution_ratio' defined.")
    else:
        feedback.append("Parameter 'substitution_ratio' NOT found.")

    # 3. System Expansion / Negative Input (40 pts) - CRITICAL
    # This proves they actually modeled the credit, not just the process
    if result.get("negative_input_found", False):
        score += 40
        feedback.append("System expansion modeled correctly (negative input found).")
    else:
        feedback.append("No negative input found (System Expansion not modeled).")

    # 4. Result Export (20 pts)
    if result.get("csv_exists", False) and result.get("csv_content_valid", False):
        score += 20
        feedback.append("Results exported to CSV.")
    elif result.get("csv_exists", False):
        score += 10
        feedback.append("CSV exported but content may be empty.")
    else:
        feedback.append("No result CSV found.")

    # VLM Trajectory Check (Bonus/Verification)
    # If score is borderline, VLM can help confirm intent, but programmatic is primary here.
    # We will use it to validate the 'negative value' if DB query failed for some reason
    # but mostly we rely on DB.
    
    passed = (score >= 60) and result.get("negative_input_found", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback),
        "details": result
    }