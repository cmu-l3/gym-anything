#!/bin/bash
set -e

echo "=== Setting up ER Diagram Task ==="

# 1. Create Directories
su - ga -c "mkdir -p /home/ga/Diagrams/exports /home/ga/Desktop" 2>/dev/null || true

# 2. Create the SQL Schema File (Chinook Subset)
cat > /home/ga/Desktop/chinook_subset_schema.sql << 'SQLEOF'
/*******************************************************************************
   Chinook Database - Media Subset Schema
   Script: chinook_subset_schema.sql
   Description: DDL for the music catalog portion of the Chinook database.
********************************************************************************/

CREATE TABLE Artist (
    ArtistId INT NOT NULL,
    Name NVARCHAR(120),
    CONSTRAINT PK_Artist PRIMARY KEY (ArtistId)
);

CREATE TABLE Album (
    AlbumId INT NOT NULL,
    Title NVARCHAR(160) NOT NULL,
    ArtistId INT NOT NULL,
    CONSTRAINT PK_Album PRIMARY KEY (AlbumId),
    CONSTRAINT FK_Album_Artist FOREIGN KEY (ArtistId) REFERENCES Artist (ArtistId)
);

CREATE TABLE MediaType (
    MediaTypeId INT NOT NULL,
    Name NVARCHAR(120),
    CONSTRAINT PK_MediaType PRIMARY KEY (MediaTypeId)
);

CREATE TABLE Genre (
    GenreId INT NOT NULL,
    Name NVARCHAR(120),
    CONSTRAINT PK_Genre PRIMARY KEY (GenreId)
);

CREATE TABLE Track (
    TrackId INT NOT NULL,
    Name NVARCHAR(200) NOT NULL,
    AlbumId INT,
    MediaTypeId INT NOT NULL,
    GenreId INT,
    Composer NVARCHAR(220),
    Milliseconds INT NOT NULL,
    Bytes INT,
    UnitPrice NUMERIC(10,2) NOT NULL,
    CONSTRAINT PK_Track PRIMARY KEY (TrackId),
    CONSTRAINT FK_Track_Album FOREIGN KEY (AlbumId) REFERENCES Album (AlbumId),
    CONSTRAINT FK_Track_Genre FOREIGN KEY (GenreId) REFERENCES Genre (GenreId),
    CONSTRAINT FK_Track_MediaType FOREIGN KEY (MediaTypeId) REFERENCES MediaType (MediaTypeId)
);

CREATE TABLE Playlist (
    PlaylistId INT NOT NULL,
    Name NVARCHAR(120),
    CONSTRAINT PK_Playlist PRIMARY KEY (PlaylistId)
);

CREATE TABLE PlaylistTrack (
    PlaylistId INT NOT NULL,
    TrackId INT NOT NULL,
    CONSTRAINT PK_PlaylistTrack PRIMARY KEY (PlaylistId, TrackId),
    CONSTRAINT FK_PlaylistTrack_Playlist FOREIGN KEY (PlaylistId) REFERENCES Playlist (PlaylistId),
    CONSTRAINT FK_PlaylistTrack_Track FOREIGN KEY (TrackId) REFERENCES Track (TrackId)
);
SQLEOF

# 3. Create Requirements File
cat > /home/ga/Desktop/er_requirements.txt << 'REQEOF'
ER DIAGRAM REQUIREMENTS
=======================

1. NOTATION:
   - Use Crow's Foot notation for cardinality.
   - Use Entity/Table shapes that list columns.

2. CONTENT:
   - Include all 7 tables from the SQL schema.
   - Mark Primary Keys with "PK" or a key icon.
   - Mark Foreign Keys with "FK".
   - Include all columns listed in the SQL.

3. RELATIONSHIPS:
   - Draw relationships exactly as defined by the Foreign Keys.
   - Pay attention to the "PlaylistTrack" table (it represents a Many-to-Many relationship).

4. DELIVERABLES:
   - Save the editable file to: ~/Diagrams/chinook_er_diagram.drawio
   - Export a PNG image to:     ~/Diagrams/exports/chinook_er_diagram.png
REQEOF

# Set permissions
chown ga:ga /home/ga/Desktop/chinook_subset_schema.sql /home/ga/Desktop/er_requirements.txt
chmod 644 /home/ga/Desktop/chinook_subset_schema.sql /home/ga/Desktop/er_requirements.txt

# 4. Clean up previous results
rm -f /home/ga/Diagrams/chinook_er_diagram.drawio 2>/dev/null || true
rm -f /home/ga/Diagrams/exports/chinook_er_diagram.png 2>/dev/null || true

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Launch draw.io (Blank)
echo "Launching draw.io..."
# Kill any existing instances
pkill -f drawio 2>/dev/null || true
sleep 1

# Launch
su - ga -c "DISPLAY=:1 /opt/drawio/drawio.AppImage --no-sandbox > /dev/null 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io" > /dev/null; then
        echo "draw.io window detected."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Attempt to dismiss update dialog if it appears
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="