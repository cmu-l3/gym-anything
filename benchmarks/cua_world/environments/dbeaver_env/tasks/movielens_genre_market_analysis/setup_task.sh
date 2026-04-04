#!/bin/bash
# Setup script for movielens_genre_market_analysis task

set -e
echo "=== Setting up MovieLens Genre Market Analysis Task ==="

source /workspace/scripts/task_utils.sh

MOVIELENS_DB="/home/ga/Documents/databases/movielens.db"
DB_DIR="/home/ga/Documents/databases"
EXPORT_DIR="/home/ga/Documents/exports"
SCRIPTS_DIR="/home/ga/Documents/scripts"

mkdir -p "$DB_DIR" "$EXPORT_DIR" "$SCRIPTS_DIR"
chown -R ga:ga /home/ga/Documents/

# Remove pre-existing outputs
rm -f "$EXPORT_DIR/genre_analysis.csv"
rm -f "$EXPORT_DIR/hidden_gems.csv"
rm -f "$SCRIPTS_DIR/market_analysis.sql"

# Download and create MovieLens database if not present
if [ ! -f "$MOVIELENS_DB" ] || [ "$(stat -c%s "$MOVIELENS_DB" 2>/dev/null || echo 0)" -lt 100000 ]; then
    echo "Downloading MovieLens small dataset..."
    rm -f "$MOVIELENS_DB"

    DOWNLOAD_SUCCESS=false

    if wget -q --timeout=120 \
        "https://files.grouplens.org/datasets/movielens/ml-latest-small.zip" \
        -O /tmp/movielens.zip 2>/dev/null && [ -s /tmp/movielens.zip ]; then
        echo "Download complete. Extracting..."
        rm -rf /tmp/ml-latest-small
        unzip -q /tmp/movielens.zip -d /tmp/ && DOWNLOAD_SUCCESS=true
        rm -f /tmp/movielens.zip
    fi

    if [ "$DOWNLOAD_SUCCESS" = "false" ]; then
        echo "ERROR: Failed to download MovieLens dataset"
        exit 1
    fi

    echo "Creating movielens.db SQLite database..."
    python3 << 'PYEOF'
import csv
import sqlite3
import json

db_path = "/home/ga/Documents/databases/movielens.db"
data_dir = "/tmp/ml-latest-small"

conn = sqlite3.connect(db_path)
c = conn.cursor()

# Create tables
c.execute("DROP TABLE IF EXISTS movies")
c.execute("DROP TABLE IF EXISTS ratings")
c.execute("DROP TABLE IF EXISTS tags")

c.execute("""CREATE TABLE movies (
    movieId INTEGER PRIMARY KEY,
    title TEXT,
    genres TEXT
)""")

c.execute("""CREATE TABLE ratings (
    userId INTEGER,
    movieId INTEGER,
    rating REAL,
    timestamp INTEGER
)""")

c.execute("""CREATE TABLE tags (
    userId INTEGER,
    movieId INTEGER,
    tag TEXT,
    timestamp INTEGER
)""")

