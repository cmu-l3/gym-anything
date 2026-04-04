#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up chinook_database_erd task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up any existing output files
rm -f /home/ga/Desktop/chinook_erd.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/chinook_erd.png 2>/dev/null || true

# Create the real Chinook database SQL schema on the Desktop.
# Chinook is a sample database designed by Luis Rocha (https://github.com/lerocha/chinook-database)
# representing a digital media store. This is the canonical published schema.
cat > /home/ga/Desktop/chinook_schema.sql << 'SQLEOF'
-- Chinook Database Schema (Physical)
-- Source: https://github.com/lerocha/chinook-database
-- Represents a digital media store (music, movies)

CREATE TABLE Genre (
    GenreId   INTEGER  NOT NULL  PRIMARY KEY,
    Name      NVARCHAR(120)
);

CREATE TABLE MediaType (
    MediaTypeId   INTEGER  NOT NULL  PRIMARY KEY,
    Name          NVARCHAR(120)
);

CREATE TABLE Artist (
    ArtistId   INTEGER  NOT NULL  PRIMARY KEY,
    Name       NVARCHAR(120)
);

CREATE TABLE Album (
    AlbumId    INTEGER  NOT NULL  PRIMARY KEY,
    Title      NVARCHAR(160)  NOT NULL,
    ArtistId   INTEGER  NOT NULL,
    FOREIGN KEY (ArtistId) REFERENCES Artist(ArtistId)
);

CREATE TABLE Track (
    TrackId      INTEGER  NOT NULL  PRIMARY KEY,
    Name         NVARCHAR(200)  NOT NULL,
    AlbumId      INTEGER,
    MediaTypeId  INTEGER  NOT NULL,
    GenreId      INTEGER,
    Composer     NVARCHAR(220),
    Milliseconds INTEGER  NOT NULL,
    Bytes        INTEGER,
    UnitPrice    NUMERIC(10,2)  NOT NULL,
    FOREIGN KEY (AlbumId) REFERENCES Album(AlbumId),
    FOREIGN KEY (MediaTypeId) REFERENCES MediaType(MediaTypeId),
    FOREIGN KEY (GenreId) REFERENCES Genre(GenreId)
);

CREATE TABLE Playlist (
    PlaylistId   INTEGER  NOT NULL  PRIMARY KEY,
    Name         NVARCHAR(120)
);

CREATE TABLE PlaylistTrack (
    PlaylistId   INTEGER  NOT NULL,
    TrackId      INTEGER  NOT NULL,
    PRIMARY KEY (PlaylistId, TrackId),
    FOREIGN KEY (PlaylistId) REFERENCES Playlist(PlaylistId),
    FOREIGN KEY (TrackId) REFERENCES Track(TrackId)
);

CREATE TABLE Employee (
    EmployeeId    INTEGER  NOT NULL  PRIMARY KEY,
    LastName      NVARCHAR(20)  NOT NULL,
    FirstName     NVARCHAR(20)  NOT NULL,
    Title         NVARCHAR(30),
    ReportsTo     INTEGER,
    BirthDate     DATETIME,
    HireDate      DATETIME,
    Address       NVARCHAR(70),
    City          NVARCHAR(40),
    State         NVARCHAR(40),
    Country       NVARCHAR(40),
    PostalCode    NVARCHAR(10),
    Phone         NVARCHAR(24),
    Fax           NVARCHAR(24),
    Email         NVARCHAR(60),
    FOREIGN KEY (ReportsTo) REFERENCES Employee(EmployeeId)
);

CREATE TABLE Customer (
    CustomerId    INTEGER  NOT NULL  PRIMARY KEY,
    FirstName     NVARCHAR(40)  NOT NULL,
    LastName      NVARCHAR(20)  NOT NULL,
    Company       NVARCHAR(80),
    Address       NVARCHAR(70),
    City          NVARCHAR(40),
    State         NVARCHAR(40),
    Country       NVARCHAR(40),
    PostalCode    NVARCHAR(10),
    Phone         NVARCHAR(24),
    Fax           NVARCHAR(24),
    Email         NVARCHAR(60)  NOT NULL,
    SupportRepId  INTEGER,
    FOREIGN KEY (SupportRepId) REFERENCES Employee(EmployeeId)
);

CREATE TABLE Invoice (
    InvoiceId         INTEGER  NOT NULL  PRIMARY KEY,
    CustomerId        INTEGER  NOT NULL,
    InvoiceDate       DATETIME  NOT NULL,
    BillingAddress    NVARCHAR(70),
    BillingCity       NVARCHAR(40),
    BillingState      NVARCHAR(40),
    BillingCountry    NVARCHAR(40),
    BillingPostalCode NVARCHAR(10),
    Total             NUMERIC(10,2)  NOT NULL,
    FOREIGN KEY (CustomerId) REFERENCES Customer(CustomerId)
);

CREATE TABLE InvoiceLine (
    InvoiceLineId   INTEGER  NOT NULL  PRIMARY KEY,
    InvoiceId       INTEGER  NOT NULL,
    TrackId         INTEGER  NOT NULL,
    UnitPrice       NUMERIC(10,2)  NOT NULL,
    Quantity        INTEGER  NOT NULL,
    FOREIGN KEY (InvoiceId) REFERENCES Invoice(InvoiceId),
    FOREIGN KEY (TrackId) REFERENCES Track(TrackId)
);
SQLEOF

chown ga:ga /home/ga/Desktop/chinook_schema.sql 2>/dev/null || true
echo "Chinook schema file created: /home/ga/Desktop/chinook_schema.sql"

# Record baseline state
INITIAL_COUNT=$(ls /home/ga/Desktop/*.drawio 2>/dev/null | wc -l || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_drawio_count

date +%s > /tmp/task_start_timestamp

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_chinook_erd.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i}s"
        break
    fi
    sleep 1
done

sleep 5

# Maximize window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Press Escape to dismiss startup dialog (blank canvas)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/chinook_erd_start.png 2>/dev/null || true

echo "=== Setup complete: chinook_schema.sql on Desktop, draw.io running with blank canvas ==="
