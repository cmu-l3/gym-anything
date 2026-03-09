# SeisComP Environment Evidence

Evidence collected from a clean environment run (no cache, full rebuild).

## Screenshots

### scolv_location_tab.png
- **What**: scolv GUI on the Location tab with the Noto earthquake loaded
- **Shows**: Event "Near West Coast of Honshu, Japan", Time 2024-01-01 07:10:09, Depth 10km, Lat 37.49N, Lon 137.27E, Agency USGS, Events (1/1)
- **Confirms**: scolv launches, connects to scmaster (`scolv@localhost/production`), loads event from database, map rendering works

### scolv_event_tab.png
- **What**: scolv GUI on the Event tab showing event details and the Type dropdown
- **Shows**: Origins panel with origin selected, Type dropdown showing "- unset -", Type certainty "- unset -", Magnitude mww 7.5, OriginReference linking Event to Origin
- **Confirms**: Event tab displays correctly, Type dropdown is "- unset -" (correct start state for set_event_type_scolv task), OriginReference exists (origin list populated)

### scconfig_bindings_collapsed.png
- **What**: scconfig GUI on the Bindings panel with GE network collapsed
- **Shows**: SeisComP 7.1.2 title, Bindings panel, Networks tree with GE network, binding profiles (access, global, scautopick, scwfparam, seedlink, slarchive, slmon, slmon2)
- **Confirms**: scconfig launches, reads inventory from etc/inventory/, displays binding profiles

### scconfig_bindings_stations.png
- **What**: scconfig GUI on the Bindings panel with GE network expanded
- **Shows**: 5 stations under GE network: BKB, GSI, KWP, SANI, TOLI. No bindings assigned (Profile column empty)
- **Confirms**: All 5 stations visible in Bindings panel, no pre-existing global binding for GE.TOLI (correct start state for configure_station_binding_scconfig task)

### scolv_event_tab_certainty.png
- **What**: scolv Event tab (second clean run) showing Type certainty "- unset -"
- **Shows**: Same event data, Type "- unset -", Type certainty "- unset -", confirming both dropdowns are unset
- **Confirms**: Correct start state for set_event_certainty_scolv task (agent must change Type certainty to "known")

### scconfig_system_scautopick.png
- **What**: scconfig System panel showing all modules and their enable/running status
- **Shows**: scmaster running (Auto: On), all other modules including scautopick "not running" (Auto: Off)
- **Confirms**: Correct start state for enable_scautopick_scconfig task (scautopick is disabled, agent must enable it)

### scconfig_modules_global.png
- **What**: scconfig Modules > global configuration panel showing agencyID and other settings
- **Shows**: agencyID = "GYM", datacenterID, organization, plugins fields
- **Confirms**: Correct start state for change_agency_scconfig task (agencyID is "GYM", agent must change to "NIED")

## Log Evidence

### environment_verification.log
Complete verification output from a running environment showing:

**Installation**:
- SeisComP binaries: seiscomp, scolv, scconfig, scrttv, scmv, scmaster (all present, correct sizes)
- MariaDB: active
- scmaster: running

**FDSN Data Downloads**:
- Station inventory: ge_stations.xml (1,344,061 bytes) - Downloaded from GEOFON FDSN station service
- Converted inventory: ge_stations.scml (327,074 bytes) - fdsnxml2inv conversion successful
- Event data: noto_earthquake.xml (2,814 bytes) - Downloaded from USGS FDSN event service
- Converted event: noto_earthquake.scml (1,460 bytes) - Python QuakeML-to-SCML conversion successful
- Waveforms: 3 stations with real data (BKB 73KB, GSI 57KB, SANI 57KB from GEOFON); 2 stations unavailable (TOLI, KWP)

**Database**:
- 65 tables in seiscomp schema
- 1 Event: "2024 Noto Peninsula, Japan Earthquake", typeCertainty=NULL (unset)
- 1 Origin: 2024-01-01 07:10:09, 37.4874N, 137.271E, depth 10km
- 1 OriginReference linking Event to Origin
- 1 Network (GE)
- 5 Stations (BKB, GSI, KWP, SANI, TOLI)

**Configuration**:
- global.cfg: dbmysql plugin, MySQL connection, agencyID=GYM
- scolv.cfg: loadEventDB=1000 (ensures 2024 event loads in 2026)
- 5 station key files in etc/key/
- Inventory XML in etc/inventory/ for scconfig Bindings panel

**SDS Waveform Archive**:
- 3 files with real miniSEED data in SDS directory structure (2024/GE/{BKB,GSI,SANI}/BHZ.D/)

## Checklist Verification

- [x] Installation script completes without errors (SeisComP 7.1.2 binaries present)
- [x] Setup script completes without errors (MariaDB, scmaster, data imports all succeeded)
- [x] Application is visible in screenshot (scolv and scconfig both captured)
- [x] Application is in correct initial state with real data loaded (event from USGS, stations from GEOFON)
- [x] Task setup runs without errors (all 5 setup_task.sh scripts verified)
- [x] Task start state is correct:
  - set_event_type_scolv: Event tab shows Type "- unset -" (agent must change to "earthquake")
  - set_event_certainty_scolv: Event tab shows Type certainty "- unset -" (agent must change to "known")
  - configure_station_binding_scconfig: Bindings panel shows TOLI with no global binding (agent must add one)
  - change_agency_scconfig: Modules > global shows agencyID = "GYM" (agent must change to "NIED")
  - enable_scautopick_scconfig: System panel shows scautopick disabled (agent must enable it)
- [x] Sufficient evidence that tasks are completable (dropdowns/fields visible, UI interaction possible)
- [x] All seismic data bundled locally (no network dependency for FDSN data)
