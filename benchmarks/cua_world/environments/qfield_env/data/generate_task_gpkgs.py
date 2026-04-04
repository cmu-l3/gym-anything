#!/usr/bin/env python3
"""
Generate GeoPackage files for 5 hard QField tasks.
Run on HOST (not Android) to create data files that are mounted read-only into the AVD.

Occupations (from master_dataset.csv):
  - 49-2022.00: Telecommunications Equipment Installers/Repairers ($19.9M GDP)
  - 45-2092.00: Farmworkers/Laborers, Crop ($4.7M GDP)
  - 45-4011.00: Forest and Conservation Workers ($2.7M GDP)
"""

import sqlite3
import struct
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


# ---------------------------------------------------------------------------
# Geometry encoding helpers
# ---------------------------------------------------------------------------

def make_point_blob(lon, lat, srid=4326):
    """GPKG geometry blob for a WGS84 point (no envelope, little-endian)."""
    header = b'GP\x00\x01' + struct.pack('<i', srid)
    wkb = b'\x01' + struct.pack('<I', 1) + struct.pack('<dd', lon, lat)
    return header + wkb


def make_polygon_blob(outer_ring, srid=4326):
    """GPKG geometry blob for a simple polygon (one ring, CCW for exterior)."""
    header = b'GP\x00\x01' + struct.pack('<i', srid)
    wkb = b'\x01' + struct.pack('<I', 3)   # type = Polygon
    wkb += struct.pack('<I', 1)            # num_rings = 1
    wkb += struct.pack('<I', len(outer_ring))
    for lon, lat in outer_ring:
        wkb += struct.pack('<dd', lon, lat)
    return header + wkb


def make_linestring_blob(coords, srid=4326):
    """GPKG geometry blob for a linestring."""
    header = b'GP\x00\x01' + struct.pack('<i', srid)
    wkb = b'\x01' + struct.pack('<I', 2)   # type = LineString
    wkb += struct.pack('<I', len(coords))
    for lon, lat in coords:
        wkb += struct.pack('<dd', lon, lat)
    return header + wkb


def init_gpkg(conn):
    """Create minimum GPKG metadata tables and register WGS84."""
    c = conn.cursor()
    c.executescript("""
        CREATE TABLE IF NOT EXISTS gpkg_spatial_ref_sys (
            srs_name TEXT NOT NULL,
            srs_id INTEGER NOT NULL PRIMARY KEY,
            organization TEXT NOT NULL,
            organization_coordsys_id INTEGER NOT NULL,
            definition TEXT NOT NULL,
            description TEXT
        );
        CREATE TABLE IF NOT EXISTS gpkg_contents (
            table_name TEXT NOT NULL PRIMARY KEY,
            data_type TEXT NOT NULL,
            identifier TEXT,
            description TEXT DEFAULT '',
            last_change TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ','now')),
            min_x REAL, min_y REAL, max_x REAL, max_y REAL,
            srs_id INTEGER
        );
        CREATE TABLE IF NOT EXISTS gpkg_geometry_columns (
            table_name TEXT NOT NULL,
            column_name TEXT NOT NULL,
            geometry_type_name TEXT NOT NULL,
            srs_id INTEGER NOT NULL,
            z TINYINT NOT NULL,
            m TINYINT NOT NULL,
            CONSTRAINT pk_geom_cols PRIMARY KEY (table_name, column_name)
        );
    """)
    wgs84_def = (
        'GEOGCS["WGS 84",DATUM["World Geodetic System 1984",'
        'SPHEROID["WGS 84",6378137,298.257223563]],'
        'PRIMEM["Greenwich",0],UNIT["degree",0.017453292519943295],'
        'AUTHORITY["EPSG","4326"]]'
    )
    c.execute(
        "INSERT OR IGNORE INTO gpkg_spatial_ref_sys "
        "(srs_name,srs_id,organization,organization_coordsys_id,definition,description) "
        "VALUES (?,?,?,?,?,?)",
        ("WGS 84", 4326, "EPSG", 4326, wgs84_def, "World Geodetic System 1984")
    )
    conn.commit()


