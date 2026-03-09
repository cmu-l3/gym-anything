#!/usr/bin/env python3
"""
Verifier for legend_performance_classification task.

Scoring (100 points total):
- Legend set created (MANDATORY) 25 pts
- Legend set has >= 3 items 15 pts
- Legend items span 0-100 10 pts
- Visualization saved 25 pts
- Visualization name matches 10 pts
- Visualization is PIVOT_TABLE 10 pts
- Anti-gaming: legend has distinct colors 5 pts

Pass threshold: 60 points
Mandatory: Legend set created
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_legend_performance_classification(traj, env_info, task_info):
    """Verify legend set creation and visualization application."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/legend_performance_result.json", temp_path)
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

        # ---------------------------------------------------------
        # Check Legend Set (Mandatory)
        # ---------------------------------------------------------
        legend_data = result.get('legend_analysis', {})
        legend_found = legend_data.get('found', False)
        best_legend = legend_data.get('best_match', {})

        if not legend_found or not best_legend:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Mandatory Requirement Failed: No new Legend Set with 'EPI', 'Coverage', or 'Performance' in name found.",
                "subscores": {}
            }

        score += 25
        subscores["legend_created"] = True
        legend_name = best_legend.get('name', 'Unknown')
        feedback_parts.append(f"Legend Set '{legend_name}' created (+25)")

        # Item count check (>= 3 items)
        item_count = best_legend.get('item_count', 0)
        if item_count >= 3:
            score += 15
            subscores["items_count"] = True
            feedback_parts.append(f"Legend has {item_count} items (+15)")
        else:
            subscores["items_count"] = False
            feedback_parts.append(f"Legend has only {item_count} items (required ≥3)")

        # Range check (0 to 100)
        min_start = best_legend.get('min_start', -1)
        max_end = best_legend.get('max_end', -1)
        if min_start <= 0 and max_end >= 100:
            score += 10
            subscores["range_check"] = True
            feedback_parts.append("Legend range covers 0-100 (+10)")
        else:
            subscores["range_check"] = False
            feedback_parts.append(f"Legend range incomplete: {min_start}-{max_end}")

        # Color check (anti-gaming)
        distinct_colors = best_legend.get('distinct_color_count', 0)
        if distinct_colors >= 2:
            score += 5
            subscores["colors_distinct"] = True
            feedback_parts.append("Distinct colors used (+5)")
        else:
            subscores["colors_distinct"] = False
            feedback_parts.append("Legend items do not have distinct colors")

        # ---------------------------------------------------------
        # Check Visualization
        # ---------------------------------------------------------
        viz_data = result.get('viz_analysis', {})
        viz_found = viz_data.get('found', False)
        best_viz = viz_data.get('best_match', {})

        if viz_found and best_viz:
            score += 25
            subscores["viz_created"] = True
            viz_name = best_viz.get('name', 'Unknown')
            feedback_parts.append(f"Visualization created (+25)")

            # Name check
            # Filter logic in export script already filtered for 'immunization', 'scorecard', 'district'
            # We can give points if it was found by that filter
            score += 10
            subscores["viz_name"] = True
            feedback_parts.append(f"Visualization name '{viz_name}' matches keywords (+10)")

            # Type check
            viz_type = best_viz.get('type', '')
            if viz_type == 'PIVOT_TABLE':
                score += 10
                subscores["viz_type"] = True
                feedback_parts.append("Visualization type is PIVOT_TABLE (+10)")
            else:
                subscores["viz_type"] = False
                feedback_parts.append(f"Visualization type is {viz_type} (expected PIVOT_TABLE)")
            
            # Optional check: Is legend applied?
            # Not strictly point-bearing based on prompt spec, but good for feedback
            legend_applied = best_viz.get('legend_applied', False)
            if legend_applied:
                feedback_parts.append(f"Legend '{best_viz.get('legend_applied_name','')}' applied to visualization")
            else:
                feedback_parts.append("Warning: Legend set not applied to visualization")

        else:
            subscores["viz_created"] = False
            feedback_parts.append("No matching visualization found")

        # Final pass check
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