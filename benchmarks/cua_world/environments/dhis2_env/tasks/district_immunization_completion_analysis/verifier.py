#!/usr/bin/env python3
"""
Verifier for district_immunization_completion_analysis task.

Scoring (100 points total):
- Indicator created with matching name (15 pts) [MANDATORY]
- Indicator numerator has subtraction expression (15 pts) [CRITICAL]
- Indicator denominator valid (10 pts)
- Indicator is Percentage type, factor=100 (5 pts)
- Pivot table visualization saved (15 pts)
- Visualization has indicator + data elements (5 pts)
- CSV/XLSX exported to Downloads (10 pts)
- Report file exists at correct path (10 pts)
- Report has substantive analytical content (15 pts)

Pass threshold: 60 points
Mandatory: At least one new indicator must exist
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_district_immunization_completion_analysis(traj, env_info, task_info):
    """Verify district immunization completion analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/district_immunization_completion_analysis_result.json", temp_path)
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
        viz_check = result.get('visualization_check', {})
        dl_check = result.get('downloads_check', {})
        report_check = result.get('report_check', {})

        # =============================================================
        # MANDATORY GATE: At least one new indicator must exist
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
        # Indicator (15 + 15 + 10 + 5 = 45 pts)
        # =============================================================
        dropout_found = ind_check.get('dropout_indicator_found', False)
        dropout_ind = ind_check.get('dropout_indicator', {}) or {}

        # If no dropout-classified indicator, use the first new one
        if not dropout_found and new_ind_count > 0:
            all_new = ind_check.get('all_new_indicators', [])
            if all_new:
                dropout_ind = all_new[0]
                dropout_found = True

        if dropout_found:
            score += 15
            subscores["indicator_created"] = True
            feedback_parts.append(f"Indicator created: {dropout_ind.get('name', 'unknown')} (+15)")

            # CRITICAL: Numerator has subtraction
            if dropout_ind.get('has_subtraction_in_numerator', False):
                score += 15
                subscores["numerator_subtraction"] = True
                feedback_parts.append("Numerator has subtraction expression (+15)")
            else:
                subscores["numerator_subtraction"] = False
                feedback_parts.append("Numerator missing subtraction (CRITICAL)")

            # Denominator valid
            if dropout_ind.get('denominator_has_formula', False):
                score += 10
                subscores["denominator_valid"] = True
                feedback_parts.append("Denominator configured (+10)")
            else:
                subscores["denominator_valid"] = False
                feedback_parts.append("Denominator empty or invalid")

            # Percentage type
            if dropout_ind.get('factor', 1) == 100:
                score += 5
                subscores["percentage_type"] = True
                feedback_parts.append("Indicator is Percentage type (+5)")
            else:
                subscores["percentage_type"] = False
                feedback_parts.append(f"Indicator factor is {dropout_ind.get('factor', 1)} (expected 100)")
        else:
            subscores["indicator_created"] = False
            feedback_parts.append("No matching indicator found")

        # =============================================================
        # Visualization (15 + 5 = 20 pts)
        # =============================================================
        target_found = viz_check.get('target_found', False) or viz_check.get('new_viz_count', 0) > 0
        best_viz = viz_check.get('best_match', {}) or {}

        if target_found and best_viz:
            viz_type = best_viz.get('type', '')
            if viz_type == 'PIVOT_TABLE':
                score += 15
                subscores["viz_created"] = True
                feedback_parts.append("Pivot table visualization saved (+15)")
            else:
                score += 8
                subscores["viz_created"] = "partial"
                feedback_parts.append(f"Visualization saved but type is {viz_type} (expected PIVOT_TABLE, +8)")

            # Check if has both indicators and data elements
            has_indicators = best_viz.get('indicator_count', 0) > 0
            has_data_elements = best_viz.get('data_element_count', 0) > 0
            if has_indicators and has_data_elements:
                score += 5
                subscores["viz_data_complete"] = True
                feedback_parts.append("Visualization has both indicator and data elements (+5)")
            elif has_indicators or has_data_elements:
                score += 2
                subscores["viz_data_complete"] = "partial"
                feedback_parts.append("Visualization has partial data dimensions (+2)")
            else:
                subscores["viz_data_complete"] = False
                feedback_parts.append("Visualization missing data dimensions")
        else:
            subscores["viz_created"] = False
            feedback_parts.append("No matching visualization found")

        # =============================================================
        # CSV Export (10 pts)
        # =============================================================
        csv_count = dl_check.get('csv_xlsx_count', 0)
        if csv_count > 0:
            score += 10
            subscores["csv_exported"] = True
            feedback_parts.append(f"CSV/XLSX exported to Downloads ({csv_count} file(s)) (+10)")
        else:
            new_dl = dl_check.get('new_files_count', 0)
            if new_dl > 0:
                score += 5
                subscores["csv_exported"] = "partial"
                feedback_parts.append(f"Files in Downloads but no CSV/XLSX ({new_dl} file(s)) (+5)")
            else:
                subscores["csv_exported"] = False
                feedback_parts.append("No files found in Downloads after task start")

        # =============================================================
        # Report File (10 + 15 = 25 pts)
        # =============================================================
        report_exists = report_check.get('exists', False)

        if report_exists:
            score += 10
            subscores["report_exists"] = True
            feedback_parts.append("Report file exists at correct path (+10)")

            # Check substantive content (up to 15 pts)
            content_score = 0
            has_count = report_check.get('has_facility_count', False)
            has_threshold = report_check.get('has_threshold_count', False)
            has_name = report_check.get('has_facility_name', False)
            has_trend = report_check.get('has_trend_assessment', False)

            if has_count:
                content_score += 4
            if has_threshold:
                content_score += 4
            if has_name:
                content_score += 4
            if has_trend:
                content_score += 3

            score += content_score
            subscores["report_content"] = content_score
            parts = []
            if has_count:
                parts.append("facility count")
            if has_threshold:
                parts.append("threshold analysis")
            if has_name:
                parts.append("facility name")
            if has_trend:
                parts.append("trend assessment")
            feedback_parts.append(f"Report content: {', '.join(parts) if parts else 'insufficient'} (+{content_score})")
        else:
            subscores["report_exists"] = False
            subscores["report_content"] = 0
            feedback_parts.append("Report file not found at /home/ga/Desktop/dropout_report.txt")

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