def register_table(conn, table_name, geom_col, geom_type, bbox, srid=4326):
    c = conn.cursor()
    min_x, min_y, max_x, max_y = bbox
    c.execute(
        "INSERT OR REPLACE INTO gpkg_contents "
        "(table_name,data_type,identifier,description,min_x,min_y,max_x,max_y,srs_id) "
        "VALUES (?,'features',?,'',?,?,?,?,?)",
        (table_name, table_name, min_x, min_y, max_x, max_y, srid)
    )
    c.execute(
        "INSERT OR REPLACE INTO gpkg_geometry_columns "
        "(table_name,column_name,geometry_type_name,srs_id,z,m) "
        "VALUES (?,?,?,?,0,0)",
        (table_name, geom_col, geom_type, srid)
    )
    conn.commit()


# ---------------------------------------------------------------------------
# Task 1: telecom_survey.gpkg  (Hartford, CT – utility poles)
# Occupation: 49-2022.00 Telecom Equipment Installers/Repairers
# ---------------------------------------------------------------------------

def create_telecom_survey():
    path = os.path.join(BASE_DIR, "telecom_survey.gpkg")
    if os.path.exists(path):
        os.remove(path)
    conn = sqlite3.connect(path)
    init_gpkg(conn)

    c = conn.cursor()
    c.execute("""
        CREATE TABLE utility_poles (
            fid INTEGER PRIMARY KEY AUTOINCREMENT,
            geom BLOB,
            pole_id TEXT NOT NULL,
            street_address TEXT,
            installation_year INTEGER,
            material TEXT,
            height_m REAL,
            condition TEXT,
            last_inspected TEXT,
            replacement_scheduled TEXT DEFAULT ''
        )
    """)

    # 25 poles around Hartford CT (center ~41.763°N, 72.685°W)
    # Real-approximate street grid coordinates
    poles = [
        # pole_id, (lon, lat), install_year, material, height_m, condition, last_inspected
        ("HFD-001", (-72.6851, 41.7631), 2008, "wood",     12.2, "fair",      "2023-04-10"),
        ("HFD-002", (-72.6893, 41.7658), 2011, "wood",     11.0, "fair",      "2023-04-10"),
        ("HFD-003", (-72.6822, 41.7645), 2013, "wood",     10.5, "fair",      "2023-04-11"),
        ("HFD-004", (-72.6774, 41.7612), 2015, "wood",     12.0, "fair",      "2023-04-11"),
        ("HFD-005", (-72.6841, 41.7598), 2009, "wood",     11.5, "fair",      "2023-04-12"),
        ("HFD-006", (-72.6912, 41.7577), 2010, "wood",     10.8, "fair",      "2023-04-12"),
        ("HFD-007", (-72.6760, 41.7665), 2012, "wood",     11.2, "good",      "2023-04-13"),
        ("HFD-008", (-72.6803, 41.7683), 2014, "wood",     12.5, "fair",      "2023-04-13"),
        # Post-2015 wood poles (should NOT be flagged)
        ("HFD-009", (-72.6870, 41.7621), 2017, "wood",     10.9, "good",      "2024-02-15"),
        ("HFD-010", (-72.6930, 41.7640), 2019, "wood",     11.0, "good",      "2024-02-15"),
        ("HFD-011", (-72.6784, 41.7630), 2021, "wood",     11.5, "excellent", "2024-02-16"),
        ("HFD-012", (-72.6745, 41.7648), 2023, "wood",     12.0, "excellent", "2024-02-16"),
        # Concrete poles (should NOT be flagged regardless of year)
        ("HFD-013", (-72.6860, 41.7590), 2005, "concrete", 13.5, "good",      "2024-03-01"),
        ("HFD-014", (-72.6831, 41.7573), 2007, "concrete", 13.0, "good",      "2024-03-01"),
        ("HFD-015", (-72.6799, 41.7555), 2009, "concrete", 14.0, "good",      "2024-03-02"),
        ("HFD-016", (-72.6770, 41.7570), 2012, "concrete", 13.5, "good",      "2024-03-02"),
        ("HFD-017", (-72.6745, 41.7588), 2014, "concrete", 12.8, "good",      "2024-03-03"),
        ("HFD-018", (-72.6720, 41.7605), 2016, "concrete", 13.2, "good",      "2024-03-03"),
        ("HFD-019", (-72.6710, 41.7625), 2018, "concrete", 13.0, "excellent", "2024-03-04"),
        ("HFD-020", (-72.6735, 41.7645), 2020, "concrete", 13.5, "excellent", "2024-03-04"),
        ("HFD-021", (-72.6958, 41.7598), 2022, "concrete", 12.5, "excellent", "2024-03-05"),
        ("HFD-022", (-72.6945, 41.7617), 2013, "concrete", 13.0, "good",      "2024-03-05"),
        ("HFD-023", (-72.6924, 41.7636), 2011, "concrete", 13.5, "good",      "2024-03-06"),
        ("HFD-024", (-72.6907, 41.7655), 2009, "concrete", 14.0, "fair",      "2024-03-06"),
        ("HFD-025", (-72.6880, 41.7672), 2007, "concrete", 13.8, "fair",      "2024-03-07"),
    ]

    for row in poles:
        pole_id, (lon, lat), yr, mat, ht, cond, insp = row
        addr = f"{int(abs(lon * 1000) % 9000 + 100)} Main St, Hartford CT"
        c.execute(
            "INSERT INTO utility_poles "
            "(geom,pole_id,street_address,installation_year,material,height_m,"
            "condition,last_inspected,replacement_scheduled) "
            "VALUES (?,?,?,?,?,?,?,?,?)",
            (make_point_blob(lon, lat), pole_id, addr, yr, mat, ht, cond, insp, "")
        )

    conn.commit()
    register_table(conn, "utility_poles", "geom", "POINT",
                   (-72.6960, 41.7555, -72.6710, 41.7685))
    conn.close()
    print(f"Created: {path}")
    print(f"  Qualifying poles (wood, install_year<=2015): HFD-001..008 (8 poles)")


