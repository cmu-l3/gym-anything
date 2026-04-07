#!/bin/bash
set -e
echo "=== Setting up Docker Disaster Recovery Drill ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Wait for Docker
if ! docker info >/dev/null 2>&1; then
    echo "Waiting for Docker..."
    for i in {1..30}; do
        if docker info >/dev/null 2>&1; then break; fi
        sleep 2
    done
fi

# 2. Cleanup previous runs
echo "Cleaning previous state..."
docker rm -f acme-db acme-cache acme-web 2>/dev/null || true
docker volume rm acme-pgdata acme-redisdata 2>/dev/null || true
rm -rf /home/ga/projects/disaster-recovery
rm -rf /home/ga/backups
mkdir -p /home/ga/projects/disaster-recovery/nginx
mkdir -p /home/ga/backups
mkdir -p /home/ga/Desktop

# 3. Create Nginx Config
cat > /home/ga/projects/disaster-recovery/nginx/nginx.conf << 'EOF'
events { worker_connections 1024; }
http {
    server {
        listen 80;
        location / {
            return 200 'AcmeCorp Disaster Recovery Drill Target';
            add_header Content-Type text/plain;
        }
        location /api/health {
            return 200 '{"status":"ok"}';
            add_header Content-Type application/json;
        }
    }
}
EOF

# 4. Create Docker Compose File
cat > /home/ga/projects/disaster-recovery/docker-compose.yml << 'EOF'
version: '3.8'
services:
  acme-db:
    image: postgres:14
    container_name: acme-db
    environment:
      POSTGRES_USER: pagila
      POSTGRES_PASSWORD: password123
      POSTGRES_DB: pagila
    volumes:
      - acme-pgdata:/var/lib/postgresql/data
    networks:
      - acme-net

  acme-cache:
    image: redis:7-alpine
    container_name: acme-cache
    command: ["redis-server", "--appendonly", "yes"]
    volumes:
      - acme-redisdata:/data
    networks:
      - acme-net

  acme-web:
    image: nginx:1.24-alpine
    container_name: acme-web
    ports:
      - "8080:80"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - acme-db
      - acme-cache
    networks:
      - acme-net

volumes:
  acme-pgdata:
  acme-redisdata:

networks:
  acme-net:
EOF

chown -R ga:ga /home/ga/projects/disaster-recovery

# 5. Start the stack
echo "Starting application stack..."
cd /home/ga/projects/disaster-recovery
sudo -u ga docker compose up -d

# Wait for DB
echo "Waiting for database to initialize..."
sleep 10
for i in {1..30}; do
    if docker exec acme-db pg_isready -U pagila >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

# 6. Generate Real Data (Pagila Schema & Data)
# We use a python script to generate SQL to avoid external dependency flakiness
echo "Generating database content..."
cat << 'PYEOF' | python3 > /tmp/pagila_data.sql
import random
from datetime import datetime, timedelta

print("BEGIN;")
# Schema
print("CREATE TABLE customer (customer_id SERIAL PRIMARY KEY, first_name TEXT, last_name TEXT, email TEXT, active BOOLEAN DEFAULT TRUE, create_date TIMESTAMP DEFAULT NOW());")
print("CREATE TABLE film (film_id SERIAL PRIMARY KEY, title TEXT, description TEXT, release_year INT, rental_duration INT, rental_rate DECIMAL(4,2), length INT, replacement_cost DECIMAL(5,2), rating TEXT);")
print("CREATE TABLE rental (rental_id SERIAL PRIMARY KEY, rental_date TIMESTAMP, inventory_id INT, customer_id INT, return_date TIMESTAMP, staff_id INT, last_update TIMESTAMP DEFAULT NOW());")

# Data - Customer (599 rows)
first_names = ["MARY", "PATRICIA", "LINDA", "BARBARA", "ELIZABETH", "JENNIFER", "MARIA", "SUSAN", "MARGARET", "DOROTHY"]
last_names = ["SMITH", "JOHNSON", "WILLIAMS", "JONES", "BROWN", "DAVIS", "MILLER", "WILSON", "MOORE", "TAYLOR"]
print("COPY customer (customer_id, first_name, last_name, email) FROM stdin;")
for i in range(1, 600):
    fn = random.choice(first_names)
    ln = random.choice(last_names)
    print(f"{i}\t{fn}\t{ln}\t{fn}.{ln}@sakilacustomer.org")
print("\\.")

# Data - Film (1000 rows)
adjectives = ["EPIC", "AWE-INSPIRING", "THOUGHTFUL", "BRILLIANT", "MINDBLOWING"]
nouns = ["DRAMA", "STORY", "SAGA", "TALE", "YARN"]
print("COPY film (film_id, title, description, release_year, rental_rate) FROM stdin;")
for i in range(1, 1001):
    title = f"{random.choice(adjectives)} {random.choice(nouns)} {i}"
    print(f"{i}\t{title}\tA {title.lower()} about a database recovery\t2006\t0.99")
print("\\.")

# Data - Rental (16044 rows)
print("COPY rental (rental_id, rental_date, customer_id, inventory_id) FROM stdin;")
start_date = datetime(2023, 1, 1)
for i in range(1, 16045):
    rdate = start_date + timedelta(minutes=i*10)
    cid = (i % 599) + 1
    inv = (i % 4000) + 1
    print(f"{i}\t{rdate}\t{cid}\t{inv}")
print("\\.")
print("COMMIT;")
PYEOF

# Load Data into Postgres
cat /tmp/pagila_data.sql | docker exec -i acme-db psql -U pagila -d pagila > /dev/null

# 7. Generate Redis Data
echo "Seeding Redis data..."
docker exec -i acme-cache sh -c '
for i in $(seq 1 50); do
  redis-cli set "session:$i" "{\"user_id\":$i,\"cart\":[\"item_1\",\"item_2\"],\"login_ts\":1698765432}" > /dev/null
done
redis-cli save > /dev/null
'

# 8. Record Task Start Time (CRITICAL for anti-gaming volume check)
# We record this AFTER initial volume creation.
# If the agent destroys the volume, the NEW volume will have a creation time > TASK_START_TIME.
# Wait a second to ensure strict inequality.
sleep 2
date +%s > /tmp/task_start_time.txt
echo "Task Start Timestamp: $(cat /tmp/task_start_time.txt)"

# Record initial volume IDs to verify they change later
docker volume inspect acme-pgdata --format '{{.CreatedAt}}' > /tmp/initial_pg_vol_created
docker volume inspect acme-redisdata --format '{{.CreatedAt}}' > /tmp/initial_redis_vol_created

# 9. Setup UI
take_screenshot /tmp/task_initial.png
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd ~/projects/disaster-recovery; echo \"DISASTER RECOVERY DRILL\"; echo \"-----------------------\"; echo \"Stack is running.\"; echo \"1. Backup everything (DB, Redis, configs)\"; echo \"2. DESTROY STACK AND VOLUMES\"; echo \"3. Restore from backup\"; echo \"4. Verify data\"; echo; exec bash'" &

echo "=== Setup Complete ==="