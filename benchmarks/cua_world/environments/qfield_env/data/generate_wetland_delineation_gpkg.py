#!/usr/bin/env python3
"""
Generate wetland_delineation_verification.gpkg for the QField wetland
delineation field verification task.

Data represents a USACE Section 404 wetland delineation survey site along
the Upper Mississippi River floodplain near La Crosse, Wisconsin.

Layers:
  wetland_boundaries  — 6 polygons (Cowardin-coded, field_verified = NULL)
  soil_borings        — 14 points  (hydric indicators, is_wetland_positive)
  verification_results — empty point layer for agent findings

Run on HOST:
  python3 generate_wetland_delineation_gpkg.py
"""

import sqlite3
import struct
import os
import json

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


# ---------------------------------------------------------------------------
# GeoPackage geometry helpers (same as existing generation scripts)
# ---------------------------------------------------------------------------

def make_point_blob(lon, lat, srid=4326):
    header = b'GP\x00\x01' + struct.pack('<i', srid)
    wkb = b'\x01' + struct.pack('<I', 1) + struct.pack('<dd', lon, lat)
    return header + wkb


def make_polygon_blob(outer_ring, srid=4326):
    header = b'GP\x00\x01' + struct.pack('<i', srid)
    wkb = b'\x01' + struct.pack('<I', 3)
    wkb += struct.pack('<I', 1)
    wkb += struct.pack('<I', len(outer_ring))
    for lon, lat in outer_ring:
        wkb += struct.pack('<dd', lon, lat)
    return header + wkb


def init_gpkg(conn):
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
        ("WGS 84", 4326, "EPSG", 4326, wgs84_def, "World Geodetic System 1984"),
    )
    conn.commit()


def register_table(conn, table_name, geom_col, geom_type, bbox, srid=4326):
    min_x, min_y, max_x, max_y = bbox
    c = conn.cursor()
    c.execute(
        "INSERT OR REPLACE INTO gpkg_contents "
        "(table_name,data_type,identifier,description,min_x,min_y,max_x,max_y,srs_id) "
        "VALUES (?,?,?,?,?,?,?,?,?)",
        (table_name, "features", table_name, "", min_x, min_y, max_x, max_y, srid),
    )
    c.execute(
        "INSERT OR REPLACE INTO gpkg_geometry_columns "
        "(table_name,column_name,geometry_type_name,srs_id,z,m) "
        "VALUES (?,?,?,?,?,?)",
        (table_name, geom_col, geom_type, srid, 0, 0),
    )
    conn.commit()


# ---------------------------------------------------------------------------
# Data definitions — Upper Mississippi River floodplain, La Crosse WI
# ---------------------------------------------------------------------------

BBOX = (-91.310, 43.740, -91.170, 43.910)