# ---------------------------------------------------------------------------
# Task 2: iowa_crop_survey.gpkg  (Jasper County, IA – crop management zones)
# Occupation: 45-2092.00 Farmworkers/Laborers, Crop
# ---------------------------------------------------------------------------

def create_iowa_crop_survey():
    path = os.path.join(BASE_DIR, "iowa_crop_survey.gpkg")
    if os.path.exists(path):
        os.remove(path)
    conn = sqlite3.connect(path)
    init_gpkg(conn)

    c = conn.cursor()
    c.execute("""
        CREATE TABLE crop_zones (
            fid INTEGER PRIMARY KEY AUTOINCREMENT,
            geom BLOB,
            zone_id TEXT NOT NULL,
            field_name TEXT,
            crop_type TEXT,
            area_acres REAL,
            scout_date TEXT DEFAULT '',
            pest_observed TEXT DEFAULT '',
            infestation_level TEXT DEFAULT '',
            action_required TEXT DEFAULT '',
            scout_notes TEXT DEFAULT ''
        )
    """)

    # 30 zones in a 6-column (A-F) × 5-row (1-5) grid
    # Center: 41.685°N, -93.050°W; each zone ~0.003° wide × 0.0025° tall
    base_lon = -93.066
    base_lat = 41.679
    dlon = 0.003
    dlat = 0.0025
    cols = list("ABCDEF")
    rows = list("12345")

    for ri, row_label in enumerate(rows):
        for ci, col_label in enumerate(cols):
            zone_id = f"{col_label}{row_label}"
            lon0 = base_lon + ci * dlon
            lat0 = base_lat + ri * dlat
            lon1 = lon0 + dlon
            lat1 = lat0 + dlat
            # CCW ring for exterior polygon
            ring = [
                (lon0, lat0), (lon1, lat0), (lon1, lat1),
                (lon0, lat1), (lon0, lat0)
            ]
            area = 18.5 + (ci + ri) * 0.3   # ~18-22 acres per zone
            field_name = f"Section {14 + ri * 6 + ci}"
            c.execute(
                "INSERT INTO crop_zones "
                "(geom,zone_id,field_name,crop_type,area_acres,"
                "scout_date,pest_observed,infestation_level,action_required,scout_notes) "
                "VALUES (?,?,?,'corn',?,?,?,?,?,?)",
                (make_polygon_blob(ring), zone_id, field_name, round(area, 1),
                 "", "", "", "", "")
            )

    conn.commit()
    register_table(conn, "crop_zones", "geom", "POLYGON",
                   (base_lon, base_lat, base_lon + 6 * dlon, base_lat + 5 * dlat))
    conn.close()
    print(f"Created: {path}")
    print(f"  30 zones (A-F, 1-5); target zones per scouting_notes: B2,C3,D1,E4,F2")


