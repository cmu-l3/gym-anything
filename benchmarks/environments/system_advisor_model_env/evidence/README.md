# Evidence Documentation for System Advisor Model Environment

## Overview

SAM environment for PV system simulation using NREL's PySAM library.

## Environment Design

### Initial State
- Ubuntu GNOME desktop with a terminal window open
- **SAM Desktop GUI open** (registration dialog dismissed via xdotool during setup)
- PySAM v7.1.0 installed (agent can also use Python SDK)
- SAM v2024.12.12 installed at `/opt/SAM/`
- Weather file path saved to `/home/ga/.SAM/solar_resource_dir.txt`
- Quickstart file at `/home/ga/SAM_QUICKSTART.txt` with tool names and directories

### Key Design Decisions
- **Discoverability**: `SAM_QUICKSTART.txt` tells agent PySAM exists and where weather data is (minimal hints, no API details or parameter names)
- **Terminal recovery**: setup_task.sh checks for terminal via wmctrl and launches one if missing
- **No hints in setup**: setup_task.sh does NOT list weather files, verify PySAM, or show API examples
- **Clean state per task**: setup_task.sh deletes all output files from previous runs
- **Anti-bypass protection**: export_result.sh checks bash_history AND .py file contents for PySAM imports (not just file existence)
- **Flexible JSON extraction**: export scripts try multiple common key paths
- **SAM GUI open**: setup_sam.sh launches SAM and dismisses registration dialog via xdotool "Skip for now"
- **Independent cross-check**: Verifiers copy agent's actual output file and parse it independently

### Available Weather Files (Bundled with SAM)
| City | State | File |
|------|-------|------|
| Phoenix | AZ | `phoenix_az_33.450495_-111.983688_psmv3_60_tmy.csv` |
| Tucson | AZ | `tucson_az_32.116521_-110.933042_psmv3_60_tmy.csv` |
| Daggett | CA | `daggett_ca_34.865371_-116.783023_psmv3_60_tmy.csv` |
| Blythe | CA | `blythe_ca_33.617773_-114.588261_psmv3_60_tmy.csv` |
| Imperial | CA | `imperial_ca_32.835205_-115.572398_psmv3_60_tmy.csv` |
| Des Moines | IA | `des_moines_ia_41.586835_-93.624959_psmv3_60_tmy.csv` |
| Fargo | ND | `fargo_nd_46.9_-96.8_mts1_60_tmy.csv` |

**Note**: Denver CO, Las Vegas NV, and Iowa wind data are NOT bundled. Agents must fetch via NRDB API (`developer.nrel.gov`) or SAM's online weather fetch. The environment has `net=true` to support this. This is an intentional difficulty element for the very_hard tasks.

## Tasks

### Original Tasks (Easy/Medium/Hard)
| Task | Difficulty | Description |
|------|-----------|-------------|
| create_residential_pv_system | easy | 5 kW Phoenix residential system |
| analyze_pv_tilt_sensitivity | medium | Tilt sweep 0-60 deg for 5 kW Tucson system |
| configure_commercial_pv_system | medium | 100 kW Daggett tracking system with premium modules |
| compare_pv_locations | hard | Compare Phoenix/Tucson/Des Moines 10 kW systems |
| export_hourly_production | hard | 8760-hour CSV export for 7.5 kW Tucson system |

### New Tasks (Very Hard)
| Task | Difficulty | Technology | Description |
|------|-----------|------------|-------------|
| wind_farm_iowa_lcoe_analysis | very_hard | PySAM Windpower | 10 MW Iowa wind farm: compare 3 turbine configs (V90, GE 1.6-100, V110), find minimum-LCOE configuration |
| csp_parabolic_trough_solar_multiple | very_hard | PySAM TroughPhysical | 50 MW CSP Daggett: sweep solar multiples 1.0–3.0 (9 values, 6h TES), find NPV-optimal SM at $80/MWh PPA |
| commercial_pv_battery_demand_charge | very_hard | PySAM Battery + Utilityrate5 | Denver 250 kW PV + battery: compare 3 battery sizes (100/200/400 kWh) for demand charge reduction, compute NPV/IRR |
| utility_pv_module_technology_lcoe | very_hard | PySAM Pvsamv1 + SingleOwner | 50 MW Daggett: compare mono-Si/HJT/CdTe using cell-level CEC parameters, find LCOE-optimal technology |
| pv_performance_degradation_diagnosis | very_hard | PySAM Pvwattsv8 | Las Vegas 25 kW forensic analysis: 42-combination soiling×degradation sweep to explain 17% Year 4 shortfall |

## Verification Approach

### Three-Layer Verification
Each verifier uses three independent verification layers:

