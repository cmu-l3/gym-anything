#!/bin/bash
# Setup script for Biodiversity Hotspot Analysis task
echo "=== Setting up Biodiversity Hotspot Analysis ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /home/ga/.task_start_time

# ---------------------------------------------------------------
# 1. Verify Oracle is running
# ---------------------------------------------------------------
CONTAINER_STATUS=$(sudo docker inspect --format='{{.State.Status}}' oracle-xe 2>/dev/null)
if [ "$CONTAINER_STATUS" != "running" ]; then
    echo "ERROR: Oracle container not running"
    exit 1
fi
echo "Oracle container is running"

# ---------------------------------------------------------------
# 2. Clean up previous run artifacts
# ---------------------------------------------------------------
echo "Cleaning up previous run artifacts..."

oracle_query "BEGIN
  EXECUTE IMMEDIATE 'DROP USER wildlife_bio CASCADE';
EXCEPTION WHEN OTHERS THEN NULL;
END;
/
EXIT;" "system" 2>/dev/null || true

rm -f /home/ga/Documents/exports/conservation_gap_report.csv 2>/dev/null || true
mkdir -p /home/ga/Documents/exports
chmod 777 /home/ga/Documents/exports

sleep 2

# ---------------------------------------------------------------
# 3. Create WILDLIFE_BIO schema and User
# ---------------------------------------------------------------
echo "Creating WILDLIFE_BIO schema (wildlife_bio user)..."

oracle_query "CREATE USER wildlife_bio IDENTIFIED BY Wildlife2024
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;
GRANT CONNECT TO wildlife_bio;
GRANT RESOURCE TO wildlife_bio;
GRANT CREATE VIEW TO wildlife_bio;
GRANT CREATE PROCEDURE TO wildlife_bio;
GRANT CREATE SESSION TO wildlife_bio;
GRANT CREATE TABLE TO wildlife_bio;
GRANT CREATE ANY DIRECTORY TO wildlife_bio;
EXIT;" "system"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create wildlife_bio user"
    exit 1
fi

# Set up UTL_FILE directory inside the oracle container mapped to the host
sudo docker exec -i oracle-xe mkdir -p /opt/oracle/exports
sudo docker exec -i oracle-xe chmod 777 /opt/oracle/exports

oracle_query "CREATE OR REPLACE DIRECTORY EXPORT_DIR AS '/opt/oracle/exports';
GRANT READ, WRITE ON DIRECTORY EXPORT_DIR TO wildlife_bio;
EXIT;" "system"

echo "wildlife_bio user created with required privileges"

# ---------------------------------------------------------------
# 4. Create schema tables
# ---------------------------------------------------------------
echo "Creating schema tables..."

sudo docker exec -i oracle-xe sqlplus -s wildlife_bio/Wildlife2024@//localhost:1521/XEPDB1 << 'EOSQL'
SET ECHO OFF FEEDBACK ON

CREATE TABLE taxonomic_hierarchy (
    taxon_id        NUMBER PRIMARY KEY,
    parent_taxon_id NUMBER REFERENCES taxonomic_hierarchy(taxon_id),
    taxon_rank      VARCHAR2(30),
    taxon_name      VARCHAR2(120),
    taxon_rank_order NUMBER
);

CREATE TABLE species (
    species_id          NUMBER PRIMARY KEY,
    taxon_id            NUMBER REFERENCES taxonomic_hierarchy(taxon_id),
    scientific_name     VARCHAR2(200),
    common_name         VARCHAR2(200),
    iucn_status         VARCHAR2(2),
    iucn_status_name    VARCHAR2(50),
    gbif_species_key    NUMBER,
    is_endemic          CHAR(1)
);

CREATE TABLE grid_sites (
    site_id         NUMBER PRIMARY KEY,
    site_name       VARCHAR2(100),
    center_lat      NUMBER(9,6),
    center_lon      NUMBER(10,6),
    region          VARCHAR2(60)
);

