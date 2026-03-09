# GeoServer Environment - Testing Evidence

## Environment Overview

- **Environment ID**: `geo_server_env@0.1`
- **Base Image**: `ubuntu-gnome-systemd_highres` (1920x1080)
- **Docker Images**: `kartoza/geoserver:2.25.2` + `kartoza/postgis:15-3.3`
- **Tasks**: 5 (create_workspace, publish_shapefile_layer, create_style, configure_wms_settings, create_layer_group)
- **Real Data**: Natural Earth 110m shapefiles (countries, populated places, rivers, lakes)

---

## Checklist Verification

### 1. Installation script completes without errors

**Evidence**: `01_desktop_post_testing.png` (**NOTE**: This screenshot was taken after interactive testing, not immediately after setup. It shows 9 workspaces because `natural_earth` was created during the create_workspace interactive test. The initial post-setup state has 8 workspaces as confirmed by REST API in item 4.)

Log output from `env_setup_pre_start.log`:
```
=== Installing GeoServer Environment ===
Get:1 http://security.ubuntu.com/ubuntu jammy-security InRelease [129 kB]
Hit:2 http://archive.ubuntu.com/ubuntu jammy InRelease
...
=== Pre-pulling Docker images ===
2.25.2: Pulling from kartoza/geoserver
4f4fb700ef54: Pulling fs layer
46be25fd3834: Pulling fs layer
...
=== Downloading Natural Earth data ===
Archive:  /tmp/ne_110m_countries.zip
  inflating: /home/ga/natural_earth/ne_110m_admin_0_countries.shp
  inflating: /home/ga/natural_earth/ne_110m_admin_0_countries.dbf
...
Archive:  /tmp/ne_110m_lakes.zip
  inflating: /home/ga/natural_earth/ne_110m_lakes.shp
...
Archive:  /tmp/ne_110m_places.zip
  inflating: /home/ga/natural_earth/ne_110m_populated_places.shp
...
=== GeoServer environment installation complete ===
```

### 2. Setup script completes without errors

**Evidence**: `01_desktop_post_testing.png` (see note in item 1 about workspace count)

Log output from `env_setup_post_start.log`:
```
=== Setting up GeoServer ===
 Network geoserver_default Created
 Volume geoserver_postgis_data Created
 Volume geoserver_geoserver_data Created
 Container gs-postgis Created
 Container gs-app Created
 Container gs-postgis Started
 Container gs-postgis Healthy
 Container gs-app Started
PostGIS is ready after 0s
GeoServer is ready after 10s (HTTP 302)
Verifying GeoServer REST API...
REST API check: {"workspaces":{"workspace":[{"name":"cite",...},{"name":"tiger",...},{"name":"nurc",...},{"name":"sde",...},{"name":"it.geosolutions",...},{"name":"topp",...},{"name":"sf",...},{"name":"ne",...}]}}
=== Importing Natural Earth data into PostGIS ===
Importing ne_110m_populated_places.shp -> ne_populated_places...
Importing ne_110m_rivers_lake_centerlines.shp -> ne_rivers...
Importing ne_110m_lakes.shp -> ne_lakes...
PostGIS tables:
 Schema |        Name         | Type  |   Owner
--------+---------------------+-------+-----------
 public | ne_countries        | table | geoserver
 public | ne_lakes            | table | geoserver
 public | ne_populated_places | table | geoserver
 public | ne_rivers           | table | geoserver
 public | spatial_ref_sys     | table | geoserver
(5 rows)

Firefox window detected
Firefox maximized
=== GeoServer setup complete ===
GeoServer URL: http://localhost:8080/geoserver/web/
Admin credentials: admin / Admin123!
PostGIS: geoserver / geoserver123 @ localhost:5432/gis
```

### 3. Application is visible in screenshot

**Evidence**: `02_task_start_screenshot.png`, `03_geoserver_logged_in_post_task.png`

