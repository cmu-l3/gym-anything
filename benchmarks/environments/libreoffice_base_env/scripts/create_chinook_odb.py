#!/usr/bin/env python3
"""
Create a LibreOffice Base ODB file (HSQLDB embedded) from the Chinook SQLite database.

The Chinook database represents a digital media store with tables for:
  Artists, Albums, Tracks, Genres, MediaTypes, Playlists, PlaylistTrack,
  Customers, Employees, Invoices, InvoiceLines

Usage:
    python3 create_chinook_odb.py <sqlite_path> <odb_path>
"""
import sqlite3
import zipfile
import sys
import os
import re

# ODB file structure constants

# The mimetype file MUST be the FIRST entry in the ZIP, UNCOMPRESSED, no extra fields.
# This is required by the ODF specification - without it LibreOffice says the file is "corrupt".
MIMETYPE = "application/vnd.oasis.opendocument.base"

MANIFEST_XML = """<?xml version="1.0" encoding="UTF-8"?>
<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0" manifest:version="1.2">
 <manifest:file-entry manifest:full-path="/" manifest:version="1.2" manifest:media-type="application/vnd.oasis.opendocument.base"/>
 <manifest:file-entry manifest:full-path="content.xml" manifest:media-type="text/xml"/>
 <manifest:file-entry manifest:full-path="database/" manifest:media-type=""/>
 <manifest:file-entry manifest:full-path="database/script" manifest:media-type=""/>
 <manifest:file-entry manifest:full-path="database/properties" manifest:media-type=""/>
</manifest:manifest>"""

CONTENT_XML = """<?xml version="1.0" encoding="UTF-8"?>
<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" xmlns:xlink="http://www.w3.org/1999/xlink" xmlns:db="urn:oasis:names:tc:opendocument:xmlns:database:1.0" office:version="1.2">
 <office:body>
  <office:database>
   <db:data-source>
    <db:connection-data>
     <db:connection-resource xlink:href="sdbc:embedded:hsqldb" xlink:type="simple"/>
     <db:login db:is-password-required="false"/>
    </db:connection-data>
    <db:driver-settings db:system-driver-settings="" db:base-dn="" db:parameter-name-substitution="false"/>
    <db:application-connection-settings db:is-table-name-length-limited="false" db:append-table-alias-name="false" db:max-row-count="100">
     <db:table-filter>
      <db:table-include-filter>
       <db:table-filter-pattern>%</db:table-filter-pattern>
      </db:table-include-filter>
     </db:table-filter>
    </db:application-connection-settings>
   </db:data-source>
  </office:database>
 </office:body>
</office:document-content>"""

# HSQLDB 1.8 properties file
PROPERTIES = """#HSQL Database Engine 1.8.0
hsqldb.script_format=0
runtime.gc_interval=0
sql.enforce_strict_size=true
hsqldb.cache_size_scale=8
readonly=false
hsqldb.original_version=1.8.0
modified=yes"""


def sqlite_type_to_hsqldb(sqlite_type):
    """Map SQLite column type to HSQLDB 1.8 compatible type."""
    if not sqlite_type:
        return 'VARCHAR(256)'
    t = sqlite_type.upper().strip()

    if 'INT' in t:
        return 'INTEGER'
    elif 'NVARCHAR' in t or 'VARCHAR' in t:
        m = re.search(r'\((\d+)\)', t)
        n = m.group(1) if m else '256'
        return f'VARCHAR({n})'
    elif 'CHAR' in t:
        m = re.search(r'\((\d+)\)', t)
        n = m.group(1) if m else '256'
        return f'VARCHAR({n})'
    elif 'DATETIME' in t or 'TIMESTAMP' in t:
        return 'TIMESTAMP'
    elif 'DATE' in t:
        return 'DATE'
    elif 'NUMERIC' in t or 'DECIMAL' in t:
        m = re.search(r'\((\d+),\s*(\d+)\)', t)
        if m:
            return f'NUMERIC({m.group(1)},{m.group(2)})'
        return 'NUMERIC(10,2)'
    elif 'REAL' in t or 'DOUBLE' in t or 'FLOAT' in t:
        return 'DOUBLE'
    elif 'TEXT' in t or 'CLOB' in t:
        return 'LONGVARCHAR'
    elif 'BLOB' in t or 'BINARY' in t:
        return 'LONGVARBINARY'
    else:
        return 'VARCHAR(256)'


def format_value(val, col_type):
    """Format a Python value for HSQLDB script INSERT statement."""
    if val is None:
        return 'NULL'

    hsqldb_type = sqlite_type_to_hsqldb(col_type)

    if 'TIMESTAMP' in hsqldb_type or 'DATE' in hsqldb_type:
        v = str(val).strip()
        if not v or v == 'None':
            return 'NULL'
        # Ensure format: YYYY-MM-DD HH:MM:SS.0
        if len(v) == 10:
            v = v + ' 00:00:00.0'
        elif len(v) == 19:
            v = v + '.0'
        return f"'{v}'"
    elif isinstance(val, bool):
        return 'TRUE' if val else 'FALSE'
    elif isinstance(val, int):
        return str(val)
    elif isinstance(val, float):
        return str(val)
    else:
        # String value - escape backslashes first (HSQLDB treats \ as escape), then single quotes
        escaped = str(val).replace("\\", "\\\\").replace("'", "''")
        return f"'{escaped}'"


