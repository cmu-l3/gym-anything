#!/usr/bin/env python3
"""
Stub verifier for eclipse_contact_time_analysis task.
Actual verification is done externally via VLM evaluators.

Intended scoring rubric (100 points):
- Location near Reykjavik or Rome (lat/lon within 0.10 rad):   10 pts
- Atmosphere ON (flag_atmosphere = true):                        5 pts
- Landscape OFF (flag_landscape = false):                        5 pts
- Constellation lines ON (flag_constellation_drawing = true):    5 pts
- 6+ new screenshots taken:                                     15 pts
- Report file exists at ~/Desktop/eclipse_contact_times.txt:     5 pts
- Report mentions C1/C2/C3/C4 contact times:                    10 pts
- Report contains Sun altitude/azimuth data:                     5 pts
- Report contains totality duration:                             5 pts
- Report contains visible objects during totality:               10 pts
- Report mentions Rome control observation:                      5 pts
- Report mentions Reykjavik/Iceland:                             5 pts
- VLM trajectory: eclipse views visible in frames:              10 pts
- VLM trajectory: multiple time states / phases observed:        5 pts

Pass threshold: 70 points
"""


def verify_eclipse_contact_time_analysis(traj, env_info, task_info):
    """Stub verifier - real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier - VLM evaluation is external"}
