#!/bin/bash
echo "=== Exporting Concurrent Inventory Bug Fix Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/concurrent_inv_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_CONCURRENT=$(cat /tmp/initial_concurrent_count 2>/dev/null || echo "0")
INITIAL_TEST_COUNT=$(cat /tmp/initial_test_count 2>/dev/null || echo "0")

PROJECT_DIR="/home/ga/inventory-service"

# ---- Concurrent primitives usage ----
ATOMIC_INTEGER_COUNT=$(grep -r "AtomicInteger\|AtomicLong" "$PROJECT_DIR/src/main/java/" 2>/dev/null | wc -l)
CONCURRENT_HASHMAP_COUNT=$(grep -r "ConcurrentHashMap" "$PROJECT_DIR/src/main/java/" 2>/dev/null | wc -l)
SYNCHRONIZED_COUNT=$(grep -r "synchronized\|ReentrantLock\|ReadWriteLock" "$PROJECT_DIR/src/main/java/" 2>/dev/null | wc -l)
TOTAL_CONCURRENT=$(grep -r "java\.util\.concurrent\|AtomicInteger\|ConcurrentHashMap\|synchronized\|ReentrantLock" \
    "$PROJECT_DIR/src/main/java/" 2>/dev/null | wc -l)

# ---- Per-class fix checks ----
STOCK_COUNTER_FIXED=$(grep -l "AtomicInteger\|synchronized" "$PROJECT_DIR/src/main/java/com/example/inventory/StockCounter.java" 2>/dev/null | wc -l)
PRODUCT_CATALOG_FIXED=$(grep -l "ConcurrentHashMap" "$PROJECT_DIR/src/main/java/com/example/inventory/ProductCatalog.java" 2>/dev/null | wc -l)
INVENTORY_MGR_FIXED=$(grep -l "ConcurrentHashMap\|synchronized\|compute\|computeIfPresent" "$PROJECT_DIR/src/main/java/com/example/inventory/InventoryManager.java" 2>/dev/null | wc -l)
RESERVATION_SVC_FIXED=$(grep -l "synchronized\|ReentrantLock\|Lock" "$PROJECT_DIR/src/main/java/com/example/inventory/ReservationService.java" 2>/dev/null | wc -l)

# ---- Test files ----
CURRENT_TEST_COUNT=$(find "$PROJECT_DIR/src/test" -name "*.java" 2>/dev/null | wc -l)
NEW_TEST_COUNT=$((CURRENT_TEST_COUNT - INITIAL_TEST_COUNT))

# ---- Concurrent test patterns ----
CONCURRENT_TEST_PATTERNS=$(grep -r "ExecutorService\|CountDownLatch\|Thread\|Callable\|Future\|CyclicBarrier" \
    "$PROJECT_DIR/src/test/" 2>/dev/null | wc -l)

# ---- Build ----
BUILD_SUCCESS="false"
BUILD_EXIT=1
if [ -d "$PROJECT_DIR" ]; then
    cd "$PROJECT_DIR"
    mvn clean test -q --no-transfer-progress 2>/tmp/mvn_concurrent_output.txt
    BUILD_EXIT=$?
    [ $BUILD_EXIT -eq 0 ] && BUILD_SUCCESS="true"
fi

# ---- Atomic remove check (more specific) ----
ATOMIC_REMOVE=$(grep -c "compute\|computeIfPresent\|getAndUpdate\|updateAndGet" \
    "$PROJECT_DIR/src/main/java/com/example/inventory/InventoryManager.java" 2>/dev/null || echo "0")

cat > /tmp/concurrent_inv_result.json << EOF
{
  "task_start": $TASK_START,
  "initial_concurrent_count": $INITIAL_CONCURRENT,
  "atomic_integer_count": $ATOMIC_INTEGER_COUNT,
  "concurrent_hashmap_count": $CONCURRENT_HASHMAP_COUNT,
  "synchronized_count": $SYNCHRONIZED_COUNT,
  "total_concurrent_count": $TOTAL_CONCURRENT,
  "stock_counter_fixed": $STOCK_COUNTER_FIXED,
  "product_catalog_fixed": $PRODUCT_CATALOG_FIXED,
  "inventory_manager_fixed": $INVENTORY_MGR_FIXED,
  "reservation_service_fixed": $RESERVATION_SVC_FIXED,
  "initial_test_count": $INITIAL_TEST_COUNT,
  "current_test_count": $CURRENT_TEST_COUNT,
  "new_test_count": $NEW_TEST_COUNT,
  "concurrent_test_patterns": $CONCURRENT_TEST_PATTERNS,
  "atomic_remove_count": $ATOMIC_REMOVE,
  "build_success": $BUILD_SUCCESS,
  "build_exit_code": $BUILD_EXIT
}
EOF

echo "Result saved to /tmp/concurrent_inv_result.json"
cat /tmp/concurrent_inv_result.json

echo "=== Export Complete ==="