def get_table_order(cursor):
    """
    Return Chinook tables in insertion order respecting FK dependencies.
    Independent tables first, then dependent ones.
    """
    # Hard-coded dependency order for Chinook database
    chinook_order = [
        'MediaType', 'Genre', 'Artist', 'Employee', 'Customer',
        'Album', 'Track', 'Invoice', 'InvoiceLine', 'Playlist', 'PlaylistTrack'
    ]

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
    all_tables = [row[0] for row in cursor.fetchall()]

    # Use known order for Chinook tables, append any others alphabetically
    ordered = [t for t in chinook_order if t in all_tables]
    extras = [t for t in sorted(all_tables) if t not in chinook_order]
    return ordered + extras


def create_hsqldb_script(sqlite_path):
    """Create HSQLDB 1.8 script content from Chinook SQLite database."""
    conn = sqlite3.connect(sqlite_path)
    cursor = conn.cursor()

    # CRITICAL HSQLDB 1.8 initialization order:
    # 1. CREATE SCHEMA first (establishes PUBLIC schema)
    # 2. CREATE USER SA (SA is NOT auto-created when a script is provided)
    # 3. GRANT DBA TO SA (SA needs DBA role to access tables)
    # Without these, LibreOffice throws "User not found: SA" connection error
    script_parts = [
        "CREATE SCHEMA PUBLIC AUTHORIZATION DBA",
        'CREATE USER SA PASSWORD ""',
        "GRANT DBA TO SA",
    ]

    table_order = get_table_order(cursor)
    print(f"Tables to process: {table_order}")

    # --- CREATE TABLE statements ---
    for table_name in table_order:
        cursor.execute(f'PRAGMA table_info("{table_name}")')
        columns = cursor.fetchall()
        if not columns:
            continue

        col_defs = []
        pk_cols = []

        for col in columns:
            # col: (cid, name, type, notnull, dflt_value, pk)
            col_id, col_name, col_type, not_null, default_val, is_pk = col
            hsql_type = sqlite_type_to_hsqldb(col_type if col_type else 'VARCHAR')

            col_def = f'"{col_name}" {hsql_type}'
            if not_null:
                col_def += ' NOT NULL'

            col_defs.append(col_def)
            if is_pk:
                pk_cols.append(f'"{col_name}"')

        if pk_cols:
            pk_list = ','.join(pk_cols)
            col_defs.append(f'CONSTRAINT "PK_{table_name}" PRIMARY KEY ({pk_list})')

        create_stmt = f'CREATE TABLE PUBLIC."{table_name}" ({",".join(col_defs)})'
        script_parts.append(create_stmt)
        print(f"  Created schema for table: {table_name} ({len(columns)} columns)")

    # --- INSERT statements ---
    for table_name in table_order:
        cursor.execute(f'PRAGMA table_info("{table_name}")')
        columns = cursor.fetchall()
        if not columns:
            continue

        col_types = {col[1]: (col[2] if col[2] else 'VARCHAR') for col in columns}
        col_names = [col[1] for col in columns]

        cursor.execute(f'SELECT * FROM "{table_name}"')
        rows = cursor.fetchall()

        for row in rows:
            values = []
            for i, val in enumerate(row):
                col_name = col_names[i]
                col_type = col_types.get(col_name, 'VARCHAR')
                values.append(format_value(val, col_type))

            insert_stmt = f'INSERT INTO PUBLIC."{table_name}" VALUES({",".join(values)})'
            script_parts.append(insert_stmt)

        print(f"  Inserted {len(rows)} rows into: {table_name}")

    # --- Final HSQLDB setup command ---
    # NOTE: Do NOT use GRANT DBA TO SA or CREATE USER SA - SA is HSQLDB's built-in DBA.
    # Attempting to create SA causes "User not found: SA" connection error in LibreOffice Base.
    script_parts.append("SET WRITE_DELAY 0")

    conn.close()
    return "\n".join(script_parts)


def create_odb(sqlite_path, odb_path):
    """Create a LibreOffice Base ODB file from Chinook SQLite."""
    print(f"Reading Chinook SQLite from: {sqlite_path}")
    print(f"SQLite file size: {os.path.getsize(sqlite_path):,} bytes")

    script_content = create_hsqldb_script(sqlite_path)
    print(f"Generated HSQLDB script: {len(script_content):,} characters")

    print(f"Creating ODB file: {odb_path}")
    with zipfile.ZipFile(odb_path, 'w', zipfile.ZIP_DEFLATED) as zf:
        # CRITICAL: 'mimetype' must be FIRST entry, UNCOMPRESSED (ZIP_STORED), no extra fields.
        # This is the ODF specification requirement. Without it LO reports "corrupt file".
        mimetype_info = zipfile.ZipInfo('mimetype')
        mimetype_info.compress_type = zipfile.ZIP_STORED
        zf.writestr(mimetype_info, MIMETYPE)

        # Remaining files are compressed normally
        zf.writestr('META-INF/manifest.xml', MANIFEST_XML)
        zf.writestr('content.xml', CONTENT_XML)
        zf.writestr('database/properties', PROPERTIES)
        zf.writestr('database/script', script_content)

    size = os.path.getsize(odb_path)
    print(f"ODB file created successfully: {size:,} bytes")


if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <sqlite_path> <odb_path>")
        sys.exit(1)

    sqlite_path = sys.argv[1]
    odb_path = sys.argv[2]

    if not os.path.exists(sqlite_path):
        print(f"ERROR: SQLite file not found: {sqlite_path}")
        sys.exit(1)

    create_odb(sqlite_path, odb_path)
    print("Done!")
