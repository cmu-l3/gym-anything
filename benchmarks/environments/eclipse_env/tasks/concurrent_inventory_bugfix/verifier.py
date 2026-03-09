import json
import os
import logging
import tempfile

logger = logging.getLogger(__name__)


def verify_concurrent_inventory_bugfix(traj, env_info, task_info):
    """
    Verify the concurrent inventory bug fix task.

    Scoring breakdown (100 pts total, pass >= 70):
    - GATE: No java.util.concurrent usage at all → score=0
    - All four concurrent primitives present (30 pts)
    - StockCounter uses AtomicInteger/synchronized (10 pts)
    - ProductCatalog uses ConcurrentHashMap (10 pts)
    - InventoryManager uses ConcurrentHashMap + atomic removeStock (10 pts)
    - ReservationService synchronized (10 pts)
    - Concurrent tests added (20 pts)
    - Build + tests pass (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')

    score = 0
    feedback_parts = []
    subscores = {}

    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix='.json', delete=False) as tmp:
            tmp_path = tmp.name
        copy_from_env('/tmp/concurrent_inv_result.json', tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_path)
    except Exception as e:
        logger.warning(f"Could not read result JSON: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result: {e}",
            "subscores": {}
        }

    initial_concurrent = int(result.get('initial_concurrent_count', 0))
    total_concurrent = int(result.get('total_concurrent_count', 0))
    new_concurrent = total_concurrent - initial_concurrent

    # --- GATE: No concurrent usage at all → score=0 ---
    if new_concurrent == 0:
        return {
            "passed": False,
            "score": 0,
            "feedback": "CRITICAL: No java.util.concurrent primitives added to main source (score=0)",
            "subscores": {"concurrent_gate": False}
        }

    subscores['concurrent_gate'] = True

    # --- Criterion 1: All four concurrent primitives (30 pts) ---
    atomic_count = int(result.get('atomic_integer_count', 0))
    chm_count = int(result.get('concurrent_hashmap_count', 0))
    sync_count = int(result.get('synchronized_count', 0))

    primitives_used = sum([atomic_count > 0, chm_count > 0, sync_count > 0])
    if primitives_used >= 3:
        score += 30
        subscores['concurrent_primitives'] = True
        feedback_parts.append(f"All required concurrent primitives used (30/30)")
    elif primitives_used >= 2:
        score += 20
        subscores['concurrent_primitives'] = 'partial'
        feedback_parts.append(f"{primitives_used}/3 concurrent primitive types used (20/30)")
    elif primitives_used >= 1:
        score += 10
        subscores['concurrent_primitives'] = 'partial'
        feedback_parts.append(f"Only {primitives_used}/3 concurrent primitive types used (10/30)")
    else:
        subscores['concurrent_primitives'] = False
        feedback_parts.append("No recognized concurrent primitives found (0/30)")

    # --- Criterion 2: StockCounter fixed (10 pts) ---
    sc_fixed = int(result.get('stock_counter_fixed', 0)) > 0
    if sc_fixed:
        score += 10
        subscores['stock_counter_fixed'] = True
        feedback_parts.append("StockCounter fixed with AtomicInteger/synchronized (10/10)")
    else:
        subscores['stock_counter_fixed'] = False
        feedback_parts.append("StockCounter NOT fixed — still using plain int (0/10)")

    # --- Criterion 3: ProductCatalog fixed (10 pts) ---
    pc_fixed = int(result.get('product_catalog_fixed', 0)) > 0
    if pc_fixed:
        score += 10
        subscores['product_catalog_fixed'] = True
        feedback_parts.append("ProductCatalog fixed with ConcurrentHashMap (10/10)")
    else:
        subscores['product_catalog_fixed'] = False
        feedback_parts.append("ProductCatalog NOT fixed — still using HashMap (0/10)")

    # --- Criterion 4: InventoryManager fixed (10 pts) ---
    im_fixed = int(result.get('inventory_manager_fixed', 0)) > 0
    if im_fixed:
        score += 10
        subscores['inventory_manager_fixed'] = True
        feedback_parts.append("InventoryManager fixed (10/10)")
    else:
        subscores['inventory_manager_fixed'] = False
        feedback_parts.append("InventoryManager NOT fixed (0/10)")

    # --- Criterion 5: ReservationService fixed (10 pts) ---
    rs_fixed = int(result.get('reservation_service_fixed', 0)) > 0
    if rs_fixed:
        score += 10
        subscores['reservation_service_fixed'] = True
        feedback_parts.append("ReservationService synchronized (10/10)")
    else:
        subscores['reservation_service_fixed'] = False
        feedback_parts.append("ReservationService NOT synchronized (0/10)")

    # --- Criterion 6: Concurrent tests (20 pts) ---
    new_test_count = int(result.get('new_test_count', 0))
    concurrent_patterns = int(result.get('concurrent_test_patterns', 0))

    if concurrent_patterns >= 5 and new_test_count >= 1:
        score += 20
        subscores['concurrent_tests'] = True
        feedback_parts.append(f"Concurrent tests added with ExecutorService/Thread patterns (20/20)")
    elif concurrent_patterns >= 2:
        score += 10
        subscores['concurrent_tests'] = 'partial'
        feedback_parts.append(f"Some concurrent test patterns found ({concurrent_patterns}) (10/20)")
    elif new_test_count >= 1:
        score += 5
        subscores['concurrent_tests'] = 'partial'
        feedback_parts.append(f"New test file added but lacks concurrent execution patterns (5/20)")
    else:
        subscores['concurrent_tests'] = False
        feedback_parts.append("No concurrent tests added (0/20)")

    # --- Criterion 7: Build passes (10 pts) ---
    build_success = result.get('build_success', False)
    if build_success:
        score += 10
        subscores['build_passes'] = True
        feedback_parts.append("Build passes: mvn clean test succeeded (10/10)")
    else:
        subscores['build_passes'] = False
        feedback_parts.append("Build FAILED (0/10)")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
