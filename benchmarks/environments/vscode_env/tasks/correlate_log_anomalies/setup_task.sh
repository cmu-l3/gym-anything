#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Log Correlation Task ==="

WORKSPACE_DIR="/home/ga/workspace/log_analysis"
LOGS_DIR="$WORKSPACE_DIR/logs"
DOCS_DIR="$WORKSPACE_DIR/docs"

# Create directory structure
sudo -u ga mkdir -p "$LOGS_DIR"
sudo -u ga mkdir -p "$DOCS_DIR"

# Generate application.log with connection pool exhaustion anomaly
cat > "$LOGS_DIR/application.log" << 'EOF'
2024-01-23 14:15:03 INFO [main] Application started successfully
2024-01-23 14:15:04 INFO [scheduler] Background jobs initialized
2024-01-23 14:16:12 INFO [api] Health check passed - all systems operational
2024-01-23 14:17:45 INFO [cache] Cache hit ratio: 94.2%
2024-01-23 14:18:22 INFO [api] Processing checkout request user_id=1052
2024-01-23 14:18:22 INFO [cache] Cache hit for product_1523
2024-01-23 14:18:23 INFO [api] Checkout completed successfully (245ms)
2024-01-23 14:19:08 INFO [api] Processing order update user_id=1067
2024-01-23 14:19:09 INFO [api] Order update completed (187ms)
2024-01-23 14:20:15 INFO [api] Processing checkout request user_id=1089
2024-01-23 14:20:15 INFO [cache] Cache hit for product_1634
2024-01-23 14:20:16 INFO [api] Checkout completed successfully (198ms)
2024-01-23 14:21:33 INFO [metrics] Current load: 45 req/min, avg response: 215ms
2024-01-23 14:22:48 INFO [api] Processing search query term="laptop"
2024-01-23 14:23:15 INFO [scheduler] Starting scheduled job: daily_export_job
2024-01-23 14:23:15 INFO [export] Initializing data export for 2024-01-22
2024-01-23 14:23:16 INFO [export] Acquiring database connections (pool_size=10)
2024-01-23 14:23:16 INFO [export] Scanning orders table for export criteria
2024-01-23 14:23:17 WARN [pool] Connection pool utilization at 90% (9/10 connections in use)
2024-01-23 14:23:17 WARN [pool] Only 1 connection available in pool
2024-01-23 14:23:18 INFO [export] Processing batch 1 of 15 (8,333 records per batch)
2024-01-23 14:23:25 INFO [api] Processing checkout request user_id=1103
2024-01-23 14:23:28 WARN [api] Slow response detected (3012ms) for /api/checkout
2024-01-23 14:23:30 INFO [api] Processing checkout request user_id=1107
2024-01-23 14:23:33 WARN [pool] Thread pool-7 waiting for database connection
2024-01-23 14:23:35 WARN [pool] Thread pool-9 waiting for database connection
2024-01-23 14:23:38 ERROR [api] Request timeout (8001ms) for /api/checkout user_id=1107
2024-01-23 14:23:38 WARN [pool] Connection pool exhausted, threads waiting
2024-01-23 14:23:42 INFO [api] Processing checkout request user_id=1112
2024-01-23 14:23:48 ERROR [monitor] Health check failed: database connection timeout
2024-01-23 14:24:05 WARN [api] Multiple requests queued waiting for DB connections (queue depth: 7)
2024-01-23 14:24:10 ERROR [api] Request timeout (8532ms) for /api/checkout user_id=1112
2024-01-23 14:24:18 INFO [api] Processing checkout request user_id=1118
2024-01-23 14:24:25 ERROR [api] Request timeout (7890ms) for /api/checkout user_id=1118
2024-01-23 14:24:42 WARN [export] Export taking longer than expected (1m27s elapsed)
2024-01-23 14:25:15 INFO [export] Processing batch 12 of 15
2024-01-23 14:25:45 INFO [export] Data export completed (2.5 minutes, 125,000 records)
2024-01-23 14:25:45 INFO [pool] Export job released all held connections
2024-01-23 14:25:45 INFO [pool] Connection pool returned to normal (2/10 in use)
2024-01-23 14:25:52 INFO [api] Processing queued requests (backlog: 3)
2024-01-23 14:26:02 INFO [api] Processing checkout request user_id=1156
2024-01-23 14:26:02 INFO [api] Checkout completed successfully (223ms)
2024-01-23 14:26:30 INFO [metrics] Load normalized: 42 req/min, avg response: 201ms
2024-01-23 14:27:15 INFO [api] All queued requests processed successfully
EOF

