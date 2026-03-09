#!/bin/bash
echo "=== Exporting Multi-Module Refactor Result ==="
source /workspace/scripts/task_utils.sh

take_screenshot /tmp/multimodule_final_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TARGET_DIR="/home/ga/ecommerce-refactored"

# ---- Parent POM check ----
PARENT_POM_EXISTS="false"
PARENT_HAS_MODULES="false"
MODULE_COUNT=0
if [ -f "$TARGET_DIR/pom.xml" ]; then
    PARENT_POM_EXISTS="true"
    MODULE_COUNT=$(grep -c "<module>" "$TARGET_DIR/pom.xml" 2>/dev/null || echo "0")
    if [ "$MODULE_COUNT" -ge 3 ]; then
        PARENT_HAS_MODULES="true"
    fi
fi

# ---- Child module pom.xml checks ----
API_POM="false"
PERSISTENCE_POM="false"
SERVICE_POM="false"
[ -f "$TARGET_DIR/ecommerce-api/pom.xml" ] && API_POM="true"
[ -f "$TARGET_DIR/ecommerce-persistence/pom.xml" ] && PERSISTENCE_POM="true"
[ -f "$TARGET_DIR/ecommerce-service/pom.xml" ] && SERVICE_POM="true"

# ---- Class existence checks ----
API_PRODUCT=$(find "$TARGET_DIR/ecommerce-api/src" -name "Product.java" 2>/dev/null | wc -l)
API_CUSTOMER=$(find "$TARGET_DIR/ecommerce-api/src" -name "Customer.java" 2>/dev/null | wc -l)
API_ORDER=$(find "$TARGET_DIR/ecommerce-api/src" -name "Order.java" 2>/dev/null | wc -l)

PERS_PRODUCT_REPO=$(find "$TARGET_DIR/ecommerce-persistence/src" -name "ProductRepository.java" 2>/dev/null | wc -l)
PERS_CUSTOMER_REPO=$(find "$TARGET_DIR/ecommerce-persistence/src" -name "CustomerRepository.java" 2>/dev/null | wc -l)
PERS_ORDER_REPO=$(find "$TARGET_DIR/ecommerce-persistence/src" -name "OrderRepository.java" 2>/dev/null | wc -l)

SVC_PRODUCT=$(find "$TARGET_DIR/ecommerce-service/src" -name "ProductService.java" 2>/dev/null | wc -l)
SVC_CUSTOMER=$(find "$TARGET_DIR/ecommerce-service/src" -name "CustomerService.java" 2>/dev/null | wc -l)
SVC_ORDER=$(find "$TARGET_DIR/ecommerce-service/src" -name "OrderService.java" 2>/dev/null | wc -l)

# ---- Inter-module dependency checks ----
PERS_DEPENDS_API="false"
SVC_DEPENDS_API="false"
SVC_DEPENDS_PERS="false"
if [ -f "$TARGET_DIR/ecommerce-persistence/pom.xml" ]; then
    grep -q "ecommerce-api" "$TARGET_DIR/ecommerce-persistence/pom.xml" && PERS_DEPENDS_API="true"
fi
if [ -f "$TARGET_DIR/ecommerce-service/pom.xml" ]; then
    grep -q "ecommerce-api" "$TARGET_DIR/ecommerce-service/pom.xml" && SVC_DEPENDS_API="true"
    grep -q "ecommerce-persistence" "$TARGET_DIR/ecommerce-service/pom.xml" && SVC_DEPENDS_PERS="true"
fi

# ---- Build check ----
BUILD_SUCCESS="false"
BUILD_EXIT=1
if [ -d "$TARGET_DIR" ] && [ -f "$TARGET_DIR/pom.xml" ]; then
    cd "$TARGET_DIR"
    mvn clean install -q --no-transfer-progress 2>/tmp/mvn_multimodule_output.txt
    BUILD_EXIT=$?
    [ $BUILD_EXIT -eq 0 ] && BUILD_SUCCESS="true"
fi

cat > /tmp/multimodule_result.json << EOF
{
  "task_start": $TASK_START,
  "parent_pom_exists": $PARENT_POM_EXISTS,
  "parent_has_modules": $PARENT_HAS_MODULES,
  "module_count": $MODULE_COUNT,
  "api_pom": $API_POM,
  "persistence_pom": $PERSISTENCE_POM,
  "service_pom": $SERVICE_POM,
  "api_product_class": $API_PRODUCT,
  "api_customer_class": $API_CUSTOMER,
  "api_order_class": $API_ORDER,
  "persistence_product_repo": $PERS_PRODUCT_REPO,
  "persistence_customer_repo": $PERS_CUSTOMER_REPO,
  "persistence_order_repo": $PERS_ORDER_REPO,
  "service_product_svc": $SVC_PRODUCT,
  "service_customer_svc": $SVC_CUSTOMER,
  "service_order_svc": $SVC_ORDER,
  "persistence_depends_api": $PERS_DEPENDS_API,
  "service_depends_api": $SVC_DEPENDS_API,
  "service_depends_persistence": $SVC_DEPENDS_PERS,
  "build_success": $BUILD_SUCCESS,
  "build_exit_code": $BUILD_EXIT
}
EOF

echo "Result saved to /tmp/multimodule_result.json"
cat /tmp/multimodule_result.json

echo "=== Export Complete ==="
