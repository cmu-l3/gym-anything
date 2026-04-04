#!/bin/bash
set -e
echo "=== Setting up add_isbn_to_books task ==="

DB_PATH="/home/ga/Zotero/zotero.sqlite"

# 1. Kill Zotero to release DB lock
echo "Stopping Zotero..."
pkill -9 -f zotero 2>/dev/null || true
sleep 3

# 2. Seed the database with the 6 specific books (without ISBNs)
echo "Seeding database with 6 books..."

cat > /tmp/seed_books.py << 'PYEOF'
import sqlite3
import time
import os

DB_PATH = "/home/ga/Zotero/zotero.sqlite"

BOOKS = [
    {
        "title": "Introduction to Algorithms",
        "publisher": "MIT Press",
        "date": "2009",
        "creators": [("Thomas H.", "Cormen"), ("Charles E.", "Leiserson"), ("Ronald L.", "Rivest"), ("Clifford", "Stein")]
    },
    {
        "title": "The Art of Computer Programming, Volume 1: Fundamental Algorithms",
        "publisher": "Addison-Wesley",
        "date": "1997",
        "creators": [("Donald E.", "Knuth")]
    },
    {
        "title": "Design Patterns: Elements of Reusable Object-Oriented Software",
        "publisher": "Addison-Wesley",
        "date": "1994",
        "creators": [("Erich", "Gamma"), ("Richard", "Helm"), ("Ralph", "Johnson"), ("John", "Vlissides")]
    },
    {
        "title": "Structure and Interpretation of Computer Programs",
        "publisher": "MIT Press",
        "date": "1996",
        "creators": [("Harold", "Abelson"), ("Gerald Jay", "Sussman")]
    },
    {
        "title": "The C Programming Language",
        "publisher": "Prentice Hall",
        "date": "1988",
        "creators": [("Brian W.", "Kernighan"), ("Dennis M.", "Ritchie")]
    },
    {
        "title": "Artificial Intelligence: A Modern Approach",
        "publisher": "Prentice Hall",
        "date": "2009",
        "creators": [("Stuart", "Russell"), ("Peter", "Norvig")]
    }
]

def get_field_id(cursor, field_name):
    cursor.execute("SELECT fieldID FROM fields WHERE fieldName=?", (field_name,))
    res = cursor.fetchone()
    return res[0] if res else None

def get_creator_type_id(cursor, creator_type):
    cursor.execute("SELECT creatorTypeID FROM creatorTypes WHERE creatorType=?", (creator_type,))
    res = cursor.fetchone()
    return res[0] if res else 8  # Default to author

def insert_value(cursor, value):
    cursor.execute("INSERT INTO itemDataValues (value) VALUES (?)", (value,))
    return cursor.lastrowid

def seed():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    
    # Clear existing items
    c.execute("DELETE FROM items")
    c.execute("DELETE FROM itemData")
    c.execute("DELETE FROM itemDataValues")
    c.execute("DELETE FROM itemCreators")
    c.execute("DELETE FROM creators")
    
    # Get IDs
    title_fid = get_field_id(c, 'title')
    date_fid = get_field_id(c, 'date')
    pub_fid = get_field_id(c, 'publisher')
    item_type_id = 2  # Book
    author_type_id = 8 # Author
    
    print(f"Field IDs: Title={title_fid}, Date={date_fid}, Pub={pub_fid}")
    
    for book in BOOKS:
        # Create item
        c.execute("INSERT INTO items (itemTypeID, dateAdded, dateModified) VALUES (?, datetime('now'), datetime('now'))", (item_type_id,))
        item_id = c.lastrowid
        
        # Add Title
        val_id = insert_value(c, book['title'])
        c.execute("INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, ?, ?)", (item_id, title_fid, val_id))
        
        # Add Date
        val_id = insert_value(c, book['date'])
        c.execute("INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, ?, ?)", (item_id, date_fid, val_id))
        
        # Add Publisher
        val_id = insert_value(c, book['publisher'])
        c.execute("INSERT INTO itemData (itemID, fieldID, valueID) VALUES (?, ?, ?)", (item_id, pub_fid, val_id))
        
        # Add Creators
        for first, last in book['creators']:
            c.execute("INSERT INTO creators (firstName, lastName) VALUES (?, ?)", (first, last))
            creator_id = c.lastrowid
            c.execute("INSERT INTO itemCreators (itemID, creatorID, creatorTypeID, 'order') VALUES (?, ?, ?, ?)", 
                      (item_id, creator_id, author_type_id, 0)) # Order simplified
                      
    conn.commit()
    conn.close()
    print("Seeding complete.")

if __name__ == "__main__":
    seed()
PYEOF

python3 /tmp/seed_books.py

# 3. Record baseline state
if [ -f "$DB_PATH" ]; then
    # Ensure no ISBNs exist
    ISBN_FIELD_ID=$(sqlite3 "$DB_PATH" "SELECT fieldID FROM fields WHERE fieldName='ISBN'")
    if [ -n "$ISBN_FIELD_ID" ]; then
        ISBN_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM itemData WHERE fieldID=$ISBN_FIELD_ID")
        echo "Initial ISBN count (should be 0): $ISBN_COUNT"
        echo "$ISBN_COUNT" > /tmp/initial_isbn_count
    fi
    
    ITEM_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM items WHERE itemTypeID=2")
    echo "Initial Book count: $ITEM_COUNT"
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# 4. Restart Zotero
echo "Starting Zotero..."
# Using sudo to run as ga user with display
sudo -u ga bash -c 'DISPLAY=:1 /opt/zotero/zotero --no-remote > /home/ga/zotero.log 2>&1 &'

# Wait for window
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Zotero"; then
        echo "Zotero window found."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "Zotero" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Zotero" 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="