# Generate database.log with slow query anomalies
cat > "$LOGS_DIR/database.log" << 'EOF'
2024-01-23 14:17:45.123 INFO [pool] Connection pool initialized (size=10, timeout=5000ms)
2024-01-23 14:18:22.445 QUERY [conn_3] SELECT * FROM products WHERE id=1523 (12ms)
2024-01-23 14:18:22.891 QUERY [conn_3] INSERT INTO orders (user_id, total, status) VALUES (1052, 299.99, 'pending') (35ms)
2024-01-23 14:18:23.102 QUERY [conn_3] COMMIT (8ms)
2024-01-23 14:19:08.234 QUERY [conn_5] UPDATE orders SET status='completed' WHERE id=9823 (23ms)
2024-01-23 14:20:15.234 QUERY [conn_5] SELECT * FROM products WHERE id=1634 (9ms)
2024-01-23 14:20:15.678 QUERY [conn_5] INSERT INTO orders (user_id, total, status) VALUES (1089, 145.50, 'pending') (28ms)
2024-01-23 14:20:16.001 QUERY [conn_5] COMMIT (11ms)
2024-01-23 14:22:48.456 QUERY [conn_2] SELECT * FROM products WHERE name LIKE '%laptop%' (34ms)
2024-01-23 14:23:16.123 QUERY [conn_1] SELECT * FROM orders WHERE date='2024-01-22' (45ms)
2024-01-23 14:23:16.456 QUERY [conn_2] SELECT * FROM order_items WHERE order_id IN (SELECT id FROM orders WHERE date='2024-01-22') (78ms)
2024-01-23 14:23:16.789 QUERY [conn_3] SELECT * FROM customers WHERE id IN (...) (62ms)
2024-01-23 14:23:16.998 QUERY [conn_4] SELECT * FROM products WHERE id IN (...) (89ms)
2024-01-23 14:23:17.012 INFO [pool] Active connections: 9/10
2024-01-23 14:23:17.245 QUERY [conn_5] SELECT * FROM shipping_addresses WHERE order_id IN (...) (112ms)
2024-01-23 14:23:18.567 QUERY [conn_6] SELECT COUNT(*) FROM order_items WHERE order_id IN (...) (156ms)
2024-01-23 14:23:20.234 QUERY [conn_7] SELECT * FROM products WHERE id=1789 (1245ms) [SLOW QUERY]
2024-01-23 14:23:21.456 QUERY [conn_8] INSERT INTO orders (user_id, total, status) VALUES (1103, 78.99, 'pending') (2134ms) [SLOW QUERY]
2024-01-23 14:23:23.678 WARN [pool] Query queue depth: 5, available connections: 0
2024-01-23 14:23:25.890 QUERY [conn_9] SELECT * FROM products WHERE id=1802 (3456ms) [SLOW QUERY]
2024-01-23 14:23:28.123 ERROR [pool] Connection acquisition timeout: no connections available after 5000ms
2024-01-23 14:23:30.456 QUERY [conn_10] INSERT INTO orders (user_id, total, status) VALUES (1107, 199.99, 'pending') (4782ms) [SLOW QUERY]
2024-01-23 14:23:35.678 WARN [pool] 12 threads waiting for connections
2024-01-23 14:23:42.890 ERROR [pool] Connection wait timeout exceeded for thread pool-12
2024-01-23 14:24:05.123 WARN [pool] All connections in use by export job threads
2024-01-23 14:24:10.345 ERROR [pool] Query timeout: INSERT INTO orders VALUES (...) - connection unavailable
2024-01-23 14:25:45.789 INFO [pool] Export connections released (8 connections freed)
2024-01-23 14:25:46.012 INFO [pool] Active connections: 2/10
2024-01-23 14:26:02.234 QUERY [conn_3] SELECT * FROM products WHERE id=1845 (14ms)
2024-01-23 14:26:02.567 QUERY [conn_3] INSERT INTO orders (user_id, total, status) VALUES (1156, 89.99, 'pending') (27ms)
2024-01-23 14:26:30.789 INFO [pool] Connection pool utilization normal: avg 3/10
EOF

# Generate requests.log with response time spikes
cat > "$LOGS_DIR/requests.log" << 'EOF'
2024-01-23 14:17:12.345 GET /api/health 200 15ms Mozilla/5.0
2024-01-23 14:17:45.678 GET /api/categories 200 48ms Mozilla/5.0
2024-01-23 14:18:22.123 GET /api/products/1523 200 45ms Mozilla/5.0
2024-01-23 14:18:22.445 POST /api/checkout 200 245ms user_id=1052 Mozilla/5.0
2024-01-23 14:18:56.789 GET /api/cart 200 67ms Mozilla/5.0
2024-01-23 14:19:08.012 PUT /api/orders/9823 200 187ms Mozilla/5.0
2024-01-23 14:19:34.234 GET /api/products 200 92ms Mozilla/5.0
2024-01-23 14:19:45.678 GET /api/products/1634 200 38ms Mozilla/5.0
2024-01-23 14:20:15.234 POST /api/checkout 200 198ms user_id=1089 Mozilla/5.0
2024-01-23 14:20:48.456 GET /api/categories/electronics 200 55ms Mozilla/5.0
2024-01-23 14:21:22.678 GET /api/cart 200 41ms Mozilla/5.0
2024-01-23 14:22:10.456 GET /api/categories 200 52ms Mozilla/5.0
2024-01-23 14:22:48.789 GET /api/search?q=laptop 200 156ms Mozilla/5.0
2024-01-23 14:23:15.012 GET /api/products/1789 200 234ms Mozilla/5.0
2024-01-23 14:23:25.789 POST /api/checkout 504 8012ms user_id=1103 Mozilla/5.0
2024-01-23 14:23:30.012 POST /api/checkout 504 8532ms user_id=1107 Mozilla/5.0
2024-01-23 14:23:42.234 POST /api/checkout 504 9123ms user_id=1112 Mozilla/5.0
2024-01-23 14:23:45.234 GET /api/products/1678 500 5234ms Mozilla/5.0
2024-01-23 14:23:58.456 GET /api/cart 504 6789ms Mozilla/5.0
2024-01-23 14:24:10.456 POST /api/checkout 504 9123ms user_id=1112 Mozilla/5.0
2024-01-23 14:24:18.678 GET /api/products/1834 504 7456ms Mozilla/5.0
2024-01-23 14:24:25.678 POST /api/checkout 504 7890ms user_id=1118 Mozilla/5.0
2024-01-23 14:24:38.890 GET /api/categories 504 5678ms Mozilla/5.0
2024-01-23 14:25:52.123 POST /api/checkout 200 312ms user_id=1145 Mozilla/5.0
2024-01-23 14:26:02.890 POST /api/checkout 200 223ms user_id=1156 Mozilla/5.0
2024-01-23 14:26:20.345 GET /api/products/1890 200 41ms Mozilla/5.0
2024-01-23 14:26:30.123 GET /api/products/1891 200 38ms Mozilla/5.0
2024-01-23 14:27:00.456 GET /api/cart 200 45ms Mozilla/5.0
EOF

# Create incident report template
cat > "$DOCS_DIR/incident_template.md" << 'EOF'
# Incident Report: [Date]

## Summary
[Brief one-sentence description of what happened]

## Impact
[Who was affected? What functionality was degraded? What were the symptoms?]

## Root Cause
[What specifically caused the issue? Be precise about the component and failure mode]

## Timeline
[Chronological sequence of events with timestamps showing how the issue developed]

Example format:
- 14:23:15 - Event A occurred
- 14:23:20 - Event B started showing symptoms
- 14:25:45 - Event C resolved the issue

## Evidence
[References to specific log entries, metrics, or data supporting your analysis]

Example format:
- application.log line ~15: Shows connection pool warning
- database.log: Query timeouts at 14:23:XX

## Resolution
[What fixed the issue? Is it currently fixed or still ongoing?]

## Action Items
[What should we do to prevent this in the future?]
EOF

# Create README with system context
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Log Analysis Workspace

## System Overview
This is a microservices-based e-commerce platform with the following components:

- **API Service**: Flask application handling HTTP requests
- **Database**: PostgreSQL with connection pool (max size: 10 connections)
- **Background Jobs**: Scheduled tasks including daily data exports
- **Cache Layer**: Redis cache for product data

## Normal Baseline Performance
- Checkout API: 200-300ms response time
- Database queries: <50ms execution time  
- Connection pool: typically 2-3 active connections under normal load
- Request success rate: >99.9%

## Architecture Notes
- Connection pool has a fixed size of 10 connections
- Connection acquisition timeout: 5000ms (5 seconds)
- Export jobs run daily at 14:23 UTC
- All timestamps in logs are in UTC

## Incident Context
**Date**: 2024-01-23  
**Time Window**: 14:00 - 15:00 UTC  
**User Report**: "Checkout is extremely slow, taking 8-10 seconds instead of normal speed"  
**Affected Endpoint**: POST /api/checkout

Your task is to analyze the three log files in the `logs/` directory to determine:
1. What went wrong?
2. When did it start?
3. What was the root cause?
4. What evidence supports your conclusion?

Document your findings in a new file: `docs/incident_report_2024-01-23.md`
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode with log analysis workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/README.md'" &
wait_for_vscode 25
wait_for_window "Visual Studio Code" 35

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Log Correlation Task Setup Complete ==="
echo "📝 Task Instructions:"
echo "  1. Review README.md for incident context"
echo "  2. Analyze three log files in logs/ directory:"
echo "     - application.log (app events)"
echo "     - database.log (query performance)"
echo "     - requests.log (API response times)"
echo "  3. Use Find in Files (Ctrl+Shift+F) to search for anomalies around 14:23"
echo "  4. Correlate events across log files"
echo "  5. Create incident_report_2024-01-23.md in docs/ with:"
echo "     - Root Cause section"
echo "     - Timeline section (3+ timestamps)"
echo "     - Evidence section (reference 2+ log files)"
echo "  6. Save your report"