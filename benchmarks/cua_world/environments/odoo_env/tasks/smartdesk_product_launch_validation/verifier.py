#!/usr/bin/env python3
"""
Stub verifier for smartdesk_product_launch_validation task.
Actual verification is done externally via VLM evaluators.

If programmatic verification is needed later, the scoring plan is:

Scoring (100 points, pass >= 70):
   5 pts: SmartDesk Pro product template exists with 6 variants
   5 pts: Size attribute Large extra = +$300
   5 pts: Finish attribute Walnut extra = +$200
  10 pts: Sub-assembly "Motorized Lift Frame" BOM correct
          (Linear Actuator x2, Steel Frame x1, Control Unit x1, Cable Harness x1)
  10 pts: Main BOM universal components correct
          (Motorized Lift Frame and Hardware Kit with NO variant restriction)
  20 pts: Main BOM variant-conditional surfaces correct — HARD GATE
          (Oak Board restricted to Oak PTAVs, White Laminate to White,
           Walnut Board to Walnut; if wrong, cap score at 64)
  15 pts: Pricelist "Authorized Dealer Network" with 3 correct tiers
          (1+ at list, 5+ at 15% off, 10+ at 25% off)
  10 pts: Test MO done with correct components consumed
          (Motorized Lift Frame + Walnut Board + Hardware Kit,
           NOT Oak Board or White Laminate)
   5 pts: SO confirmed for Cascade, 8x Standard/Walnut
  15 pts: SO total = $9,520 +/- $10

Anti-gaming: All records must be created after task_start_timestamp.
"""

import json
import logging

logger = logging.getLogger(__name__)


def verify_smartdesk_product_launch(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier — VLM evaluation is external",
    }
