#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Repair SQLAlchemy ORM Layer Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/orm_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
cd "$WORKSPACE_DIR"

# 1. Generate legacy SQLite database (Chinook schema subset)
echo "Generating legacy SQLite database..."
sudo -u ga sqlite3 "$WORKSPACE_DIR/data/Chinook_Sqlite.sqlite" << 'SQL'
CREATE TABLE Genre (GenreId INTEGER PRIMARY KEY, Name TEXT);
CREATE TABLE Artist (ArtistId INTEGER PRIMARY KEY, Name TEXT);
CREATE TABLE Album (AlbumId INTEGER PRIMARY KEY, Title TEXT, ArtistId INTEGER, FOREIGN KEY(ArtistId) REFERENCES Artist(ArtistId));
CREATE TABLE Track (TrackId INTEGER PRIMARY KEY, Name TEXT, AlbumId INTEGER, GenreId INTEGER, Milliseconds INTEGER, UnitPrice REAL, FOREIGN KEY(AlbumId) REFERENCES Album(AlbumId), FOREIGN KEY(GenreId) REFERENCES Genre(GenreId));
CREATE TABLE Employee (EmployeeId INTEGER PRIMARY KEY, FirstName TEXT, LastName TEXT, ReportsTo INTEGER, FOREIGN KEY(ReportsTo) REFERENCES Employee(EmployeeId));
CREATE TABLE InvoiceLine (InvoiceLineId INTEGER PRIMARY KEY, InvoiceId INTEGER, TrackId INTEGER, UnitPrice REAL, Quantity INTEGER, FOREIGN KEY(TrackId) REFERENCES Track(TrackId));

INSERT INTO Genre VALUES (1, 'Rock'), (2, 'Jazz');
INSERT INTO Artist VALUES (1, 'AC/DC'), (2, 'Accept');
INSERT INTO Album VALUES (1, 'For Those About To Rock', 1), (2, 'Balls to the Wall', 2);
INSERT INTO Track VALUES (1, 'Track 1', 1, 1, 300000, 0.99), (2, 'Track 2', 1, 1, 250000, 0.99), (3, 'Track 3', 2, 1, 340000, 0.99);
INSERT INTO Employee VALUES (1, 'Adams', 'Andrew', NULL), (2, 'Edwards', 'Nancy', 1);
INSERT INTO InvoiceLine VALUES (1, 1, 1, 0.99, 2), (2, 1, 2, 0.99, 1), (3, 2, 3, 0.99, 5);
SQL

# 2. Setup project files
cat > "$WORKSPACE_DIR/database.py" << 'PYEOF'
import os
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

DB_PATH = os.path.join(os.path.dirname(__file__), "data", "Chinook_Sqlite.sqlite")
engine = create_engine(f"sqlite:///{DB_PATH}", echo=False)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

def get_session():
    return SessionLocal()
PYEOF

cat > "$WORKSPACE_DIR/models.py" << 'PYEOF'
from sqlalchemy import Column, Integer, String, Float, ForeignKey, Numeric
from sqlalchemy.orm import declarative_base, relationship

Base = declarative_base()

class Genre(Base):
    __tablename__ = 'Genre'
    GenreId = Column(Integer, primary_key=True)
    Name = Column(String(120))
    tracks = relationship("Track", back_populates="genre")

class Artist(Base):
    __tablename__ = 'Artist'
    ArtistId = Column(Integer, primary_key=True)
    Name = Column(String(120))
    albums = relationship("Album", back_populates="artist")

class Album(Base):
    __tablename__ = 'Album'
    AlbumId = Column(Integer, primary_key=True)
    Title = Column(String(160))
    ArtistId = Column(Integer, ForeignKey('Artist.ArtistId'))
    
    artist = relationship("Artist", back_populates="albums")
    tracks = relationship("Track", back_populates="album")

class Track(Base):
    __tablename__ = 'Track'
    TrackId = Column(Integer, primary_key=True)
    Name = Column(String(200))
    AlbumId = Column(Integer, ForeignKey('Album.AlbumId'))
    GenreId = Column(Integer, ForeignKey('Genre.GenreId'))
    Milliseconds = Column(Integer)
    UnitPrice = Column(Float)
    
    album = relationship("Album", back_populates="tracks")
    genre = relationship("Genre", back_populates="tracks")

class Employee(Base):
    __tablename__ = 'Employee'
    EmployeeId = Column(Integer, primary_key=True)
    FirstName = Column(String(20))
    LastName = Column(String(20))
    ReportsTo = Column(Integer, ForeignKey('Employee.EmployeeId'))
    
    manager = relationship("Employee")