- GeoServer Welcome page visible at `http://localhost:8080/geoserver/web/`
- Firefox browser maximized with GeoServer admin interface
- Login with admin/Admin123! successful

### 4. Application is in correct initial state

**Evidence**: REST API verification (screenshot 05 was taken post-task and shows 9 workspaces including the created `natural_earth`; the pre-task state has 8 workspaces)

GeoServer REST API confirms 8 default workspaces at initial state (with SAMPLE_DATA=TRUE):
- cite, tiger, nurc, sde, it.geosolutions, topp, sf, ne

PostGIS database has 4 Natural Earth tables:
- ne_countries (177 records, MultiPolygon)
- ne_populated_places (243 records, Point)
- ne_rivers (13 records, MultiLineString)
- ne_lakes (24 records, MultiPolygon)

### 5. Task setup runs without errors

Log output from running `setup_task.sh` for `create_workspace`:
```
=== Setting up create_workspace task ===
Initial workspace count: 8
Verifying GeoServer is accessible...
Window title: 0x01000003  0 ga-base GeoServer: Welcome — Mozilla Firefox
Successfully verified: logged into GeoServer
Result nonce: f7559314c91f2f13fa87497f055baa87
Screenshot saved: /tmp/task_start_screenshot.png
=== create_workspace task setup complete ===
```

### 6. Export script produces valid JSON

Log output from running `export_result.sh` after completing the create_workspace task:
```
=== Exporting create_workspace result ===
Screenshot saved: /tmp/task_end_screenshot.png
Result saved to /tmp/create_workspace_result.json
{
    "initial_workspace_count": 8,
    "current_workspace_count": 9,
    "workspace_found": true,
    "workspace_name": "natural_earth",
    "namespace_uri": "http://naturalearthdata.com",
    "result_nonce": "70f90bafadbbfc9d003e49e1f23e18f8",
    "timestamp": "2026-02-06T04:32:10+00:00"
}
=== Export complete ===
```

### 7. Verifier can read and process the result

Verifier output after successful task completion:
```
Score: 100/100
Passed: True
Feedback: Workspace found in GeoServer | Workspace name exact match: 'natural_earth' |
          Namespace URI exact match: 'http://naturalearthdata.com' |
          Workspace count increased: 8 -> 9
```

### 8. Do-nothing test returns score 0

**Evidence**: `06_do_nothing_test_post_task.png`

Export JSON when no workspace was created (do-nothing test):
```json
{
    "initial_workspace_count": 8,
    "current_workspace_count": 8,
    "workspace_found": false,
    "workspace_name": "",
    "namespace_uri": "",
    "result_nonce": "f7559314c91f2f13fa87497f055baa87",
    "timestamp": "2026-02-06T04:42:58+00:00"
}
```

Verifier output:
```
Score: 0/100
Passed: False
Feedback: Workspace NOT found in GeoServer
```

### 8b. Do-nothing tests for ALL 5 tasks (post-audit)

After the independent audit, all 5 tasks were re-tested with do-nothing tests to confirm score 0:

**create_workspace**:
```
Score: 0/100, Passed: False
Feedback: Workspace NOT found in GeoServer
```

**publish_shapefile_layer**:
```
Score: 0/100, Passed: False
Feedback: Layer NOT found in GeoServer
```

**create_style**:
```
Score: 0/100, Passed: False
Feedback: Style NOT found in GeoServer
```

**configure_wms_settings**:
```
Score: 0/100, Passed: False
Feedback: Max rendering memory unchanged: 0 KB | Max rendering time unchanged: 0s | Watermark unchanged: false
```

**create_layer_group**:
```
Score: 0/100, Passed: False
Feedback: Layer group NOT found in GeoServer
```

---

## Interactive Testing

### Phase 6: create_workspace (CUA+xdotool)

The `create_workspace` task was tested using the full interactive CUA+xdotool loop:

