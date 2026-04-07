#!/bin/bash
# Setup script for Clinical Statistical Hypothesis Testing task
# Downloads UCI Heart Disease dataset, cleans it, and loads it into Oracle

set -e

echo "=== Setting up Clinical Statistics Task ==="

source /workspace/scripts/task_utils.sh

# --- Pre-flight Checks ---
echo "[1/5] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Create RESEARCH User ---
echo "[2/5] Creating RESEARCH user..."
oracle_query "
-- Drop user if exists
BEGIN
  EXECUTE IMMEDIATE 'DROP USER research CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
CREATE USER research IDENTIFIED BY research123 DEFAULT TABLESPACE users QUOTA UNLIMITED ON users;
GRANT CONNECT, RESOURCE, CREATE VIEW TO research;
GRANT EXECUTE ON DBMS_STATS TO research;
" "system" > /dev/null

# --- Download and Prepare Data ---
echo "[3/5] Downloading UCI Heart Disease dataset..."
DATA_DIR="/tmp/heart_data"
mkdir -p "$DATA_DIR"
curl -sL "https://archive.ics.uci.edu/ml/machine-learning-databases/heart-disease/processed.cleveland.data" -o "$DATA_DIR/raw.data"

# --- Load Data via Python ---
# We use Python to handle the '?' missing values and insert cleanly
echo "[4/5] Loading data into HEART_PATIENTS table..."
python3 << 'PYEOF'
import oracledb
import csv

# Connect as RESEARCH user
try:
    conn = oracledb.connect(user="research", password="research123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Create Table
    cursor.execute("""
        CREATE TABLE heart_patients (
            age NUMBER,
            sex NUMBER,
            cp NUMBER,
            trestbps NUMBER,
            chol NUMBER,
            fbs NUMBER,
            restecg NUMBER,
            thalach NUMBER,
            exang NUMBER,
            oldpeak NUMBER,
            slope NUMBER,
            ca NUMBER,
            thal NUMBER,
            diagnosis NUMBER
        )
    """)

    # Parse and Load
    rows_to_insert = []
    with open('/tmp/heart_data/raw.data', 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) < 14: continue
            
            # Clean data: '?' -> None (NULL), float conversion
            cleaned_row = []
            for val in row:
                val = val.strip()
                if val == '?':
                    cleaned_row.append(None)
                else:
                    try:
                        cleaned_row.append(float(val))
                    except ValueError:
                        cleaned_row.append(None)
            
            rows_to_insert.append(tuple(cleaned_row))

    cursor.executemany("""
        INSERT INTO heart_patients VALUES (
            :1, :2, :3, :4, :5, :6, :7, :8, :9, :10, :11, :12, :13, :14
        )
    """, rows_to_insert)
    
    conn.commit()
    print(f"Loaded {len(rows_to_insert)} patient records.")
    
    cursor.close()
    conn.close()

except Exception as e:
    print(f"Error loading data: {e}")
    exit(1)
PYEOF

# --- Record Initial State ---
echo "[5/5] Recording initial state..."
date +%s > /tmp/task_start_timestamp

# Ensure DBeaver is installed (standard for environment, but good to check)
if ! which dbeaver-ce > /dev/null 2>&1; then
    echo "Installing DBeaver..."
    sudo snap install dbeaver-ce --classic 2>/dev/null || true
fi

# Take startup screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "User: RESEARCH / research123"
echo "Table: HEART_PATIENTS loaded"