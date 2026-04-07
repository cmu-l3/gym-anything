#!/usr/bin/env python3
"""
Verifier for microservice_mesh_connectivity_restoration task.

Scoring (100 points total):
- C1 (20 pts): api-gateway Service has >= 1 endpoint address (selector fixed)
- C2 (20 pts): product-service INVENTORY_HOST contains 'ecommerce-platform' FQDN
- C3 (20 pts): NetworkPolicy allows port 3000 egress from cart-service
- C4 (20 pts): payment-config ConfigMap NOTIFICATION_HOST contains 'ecommerce-platform'
- C5 (20 pts): inventory-db Service port is 5432

Pass threshold: 70 (any 4 of 5 criteria, or 3 criteria + partial — but scoring is binary per criterion)

Anti-gaming analysis:
  Do-nothing: C1=0 (selector typo → 0 endpoints), C2=0 (wrong namespace FQDN),
              C3=0 (port 3000 blocked), C4=0 (wrong namespace in NOTIFICATION_HOST),
              C5=0 (port=5433) → score=0
  Wrong namespace: rejected with score=0
  Delete namespace: score=0 (all checks return defaults/errors)
  Max partial total: 0 per criterion (binary scoring) → cannot game partial credits

Strategy enumeration:
  | Strategy          | C1 | C2 | C3 | C4 | C5 | Score | Pass? |
  | Do-nothing        |  0 |  0 |  0 |  0 |  0 |     0 | No    |
  | Fix C1 only       | 20 |  0 |  0 |  0 |  0 |    20 | No    |
  | Fix any 3         | 20 | 20 | 20 |  0 |  0 |    60 | No    |
  | Fix any 4         | 20 | 20 | 20 | 20 |  0 |    80 | Yes   |
  | Fix all 5         | 20 | 20 | 20 | 20 | 20 |   100 | Yes   |
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/microservice_mesh_connectivity_restoration_result.json"
PASS_THRESHOLD = 70


def verify_microservice_mesh_connectivity_restoration(traj, env_info, task_info):
    """
    Verify that all 5 microservice connectivity failures have been restored.

    Scoring:
      C1: api-gateway Service has >= 1 endpoint               20 pts
      C2: product-service INVENTORY_HOST uses ecommerce-platform FQDN  20 pts
      C3: NetworkPolicy allows port 3000 egress from cart-service       20 pts
      C4: payment-config NOTIFICATION_HOST uses ecommerce-platform      20 pts
      C5: inventory-db Service port is 5432                             20 pts
    Pass: >= 70
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        try:
            copy_from_env(RESULT_PATH, tmp.name)
            with open(tmp.name, "r") as f:
                result = json.load(f)
        finally:
            try:
                os.unlink(tmp.name)
            except Exception:
                pass
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export script did not run",
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}

    # Wrong-target guard
    if result.get("namespace") != "ecommerce-platform":
        return {
            "passed": False,
            "score": 0,
            "feedback": "Wrong namespace — must target 'ecommerce-platform'",
        }

    score = 0
    feedback_parts = []

    # ── Criterion 1: api-gateway Service must have >= 1 endpoint ─────────────
    api_gw = result.get("api_gateway", {})
    endpoint_count = int(api_gw.get("endpoint_count", 0))
    selector = api_gw.get("service_selector", "")

    if endpoint_count >= 1:
        score += 20
        feedback_parts.append(
            f"C1 PASS: api-gateway Service has {endpoint_count} endpoint(s) — selector fixed (+20)"
        )
    else:
        feedback_parts.append(
            f"C1 FAIL: api-gateway Service has 0 endpoints — selector={selector!r} "
            f"(must select 'app: api-gateway' pods)"
        )

    # ── Criterion 2: product-service INVENTORY_HOST must contain 'ecommerce-platform' ──
    prod = result.get("product_service", {})
    inventory_host = prod.get("inventory_host", "")

    if "ecommerce-platform" in str(inventory_host):
        score += 20
        feedback_parts.append(
            f"C2 PASS: product-service INVENTORY_HOST='{inventory_host}' uses correct namespace (+20)"
        )
    else:
        feedback_parts.append(
            f"C2 FAIL: product-service INVENTORY_HOST='{inventory_host}' — "
            f"must contain 'ecommerce-platform' (not another namespace FQDN)"
        )

    # ── Criterion 3: NetworkPolicy must allow port 3000 egress ───────────────
    netpol = result.get("cart_service_netpol", {})
    policy_exists = int(netpol.get("policy_exists", 0))
    allows_3000 = str(netpol.get("allows_port_3000", "false")).lower()

    # Pass if: policy doesn't exist (no restriction) OR policy explicitly allows 3000
    if policy_exists == 0 or allows_3000 == "true":
        score += 20
        if policy_exists == 0:
            feedback_parts.append(
                "C3 PASS: NetworkPolicy 'restrict-cart-egress' removed — port 3000 egress unblocked (+20)"
            )
        else:
            feedback_parts.append(
                "C3 PASS: NetworkPolicy 'restrict-cart-egress' now allows port 3000 egress (+20)"
            )
    else:
        feedback_parts.append(
            f"C3 FAIL: NetworkPolicy 'restrict-cart-egress' still blocks port 3000 egress from cart-service "
            f"(allows_port_3000={allows_3000})"
        )

    # ── Criterion 4: payment-config NOTIFICATION_HOST must contain 'ecommerce-platform' ──
    pay = result.get("payment_config", {})
    notification_host = pay.get("notification_host", "")

    if "ecommerce-platform" in str(notification_host):
        score += 20
        feedback_parts.append(
            f"C4 PASS: payment-config NOTIFICATION_HOST='{notification_host}' uses correct namespace (+20)"
        )
    else:
        feedback_parts.append(
            f"C4 FAIL: payment-config NOTIFICATION_HOST='{notification_host}' — "
            f"must contain 'ecommerce-platform' namespace"
        )

    # ── Criterion 5: inventory-db Service port must be 5432 ──────────────────
    inv = result.get("inventory_db", {})
    service_port = int(inv.get("service_port", 0))

    if service_port == 5432:
        score += 20
        feedback_parts.append(
            "C5 PASS: inventory-db Service port is 5432 (standard PostgreSQL port) (+20)"
        )
    else:
        feedback_parts.append(
            f"C5 FAIL: inventory-db Service port is {service_port} — must be 5432 (not 5433)"
        )

    passed = score >= PASS_THRESHOLD
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }
