#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Analyze Test Failures Task ==="

WORKSPACE_DIR="/home/ga/workspace"
LOG_FILE="$WORKSPACE_DIR/test_output.log"

# Create workspace
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Remove any existing files
rm -f "$LOG_FILE"
rm -f "$WORKSPACE_DIR/test_failures_summary.txt"

echo "Generating realistic test output log (~8200 lines)..."

# Generate massive test log with realistic content
cat > "$LOG_FILE" << 'LOGEOF'
================================ test session starts =================================
platform linux -- Python 3.10.12, pytest-7.4.3, pluggy-1.3.0
rootdir: /app/microservices
plugins: asyncio-0.21.1, cov-4.1.0, django-4.5.2
collected 487 items

tests/test_auth.py::test_login_success PASSED                                  [ 1%]
[INFO] 2024-01-15 10:23:45 - Database connection established: postgresql://localhost:5432/testdb
[DEBUG] 2024-01-15 10:23:45 - Query: SELECT * FROM users WHERE username='testuser' (0.012s)
[INFO] 2024-01-15 10:23:45 - User authenticated successfully
tests/test_auth.py::test_login_invalid_credentials PASSED                      [ 2%]
[DEBUG] 2024-01-15 10:23:46 - Authentication failed for user: invaliduser
tests/test_auth.py::test_logout PASSED                                         [ 3%]
[INFO] 2024-01-15 10:23:46 - Session terminated for user_id: 12345

tests/test_database.py::test_connection_success PASSED                         [ 4%]
[DEBUG] 2024-01-15 10:23:47 - Testing database connection pool
[INFO] 2024-01-15 10:23:47 - Connection pool size: 10, Active: 2
FAILED tests/test_database.py::test_connection_timeout - TimeoutError: Connection timed out after 30s
[ERROR] 2024-01-15 10:23:48 - Failed to connect to database within timeout period
[STACK TRACE]
Traceback (most recent call last):
  File "/app/tests/test_database.py", line 45, in test_connection_timeout
    conn = db.connect(timeout=30)
  File "/app/database/connection.py", line 89, in connect
    raise TimeoutError("Connection timed out after 30s")
TimeoutError: Connection timed out after 30s

tests/test_database.py::test_query_performance PASSED                          [ 5%]
[DEBUG] 2024-01-15 10:23:50 - Query executed in 0.234s
[INFO] 2024-01-15 10:23:50 - Performance benchmark passed

tests/test_api.py::test_health_check PASSED                                    [ 6%]
[INFO] 2024-01-15 10:23:51 - GET /health - 200 OK (0.045s)
tests/test_api.py::test_version_endpoint PASSED                                [ 7%]
[INFO] 2024-01-15 10:23:51 - GET /version - 200 OK - version: 2.4.1
FAILED tests/test_auth.py::test_invalid_token - AssertionError: Expected 401, got 403
[ERROR] 2024-01-15 10:23:52 - Token validation returned unexpected status code
[STACK TRACE]
Traceback (most recent call last):
  File "/app/tests/test_auth.py", line 78, in test_invalid_token
    assert response.status_code == 401
AssertionError: Expected 401, got 403

tests/test_api.py::test_list_users PASSED                                      [ 8%]
[DEBUG] 2024-01-15 10:23:53 - Query: SELECT id, username, email FROM users LIMIT 100
[INFO] 2024-01-15 10:23:53 - Retrieved 47 users
FAILED tests/test_api.py::test_user_creation - DatabaseError: Duplicate key violation
[ERROR] 2024-01-15 10:23:54 - Failed to create user due to constraint violation
[STACK TRACE]
Traceback (most recent call last):
  File "/app/tests/test_api.py", line 112, in test_user_creation
    user = api.create_user(username="testuser", email="test@example.com")
  File "/app/api/users.py", line 234, in create_user
    db.insert(user_data)
psycopg2.errors.UniqueViolation: duplicate key value violates unique constraint "users_email_key"
DatabaseError: Duplicate key violation

tests/test_cache.py::test_cache_set PASSED                                     [ 9%]
[DEBUG] 2024-01-15 10:23:55 - SET cache_key_123 = "cached_value" (TTL: 300s)
tests/test_cache.py::test_cache_get PASSED                                     [10%]
[DEBUG] 2024-01-15 10:23:55 - GET cache_key_123 = "cached_value"
FAILED tests/test_cache.py::test_redis_unavailable - ConnectionError: Redis not available
[ERROR] 2024-01-15 10:23:56 - Could not establish connection to Redis server
[STACK TRACE]
Traceback (most recent call last):
  File "/app/tests/test_cache.py", line 67, in test_redis_unavailable
    cache.connect()
  File "/app/cache/redis_client.py", line 45, in connect
    raise ConnectionError("Redis not available")
