#!/usr/bin/env python3
"""
Verifier for malaria_burden_dashboard task.

Scoring (100 points total):
- Dashboard created with malaria-related name (20 pts)
- Dashboard was created after task start (10 pts)
- Dashboard has at least 2 items (20 pts)
- Dashboard has at least 3 items (15 pts)
- At least one column/bar chart visualization created (15 pts)
- At least one map visualization created (10 pts)
- At least one pivot table visualization created (10 pts)

Pass threshold: 60 points
Mandatory: Dashboard created (20 pts) must be satisfied
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_malaria_burden_dashboard(traj, env_info, task_info):
    """Verify that a malaria burden dashboard was created with required visualizations."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/malaria_burden_dashboard_result.json", temp_path)
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

        # Criterion 1: A NEW dashboard with malaria-related name was created (MANDATORY)
        # Must be genuinely new - not a pre-existing demo dashboard
        dashboard_found = result.get('dashboard_found', False)
        if isinstance(dashboard_found, str):
            dashboard_found = dashboard_found.lower() == 'true'

        is_new_dashboard = result.get('is_new_dashboard', dashboard_found)
        if isinstance(is_new_dashboard, str):
            is_new_dashboard = is_new_dashboard.lower() == 'true'

        # Also check net increase in dashboard count
        current_count = int(result.get('current_dashboard_count', 0))
        initial_count = int(result.get('initial_dashboard_count', 0))
        net_new = current_count - initial_count

        if not dashboard_found or (not is_new_dashboard and net_new <= 0):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No new malaria-related dashboard was created. Agent must create a new dashboard with 'Malaria' or 'burden' in the name.",
                "subscores": {}
            }

        score += 20
        subscores["dashboard_created"] = True
        dashboard_name = result.get('dashboard_name', '')
        feedback_parts.append(f"Dashboard '{dashboard_name}' created (+20)")

        # Criterion 2: Dashboard created after task start
        created_after = result.get('dashboard_created_after_start', False)
        if isinstance(created_after, str):
            created_after = created_after.lower() == 'true'

        if created_after:
            score += 10
            subscores["created_after_start"] = True
            feedback_parts.append("Dashboard created during task (+10)")
        else:
            subscores["created_after_start"] = False
            feedback_parts.append("Dashboard may be pre-existing (0)")

        # Criterion 3: Dashboard has at least 2 items
        item_count = int(result.get('dashboard_item_count', 0))
        if item_count >= 2:
            score += 20
            subscores["has_2_items"] = True
            feedback_parts.append(f"Dashboard has {item_count} items (≥2) (+20)")
        else:
            subscores["has_2_items"] = False
            feedback_parts.append(f"Dashboard has only {item_count} items (need ≥2)")

        # Criterion 4: Dashboard has at least 3 items
        if item_count >= 3:
            score += 15
            subscores["has_3_items"] = True
            feedback_parts.append("Dashboard has ≥3 items (+15)")
        else:
            subscores["has_3_items"] = False

        # Criterion 5: At least one bar/column chart visualization created
        has_chart = result.get('has_column_or_bar_chart', False)
        if isinstance(has_chart, str):
            has_chart = has_chart.lower() == 'true'

        new_viz_count = int(result.get('new_visualization_count', 0))

        if has_chart or new_viz_count >= 1:
            score += 15
            subscores["has_bar_chart"] = True
            feedback_parts.append("Bar/column chart visualization created (+15)")
        else:
            subscores["has_bar_chart"] = False
            feedback_parts.append("No bar/column chart visualization found")

        # Criterion 6: At least one map visualization created
        new_map_count = int(result.get('new_map_count', 0))
        if new_map_count >= 1:
            score += 10
            subscores["has_map"] = True
            feedback_parts.append(f"Map visualization created (+10)")
        else:
            subscores["has_map"] = False
            feedback_parts.append("No new map visualization found (0)")

        # Criterion 7: At least one pivot table visualization created
        has_pivot = result.get('has_pivot_table', False)
        if isinstance(has_pivot, str):
            has_pivot = has_pivot.lower() == 'true'

        if has_pivot:
            score += 10
            subscores["has_pivot"] = True
            feedback_parts.append("Pivot table visualization created (+10)")
        else:
            subscores["has_pivot"] = False
            feedback_parts.append("No pivot table visualization found (0)")

        passed = score >= 60

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except Exception as e:
        logger.exception("Unexpected error in verifier")
        return {"passed": False, "score": 0, "feedback": f"Verifier error: {str(e)}"}