1. **Screenshot**: Took initial screenshot showing GeoServer Welcome page
2. **CUA query**: Asked for username field location -> (672, 118) in 1280x720
3. **Action**: Scaled to (1008, 177), clicked, typed `admin`, tabbed, typed `Admin123!`, pressed Return
4. **Screenshot**: Confirmed login successful, Firefox password save dialog appeared
5. **CUA query**: Asked for "Not now" button -> (462, 228) -> scaled to (693, 342), clicked
6. **CUA query**: Asked for "Workspaces" sidebar link -> (101, 288) -> scaled to (152, 432), clicked
7. **Screenshot**: Workspaces page loaded with 8 default workspaces
8. **CUA query**: Dismissed Firefox sidebar popup via X button
9. **CUA query**: Asked for "Add new workspace" -> (266, 194) -> scaled to (399, 291), clicked
10. **CUA query**: Asked for Name field -> (270, 257) -> scaled to (405, 386)
11. **Action**: Typed `natural_earth`, tabbed, typed `http://naturalearthdata.com`
12. **CUA query**: Asked for Save button -> (229, 370) -> scaled to (344, 555), clicked
13. **Result**: Workspace created successfully, count went from 8 to 9

### Phase 7: create_layer_group (REST API + verifier)

The `create_layer_group` task was tested end-to-end:

1. **Setup**: Ran setup_task.sh, recorded initial layer group count = 3
2. **Action**: Created layer group via REST API (simulating GUI completion):
   - Name: `world_basemap`, Title: `World Basemap`
   - Layers: `ne:ne_countries`, `ne:ne_populated_places`, `ne:ne_lakes`
   - Bounds: -180,-90,180,90 (EPSG:4326)
3. **Export**: Ran export_result.sh, produced valid JSON:
```json
{
    "group_found": true,
    "group_name": "world_basemap",
    "group_title": "World Basemap",
    "group_layer_count": 3,
    "group_layers": "ne:ne_countries,ne:ne_populated_places,ne:ne_lakes",
    "group_bbox": "-180,-90,180,90",
    "initial_layergroup_count": 3,
    "current_layergroup_count": 4
}
```
4. **Verifier result**:
```
Score: 100/100, Passed: True
Feedback: Layer group found: 'world_basemap' | Group name exact match |
          Group title matches: 'World Basemap' |
          Group contains 3 layers (meets minimum of 3) |
          Group contains expected Natural Earth layers (3 matches) |
          Bounding box computed for layer group |
          Layer group count increased: 3 -> 4
```

All CUA coordinates were in 1280x720 space and scaled to 1920x1080 actual resolution using: `actual = cua * 1920/1280` (x) and `actual = cua * 1080/720` (y).

---

## Screenshots Index

| File | Description |
|------|-------------|
| `01_desktop_post_testing.png` | Desktop with Firefox and GeoServer (POST-TESTING: shows 9 workspaces, not initial 8) |
| `02_task_start_screenshot.png` | State at task start (pre_task complete; shows 8 workspaces — correct initial state, but has sidebar popup) |
| `03_geoserver_logged_in_post_task.png` | GeoServer admin interface after login (POST-TASK: shows 9 workspaces) |
| `04_layer_preview.png` | GeoServer layer preview page |
| `05_workspaces_page.png` | Workspaces listing page (POST-TASK: shows 9 workspaces including created natural_earth) |
| `06_do_nothing_test_post_task.png` | State during do-nothing test (POST-TASK environment: shows 9 workspaces; verifier correctly scores 0) |

**Note on screenshot evidence gaps**: No clean initial-state screenshot exists showing 8 workspaces without sidebar popup and user not logged in. Screenshot 02 is the closest to initial state (8 workspaces) but has a sidebar popup. The correct initial state (8 workspaces, 28 layers) is confirmed by REST API output in the setup log (item 2) and by setup_task.sh output (item 5). The two-phase Firefox launch added in the fourth audit fixes should prevent the sidebar popup in future runs.

---

## Bugs Found and Fixed