# ---------------------------------------------------------------------------
# Task 3: forest_inventory.gpkg  (Green Mountain NF, VT – forest stands)
# Occupation: 45-4011.00 Forest and Conservation Workers
# ---------------------------------------------------------------------------

def create_forest_inventory():
    path = os.path.join(BASE_DIR, "forest_inventory.gpkg")
    if os.path.exists(path):
        os.remove(path)
    conn = sqlite3.connect(path)
    init_gpkg(conn)

    c = conn.cursor()
    # Stand polygons
    c.execute("""
        CREATE TABLE forest_stands (
            fid INTEGER PRIMARY KEY AUTOINCREMENT,
            geom BLOB,
            stand_id TEXT NOT NULL,
            compartment TEXT,
            dominant_species TEXT,
            stand_age_years INTEGER,
            last_inventory_year INTEGER,
            basal_area_m2ha REAL,
            stocking_pct INTEGER,
            condition TEXT
        )
    """)
    # Tree inventory points (empty at task start)
    c.execute("""
        CREATE TABLE tree_samples (
            fid INTEGER PRIMARY KEY AUTOINCREMENT,
            geom BLOB,
            sample_id TEXT NOT NULL,
            stand_id TEXT NOT NULL,
            tree_species TEXT DEFAULT '',
            dbh_cm REAL DEFAULT 0,
            height_m REAL DEFAULT 0,
            crown_class TEXT DEFAULT '',
            condition TEXT DEFAULT '',
            sample_notes TEXT DEFAULT ''
        )
    """)

    # 20 stands around Green Mountain NF, VT (43.65°N, -72.90°W)
    # 6 qualifying stands: last_inventory_year <= 2020
    base_lon = -72.930
    base_lat = 43.630
    dlon = 0.012
    dlat = 0.010

    stands = [
        # stand_id, col, row, compartment, species, age, last_inv_year, ba, stocking, cond
        ("VT-A01", 0, 0, "C-11", "Pinus strobus",    65, 2019, 24.3, 70, "good"),    # qualifying
        ("VT-A02", 1, 0, "C-11", "Abies balsamea",   45, 2024, 18.7, 85, "good"),
        ("VT-A03", 2, 0, "C-12", "Pinus strobus",    80, 2018, 28.1, 60, "fair"),    # qualifying
        ("VT-A04", 3, 0, "C-12", "Betula papyrifera",35, 2023, 15.2, 90, "good"),
        ("VT-B01", 0, 1, "C-13", "Picea rubens",     55, 2020, 22.8, 75, "good"),    # qualifying
        ("VT-B02", 1, 1, "C-13", "Acer saccharum",   70, 2025, 30.5, 65, "fair"),
        ("VT-B03", 2, 1, "C-14", "Pinus strobus",    90, 2016, 32.0, 55, "fair"),    # qualifying
        ("VT-B04", 3, 1, "C-14", "Betula alleghaniensis", 50, 2024, 19.3, 80, "good"),
        ("VT-C01", 0, 2, "C-15", "Abies balsamea",   40, 2025, 17.5, 88, "good"),
        ("VT-C02", 1, 2, "C-15", "Pinus strobus",    75, 2017, 26.8, 62, "fair"),    # qualifying
        ("VT-C03", 2, 2, "C-16", "Acer saccharum",   60, 2023, 21.4, 78, "good"),
        ("VT-C04", 3, 2, "C-16", "Picea rubens",     85, 2015, 34.2, 50, "poor"),    # qualifying
        ("VT-D01", 0, 3, "C-17", "Pinus strobus",    50, 2024, 20.1, 85, "good"),
        ("VT-D02", 1, 3, "C-17", "Betula papyrifera",45, 2025, 16.9, 87, "good"),
        ("VT-D03", 2, 3, "C-18", "Abies balsamea",   60, 2024, 23.6, 75, "good"),
        ("VT-D04", 3, 3, "C-18", "Acer saccharum",   80, 2022, 31.0, 60, "fair"),
        ("VT-E01", 0, 4, "C-19", "Pinus strobus",    70, 2023, 25.4, 70, "good"),
        ("VT-E02", 1, 4, "C-19", "Picea rubens",     55, 2024, 20.8, 82, "good"),
        ("VT-E03", 2, 4, "C-20", "Betula alleghaniensis", 65, 2022, 22.1, 74, "good"),
        ("VT-E04", 3, 4, "C-20", "Pinus strobus",    95, 2025, 35.0, 48, "fair"),
    ]

    for (stand_id, ci, ri, comp, species, age, last_yr, ba, stocking, cond) in stands:
        lon0 = base_lon + ci * dlon
        lat0 = base_lat + ri * dlat
        lon1 = lon0 + dlon
        lat1 = lat0 + dlat
        ring = [(lon0, lat0), (lon1, lat0), (lon1, lat1), (lon0, lat1), (lon0, lat0)]
        c.execute(
            "INSERT INTO forest_stands "
            "(geom,stand_id,compartment,dominant_species,stand_age_years,"
            "last_inventory_year,basal_area_m2ha,stocking_pct,condition) "
            "VALUES (?,?,?,?,?,?,?,?,?)",
            (make_polygon_blob(ring), stand_id, comp, species, age,
             last_yr, ba, stocking, cond)
        )

    conn.commit()
    register_table(conn, "forest_stands", "geom", "POLYGON",
                   (base_lon, base_lat, base_lon + 4 * dlon, base_lat + 5 * dlat))
    register_table(conn, "tree_samples", "geom", "POINT",
                   (base_lon, base_lat, base_lon + 4 * dlon, base_lat + 5 * dlat))
    conn.close()
    print(f"Created: {path}")
    qualifying = [s[0] for s in stands if s[6] <= 2020]
    print(f"  Qualifying stands (last_inventory_year<=2020): {qualifying}")


