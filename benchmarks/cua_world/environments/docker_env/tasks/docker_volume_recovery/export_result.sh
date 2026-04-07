#!/bin/bash
# Export script for docker_volume_recovery

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
PROJECT_DIR="/home/ga/projects/acme-musicstore"

# 1. Container Status
DB_RUNNING=$(docker ps --format '{{.Names}}' | grep -c "acme-db")
REDIS_RUNNING=$(docker ps --format '{{.Names}}' | grep -c "acme-cache")
APP_RUNNING=$(docker ps --format '{{.Names}}' | grep -c "acme-app")

# 2. Database Content Verification
# Wait for DB to be ready if running
DB_TRACKS=0
DB_ARTISTS=0
DB_ALBUMS=0

if [ "$DB_RUNNING" -eq 1 ]; then
    # Give it a moment if it just started
    sleep 2
    DB_TRACKS=$(docker exec acme-db psql -U acme -d chinook -t -c 'SELECT COUNT(*) FROM "Track";' 2>/dev/null | tr -d '[:space:]' || echo "0")
    DB_ARTISTS=$(docker exec acme-db psql -U acme -d chinook -t -c 'SELECT COUNT(*) FROM "Artist";' 2>/dev/null | tr -d '[:space:]' || echo "0")
    DB_ALBUMS=$(docker exec acme-db psql -U acme -d chinook -t -c 'SELECT COUNT(*) FROM "Album";' 2>/dev/null | tr -d '[:space:]' || echo "0")
fi

# 3. Redis Content Verification
REDIS_KEYS=0
if [ "$REDIS_RUNNING" -eq 1 ]; then
    REDIS_KEYS=$(docker exec acme-cache redis-cli dbsize 2>/dev/null | tr -d '[:space:]' || echo "0")
fi

# 4. API End-to-End Verification
API_STATUS=0
API_JSON=""
if curl -s -f "http://localhost:5000/api/stats" > /tmp/api_response.json; then
    API_STATUS=200
    API_JSON=$(cat /tmp/api_response.json)
fi

# 5. Backup Script Verification
BACKUP_SCRIPT_EXISTS=0
BACKUP_SCRIPT_EXECUTABLE=0
BACKUP_GENERATED_SQL=0
BACKUP_GENERATED_REDIS=0

if [ -f "$PROJECT_DIR/backup.sh" ]; then
    BACKUP_SCRIPT_EXISTS=1
    if [ -x "$PROJECT_DIR/backup.sh" ]; then
        BACKUP_SCRIPT_EXECUTABLE=1
        
        # Run the backup script to test it
        echo "Testing user backup script..."
        cd "$PROJECT_DIR"
        # Run as ga user
        if su - ga -c "cd $PROJECT_DIR && ./backup.sh"; then
            echo "Backup script executed successfully."
        else
            echo "Backup script returned error."
        fi
        
        # Check for output in backups/latest (or where they put it, checking likely locations)
        # Task said "backups/latest/"
        LATEST_DIR="$PROJECT_DIR/backups/latest"
        if [ -d "$LATEST_DIR" ]; then
            # Check for SQL file
            SQL_FILE=$(find "$LATEST_DIR" -name "*.sql" -type f | head -1)
            if [ -n "$SQL_FILE" ] && [ -s "$SQL_FILE" ]; then
                # Check if it looks like a dump (contains CREATE or INSERT)
                if grep -qE "CREATE|INSERT|COPY" "$SQL_FILE"; then
                    BACKUP_GENERATED_SQL=1
                fi
            fi
            
            # Check for Redis file (rdb or json or txt)
            REDIS_FILE=$(find "$LATEST_DIR" -name "*.rdb" -o -name "*.json" -o -name "*.txt" -type f | grep -v "chinook" | head -1)
            if [ -n "$REDIS_FILE" ] && [ -s "$REDIS_FILE" ]; then
                BACKUP_GENERATED_REDIS=1
            fi
        fi
    fi
fi

# 6. JSON Export
cat > /tmp/volume_recovery_result.json <<EOF
{
    "task_start": $TASK_START,
    "containers": {
        "db": $DB_RUNNING,
        "redis": $REDIS_RUNNING,
        "app": $APP_RUNNING
    },
    "postgres": {
        "tracks": "$DB_TRACKS",
        "artists": "$DB_ARTISTS",
        "albums": "$DB_ALBUMS"
    },
    "redis": {
        "keys": "$REDIS_KEYS"
    },
    "api": {
        "status": $API_STATUS,
        "response": $(cat /tmp/api_response.json 2>/dev/null || echo "{}")
    },
    "backup_script": {
        "exists": $BACKUP_SCRIPT_EXISTS,
        "executable": $BACKUP_SCRIPT_EXECUTABLE,
        "generated_sql": $BACKUP_GENERATED_SQL,
        "generated_redis": $BACKUP_GENERATED_REDIS
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/volume_recovery_result.json"
cat /tmp/volume_recovery_result.json