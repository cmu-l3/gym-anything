#!/usr/bin/env python3
"""
Verifier for rmncah_scorecard_dashboard task.

Scoring (100 points total):
- ANC indicator created (10 pts) [MANDATORY - at least one indicator must exist]
- ANC numerator valid (8 pts)
- ANC denominator valid (7 pts)
- Dropout indicator created (10 pts) [MANDATORY]
- Dropout numerator has subtraction (15 pts) [CRITICAL]
- Dropout numerator refs correct DEs (5 pts)
- Dropout denominator valid (5 pts)
- Both indicators Percentage type (5 pts)
- Legend set created with >=3 items (10 pts)
- Legend range covers 0-100 (5 pts)
- Pivot table visualization saved (10 pts)
- Dashboard with >=1 item (10 pts)

Pass threshold: 60 points
Mandatory: At least one indicator must exist
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_rmncah_scorecard_dashboard(traj, env_info, task_info):
    """Verify RMNCAH scorecard dashboard configuration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/rmncah_scorecard_result.json", temp_path)
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

        ind_check = result.get('indicator_check', {})
        legend_check = result.get('legend_check', {})
        viz_check = result.get('visualization_check', {})
        dash_check = result.get('dashboard_check', {})
        de_uids = result.get('data_element_uids', {})

        # =============================================================
        # MANDATORY GATE: At least one indicator must exist
        # =============================================================
        new_ind_count = ind_check.get('new_indicator_count', 0)
        if new_ind_count == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Mandatory requirement failed: No new indicators were created.",
                "subscores": {}
            }

        # =============================================================
        # ANC Indicator (10 + 8 + 7 = 25 pts)
        # =============================================================
        anc_found = ind_check.get('anc_indicator_found', False)
        anc_ind = ind_check.get('anc_indicator', {}) or {}

        if anc_found:
            score += 10
            subscores["anc_indicator_created"] = True
            feedback_parts.append("ANC indicator created (+10)")

            # Numerator valid
            if anc_ind.get('numerator_has_formula', False):
                score += 8
                subscores["anc_numerator_valid"] = True
                feedback_parts.append("ANC numerator configured (+8)")
            else:
                subscores["anc_numerator_valid"] = False
                feedback_parts.append("ANC numerator empty or invalid")

            # Denominator valid
            if anc_ind.get('denominator_has_formula', False):
                score += 7
                subscores["anc_denominator_valid"] = True
                feedback_parts.append("ANC denominator configured (+7)")
            else:
                subscores["anc_denominator_valid"] = False
                feedback_parts.append("ANC denominator empty or invalid")
        else:
            subscores["anc_indicator_created"] = False
            feedback_parts.append("No ANC-related indicator found")

        # =============================================================
        # Dropout Indicator (10 + 15 + 5 + 5 = 35 pts)
        # =============================================================
        dropout_found = ind_check.get('dropout_indicator_found', False)
        dropout_ind = ind_check.get('dropout_indicator', {}) or {}

        if dropout_found:
            score += 10
            subscores["dropout_indicator_created"] = True
            feedback_parts.append("Dropout indicator created (+10)")

            # CRITICAL: Numerator has subtraction
            if dropout_ind.get('has_subtraction_in_numerator', False):
                score += 15
                subscores["dropout_subtraction"] = True
                feedback_parts.append("Dropout numerator has subtraction expression (+15)")
            else:
                subscores["dropout_subtraction"] = False
                feedback_parts.append("Dropout numerator missing subtraction (CRITICAL)")

            # Numerator refs correct DEs
            numerator = dropout_ind.get('numerator', '')
            penta1_uid = de_uids.get('Penta 1 doses given', '')
            penta3_uid = de_uids.get('Penta 3 doses given', '')
            refs_correct = False
            if penta1_uid and penta3_uid:
                refs_correct = penta1_uid in numerator and penta3_uid in numerator
            elif numerator and '#{' in numerator:
                # At least has data element references
                refs_correct = numerator.count('#{') >= 2

            if refs_correct:
                score += 5
                subscores["dropout_numerator_refs"] = True
                feedback_parts.append("Dropout numerator references correct DEs (+5)")
            else:
                subscores["dropout_numerator_refs"] = False
                feedback_parts.append("Dropout numerator DE references unclear")

            # Denominator valid
            if dropout_ind.get('denominator_has_formula', False):
                score += 5
                subscores["dropout_denominator_valid"] = True
                feedback_parts.append("Dropout denominator configured (+5)")
            else:
                subscores["dropout_denominator_valid"] = False
                feedback_parts.append("Dropout denominator empty or invalid")
        else:
            subscores["dropout_indicator_created"] = False
            feedback_parts.append("No dropout-related indicator found")

        # =============================================================
        # Both indicators Percentage type (5 pts)
        # =============================================================
        anc_pct = anc_ind.get('factor', 1) == 100 if anc_ind else False
        dropout_pct = dropout_ind.get('factor', 1) == 100 if dropout_ind else False
        if anc_pct and dropout_pct:
            score += 5
            subscores["percentage_type"] = True
            feedback_parts.append("Both indicators are Percentage type (+5)")
        elif anc_pct or dropout_pct:
            score += 2
            subscores["percentage_type"] = "partial"
            feedback_parts.append("One indicator is Percentage type (+2)")
        else:
            subscores["percentage_type"] = False
            feedback_parts.append("Neither indicator is Percentage type")

        # =============================================================
        # Legend Set (10 + 5 = 15 pts)
        # =============================================================
        legend_found = legend_check.get('rmncah_legend_found', False) or legend_check.get('new_legend_count', 0) > 0
        best_legend = legend_check.get('best_match', {}) or {}

        if legend_found and best_legend:
            item_count = best_legend.get('item_count', 0)
            if item_count >= 3:
                score += 10
                subscores["legend_created"] = True
                feedback_parts.append(f"Legend set created with {item_count} items (+10)")
            elif item_count > 0:
                score += 5
                subscores["legend_created"] = "partial"
                feedback_parts.append(f"Legend set created but only {item_count} items (+5)")
            else:
                subscores["legend_created"] = False
                feedback_parts.append("Legend set exists but has no items")

            # Range check
            min_start = best_legend.get('min_start', -1)
            max_end = best_legend.get('max_end', -1)
            if min_start >= 0 and min_start <= 2 and max_end >= 98:
                score += 5
                subscores["legend_range"] = True
                feedback_parts.append("Legend range covers 0-100 (+5)")
            else:
                subscores["legend_range"] = False
                feedback_parts.append(f"Legend range: {min_start}-{max_end} (expected 0-100)")
        else:
            subscores["legend_created"] = False
            feedback_parts.append("No legend set found")

        # =============================================================
        # Visualization (10 pts)
        # =============================================================
        scorecard_found = viz_check.get('scorecard_found', False) or viz_check.get('new_viz_count', 0) > 0
        best_viz = viz_check.get('best_match', {}) or {}

        if scorecard_found and best_viz:
            viz_type = best_viz.get('type', '')
            if viz_type == 'PIVOT_TABLE':
                score += 10
                subscores["viz_created"] = True
                feedback_parts.append(f"Pivot table visualization saved (+10)")
            else:
                score += 5
                subscores["viz_created"] = "partial"
                feedback_parts.append(f"Visualization saved but type is {viz_type} (expected PIVOT_TABLE, +5)")
        else:
            subscores["viz_created"] = False
            feedback_parts.append("No matching visualization found")

        # =============================================================
        # Dashboard (10 pts)
        # =============================================================
        dash_found = dash_check.get('rmncah_dashboard_found', False) or dash_check.get('new_dashboard_count', 0) > 0
        best_dash = dash_check.get('best_match', {}) or {}

        if dash_found and best_dash:
            item_count = best_dash.get('item_count', 0)
            if item_count >= 1:
                score += 10
                subscores["dashboard_created"] = True
                feedback_parts.append(f"Dashboard created with {item_count} item(s) (+10)")
            else:
                score += 5
                subscores["dashboard_created"] = "partial"
                feedback_parts.append("Dashboard created but no items added (+5)")
        else:
            subscores["dashboard_created"] = False
            feedback_parts.append("No matching dashboard found")

        # =============================================================
        # Final result
        # =============================================================
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
