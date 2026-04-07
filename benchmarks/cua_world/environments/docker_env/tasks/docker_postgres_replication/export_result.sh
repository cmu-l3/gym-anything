#!/bin/bash
echo "=== Exporting PostgreSQL Replication Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Capture final state
take_screenshot /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
DB_PASS="password123"

# 1. Check Containers Existence & Status
PRIMARY_RUNNING=0
REPLICA_RUNNING=0

if docker ps --format '{{.Names}}' | grep -q "^primary$"; then PRIMARY_RUNNING=1; fi
if docker ps --format '{{.Names}}' | grep -q "^replica$"; then REPLICA_RUNNING=1; fi

# 2. Check Replication Status on Primary
REPLICATION_ACTIVE=0
REPL_CLIENT_ADDR=""

if [ "$PRIMARY_RUNNING" = "1" ]; then
    # Query pg_stat_replication
    REPL_INFO=$(docker exec -e PGPASSWORD=$DB_PASS primary psql -U postgres -d postgres -t -c "SELECT client_addr, state FROM pg_stat_replication;" 2>/dev/null || echo "")
    if echo "$REPL_INFO" | grep -q "streaming"; then
        REPLICATION_ACTIVE=1
        REPL_CLIENT_ADDR=$(echo "$REPL_INFO" | grep "streaming" | awk '{print $1}')
    fi
fi

# 3. Check Initial Data Sync (Seed Data)
SEED_DATA_PRESENT=0
SEED_COUNT=0
if [ "$REPLICA_RUNNING" = "1" ]; then
    SEED_COUNT=$(docker exec -e PGPASSWORD=$DB_PASS replica psql -U postgres -d postgres -t -c "SELECT COUNT(*) FROM products;" 2>/dev/null | tr -d '[:space:]' || echo "0")
    # We expect 5 rows from seed.sql
    if [ "$SEED_COUNT" -ge "5" ]; then
        SEED_DATA_PRESENT=1
    fi
fi

# 4. Verify Real-Time Replication (The Canary Test)
CANARY_TOKEN="CANARY_$(date +%s)"
CANARY_REPLICATED=0
WRITE_SUCCESS=0

if [ "$PRIMARY_RUNNING" = "1" ] && [ "$REPLICA_RUNNING" = "1" ] && [ "$REPLICATION_ACTIVE" = "1" ]; then
    # Insert into Primary
    if docker exec -e PGPASSWORD=$DB_PASS primary psql -U postgres -d postgres -c "INSERT INTO products (name, price, stock) VALUES ('$CANARY_TOKEN', 999.99, 1);" > /dev/null 2>&1; then
        WRITE_SUCCESS=1
        
        # Wait for replication lag
        sleep 3
        
        # Check Replica
        FOUND_CANARY=$(docker exec -e PGPASSWORD=$DB_PASS replica psql -U postgres -d postgres -t -c "SELECT count(*) FROM products WHERE name='$CANARY_TOKEN';" 2>/dev/null | tr -d '[:space:]' || echo "0")
        if [ "$FOUND_CANARY" = "1" ]; then
            CANARY_REPLICATED=1
        fi
    fi
fi

# 5. Verify Read-Only Enforcement on Replica
READ_ONLY_ENFORCED=0
if [ "$REPLICA_RUNNING" = "1" ]; then
    # Attempt to write to replica - expect failure
    if ! docker exec -e PGPASSWORD=$DB_PASS replica psql -U postgres -d postgres -c "CREATE TABLE test_ro (id int);" > /dev/null 2>&1; then
        # Failed to write, which is good. Double check it was due to read-only transaction.
        ERR_MSG=$(docker exec -e PGPASSWORD=$DB_PASS replica psql -U postgres -d postgres -c "CREATE TABLE test_ro (id int);" 2>&1 || true)
        if echo "$ERR_MSG" | grep -qi "read-only transaction"; then
            READ_ONLY_ENFORCED=1
        fi
    else
        # Write succeeded - bad!
        docker exec -e PGPASSWORD=$DB_PASS replica psql -U postgres -d postgres -c "DROP TABLE test_ro;" > /dev/null 2>&1 || true
        READ_ONLY_ENFORCED=0
    fi
fi

# 6. Check Persistence (Volumes)
VOLUMES_EXIST=0
if docker volume inspect db-primary-data >/dev/null 2>&1 && docker volume inspect db-replica-data >/dev/null 2>&1; then
    VOLUMES_EXIST=1
fi

# Generate JSON Result
cat > /tmp/db_replication_result.json <<EOF
{
    "task_start": $TASK_START,
    "primary_running": $PRIMARY_RUNNING,
    "replica_running": $REPLICA_RUNNING,
    "replication_active": $REPLICATION_ACTIVE,
    "replication_client_addr": "$REPL_CLIENT_ADDR",
    "seed_data_count": $SEED_COUNT,
    "seed_data_present": $SEED_DATA_PRESENT,
    "canary_write_success": $WRITE_SUCCESS,
    "canary_replicated": $CANARY_REPLICATED,
    "read_only_enforced": $READ_ONLY_ENFORCED,
    "volumes_exist": $VOLUMES_EXIST,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result generated:"
cat /tmp/db_replication_result.json
echo "=== Export Complete ==="