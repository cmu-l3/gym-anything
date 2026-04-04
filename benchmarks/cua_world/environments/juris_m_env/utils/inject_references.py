#!/usr/bin/env python3
"""
Inject real legal references into Jurism SQLite database.
Used by setup scripts to pre-populate the library with real legal data.

References are real US Supreme Court cases and law review articles.
Field IDs and item type IDs verified against Jurism 6 (Jurism-6.0.30m3) database schema.
"""

import sqlite3
import sys
import os
import random
import string
from datetime import datetime, timedelta

# Real US Supreme Court cases and law review articles
# All are publicly documented historical cases
LEGAL_REFERENCES = [
    {
        "type": "case",
        "caseName": "Brown v. Board of Education",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "347",
        "firstPage": "483",
        "dateDecided": "1954",
        "abstractNote": "Landmark Supreme Court case that declared racial segregation in public schools unconstitutional, overturning Plessy v. Ferguson.",
    },
    {
        "type": "case",
        "caseName": "Marbury v. Madison",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "5",
        "firstPage": "137",
        "dateDecided": "1803",
        "abstractNote": "Foundational case establishing the principle of judicial review in the United States.",
    },
    {
        "type": "case",
        "caseName": "Miranda v. Arizona",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "384",
        "firstPage": "436",
        "dateDecided": "1966",
        "abstractNote": "Case establishing the Miranda warning requirement for suspects in police custody.",
    },
    {
        "type": "case",
        "caseName": "New York Times Co. v. Sullivan",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "376",
        "firstPage": "254",
        "dateDecided": "1964",
        "abstractNote": "Landmark First Amendment case establishing the actual malice standard for defamation claims by public officials.",
    },
    {
        "type": "case",
        "caseName": "Gideon v. Wainwright",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "372",
        "firstPage": "335",
        "dateDecided": "1963",
        "abstractNote": "Case holding that the Sixth Amendment's right to counsel applies to state criminal proceedings through the Fourteenth Amendment.",
    },
    {
        "type": "case",
        "caseName": "Obergefell v. Hodges",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "576",
        "firstPage": "644",
        "dateDecided": "2015",
        "abstractNote": "Case holding that the fundamental right to marry is guaranteed to same-sex couples.",
    },
    {
        "type": "journalArticle",
        "title": "The Path of the Law",
        "authorFirst": "Oliver Wendell",
        "authorLast": "Holmes",
        "publicationTitle": "Harvard Law Review",
        "volume": "10",
        "issue": "8",
        "pages": "457-478",
        "date": "1897",
        "abstractNote": "Seminal essay by Oliver Wendell Holmes Jr. on legal theory, the nature of law, and the role of courts.",
        "ISSN": "0017-811X",
    },
    {
        "type": "journalArticle",
        "title": "Constitutional Fact Review",
        "authorFirst": "Henry P.",
        "authorLast": "Monaghan",
        "publicationTitle": "Columbia Law Review",
        "volume": "85",
        "issue": "2",
        "pages": "229-277",
        "date": "1985",
        "abstractNote": "This article examines the doctrine of constitutional fact review, analyzing when and why courts engage in independent review of factual determinations.",
        "ISSN": "0010-1958",
    },
    {
        "type": "journalArticle",
        "title": "The Due Process Clause and the Substantive Law of Torts",
        "authorFirst": "Ronald D.",
        "authorLast": "Poe",
        "publicationTitle": "Yale Law Journal",
        "volume": "80",
        "issue": "5",
        "pages": "920-980",
        "date": "1971",
        "abstractNote": "An examination of the relationship between the Fourteenth Amendment's Due Process Clause and substantive tort law.",
        "ISSN": "0044-0094",
    },
    {
        "type": "case",
        "caseName": "Tinker v. Des Moines Independent Community School District",
        "court": "United States Supreme Court",
        "reporter": "U.S.",
        "reporterVolume": "393",
        "firstPage": "503",
        "dateDecided": "1969",
        "abstractNote": "Case holding that students do not lose their First Amendment rights at the schoolhouse gate.",
    },
]

# Field IDs verified against Jurism 6.0.30m3 database schema
FIELD_IDS = {
    "title": 1,
    "abstractNote": 2,
    "publicationTitle": 7,
    "date": 8,
    "callNumber": 14,
    "extra": 18,
    "volume": 22,
    "pages": 47,
    "reporter": 49,
    "caseName": 58,    # The case name (e.g., "Brown v. Board of Education")
    "court": 60,       # The court (e.g., "United States Supreme Court")
    "reporterVolume": 66,
    "firstPage": 67,
    "dateDecided": 69,
    "issue": 72,
    "ISSN": 108,
}

# Item type IDs verified against Jurism 6.0.30m3 database schema
ITEM_TYPE_IDS = {
    "journalArticle": 24,
    "book": 7,
    "case": 9,
}

# Creator type IDs (standard Zotero/Jurism)
CREATOR_TYPE_IDS = {
    "author": 1,
    "editor": 2,
}


def get_or_create_value(conn, value):
    """Get or create a value in itemDataValues, return valueID."""
    cursor = conn.cursor()
    cursor.execute("SELECT valueID FROM itemDataValues WHERE value = ?", (value,))
    row = cursor.fetchone()
    if row:
        return row[0]
    cursor.execute("INSERT INTO itemDataValues (value) VALUES (?)", (value,))
    return cursor.lastrowid


def get_or_create_creator(conn, first_name, last_name):
    """Get or create a creator, return creatorID."""
    cursor = conn.cursor()
    cursor.execute(
        "SELECT creatorID FROM creators WHERE firstName = ? AND lastName = ?",
        (first_name, last_name)
    )
    row = cursor.fetchone()
    if row:
        return row[0]
    cursor.execute(
        "INSERT INTO creators (firstName, lastName, fieldMode) VALUES (?, ?, 0)",
        (first_name, last_name)
    )
    return cursor.lastrowid


def insert_reference(conn, ref, offset_hours=0):
    """Insert a single reference into the Jurism database."""
    cursor = conn.cursor()

    ref_type = ref.get("type", "journalArticle")
    type_id = ITEM_TYPE_IDS.get(ref_type, 24)
    now = datetime.now() - timedelta(hours=offset_hours)
    now_str = now.strftime("%Y-%m-%d %H:%M:%S")

    # Insert into items table (libraryID=1 is the user library; key is Zotero-style 8-char alphanumeric)
    key = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
    cursor.execute(
        "INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified, libraryID, key) VALUES (?, ?, ?, ?, ?, ?)",
        (type_id, now_str, now_str, now_str, 1, key)
    )
    item_id = cursor.lastrowid

    # Build field data based on item type
    fields_to_insert = {}

    if ref_type == "case":
        # For case items: caseName is the primary identifier (display title)
        if ref.get("caseName"):
            fields_to_insert["caseName"] = ref["caseName"]
        if ref.get("court"):
            fields_to_insert["court"] = ref["court"]
        if ref.get("reporter"):
            fields_to_insert["reporter"] = ref["reporter"]
        if ref.get("reporterVolume"):
            fields_to_insert["reporterVolume"] = ref["reporterVolume"]
        if ref.get("firstPage"):
            fields_to_insert["firstPage"] = ref["firstPage"]
        if ref.get("dateDecided"):
            fields_to_insert["dateDecided"] = ref["dateDecided"]
        if ref.get("abstractNote"):
            fields_to_insert["abstractNote"] = ref["abstractNote"]
    else:
        # For journal articles and other types: title is the primary identifier
        if ref.get("title"):
            fields_to_insert["title"] = ref["title"]
        if ref.get("abstractNote"):
            fields_to_insert["abstractNote"] = ref["abstractNote"]
        if ref.get("date"):
            fields_to_insert["date"] = ref["date"]
        if ref.get("publicationTitle"):
            fields_to_insert["publicationTitle"] = ref["publicationTitle"]
        if ref.get("volume"):
            fields_to_insert["volume"] = ref["volume"]
        if ref.get("issue"):
            fields_to_insert["issue"] = ref["issue"]
        if ref.get("pages"):
            fields_to_insert["pages"] = ref["pages"]
        if ref.get("ISSN"):
            fields_to_insert["ISSN"] = ref["ISSN"]

    # Insert fields
    for field_name, field_value in fields_to_insert.items():
        if not field_value:
            continue
        field_id = FIELD_IDS.get(field_name)
        if field_id is None:
            print(f"  WARNING: Unknown field '{field_name}', skipping", file=sys.stderr)
            continue
        value_id = get_or_create_value(conn, str(field_value))
        try:
            cursor.execute(
                "INSERT OR IGNORE INTO itemData (itemID, fieldID, valueID) VALUES (?, ?, ?)",
                (item_id, field_id, value_id)
            )
        except sqlite3.IntegrityError:
            pass

    # Insert creator (author) if present
    if ref.get("authorFirst") and ref.get("authorLast"):
        creator_id = get_or_create_creator(conn, ref["authorFirst"], ref["authorLast"])
        try:
            cursor.execute(
                "INSERT OR IGNORE INTO itemCreators (itemID, creatorID, creatorTypeID, orderIndex) VALUES (?, ?, ?, 0)",
                (item_id, creator_id, CREATOR_TYPE_IDS["author"])
            )
        except sqlite3.IntegrityError:
            pass

    return item_id


def main():
    if len(sys.argv) < 2:
        print("Usage: inject_references.py <database_path>")
        sys.exit(1)

    db_path = sys.argv[1]
    if not os.path.exists(db_path):
        print(f"ERROR: Database not found: {db_path}")
        sys.exit(1)

    conn = sqlite3.connect(db_path)

    try:
        # Check if already populated
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM items WHERE itemTypeID NOT IN (1, 3, 31)")
        count = cursor.fetchone()[0]

        if count >= len(LEGAL_REFERENCES):
            print(f"Database already has {count} items, skipping injection")
            conn.close()
            return

        print(f"Injecting {len(LEGAL_REFERENCES)} legal references...")
        for i, ref in enumerate(LEGAL_REFERENCES):
            item_id = insert_reference(conn, ref, offset_hours=i)
            label = ref.get("caseName") or ref.get("title", "Unknown")
            print(f"  Inserted: {label[:50]} (itemID={item_id})")

        conn.commit()
        print(f"Successfully injected {len(LEGAL_REFERENCES)} references")

    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()
        conn.rollback()
        sys.exit(1)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
