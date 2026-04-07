#!/usr/bin/env python3
"""
Stub verifier for Complete Partial Deployment task.
Actual verification is done externally via VLM evaluators.

Task: Complete a partially-configured Matomo analytics deployment for
'GlobalRetail Corp' based on a deployment specification document.
Covers site config, goals, custom dimensions, segments, Tag Manager,
user management, and dashboard configuration.

Scoring (~107 points, capped at 100):
  Site Config:
    - Currency = EUR:                              3 pts
    - Timezone = Europe/Berlin:                     3 pts
    - E-commerce enabled:                           2 pts
    - Excluded params (fbclid,gclid,session_id):    4 pts
  Goals:
    - Add to Cart pattern fixed to /cart/add:       5 pts
    - Checkout Started created correctly:           5 pts
    - Purchase Complete created (exact match):      6 pts
    - Product Page View preserved:                  2 pts
  Custom Dimensions:
    - Page Category (action, active) created:       5 pts
    - Customer Tier preserved:                      2 pts
  Segments:
    - High-Value Customers created:                 6 pts
    - Mobile Shoppers created:                      5 pts
    - Both segments visible to all:                 2 pts
  Tag Manager:
    - AllPages trigger exists:                      5 pts
    - PageViewTracker tag exists:                   5 pts
    - ConversionEvent tag exists:                   5 pts
    - ConversionEvent correct HTML content:         4 pts
    - Tags linked to AllPages trigger:              3 pts
    - Container published as v1-launch:             5 pts
    - Container has content (non-empty):            3 pts
  Users:
    - marketing_lead exists:                        3 pts
    - marketing_lead has view access:               4 pts
    - data_analyst exists:                          3 pts
    - data_analyst has admin access:                4 pts
    - Neither user is superuser:                    2 pts
  Dashboard:
    - Named 'Client Overview':                      3 pts
    - Referrers widget:                             2 pts
    - DevicesDetection widget:                      2 pts
    - Goals widget:                                 2 pts
  Anti-gaming:
    - Initial Site (ID 1) not modified:             2 pts

Pass threshold: >= 70 points.
"""

from typing import Any, Dict


def verify_complete_partial_deployment(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any],
) -> Dict[str, Any]:
    """Stub verifier — real verification is done via external VLM evaluation."""
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier — VLM evaluation is external",
    }
