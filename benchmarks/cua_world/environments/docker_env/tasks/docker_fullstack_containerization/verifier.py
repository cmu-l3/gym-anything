#!/usr/bin/env python3
"""
Verifier for docker_fullstack_containerization task.

Scoring is based on the exported result JSON from export_result.sh.
Full verification is supplemented by external VLM checklist evaluation.
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 70


def verify_docker_fullstack_containerization(traj, env_info, task_info):
    """
    Verify the full-stack containerization task.

    Scoring (100 points total, pass threshold 70):
      - Docker artifacts exist (Dockerfiles, compose, nginx.conf):  8 pts
      - All 5 containers running:                                  12 pts
      - GET /api/products returns 25 products (HTTP 200):          15 pts
      - GET /api/inventory returns warehouse data (HTTP 200):      12 pts
      - POST /api/orders creates order (HTTP 201):                 15 pts
      - GET /api/orders includes created order:                    10 pts
      - Worker processed order (status = completed):               13 pts
      - Inventory decremented correctly:                           15 pts

    Hard gate: POST->worker->inventory chain must work to pass.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        temp_file.close()
        # Try both result file paths
        try:
            copy_from_env("/tmp/fullstack_result.json", temp_file.name)
        except Exception:
            copy_from_env("/tmp/task_result.json", temp_file.name)

        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # ---- Criterion 1: Docker artifacts exist (8 pts) ----
    artifact_pts = 0
    if result.get('has_api_dockerfile', False):
        artifact_pts += 2
    if result.get('has_worker_dockerfile', False):
        artifact_pts += 2
    if result.get('has_compose', False):
        artifact_pts += 2
    if result.get('has_nginx_conf', False):
        artifact_pts += 2
    score += artifact_pts
    feedback.append(f"Docker artifacts: {artifact_pts}/8")

    # ---- Criterion 2: Containers running (12 pts) ----
    svc_count = int(result.get('service_count', 0))
    if svc_count >= 5:
        score += 12
        feedback.append("All 5 services running (+12)")
    elif svc_count >= 3:
        score += 7
        feedback.append(f"{svc_count} services running (+7)")
    elif svc_count >= 1:
        score += 3
        feedback.append(f"{svc_count} service(s) running (+3)")
    else:
        feedback.append("No services detected running")

    # ---- Criterion 3: Products endpoint (15 pts) ----
    products_ok = False
    if result.get('products_http_code') == '200':
        pcount = int(result.get('products_count', 0))
        if pcount == 25:
            score += 15
            products_ok = True
            feedback.append("GET /api/products: 25 products (+15)")
        elif pcount > 0:
            score += 8
            feedback.append(f"GET /api/products: {pcount} products (expected 25) (+8)")
        else:
            score += 3
            feedback.append("GET /api/products: 200 but empty (+3)")
    else:
        feedback.append(f"GET /api/products: HTTP {result.get('products_http_code', 'N/A')}")

    # ---- Criterion 4: Inventory endpoint (12 pts) ----
    if result.get('inventory_http_code') == '200':
        inv_count = int(result.get('inventory_count', 0))
        if inv_count >= 75:
            score += 12
            feedback.append("GET /api/inventory: full data (+12)")
        elif inv_count > 0:
            score += 6
            feedback.append(f"GET /api/inventory: {inv_count} entries (+6)")
        else:
            score += 2
            feedback.append("GET /api/inventory: 200 but empty (+2)")
    else:
        feedback.append(f"GET /api/inventory: HTTP {result.get('inventory_http_code', 'N/A')}")

    # ---- Criterion 5: Order creation (15 pts) ----
    order_created = False
    if result.get('order_create_http_code') == '201':
        score += 15
        order_created = True
        feedback.append("POST /api/orders: 201 Created (+15)")
    elif result.get('order_create_http_code') in ('200', '202'):
        score += 8
        order_created = True
        feedback.append(f"POST /api/orders: HTTP {result.get('order_create_http_code')} (+8)")
    else:
        feedback.append(f"POST /api/orders: HTTP {result.get('order_create_http_code', 'N/A')}")

    # ---- Criterion 6: Orders list (10 pts) ----
    if result.get('orders_http_code') == '200' and int(result.get('order_id', 0)) > 0:
        order_status = result.get('order_status', 'unknown')
        if order_status != 'not_found':
            score += 10
            feedback.append(f"GET /api/orders: order found, status={order_status} (+10)")
        else:
            score += 3
            feedback.append("GET /api/orders: 200 but order not found (+3)")
    else:
        feedback.append(f"GET /api/orders: HTTP {result.get('orders_http_code', 'N/A')}")

    # ---- Criterion 7: Worker processed order (13 pts) ----
    worker_ok = False
    order_status = result.get('order_status', 'unknown')
    if order_status == 'completed':
        score += 13
        worker_ok = True
        feedback.append("Worker: order status 'completed' (+13)")
    elif order_status == 'processing':
        score += 5
        feedback.append("Worker: order still 'processing' (+5)")
    elif order_status == 'pending':
        feedback.append("Worker: order still 'pending' (worker may not be connected)")
    else:
        feedback.append(f"Worker: order status '{order_status}'")

    # ---- Criterion 8: Inventory decremented (15 pts) ----
    inv_ok = False
    if result.get('inventory_decremented', False):
        score += 15
        inv_ok = True
        feedback.append("Inventory decremented correctly (+15)")
    else:
        initial = int(result.get('initial_inventory_p1w1', 0))
        final = int(result.get('final_inventory_p1w1', 0))
        if initial > 0 and final > 0 and final < initial:
            score += 8
            feedback.append(f"Inventory changed ({initial} -> {final}) but not exact (-2) (+8)")
        else:
            feedback.append(f"Inventory not decremented (initial={initial}, final={final})")

    # ---- Final verdict ----
    # Hard gate: the async pipeline (order creation + worker + inventory) must work
    pipeline_ok = order_created and worker_ok and inv_ok
    passed = score >= PASS_THRESHOLD and pipeline_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }
