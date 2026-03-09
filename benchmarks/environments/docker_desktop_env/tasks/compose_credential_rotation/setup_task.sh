#!/bin/bash
set -e

echo "=== Setting up compose_credential_rotation task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Prepare Workspace
PROJECT_DIR="/home/ga/app-stack"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# 2. Create Initial Docker Compose File (with OLD password)
cat > "$PROJECT_DIR/docker-compose.yml" << 'EOF'
services:
  db:
    image: postgres:15-alpine
    container_name: appstack-db
    environment:
      POSTGRES_USER: appuser
      POSTGRES_PASSWORD: oldpass123
      POSTGRES_DB: appdb
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U appuser -d appdb"]
      interval: 5s
      timeout: 3s
      retries: 5
    restart: unless-stopped

  adminer:
    image: adminer:latest
    container_name: appstack-adminer
    environment:
      ADMINER_DEFAULT_SERVER: db
      ADMINER_DEFAULT_USER: appuser
      ADMINER_DEFAULT_PASSWORD: oldpass123
    ports:
      - "8081:8080"
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

volumes:
  pgdata:
EOF
chown ga:ga "$PROJECT_DIR/docker-compose.yml"

# 3. Start the Stack
echo "Starting Docker Compose stack..."
cd "$PROJECT_DIR"
# Ensure we start fresh
docker compose down -v 2>/dev/null || true
docker compose up -d

# 4. Wait for Database to be Healthy
echo "Waiting for database to be ready..."
for i in {1..30}; do
    if docker inspect --format '{{.State.Health.Status}}' appstack-db 2>/dev/null | grep -q "healthy"; then
        echo "Database is healthy."
        break
    fi
    sleep 2
done

# 5. Seed Real Data
echo "Seeding database..."
# Wait a tiny bit more for socket availability
sleep 2

docker exec appstack-db psql -U appuser -d appdb -c "
DROP TABLE IF EXISTS projects;
CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    status VARCHAR(50) NOT NULL,
    budget DECIMAL(12,2) NOT NULL,
    start_date DATE NOT NULL,
    team_lead VARCHAR(100) NOT NULL
);
INSERT INTO projects (name, status, budget, start_date, team_lead) VALUES
('Cloud Migration Phase 2', 'In Progress', 450000.00, '2024-01-15', 'Sarah Chen'),
('Mobile App Redesign', 'Planning', 280000.00, '2024-03-01', 'Marcus Johnson'),
('Data Pipeline Modernization', 'In Progress', 620000.00, '2023-11-20', 'Priya Patel'),
('Customer Portal v3', 'On Hold', 175000.00, '2024-02-10', 'David Kim'),
('Security Compliance Audit', 'Completed', 95000.00, '2023-09-05', 'Elena Rodriguez');
"

# 6. Verify Initial State
INITIAL_ROWS=$(docker exec appstack-db psql -U appuser -d appdb -t -c "SELECT COUNT(*) FROM projects;" | xargs)
echo "$INITIAL_ROWS" > /tmp/initial_row_count.txt
echo "Seeded $INITIAL_ROWS rows."

# Record task start time
date +%s > /tmp/task_start_time.txt

# 7. Setup Desktop Environment
# Ensure Docker Desktop is running (if not already handled by hook)
if ! docker_desktop_running; then
    su - ga -c "DISPLAY=:1 /opt/docker-desktop/bin/docker-desktop > /dev/null 2>&1 &"
    sleep 5
fi

# Open the project folder in a file manager for convenience
su - ga -c "DISPLAY=:1 nautilus $PROJECT_DIR &"
sleep 2

# Maximize file manager
DISPLAY=:1 wmctrl -r "app-stack" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="