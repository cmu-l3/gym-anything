#!/bin/bash
set -euo pipefail

echo "=== Setup: collaborative_filtering_recommendation_engine ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin

source /workspace/scripts/task_utils.sh
wait_for_orientdb 90

rm -f /tmp/collaborative_filtering_recommendation_engine_result.json \
      /tmp/collaborative_filtering_recommendation_engine_baseline.json \
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

ensure_hotel() {
    local name="$1" htype="$2" phone="$3" lat="$4" lon="$5" street="$6" city="$7" country="$8" stars="$9"
    local cnt
    cnt=$(sql_count "SELECT COUNT(*) as cnt FROM Hotels WHERE Name='${name}'")
    if [ "$cnt" = "0" ]; then
        orientdb_sql "demodb" "INSERT INTO Hotels SET Name='${name}', Type='${htype}', Phone='${phone}', Latitude=${lat}, Longitude=${lon}, Street='${street}', City='${city}', Country='${country}', Stars=${stars}" >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------
# 1. Clean up prior task artifacts
# ---------------------------------------------------------------
orientdb_sql "demodb" "DELETE EDGE SimilarTraveler" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS SimilarTraveler UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DELETE VERTEX HotelRecommendation" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP INDEX HotelRecommendation.TargetEmail_HotelName" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS HotelRecommendation UNSAFE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DELETE VERTEX RecommendationReport" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS RecommendationReport UNSAFE" >/dev/null 2>&1 || true

# ---------------------------------------------------------------
# 2. Seed canonical hotels
# ---------------------------------------------------------------
# Drop Hotels.Id UNIQUE index to allow null-Id canonical inserts.
# The built-in OrientDB DemoDB Italian hotels have non-null OSM Id values in a Hotels.Id
# UNIQUE index. Canonical inserts don't specify Id (null), so INSERT #1 succeeds but
# INSERT #2 fails with UNIQUE constraint violation.
echo "Dropping Hotels.Id UNIQUE index to allow null-Id canonical inserts..."
orientdb_sql "demodb" "DROP INDEX Hotels.Id" >/dev/null 2>&1 || true

echo "Ensuring 15 canonical hotels..."
ensure_hotel "Hotel Artemide"               "Boutique"  "+39-06-4884-6000" "41.8981"  "12.4989"   "Via Nazionale 22"          "Rome"            "Italy"           "4"
ensure_hotel "Hotel Adlon Kempinski"        "Luxury"    "+49-30-2261-0"    "52.5162"  "13.3777"   "Unter den Linden 77"       "Berlin"          "Germany"         "5"
ensure_hotel "Hotel de Crillon"             "Palace"    "+33-1-44-71-15-00" "48.8679" "2.3215"    "Place de la Concorde 10"   "Paris"           "France"          "5"
ensure_hotel "The Savoy"                    "Luxury"    "+44-20-7836-4343" "51.5099"  "-0.1201"   "Strand"                    "London"          "United Kingdom"  "5"
ensure_hotel "The Plaza Hotel"              "Historic"  "+1-212-759-3000"  "40.7645"  "-73.9753"  "Fifth Avenue"              "New York"        "United States"   "5"
ensure_hotel "Park Hyatt Tokyo"             "Luxury"    "+81-3-5322-1234"  "35.6895"  "139.6933"  "Shinjuku 3-7-1-2"         "Tokyo"           "Japan"           "5"
ensure_hotel "Four Seasons Sydney"          "Luxury"    "+61-2-9250-3100"  "-33.8688" "151.2093"  "George Street 199"         "Sydney"          "Australia"       "5"
ensure_hotel "Copacabana Palace"            "Historic"  "+55-21-2548-7070" "-22.9697" "-43.1817"  "Av Atlantica 1702"         "Rio de Janeiro"  "Brazil"          "5"
ensure_hotel "Hotel Arts Barcelona"         "Boutique"  "+34-93-221-1000"  "41.3851"  "2.1967"    "Marina 19-21"              "Barcelona"       "Spain"           "5"
ensure_hotel "Grande Bretagne Hotel"        "Historic"  "+30-210-333-0000" "37.9754"  "23.7367"   "Syntagma Square 1"         "Athens"          "Greece"          "5"
ensure_hotel "Intercontinental Amsterdam"   "Luxury"    "+31-20-655-6262"  "52.3702"  "4.9076"    "Prof Tulpplein 1"          "Amsterdam"       "Netherlands"     "5"
ensure_hotel "Fairmont Le Manoir"           "Historic"  "+33-1-46-31-98-00" "48.8197" "2.2999"    "Route de Montrouge 1"      "Paris"           "France"          "4"
ensure_hotel "Hotel Villa d Este"           "Resort"    "+39-031-348-1"    "45.8440"  "9.0726"    "Via Regina 40"             "Cernobbio"       "Italy"           "5"
ensure_hotel "Baglioni Hotel Luna"          "Historic"  "+39-041-528-9840" "45.4341"  "12.3401"   "Riva degli Schiavoni 1243" "Venice"          "Italy"           "5"
ensure_hotel "Melia Berlin"                 "Business"  "+49-30-20607-0"   "52.5203"  "13.3867"   "Friedrichstrasse 103"      "Berlin"          "Germany"         "4"

# Remove Italian null-Country records left from DemoDB checkpoint.
# Must use DELETE VERTEX (not DELETE FROM) because Italian hotels have connected edges.
echo "Removing Italian null-Country records from Hotels..."
orientdb_sql "demodb" "DELETE VERTEX Hotels WHERE Country IS NULL" >/dev/null 2>&1 || true
sleep 2

# ---------------------------------------------------------------
# 3. Ensure canonical profiles
# ---------------------------------------------------------------
# Drop Profiles.Id UNIQUE index (same issue as Hotels.Id: null-Id INSERTs after
# the first one fail with UNIQUE constraint violation).
echo "Dropping Profiles.Id UNIQUE index to allow null-Id canonical inserts..."
orientdb_sql "demodb" "DROP INDEX Profiles.Id" >/dev/null 2>&1 || true

echo "Ensuring 15 canonical profiles..."
ensure_profile "john.smith@example.com"       "John"    "Smith"       "Male"   "1985-03-15" "American"
ensure_profile "maria.garcia@example.com"     "Maria"   "Garcia"      "Female" "1990-07-22" "Spanish"
ensure_profile "david.jones@example.com"      "David"   "Jones"       "Male"   "1978-11-08" "British"
ensure_profile "sophie.martin@example.com"    "Sophie"  "Martin"      "Female" "1992-05-30" "French"
ensure_profile "luca.rossi@example.com"       "Luca"    "Rossi"       "Male"   "1988-01-17" "Italian"
ensure_profile "anna.mueller@example.com"     "Anna"    "Mueller"     "Female" "1983-09-25" "German"
ensure_profile "yuki.tanaka@example.com"      "Yuki"    "Tanaka"      "Female" "1995-04-12" "Japanese"
ensure_profile "james.brown@example.com"      "James"   "Brown"       "Male"   "1975-08-03" "Australian"
ensure_profile "emma.white@example.com"       "Emma"    "White"       "Female" "1991-12-19" "British"
ensure_profile "carlos.lopez@example.com"     "Carlos"  "Lopez"       "Male"   "1987-06-07" "Mexican"
ensure_profile "piet.vanderberg@example.com"  "Piet"    "Vanderberg"  "Male"   "1980-02-14" "Dutch"
ensure_profile "elena.petrakis@example.com"   "Elena"   "Petrakis"    "Female" "1993-10-28" "Greek"
ensure_profile "thomas.schafer@example.com"   "Thomas"  "Schafer"     "Male"   "1970-05-05" "German"
ensure_profile "clara.dubois@example.com"     "Clara"   "Dubois"      "Female" "1989-03-21" "French"
ensure_profile "kai.yamamoto@example.com"     "Kai"     "Yamamoto"    "Male"   "1996-08-16" "Japanese"

# ---------------------------------------------------------------
# 4. Reset HasStayed edges to a controlled set of 34
# ---------------------------------------------------------------
echo "Resetting HasStayed edges..."
orientdb_sql "demodb" "DELETE EDGE HasStayed" >/dev/null 2>&1 || true

# Drop linked-class constraints on HasStayed (and its parent HasUsedService).
# The built-in DemoDB constrains HasStayed.out to Customers and HasStayed.in to Hotels.
# We need Profile -> Hotel edges, so we must remove these constraints.
echo "Dropping HasStayed/HasUsedService linked-class constraints..."
orientdb_sql "demodb" "DROP PROPERTY HasUsedService.out FORCE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP PROPERTY HasStayed.out FORCE" >/dev/null 2>&1 || true
orientdb_sql "demodb" "DROP PROPERTY HasStayed.in FORCE" >/dev/null 2>&1 || true

echo "Creating 34 deterministic HasStayed edges..."

# john.smith: Artemide, Savoy, Plaza (3 stays)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='john.smith@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Artemide')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='john.smith@example.com') TO (SELECT FROM Hotels WHERE Name='The Savoy')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='john.smith@example.com') TO (SELECT FROM Hotels WHERE Name='The Plaza Hotel')" >/dev/null 2>&1 || true

# maria.garcia: Artemide, Crillon, Arts Barcelona (3 stays)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='maria.garcia@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Artemide')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='maria.garcia@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel de Crillon')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='maria.garcia@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Arts Barcelona')" >/dev/null 2>&1 || true

# david.jones: Savoy, Adlon, Plaza, Artemide (4 stays)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='david.jones@example.com') TO (SELECT FROM Hotels WHERE Name='The Savoy')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='david.jones@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Adlon Kempinski')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='david.jones@example.com') TO (SELECT FROM Hotels WHERE Name='The Plaza Hotel')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='david.jones@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Artemide')" >/dev/null 2>&1 || true

# sophie.martin: Crillon, Fairmont, Arts Barcelona (3 stays)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='sophie.martin@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel de Crillon')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='sophie.martin@example.com') TO (SELECT FROM Hotels WHERE Name='Fairmont Le Manoir')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='sophie.martin@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Arts Barcelona')" >/dev/null 2>&1 || true

# luca.rossi: Artemide, Baglioni, Villa d Este (3 stays)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='luca.rossi@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Artemide')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='luca.rossi@example.com') TO (SELECT FROM Hotels WHERE Name='Baglioni Hotel Luna')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='luca.rossi@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Villa d Este')" >/dev/null 2>&1 || true

# anna.mueller: Adlon, Melia, Savoy (3 stays)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='anna.mueller@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Adlon Kempinski')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='anna.mueller@example.com') TO (SELECT FROM Hotels WHERE Name='Melia Berlin')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='anna.mueller@example.com') TO (SELECT FROM Hotels WHERE Name='The Savoy')" >/dev/null 2>&1 || true

# yuki.tanaka: Park Hyatt (1 stay)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='yuki.tanaka@example.com') TO (SELECT FROM Hotels WHERE Name='Park Hyatt Tokyo')" >/dev/null 2>&1 || true

# james.brown: Four Seasons, Copacabana (2 stays)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='james.brown@example.com') TO (SELECT FROM Hotels WHERE Name='Four Seasons Sydney')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='james.brown@example.com') TO (SELECT FROM Hotels WHERE Name='Copacabana Palace')" >/dev/null 2>&1 || true

# emma.white: Savoy, Grande Bretagne (2 stays)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='emma.white@example.com') TO (SELECT FROM Hotels WHERE Name='The Savoy')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='emma.white@example.com') TO (SELECT FROM Hotels WHERE Name='Grande Bretagne Hotel')" >/dev/null 2>&1 || true

# carlos.lopez: Copacabana, Arts Barcelona (2 stays)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='carlos.lopez@example.com') TO (SELECT FROM Hotels WHERE Name='Copacabana Palace')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='carlos.lopez@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Arts Barcelona')" >/dev/null 2>&1 || true

# piet.vanderberg: Intercontinental, Adlon (2 stays)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='piet.vanderberg@example.com') TO (SELECT FROM Hotels WHERE Name='Intercontinental Amsterdam')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='piet.vanderberg@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Adlon Kempinski')" >/dev/null 2>&1 || true

# elena.petrakis: Grande Bretagne, Artemide (2 stays)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='elena.petrakis@example.com') TO (SELECT FROM Hotels WHERE Name='Grande Bretagne Hotel')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='elena.petrakis@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Artemide')" >/dev/null 2>&1 || true

# thomas.schafer: Melia, Adlon (2 stays)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='thomas.schafer@example.com') TO (SELECT FROM Hotels WHERE Name='Melia Berlin')" >/dev/null 2>&1 || true
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='thomas.schafer@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel Adlon Kempinski')" >/dev/null 2>&1 || true

