# Inventory Network Expansion via scconfig (`inventory_network_expansion_scconfig@1`)

## Task Overview

A seismologist expands the observatory's monitoring capability by incorporating three stations from the IU (Global Seismograph Network) into the existing SeisComP installation. The task requires converting a FDSN StationXML inventory file, importing it into the database, placing it in the configuration directory, configuring processing module bindings for the new stations, and verifying the expanded network with scinv.

## Domain Context

**Occupation:** Geoscientists / Seismologists (SOC 19-2042.00)

Adding new stations to a seismic monitoring network is a routine but multi-step administrative task. Station metadata arrives as FDSN StationXML from data centers like IRIS-DMC and must be converted to SeisComP's internal XML format, loaded into the database, and placed in the correct configuration directory. Each new station also needs module bindings (scautopick for phase detection, scamp for amplitude measurement) to participate in the automatic processing chain.

**Environment:** SeisComP with MariaDB database (`mysql -u sysop -psysop seiscomp`), configuration at `/home/ga/seiscomp/etc/`.

## Goal Description

1. Convert the IU StationXML file at `/home/ga/Desktop/iu_stations.xml` to SeisComP XML format using `fdsnxml2inv`.
2. Import the converted inventory into the SeisComP database using `scdb`.
3. Copy the converted inventory file to `$SEISCOMP_ROOT/etc/inventory/` so it is visible in scconfig.
4. In scconfig, navigate to the Bindings panel and configure scautopick and scamp module bindings for all three new IU stations: IU.ANMO, IU.HRV, IU.KONO.
5. Verify the stations appear in the system by running `scinv ls` and saving the output to `/home/ga/Desktop/network_inventory.txt`.

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| Stations imported | 25 | IU network record and all 3 stations (ANMO, HRV, KONO) exist in the database |
| Inventory file placed | 15 | Converted inventory file exists in `$SEISCOMP_ROOT/etc/inventory/` |
| scautopick bindings | 30 | scautopick module binding configured for all 3 IU stations (key files contain "scautopick") |
| scamp bindings | 15 | scamp module binding configured for all 3 IU stations (key files contain "scamp") |
| Inventory listing | 15 | File at `/home/ga/Desktop/network_inventory.txt` exists and contains IU network information |

**Pass threshold:** 60 / 100

## Verification Strategy

The post-task `export_result.sh` script queries the database and filesystem:

- Queries `SELECT COUNT(*) FROM Network WHERE code='IU'` and `SELECT COUNT(*) FROM Station WHERE code IN ('ANMO','HRV','KONO')`.
- Checks for inventory XML files in `$SEISCOMP_ROOT/etc/inventory/` matching IU content.
- Inspects key files `$SEISCOMP_ROOT/etc/key/station_IU_ANMO`, `station_IU_HRV`, `station_IU_KONO` for `scautopick` and `scamp` lines.
- Checks `/home/ga/Desktop/network_inventory.txt` for existence and IU network references.
- A do-nothing guard returns score 0 if no IU stations in DB, no bindings configured, and no listing file.

The `verifier.py::verify_inventory_network_expansion_scconfig` function consumes the exported JSON and computes the weighted score.

## Schema and Data Reference

**Input StationXML:** `/home/ga/Desktop/iu_stations.xml` -- FDSN StationXML for IU network with 3 stations:
- IU.ANMO (Albuquerque, NM, USA) -- lat 34.9459, lon -106.4572, elev 1850m
- IU.HRV (Adam Dziewonski Observatory, MA, USA) -- lat 42.5064, lon -71.5583, elev 200m
- IU.KONO (Kongsberg, Norway) -- lat 59.6491, lon 9.5982, elev 216m

Each station has BHZ/BHN/BHE channels at 40 Hz with instrument response metadata.

**Station key files:** `$SEISCOMP_ROOT/etc/key/station_IU_{STATION}` -- created by scconfig when bindings are added.

**Inventory directory:** `$SEISCOMP_ROOT/etc/inventory/` -- SeisComP XML inventory files must be placed here for scconfig visibility.

**Database tables:** `Network` (network code, description), `Station` (station code, location, elevation).

**CLI tools:** `fdsnxml2inv` (StationXML to SeisComP XML conversion), `scdb` (database import), `scinv ls` (inventory listing).

**Output file:** `/home/ga/Desktop/network_inventory.txt`

## Files

- `task.json` -- Task configuration (100 steps, 900s timeout, very_hard difficulty)
- `setup_task.sh` -- Cleans previous IU data, creates StationXML on Desktop, launches scconfig and terminal
- `export_result.sh` -- Extracts DB state, binding files, inventory listing, and writes result JSON
- `verifier.py` -- Scores the result against the 5 criteria
