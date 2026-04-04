#!/bin/bash
echo "=== Exporting create_diverse_reference_types result ==="

# Record end time
date +%s > /tmp/task_end_time.txt
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We use an embedded Python script to inspect the SQLite database thoroughly.
# This handles the complexity of Zotero's EAV (Entity-Attribute-Value) schema.
cat << 'PYEOF' > /tmp/inspect_zotero.py
import sqlite3
import json
import os
import sys

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
START_TIME = int(sys.argv[1]) if len(sys.argv) > 1 else 0

def get_db_connection():
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.row_factory = sqlite3.Row
        return conn
    except Exception as e:
        print(f"Error connecting to DB: {e}", file=sys.stderr)
        return None

def get_field_value(conn, item_id, field_name):
    query = """
    SELECT v.value
    FROM itemData d
    JOIN itemDataValues v ON d.valueID = v.valueID
    JOIN fields f ON d.fieldID = f.fieldID
    WHERE d.itemID = ? AND f.fieldName = ?
    """
    cursor = conn.execute(query, (item_id, field_name))
    row = cursor.fetchone()
    return row['value'] if row else None

def get_creators(conn, item_id):
    query = """
    SELECT c.firstName, c.lastName, ct.creatorType
    FROM itemCreators ic
    JOIN creators c ON ic.creatorID = c.creatorID
    JOIN creatorTypes ct ON ic.creatorTypeID = ct.creatorTypeID
    WHERE ic.itemID = ?
    ORDER BY ic.orderIndex
    """
    cursor = conn.execute(query, (item_id,))
    return [dict(row) for row in cursor.fetchall()]

def analyze_items():
    conn = get_db_connection()
    if not conn:
        return {}

    # Map item type names to IDs
    type_query = "SELECT itemTypeID, typeName FROM itemTypes"
    types = {row['typeName']: row['itemTypeID'] for row in conn.execute(type_query)}
    
    # Types we care about
    target_types = {
        'thesis': types.get('thesis'),
        'patent': types.get('patent'),
        'report': types.get('report'),
        'bookSection': types.get('bookSection')
    }

    results = {
        'thesis': None,
        'patent': None,
        'report': None,
        'bookSection': None,
        'total_new_items': 0
    }

    # Find items added after start time
    # Note: dateAdded is usually stored as 'YYYY-MM-DD HH:MM:SS' string in Zotero SQLite
    # We will fetch all items and filter by timestamp in python to be safe with formats
    items_query = """
    SELECT itemID, itemTypeID, dateAdded 
    FROM items 
    WHERE itemTypeID NOT IN (1, 14) -- exclude notes/attachments
    """
    cursor = conn.execute(items_query)
    
    import datetime
    
    # Simple count of items added during task
    new_item_count = 0

    for row in cursor.fetchall():
        try:
            # Parse dateAdded "2023-10-25 10:00:00"
            dt = datetime.datetime.strptime(row['dateAdded'], "%Y-%m-%d %H:%M:%S")
            # Assume local time or UTC? Zotero usually uses UTC in DB.
            # We'll compare flexibly. If the file mtime checks pass, we trust it reasonably.
            # Ideally compare timestamps, but for robustness against timezone mismatch,
            # we check if it was likely created during this session.
            # Using the START_TIME passed from shell
            timestamp = dt.timestamp()
            
            # Allow a small buffer (e.g. clock skew)
            if timestamp > (START_TIME - 60):
                new_item_count += 1
                
                # Check if this item matches one of our target types
                item_id = row['itemID']
                type_id = row['itemTypeID']
                
                # Helper to build item dict
                item_data = {
                    'itemID': item_id,
                    'title': get_field_value(conn, item_id, 'title'),
                    'creators': get_creators(conn, item_id)
                }

                if type_id == target_types['thesis']:
                    item_data['university'] = get_field_value(conn, item_id, 'university')
                    item_data['type'] = get_field_value(conn, item_id, 'type') # thesisType
                    item_data['date'] = get_field_value(conn, item_id, 'date')
                    item_data['numPages'] = get_field_value(conn, item_id, 'numPages')
                    results['thesis'] = item_data
                    
                elif type_id == target_types['patent']:
                    item_data['patentNumber'] = get_field_value(conn, item_id, 'patentNumber')
                    item_data['assignee'] = get_field_value(conn, item_id, 'assignee')
                    item_data['place'] = get_field_value(conn, item_id, 'place')
                    item_data['date'] = get_field_value(conn, item_id, 'date')
                    results['patent'] = item_data
                    
                elif type_id == target_types['report']:
                    item_data['reportNumber'] = get_field_value(conn, item_id, 'reportNumber')
                    item_data['institution'] = get_field_value(conn, item_id, 'institution')
                    item_data['place'] = get_field_value(conn, item_id, 'place')
                    item_data['date'] = get_field_value(conn, item_id, 'date')
                    results['report'] = item_data
                    
                elif type_id == target_types['bookSection']:
                    item_data['publicationTitle'] = get_field_value(conn, item_id, 'publicationTitle')
                    item_data['publisher'] = get_field_value(conn, item_id, 'publisher')
                    item_data['pages'] = get_field_value(conn, item_id, 'pages')
                    item_data['date'] = get_field_value(conn, item_id, 'date')
                    item_data['place'] = get_field_value(conn, item_id, 'place')
                    results['bookSection'] = item_data

        except Exception as e:
            # Date parsing error or other
            continue

    results['total_new_items'] = new_item_count
    
    conn.close()
    return results

if __name__ == "__main__":
    data = analyze_items()
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f, indent=2)
PYEOF

# Run the python script
python3 /tmp/inspect_zotero.py "$START_TIME"

# Adjust permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export complete ==="