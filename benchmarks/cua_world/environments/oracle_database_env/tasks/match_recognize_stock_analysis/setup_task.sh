#!/bin/bash
# Setup for match_recognize_stock_analysis
# Creates STOCK_PRICES table and populates it with a specific V-shape pattern

set -e

echo "=== Setting up Stock Analysis Task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_timestamp

# --- 1. Verify Database Connection ---
echo "Verifying database connection..."
if ! wait_for_oracle 60; then
    echo "ERROR: Database not ready"
    exit 1
fi

# --- 2. Clean up previous run artifacts ---
rm -f /home/ga/Desktop/reversal_patterns.csv
rm -f /home/ga/Desktop/find_patterns.sql

# --- 3. Create and Populate STOCK_PRICES table ---
echo "Creating and populating STOCK_PRICES table..."

# We plant a clear V-shape pattern:
# 2026-02-03: 154.67 (Start/Peak)
# 2026-02-04: 146.67 (Down 1)
# 2026-02-05: 136.48 (Down 2, Bottom, ~11.7% drop from peak)
# 2026-02-06: 142.82 (Up 1)
# 2026-02-09: 156.59 (Up 2, End)

oracle_query "
BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE stock_prices';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

CREATE TABLE stock_prices (
    symbol VARCHAR2(10),
    trade_date DATE,
    open_price NUMBER,
    high_price NUMBER,
    low_price NUMBER,
    close_price NUMBER,
    volume NUMBER
);

-- Pre-pattern noise
INSERT INTO stock_prices VALUES ('ORCL', TO_DATE('2026-01-28', 'YYYY-MM-DD'), 148.50, 150.00, 148.00, 149.20, 1000000);
INSERT INTO stock_prices VALUES ('ORCL', TO_DATE('2026-01-29', 'YYYY-MM-DD'), 149.20, 151.00, 149.00, 150.50, 1100000);
INSERT INTO stock_prices VALUES ('ORCL', TO_DATE('2026-01-30', 'YYYY-MM-DD'), 150.50, 152.00, 150.00, 151.80, 1200000);
INSERT INTO stock_prices VALUES ('ORCL', TO_DATE('2026-02-02', 'YYYY-MM-DD'), 151.80, 153.00, 151.00, 152.00, 1050000);

-- START OF PATTERN (Peak)
INSERT INTO stock_prices VALUES ('ORCL', TO_DATE('2026-02-03', 'YYYY-MM-DD'), 152.00, 155.00, 151.50, 154.67, 1500000);

-- DOWN LEG (2 days)
INSERT INTO stock_prices VALUES ('ORCL', TO_DATE('2026-02-04', 'YYYY-MM-DD'), 154.67, 154.67, 145.00, 146.67, 3000000); -- Drop
INSERT INTO stock_prices VALUES ('ORCL', TO_DATE('2026-02-05', 'YYYY-MM-DD'), 146.67, 147.00, 135.00, 136.48, 4500000); -- Drop (Bottom)

-- UP LEG (2 days)
INSERT INTO stock_prices VALUES ('ORCL', TO_DATE('2026-02-06', 'YYYY-MM-DD'), 136.48, 143.00, 136.00, 142.82, 3200000); -- Rise
INSERT INTO stock_prices VALUES ('ORCL', TO_DATE('2026-02-09', 'YYYY-MM-DD'), 142.82, 157.00, 142.00, 156.59, 2800000); -- Rise (End)

-- Post-pattern noise
INSERT INTO stock_prices VALUES ('ORCL', TO_DATE('2026-02-10', 'YYYY-MM-DD'), 156.59, 158.00, 155.00, 155.00, 1200000);
INSERT INTO stock_prices VALUES ('ORCL', TO_DATE('2026-02-11', 'YYYY-MM-DD'), 155.00, 156.00, 154.00, 154.50, 1000000);

COMMIT;
" "hr"

# --- 4. Ensure DBeaver is ready (optional but helpful) ---
if ! which dbeaver-ce > /dev/null 2>&1; then
    echo "Installing DBeaver..."
    sudo snap install dbeaver-ce --classic 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "Setup complete. STOCK_PRICES table ready in HR schema."