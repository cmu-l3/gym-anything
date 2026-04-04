#!/usr/bin/env python3
"""Verifier for turbine_performance_evaluation task.

Scoring (100 points):
- Gate: if neither BEM file nor report file exists, score=0 immediately
- BEM results file exists: 15 points
- BEM results have multi-column numeric data with >=10 points: 15 points
- BEM results contain Cp and/or TSR data labels: 15 points
- Report file exists with content: 15 points
- Report mentions optimal TSR (value 5-12): 15 points
- Report mentions max Cp (value 0.30-0.55): 15 points
- QBlade was running: 10 points

Pass threshold: 70 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_turbine_performance_evaluation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    tsr_range = metadata.get('optimal_tsr_range', [5, 12])
    cp_range = metadata.get('max_cp_range', [0.3, 0.55])

    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_file.name)

        score = 0
        feedback_parts = []
        subscores = {}

        bem = result.get('bem_file', {})
        report = result.get('report_file', {})

        # Gate: if NEITHER output file exists, no work was done
        if not bem.get('exists') and not report.get('exists'):
            return {
                "passed": False,
                "score": 0,
                "feedback": "No output files found — neither BEM results nor report created"
            }

        # Criterion 1: BEM results file exists (15 pts)
        try:
            if bem.get('exists'):
                score += 15
                subscores['bem_exists'] = True
                feedback_parts.append("BEM results file exists")
            else:
                feedback_parts.append("BEM results file not found")
        except Exception as e:
            feedback_parts.append(f"BEM file check error: {e}")

        # Criterion 2: BEM has numeric data (15 pts)
        try:
            dp = bem.get('data_points', 0)
            if bem.get('has_data') and dp >= 10:
                score += 15
                subscores['bem_data'] = True
                feedback_parts.append(f"BEM data: {dp} numeric rows")
            elif bem.get('has_data') and dp >= 5:
                score += 8
                feedback_parts.append(f"BEM data: only {dp} numeric rows")
            elif bem.get('has_data'):
                score += 4
                feedback_parts.append(f"BEM data: minimal ({dp} rows)")
            else:
                feedback_parts.append("BEM file lacks numeric data")
        except Exception as e:
            feedback_parts.append(f"BEM data check error: {e}")

        # Criterion 3: BEM contains Cp/TSR labels (15 pts)
        try:
            has_cp = bem.get('has_cp', False)
            has_tsr = bem.get('has_tsr', False)
            if has_cp and has_tsr:
                score += 15
                subscores['bem_labels'] = True
                feedback_parts.append("BEM data has both Cp and TSR labels")
            elif has_cp or has_tsr:
                score += 8
                label = "Cp" if has_cp else "TSR"
                feedback_parts.append(f"BEM data has {label} label only")
            else:
                feedback_parts.append("BEM data lacks Cp/TSR labels")
        except Exception as e:
            feedback_parts.append(f"BEM label check error: {e}")

        # Criterion 4: Report file exists (15 pts)
        try:
            if report.get('exists') and report.get('lines', 0) >= 2:
                score += 15
                subscores['report_exists'] = True
                feedback_parts.append(f"Report file exists ({report.get('lines', 0)} lines)")
            elif report.get('exists'):
                score += 8
                feedback_parts.append("Report file exists but minimal content")
            else:
                feedback_parts.append("Report file not found")
        except Exception as e:
            feedback_parts.append(f"Report file check error: {e}")

        # Criterion 5: Report mentions optimal TSR (15 pts)
        try:
            if report.get('has_optimal_tsr'):
                tsr_val = report.get('tsr_value', '')
                try:
                    tsr_num = float(tsr_val)
                    if tsr_range[0] <= tsr_num <= tsr_range[1]:
                        score += 15
                        subscores['optimal_tsr'] = True
                        feedback_parts.append(f"Optimal TSR reported: {tsr_num} (expected range {tsr_range[0]}-{tsr_range[1]})")
                    else:
                        score += 8
                        feedback_parts.append(f"TSR value {tsr_num} outside expected range {tsr_range[0]}-{tsr_range[1]}")
                except (ValueError, TypeError):
                    score += 5
                    feedback_parts.append(f"TSR mentioned but value unclear: '{tsr_val}'")
            else:
                feedback_parts.append("Report does not mention optimal TSR")
        except Exception as e:
            feedback_parts.append(f"TSR check error: {e}")

        # Criterion 6: Report mentions max Cp (15 pts)
        try:
            if report.get('has_max_cp'):
                cp_val = report.get('cp_value', '')
                try:
                    cp_num = float(cp_val)
                    if cp_range[0] <= cp_num <= cp_range[1]:
                        score += 15
                        subscores['max_cp'] = True
                        feedback_parts.append(f"Max Cp reported: {cp_num} (expected range {cp_range[0]}-{cp_range[1]})")
                    else:
                        score += 8
                        feedback_parts.append(f"Cp value {cp_num} outside expected range {cp_range[0]}-{cp_range[1]}")
                except (ValueError, TypeError):
                    score += 5
                    feedback_parts.append(f"Cp mentioned but value unclear: '{cp_val}'")
            else:
                feedback_parts.append("Report does not mention max Cp")
        except Exception as e:
            feedback_parts.append(f"Cp check error: {e}")

        # Criterion 7: QBlade running (10 pts) — but NOT sufficient to pass alone
        try:
            if result.get('qblade_running'):
                score += 10
                subscores['qblade_running'] = True
                feedback_parts.append("QBlade running")
        except Exception as e:
            feedback_parts.append(f"QBlade check error: {e}")

        passed = score >= 70

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts) or "No criteria met",
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