### VNC Password Bug
- `EnvSpec` auto-creates `VNCSpec(password=None)` even without vnc config in env.json
- Fix: Added `"vnc": {"enable": false, "password": "password"}` to env.json

### PostGIS Authentication
- `psql` via Docker exec uses Unix socket by default (peer auth fails)
- Fix: Added `-h localhost` flag to force TCP connection with password auth

### ogr2ogr vs shp2pgsql
- `shp2pgsql` is NOT available in kartoza/postgis container
- Fix: Used `ogr2ogr` instead (available at `/usr/bin/ogr2ogr`)

### Countries Shapefile Geometry
- Natural Earth countries contains mixed Polygon/MultiPolygon geometries
- Fix: Added `-nlt PROMOTE_TO_MULTI` flag to ogr2ogr

### WMS Settings REST API Field Name
- GUI label "Max rendering memory" maps to REST API field `maxRequestMemory` (NOT `maxRenderingMemory`)
- Fix: Updated export_result.sh and setup_task.sh for configure_wms_settings task

### create_layer_group Layer References
- Original task referenced non-existent `cite:DEM`, `cite:Lakes`, `cite:Streams`
- Fix: Updated to use actual layers from sample data (ne:countries, etc.)

---

## Audit Fixes Applied

Following an independent audit, these issues were identified and fixed:

### CRITICAL: create_layer_group referenced non-existent layers
- **Issue**: Task description referenced `ne:coastlines` which doesn't exist
- **Fix**: Pre-publish 4 Natural Earth layers (ne_countries, ne_populated_places, ne_rivers, ne_lakes) in `ne` workspace via REST API in `setup_geoserver.sh`; updated task description to reference actual layers

