#!/bin/bash
echo "=== Exporting Full-Stack Containerization Results ==="

PROJECT_DIR="/home/ga/projects/acme-inventory"
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULT_FILE="/tmp/fullstack_result.json"

# ---- Helper functions ----
check_file() {
    if [ -f "$1" ]; then echo "true"; else echo "false"; fi
}

# ---- 1. File Existence Checks ----
HAS_API_DOCKERFILE=$(check_file "$PROJECT_DIR/api/Dockerfile")
# Also check project root for Dockerfile
if [ "$HAS_API_DOCKERFILE" = "false" ]; then
    HAS_API_DOCKERFILE=$(check_file "$PROJECT_DIR/Dockerfile")
fi

HAS_WORKER_DOCKERFILE=$(check_file "$PROJECT_DIR/worker/Dockerfile")
HAS_COMPOSE=$(check_file "$PROJECT_DIR/docker-compose.yml")
# Also check docker-compose.yaml
if [ "$HAS_COMPOSE" = "false" ]; then
    HAS_COMPOSE=$(check_file "$PROJECT_DIR/docker-compose.yaml")
fi

HAS_NGINX_CONF="false"
if [ -f "$PROJECT_DIR/nginx/nginx.conf" ] || [ -f "$PROJECT_DIR/nginx/default.conf" ] || [ -f "$PROJECT_DIR/nginx.conf" ]; then
    HAS_NGINX_CONF="true"
fi

# ---- 2. Container Checks ----
ALL_CONTAINERS=$(docker ps --format '{{.Names}}' 2>/dev/null || echo "")
if [ -z "$ALL_CONTAINERS" ]; then
    RUNNING_COUNT=0
else
    RUNNING_COUNT=$(echo "$ALL_CONTAINERS" | wc -l)
fi

HAS_DB_CONTAINER="false"
HAS_API_CONTAINER="false"
HAS_REDIS_CONTAINER="false"
HAS_WORKER_CONTAINER="false"
HAS_NGINX_CONTAINER="false"

if echo "$ALL_CONTAINERS" | grep -qiE "db|postgres|database"; then HAS_DB_CONTAINER="true"; fi
if echo "$ALL_CONTAINERS" | grep -qiE "api|app|flask|web"; then HAS_API_CONTAINER="true"; fi
if echo "$ALL_CONTAINERS" | grep -qiE "redis|cache|broker"; then HAS_REDIS_CONTAINER="true"; fi
if echo "$ALL_CONTAINERS" | grep -qiE "worker|celery"; then HAS_WORKER_CONTAINER="true"; fi
if echo "$ALL_CONTAINERS" | grep -qiE "nginx|proxy"; then HAS_NGINX_CONTAINER="true"; fi

# Count matching services
SERVICE_COUNT=0
[ "$HAS_DB_CONTAINER" = "true" ] && SERVICE_COUNT=$((SERVICE_COUNT + 1))
[ "$HAS_API_CONTAINER" = "true" ] && SERVICE_COUNT=$((SERVICE_COUNT + 1))
[ "$HAS_REDIS_CONTAINER" = "true" ] && SERVICE_COUNT=$((SERVICE_COUNT + 1))
[ "$HAS_WORKER_CONTAINER" = "true" ] && SERVICE_COUNT=$((SERVICE_COUNT + 1))
[ "$HAS_NGINX_CONTAINER" = "true" ] && SERVICE_COUNT=$((SERVICE_COUNT + 1))

# ---- 3. API Endpoint Checks ----
echo "Waiting for services to settle..."
sleep 5

