#!/bin/bash
# Export script for Oracle Text Search task
# Verifies index structure, stoplist usage, package logic, and real-time sync

echo "=== Exporting Oracle Text Search Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create Python verification script to run INSIDE the container context (via docker exec)
# We construct the script locally, then pipe it to python inside the container is tricky,
# so we run python locally using oracledb to connect to localhost.

cat > /tmp/verify_oracle_text.py << 'PYEOF'
import oracledb
import json
import uuid
import time

result = {
    "index_exists": False,
    "index_status": "INVALID",
    "stoplist_exists": False,
    "stopwords_correct": False,
    "package_valid": False,
    "stemming_works": False,
    "scoring_works": False,
    "sync_works": False,
    "error": None
}

try:
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # 1. Verify Index Existence & Status
    cursor.execute("""
        SELECT idx_name, idx_status, idx_type 
        FROM ctx_user_indexes 
        WHERE idx_name = 'IDX_CATALOG_SYNOPSIS'
    """)
    row = cursor.fetchone()
    if row:
        result["index_exists"] = True
        result["index_status"] = row[1]  # 'INDEXED' is good

    # 2. Verify Stoplist
    # Check if preference exists
    cursor.execute("""
        SELECT pre_name FROM ctx_user_preferences WHERE pre_name = 'ARCHIVE_STOPLIST'
    """)
    if cursor.fetchone():
        result["stoplist_exists"] = True
        
        # Check specific stopwords in the stoplist
        # We query ctx_user_stopwords for our specific list
        required = {'edition', 'volume', 'series', 'copyright', 'publisher'}
        cursor.execute("""
            SELECT sw_word FROM ctx_user_stopwords WHERE sw_stoplist_name = 'ARCHIVE_STOPLIST'
        """)
        found_words = {r[0].lower() for r in cursor.fetchall()}
        if required.issubset(found_words):
            result["stopwords_correct"] = True

    # 3. Verify Package Validity
    cursor.execute("""
        SELECT status FROM user_objects WHERE object_name = 'SEARCH_ENGINE' AND object_type = 'PACKAGE BODY'
    """)
    row = cursor.fetchone()
    if row and row[0] == 'VALID':
        result["package_valid"] = True

    # 4. Functional Testing (Stemming & Scoring)
    # We assume the agent implemented FIND_BOOKS correctly
    if result["package_valid"]:
        try:
            # Test Stemming: 'run' should match 'running'
            # First, ensure we have a record with 'running'
            cursor.execute("INSERT INTO library_catalog (title, synopsis) VALUES ('Stem Test', 'The athlete is running fast.')")
            conn.commit()
            
            # Need to sync index if the agent's package does it, or manual for the test setup?
            # Ideally the agent's ADD_BOOK handles sync, but here we inserted manually.
            # We will try to sync manually just for this functional test step to be fair 
            # if they missed sync in ADD_BOOK, we still want to give points for Stemming.
            try:
                cursor.execute("BEGIN CTX_DDL.SYNC_INDEX('IDX_CATALOG_SYNOPSIS'); END;")
            except:
                pass

            # Call package
            out_cur = conn.cursor()
            cursor.callproc("SEARCH_ENGINE.FIND_BOOKS", ["run", out_cur])
            
            found_stem = False
            has_score = False
            
            for row in out_cur:
                # Expected columns: BOOK_ID, TITLE, SCORE
                title = row[1]
                score = row[2]
                if title == 'Stem Test':
                    found_stem = True
                if score and score > 0:
                    has_score = True
            
            result["stemming_works"] = found_stem
            result["scoring_works"] = has_score

        except Exception as e:
            result["functional_error"] = str(e)

    # 5. Verify Real-time Sync (The most critical architectural test)
    # We call the agent's ADD_BOOK, then IMMEDIATELY search.
    # If the index wasn't synced inside ADD_BOOK, the search will fail (Context indexes are async by default).
    if result["package_valid"]:
        try:
            unique_token = "XY_" + str(uuid.uuid4())[:8]
            cursor.callproc("SEARCH_ENGINE.ADD_BOOK", ["Sync Test", f"This is a {unique_token} test."])
            
            # Immediate search without manual sync
            out_cur_sync = conn.cursor()
            cursor.callproc("SEARCH_ENGINE.FIND_BOOKS", [unique_token, out_cur_sync])
            
            found_sync = False
            for row in out_cur_sync:
                if row[1] == "Sync Test":
                    found_sync = True
                    break
            
            result["sync_works"] = found_sync
            
        except Exception as e:
            result["sync_error"] = str(e)

    cursor.close()
    conn.close()

except Exception as e:
    result["error"] = str(e)

with open("/tmp/oracle_text_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

# Run the python script
python3 /tmp/verify_oracle_text.py

# Check for output file
OUTPUT_FILE="/home/ga/Desktop/search_results.txt"
OUTPUT_EXISTS="false"
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
fi

# Merge results
jq --arg exists "$OUTPUT_EXISTS" '. + {output_file_exists: ($exists == "true")}' /tmp/oracle_text_result.json > /tmp/task_result.json

echo "Result JSON:"
cat /tmp/task_result.json
echo "=== Export Complete ==="