# Import movies
movies_count = 0
with open(f'{data_dir}/movies.csv', 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        c.execute("INSERT OR IGNORE INTO movies VALUES (?,?,?)",
                  (int(row['movieId']), row['title'], row['genres']))
        movies_count += 1

# Import ratings
ratings_count = 0
with open(f'{data_dir}/ratings.csv', 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    batch = []
    for row in reader:
        batch.append((int(row['userId']), int(row['movieId']),
                      float(row['rating']), int(row['timestamp'])))
        if len(batch) >= 10000:
            c.executemany("INSERT INTO ratings VALUES (?,?,?,?)", batch)
            ratings_count += len(batch)
            batch = []
    if batch:
        c.executemany("INSERT INTO ratings VALUES (?,?,?,?)", batch)
        ratings_count += len(batch)

# Import tags
tags_count = 0
with open(f'{data_dir}/tags.csv', 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        c.execute("INSERT INTO tags VALUES (?,?,?,?)",
                  (int(row['userId']), int(row['movieId']),
                   row['tag'], int(row['timestamp'])))
        tags_count += 1

conn.commit()
print(f"Imported: {movies_count} movies, {ratings_count} ratings, {tags_count} tags")

# --- Compute ground truth for genre analysis ---
# For genre analysis, use LIKE-based counting for each known genre
# This approximates what agents might do without recursive CTEs

# Get all distinct genre tokens
all_genres_q = c.execute("SELECT DISTINCT genres FROM movies WHERE genres != '(no genres listed)'").fetchall()
genre_set = set()
for row in all_genres_q:
    for g in row[0].split('|'):
        if g and g != '(no genres listed)':
            genre_set.add(g)

print(f"Distinct genres: {len(genre_set)}")

genre_stats = []
for genre in genre_set:
    # Count ratings for movies in this genre
    result = c.execute("""
        SELECT COUNT(r.rating), AVG(r.rating)
        FROM ratings r
        JOIN movies m ON r.movieId = m.movieId
        WHERE m.genres LIKE ?
    """, (f'%{genre}%',)).fetchone()
    count, avg = result
    if count and count >= 500:
        genre_stats.append({'genre': genre, 'avg_rating': round(avg, 4), 'rating_count': count})

genre_stats.sort(key=lambda x: x['avg_rating'], reverse=True)
top5_genres = genre_stats[:5]
print(f"Top 5 genres (with >=500 ratings): {[g['genre'] for g in top5_genres]}")

# --- Compute ground truth for hidden gems ---
hidden_gems_q = c.execute("""
    SELECT m.movieId, m.title,
           ROUND(AVG(r.rating), 4) as avg_rating,
           COUNT(r.rating) as rating_count
    FROM movies m
    JOIN ratings r ON m.movieId = r.movieId
    GROUP BY m.movieId
    HAVING avg_rating >= 4.0 AND rating_count < 50
    ORDER BY avg_rating DESC, m.movieId ASC
    LIMIT 10
""").fetchall()

hidden_gems = [{'movieId': r[0], 'title': r[1], 'avg_rating': r[2], 'rating_count': r[3]}
               for r in hidden_gems_q]
print(f"Hidden gems found: {len(hidden_gems)}")
if hidden_gems:
    print(f"Top hidden gem: {hidden_gems[0]}")

ground_truth = {
    'top5_genres': top5_genres,
    'top1_genre': top5_genres[0]['genre'] if top5_genres else '',
    'genre_count_with_500': len(genre_stats),
    'hidden_gems': hidden_gems,
    'total_movies': movies_count,
    'total_ratings': ratings_count
}

with open('/tmp/movielens_gt.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)

print("Ground truth saved to /tmp/movielens_gt.json")
conn.close()
PYEOF

    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create MovieLens database"
        exit 1
    fi

    chown ga:ga "$MOVIELENS_DB"
    rm -rf /tmp/ml-latest-small
    echo "MovieLens database created"
else
    echo "MovieLens database already present"
    # Recompute ground truth even if DB exists
    python3 << 'PYEOF'
import sqlite3, json

db_path = "/home/ga/Documents/databases/movielens.db"
conn = sqlite3.connect(db_path)
c = conn.cursor()

all_genres_q = c.execute("SELECT DISTINCT genres FROM movies WHERE genres != '(no genres listed)'").fetchall()
genre_set = set()
for row in all_genres_q:
    for g in row[0].split('|'):
        if g and g != '(no genres listed)':
            genre_set.add(g)

genre_stats = []
for genre in genre_set:
    result = c.execute("""
        SELECT COUNT(r.rating), AVG(r.rating)
        FROM ratings r
        JOIN movies m ON r.movieId = m.movieId
        WHERE m.genres LIKE ?
    """, (f'%{genre}%',)).fetchone()
    count, avg = result
    if count and count >= 500:
        genre_stats.append({'genre': genre, 'avg_rating': round(avg, 4), 'rating_count': count})

genre_stats.sort(key=lambda x: x['avg_rating'], reverse=True)
top5_genres = genre_stats[:5]

hidden_gems_q = c.execute("""
    SELECT m.movieId, m.title,
           ROUND(AVG(r.rating), 4) as avg_rating,
           COUNT(r.rating) as rating_count
    FROM movies m
    JOIN ratings r ON m.movieId = r.movieId
    GROUP BY m.movieId
    HAVING avg_rating >= 4.0 AND rating_count < 50
    ORDER BY avg_rating DESC, m.movieId ASC
    LIMIT 10
""").fetchall()
hidden_gems = [{'movieId': r[0], 'title': r[1], 'avg_rating': r[2], 'rating_count': r[3]}
               for r in hidden_gems_q]

ground_truth = {
    'top5_genres': top5_genres,
    'top1_genre': top5_genres[0]['genre'] if top5_genres else '',
    'genre_count_with_500': len(genre_stats),
    'hidden_gems': hidden_gems,
}
with open('/tmp/movielens_gt.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)
print("Ground truth recomputed")
conn.close()
PYEOF
fi

# Verify DB
MOVIE_COUNT=$(sqlite3 "$MOVIELENS_DB" "SELECT COUNT(*) FROM movies" 2>/dev/null || echo 0)
RATING_COUNT=$(sqlite3 "$MOVIELENS_DB" "SELECT COUNT(*) FROM ratings" 2>/dev/null || echo 0)
echo "Movies: $MOVIE_COUNT, Ratings: $RATING_COUNT"

if [ "$RATING_COUNT" -lt 50000 ]; then
    echo "ERROR: MovieLens database has too few ratings ($RATING_COUNT)"
    exit 1
fi

# Record baseline
echo "$MOVIE_COUNT" > /tmp/initial_movies_count
echo "$RATING_COUNT" > /tmp/initial_ratings_count

DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"
INITIAL_CONN_COUNT=0
if [ -f "$DBEAVER_CONFIG" ]; then
    INITIAL_CONN_COUNT=$(python3 -c "
import json
try:
    with open('$DBEAVER_CONFIG') as f:
        c = json.load(f)
    print(len(c.get('connections', {})))
except:
    print(0)
" 2>/dev/null || echo 0)
fi
echo "$INITIAL_CONN_COUNT" > /tmp/initial_dbeaver_conn_count

date +%s > /tmp/task_start_timestamp
echo "Task started at: $(date)"

if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 dbeaver &" 2>/dev/null &
    sleep 8
fi
focus_dbeaver || true
sleep 2

take_screenshot /tmp/movielens_task_start.png
echo "=== MovieLens Market Analysis Setup Complete ==="