# Products endpoint
PRODUCTS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/products 2>/dev/null)
PRODUCTS_CODE=${PRODUCTS_CODE:-000}
PRODUCTS_BODY=$(curl -s http://localhost:8080/api/products 2>/dev/null || echo "")
PRODUCTS_COUNT=0
if [ "$PRODUCTS_CODE" = "200" ]; then
    PRODUCTS_COUNT=$(echo "$PRODUCTS_BODY" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "0")
fi

# Inventory endpoint
INVENTORY_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/inventory 2>/dev/null)
INVENTORY_CODE=${INVENTORY_CODE:-000}
INVENTORY_BODY=$(curl -s http://localhost:8080/api/inventory 2>/dev/null || echo "")
INVENTORY_COUNT=0
WAREHOUSE_NAMES=""
if [ "$INVENTORY_CODE" = "200" ]; then
    INVENTORY_COUNT=$(echo "$INVENTORY_BODY" | python3 -c "import sys,json; data=json.load(sys.stdin); print(len(data))" 2>/dev/null || echo "0")
    WAREHOUSE_NAMES=$(echo "$INVENTORY_BODY" | python3 -c "
import sys, json
data = json.load(sys.stdin)
names = set()
for e in data:
    wn = e.get('warehouse_name', '')
    if wn: names.add(wn)
print(','.join(sorted(names)))
" 2>/dev/null || echo "")
fi

# Get initial inventory for product 1, warehouse 1 BEFORE test order
INITIAL_INV_P1W1=0
if [ "$INVENTORY_CODE" = "200" ]; then
    INITIAL_INV_P1W1=$(echo "$INVENTORY_BODY" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for e in data:
    if e.get('product_id') == 1 and e.get('warehouse_id') == 1:
        print(e.get('quantity', 0))
        break
else:
    print(0)
" 2>/dev/null || echo "0")
fi

# ---- 4. Order Creation Test ----
# Create a test order to verify the full async pipeline
ORDER_CREATE_CODE="000"
ORDER_ID="0"
ORDER_CREATE_CODE=$(curl -s -o /tmp/order_response.json -w "%{http_code}" \
    -X POST http://localhost:8080/api/orders \
    -H "Content-Type: application/json" \
    -d '{"product_id": 1, "quantity": 2, "warehouse_id": 1}' 2>/dev/null)
ORDER_CREATE_CODE=${ORDER_CREATE_CODE:-000}

if [ "$ORDER_CREATE_CODE" = "201" ]; then
    ORDER_ID=$(python3 -c "import json; print(json.load(open('/tmp/order_response.json')).get('order_id', 0))" 2>/dev/null || echo "0")
fi

# Wait for worker to process the order
echo "Waiting for worker to process order..."
sleep 8

# Check order status after processing
ORDER_STATUS="unknown"
ORDERS_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/orders 2>/dev/null)
ORDERS_CODE=${ORDERS_CODE:-000}
ORDERS_BODY=$(curl -s http://localhost:8080/api/orders 2>/dev/null || echo "[]")
if [ "$ORDERS_CODE" = "200" ] && [ "$ORDER_ID" != "0" ]; then
    ORDER_STATUS=$(echo "$ORDERS_BODY" | python3 -c "
import sys, json
data = json.load(sys.stdin)
oid = $ORDER_ID
for o in data:
    if o.get('id') == oid:
        print(o.get('status', 'unknown'))
        break
else:
    print('not_found')
" 2>/dev/null || echo "unknown")
fi

# Check inventory after order processing (should be decremented by 2)
FINAL_INV_P1W1=0
FINAL_INVENTORY_BODY=$(curl -s http://localhost:8080/api/inventory 2>/dev/null || echo "")
if [ -n "$FINAL_INVENTORY_BODY" ]; then
    FINAL_INV_P1W1=$(echo "$FINAL_INVENTORY_BODY" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for e in data:
    if e.get('product_id') == 1 and e.get('warehouse_id') == 1:
        print(e.get('quantity', 0))
        break
else:
    print(0)
" 2>/dev/null || echo "0")
fi

INVENTORY_DECREMENTED="false"
if [ "$INITIAL_INV_P1W1" != "0" ] && [ "$FINAL_INV_P1W1" != "0" ]; then
    EXPECTED=$((INITIAL_INV_P1W1 - 2))
    if [ "$FINAL_INV_P1W1" = "$EXPECTED" ]; then
        INVENTORY_DECREMENTED="true"
    fi
fi

# ---- 5. Database Direct Check ----
DB_PRODUCT_COUNT=0
DB_WAREHOUSE_COUNT=0
DB_ID=$(docker ps -q --filter "ancestor=postgres:14" 2>/dev/null | head -n 1)
if [ -z "$DB_ID" ]; then
    DB_ID=$(docker ps -q --filter "ancestor=postgres:15" 2>/dev/null | head -n 1)
fi
if [ -z "$DB_ID" ]; then
    DB_ID=$(docker ps -q --filter "ancestor=postgres" 2>/dev/null | head -n 1)
fi
if [ -n "$DB_ID" ]; then
    DB_PRODUCT_COUNT=$(docker exec "$DB_ID" psql -U acme -d acme_inventory -t -c "SELECT COUNT(*) FROM product;" 2>/dev/null | tr -d '[:space:]' || echo "0")
    if [ "$DB_PRODUCT_COUNT" = "0" ] || [ -z "$DB_PRODUCT_COUNT" ]; then
        DB_PRODUCT_COUNT=$(docker exec "$DB_ID" psql -U postgres -t -c "SELECT COUNT(*) FROM product;" 2>/dev/null | tr -d '[:space:]' || echo "0")
    fi
    DB_WAREHOUSE_COUNT=$(docker exec "$DB_ID" psql -U acme -d acme_inventory -t -c "SELECT COUNT(*) FROM warehouse;" 2>/dev/null | tr -d '[:space:]' || echo "0")
    if [ "$DB_WAREHOUSE_COUNT" = "0" ] || [ -z "$DB_WAREHOUSE_COUNT" ]; then
        DB_WAREHOUSE_COUNT=$(docker exec "$DB_ID" psql -U postgres -t -c "SELECT COUNT(*) FROM warehouse;" 2>/dev/null | tr -d '[:space:]' || echo "0")
    fi
fi

# ---- 6. Health Check ----
HEALTH_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/health 2>/dev/null)
HEALTH_CODE=${HEALTH_CODE:-000}

# ---- 7. Final Screenshot ----
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ---- 8. Write Result JSON ----
cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "has_api_dockerfile": $HAS_API_DOCKERFILE,
    "has_worker_dockerfile": $HAS_WORKER_DOCKERFILE,
    "has_compose": $HAS_COMPOSE,
    "has_nginx_conf": $HAS_NGINX_CONF,
    "running_containers_count": $RUNNING_COUNT,
    "service_count": $SERVICE_COUNT,
    "has_db_container": $HAS_DB_CONTAINER,
    "has_api_container": $HAS_API_CONTAINER,
    "has_redis_container": $HAS_REDIS_CONTAINER,
    "has_worker_container": $HAS_WORKER_CONTAINER,
    "has_nginx_container": $HAS_NGINX_CONTAINER,
    "products_http_code": "$PRODUCTS_CODE",
    "products_count": $PRODUCTS_COUNT,
    "inventory_http_code": "$INVENTORY_CODE",
    "inventory_count": $INVENTORY_COUNT,
    "warehouse_names": "$WAREHOUSE_NAMES",
    "order_create_http_code": "$ORDER_CREATE_CODE",
    "order_id": $ORDER_ID,
    "order_status": "$ORDER_STATUS",
    "orders_http_code": "$ORDERS_CODE",
    "initial_inventory_p1w1": $INITIAL_INV_P1W1,
    "final_inventory_p1w1": $FINAL_INV_P1W1,
    "inventory_decremented": $INVENTORY_DECREMENTED,
    "db_product_count": "$DB_PRODUCT_COUNT",
    "db_warehouse_count": "$DB_WAREHOUSE_COUNT",
    "health_http_code": "$HEALTH_CODE",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Copy and set permissions
cp "$RESULT_FILE" /tmp/task_result.json 2>/dev/null || true
chmod 666 "$RESULT_FILE" 2>/dev/null || true
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat "$RESULT_FILE"