ConnectionError: Redis not available

tests/test_payments.py::test_payment_processing PASSED                         [11%]
[INFO] 2024-01-15 10:23:57 - Payment processed: $49.99 USD
[DEBUG] 2024-01-15 10:23:57 - Stripe charge ID: ch_1234567890abcdef
FAILED tests/test_payments.py::test_stripe_webhook - AssertionError: Webhook signature invalid
[ERROR] 2024-01-15 10:23:58 - Webhook verification failed
[STACK TRACE]
Traceback (most recent call last):
  File "/app/tests/test_payments.py", line 145, in test_stripe_webhook
    assert webhook.verify_signature(payload, signature)
AssertionError: Webhook signature invalid

tests/test_email.py::test_email_template_rendering PASSED                      [12%]
[DEBUG] 2024-01-15 10:23:59 - Rendered email template: welcome_email.html
tests/test_email.py::test_email_validation PASSED                              [13%]
[DEBUG] 2024-01-15 10:23:59 - Email validation passed: user@example.com
FAILED tests/test_email.py::test_send_notification - TimeoutError: SMTP timeout
[ERROR] 2024-01-15 10:24:00 - Failed to send email notification
[STACK TRACE]
Traceback (most recent call last):
  File "/app/tests/test_email.py", line 89, in test_send_notification
    mailer.send(to="user@example.com", subject="Test", body="Test email")
  File "/app/email/smtp_client.py", line 123, in send
    raise TimeoutError("SMTP timeout")
TimeoutError: SMTP timeout

tests/test_auth.py::test_token_generation PASSED                               [14%]
[DEBUG] 2024-01-15 10:24:01 - Generated JWT token (expires: 3600s)
FAILED tests/test_auth.py::test_password_reset - AssertionError: Token not in email body
[ERROR] 2024-01-15 10:24:02 - Password reset email missing token
[STACK TRACE]
Traceback (most recent call last):
  File "/app/tests/test_auth.py", line 234, in test_password_reset
    assert reset_token in email_body
AssertionError: Token not in email body

tests/test_database.py::test_transaction_rollback PASSED                       [15%]
[DEBUG] 2024-01-15 10:24:03 - Transaction rolled back successfully
FAILED tests/test_database.py::test_migration_rollback - IntegrityError: Foreign key constraint
[ERROR] 2024-01-15 10:24:04 - Migration rollback failed due to constraint violation
[STACK TRACE]
Traceback (most recent call last):
  File "/app/tests/test_database.py", line 178, in test_migration_rollback
    db.rollback_migration("0015_add_user_preferences")
  File "/app/database/migrations.py", line 456, in rollback_migration
    cursor.execute(rollback_sql)
psycopg2.errors.ForeignKeyViolation: update or delete on table violates foreign key constraint
IntegrityError: Foreign key constraint

tests/test_api.py::test_pagination PASSED                                      [16%]
[DEBUG] 2024-01-15 10:24:05 - Query: SELECT * FROM items LIMIT 20 OFFSET 0
[INFO] 2024-01-15 10:24:05 - Page 1/5 retrieved
FAILED tests/test_api.py::test_rate_limiting - AssertionError: Expected 429, got 200
[ERROR] 2024-01-15 10:24:06 - Rate limiting not enforced
[STACK TRACE]
Traceback (most recent call last):
  File "/app/tests/test_api.py", line 289, in test_rate_limiting
    assert response.status_code == 429
AssertionError: Expected 429, got 200

tests/test_cache.py::test_cache_expiration PASSED                              [17%]
[DEBUG] 2024-01-15 10:24:07 - Cache key expired after TTL
FAILED tests/test_cache.py::test_cache_invalidation - AssertionError: Stale data returned
[ERROR] 2024-01-15 10:24:08 - Cache invalidation did not work as expected
[STACK TRACE]
Traceback (most recent call last):
  File "/app/tests/test_cache.py", line 145, in test_cache_invalidation
    assert cache.get("user_123") is None
AssertionError: Stale data returned

tests/test_payments.py::test_refund_initiation PASSED                          [18%]
[INFO] 2024-01-15 10:24:09 - Refund initiated: $49.99 USD
FAILED tests/test_payments.py::test_refund_processing - APIError: Stripe API returned 500
[ERROR] 2024-01-15 10:24:10 - Refund processing failed
[STACK TRACE]
Traceback (most recent call last):
  File "/app/tests/test_payments.py", line 234, in test_refund_processing
    refund = stripe_client.process_refund(charge_id)
  File "/app/payments/stripe_client.py", line 178, in process_refund
    raise APIError("Stripe API returned 500")
