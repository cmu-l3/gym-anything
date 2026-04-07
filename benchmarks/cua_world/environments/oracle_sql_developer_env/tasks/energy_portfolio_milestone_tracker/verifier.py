#!/usr/bin/env python3
"""Verifier for Energy Portfolio Milestone Tracker task."""

import json
import logging
import os
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _check_gui_usage(gui_evidence):
    """Check if SQL Developer GUI was actually used (2+ signals required)."""
    if not gui_evidence:
        return False, 0.0, "No GUI evidence"
    signals = 0
    details = []
    if gui_evidence.get('mru_connection_count', 0) > 0:
        signals += 1
        details.append(f"MRU:{gui_evidence['mru_connection_count']}")
    if gui_evidence.get('sqldev_oracle_sessions', 0) > 0:
        signals += 1
        details.append(f"sessions:{gui_evidence['sqldev_oracle_sessions']}")
    if gui_evidence.get('sql_history_count', 0) > 0:
        signals += 1
        details.append(f"history:{gui_evidence['sql_history_count']}")
    gui_used = signals >= 2
    return gui_used, min(signals / 3, 1.0), "; ".join(details) or "No signals"


def verify_energy_portfolio_milestone_tracker(traj, env_info, task_info):
    """
    Verify energy portfolio milestone tracker task completion.

    Scoring (100 pts total):
    1. Milestone Sequence Fixes (40 pts)
       - Each of 4 contaminated projects fixed: 10 pts each
       - shepherds_flat_fixed, alta_wind_fixed, roscoe_fixed, horse_hollow_fixed
       - Partial credit: total_remaining_violations reduced but not zero
    2. Hierarchical View (15 pts)
       - hierarchy_vw_exists: 8 pts
       - connect_by_used: 7 pts
    3. Pivot Dashboard (10 pts)
       - pivot_vw_exists: 5 pts
       - pivot_used: 5 pts
    4. Scheduler Job + Procedure (15 pts)
       - overdue_proc_exists: 5 pts
       - alerts_table_exists: 5 pts
       - scheduler_job_exists: 5 pts
    5. Constraint Enforcement (10 pts)
       - constraint_exists: 10 pts
    6. GUI Usage (10 pts)
       - 2+ signals: full points

    Pass threshold: 70 pts AND milestones_fixed_count >= 3
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/energy_portfolio_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        subscores = {}

        # Extract result fields
        milestones_fixed_count = result.get('milestones_fixed_count', 0)
        total_remaining_violations = result.get('total_remaining_violations', 0)
        shepherds_flat_fixed = result.get('shepherds_flat_fixed', False)
        alta_wind_fixed = result.get('alta_wind_fixed', False)
        roscoe_fixed = result.get('roscoe_fixed', False)
        horse_hollow_fixed = result.get('horse_hollow_fixed', False)
        hierarchy_vw_exists = result.get('hierarchy_vw_exists', False)
        connect_by_used = result.get('connect_by_used', False)
        pivot_vw_exists = result.get('pivot_vw_exists', False)
        pivot_used = result.get('pivot_used', False)
        scheduler_job_exists = result.get('scheduler_job_exists', False)
        overdue_proc_exists = result.get('overdue_proc_exists', False)
        alerts_table_exists = result.get('alerts_table_exists', False)
        alert_count = result.get('alert_count', 0)
        constraint_exists = result.get('constraint_exists', False)
        gui_evidence = result.get('gui_evidence', {})

        # Criterion 1: Milestone Sequence Fixes (40 pts)
        milestone_pts = 0
        fixed_projects = []
        unfixed_projects = []

        if shepherds_flat_fixed:
            milestone_pts += 10
            fixed_projects.append("Shepherds Flat")
        else:
            unfixed_projects.append("Shepherds Flat")

        if alta_wind_fixed:
            milestone_pts += 10
            fixed_projects.append("Alta Wind")
        else:
            unfixed_projects.append("Alta Wind")

        if roscoe_fixed:
            milestone_pts += 10
            fixed_projects.append("Roscoe")
        else:
            unfixed_projects.append("Roscoe")

        if horse_hollow_fixed:
            milestone_pts += 10
            fixed_projects.append("Horse Hollow")
        else:
            unfixed_projects.append("Horse Hollow")

        # Partial credit: if violations reduced but not all projects fully fixed
        # Require at least 1 project fixed to earn partial credit
        if milestone_pts < 40 and total_remaining_violations > 0 and milestones_fixed_count > 0 and milestones_fixed_count < 4:
            # Proportional partial credit for unfixed projects based on violation reduction
            # Assume initial contamination baseline; give partial for effort
            partial_bonus = 0
            if total_remaining_violations <= 2:
                partial_bonus = 5
            elif total_remaining_violations <= 5:
                partial_bonus = 3
            elif total_remaining_violations <= 10:
                partial_bonus = 1
            milestone_pts += partial_bonus
            if partial_bonus > 0:
                feedback_parts.append(
                    f"Milestone fixes: {milestones_fixed_count}/4 projects fully fixed "
                    f"[{', '.join(fixed_projects) or 'none'}] + {partial_bonus} partial credit "
                    f"({total_remaining_violations} remaining violations) ({milestone_pts}/40)"
                )
            else:
                feedback_parts.append(
                    f"Milestone fixes: {milestones_fixed_count}/4 projects fully fixed "
                    f"[{', '.join(fixed_projects) or 'none'}], {total_remaining_violations} "
                    f"remaining violations ({milestone_pts}/40)"
                )
        elif milestone_pts == 40:
            feedback_parts.append(
                f"All 4 contaminated projects fixed with 0 remaining violations (40/40)"
            )
        else:
            feedback_parts.append(
                f"Milestone fixes: {milestones_fixed_count}/4 projects fully fixed "
                f"[{', '.join(fixed_projects) or 'none'}] ({milestone_pts}/40)"
            )

        score += milestone_pts
        subscores['milestones'] = milestones_fixed_count
        subscores['shepherds_flat_fixed'] = shepherds_flat_fixed
        subscores['alta_wind_fixed'] = alta_wind_fixed
        subscores['roscoe_fixed'] = roscoe_fixed
        subscores['horse_hollow_fixed'] = horse_hollow_fixed

        # Criterion 2: Hierarchical View (15 pts)
        hierarchy_pts = 0
        if hierarchy_vw_exists:
            hierarchy_pts += 8
        if connect_by_used:
            hierarchy_pts += 7
        score += hierarchy_pts
        subscores['hierarchy_vw'] = hierarchy_vw_exists
        subscores['connect_by'] = connect_by_used

        if hierarchy_vw_exists and connect_by_used:
            feedback_parts.append(f"Hierarchical view exists with CONNECT BY (15/15)")
        elif hierarchy_vw_exists:
            feedback_parts.append(f"Hierarchical view exists but CONNECT BY not detected (8/15)")
        elif connect_by_used:
            feedback_parts.append(f"CONNECT BY used but hierarchy view not found (7/15)")
        else:
            feedback_parts.append(f"No hierarchical view found (0/15)")

        # Criterion 3: Pivot Dashboard (10 pts)
        pivot_pts = 0
        if pivot_vw_exists:
            pivot_pts += 5
        if pivot_used:
            pivot_pts += 5
        score += pivot_pts
        subscores['pivot_vw'] = pivot_vw_exists
        subscores['pivot_used'] = pivot_used

        if pivot_vw_exists and pivot_used:
            feedback_parts.append(f"Pivot dashboard view exists with PIVOT clause (10/10)")
        elif pivot_vw_exists:
            feedback_parts.append(f"Pivot view exists but PIVOT clause not detected (5/10)")
        elif pivot_used:
            feedback_parts.append(f"PIVOT clause used but pivot view not found (5/10)")
        else:
            feedback_parts.append(f"No pivot dashboard view found (0/10)")

        # Criterion 4: Scheduler Job + Procedure (15 pts)
        scheduler_pts = 0
        if overdue_proc_exists:
            scheduler_pts += 5
        if alerts_table_exists and alert_count > 0:
            scheduler_pts += 5
        if scheduler_job_exists:
            scheduler_pts += 5
        score += scheduler_pts
        subscores['overdue_proc'] = overdue_proc_exists
        subscores['alerts_table'] = alerts_table_exists
        subscores['scheduler_job'] = scheduler_job_exists

        sched_details = []
        if overdue_proc_exists:
            sched_details.append("overdue procedure")
        if alerts_table_exists:
            sched_details.append(f"alerts table ({alert_count} alerts)")
        if scheduler_job_exists:
            sched_details.append("scheduler job")
        if sched_details:
            feedback_parts.append(
                f"Scheduler components: {', '.join(sched_details)} ({scheduler_pts}/15)"
            )
        else:
            feedback_parts.append(f"No scheduler components found (0/15)")

        # Criterion 5: Constraint Enforcement (10 pts)
        constraint_pts = 0
        if constraint_exists:
            constraint_pts = 10
        score += constraint_pts
        subscores['constraint'] = constraint_exists

        if constraint_exists:
            feedback_parts.append(f"Milestone sequence constraint enforced (10/10)")
        else:
            feedback_parts.append(f"No milestone sequence constraint found (0/10)")

        # Criterion 6: GUI Usage (10 pts)
        gui_used, gui_frac, gui_details = _check_gui_usage(gui_evidence)
        gui_pts = int(gui_frac * 10)
        score += gui_pts
        subscores['gui'] = gui_used
        if gui_used:
            feedback_parts.append(f"GUI confirmed ({gui_details}) ({gui_pts}/10)")
        elif gui_pts > 0:
            feedback_parts.append(f"Partial GUI evidence ({gui_details}) ({gui_pts}/10)")
        else:
            feedback_parts.append(f"No GUI usage evidence (0/10)")

        # VLM bonus
        if query_vlm:
            try:
                temp_ss = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
                try:
                    copy_from_env("/tmp/task_end_screenshot.png", temp_ss.name)
                    vlm_prompt = (
                        "Examine this Oracle SQL Developer screenshot. "
                        "Is there evidence of: milestone data correction, hierarchical queries "
                        "using CONNECT BY, PIVOT views, DBMS_SCHEDULER job creation, or "
                        "constraint definitions for energy portfolio data? "
                        "Reply VERIFIED if energy portfolio milestone work is visible, else NOT_VERIFIED."
                    )
                    vlm_result = query_vlm(image=temp_ss.name, prompt=vlm_prompt)
                    if vlm_result and 'VERIFIED' in str(vlm_result).upper() and 'NOT_VERIFIED' not in str(vlm_result).upper():
                        if score < 95:
                            score = min(score + 5, 100)
                            feedback_parts.append("VLM: energy portfolio milestone work visible (+5 bonus)")
                finally:
                    os.unlink(temp_ss.name)
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")

        passed = (
            score >= 70 and
            milestones_fixed_count >= 3
        )

        return {
            "passed": passed,
            "score": min(score, 100),
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid result JSON: {e}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
