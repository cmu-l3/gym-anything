#!/usr/bin/env python3
"""Verifier stub for mandm_conference_case_review task.

Actual verification will be performed via vlm_checklist_verifier.

Scoring overview (100 points total):
  - full_timeline.png: exists >10KB, shows HR/SpO2/ETCO2 tracks with Y-axis ranges (20 pts)
  - induction_detail.png: exists >10KB, shows ~15min after Surgery started (17 pts)
  - emergence_detail.png: exists >10KB, shows ~15min before Surgery finished (17 pts)
  - intraop_data.csv: exists >100B, has physio columns, correct row fraction (21 pts)
  - case_report.txt: exists >300B, has durations/devices/monitoring info (25 pts)

Pass threshold: 60 points
"""


def verify_mandm_conference_case_review(traj, env_info, task_info):
    """Stub verifier — returns passed=True, score=100."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier: actual evaluation via vlm_checklist_verifier.",
    }
