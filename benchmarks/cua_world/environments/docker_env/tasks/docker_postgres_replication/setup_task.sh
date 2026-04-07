#!/bin/bash
set -e
echo "=== Setting up PostgreSQL Replication Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker to be ready
if type wait_for_docker &>/dev/null; then
    wait_for_docker
else
    sleep 5
fi

# Clean up any previous run artifacts
echo "Cleaning up previous runs..."
docker rm -f primary replica db 2>/dev/null || true
docker volume rm db-primary-data db-replica-data 2>/dev/null || true
rm -rf /home/ga/projects/db-cluster

# Set up project directory structure
PROJECT_DIR="/home/ga/projects/db-cluster"
mkdir -p "$PROJECT_DIR/init-data"

# Create initial single-node docker-compose.yml
cat > "$PROJECT_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  # TODO: Rename to 'primary' and add configuration for replication
  db:
    image: postgres:15-alpine
    container_name: db
    environment:
      POSTGRES_PASSWORD: password123
    ports:
      - "5432:5432"
    volumes:
      - db-data:/var/lib/postgresql/data
      - ./init-data:/docker-entrypoint-initdb.d

volumes:
  db-data:
EOF

# Create Schema SQL
cat > "$PROJECT_DIR/init-data/01-schema.sql" <<EOF
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    stock INT NOT NULL DEFAULT 0
);

CREATE TABLE replication_logs (
    id SERIAL PRIMARY KEY,
    event VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
EOF

# Create Seed Data SQL
cat > "$PROJECT_DIR/init-data/02-seed.sql" <<EOF
INSERT INTO products (name, price, stock) VALUES
('Gaming Laptop', 1299.99, 50),
('Wireless Mouse', 29.99, 200),
('Mechanical Keyboard', 89.99, 75),
('Monitor 27-inch', 249.99, 30),
('USB-C Hub', 39.99, 100);
EOF

chown -R ga:ga "/home/ga/projects"

# Record task start timestamp
date +%s > /tmp/task_start_timestamp

# Launch a terminal for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/db-cluster && echo \"PostgreSQL HA Cluster Setup\"; echo \"Current setup: Single node (db)\"; echo \"Goal: Convert to Primary-Replica HA cluster\"; echo; ls -la; exec bash'" > /tmp/db_terminal.log 2>&1 &

sleep 5
take_screenshot /tmp/task_start.png 2>/dev/null || true

echo "=== Setup Complete ==="