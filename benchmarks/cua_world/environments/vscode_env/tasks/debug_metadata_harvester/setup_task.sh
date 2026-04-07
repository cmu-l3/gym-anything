#!/bin/bash
set -e
echo "=== Setting up Debug Metadata Harvester Task ==="

source /workspace/scripts/task_utils.sh

# Record timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/metadata_harvester"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
cd "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# Create sample OAI-PMH XML Data
# ─────────────────────────────────────────────────────────────
sudo -u ga cat > "$WORKSPACE_DIR/data/arxiv_oai_sample.xml" << 'XML_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<OAI-PMH xmlns="http://www.openarchives.org/OAI/2.0/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/ http://www.openarchives.org/OAI/2.0/OAI-PMH.xsd">
  <responseDate>2023-10-24T12:00:00Z</responseDate>
  <request verb="ListRecords" metadataPrefix="oai_dc">http://export.arxiv.org/oai2</request>
  <ListRecords>
    <record>
      <header>
        <identifier>oai:arXiv.org:0704.0001</identifier>
        <datestamp>2007-04-02</datestamp>
        <setSpec>physics:hep-ph</setSpec>
      </header>
      <metadata>
        <oai_dc:dc xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai_dc/ http://www.openarchives.org/OAI/2.0/oai_dc.xsd">
          <dc:title>  First string theory
          on a
          multiverse   </dc:title>
          <dc:creator>Balázs, C.</dc:creator>
          <dc:creator>Berger, E. L.</dc:creator>
          <dc:creator>Nadolsky, P. M.</dc:creator>
          <dc:creator>Yuan, C. -P.</dc:creator>
          <dc:date>2007-04-02</dc:date>
        </oai_dc:dc>
      </metadata>
    </record>
    <record>
      <header status="deleted">
        <identifier>oai:arXiv.org:0704.0002</identifier>
        <datestamp>2007-05-23</datestamp>
        <setSpec>physics:math-ph</setSpec>
      </header>
    </record>
    <record>
      <header>
        <identifier>oai:arXiv.org:0704.0027</identifier>
        <datestamp>2007-04-03</datestamp>
        <setSpec>math:math.CO</setSpec>
      </header>
      <metadata>
        <oai_dc:dc xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai_dc/ http://www.openarchives.org/OAI/2.0/oai_dc.xsd">
          <dc:title>On the complexity of the Schrödinger equation</dc:title>
          <dc:creator>Štěpán, J.</dc:creator>
          <dc:date>2007-04-03</dc:date>
        </oai_dc:dc>
      </metadata>
    </record>
    <record>
      <header status="deleted">
        <identifier>oai:arXiv.org:0704.0035</identifier>
        <datestamp>2007-06-11</datestamp>
        <setSpec>q-bio:q-bio.NC</setSpec>
      </header>
    </record>
    <record>
      <header>
        <identifier>oai:arXiv.org:0704.0099</identifier>
        <datestamp>2007-04-12</datestamp>
        <setSpec>astro-ph</setSpec>
      </header>
      <metadata>
        <oai_dc:dc xmlns:oai_dc="http://www.openarchives.org/OAI/2.0/oai_dc/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.openarchives.org/OAI/2.0/oai_dc/ http://www.openarchives.org/OAI/2.0/oai_dc.xsd">
          <dc:title>Star formation in the local universe</dc:title>
          <dc:creator>Smith, A.</dc:creator>
          <dc:date>2007-04-12</dc:date>
        </oai_dc:dc>
      </metadata>
    </record>
  </ListRecords>
</OAI-PMH>
XML_EOF

# ─────────────────────────────────────────────────────────────
# Create Database Setup script
# ─────────────────────────────────────────────────────────────
sudo -u ga cat > "$WORKSPACE_DIR/db_setup.py" << 'PY_EOF'
import sqlite3

def init_db():
    conn = sqlite3.connect('output.sqlite')
    cursor = conn.cursor()
    cursor.execute("DROP TABLE IF EXISTS records")
    cursor.execute('''
        CREATE TABLE records (
            id TEXT PRIMARY KEY,
            title TEXT,
            author TEXT,
            date TEXT
        )
    ''')
    conn.commit()
    conn.close()
PY_EOF

# ─────────────────────────────────────────────────────────────
# Create Buggy Harvester script
# ─────────────────────────────────────────────────────────────
sudo -u ga cat > "$WORKSPACE_DIR/harvester.py" << 'PY_EOF'
import xml.etree.ElementTree as ET
import sqlite3
import db_setup

