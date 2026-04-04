#!/bin/bash
set -e
echo "=== Setting up ER Diagram task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Create the Diagrams directory
mkdir -p /home/ga/Diagrams

# Create the schema specification file with real data from Chinook DB
cat > /home/ga/Diagrams/chinook_schema_spec.txt << 'EOSCHEMA'
=== CHINOOK DATABASE - ER DIAGRAM SPECIFICATION ===
Source: https://github.com/lerocha/chinook-database (MIT License)

INSTRUCTIONS:
Model the following 5 entities with their attributes and relationships.
Mark Primary Keys with [PK] and Foreign Keys with [FK].

1. ENTITY: Artist
   - ArtistId   INTEGER  [PK]
   - Name       TEXT

2. ENTITY: Album
   - AlbumId    INTEGER  [PK]
   - Title      TEXT
   - ArtistId   INTEGER  [FK -> Artist.ArtistId]

3. ENTITY: Track
   - TrackId    INTEGER  [PK]
   - Name       TEXT
   - AlbumId    INTEGER  [FK -> Album.AlbumId]
   - GenreId    INTEGER  [FK -> Genre.GenreId]
   - UnitPrice  REAL

4. ENTITY: Genre
   - GenreId    INTEGER  [PK]
   - Name       TEXT

5. ENTITY: Invoice
   - InvoiceId       INTEGER   [PK]
   - CustomerId      INTEGER
   - InvoiceDate     DATETIME
   - BillingCountry  TEXT
   - Total           REAL

RELATIONSHIPS (Cardinality):
   Artist (1) ----> (N) Album     [One Artist has Many Albums]
   Album  (1) ----> (N) Track     [One Album has Many Tracks]
   Genre  (1) ----> (N) Track     [One Genre has Many Tracks]
EOSCHEMA

# Set ownership
chown ga:ga /home/ga/Diagrams/chinook_schema_spec.txt
chmod 644 /home/ga/Diagrams/chinook_schema_spec.txt

# Clean up any previous run artifacts to ensure fresh start
rm -f /home/ga/Diagrams/chinook_er_diagram.eddx
rm -f /home/ga/Diagrams/chinook_er_diagram.png

# Kill any existing EdrawMax instances
kill_edrawmax

# Launch EdrawMax (empty state)
echo "Launching EdrawMax..."
launch_edrawmax

# Wait for application to load
wait_for_edrawmax 90

# Dismiss startup dialogs
dismiss_edrawmax_dialogs

# Maximize window
maximize_edrawmax

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== ER Diagram task setup complete ==="