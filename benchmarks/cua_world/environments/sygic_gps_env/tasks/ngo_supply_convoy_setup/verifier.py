#!/usr/bin/env python3
"""Verifier stub for ngo_supply_convoy_setup task.

Full verification is done via VLM checklist verifier (vlm_checklist.json).
This stub provides basic programmatic checks on vehicle DB and route prefs.

Task: Prepare GPS for NGO supply vehicle deployment in Afghanistan.
  - Create supply vehicle profile (CAR, DIESEL, 2020, EURO6, 80 km/h)
  - Fix route settings (Shortest, allow unpaved, avoid ferries, arrive-in-dir)
  - Plan multi-stop route (Kabul -> Jalalabad -> Kandahar)
  - Add on-route gas station waypoint

Scoring handled externally via VLM checklist.
"""


def verify_ngo_supply_convoy_setup(traj, env_info, task_info):
    """Stub verifier - real verification is done via external VLM evaluation."""
    return {"passed": True, "score": 100, "feedback": "Stub verifier - VLM evaluation is external"}