class InvoiceLine(Base):
    __tablename__ = 'InvoiceLine'
    InvoiceLineId = Column(Integer, primary_key=True)
    InvoiceId = Column(Integer)
    TrackId = Column(Integer, ForeignKey('Track.TrackId'))
    UnitPrice = Column(Float)
    Quantity = Column(Integer)
    
    track = relationship("Track")
PYEOF

cat > "$WORKSPACE_DIR/repository.py" << 'PYEOF'
from sqlalchemy.orm import selectinload, joinedload
from sqlalchemy import func
from models import Artist, Album, Track, Employee, InvoiceLine, Genre

def get_all_artists_with_albums(session):
    """Fetch all artists and their albums."""
    return session.query(Artist).all()

def delete_album(session, album_id):
    """Delete an album by ID."""
    album = session.query(Album).filter_by(AlbumId=album_id).first()
    if album:
        session.delete(album)
        session.commit()

def get_employee_manager(session, employee_id):
    """Get the manager of an employee."""
    emp = session.query(Employee).filter_by(EmployeeId=employee_id).first()
    return emp.manager if emp else None

def calculate_total_revenue(session):
    """Calculate the total revenue from all invoice lines."""
    lines = session.query(InvoiceLine).all()
    return sum(line.UnitPrice * line.Quantity for line in lines)

def get_genre_total_duration(session, genre_name):
    """Calculate the total track duration (in ms) for a given genre."""
    genre = session.query(Genre).filter_by(Name=genre_name).first()
    if not genre:
        return 0
        
    tracks = session.query(Track).filter_by(GenreId=genre.GenreId).all()
    return sum(track.Milliseconds for track in tracks)
PYEOF

cat > "$WORKSPACE_DIR/tests/test_orm.py" << 'PYEOF'
import pytest
import decimal
from sqlalchemy import event
from database import engine, SessionLocal
from models import Artist, Album, Employee, Track
from repository import (
    get_all_artists_with_albums, delete_album, get_employee_manager,
    calculate_total_revenue, get_genre_total_duration
)

@pytest.fixture
def session():
    db = SessionLocal()
    yield db
    db.close()

def test_n_plus_one(session):
    query_count = 0
    def before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
        nonlocal query_count
        query_count += 1
    
    event.listen(engine, "before_cursor_execute", before_cursor_execute)
    try:
        artists = get_all_artists_with_albums(session)
        for artist in artists:
            _ = artist.albums
        assert query_count <= 2, f"N+1 problem! Executed {query_count} queries."
    finally:
        event.remove(engine, "before_cursor_execute", before_cursor_execute)

def test_cascade_delete(session):
    album = Album(Title="Test Album", ArtistId=1)
    session.add(album)
    session.commit()
    album_id = album.AlbumId
    track = Track(Name="Test Track", AlbumId=album_id, Milliseconds=1000, UnitPrice=0.99)
    session.add(track)
    session.commit()
    
    try:
        delete_album(session, album_id)
    except Exception as e:
        pytest.fail(f"Cascade delete failed: {e}")
        
    assert session.query(Track).filter_by(AlbumId=album_id).count() == 0

def test_employee_hierarchy(session):
    try:
        manager = get_employee_manager(session, 2)
        assert manager is not None
        assert manager.EmployeeId == 1
    except Exception as e:
        pytest.fail(f"Self-referential relationship error: {e}")

def test_financial_precision(session):
    total = calculate_total_revenue(session)
    assert isinstance(total, decimal.Decimal), "Revenue should be a Decimal, not float"

def test_genre_duration_memory(session):
    used_sum_in_sql = False
    def before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
        nonlocal used_sum_in_sql
        if 'SUM' in statement.upper():
            used_sum_in_sql = True
            
    event.listen(engine, "before_cursor_execute", before_cursor_execute)
    try:
        duration = get_genre_total_duration(session, 'Rock')
        assert duration > 0
        assert used_sum_in_sql, "Aggregation should happen in SQL (use func.sum), not in Python memory"
    finally:
        event.remove(engine, "before_cursor_execute", before_cursor_execute)
PYEOF

cat > "$WORKSPACE_DIR/requirements.txt" << 'PYEOF'
sqlalchemy
pytest
PYEOF

# Fix permissions
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Install dependencies
echo "Installing Python dependencies..."
sudo -u ga pip3 install -r "$WORKSPACE_DIR/requirements.txt"

# Ensure VSCode is running
if ! pgrep -f "code.*--ms-enable-electron-run-as-node" > /dev/null; then
    echo "Starting VSCode..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR &"
    sleep 5
fi

# Wait for window to appear
wait_for_window "Visual Studio Code" 30

# Maximize and focus
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
focus_vscode_window 2>/dev/null || true

# Capture initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="