def parse_and_store(xml_file='data/arxiv_oai_sample.xml'):
    db_setup.init_db()
    conn = sqlite3.connect('output.sqlite')
    cursor = conn.cursor()

    # Open XML
    with open(xml_file, 'r', encoding='ascii', errors='ignore') as f:
        tree = ET.parse(f)
    root = tree.getroot()

    # Known namespaces in the XML
    ns = {
        'oai_dc': 'http://www.openarchives.org/OAI/2.0/oai_dc/',
        'dc': 'http://purl.org/dc/elements/1.1/'
    }

    # Find all records
    records = root.findall('.//record')

    for record in records:
        header = record.find('.//header')
        identifier = header.find('identifier').text if header is not None else 'unknown'

        # Extract metadata
        metadata_node = record.find('.//metadata')
        dc_node = metadata_node.find('.//oai_dc:dc', namespaces=ns)

        # Extract Title
        title_node = dc_node.find('dc:title', namespaces=ns)
        title = title_node.text if title_node is not None else ""

        # Extract Creator (Author)
        creator_node = dc_node.find('dc:creator', namespaces=ns)
        author = creator_node.text if creator_node is not None else ""

        # Extract Date
        date_node = dc_node.find('dc:date', namespaces=ns)
        date = date_node.text if date_node is not None else ""

        cursor.execute("INSERT INTO records (id, title, author, date) VALUES (?, ?, ?, ?)",
                       (identifier, title, author, date))

    conn.commit()
    conn.close()
    print(f"Harvest complete. Processed {len(records)} records.")

if __name__ == "__main__":
    parse_and_store()
PY_EOF

# ─────────────────────────────────────────────────────────────
# Create Local Test Suite
# ─────────────────────────────────────────────────────────────
sudo -u ga cat > "$WORKSPACE_DIR/tests/test_harvester.py" << 'PY_EOF'
import unittest
import sqlite3
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
import harvester

class TestHarvester(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            harvester.parse_and_store('data/arxiv_oai_sample.xml')
            cls.setup_error = None
        except Exception as e:
            cls.setup_error = e

    def test_01_execution(self):
        self.assertIsNone(self.setup_error, f"Harvester crashed during execution: {self.setup_error}")

    def test_02_record_count(self):
        if self.setup_error: self.skipTest("Setup failed")
        conn = sqlite3.connect('output.sqlite')
        count = conn.execute("SELECT COUNT(*) FROM records").fetchone()[0]
        conn.close()
        self.assertEqual(count, 3, "Expected exactly 3 valid records. Deleted records should be skipped.")

    def test_03_authors_joined(self):
        if self.setup_error: self.skipTest("Setup failed")
        conn = sqlite3.connect('output.sqlite')
        row = conn.execute("SELECT author FROM records WHERE id='oai:arXiv.org:0704.0001'").fetchone()
        conn.close()
        self.assertIsNotNone(row, "Record 0704.0001 not found")
        author = row[0]
        self.assertIn(";", author, "Multiple authors should be joined by '; '")
        self.assertEqual(author, "Balázs, C.; Berger, E. L.; Nadolsky, P. M.; Yuan, C. -P.")

    def test_04_unicode_preservation(self):
        if self.setup_error: self.skipTest("Setup failed")
        conn = sqlite3.connect('output.sqlite')
        row = conn.execute("SELECT author FROM records WHERE id='oai:arXiv.org:0704.0027'").fetchone()
        conn.close()
        self.assertIsNotNone(row, "Record 0704.0027 not found")
        self.assertEqual(row[0], "Štěpán, J.", "Unicode characters (diacritics) were lost or mangled.")

    def test_05_title_whitespace(self):
        if self.setup_error: self.skipTest("Setup failed")
        conn = sqlite3.connect('output.sqlite')
        row = conn.execute("SELECT title FROM records WHERE id='oai:arXiv.org:0704.0001'").fetchone()
        conn.close()
        self.assertIsNotNone(row, "Record 0704.0001 not found")
        title = row[0]
        self.assertNotIn("\n", title, "Titles should not contain newlines.")
        self.assertNotIn("  ", title, "Multiple spaces should be collapsed.")
        self.assertEqual(title, "First string theory on a multiverse")

if __name__ == '__main__':
    unittest.main()
PY_EOF

# ─────────────────────────────────────────────────────────────
# Open VSCode and Initialize Display
# ─────────────────────────────────────────────────────────────
chown -R ga:ga "$WORKSPACE_DIR"

# Ensure VSCode is stopped
pkill -f "code" 2>/dev/null || true
sleep 2

echo "Starting VSCode..."
sudo -u ga DISPLAY=:1 code "$WORKSPACE_DIR" > /tmp/vscode_launch.log 2>&1 &

wait_for_vscode 30
focus_vscode_window

# Wait for UI to stabilize and capture initial screenshot
sleep 3
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="