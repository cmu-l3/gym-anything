# Task: EMCOMM Regional Satellite Network Configuration

## Domain Context

Amateur Radio Emergency Communications (EMCOMM) coordinators use GPredict to plan and schedule satellite contacts for emergency communications. The Radio Amateur Civil Emergency Service (RACES) program supplements public safety communications during emergencies using amateur radio satellites. Coordinators must maintain accurate ground station data across multiple cities in their region and track the specific satellites approved for EMCOMM use.

This task reflects real work that a Pennsylvania RACES or ARES (Amateur Radio Emergency Service) coordinator would perform when setting up a regional communication network that spans multiple served agencies across different cities.

## Persona

Regional EMCOMM Coordinator, Pennsylvania Emergency Management Agency — responsible for configuring satellite tracking for multiple amateur radio ground stations across the state to coordinate emergency communication passes via amateur satellites.

## Scenario

You have inherited a partially configured GPredict installation. The configuration has several errors and omissions:

1. The Pittsburgh ground station has an **incorrect altitude** of 450 meters — the GPS-surveyed altitude is **230 meters** and the METAR weather station code should be **KPIT**.
2. Two regional ground stations are **missing**: Erie PA and Harrisburg PA need to be added for regional coordination.
3. The RACES module was started but is **incomplete** — it only contains SO-50. It should also contain AO-85 (Fox-1A) and ISS (ZARYA), which are the three satellites approved for regional EMCOMM voice operations.

## Task Description (for agent)

You are configuring GPredict for the Pennsylvania Emergency Management Agency's regional satellite communication network.

The current configuration has errors that must be corrected:

1. The **Pittsburgh** ground station has incorrect altitude and weather station data. Update it: Altitude = 230 meters, Weather Station Code = KPIT.
2. Add a ground station for **Erie, PA**: Latitude = 42.1292°N, Longitude = 80.0851°W, Altitude = 222 meters, Weather Station = KEIE.
3. Add a ground station for **Harrisburg, PA**: Latitude = 40.2732°N, Longitude = 76.8867°W, Altitude = 102 meters, Weather Station = KMDT.
4. The **RACES** module currently only contains SO-50. Complete it by adding **AO-85** (Fox-1A, NORAD catalog number 40967) and the **ISS** (ZARYA, NORAD catalog number 25544). SO-50 (NORAD 27607) is already in the module and should remain.

Login: username `ga`, password `password123`. GPredict is already open.

## Success Criteria

The task is complete when:
- Pittsburgh.qth has altitude corrected to 230m (not 450m)
- Pittsburgh.qth has WX=KPIT
- Erie.qth exists with correct coordinates (LAT≈42.13, LON≈-80.09, ALT=222)
- Harrisburg.qth exists with correct coordinates (LAT≈40.27, LON≈-76.89, ALT=102)
- RACES.mod SATELLITES field contains NORAD IDs 27607 (SO-50), 40967 (AO-85), and 25544 (ISS)

## Verification Strategy

The verifier reads these files from the VM:
- `/home/ga/.config/Gpredict/Pittsburgh.qth`
- `/home/ga/.config/Gpredict/Erie.qth`
- `/home/ga/.config/Gpredict/Harrisburg.qth`
- `/home/ga/.config/Gpredict/modules/RACES.mod`

Scoring (100 points, pass ≥ 70):
- Pittsburgh altitude corrected (ALT=230): 20 pts
- Pittsburgh WX code correct (KPIT): 10 pts
- Erie.qth exists with correct LAT/LON/ALT: 25 pts
- Harrisburg.qth exists with correct LAT/LON/ALT: 25 pts
- RACES.mod contains all 3 required satellites: 20 pts

## Key Data Reference

### Ground Station Coordinates (real GPS data)
| Station | Lat | Lon | Alt | WX |
|---------|-----|-----|-----|----|
| Pittsburgh, PA | 40.4406°N | 79.9959°W | 230m | KPIT |
| Erie, PA | 42.1292°N | 80.0851°W | 222m | KEIE |
| Harrisburg, PA | 40.2732°N | 76.8867°W | 102m | KMDT |

### Satellite NORAD IDs (from CelesTrak TLE data)
| Satellite | NORAD ID | Purpose |
|-----------|----------|---------|
| ISS (ZARYA) | 25544 | Voice relay via crossband repeater |
| SO-50 (SaudiSat 1C) | 27607 | FM voice repeater satellite |
| AO-85 (Fox-1A) | 40967 | FM voice + telemetry satellite |

### GPredict File Formats
- `.qth` files: GLib key file, section `[GROUND STATION]`, keys: LAT, LON, ALT, WX, LOCATION
- `.mod` files: GLib key file, section `[MODULE]`, key: SATELLITES (semicolon-delimited NORAD IDs)

## Edge Cases
- GPredict may append a trailing semicolon to the SATELLITES list
- NORAD IDs are stored as integers (no leading zeros in the mod file, but 7530 may be stored as 7530)
- Ground station names are taken from the filename (minus .qth extension)
- The agent may rename files — verifier searches by LAT/LON proximity if exact filename not found