# ---------------------------------------------------------------------------
# Task 4: pipeline_survey.gpkg  (Central Texas – gas pipeline segments)
# Occupation: 49-2022.00 Telecom/Utility Infrastructure Installers
# ---------------------------------------------------------------------------

def create_pipeline_survey():
    path = os.path.join(BASE_DIR, "pipeline_survey.gpkg")
    if os.path.exists(path):
        os.remove(path)
    conn = sqlite3.connect(path)
    init_gpkg(conn)

    c = conn.cursor()
    c.execute("""
        CREATE TABLE pipeline_segments (
            fid INTEGER PRIMARY KEY AUTOINCREMENT,
            geom BLOB,
            segment_id TEXT NOT NULL,
            route_name TEXT,
            diameter_mm INTEGER,
            material TEXT,
            pressure_class TEXT,
            install_year INTEGER,
            last_inspection TEXT,
            condition TEXT,
            anomaly_noted TEXT DEFAULT '',
            work_order TEXT DEFAULT ''
        )
    """)

    # 25 segments near Austin TX (30.27°N, -97.74°W)
    # Lines run roughly N-S and E-W in a grid pattern
    # 3 segments have INCORRECT condition values (the task is to fix them)
    # Correct values come from pipeline_log.txt
    base_lon = -97.780
    base_lat = 30.250

    segments = [
        # seg_id, (lon0,lat0), (lon1,lat1), route, diam, material, pressure, install_yr, last_insp, condition
        ("GV-0001", (-97.7800, 30.2500), (-97.7650, 30.2500), "Loop 360 N", 152, "steel", "Class 3", 2005, "2024-01-15", "satisfactory"),
        ("GV-0002", (-97.7650, 30.2500), (-97.7500, 30.2500), "Loop 360 N", 152, "steel", "Class 3", 2005, "2024-01-15", "satisfactory"),
        ("GV-0003", (-97.7500, 30.2500), (-97.7350, 30.2500), "Loop 360 N", 152, "steel", "Class 3", 2008, "2024-01-16", "satisfactory"),
        ("GV-0004", (-97.7350, 30.2500), (-97.7200, 30.2500), "Loop 360 N", 152, "steel", "Class 3", 2008, "2024-01-16", "satisfactory"),
        ("GV-0005", (-97.7200, 30.2500), (-97.7050, 30.2500), "Loop 360 N", 152, "steel", "Class 3", 2010, "2024-01-17", "satisfactory"),
        ("GV-0006", (-97.7800, 30.2650), (-97.7650, 30.2650), "Bee Cave Rd", 203, "steel", "Class 2", 2003, "2024-02-01", "satisfactory"),
        ("GV-0007", (-97.7650, 30.2650), (-97.7500, 30.2650), "Bee Cave Rd", 203, "steel", "Class 2", 2003, "2024-02-01", "satisfactory"),
        ("GV-0008", (-97.7500, 30.2650), (-97.7350, 30.2650), "Bee Cave Rd", 203, "steel", "Class 2", 2006, "2024-02-02", "satisfactory"),
        ("GV-0009", (-97.7350, 30.2650), (-97.7200, 30.2650), "Bee Cave Rd", 203, "steel", "Class 2", 2006, "2024-02-02", "satisfactory"),
        ("GV-0010", (-97.7200, 30.2650), (-97.7050, 30.2650), "Bee Cave Rd", 203, "steel", "Class 2", 2009, "2024-02-03", "satisfactory"),
        ("GV-0011", (-97.7800, 30.2800), (-97.7650, 30.2800), "Mopac N",    102, "HDPE",  "Class 4", 2015, "2024-03-10", "satisfactory"),
        # GV-0012: INCORRECT condition recorded as 'good' - should be 'needs monitoring'
        ("GV-0012", (-97.7650, 30.2800), (-97.7500, 30.2800), "Mopac N",    102, "HDPE",  "Class 4", 2015, "2024-03-10", "good"),
        ("GV-0013", (-97.7500, 30.2800), (-97.7350, 30.2800), "Mopac N",    102, "HDPE",  "Class 4", 2018, "2024-03-11", "satisfactory"),
        ("GV-0014", (-97.7350, 30.2800), (-97.7200, 30.2800), "Mopac N",    102, "HDPE",  "Class 4", 2018, "2024-03-11", "satisfactory"),
        ("GV-0015", (-97.7200, 30.2800), (-97.7050, 30.2800), "Mopac N",    102, "HDPE",  "Class 4", 2020, "2024-03-12", "satisfactory"),
        ("GV-0016", (-97.7800, 30.2950), (-97.7650, 30.2950), "US-290 E",   254, "steel", "Class 2", 1998, "2024-04-05", "fair"),
        ("GV-0017", (-97.7650, 30.2950), (-97.7500, 30.2950), "US-290 E",   254, "steel", "Class 2", 1998, "2024-04-05", "fair"),
        # GV-0017: INCORRECT condition recorded as 'fair' - should be 'poor - scheduled repair'
        # Note: GV-0017 is index 16 (0-based), we'll override it below
        ("GV-0018", (-97.7500, 30.2950), (-97.7350, 30.2950), "US-290 E",   254, "steel", "Class 2", 2000, "2024-04-06", "fair"),
        ("GV-0019", (-97.7350, 30.2950), (-97.7200, 30.2950), "US-290 E",   254, "steel", "Class 2", 2000, "2024-04-06", "satisfactory"),
        ("GV-0020", (-97.7200, 30.2950), (-97.7050, 30.2950), "US-290 E",   254, "steel", "Class 2", 2002, "2024-04-07", "satisfactory"),
        ("GV-0021", (-97.7800, 30.3100), (-97.7650, 30.3100), "RM 2222",    152, "steel", "Class 3", 2012, "2024-05-20", "satisfactory"),
        ("GV-0022", (-97.7650, 30.3100), (-97.7500, 30.3100), "RM 2222",    152, "steel", "Class 3", 2012, "2024-05-20", "satisfactory"),
        # GV-0023: INCORRECT condition recorded as 'satisfactory' - should be 'critical - immediate repair'
        ("GV-0023", (-97.7500, 30.3100), (-97.7350, 30.3100), "RM 2222",    152, "steel", "Class 3", 2012, "2024-05-21", "satisfactory"),
        ("GV-0024", (-97.7350, 30.3100), (-97.7200, 30.3100), "RM 2222",    152, "steel", "Class 3", 2015, "2024-05-21", "satisfactory"),
        ("GV-0025", (-97.7200, 30.3100), (-97.7050, 30.3100), "RM 2222",    152, "steel", "Class 3", 2015, "2024-05-22", "satisfactory"),
    ]

    for seg in segments:
        seg_id, (lon0, lat0), (lon1, lat1), route, diam, mat, pressure, install_yr, last_insp, cond = seg
        geom = make_linestring_blob([(lon0, lat0), (lon1, lat1)])
        c.execute(
            "INSERT INTO pipeline_segments "
            "(geom,segment_id,route_name,diameter_mm,material,pressure_class,"
            "install_year,last_inspection,condition,anomaly_noted,work_order) "
            "VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (geom, seg_id, route, diam, mat, pressure, install_yr, last_insp, cond, "", "")
        )

    conn.commit()
    register_table(conn, "pipeline_segments", "geom", "LINESTRING",
                   (-97.780, 30.250, -97.705, 30.310))
    conn.close()
    print(f"Created: {path}")
    print(f"  Segments with INCORRECT conditions (to fix): GV-0012, GV-0017, GV-0023")
    print(f"  GV-0012: 'good' -> 'needs monitoring'")
    print(f"  GV-0017: 'fair' -> 'poor - scheduled repair'")
    print(f"  GV-0023: 'satisfactory' -> 'critical - immediate repair'")


