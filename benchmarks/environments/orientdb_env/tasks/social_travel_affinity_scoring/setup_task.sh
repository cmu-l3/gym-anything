#!/bin/bash
echo "=== Setting up social_travel_affinity_scoring task ==="

# Ensure safe PATH
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB
wait_for_orientdb 60

echo "Configuring deterministic dataset..."

# 1. Clean up previous runs (Drop HasVisited if exists to force agent to create it)
if orientdb_class_exists "demodb" "HasVisited"; then
    echo "Dropping existing HasVisited class..."
    orientdb_sql "demodb" "DROP CLASS HasVisited UNSAFE" > /dev/null
fi

# 2. Remove specific test users if they exist
for email in "task_user_a@test.com" "task_user_b@test.com" "task_user_c@test.com"; do
    orientdb_sql "demodb" "DELETE VERTEX Profiles WHERE Email = '$email'" > /dev/null
done

# 3. Create Test Users
# User A: Visits Italy (Artemide) and France (Crillon)
# User B: Visits Italy (Danieli) and Germany (Adlon)
# User C: No visits
echo "Creating test profiles..."
orientdb_sql "demodb" "INSERT INTO Profiles SET Email='task_user_a@test.com', Name='Alice', Surname='Tasker', Gender='Female', Nationality='American'" > /dev/null
orientdb_sql "demodb" "INSERT INTO Profiles SET Email='task_user_b@test.com', Name='Bob', Surname='Builder', Gender='Male', Nationality='British'" > /dev/null
orientdb_sql "demodb" "INSERT INTO Profiles SET Email='task_user_c@test.com', Name='Charlie', Surname='Check', Gender='Male', Nationality='Canadian'" > /dev/null

# 4. Create Stays (User -> Hotel)
# Note: Hotels are pre-seeded in env. 
# Hotel Artemide (Rome, Italy)
# Hotel de Crillon (Paris, France)
# Hotel Danieli (Venice, Italy)
# Hotel Adlon Kempinski (Berlin, Germany)

echo "Creating stays..."
# Alice -> Artemide (Italy)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='task_user_a@test.com') TO (SELECT FROM Hotels WHERE Name='Hotel Artemide')" > /dev/null
# Alice -> Crillon (France)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='task_user_a@test.com') TO (SELECT FROM Hotels WHERE Name='Hotel de Crillon')" > /dev/null

# Bob -> Danieli (Italy)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='task_user_b@test.com') TO (SELECT FROM Hotels WHERE Name='Hotel Danieli')" > /dev/null
# Bob -> Adlon (Germany)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='task_user_b@test.com') TO (SELECT FROM Hotels WHERE Name='Hotel Adlon Kempinski')" > /dev/null

# 5. Create Friendships
# Alice <-> Bob (Should have Jaccard ~0.33: Italy / {Italy, France, Germany})
# Bob <-> Charlie (Should have Jaccard 0: {Italy, Germany} / {})
echo "Creating friendships..."
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='task_user_a@test.com') TO (SELECT FROM Profiles WHERE Email='task_user_b@test.com')" > /dev/null
orientdb_sql "demodb" "CREATE EDGE HasFriend FROM (SELECT FROM Profiles WHERE Email='task_user_b@test.com') TO (SELECT FROM Profiles WHERE Email='task_user_c@test.com')" > /dev/null

# 6. Ensure Countries exist (They should from seed_demodb.py, but just in case)
# The seed script creates: Italy, France, Germany.

# Launch Firefox to OrientDB Studio
echo "Launching Firefox to OrientDB Studio..."
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"
sleep 5

# Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="