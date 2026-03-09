#!/usr/bin/env python3
"""
Verifier for data_entry_and_validation task.

Scoring (100 points total):
- At least 1 new data value entered for Ngelehun CHC, Oct 2023 (30 pts) [MANDATORY]
- At least 5 new data values entered (25 pts)
- Dataset marked complete (completedatasetregistration exists after task start) (25 pts)
- Entered values are within plausible range 0-10,000 (20 pts)

Pass threshold: 60 points
Mandatory: At least 1 data value entered for Ngelehun CHC in October 2023 after task start
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_data_entry_and_validation(traj, env_info, task_info):
    """Verify that aggregate data was entered for Ngelehun CHC for October 2023."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/data_entry_and_validation_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)

        score = 0
        feedback_parts = []
        subscores = {}

        # Get metadata
        metadata = task_info.get('metadata', {})
        target_ou = metadata.get('target_org_unit', 'Ngelehun CHC')
        min_values = int(metadata.get('minimum_data_values', 5))

        new_dv_count = int(result.get('new_datavalue_count', 0))
        current_dv_count = int(result.get('current_datavalue_count', 0))
        initial_dv_count = int(result.get('initial_datavalue_count', 0))
        values_in_range = int(result.get('values_in_plausible_range', 0))
        complete_after_start = int(result.get('complete_registration_after_start', 0))
        complete_exists = int(result.get('complete_registration_exists', 0))

        # Also use net change as a fallback if timestamp comparison failed
        net_change = max(0, current_dv_count - initial_dv_count)
        effective_new_count = max(new_dv_count, net_change)

        # Criterion 1: At least 1 data value entered (MANDATORY)
        if effective_new_count < 1:
            return {
                "passed": False,
                "score": 0,
                "feedback": (
                    f"No new data values found in DHIS2 for {target_ou} (Ngelehun CHC) for October 2023. "
                    f"Agent must navigate to Data Entry, select the facility and period, and enter data. "
                    f"Current count: {current_dv_count}, Initial: {initial_dv_count}"
                ),
                "subscores": {}
            }

        score += 30
        subscores["has_data_values"] = True
        feedback_parts.append(f"Data values entered for Ngelehun CHC Oct 2023 ({effective_new_count} new) (+30)")

        # Criterion 2: At least 5 data values
        if effective_new_count >= min_values:
            score += 25
            subscores["has_5_values"] = True
            feedback_parts.append(f"≥{min_values} data values entered ({effective_new_count}) (+25)")
        else:
            subscores["has_5_values"] = False
            feedback_parts.append(f"Only {effective_new_count} data value(s) — need ≥{min_values}")

        # Criterion 3: Dataset marked complete
        if complete_after_start >= 1 or complete_exists >= 1:
            score += 25
            subscores["dataset_complete"] = True
            complete_msg = "after task start" if complete_after_start >= 1 else "exists (may be pre-existing)"
            feedback_parts.append(f"Dataset marked complete {complete_msg} (+25)")
        else:
            subscores["dataset_complete"] = False
            feedback_parts.append("Dataset NOT marked complete — must click Complete button in Data Entry")

        # Criterion 4: Values are within plausible range
        if effective_new_count > 0 and (values_in_range >= min(effective_new_count, 5)):
            score += 20
            subscores["values_plausible"] = True
            feedback_parts.append(f"Data values are within plausible range (0-10,000) (+20)")
        elif effective_new_count > 0:
            # Give partial credit if some values are in range
            if values_in_range > 0:
                score += 10
                subscores["values_plausible"] = "partial"
                feedback_parts.append(f"Some values in plausible range ({values_in_range}/{effective_new_count}) (+10)")
            else:
                subscores["values_plausible"] = False
                feedback_parts.append("Entered values are outside plausible range (0-10,000)")
        else:
            subscores["values_plausible"] = False

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "new_data_values": effective_new_count,
                "dataset_completed": complete_after_start >= 1 or complete_exists >= 1
            }
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
