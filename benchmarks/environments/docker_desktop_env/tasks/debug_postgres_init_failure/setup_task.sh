#!/bin/bash
# Setup script for debug_postgres_init_failure
# Creates a scenario where a Postgres container has a stale, empty data volume
# preventing the init.sql script from running.

echo "=== Setting up debug_postgres_init_failure task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time

# Wait for Docker Daemon
wait_for_docker_daemon 60

# Define paths
PROJECT_DIR="/home/ga/Documents/docker-projects/inventory"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# 1. Create the init.sql file
cat > "$PROJECT_DIR/init.sql" << 'EOF'
-- Initial schema for Inventory System
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    sku VARCHAR(50) UNIQUE NOT NULL,
    quantity INTEGER DEFAULT 0,
    price DECIMAL(10, 2)
);

INSERT INTO products (name, sku, quantity, price) VALUES 
('Laptop Stand', 'LPT-STD-001', 50, 29.99),
('Wireless Mouse', 'WRL-MSE-002', 120, 15.50),
('Mechanical Keyboard', 'MCH-KBD-003', 30, 89.99);
EOF
chown ga:ga "$PROJECT_DIR/init.sql"

# 2. Create the docker-compose.yml
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  db:
    image: postgres:15-alpine
    container_name: inventory_db
    environment:
      POSTGRES_PASSWORD: password
      POSTGRES_DB: inventory
    volumes:
      - pgdata:/var/lib/postgresql/data
      # This script should run on init, but won't if pgdata is already populated
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql:ro
    ports:
      - "5432:5432"
    restart: unless-stopped

  adminer:
    image: adminer
    restart: unless-stopped
    ports:
      - 8080:8080

volumes:
  pgdata:
    name: inventory_pgdata
EOF
chown ga:ga "$PROJECT_DIR/docker-compose.yml"

# 3. Create the TRAP: Pre-populate the volume WITHOUT the init script
echo "Setting up stale volume state..."

# Clean up any previous attempts
docker rm -f inventory_db 2>/dev/null || true
docker volume rm inventory_pgdata 2>/dev/null || true

# Start a temporary postgres container attached to the named volume
# We do NOT mount the init.sql here, so the volume initializes empty
docker run -d \
    --name setup-temp-db \
    -v inventory_pgdata:/var/lib/postgresql/data \
    -e POSTGRES_PASSWORD=password \
    -e POSTGRES_DB=inventory \
    postgres:15-alpine

# Wait for it to initialize the data directory
echo "Waiting for DB initialization..."
for i in {1..30}; do
    if docker logs setup-temp-db 2>&1 | grep -q "database system is ready to accept connections"; then
        echo "DB initialized (stale state created)"
        break
    fi
    sleep 1
done

# Stop and remove the container, LEAVING THE VOLUME
docker rm -f setup-temp-db

# 4. Ensure Docker Desktop is visible
focus_docker_desktop

# Take initial screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="
echo "Project created at $PROJECT_DIR"
echo "Stale volume 'inventory_pgdata' created."