# Wetland polygons — irregular 5-7 vertex rings (closed), Cowardin-coded
WETLANDS = [
    {
        "wetland_id": "WL-001",
        "wetland_type": "PEM1C",       # Palustrine Emergent Persistent Seasonally Flooded
        "acreage": 2.3,
        "nwi_status": "preliminary",
        "ring": [
            (-91.243, 43.798), (-91.241, 43.797), (-91.237, 43.799),
            (-91.238, 43.802), (-91.242, 43.803), (-91.243, 43.798),
        ],
    },
    {
        "wetland_id": "WL-002",
        "wetland_type": "PFO1A",       # Palustrine Forested Broad-leaved Deciduous Temporarily Flooded
        "acreage": 5.1,
        "nwi_status": "preliminary",
        "ring": [
            (-91.204, 43.847), (-91.201, 43.846), (-91.196, 43.849),
            (-91.197, 43.853), (-91.202, 43.854), (-91.204, 43.847),
        ],
    },
    {
        "wetland_id": "WL-003",
        "wetland_type": "PSS1C",       # Palustrine Scrub-Shrub Broad-leaved Deciduous Seasonally Flooded
        "acreage": 1.8,
        "nwi_status": "preliminary",
        "ring": [
            (-91.183, 43.778), (-91.180, 43.777), (-91.177, 43.779),
            (-91.178, 43.782), (-91.182, 43.782), (-91.183, 43.778),
        ],
    },
    {
        "wetland_id": "WL-004",
        "wetland_type": "PEM1F",       # Palustrine Emergent Persistent Semi-permanently Flooded
        "acreage": 3.4,
        "nwi_status": "preliminary",
        "ring": [
            (-91.254, 43.897), (-91.251, 43.896), (-91.246, 43.899),
            (-91.247, 43.903), (-91.253, 43.904), (-91.254, 43.897),
        ],
    },
    {
        "wetland_id": "WL-005",
        "wetland_type": "L2UBH",       # Lacustrine Littoral Unconsolidated Bottom Permanently Flooded
        "acreage": 8.2,
        "nwi_status": "preliminary",
        "ring": [
            (-91.306, 43.816), (-91.302, 43.815), (-91.295, 43.818),
            (-91.294, 43.823), (-91.300, 43.825), (-91.305, 43.823),
            (-91.306, 43.816),
        ],
    },
    {
        "wetland_id": "WL-006",
        "wetland_type": "PFO1C",       # Palustrine Forested Broad-leaved Deciduous Seasonally Flooded
        "acreage": 4.6,
        "nwi_status": "preliminary",
        "ring": [
            (-91.224, 43.747), (-91.221, 43.746), (-91.216, 43.749),
            (-91.217, 43.753), (-91.222, 43.754), (-91.224, 43.747),
        ],
    },
]

