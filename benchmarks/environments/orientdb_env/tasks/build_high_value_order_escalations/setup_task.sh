#!/bin/bash
set -euo pipefail

echo "=== Setup: build_high_value_order_escalations ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh
wait_for_orientdb 90

rm -f /tmp/build_high_value_order_escalations_result.json \
      /tmp/build_high_value_order_escalations_baseline.json \
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

ensure_profile "anna.mueller@example.com" "Anna" "Mueller" "Female" "1983-09-25" "German"
ensure_profile "james.brown@example.com" "James" "Brown" "Male" "1975-08-03" "Australian"
ensure_profile "clara.dubois@example.com" "Clara" "Dubois" "Female" "1989-03-21" "French"

# Reset targeted orders to deterministic values
orientdb_sql "demodb" "DELETE EDGE HasOrder WHERE in.OrderedId IN [3,7,10]" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DELETE VERTEX Orders WHERE OrderedId IN [3,7,10]" >/dev/null 2>&1 || true

orientdb_sql "demodb" "INSERT INTO Orders SET OrderedId=3, Date='2024-05-10', Status='Pending', Price=2100.0" >/dev/null 2>&1 || true
orientdb_sql "demodb" "INSERT INTO Orders SET OrderedId=7, Date='2024-07-04', Status='Pending', Price=3200.0" >/dev/null 2>&1 || true
orientdb_sql "demodb" "INSERT INTO Orders SET OrderedId=10, Date='2024-08-30', Status='Completed', Price=1870.5" >/dev/null 2>&1 || true

# Owner mapping via HasOrder
orientdb_sql "demodb" "CREATE EDGE HasOrder FROM (SELECT FROM Profiles WHERE Email='anna.mueller@example.com') TO (SELECT FROM Orders WHERE OrderedId=3)" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasOrder FROM (SELECT FROM Profiles WHERE Email='james.brown@example.com') TO (SELECT FROM Orders WHERE OrderedId=7)" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasOrder FROM (SELECT FROM Profiles WHERE Email='clara.dubois@example.com') TO (SELECT FROM Orders WHERE OrderedId=10)" >/dev/null 2>&1 || true

# Remove prior escalation artifacts
orientdb_sql "demodb" "DELETE EDGE EscalatesOrder" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS EscalatesOrder UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DELETE VERTEX OrderEscalation" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS OrderEscalation UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX OrderEscalation.OrderedId" >/dev/null 2>&1 || true

# Baseline snapshot for anti-gaming verification
cat > /tmp/build_high_value_order_escalations_baseline.json << 'EOF'
{
  "escalation_count": 0,
  "escalation_edge_count": 0
}
EOF

date +%s > /tmp/task_start_timestamp

kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 8
take_screenshot /tmp/task_start_build_high_value_order_escalations.png

echo "=== Setup complete: build_high_value_order_escalations ==="
