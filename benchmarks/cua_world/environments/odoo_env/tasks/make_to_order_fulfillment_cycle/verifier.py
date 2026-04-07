#!/usr/bin/env python3
"""
Stub verifier for make_to_order_fulfillment_cycle task.
Actual verification is done externally via VLM evaluators.

If programmatic verification is needed later, the scoring plan is:

Scoring (100 points, pass >= 65):
  10 pts: SO exists and confirmed (state in {sale, done}) for TechWorld Distributors
  10 pts: SO line has Camera x10 @ $425 (+/- $1)
  10 pts: MO exists for Camera, qty=10
  15 pts: MO is Done (state='done') — hard gate: if fails, cap at 64
  10 pts: PO exists for ShenZhen, USB-C Board, qty>=10, confirmed
  10 pts: Purchase receipt validated (PO picking state='done')
  10 pts: Delivery validated (SO picking state='done', Camera x10)
  10 pts: Invoice posted, amount ~$4,250
  10 pts: Payment registered (payment_state in {paid, in_payment})
   5 pts: MO consumed correct components (5 types x 10 each)

Anti-gaming: verify stock moves originate from correct locations
  (production for cameras, supplier for USB-C boards, customer for delivery)
"""

import json
import logging
import tempfile
import os

logger = logging.getLogger(__name__)


def verify_make_to_order_fulfillment_cycle(traj, env_info, task_info):
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier — VLM evaluation is external",
    }