# Soil borings — 14 total, unequally distributed across 6 wetlands
# Data uses USACE hydric soil indicators, Munsell notation, and regional plant species
BORINGS = [
    # --- WL-001: 2 borings, both positive → CONFIRMED ---
    {
        "boring_id": "SB-001", "wetland_id": "WL-001",
        "hydric_indicator": "depleted_matrix",
        "depth_to_water_cm": 15, "soil_munsell": "10YR 4/1",
        "dominant_vegetation": "Typha latifolia",
        "is_wetland_positive": 1,
        "lon": -91.240, "lat": 43.800,
    },
    {
        "boring_id": "SB-002", "wetland_id": "WL-001",
        "hydric_indicator": "hydrogen_sulfide",
        "depth_to_water_cm": 8, "soil_munsell": "10YR 3/1",
        "dominant_vegetation": "Carex stricta",
        "is_wetland_positive": 1,
        "lon": -91.239, "lat": 43.799,
    },
    # --- WL-002: 3 borings, none positive → REJECTED ---
    {
        "boring_id": "SB-003", "wetland_id": "WL-002",
        "hydric_indicator": "none",
        "depth_to_water_cm": 95, "soil_munsell": "10YR 5/4",
        "dominant_vegetation": "Quercus alba",
        "is_wetland_positive": 0,
        "lon": -91.201, "lat": 43.849,
    },
    {
        "boring_id": "SB-004", "wetland_id": "WL-002",
        "hydric_indicator": "none",
        "depth_to_water_cm": 110, "soil_munsell": "7.5YR 5/6",
        "dominant_vegetation": "Acer rubrum",
        "is_wetland_positive": 0,
        "lon": -91.200, "lat": 43.850,
    },
    {
        "boring_id": "SB-005", "wetland_id": "WL-002",
        "hydric_indicator": "none",
        "depth_to_water_cm": 88, "soil_munsell": "10YR 5/3",
        "dominant_vegetation": "Fraxinus americana",
        "is_wetland_positive": 0,
        "lon": -91.198, "lat": 43.851,
    },
    # --- WL-003: 2 borings, both positive → CONFIRMED ---
    {
        "boring_id": "SB-006", "wetland_id": "WL-003",
        "hydric_indicator": "depleted_matrix",
        "depth_to_water_cm": 22, "soil_munsell": "2.5Y 5/2",
        "dominant_vegetation": "Salix nigra",
        "is_wetland_positive": 1,
        "lon": -91.180, "lat": 43.780,
    },
    {
        "boring_id": "SB-007", "wetland_id": "WL-003",
        "hydric_indicator": "redox_concentrations",
        "depth_to_water_cm": 18, "soil_munsell": "10YR 4/2",
        "dominant_vegetation": "Cornus amomum",
        "is_wetland_positive": 1,
        "lon": -91.179, "lat": 43.779,
    },
    # --- WL-004: 3 borings, only 1 positive → REJECTED ---
    {
        "boring_id": "SB-008", "wetland_id": "WL-004",
        "hydric_indicator": "none",
        "depth_to_water_cm": 85, "soil_munsell": "10YR 5/6",
        "dominant_vegetation": "Quercus rubra",
        "is_wetland_positive": 0,
        "lon": -91.250, "lat": 43.900,
    },
    {
        "boring_id": "SB-009", "wetland_id": "WL-004",
        "hydric_indicator": "depleted_below",
        "depth_to_water_cm": 30, "soil_munsell": "2.5Y 4/2",
        "dominant_vegetation": "Fraxinus nigra",
        "is_wetland_positive": 1,
        "lon": -91.249, "lat": 43.899,
    },
    {
        "boring_id": "SB-010", "wetland_id": "WL-004",
        "hydric_indicator": "none",
        "depth_to_water_cm": 92, "soil_munsell": "7.5YR 5/4",
        "dominant_vegetation": "Betula alleghaniensis",
        "is_wetland_positive": 0,
        "lon": -91.248, "lat": 43.901,
    },
    # --- WL-005: 2 borings, both positive → CONFIRMED (primary_reference) ---
    {
        "boring_id": "SB-011", "wetland_id": "WL-005",
        "hydric_indicator": "loamy_gleyed_matrix",
        "depth_to_water_cm": 5, "soil_munsell": "GLEY1 4/10Y",
        "dominant_vegetation": "Nuphar lutea",
        "is_wetland_positive": 1,
        "lon": -91.300, "lat": 43.820,
    },
    {
        "boring_id": "SB-012", "wetland_id": "WL-005",
        "hydric_indicator": "depleted_matrix",
        "depth_to_water_cm": 12, "soil_munsell": "10YR 4/1",
        "dominant_vegetation": "Pontederia cordata",
        "is_wetland_positive": 1,
        "lon": -91.299, "lat": 43.819,
    },
    # --- WL-006: 2 borings, none positive → REJECTED ---
    {
        "boring_id": "SB-013", "wetland_id": "WL-006",
        "hydric_indicator": "none",
        "depth_to_water_cm": 120, "soil_munsell": "7.5YR 4/6",
        "dominant_vegetation": "Pinus strobus",
        "is_wetland_positive": 0,
        "lon": -91.220, "lat": 43.750,
    },
    {
        "boring_id": "SB-014", "wetland_id": "WL-006",
        "hydric_indicator": "none",
        "depth_to_water_cm": 105, "soil_munsell": "10YR 5/4",
        "dominant_vegetation": "Tsuga canadensis",
        "is_wetland_positive": 0,
        "lon": -91.219, "lat": 43.749,
    },
]

# ---------------------------------------------------------------------------
# Ground truth (for verifier reference, NOT shown to agent)
# ---------------------------------------------------------------------------

GROUND_TRUTH = {
    "classification": {
        "WL-001": "CONFIRMED",   # 2/2 positive
        "WL-002": "REJECTED",    # 0/3 positive
        "WL-003": "CONFIRMED",   # 2/2 positive
        "WL-004": "REJECTED",    # 1/3 positive
        "WL-005": "CONFIRMED",   # 2/2 positive
        "WL-006": "REJECTED",    # 0/2 positive
    },
    "primary_reference": "WL-005",   # avg depth (5+12)/2 = 8.5 cm (shallowest)
    "rejected_ids": ["WL-002", "WL-004", "WL-006"],
    "confirmed_ids": ["WL-001", "WL-003", "WL-005"],
    "avg_depth_confirmed": {
        "WL-001": 11.5,   # (15+8)/2
        "WL-003": 20.0,   # (22+18)/2
        "WL-005": 8.5,    # (5+12)/2
    },
    "negative_borings_per_rejected": {
        "WL-002": ["SB-003", "SB-004", "SB-005"],
        "WL-004": ["SB-008", "SB-010"],
        "WL-006": ["SB-013", "SB-014"],
    },
    "pass_threshold": 60,
}