# ---------------------------------------------------------------------------
# Task 5: water_monitoring.gpkg  (Ohio River tributaries – monitoring stations)
# Occupation: 45-4011.00 Forest and Conservation Workers (environmental)
# ---------------------------------------------------------------------------

def create_water_monitoring():
    path = os.path.join(BASE_DIR, "water_monitoring.gpkg")
    if os.path.exists(path):
        os.remove(path)
    conn = sqlite3.connect(path)
    init_gpkg(conn)

    c = conn.cursor()
    c.execute("""
        CREATE TABLE monitoring_stations (
            fid INTEGER PRIMARY KEY AUTOINCREMENT,
            geom BLOB,
            station_id TEXT NOT NULL,
            stream_name TEXT,
            watershed TEXT,
            last_visit_date TEXT DEFAULT '',
            ph REAL DEFAULT 0,
            dissolved_oxygen_mgl REAL DEFAULT 0,
            turbidity_ntu REAL DEFAULT 0,
            status TEXT DEFAULT 'active',
            inspector_notes TEXT DEFAULT ''
        )
    """)

    # 15 stations in Ohio River basin near Cincinnati (39.10°N, -84.51°W)
    # 4 with status='scheduled' (due for inspection today)
    stations = [
        # station_id, (lon, lat), stream_name, watershed, last_visit, ph, do, turb, status
        ("WQ-001", (-84.5500, 39.0950), "Mill Creek",          "Mill Creek",      "2026-02-15", 7.2, 8.5, 2.1, "completed"),
        ("WQ-002", (-84.5320, 39.1020), "Lick Run",            "Mill Creek",      "2026-02-16", 7.4, 8.1, 1.8, "completed"),
        ("WQ-003", (-84.5150, 39.1100), "West Fork Mill Cr",   "Mill Creek",      "",           0.0, 0.0, 0.0, "scheduled"),   # TODAY
        ("WQ-004", (-84.4980, 39.1180), "Stonelick Creek",     "Little Miami",    "2026-02-10", 7.1, 9.2, 3.5, "completed"),
        ("WQ-005", (-84.4810, 39.1250), "East Fork L. Miami",  "Little Miami",    "2026-02-11", 6.9, 8.8, 2.9, "completed"),
        ("WQ-006", (-84.4640, 39.1320), "Williamson Creek",    "Little Miami",    "2026-02-12", 7.3, 8.3, 1.5, "completed"),
        ("WQ-007", (-84.5480, 39.1450), "Twelve Mile Creek",   "Whitewater",      "",           0.0, 0.0, 0.0, "scheduled"),   # TODAY
        ("WQ-008", (-84.5310, 39.1520), "Indian Creek",        "Whitewater",      "2026-02-08", 7.5, 8.6, 1.2, "completed"),
        ("WQ-009", (-84.5140, 39.1590), "Dry Fork",            "Whitewater",      "2026-02-09", 7.6, 8.2, 0.9, "completed"),
        ("WQ-010", (-84.4970, 39.1660), "Fourmile Creek",      "Whitewater",      "2026-01-30", 7.0, 9.5, 4.2, "completed"),
        ("WQ-011", (-84.4800, 39.1730), "Banklick Creek",      "Licking River",   "2026-01-31", 7.2, 8.9, 2.3, "completed"),
        ("WQ-012", (-84.5460, 39.1900), "Gunpowder Creek",     "Licking River",   "",           0.0, 0.0, 0.0, "scheduled"),   # TODAY
        ("WQ-013", (-84.5290, 39.1970), "South Fork Licking",  "Licking River",   "2026-01-25", 7.4, 8.4, 1.7, "completed"),
        ("WQ-014", (-84.5120, 39.2040), "Grassy Creek",        "Licking River",   "2026-01-26", 7.3, 8.7, 2.0, "completed"),
        ("WQ-015", (-84.4950, 39.2110), "Howard Creek",        "Licking River",   "",           0.0, 0.0, 0.0, "scheduled"),   # TODAY
    ]

    for (sid, (lon, lat), stream, ws, last_v, ph, do_, turb, status) in stations:
        c.execute(
            "INSERT INTO monitoring_stations "
            "(geom,station_id,stream_name,watershed,last_visit_date,"
            "ph,dissolved_oxygen_mgl,turbidity_ntu,status,inspector_notes) "
            "VALUES (?,?,?,?,?,?,?,?,?,?)",
            (make_point_blob(lon, lat), sid, stream, ws, last_v,
             ph, do_, turb, status, "")
        )

    conn.commit()
    register_table(conn, "monitoring_stations", "geom", "POINT",
                   (-84.5500, 39.0950, -84.4640, 39.2110))
    conn.close()
    print(f"Created: {path}")
    print(f"  Stations scheduled for today: WQ-003, WQ-007, WQ-012, WQ-015")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("Generating QField task GeoPackages...")
    create_telecom_survey()
    create_iowa_crop_survey()
    create_forest_inventory()
    create_pipeline_survey()
    create_water_monitoring()
    print("\nAll GeoPackages generated successfully.")
    print("Files are in:", BASE_DIR)
