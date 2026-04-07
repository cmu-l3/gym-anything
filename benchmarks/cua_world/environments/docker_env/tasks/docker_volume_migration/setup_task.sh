#!/bin/bash
set -e
echo "=== Setting up Docker Volume Migration Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Function to wait for Docker (fallback if utils not present)
if ! type wait_for_docker &>/dev/null; then
    wait_for_docker() {
        for i in {1..60}; do
            if docker info > /dev/null 2>&1; then return 0; fi
            sleep 2
        done; return 1
    }
fi

wait_for_docker

# 1. Prepare Project Directory
PROJECT_DIR="/home/ga/projects/employee-db"
mkdir -p "$PROJECT_DIR/pgdata"
chmod 777 "$PROJECT_DIR/pgdata" # Ensure writable by container

# 2. Create docker-compose.yml with Bind Mount
cat > "$PROJECT_DIR/docker-compose.yml" <<EOF
version: '3.8'

services:
  db:
    image: postgres:14
    container_name: employee-db
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: employees
    volumes:
      - ./pgdata:/var/lib/postgresql/data
    ports:
      - "5432:5432"
EOF

chown -R ga:ga "$PROJECT_DIR"

# 3. Start Container to Initialize DB
echo "Starting initial database container..."
cd "$PROJECT_DIR"
# Run as ga user to ensure file permissions are correct
su - ga -c "docker compose up -d"

# 4. Wait for DB to be healthy
echo "Waiting for PostgreSQL to be ready..."
for i in {1..30}; do
    if docker exec employee-db pg_isready -U postgres >/dev/null 2>&1; then
        echo "Database is ready."
        break
    fi
    sleep 2
done

# 5. Seed Data (100 Employee Records)
echo "Seeding database with 100 records..."
# Generate SQL file using Python
cat << 'PY_SCRIPT' | python3 > "$PROJECT_DIR/seed.sql"
import random

print("CREATE TABLE IF NOT EXISTS employees (id SERIAL PRIMARY KEY, name VARCHAR(100), role VARCHAR(100), salary INT);")
print("INSERT INTO employees (name, role, salary) VALUES")

roles = ["Engineer", "Manager", "Designer", "HR", "Sales"]
names = ["John", "Jane", "Alice", "Bob", "Charlie", "David", "Eve", "Frank"]
surnames = ["Doe", "Smith", "Johnson", "Brown", "Williams", "Jones"]

values = []
for i in range(100):
    name = f"{random.choice(names)} {random.choice(surnames)}"
    role = random.choice(roles)
    salary = random.randint(50000, 150000)
    values.append(f"('{name}', '{role}', {salary})")

print(",\n".join(values) + ";")
PY_SCRIPT

# Execute Seed
cat "$PROJECT_DIR/seed.sql" | docker exec -i employee-db psql -U postgres -d employees >/dev/null

# 6. Verify Initial State
INITIAL_COUNT=$(docker exec employee-db psql -U postgres -d employees -t -c "SELECT COUNT(*) FROM employees;" | tr -d '[:space:]')
echo "Initial record count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/initial_record_count

if [ "$INITIAL_COUNT" != "100" ]; then
    echo "ERROR: Data seeding failed. Count is $INITIAL_COUNT"
    exit 1
fi

# 7. Record Task Start Time
date +%s > /tmp/task_start_timestamp

# 8. Setup User Interface (Terminal)
mkdir -p /home/ga/Desktop
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/employee-db && echo \"Task: Migrate ./pgdata bind mount to named volume employee_db_data\"; echo \"Current Status:\"; docker compose ps; echo; ls -l pgdata; exec bash'" > /tmp/terminal.log 2>&1 &
sleep 2

# 9. Screenshot
DISPLAY=:1 scrot /tmp/task_start_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="