#!/usr/bin/env python3
"""
Set up the Brightway2 'default' project with real LCA data.

Uses the 'default' project because Activity Browser opens with it automatically.
Installs biosphere3, LCIA methods, and creates a product system database
with real emission factors from published LCA literature.
"""

import sys
import logging

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

PROJECT_NAME = "default"


def setup_project():
    """Set up the default Brightway2 project with biosphere3, LCIA methods, and data."""
    try:
        import brightway2 as bw
    except ImportError:
        logger.error("brightway2 not installed. Cannot set up project.")
        sys.exit(1)

    logger.info("Setting up Brightway2 project: %s", PROJECT_NAME)

    # Switch to the default project
    bw.projects.set_current(PROJECT_NAME)
    logger.info("Active project: %s", bw.projects.current)
    logger.info("Project directory: %s", bw.projects.dir)

    # Check current state
    existing_dbs = list(bw.databases)
    logger.info("Existing databases: %s", existing_dbs)
    logger.info("Existing LCIA methods: %d", len(bw.methods))

    # Install biosphere3 and LCIA methods if not present
    if "biosphere3" not in bw.databases:
        logger.info("Installing biosphere3 and LCIA methods via bw2setup()...")
        bw.bw2setup()
        logger.info("biosphere3 installed. Databases: %s", list(bw.databases))
        logger.info("LCIA methods available: %d", len(bw.methods))
    else:
        logger.info("biosphere3 already present")

    # Check if we already have a technosphere database
    tech_dbs = [db for db in bw.databases if db != "biosphere3"]
    if tech_dbs:
        logger.info("Technosphere databases already present: %s", tech_dbs)
        for db_name in tech_dbs:
            db = bw.Database(db_name)
            logger.info("  %s: %d activities", db_name, len(db))
    else:
        # Create our product system database
        logger.info("No technosphere database found. Creating product system...")
        create_product_system_db()

    # Final status
    logger.info("=== Project Setup Complete ===")
    logger.info("Project: %s", bw.projects.current)
    logger.info("Databases: %s", list(bw.databases))
    logger.info("LCIA methods: %d", len(bw.methods))

    for db_name in bw.databases:
        db = bw.Database(db_name)
        logger.info("  %s: %d activities", db_name, len(db))

    return True


