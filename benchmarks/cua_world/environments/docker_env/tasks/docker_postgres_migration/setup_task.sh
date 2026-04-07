#!/bin/bash
echo "=== Setting up Docker PostgreSQL Migration Task ==="
source /workspace/scripts/task_utils.sh

wait_for_docker

# ── Tear down any pre-existing migration containers ───────────────────────────
for name in chinook-pg13 chinook-pg15; do
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        docker rm -f "$name" 2>/dev/null || true
    fi
done

# ── Start the PostgreSQL 13 source container ──────────────────────────────────
echo "Starting PostgreSQL 13 source container..."
sudo -u ga docker compose -f /workspace/data/task5_migration/docker-compose.source.yml \
    --project-name chinook-source \
    up -d 2>&1 | tail -20

# ── Wait for PG13 to be healthy ───────────────────────────────────────────────
echo "Waiting for chinook-pg13 to become healthy..."
for i in $(seq 1 60); do
    STATUS=$(docker inspect chinook-pg13 --format '{{.State.Health.Status}}' 2>/dev/null || echo "not_running")
    if [ "$STATUS" = "healthy" ]; then
        echo "chinook-pg13 is healthy."
        break
    fi
    if [ "$i" = "60" ]; then
        echo "WARNING: chinook-pg13 not healthy after 120s, proceeding anyway."
    fi
    sleep 2
done

# Also verify psql connectivity directly
echo "Verifying database connectivity..."
for i in $(seq 1 30); do
    if docker exec chinook-pg13 pg_isready -U chinook -d chinook 2>/dev/null; then
        echo "Database is accepting connections."
        break
    fi
    sleep 2
done

# ── Record baseline row counts from PG13 ─────────────────────────────────────
echo "Recording baseline row counts from PG13..."

pg13_query() {
    docker exec chinook-pg13 psql -U chinook -d chinook -t -c "$1" 2>/dev/null | tr -d ' \n'
}

ARTIST_COUNT=$(pg13_query 'SELECT COUNT(*) FROM "Artist"')
ALBUM_COUNT=$(pg13_query 'SELECT COUNT(*) FROM "Album"')
TRACK_COUNT=$(pg13_query 'SELECT COUNT(*) FROM "Track"')
CUSTOMER_COUNT=$(pg13_query 'SELECT COUNT(*) FROM "Customer"')
EMPLOYEE_COUNT=$(pg13_query 'SELECT COUNT(*) FROM "Employee"')
GENRE_COUNT=$(pg13_query 'SELECT COUNT(*) FROM "Genre"')
MEDIATYPE_COUNT=$(pg13_query 'SELECT COUNT(*) FROM "MediaType"')
INVOICE_COUNT=$(pg13_query 'SELECT COUNT(*) FROM "Invoice"')
INVOICELINE_COUNT=$(pg13_query 'SELECT COUNT(*) FROM "InvoiceLine"')
PLAYLIST_COUNT=$(pg13_query 'SELECT COUNT(*) FROM "Playlist"')
PLAYLISTTRACK_COUNT=$(pg13_query 'SELECT COUNT(*) FROM "PlaylistTrack"')

# Use 0 as fallback for any empty values
ARTIST_COUNT=${ARTIST_COUNT:-0}
ALBUM_COUNT=${ALBUM_COUNT:-0}
TRACK_COUNT=${TRACK_COUNT:-0}
CUSTOMER_COUNT=${CUSTOMER_COUNT:-0}
EMPLOYEE_COUNT=${EMPLOYEE_COUNT:-0}
GENRE_COUNT=${GENRE_COUNT:-0}
MEDIATYPE_COUNT=${MEDIATYPE_COUNT:-0}
INVOICE_COUNT=${INVOICE_COUNT:-0}
INVOICELINE_COUNT=${INVOICELINE_COUNT:-0}
PLAYLIST_COUNT=${PLAYLIST_COUNT:-0}
PLAYLISTTRACK_COUNT=${PLAYLISTTRACK_COUNT:-0}

cat > /tmp/initial_pg13_counts.json <<EOF
{
  "Artist": ${ARTIST_COUNT},
  "Album": ${ALBUM_COUNT},
  "Track": ${TRACK_COUNT},
  "Customer": ${CUSTOMER_COUNT},
  "Employee": ${EMPLOYEE_COUNT},
  "Genre": ${GENRE_COUNT},
  "MediaType": ${MEDIATYPE_COUNT},
  "Invoice": ${INVOICE_COUNT},
  "InvoiceLine": ${INVOICELINE_COUNT},
  "Playlist": ${PLAYLIST_COUNT},
  "PlaylistTrack": ${PLAYLISTTRACK_COUNT}
}
EOF

echo "PG13 baseline row counts:"
cat /tmp/initial_pg13_counts.json

# ── Record task start timestamp ───────────────────────────────────────────────
date +%s > /tmp/task_start_timestamp
echo "Task start: $(cat /tmp/task_start_timestamp)"

# ── Create Desktop directory ───────────────────────────────────────────────────
sudo -u ga mkdir -p /home/ga/Desktop

# ── Take initial screenshot ────────────────────────────────────────────────────
take_screenshot "migration_task_start"

echo "=== Setup Complete ==="
echo ""
echo "PostgreSQL 13 source is running:"
docker ps --filter "name=chinook-pg13" --format "  {{.Names}} ({{.Image}}) - {{.Status}}"
echo ""
echo "Connect to source: psql -h localhost -p 5433 -U chinook -d chinook"
echo "Password: chinook_secret_2019"
echo ""
echo "Your goal: migrate all data to a PostgreSQL 15 container"
echo "Target container name: chinook-pg15"
echo "Target port: 5434"
echo "Same credentials: -U chinook -d chinook, password chinook_secret_2019"