CREATE TABLE occurrences (
    occurrence_id   NUMBER PRIMARY KEY,
    species_id      NUMBER REFERENCES species(species_id),
    site_id         NUMBER REFERENCES grid_sites(site_id),
    latitude        NUMBER(9,6),
    longitude       NUMBER(10,6),
    observation_date DATE,
    basis_of_record VARCHAR2(30),
    observer        VARCHAR2(200)
);

CREATE TABLE protected_areas (
    area_id         NUMBER PRIMARY KEY,
    area_name       VARCHAR2(200),
    designation     VARCHAR2(100),
    center_lat      NUMBER(9,6),
    center_lon      NUMBER(10,6),
    area_sq_km      NUMBER(10,2)
);

-- Insert Taxonomy Data (Brown Bear lineage)
INSERT INTO taxonomic_hierarchy VALUES (1, NULL, 'Kingdom', 'Animalia', 1);
INSERT INTO taxonomic_hierarchy VALUES (2, 1, 'Phylum', 'Chordata', 2);
INSERT INTO taxonomic_hierarchy VALUES (3, 2, 'Class', 'Mammalia', 3);
INSERT INTO taxonomic_hierarchy VALUES (4, 3, 'Order', 'Carnivora', 4);
INSERT INTO taxonomic_hierarchy VALUES (5, 4, 'Family', 'Ursidae', 5);
INSERT INTO taxonomic_hierarchy VALUES (6, 5, 'Genus', 'Ursus', 6);
INSERT INTO taxonomic_hierarchy VALUES (7, 6, 'Species', 'Ursus arctos', 7);

-- Insert Taxonomy Data (Mountain Lion lineage)
INSERT INTO taxonomic_hierarchy VALUES (8, 4, 'Family', 'Felidae', 5);
INSERT INTO taxonomic_hierarchy VALUES (9, 8, 'Genus', 'Puma', 6);
INSERT INTO taxonomic_hierarchy VALUES (10, 9, 'Species', 'Puma concolor', 7);

-- Insert Taxonomy Data (California Condor lineage)
INSERT INTO taxonomic_hierarchy VALUES (11, 2, 'Class', 'Aves', 3);
INSERT INTO taxonomic_hierarchy VALUES (12, 11, 'Order', 'Cathartiformes', 4);
INSERT INTO taxonomic_hierarchy VALUES (13, 12, 'Family', 'Cathartidae', 5);
INSERT INTO taxonomic_hierarchy VALUES (14, 13, 'Genus', 'Gymnogyps', 6);
INSERT INTO taxonomic_hierarchy VALUES (15, 14, 'Species', 'Gymnogyps californianus', 7);

-- Insert Species
INSERT INTO species VALUES (101, 7, 'Ursus arctos', 'Brown Bear', 'LC', 'Least Concern', 2433433, 'N');
INSERT INTO species VALUES (102, 10, 'Puma concolor', 'Mountain Lion', 'LC', 'Least Concern', 2435099, 'N');
INSERT INTO species VALUES (103, 15, 'Gymnogyps californianus', 'California Condor', 'CR', 'Critically Endangered', 2481931, 'Y');

-- Insert Protected Areas
-- Yosemite NP (37.8651, -119.5383)
INSERT INTO protected_areas VALUES (1, 'Yosemite National Park', 'National Park', 37.8651, -119.5383, 3080.74);
-- Joshua Tree NP (33.8734, -115.9010)
INSERT INTO protected_areas VALUES (2, 'Joshua Tree National Park', 'National Park', 33.8734, -115.9010, 3195.99);