### HIGH: create_style provided verbatim SLD XML
- **Issue**: Task description contained copy-paste SLD XML
- **Fix**: Rewrote description to specify desired result (blue fill #0000FF, dark blue stroke #000080) without providing the SLD code

### HIGH: create_layer_group verifier too lenient
- **Issue**: Pass threshold was >= 55 with only 1 layer required
- **Fix**: Raised to >= 65 with >= 2 layers required; tightened layer scoring (25 pts for >= 3 layers)

### MODERATE: Partial name matching too generous
- **Issue**: Single-keyword partial matches gave too many points
- **Fix**: All verifiers now require BOTH keywords for partial match (e.g., both "blue" AND "polygon")

### MODERATE: publish_shapefile_layer over-detailed description
- **Issue**: Step-by-step GUI instructions reduced task to trivial mechanical clicks
- **Fix**: Rewrote to provide only essential info (connection params, store name, workspace)

### MODERATE: VLM field name incorrect
- **Issue**: Verifiers checked `vlm_result.get('answer')` but VLM returns `{"response": "...", "parsed": {"answer": ...}}`
- **Fix**: All verifiers updated to check `parsed.get('answer')` and `response.lower().startswith('yes')`

### MODERATE: publish_shapefile_layer do-nothing scored 85
- **Issue**: Export script found pre-published ne_countries layer globally
- **Fix**: Restricted search to `cite` workspace first; global fallback only if layer count increased and excludes `ne` workspace layers

### MODERATE: configure_wms_settings watermark format mismatch
- **Issue**: Setup stored Python `False` but export compared lowercase `false`
- **Fix**: Setup now uses `str().lower()` conversion matching export format

### LOW: Firefox sidebar popup not suppressed
- **Issue**: Firefox sidebar popup appeared during task interaction
- **Fix**: Added suppression prefs to `user.js` in setup_geoserver.sh

---

## Second Audit Fixes Applied

Following a second independent audit:

### HIGH: create_style stroke verification free points
- **Issue**: `grep -qi "000080|stroke"` matched ANY SLD with `<Stroke>` elements (nearly all of them), giving 15 free points
- **Fix**: Removed `|stroke` alternative; now only matches `000080` specifically

### HIGH: create_style fill color check too loose
- **Issue**: `grep -qi "0000FF|0000ff|blue"` matched the word "blue" in any context (style name, comments, etc.)
- **Fix**: Removed `|blue` alternative; now only matches `0000FF`/`0000ff` hex codes

### HIGH: create_style pass condition too weak
- **Issue**: Agent could pass with wrong colors if score reached 65 via name+found+count
- **Fix**: Added `has_correct_color` requirement — at least one color (#0000FF fill or #000080 stroke) must match to pass

### HIGH: "Newest entity" fallback awards undeserved credit
- **Issue**: If any entity was created (regardless of name), fallback picked the last item, awarding "found" points
- **Fix**: All 4 export scripts now limit fallback to count increases of 1-2 only; create_workspace verifier re-weighted: found=20pts (was 30), name=40pts (was 35)

### MODERATE: create_workspace description over-detailed
- **Issue**: Step-by-step GUI instructions ("go to Workspaces under Data, click Add new workspace")
- **Fix**: Simplified to essentials: workspace name, URI, admin URL, and credentials only

### MODERATE: configure_wms_settings exact-match without change guard
- **Issue**: If default values happened to match targets, agent scored full points for doing nothing
- **Fix**: Full credit now requires BOTH correct value AND `*_changed` flag; value-matches-but-no-change gets reduced credit (15 pts instead of 35)

### MODERATE: Firefox sidebar popup still visible
- **Fix**: Added more aggressive sidebar suppression prefs (`sidebar.main.tools=""`, `sidebar.visibility="hide-sidebar"`, etc.) and popup dismissal after Firefox launch

### MODERATE: Screenshot 05 evidence mismatch
- **Issue**: README described screenshot 05 as showing "8 default workspaces" but it showed 9 (post-task)
- **Fix**: Updated README to accurately note screenshot was taken post-task

### LOW-MODERATE: create_style description had SLD element names
- **Issue**: Specifying "PolygonSymbolizer" and "CssParameters" is implementation detail
- **Fix**: Removed SLD element names; description now specifies visual result only

### Adversarial test results (post-fix):
- Wrong stroke color (red #FF0000): Score 75 (was 90 before fix), Passed: True (fill IS correct)
- Correct style: Score 90, Passed: True
- Do-nothing: Score 0, Passed: False (all 5 tasks confirmed)

---

## Third Audit Fixes Applied

Following a third independent audit:

### HIGH: Screenshot 01 evidence misleading
- **Issue**: Screenshot `01_desktop_after_setup.png` shows 9 workspaces (post-task state), but is labeled as post-setup evidence (should show initial 8)
- **Fix**: Updated README to clearly note the screenshot was taken post-testing; initial state confirmed by REST API (8 workspaces in item 4)

### MODERATE: Firefox sidebar popup still visible
- **Issue**: Firefox sidebar popup persisted despite user.js prefs and single Escape press
- **Fix**: Copied `user.js` to `prefs.js` (some Firefox versions read different file); added F9 sidebar toggle, multiple Escape presses, wmctrl close by title, and content area click to dismiss tooltips

### MODERATE: configure_wms_settings description over-specified
- **Issue**: Description included navigation hints ("Go to 'WMS' under the 'Services' section") and action hints ("click 'Submit'")
- **Fix**: Simplified to essential info only — setting names, target values, and credentials

### LOW: publish_shapefile_layer/setup_task.sh uses unavailable shp2pgsql
- **Issue**: Fallback reimport code used `shp2pgsql` which is not available in kartoza/postgis container
- **Fix**: Replaced with `ogr2ogr` (available in container), with proper flags including `-nlt PROMOTE_TO_MULTI` for mixed geometry

### LOW: create_workspace export `ne_` partial match too short
- **Issue**: `ne_` pattern in workspace name grep could match unrelated workspaces (e.g., `ne` which is a default workspace)
- **Fix**: Removed `ne_` from partial match pattern; replaced with `nat_earth` as additional alternative alongside `natural.*earth`, `earth.*natural`, `natearth`

### LOW: No VLM checklists
- **Issue**: All 5 verifiers used single final screenshot for VLM with simple yes/no binary check
- **Fix**: Upgraded all 5 verifiers to use trajectory-based VLM verification:
  - Uses `sample_trajectory_frames()`, `get_first_screenshot()`, `get_final_screenshot()` from `gym_anything.vlm`
  - Sends multiple trajectory frames (first + sampled + last) for process verification
  - Each verifier has a 3-item checklist specific to the task (navigation, interaction, completion)
  - Points distributed across checklist items instead of single binary award

---

## Fourth Audit Fixes Applied

Following a fourth independent audit:

### CRITICAL: configure_wms_settings gave points for unchanged values
- **Issue**: Verifier awarded 15 points per setting that matched the target but was NOT actually changed (could pass with 45 free pts + 10 "any change" = 55 from a single changed setting)
- **Fix**: Removed all credit for "value matches but wasn't changed" scenarios. Memory/time/watermark now give 0 points if unchanged even if value matches target. Only "changed to correct value" gets full credit; "changed to wrong value" gets reduced credit (10/10/5 pts respectively)

### HIGH: REST API bypass across all 5 tasks
- **Issue**: All tasks could be completed via `curl` REST API calls, scoring 85-100 without any GUI interaction
- **Fix**: Made VLM trajectory checks mandatory for passing. Added `vlm_gui_confirmed` flag to all 5 verifiers — if VLM is available and trajectory shows 0 GUI interaction, `vlm_gui_confirmed = False` blocks passing. If VLM is unavailable or call fails, defaults to True (don't penalize)

### HIGH: publish_shapefile_layer missing workspace verification
- **Issue**: Agent could publish ne_countries in any workspace (e.g., `ne`, `topp`) and still pass — workspace was not verified
- **Fix**: Added `layer_workspace` and `layer_in_cite` tracking to export_result.sh; added 10-point workspace check to verifier.py; added `layer_in_cite` to pass condition

### HIGH: create_style SLD color verification context-unaware
- **Issue**: `grep "000080"` matched hex code anywhere in SLD XML (attribute values, comments, CRS strings)
- **Fix**: Replaced grep-based checks with Python XML parsing using `xml.etree.ElementTree`. Now checks `<CssParameter name="fill">` contains `0000FF` and `<CssParameter name="stroke">` contains `000080` specifically. Falls back to simple grep if XML parsing fails

### MODERATE: publish_shapefile_layer description hostname ambiguity
- **Issue**: Description said "connect to PostGIS at gs-postgis:5432" which could be misread as VM hostname vs container hostname
- **Fix**: Clarified to "When configuring the data store connection in GeoServer, use hostname 'gs-postgis' and port 5432"

### MODERATE: create_layer_group pass condition allowed 2/3 required layers
- **Issue**: Task says "at least these three layers" but pass condition was `layer_count >= 2`
- **Fix**: Changed to `layer_count >= 3` in pass condition

### MODERATE: Firefox sidebar popup more aggressive suppression
- **Issue**: Sidebar popup still visible despite prefs.js copy and F9/Escape dismissal
- **Fix**: Two-phase Firefox launch: (1) launch headless to initialize profile, kill, (2) force sidebar prefs into prefs.js after profile init, (3) relaunch for real. Ensures prefs are baked in before visible Firefox window appears

### LOW: Nonce check was best-effort (silently passed on error)
- **Issue**: All verifiers had `except Exception: pass` for nonce check — if nonce file couldn't be read, check was silently skipped
- **Fix**: Now checks if `result_nonce` key exists in result JSON when nonce file is unreadable. If result claims to have a nonce but the file can't be verified, fails with "nonce in result but nonce file unreadable"

### LOW: create_workspace partial match patterns too narrow
- **Issue**: Variations like `NaturalEarth` (no separator), `nat_earth`, `natearth` got 0 partial match points
- **Fix**: Broadened workspace name partial match: added `naturalearth` (no separator), `nat_earth`, `natearth` patterns. Also broadened namespace URI partial match to accept `natural-earth`, `naturalearth`, and any URI containing both `natural` and `earth`

---

## Fifth Audit Fixes Applied

Following a fifth independent audit:

### HIGH: VLM guard disabled by default (REST API bypass unprotected)
- **Issue**: All 5 verifiers' VLM-based anti-bypass guard defaulted to `True` when VLM was unavailable (common in local/test deployments), meaning agents could use `curl` REST API calls to complete all tasks with 85-100 score and no GUI interaction
- **Fix**: Added access-log-based GUI interaction detection as a fallback anti-bypass mechanism:
  - New `snapshot_access_log()` function in `task_utils.sh` records GeoServer Tomcat access log line count at task start
  - New `check_gui_interaction()` function checks for Wicket form `POST` requests to `/geoserver/web/` (evidence of GUI form submissions) since the snapshot
  - All 5 setup_task.sh scripts now call `snapshot_access_log` at task start
  - All 5 export_result.sh scripts now include `gui_interaction_detected` boolean in result JSON
  - All 5 verifiers now use combined guard: `gui_confirmed = vlm_gui_confirmed or gui_interaction` — must have EITHER VLM trajectory confirmation OR access log evidence of GUI POSTs
  - If VLM is unavailable AND no GUI form POSTs were detected, task will not pass

### MODERATE: create_style pass condition allowed incorrect stroke color
- **Issue**: `has_correct_color` was `True` if fill OR stroke matched — agent could pass with correct fill but wrong stroke (score 75 with only one of two colors correct)
- **Fix**: Changed to require BOTH: `has_correct_color = result.get('style_has_fill') and result.get('style_has_stroke')`

### HIGH: Screenshot evidence filenames misleading
- **Issue**: Screenshots 01, 03, and 06 showed post-task state (9 workspaces) but filenames implied initial/setup state
- **Fix**: Renamed files to accurately reflect content:
  - `01_desktop_after_setup.png` -> `01_desktop_post_testing.png`
  - `03_geoserver_logged_in.png` -> `03_geoserver_logged_in_post_task.png`
  - `06_do_nothing_test.png` -> `06_do_nothing_test_post_task.png`
- Updated all README references to use new filenames
- Added explicit note about screenshot evidence gaps (no clean initial-state screenshot exists)

---

## New Hard/Very-Hard Tasks (Added 2026-03-01)

Five new tasks were added to `geo_server_env` following the task_creation_notes criteria. All pipeline tests pass (20/20: 4 scenarios × 5 tasks).

### Task Registry Update

`constants.py` now defines:
```python
GEO_SERVER_TRAIN_TASKS = ['create_workspace', 'publish_shapefile_layer', 'create_style', 'configure_wms_settings', 'create_layer_group']
GEO_SERVER_TEST_TASKS = ['continent_thematic_map', 'wfs_feature_service_setup', 'access_control_configuration', 'gwc_tile_cache_seeding', 'multi_workspace_portal']
```

### Task 6: continent_thematic_map (very_hard)

**Role**: GIS Analyst — publish a continent-level thematic world map as a live web layer

**Requirements**:
- Create workspace `regional_atlas` with PostGIS datastore pointing to `gis` database
- Publish `ne_countries` table as a layer named `countries` (EPSG:4326)
- Create SLD style `continent_colors` with ≥7 rules (one per continent) using `PropertyIsEqualTo` OGC filters on the `CONTINENT` attribute
- Each rule must have a distinct fill color; apply as default style

**Pipeline test results** (see `continent_thematic_map_evidence.json`):
```
do_nothing_no_export:  score=0,  passed=False ✓
do_nothing_baseline:   score=0,  passed=False ✓
partial_no_layer:      score=25, passed=False ✓
full_success:          score=100, passed=True  ✓
```

---

### Task 7: wfs_feature_service_setup (hard)

**Role**: Spatial Data Engineer — configure WFS and publish a SQL view for city data

**Requirements**:
- Enable WFS service with title "Natural Earth WFS" and maxFeatures=5000
- Create SQL view `major_cities` in `ne` workspace from `ne_populated_places` table (Point geometry)
- Create SLD style `city_marker` with circle mark (red fill) and apply as default style

**Pipeline test results** (see `wfs_feature_service_setup_evidence.json`):
```
do_nothing_no_export:  score=0,  passed=False ✓
do_nothing_baseline:   score=0,  passed=False ✓
partial_no_sql_view:   score=35, passed=False ✓
full_success:          score=100, passed=True  ✓
```

---

### Task 8: access_control_configuration (hard)

**Role**: GIS Security Administrator — configure RBAC for read-only data access

**Requirements**:
- Create user `gis_reader` in GeoServer security store
- Create role `ROLE_GIS_READER`
- Assign user to role
- Create data ACL rule granting `ROLE_GIS_READER` read access to `ne.*` layers
- Create service security rule restricting WMS GetMap to `ROLE_GIS_READER`

**Pipeline test results** (see `access_control_configuration_evidence.json`):
```
do_nothing_no_export:    score=0,  passed=False ✓
do_nothing_baseline:     score=0,  passed=False ✓
partial_no_assignment:   score=40, passed=False ✓
full_success:            score=100, passed=True  ✓
```

---

### Task 9: gwc_tile_cache_seeding (very_hard)

**Role**: GIS Platform Architect — configure and seed a tile cache for production performance

**Requirements**:
- Configure GeoWebCache tile layer for `ne:ne_countries`
- Add both `EPSG:4326` and `EPSG:900913` gridsets
- Set `image/png` tile format, metatile 4×4
- Trigger tile seeding for zoom levels 0–3

**Score cap gate**: If seeding is not triggered, score is capped at 55 (below 60-pt threshold) — configuring GWC without seeding is insufficient.

**Pipeline test results** (see `gwc_tile_cache_seeding_evidence.json`):
```
do_nothing_no_export:  score=0,  passed=False ✓
do_nothing_baseline:   score=0,  passed=False ✓
partial_no_seeding:    score=55, passed=False ✓  (score cap gate applied)
full_success:          score=100, passed=True  ✓
```

---

### Task 10: multi_workspace_portal (very_hard)

**Role**: GIS Solutions Architect — build a multi-workspace geospatial portal

**Requirements**:
- Create workspaces `infrastructure` and `environment` with PostGIS datastores
- Publish `ne_populated_places` as `settlements` layer in `infrastructure` workspace
- Publish `ne_rivers` as `waterways` layer in `environment` workspace
- Create SLDs `settlement_marker` (point) and `waterway_line` (line), apply to respective layers
- Create layer group `regional_portal` combining both layers

**Pipeline test results** (see `multi_workspace_portal_evidence.json`):
```
do_nothing_no_export:              score=0,  passed=False ✓
do_nothing_baseline:               score=0,  passed=False ✓
partial_one_workspace_one_layer:   score=30, passed=False ✓
full_success:                      score=100, passed=True  ✓
```

---

### Evidence Files for New Tasks

| Task | Evidence File | Pipeline Score |
|------|--------------|----------------|
| continent_thematic_map | `continent_thematic_map_evidence.json` | 0/0/25/100 |
| wfs_feature_service_setup | `wfs_feature_service_setup_evidence.json` | 0/0/35/100 |
| access_control_configuration | `access_control_configuration_evidence.json` | 0/0/40/100 |
| gwc_tile_cache_seeding | `gwc_tile_cache_seeding_evidence.json` | 0/0/55/100 |
| multi_workspace_portal | `multi_workspace_portal_evidence.json` | 0/0/30/100 |

Pipeline test script: `test_geo_server_new_tasks.py` (all 20/20 passing).