def create_product_system_db():
    """
    Create a product system database with activities representing energy
    production and industrial processes. Uses real emission factors from
    published LCA literature (IPCC, ecoinvent documentation, IEA data).

    Emission factors sourced from:
    - Coal power: ~0.95 kg CO2/kWh (IPCC 2006 Guidelines, Vol 2, Ch 2)
    - Natural gas: ~0.45 kg CO2/kWh (IPCC 2006 Guidelines)
    - Wind power: ~0.01 kg CO2/kWh (lifecycle, Vestas LCA reports)
    - Steel: ~1.8 kg CO2/kg (World Steel Association sustainability indicators)
    - Aluminium: ~1.5 kg CO2/kg direct + 15 kWh/kg electricity (IAI data)
    """
    import brightway2 as bw

    db_name = "Energy_and_Materials"
    if db_name in bw.databases:
        logger.info("Database '%s' already exists", db_name)
        return

    logger.info("Creating database: %s", db_name)
    db = bw.Database(db_name)

    # Get biosphere database for linking real emission flows
    bio = bw.Database("biosphere3")

    # Find real biosphere flows by key
    co2_key = ch4_key = so2_key = nox_key = None

    for act in bio:
        name = act.get('name', '').lower()
        cat_str = str(act.get('categories', ())).lower()
        if 'carbon dioxide, fossil' in name and 'air' in cat_str and co2_key is None:
            co2_key = act.key
        elif 'methane, fossil' in name and 'air' in cat_str and ch4_key is None:
            ch4_key = act.key
        elif 'sulfur dioxide' in name and 'air' in cat_str and so2_key is None:
            so2_key = act.key
        elif 'nitrogen oxides' in name and 'air' in cat_str and nox_key is None:
            nox_key = act.key

    logger.info("Biosphere flows found: CO2=%s, CH4=%s, SO2=%s, NOx=%s",
                co2_key is not None, ch4_key is not None,
                so2_key is not None, nox_key is not None)

    # Build the database dict using db.write() (proper Brightway2 API)
    # All emission factors from published literature (see docstring)
    data = {}

    # Helper to build exchange lists
    def make_exchanges(activity_key, production_amount, biosphere_list, technosphere_list):
        """Build exchange list for an activity."""
        excs = [{"input": activity_key, "amount": production_amount, "type": "production"}]
        for flow_key, amount in biosphere_list:
            if flow_key is not None:
                excs.append({"input": flow_key, "amount": amount, "type": "biosphere"})
        for tech_key, amount in technosphere_list:
            excs.append({"input": tech_key, "amount": amount, "type": "technosphere"})
        return excs

    # Activity definitions with their exchange data
    activities = {
        "coal_power": {
            "name": "Electricity, hard coal, at power plant",
            "unit": "kWh", "location": "EU", "type": "process",
            "bio": [(co2_key, 0.95), (ch4_key, 0.001), (so2_key, 0.0035), (nox_key, 0.0025)],
            "tech": [],
        },
        "gas_power": {
            "name": "Electricity, natural gas, at power plant",
            "unit": "kWh", "location": "EU", "type": "process",
            "bio": [(co2_key, 0.45), (ch4_key, 0.005), (nox_key, 0.0008)],
            "tech": [],
        },
        "wind_power": {
            "name": "Electricity, wind, onshore, at power plant",
            "unit": "kWh", "location": "EU", "type": "process",
            "bio": [(co2_key, 0.011)],
            "tech": [],
        },
        "solar_pv": {
            "name": "Electricity, solar photovoltaic, at plant",
            "unit": "kWh", "location": "EU", "type": "process",
            "bio": [(co2_key, 0.045)],
            "tech": [],
        },
        "grid_mix": {
            "name": "Electricity, production mix, at grid",
            "unit": "kWh", "location": "EU", "type": "process",
            "bio": [],
            "tech": [((db_name, "coal_power"), 0.30), ((db_name, "gas_power"), 0.25),
                     ((db_name, "wind_power"), 0.25), ((db_name, "solar_pv"), 0.20)],
        },
        "steel_bof": {
            "name": "Steel, basic oxygen furnace, at plant",
            "unit": "kg", "location": "EU", "type": "process",
            "bio": [(co2_key, 1.85), (so2_key, 0.002)],
            "tech": [((db_name, "grid_mix"), 0.5)],
        },
        "aluminum_primary": {
            "name": "Aluminium, primary, ingot, at plant",
            "unit": "kg", "location": "EU", "type": "process",
            "bio": [(co2_key, 1.5)],
            "tech": [((db_name, "grid_mix"), 15.0)],
        },
        "cement": {
            "name": "Cement, Portland, at plant",
            "unit": "kg", "location": "EU", "type": "process",
            "bio": [(co2_key, 0.84), (nox_key, 0.0018)],
            "tech": [((db_name, "grid_mix"), 0.11)],
        },
        "transport_truck": {
            "name": "Transport, freight, lorry 16-32t, EURO5",
            "unit": "tkm", "location": "EU", "type": "process",
            "bio": [(co2_key, 0.062), (nox_key, 0.00035)],
            "tech": [],
        },
        "passenger_car": {
            "name": "Transport, passenger car, petrol, EURO5",
            "unit": "km", "location": "EU", "type": "process",
            "bio": [(co2_key, 0.17), (nox_key, 0.00006), (ch4_key, 0.00003)],
            "tech": [],
        },
    }

    for code, info in activities.items():
        key = (db_name, code)
        data[key] = {
            "name": info["name"],
            "unit": info["unit"],
            "location": info["location"],
            "type": info["type"],
            "exchanges": make_exchanges(key, 1.0, info["bio"], info["tech"]),
        }

    # Write the entire database at once (proper Brightway2 API)
    db.write(data)

    logger.info("Created %d activities in '%s'", len(data), db_name)


if __name__ == "__main__":
    success = setup_project()
    if success:
        logger.info("Setup completed successfully")
        sys.exit(0)
    else:
        logger.error("Setup failed")
        sys.exit(1)
