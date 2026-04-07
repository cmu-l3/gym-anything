#!/bin/bash
echo "=== Exporting Disaster Recovery Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Service Status
DB_RUNNING=$(docker ps --format '{{.Names}}' | grep -q "acme-db" && echo "true" || echo "false")
CACHE_RUNNING=$(docker ps --format '{{.Names}}' | grep -q "acme-cache" && echo "true" || echo "false")
WEB_RUNNING=$(docker ps --format '{{.Names}}' | grep -q "acme-web" && echo "true" || echo "false")
WEB_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/api/health 2>/dev/null || echo "000")

# 2. Check Data Integrity
CUSTOMER_COUNT=$(docker exec acme-db psql -U pagila -d pagila -t -c "SELECT COUNT(*) FROM customer;" 2>/dev/null | xargs || echo "0")
FILM_COUNT=$(docker exec acme-db psql -U pagila -d pagila -t -c "SELECT COUNT(*) FROM film;" 2>/dev/null | xargs || echo "0")
RENTAL_COUNT=$(docker exec acme-db psql -U pagila -d pagila -t -c "SELECT COUNT(*) FROM rental;" 2>/dev/null | xargs || echo "0")
REDIS_KEYS=$(docker exec acme-cache redis-cli keys "session:*" 2>/dev/null | wc -l || echo "0")

# 3. Verify Destruction (Anti-Gaming)
# We check if the current volumes were created AFTER the task start time.
PG_VOL_CREATED=$(docker volume inspect acme-pgdata --format '{{.CreatedAt}}' 2>/dev/null || echo "")
REDIS_VOL_CREATED=$(docker volume inspect acme-redisdata --format '{{.CreatedAt}}' 2>/dev/null || echo "")

# Convert ISO 8601 to epoch
PG_VOL_EPOCH=$(date -d "$PG_VOL_CREATED" +%s 2>/dev/null || echo "0")
REDIS_VOL_EPOCH=$(date -d "$REDIS_VOL_CREATED" +%s 2>/dev/null || echo "0")

VOLUMES_DESTROYED="false"
if [ "$PG_VOL_EPOCH" -gt "$TASK_START" ] && [ "$REDIS_VOL_EPOCH" -gt "$TASK_START" ]; then
    VOLUMES_DESTROYED="true"
fi

# 4. Check Artifacts
BACKUP_SQL_EXISTS=$([ -f /home/ga/backups/acme-db.sql ] && echo "true" || echo "false")
BACKUP_RDB_EXISTS=$([ -f /home/ga/backups/acme-cache.rdb ] && echo "true" || echo "false")
BACKUP_COMPOSE_EXISTS=$([ -f /home/ga/backups/docker-compose.yml ] && echo "true" || echo "false")
RUNBOOK_EXISTS=$([ -f /home/ga/Desktop/recovery_runbook.md ] && echo "true" || echo "false")

RUNBOOK_CONTENT=""
if [ "$RUNBOOK_EXISTS" = "true" ]; then
    RUNBOOK_CONTENT=$(cat /home/ga/Desktop/recovery_runbook.md | head -c 2000)
fi

# 5. Screenshot
take_screenshot /tmp/task_final.png

# 6. JSON Export
cat > /tmp/task_result.json << EOF
{
    "task_start_ts": $TASK_START,
    "pg_vol_created_ts": $PG_VOL_EPOCH,
    "redis_vol_created_ts": $REDIS_VOL_EPOCH,
    "volumes_destroyed_recreated": $VOLUMES_DESTROYED,
    "db_running": $DB_RUNNING,
    "cache_running": $CACHE_RUNNING,
    "web_running": $WEB_RUNNING,
    "web_response_code": "$WEB_RESPONSE",
    "customer_count": $CUSTOMER_COUNT,
    "film_count": $FILM_COUNT,
    "rental_count": $RENTAL_COUNT,
    "redis_key_count": $REDIS_KEYS,
    "backup_sql_exists": $BACKUP_SQL_EXISTS,
    "backup_rdb_exists": $BACKUP_RDB_EXISTS,
    "backup_compose_exists": $BACKUP_COMPOSE_EXISTS,
    "runbook_exists": $RUNBOOK_EXISTS,
    "runbook_length": $(echo "$RUNBOOK_CONTENT" | wc -c),
    "runbook_content": $(echo "$RUNBOOK_CONTENT" | jq -R .)
}
EOF

# Safe copy
cp /tmp/task_result.json /tmp/dr_result.json
chmod 666 /tmp/dr_result.json

echo "Results exported to /tmp/dr_result.json"
cat /tmp/dr_result.json
echo "=== Export Complete ==="