APIError: Stripe API returned 500

tests/test_monitoring.py::test_metrics_collection PASSED                       [19%]
[DEBUG] 2024-01-15 10:24:11 - Collected 45 metrics
tests/test_monitoring.py::test_alert_configuration PASSED                      [20%]
[DEBUG] 2024-01-15 10:24:11 - Alert threshold configured: CPU > 80%
FAILED tests/test_monitoring.py::test_alert_threshold - AssertionError: Alert not triggered
[ERROR] 2024-01-15 10:24:12 - Alert should have been triggered but wasn't
[STACK TRACE]
Traceback (most recent call last):
  File "/app/tests/test_monitoring.py", line 89, in test_alert_threshold
    assert alert_triggered is True
AssertionError: Alert not triggered

tests/test_logging.py::test_log_formatting PASSED                              [21%]
[DEBUG] 2024-01-15 10:24:13 - Log format validated
tests/test_logging.py::test_log_rotation PASSED                                [22%]
[DEBUG] 2024-01-15 10:24:13 - Log file rotated successfully
tests/test_error_handling.py::test_ERROR_constant PASSED                       [23%]
[DEBUG] 2024-01-15 10:24:14 - Testing ERROR_CODE constant = 500
[INFO] 2024-01-15 10:24:14 - Error handling test passed
tests/test_utils.py::test_string_utils PASSED                                  [24%]
[DEBUG] 2024-01-15 10:24:15 - String utility functions validated
# Testing ERROR_CODE = 500 scenario in error handling module
tests/test_utils.py::test_date_utils PASSED                                    [25%]
[DEBUG] 2024-01-15 10:24:15 - Date parsing successful
LOGEOF

# Now add massive amounts of realistic noise to make it 8000+ lines
for i in {1..300}; do
    cat >> "$LOG_FILE" << 'NOISEEOF'
tests/test_integration_NOISEEOF
    echo "module_$i.py::test_scenario_$((i % 50)) PASSED                             [$((26 + i % 50))%]" >> "$LOG_FILE"
    echo "[DEBUG] 2024-01-15 10:24:$((16 + i % 44)) - Query execution: SELECT * FROM table_$i WHERE id > $((i * 100)) (0.$((RANDOM % 999))s)" >> "$LOG_FILE"
    echo "[INFO] 2024-01-15 10:24:$((16 + i % 44)) - Retrieved $((i * 3 % 500)) records from database" >> "$LOG_FILE"
    echo "[DEBUG] 2024-01-15 10:24:$((16 + i % 44)) - HTTP Request: GET /api/v1/resource_$i - Status: 200" >> "$LOG_FILE"
    echo "[INFO] 2024-01-15 10:24:$((16 + i % 44)) - Response time: 0.$((RANDOM % 999))s" >> "$LOG_FILE"
    
    if [ $((i % 10)) -eq 0 ]; then
        echo "[WARN] 2024-01-15 10:24:$((16 + i % 44)) - Slow query detected (>1s)" >> "$LOG_FILE"
    fi
    
    if [ $((i % 15)) -eq 0 ]; then
        echo "[DEBUG] 2024-01-15 10:24:$((16 + i % 44)) - Cache hit for key: cache_key_$i" >> "$LOG_FILE"
    fi
    
    if [ $((i % 7)) -eq 0 ]; then
        echo "# Logging test ERROR message - this should be ignored" >> "$LOG_FILE"
        echo "[INFO] 2024-01-15 10:24:$((16 + i % 44)) - Testing error handling with ERROR constant" >> "$LOG_FILE"
    fi
done

# Add more passing tests at the end
for i in {1..150}; do
    echo "tests/test_final_module.py::test_case_$i PASSED                             [99%]" >> "$LOG_FILE"
    echo "[DEBUG] 2024-01-15 10:25:$((i % 60)) - Test case $i completed successfully" >> "$LOG_FILE"
done

cat >> "$LOG_FILE" << 'ENDEOF'

================================= SUMMARY =================================
487 tests: 475 passed, 12 failed in 847.32s (0:14:07)
===========================================================================
ENDEOF

sudo chown ga:ga "$LOG_FILE"

echo "Generated test log with $(wc -l < "$LOG_FILE") lines"

# Open VSCode with the log file
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$LOG_FILE'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Analyze Test Failures Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. The file test_output.log is open in VSCode (~8200 lines)"
echo "  2. Use Ctrl+F or search features to find all 'FAILED' test lines"
echo "  3. Extract test names and error types"
echo "  4. Create summary at: /home/ga/workspace/test_failures_summary.txt"
echo "  5. Organize by error category and keep it concise"