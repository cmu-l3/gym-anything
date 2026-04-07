#!/usr/bin/env python3
"""
Verifier for exhaust_port_gasket_template task.

A manufacturing engineer must create a flat gasket cutting template for an
engine exhaust port flange. The gasket has:
  - 150x120mm rectangular outer boundary centered at origin
  - Egg-shaped exhaust port bore: semicircular bottom arc (R=20mm),
    horizontal top flat (30mm), two fillet arcs (R=8mm) connecting them
    with tangent transitions (arc-to-arc and arc-to-line)
  - 4x bolt clearance holes (Ø9mm) at (±50, ±40)
  - Extruded to 2mm material thickness
  - Saved as exhaust_gasket.slvs + exported as exhaust_gasket.dxf

Stub verifier — VLM checklist evaluation is used externally.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/exhaust_port_gasket_result.json"


def verify_exhaust_port_gasket(traj, env_info, task_info):
    """Stub verifier — returns pass with note that VLM evaluation is external."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier — VLM checklist evaluation is performed externally."
    }