# clara.dubois: Crillon (1 stay)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='clara.dubois@example.com') TO (SELECT FROM Hotels WHERE Name='Hotel de Crillon')" >/dev/null 2>&1 || true

# kai.yamamoto: Park Hyatt (1 stay)
orientdb_sql "demodb" "CREATE EDGE HasStayed FROM (SELECT FROM Profiles WHERE Email='kai.yamamoto@example.com') TO (SELECT FROM Hotels WHERE Name='Park Hyatt Tokyo')" >/dev/null 2>&1 || true

# ---------------------------------------------------------------
# 5. Verify counts
# ---------------------------------------------------------------
stayed_count=$(sql_count "SELECT COUNT(*) as cnt FROM HasStayed")
hotel_count=$(sql_count "SELECT COUNT(*) as cnt FROM Hotels")
profile_count=$(sql_count "SELECT COUNT(*) as cnt FROM Profiles")
echo "HasStayed edges: ${stayed_count} (expected 34)"
echo "Hotels: ${hotel_count} (expected 15)"
echo "Profiles: ${profile_count} (expected >= 15)"

# ---------------------------------------------------------------
# 6. Baseline snapshot
# ---------------------------------------------------------------
cat > /tmp/collaborative_filtering_recommendation_engine_baseline.json << 'EOF'
{
  "has_stayed_count": 34,
  "similar_traveler_count": 0,
  "recommendation_count": 0,
  "report_count": 0
}
EOF

date +%s > /tmp/task_start_timestamp

kill_firefox
launch_firefox "http://localhost:2480/studio/index.html" 8
take_screenshot /tmp/task_start_collaborative_filtering_recommendation_engine.png

echo "=== Setup complete: collaborative_filtering_recommendation_engine ==="
