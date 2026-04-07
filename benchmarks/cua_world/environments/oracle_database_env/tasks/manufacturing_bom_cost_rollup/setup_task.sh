#!/bin/bash
# Setup for manufacturing_bom_cost_rollup task
# Creates MFG_PARTS and MFG_BOM tables with a realistic hardware hierarchy

set -e

echo "=== Setting up Manufacturing BOM Task ==="

source /workspace/scripts/task_utils.sh

# --- 1. Verify Oracle is running ---
echo "[1/4] Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- 2. Clean up prior artifacts ---
echo "[2/4] Cleaning up old tables and views..."
oracle_query "
BEGIN
  EXECUTE IMMEDIATE 'DROP VIEW assembly_cost_analysis';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE mfg_bom CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
BEGIN
  EXECUTE IMMEDIATE 'DROP TABLE mfg_parts CASCADE CONSTRAINTS';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/" "hr" > /dev/null 2>&1 || true

rm -f /home/ga/Desktop/top_expensive_products.csv

# --- 3. Create Tables and Insert Data ---
echo "[3/4] Creating Manufacturing Schema..."

# We use a python script to insert data cleanly to avoid escaping hell in bash
python3 << 'PYEOF'
import oracledb

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # Create Tables
    cursor.execute("""
        CREATE TABLE mfg_parts (
            part_id     NUMBER PRIMARY KEY,
            part_name   VARCHAR2(100),
            part_type   VARCHAR2(20) CHECK (part_type IN ('RAW', 'ASSEMBLY')),
            unit_cost   NUMBER(10, 2) -- Only populated for RAW, NULL or 0 for ASSEMBLY initially
        )
    """)
    
    cursor.execute("""
        CREATE TABLE mfg_bom (
            parent_id   NUMBER,
            child_id    NUMBER,
            quantity    NUMBER,
            CONSTRAINT bom_pk PRIMARY KEY (parent_id, child_id),
            CONSTRAINT bom_parent_fk FOREIGN KEY (parent_id) REFERENCES mfg_parts(part_id),
            CONSTRAINT bom_child_fk FOREIGN KEY (child_id) REFERENCES mfg_parts(part_id)
        )
    """)

    # Insert Data
    # Hierarchy:
    # Level 0 (Raw Materials)
    # 1: Steel Sheet ($5)
    # 2: Screw ($0.10)
    # 3: Plastic Granules ($2)
    # 4: CPU Core ($50)
    # 5: RAM Chip ($20)
    # 6: Copper Wire ($1)
    
    parts_data = [
        (1, 'Steel Sheet', 'RAW', 5.00),
        (2, 'Screw M4', 'RAW', 0.10),
        (3, 'Plastic Granules', 'RAW', 2.00),
        (4, 'CPU Core', 'RAW', 50.00),
        (5, 'RAM Chip', 'RAW', 20.00),
        (6, 'Copper Wire', 'RAW', 1.00),
        
        (10, 'Case Frame', 'ASSEMBLY', 0),
        (11, 'Motherboard PCB', 'ASSEMBLY', 0),
        (20, 'CPU Module', 'ASSEMBLY', 0),
        (21, 'RAM Stick', 'ASSEMBLY', 0),
        (30, 'Server X1', 'ASSEMBLY', 0)
    ]
    
    cursor.executemany("INSERT INTO mfg_parts VALUES (:1, :2, :3, :4)", parts_data)
    
    # BOM Relationships
    # Parent, Child, Qty
    bom_data = [
        # Level 1 Assemblies
        (10, 1, 1),   # Case Frame needs 1 Steel Sheet
        (10, 2, 20),  # Case Frame needs 20 Screws -> Cost: 5 + 2 = 7
        
        (11, 3, 1),   # PCB needs 1 Plastic
        (11, 6, 2),   # PCB needs 2 Copper Wire -> Cost: 2 + 2 = 4
        
        # Level 2 Assemblies
        (20, 4, 8),   # CPU Module needs 8 Cores
        (20, 11, 1),  # CPU Module needs 1 PCB -> Cost: 400 + 4 = 404
        
        (21, 5, 8),   # RAM Stick needs 8 RAM Chips
        (21, 11, 1),  # RAM Stick needs 1 PCB -> Cost: 160 + 4 = 164
        
        # Level 3 Finished Product
        (30, 10, 1),  # Server X1 needs 1 Case ($7)
        (30, 20, 2),  # Server X1 needs 2 CPU Modules ($808)
        (30, 21, 4),  # Server X1 needs 4 RAM Sticks ($656)
        (30, 2, 50)   # Server X1 needs 50 Screws ($5) -> Total: 1476
    ]
    
    cursor.executemany("INSERT INTO mfg_bom VALUES (:1, :2, :3)", bom_data)
    
    conn.commit()
    print("Schema created and data populated successfully.")
    
except Exception as e:
    print(f"Error: {e}")
    exit(1)
PYEOF

# --- 4. Final Setup ---
echo "[4/4] Finalizing setup..."
date +%s > /tmp/task_start_time
chmod 644 /tmp/task_start_time

# Ensure DBeaver is running/ready for the agent
if ! pgrep -f "dbeaver" > /dev/null; then
    su - ga -c "DISPLAY=:1 /usr/bin/dbeaver-ce &" > /dev/null 2>&1 || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="