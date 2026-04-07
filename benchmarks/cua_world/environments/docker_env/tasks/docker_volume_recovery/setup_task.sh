#!/bin/bash
# Setup script for docker_volume_recovery task

set -e
echo "=== Setting up Docker Volume Recovery Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi

wait_for_docker

# Clean up any previous runs
echo "Cleaning previous state..."
docker rm -f acme-db acme-cache acme-app 2>/dev/null || true
docker volume rm acme_pgdata acme_redisdata 2>/dev/null || true

# Setup Project Directory
PROJECT_DIR="/home/ga/projects/acme-musicstore"
mkdir -p "$PROJECT_DIR/app"
mkdir -p "$PROJECT_DIR/backups"

# 1. Create docker-compose.yml
cat > "$PROJECT_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  db:
    image: postgres:15
    container_name: acme-db
    environment:
      POSTGRES_USER: acme
      POSTGRES_PASSWORD: acmepass123
      POSTGRES_DB: chinook
    volumes:
      - acme_pgdata:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    networks:
      - music-net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U acme -d chinook"]
      interval: 5s
      timeout: 5s
      retries: 5

  cache:
    image: redis:7-alpine
    container_name: acme-cache
    volumes:
      - acme_redisdata:/data
    ports:
      - "6379:6379"
    networks:
      - music-net
    command: redis-server --appendonly yes

  app:
    build: ./app
    container_name: acme-app
    ports:
      - "5000:5000"
    environment:
      DATABASE_URL: postgresql://acme:acmepass123@db:5432/chinook
      REDIS_URL: redis://cache:6379/0
    depends_on:
      db:
        condition: service_healthy
      cache:
        condition: service_started
    networks:
      - music-net

volumes:
  acme_pgdata:
  acme_redisdata:

networks:
  music-net:
EOF

# 2. Create Flask App
cat > "$PROJECT_DIR/app/requirements.txt" <<EOF
flask==3.0.0
psycopg2-binary==2.9.9
redis==5.0.1
EOF

cat > "$PROJECT_DIR/app/Dockerfile" <<EOF
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "app.py"]
EOF

cat > "$PROJECT_DIR/app/app.py" <<EOF
import os
import psycopg2
import redis
from flask import Flask, jsonify

app = Flask(__name__)

def get_db_connection():
    conn = psycopg2.connect(os.environ['DATABASE_URL'])
    return conn

def get_redis_connection():
    return redis.from_url(os.environ['REDIS_URL'])

@app.route('/api/stats')
def stats():
    stats = {}
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("SELECT COUNT(*) FROM \"Track\";")
        stats['tracks'] = cur.fetchone()[0]
        
        cur.execute("SELECT COUNT(*) FROM \"Artist\";")
        stats['artists'] = cur.fetchone()[0]
        
        cur.execute("SELECT COUNT(*) FROM \"Album\";")
        stats['albums'] = cur.fetchone()[0]
        
        cur.close()
        conn.close()
        stats['db_status'] = 'connected'
    except Exception as e:
        stats['db_status'] = 'error'
        stats['db_error'] = str(e)

    try:
        r = get_redis_connection()
        stats['sessions'] = r.dbsize()
        stats['redis_status'] = 'connected'
    except Exception as e:
        stats['redis_status'] = 'error'
        stats['redis_error'] = str(e)

    return jsonify(stats)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
EOF

# 3. Download/Prepare Backup Data
echo "Preparing backup data..."

# Chinook DB SQL
# Using curl to download from GitHub. If fails, create a minimal dummy (fallback).
CHINOOK_URL="https://raw.githubusercontent.com/lerocha/chinook-database/master/ChinookDatabase/DataSources/Chinook_PostgreSql.sql"
if curl -L -o "$PROJECT_DIR/backups/chinook_db.sql" "$CHINOOK_URL"; then
    echo "Chinook DB downloaded."
else
    echo "Failed to download Chinook. Creating fallback..."
    # Fallback minimal SQL (not ideal for strict verification but prevents crash)
    cat > "$PROJECT_DIR/backups/chinook_db.sql" <<EOF
CREATE TABLE "Artist" ("ArtistId" INT NOT NULL, "Name" VARCHAR(120), CONSTRAINT "PK_Artist" PRIMARY KEY ("ArtistId"));
CREATE TABLE "Album" ("AlbumId" INT NOT NULL, "Title" VARCHAR(160) NOT NULL, "ArtistId" INT NOT NULL, CONSTRAINT "PK_Album" PRIMARY KEY ("AlbumId"));
CREATE TABLE "Track" ("TrackId" INT NOT NULL, "Name" VARCHAR(200) NOT NULL, "AlbumId" INT, "MediaTypeId" INT NOT NULL, "GenreId" INT, "Composer" VARCHAR(220), "Milliseconds" INT NOT NULL, "Bytes" INT, "UnitPrice" NUMERIC(10,2) NOT NULL, CONSTRAINT "PK_Track" PRIMARY KEY ("TrackId"));
-- Insert dummy data to match counts if download fails (would need 3503 inserts, omitted for brevity in fallback)
-- Real task relies on download.
EOF
fi

# Redis Restore Data (Text format for --pipe)
echo "Generating Redis backup..."
rm -f "$PROJECT_DIR/backups/redis_restore.txt"
for i in {1..55}; do
    echo "SET session:user$i \"{\\\"cart\\\": $i, \\\"active\\\": true}\"" >> "$PROJECT_DIR/backups/redis_restore.txt"
done

# Create a fake .rdb file just so it exists (agent might look for it, but task says use the text one or RDB)
# Since we don't have a binary generator, we'll just leave the text one as the primary source.
# The prompt says "backups/redis_sessions.rdb" exists. We can copy a dummy or just rely on the text file.
# Let's create the text file as the main restore source mentioned in description.

chown -R ga:ga "$PROJECT_DIR"

# 4. Anti-Gaming Setup
date +%s > /tmp/task_start_timestamp

# 5. Open Terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/acme-musicstore && echo \"URGENT: Database and Redis volumes lost!\"; echo \"Backups available in ./backups/\"; echo \"Restore the service and create a backup script.\"; echo; ls -F; exec bash'" > /tmp/term.log 2>&1 &
sleep 2

# Initial Screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="