-- Insert Grid Sites
-- Site 1: Close to Yosemite (High coverage)
INSERT INTO grid_sites VALUES (1, 'Sierra Central Grid 04', 37.8500, -119.5500, 'Sierra Nevada');
-- Site 2: Hotspot away from PAs (Gap) - e.g., near Auburn (38.8950, -121.0760)
INSERT INTO grid_sites VALUES (2, 'Foothills North Grid 12', 38.8950, -121.0760, 'Sierra Foothills');
-- Site 3: Close to Joshua Tree
INSERT INTO grid_sites VALUES (3, 'Mojave South Grid 08', 33.8800, -115.9100, 'Mojave Desert');

-- Insert Occurrences
-- Site 1 (Yosemite area) - Mix of Bear and Mountain Lion
INSERT INTO occurrences VALUES (1001, 101, 1, 37.8510, -119.5510, DATE '2023-04-15', 'HUMAN_OBSERVATION', 'J. Muir');
INSERT INTO occurrences VALUES (1002, 101, 1, 37.8520, -119.5520, DATE '2023-05-10', 'HUMAN_OBSERVATION', 'A. Adams');
INSERT INTO occurrences VALUES (1003, 102, 1, 37.8490, -119.5490, DATE '2023-05-12', 'MACHINE_OBSERVATION', 'Cam-44');
INSERT INTO occurrences VALUES (1004, 101, 1, 37.8505, -119.5505, DATE '2023-06-01', 'HUMAN_OBSERVATION', 'T. Roosevelt');

-- Site 2 (Hotspot gap) - Mix of all three, highly diverse
INSERT INTO occurrences VALUES (2001, 101, 2, 38.8940, -121.0750, DATE '2023-03-20', 'MACHINE_OBSERVATION', 'Cam-12');
INSERT INTO occurrences VALUES (2002, 102, 2, 38.8960, -121.0770, DATE '2023-04-05', 'HUMAN_OBSERVATION', 'S. Davis');
INSERT INTO occurrences VALUES (2003, 102, 2, 38.8955, -121.0765, DATE '2023-05-22', 'HUMAN_OBSERVATION', 'S. Davis');
INSERT INTO occurrences VALUES (2004, 103, 2, 38.8950, -121.0760, DATE '2023-06-15', 'HUMAN_OBSERVATION', 'B. Bird');
INSERT INTO occurrences VALUES (2005, 103, 2, 38.8945, -121.0755, DATE '2023-07-10', 'MACHINE_OBSERVATION', 'Cam-14');
INSERT INTO occurrences VALUES (2006, 101, 2, 38.8952, -121.0762, DATE '2023-08-01', 'HUMAN_OBSERVATION', 'L. Chen');

-- Site 3 (Joshua Tree area) - Mostly Mountain Lion
INSERT INTO occurrences VALUES (3001, 102, 3, 33.8810, -115.9110, DATE '2023-01-10', 'MACHINE_OBSERVATION', 'Cam-99');
INSERT INTO occurrences VALUES (3002, 102, 3, 33.8790, -115.9090, DATE '2023-02-14', 'MACHINE_OBSERVATION', 'Cam-99');

COMMIT;
EXIT;
EOSQL

echo "Data populated successfully."

# Pre-configure SQL Developer Connection
ensure_hr_connection "Wildlife DB" "wildlife_bio" "Wildlife2024"

# Ensure SQL Developer is running
if ! pgrep -f "sqldeveloper" > /dev/null; then
    echo "Starting SQL Developer..."
    su - ga -c "DISPLAY=:1 /usr/local/bin/sqldeveloper &"
    sleep 20
fi

# Try to open the connection in the GUI
open_hr_connection_in_sqldeveloper

# Create a symlink mapping for the container export to the host
# The agent writes to EXPORT_DIR mapped to /opt/oracle/exports inside container.
# We mount that container directory to the host system via Docker volume or copy on export.
# To make it accessible during task via the expected path for the user:
# Actually, the user can't see inside the container directly.
# We will use `docker cp` in export_result.sh to retrieve the file from /opt/oracle/exports.
# For their instructions, they are told to write to EXPORT_DIR.

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task Setup Complete ==="