1. **export_result.sh** (in VM):
   - Extracts values from agent's JSON using flexible jq key paths
   - Checks python_ran flag (bash_history + .py file timestamps)
   - Writes `/tmp/task_result.json`

2. **verifier.py** (on host):
   - Reads exported data via `copy_from_env()`
   - Validates against expected ranges and physics sanity checks
   - If python_ran is false, score is capped at 20 and task cannot pass

3. **Independent file cross-check** (on host):
   - Copies agent's actual output file directly (e.g., `Phoenix_Residential_5kW.json`)
   - Independently parses and validates: weather refs, numeric field counts, array lengths
   - Cross-checks extracted values against export_result.sh extraction
   - For CSV tasks: independently counts rows and sums energy totals

### Physics Sanity Checks

**Original PV tasks:**
- Desert SW (Phoenix, Tucson, Daggett): CF 16-26% (fixed), 22-32% (tracking)
- Midwest (Des Moines, Fargo): CF 12-20%
- Peak power < DC rating * 1.2
- Energy ranking matches geography (Tucson > Phoenix > Des Moines)

**New very_hard tasks:**
- Iowa wind (Ames, 80-95m hub): CF 28-58% expected for 2 MW class turbines
- Daggett CSP parabolic trough: CF 25-75% depending on solar multiple; LCOE 60-350 $/MWh
- Denver commercial PV+Battery: Annual PV output ~350,000-420,000 kWh for 250 kW system
- Daggett utility PV (single-axis tracking): CF 22-35%; AEP 90,000-160,000 MWh/yr for 50 MW
- Las Vegas 25 kW residential: Baseline ~42,000-43,500 kWh/yr Year 1 (per PVWatts historical data)

### Key Finding: Tucson > Phoenix in TMY Data
The NSRDB TMY data for Tucson produces ~2.8% more energy than Phoenix for identical systems.

## Audit Fixes Applied

### First Audit (3.5/10)
| Issue | Fix |
|-------|-----|
| Tasks trivially completable via pysam_helper.py | Removed pysam_helper.py entirely |
| Task descriptions give away exact commands | Rewrote as narrative scenarios |
| SAM Registration Dialog in screenshots | Kill SAM processes in install + setup scripts |
| Stale verifier defaults | Fixed all defaults to match actual locations |
| Circular verification | Added physics sanity checks |
| Dead LK scripts | Removed both .lk files |

### Second Audit (4.0/10)
| Issue | Fix |
|-------|-----|
| Zero-action perfect scores (pre-computed files) | setup_task.sh now deletes all output files before task starts |
| Task descriptions still too prescriptive | Removed all PySAM module names, parameter names, API hints |
| SAM Registration Dialog still in artifacts | Added killall in both install_sam.sh and setup_sam.sh |
| Circular verification (self-reported values) | Added anti-bypass check (python_ran flag) |
| Fragile JSON key dependencies | Export scripts now try multiple common key paths |
| Setup scripts give free hints | Removed PySAM verification and weather file listing from setup_task.sh |
| No clean state between episodes | setup_task.sh deletes expected output files + cached scripts |
| Evidence doesn't match artifacts | Rewrote README to not claim specific scores |

### Third Audit
| Issue | Fix |
|-------|-----|
| compare_pv_locations verifier max score 105 | Redistributed points: Tucson(5) + Ranking(5) = 10, added min(score, 100) cap |
| No discoverability hints at task start | Added SAM_QUICKSTART.txt via setup_sam.sh with tool names and directories |
| setup_task.sh doesn't ensure terminal | Added wmctrl terminal check + gnome-terminal launch if missing |
| Verifiers trust agent JSON without cross-check | Added independent file cross-check: copy + parse agent's actual output |
| compare_pv_locations tested with wrong cities | Fixed setup_notes.md: Phoenix/Tucson/Des Moines (was Phoenix/Des Moines/Fargo) |
| Setup notes reference removed helper script | Removed pysam_helper.py section, removed PySAM API details |

### Fourth Audit (6.0/10)
| Issue | Fix |
|-------|-----|
| Anti-bypass weakness: `touch foo.py` bypasses check | Now checks .py file contents for `import PySAM` / `from PySAM` patterns |
| JSON construction uses unsafe string interpolation | Replaced `cat << EOF` with safe `jq -n --arg/--argjson` in all 5 export scripts |
| configure_commercial_pv_system over-specified | Rewrote description: outcome-based instead of listing exact parameter values |
| Tilt curve shape check gives 10 free points | Now requires optimal tilt in expected range AND sufficient sweep points |
| Generous partial credit inflates scores (~47 pts achievable) | Reduced partial credit from 3 pts to 1 pt for wrong-but-present values |
| SAM_QUICKSTART.txt claim of "no hints" misleading | Updated docs to accurately describe discoverability level |