# ---------------------------------------------------------------------------
# Generate GeoPackage
# ---------------------------------------------------------------------------

def generate():
    gpkg_path = os.path.join(BASE_DIR, "wetland_delineation_verification.gpkg")
    gt_path = os.path.join(BASE_DIR, "wetland_delineation_verification_gt.json")

    if os.path.exists(gpkg_path):
        os.remove(gpkg_path)

    conn = sqlite3.connect(gpkg_path)
    init_gpkg(conn)

    # --- wetland_boundaries (polygon layer) ---
    conn.execute("""
        CREATE TABLE wetland_boundaries (
            fid INTEGER PRIMARY KEY AUTOINCREMENT,
            wetland_id TEXT NOT NULL,
            wetland_type TEXT,
            acreage REAL,
            nwi_status TEXT DEFAULT 'preliminary',
            field_verified TEXT,
            verification_date TEXT,
            delineator TEXT,
            boundary_accuracy TEXT DEFAULT 'provisional',
            geom BLOB
        )
    """)
    register_table(conn, "wetland_boundaries", "geom", "POLYGON", BBOX)

    for w in WETLANDS:
        conn.execute(
            "INSERT INTO wetland_boundaries "
            "(wetland_id, wetland_type, acreage, nwi_status, "
            " field_verified, verification_date, delineator, boundary_accuracy, geom) "
            "VALUES (?,?,?,?,NULL,NULL,NULL,'provisional',?)",
            (
                w["wetland_id"], w["wetland_type"], w["acreage"],
                w["nwi_status"],
                make_polygon_blob(w["ring"]),
            ),
        )

    # --- soil_borings (point layer) ---
    conn.execute("""
        CREATE TABLE soil_borings (
            fid INTEGER PRIMARY KEY AUTOINCREMENT,
            boring_id TEXT NOT NULL,
            wetland_id TEXT NOT NULL,
            hydric_indicator TEXT,
            depth_to_water_cm INTEGER,
            soil_munsell TEXT,
            dominant_vegetation TEXT,
            is_wetland_positive INTEGER NOT NULL DEFAULT 0,
            geom BLOB
        )
    """)
    register_table(conn, "soil_borings", "geom", "POINT", BBOX)

    for b in BORINGS:
        conn.execute(
            "INSERT INTO soil_borings "
            "(boring_id, wetland_id, hydric_indicator, depth_to_water_cm, "
            " soil_munsell, dominant_vegetation, is_wetland_positive, geom) "
            "VALUES (?,?,?,?,?,?,?,?)",
            (
                b["boring_id"], b["wetland_id"], b["hydric_indicator"],
                b["depth_to_water_cm"], b["soil_munsell"],
                b["dominant_vegetation"], b["is_wetland_positive"],
                make_point_blob(b["lon"], b["lat"]),
            ),
        )

    # --- verification_results (empty point layer for agent) ---
    conn.execute("""
        CREATE TABLE verification_results (
            fid INTEGER PRIMARY KEY AUTOINCREMENT,
            result_id TEXT,
            wetland_id TEXT,
            finding TEXT,
            notes TEXT,
            geom BLOB
        )
    """)
    register_table(conn, "verification_results", "geom", "POINT", BBOX)

    conn.commit()
    conn.close()

    # Write ground truth JSON
    with open(gt_path, "w") as f:
        json.dump(GROUND_TRUTH, f, indent=2)

    print(f"Generated: {gpkg_path}")
    print(f"Ground truth: {gt_path}")

    # Verify
    conn = sqlite3.connect(gpkg_path)
    wc = conn.execute("SELECT COUNT(*) FROM wetland_boundaries").fetchone()[0]
    bc = conn.execute("SELECT COUNT(*) FROM soil_borings").fetchone()[0]
    rc = conn.execute("SELECT COUNT(*) FROM verification_results").fetchone()[0]
    conn.close()
    print(f"  wetland_boundaries: {wc} rows")
    print(f"  soil_borings:       {bc} rows")
    print(f"  verification_results: {rc} rows")


if __name__ == "__main__":
    generate()
