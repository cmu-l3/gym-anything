#!/bin/bash
echo "=== Setting up Clickstream Funnel Analysis task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# 1. Verify Oracle is running
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# 2. Clean up and recreate CLICK_ANALYST schema
echo "Setting up CLICK_ANALYST schema..."
oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER click_analyst CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

sleep 2

oracle_query "CREATE USER click_analyst IDENTIFIED BY Click2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO click_analyst;
GRANT RESOURCE TO click_analyst;
GRANT CREATE VIEW TO click_analyst;
GRANT CREATE MATERIALIZED VIEW TO click_analyst;
GRANT CREATE PROCEDURE TO click_analyst;
GRANT CREATE SESSION TO click_analyst;
GRANT CREATE TABLE TO click_analyst;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create click_analyst user"
    exit 1
fi

# 3. Create tables and generate realistic data
echo "Creating tables and generating clickstream data (this may take ~30 seconds)..."

sudo docker exec -i oracle-xe sqlplus -s click_analyst/Click2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET SERVEROUTPUT ON
SET FEEDBACK OFF

CREATE TABLE users (
    user_id        NUMBER PRIMARY KEY,
    first_seen     TIMESTAMP,
    device_type    VARCHAR2(20),
    browser        VARCHAR2(30),
    country        VARCHAR2(50),
    referral_source VARCHAR2(30)
);

CREATE TABLE products (
    product_id     NUMBER PRIMARY KEY,
    product_name   VARCHAR2(100),
    category       VARCHAR2(50),
    price          NUMBER(10,2),
    brand          VARCHAR2(50)
);

CREATE TABLE events (
    event_id       NUMBER PRIMARY KEY,
    user_id        NUMBER REFERENCES users(user_id),
    event_type     VARCHAR2(30),
    event_timestamp TIMESTAMP,
    page_url       VARCHAR2(200),
    product_id     NUMBER,
    event_value    NUMBER(10,2)
);

-- Generate realistic data
DECLARE
    v_event_id NUMBER := 1;
    v_ts TIMESTAMP;
    v_session_count NUMBER;
    v_funnel_depth NUMBER;
    v_prod_id NUMBER;
    v_users NUMBER := 1000;
    v_prods NUMBER := 50;
BEGIN
    -- 1. Insert Products
    FOR p IN 1..v_prods LOOP
        INSERT INTO products VALUES (p, 'Product '||p, 'Category '||MOD(p, 5), ROUND(DBMS_RANDOM.VALUE(15, 250), 2), 'Brand '||MOD(p, 3));
    END LOOP;

    -- 2. Insert Users and Events
    FOR u IN 1..v_users LOOP
        INSERT INTO users VALUES (u, SYSTIMESTAMP - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(10, 90), 'DAY'), 
                                  CASE MOD(u, 3) WHEN 0 THEN 'mobile' WHEN 1 THEN 'desktop' ELSE 'tablet' END,
                                  'chrome', 'US', 'organic');
        
        -- Simulate 1 to 6 sessions per user over their lifetime
        v_session_count := ROUND(DBMS_RANDOM.VALUE(1, 6));
        
        FOR s IN 1..v_session_count LOOP
            v_ts := SYSTIMESTAMP - NUMTODSINTERVAL(DBMS_RANDOM.VALUE(1, 90), 'DAY');
            
            -- Session start (page_view)
            INSERT INTO events VALUES (v_event_id, u, 'page_view', v_ts, '/home', NULL, NULL);
            v_event_id := v_event_id + 1;
            v_ts := v_ts + NUMTODSINTERVAL(DBMS_RANDOM.VALUE(5, 120), 'SECOND');
            
            -- Funnel logic
            v_funnel_depth := DBMS_RANDOM.VALUE(0, 100);
            IF v_funnel_depth > 40 THEN  -- 60% view product
                v_prod_id := ROUND(DBMS_RANDOM.VALUE(1, v_prods));
                INSERT INTO events VALUES (v_event_id, u, 'product_view', v_ts, '/product/'||v_prod_id, v_prod_id, NULL);
                v_event_id := v_event_id + 1;
                v_ts := v_ts + NUMTODSINTERVAL(DBMS_RANDOM.VALUE(30, 240), 'SECOND');
                
                IF v_funnel_depth > 70 THEN  -- 30% add to cart
                    INSERT INTO events VALUES (v_event_id, u, 'add_to_cart', v_ts, '/cart', v_prod_id, NULL);
                    v_event_id := v_event_id + 1;
                    v_ts := v_ts + NUMTODSINTERVAL(DBMS_RANDOM.VALUE(15, 60), 'SECOND');
                    
                    IF v_funnel_depth > 85 THEN  -- 15% checkout start
                        INSERT INTO events VALUES (v_event_id, u, 'checkout_start', v_ts, '/checkout', NULL, NULL);
                        v_event_id := v_event_id + 1;
                        v_ts := v_ts + NUMTODSINTERVAL(DBMS_RANDOM.VALUE(45, 180), 'SECOND');
                        
                        IF v_funnel_depth > 93 THEN  -- 7% purchase (approx industry avg)
                            INSERT INTO events VALUES (v_event_id, u, 'purchase', v_ts, '/checkout/success', v_prod_id, ROUND(DBMS_RANDOM.VALUE(15, 250), 2));
                            v_event_id := v_event_id + 1;
                        END IF;
                    END IF;
                END IF;
            END IF;
        END LOOP;
    END LOOP;
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Generated ' || (v_event_id - 1) || ' events for ' || v_users || ' users.');
END;
/
EXIT;
EOSQL

echo "Data generation complete."

# 4. Pre-configure SQL Developer Connection
SQLDEVELOPER_SYSTEM_DIR=$(find /home/ga/.sqldeveloper -maxdepth 1 -name "system*" -type d 2>/dev/null | head -1)
if [ -n "$SQLDEVELOPER_SYSTEM_DIR" ]; then
    CONN_DIR="$SQLDEVELOPER_SYSTEM_DIR/o.jdeveloper.db.connection.24.2.0.284.2209"
    mkdir -p "$CONN_DIR"
    CONN_FILE="$CONN_DIR/connections.json"
    
    cat > "$CONN_FILE" << 'CONNEOF'
{
  "connections": [
    {
      "name": "Clickstream Database",
      "type": "jdbc",
      "info": {
        "role": "",
        "SavePassword": "true",
        "OracleConnectionType": "BASIC",
        "RaptorConnectionType": "Oracle",
        "customUrl": "jdbc:oracle:thin:@localhost:1521/XEPDB1",
        "hostname": "localhost",
        "driver": "oracle.jdbc.OracleDriver",
        "port": "1521",
        "subtype": "oraJDBC",
        "ConnName": "Clickstream Database",
        "serviceName": "XEPDB1",
        "user": "click_analyst",
        "password": "Click2024"
      }
    }
  ]
}
CONNEOF
    chown -R ga:ga /home/ga/.sqldeveloper
fi

# 5. Start SQL Developer
if ! pgrep -f "sqldeveloper" > /dev/null; then
    echo "Starting SQL Developer..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper > /tmp/sqldeveloper.log 2>&1 &"
    
    # Wait for window
    for i in {1..60}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "sql developer\|oracle sql"; then
            echo "SQL Developer window detected"
            break
        fi
        sleep 1
    done
fi

sleep 5
# Maximize window
DISPLAY=:1 wmctrl -r "Oracle SQL Developer" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Oracle SQL Developer" 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="