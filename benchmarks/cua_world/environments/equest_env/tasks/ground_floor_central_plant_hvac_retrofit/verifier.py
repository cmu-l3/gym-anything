#!/usr/bin/env python3
"""
Verifier stub for ground_floor_central_plant_hvac_retrofit task.

This task is primarily verified via VLM checklist evaluation.
The programmatic verifier is a stub that returns a default pass.

Full verification (if implemented) would check the exported JSON for:
- CIRCULATION-LOOP objects (CHW and HW) with correct types and temperatures
- CHILLER object with correct EIR, capacity, and CHW-LOOP attachment
- BOILER object with correct HIR, capacity, and HW-LOOP attachment
- 5 Ground Floor SYSTEM objects with COOL-SOURCE=CHW, HEAT-SOURCE=HOT-WATER,
  correct loop attachments, and ERV parameters
- Simulation ran during session (sim_file_is_new)
"""


def verify_task(traj, env_info, task_info):
    """Stub verifier — real verification is done via VLM checklist evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier. Use VLM checklist for actual evaluation."
    }
