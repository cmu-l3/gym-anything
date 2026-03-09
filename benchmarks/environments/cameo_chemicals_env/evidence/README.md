# CAMEO Chemicals Environment - Evidence Documentation

## Environment Overview
- **Application**: CAMEO Chemicals (NOAA/EPA web-based hazardous materials database)
- **URL**: https://cameochemicals.noaa.gov/
- **Access Method**: Firefox browser in Ubuntu GNOME VM
- **Network**: Required (`net: true`) for accessing the CAMEO Chemicals web application

## Verification Checklist

### Installation (pre_start hook)
- [x] Firefox installed successfully (version 147.0.4)
- [x] GUI automation tools installed (xdotool, wmctrl, scrot, imagemagick)
- [x] Utilities installed (curl, wget, jq, python3)
- [x] Script completes without errors

**Pre-start log snippet:**
```
Firefox installed: Mozilla Firefox 147.0.4
=== CAMEO Chemicals Environment Installation Complete ===
```

### Setup (post_start hook)
- [x] Firefox profile configured with first-run suppression
- [x] Homepage set to https://cameochemicals.noaa.gov/
- [x] Warm-up launch completed (clears first-run dialogs)
- [x] Data files copied to Desktop
- [x] Script completes without errors

**Post-start log snippet:**
```
Firefox warm-up started after 0s
Firefox window appeared after 2s
Killing warm-up Firefox...
=== CAMEO Chemicals Environment Setup Complete ===
Firefox profile configured at: /home/ga/.mozilla/firefox/default.profile
Homepage set to: https://cameochemicals.noaa.gov/
```

### Task Setup (pre_task hook - chemical_reactivity_prediction)
- [x] Task start time recorded
- [x] Output file removed (anti-gaming)
- [x] Scenario document placed on Desktop
- [x] Firefox launched and navigated to CAMEO Chemicals
- [x] Firefox window maximized and focused
- [x] CAMEO Chemicals homepage fully loaded

**Pre-task log snippet:**
```
Task start time: 1772087164
Firefox process started after 0s
Firefox window appeared after 2s
Firefox window maximized: 0x00800003
=== chemical_reactivity_prediction task setup complete ===
```

### Application State Verification
- [x] Firefox shows "CAMEO Chemicals | NOAA" in title bar
- [x] Homepage fully rendered with Search, MyChemicals, and Reactivity options
- [x] Search page accessible with Name, CAS, and UN/NA search fields
- [x] Reactivity prediction page accessible
- [x] All data files present on Desktop (5 files)
- [x] Documents directory empty (ready for agent output)

### Anti-Gaming Verification
- [x] Output file does NOT exist before task starts
- [x] Task start time is recorded for timestamp checking
- [x] Stub verifiers return pass (VLM evaluation is external)

## Evidence Screenshots
1. `task1_initial_state.png` - Firefox showing CAMEO Chemicals homepage (task start state)
2. `reactivity_page.png` - Reactivity prediction page accessible
3. `search_page.png` - Chemical search page with all search fields

## Timing
- VM boot + pre_start hook: ~224 seconds (Firefox + tool installation)
- Post_start hook: ~10 seconds (profile setup + warm-up launch)
- Pre_task hook: ~11 seconds (Firefox launch + page load)
- Total reset time: ~235 seconds

## Tasks (5 total)

| Task | Difficulty | Timeout | Max Steps | Description |
|------|-----------|---------|-----------|-------------|
| chemical_reactivity_prediction | Medium | 300s | 40 | Predict hazards of mixing Sulfuric Acid + Sodium Cyanide |
| hazmat_emergency_response | Medium | 300s | 40 | Look up ERG for Chlorine (UN1017) spill |
| chemical_datasheet_lookup | Easy | 240s | 35 | Extract Benzene physical properties |
| reactive_group_compatibility | Hard | 360s | 50 | H2O2 reactive group compatibility assessment |
| multi_chemical_hazard_assessment | Hard | 420s | 60 | 3-chemical pairwise reactivity check |

## Data Files (Real-World Scenarios)
All data files use real chemical identifiers (UN numbers, CAS numbers):
- `facility_chemical_inventory.csv` - 15 chemicals with real UN/CAS/NFPA data
- `hazmat_incident_report.txt` - Chlorine tanker accident scenario
- `reactivity_scenario.txt` - Sulfuric Acid + Sodium Cyanide mixing hazard
- `safety_assessment_request.txt` - Benzene workplace assessment
- `storage_compatibility_query.txt` - H2O2 storage compatibility review
