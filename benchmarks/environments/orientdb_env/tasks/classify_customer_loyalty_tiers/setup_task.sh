#!/bin/bash
set -euo pipefail

echo "=== Setup: classify_customer_loyalty_tiers ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh
wait_for_orientdb 90

rm -f /tmp/classify_customer_loyalty_tiers_result.json \
      /tmp/classify_customer_loyalty_tiers_baseline.json \
      /tmp/task_start_timestamp 2>/dev/null || true

sql_count() {
    local query="$1"
    orientdb_sql "demodb" "$query" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('result',[{}])[0].get('cnt',0))" 2>/dev/null || echo "0"
}

ensure_profile() {
    local email="$1" name="$2" surname="$3" gender="$4" bday="$5" nationality="$6"
    local cnt
    cnt=$(sql_count "SELECT COUNT(*) as cnt FROM Profiles WHERE Email='${email}'")
    if [ "$cnt" = "0" ]; then
        orientdb_sql "demodb" "INSERT INTO Profiles SET Email='${email}', Name='${name}', Surname='${surname}', Gender='${gender}', Birthday='${bday}', Nationality='${nationality}'" >/dev/null 2>&1 || true
    fi
}

# Ensure cohort profiles exist
ensure_profile "yuki.tanaka@example.com"     "Yuki"   "Tanaka"    "Female" "1995-04-12" "Japanese"
ensure_profile "carlos.lopez@example.com"    "Carlos" "Lopez"     "Male"   "1987-06-07" "Mexican"
ensure_profile "thomas.schafer@example.com"  "Thomas" "Schafer"   "Male"   "1970-05-05" "German"
ensure_profile "piet.vanderberg@example.com" "Piet"   "Vanderberg" "Male"  "1980-02-14" "Dutch"

# Clean up prior task-specific orders (IDs 21-26) and their edges
orientdb_sql "demodb" "DELETE EDGE HasOrder WHERE in.OrderedId IN [21,22,23,24,25,26]" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DELETE VERTEX Orders WHERE OrderedId IN [21,22,23,24,25,26]" >/dev/null 2>&1 || true

# Create deterministic orders for each cohort profile
# yuki.tanaka: 2 Completed orders -> TotalSpend = 4500.0 -> Gold
orientdb_sql "demodb" "INSERT INTO Orders SET OrderedId=21, Date='2025-01-10', Status='Completed', Price=2600.0" >/dev/null 2>&1 || true
orientdb_sql "demodb" "INSERT INTO Orders SET OrderedId=22, Date='2025-02-15', Status='Completed', Price=1900.0" >/dev/null 2>&1 || true

# carlos.lopez: 1 Completed order -> TotalSpend = 900.0 -> Bronze
orientdb_sql "demodb" "INSERT INTO Orders SET OrderedId=23, Date='2025-01-20', Status='Completed', Price=900.0" >/dev/null 2>&1 || true

# thomas.schafer: 2 Completed orders -> TotalSpend = 2000.0 -> Silver (CompletedOrderCount >= 2)
orientdb_sql "demodb" "INSERT INTO Orders SET OrderedId=24, Date='2025-01-05', Status='Completed', Price=1200.0" >/dev/null 2>&1 || true
orientdb_sql "demodb" "INSERT INTO Orders SET OrderedId=25, Date='2025-02-01', Status='Completed', Price=800.0" >/dev/null 2>&1 || true

# piet.vanderberg: 1 Completed order -> TotalSpend = 1700.0 -> Silver (TotalSpend >= 1500 AND < 4000)
orientdb_sql "demodb" "INSERT INTO Orders SET OrderedId=26, Date='2025-01-25', Status='Completed', Price=1700.0" >/dev/null 2>&1 || true

# Create HasOrder edges (Profile -> Orders)
orientdb_sql "demodb" "CREATE EDGE HasOrder FROM (SELECT FROM Profiles WHERE Email='yuki.tanaka@example.com') TO (SELECT FROM Orders WHERE OrderedId=21)" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasOrder FROM (SELECT FROM Profiles WHERE Email='yuki.tanaka@example.com') TO (SELECT FROM Orders WHERE OrderedId=22)" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasOrder FROM (SELECT FROM Profiles WHERE Email='carlos.lopez@example.com') TO (SELECT FROM Orders WHERE OrderedId=23)" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasOrder FROM (SELECT FROM Profiles WHERE Email='thomas.schafer@example.com') TO (SELECT FROM Orders WHERE OrderedId=24)" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasOrder FROM (SELECT FROM Profiles WHERE Email='thomas.schafer@example.com') TO (SELECT FROM Orders WHERE OrderedId=25)" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasOrder FROM (SELECT FROM Profiles WHERE Email='piet.vanderberg@example.com') TO (SELECT FROM Orders WHERE OrderedId=26)" >/dev/null 2>&1 || true

# Remove prior LoyaltyTier artifacts
orientdb_sql "demodb" "DELETE VERTEX LoyaltyTier" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX LoyaltyTier.CustomerEmail" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS LoyaltyTier UNSAFE" >/dev/null 2>&1 || true

# Baseline snapshot
cat > /tmp/classify_customer_loyalty_tiers_baseline.json << 'EOF'
{
  "loyalty_tier_count": 0
}
EOF

date +%s > /tmp/task_start_timestamp

kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 8
take_screenshot /tmp/task_start_classify_customer_loyalty_tiers.png

echo "=== Setup complete: classify_customer_loyalty_tiers ==="
