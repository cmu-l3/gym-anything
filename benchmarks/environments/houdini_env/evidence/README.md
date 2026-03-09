# Houdini Environment - Evidence Documentation

## Summary

Houdini 20.5.684 is installed from the Docker image `aaronsmithtv/hbuild:20.5.684-base`. The binary files are extracted to `/opt/houdini/build` with a symlink at `/opt/hfs20.5`. The Houdini GUI launches and the license server infrastructure (`hserver`, `sesinetd`, `sesictrl`) is in place. However, Houdini requires SideFX API credentials to acquire even the free Apprentice license, which are not provided in this environment setup. Without a license, hython cannot create scenes and the GUI shows a license error dialog.

## Verification Checklist

### 1. Installation script completes without errors

**Status: PASS**

The pre_start hook (`install_houdini.sh`) successfully:
- Installs all system dependencies (X11, Qt, OpenGL, GUI automation tools, libtinfo5)
- Pulls Docker image `aaronsmithtv/hbuild:20.5.684-base`
- Extracts Houdini binaries from the container to `/opt/houdini/build`
- Creates symlink `/opt/hfs20.5 -> /opt/houdini/build`
- Copies license tools (`sesictrl`, `sesinetd`) to `/usr/lib/sesi/`
- Starts `hserver` (license proxy daemon)
- Configures environment (`/etc/profile.d/houdini.sh`)
- Creates desktop entry and symlinks in `/usr/local/bin/`

**Log snippet (from `pre_start_hook.log`):**
```
Extracting Houdini from Docker image aaronsmithtv/hbuild:20.5.684-base...
Pulling Docker image (this may take several minutes)...
Extracting Houdini files from container...
Copying /opt/houdini from container...
Created symlink /opt/hfs20.5 -> /opt/houdini/build
Houdini extracted to: /opt/hfs20.5
...
hserver started
No SideFX API credentials found.
...
=== Houdini installation complete ===
HFS: /opt/hfs20.5
```

---

### 2. Setup script completes without errors

**Status: PASS**

The post_start hook (`setup_houdini.sh`) successfully:
- Detects Houdini installation at `/opt/hfs20.5`
- Sources `houdini_setup` environment
- Creates user directories (`HoudiniProjects/`, `data/`, `renders/`)
- Downloads 3 real data files from public sources
- Starts license server (`hserver`)
- Creates desktop launcher script
- Creates utility scripts (`houdini-info`, `houdini-query-scene`)

Scenes are NOT pre-created because hython requires a license.

**Log snippet (from `post_start_hook.log`):**
```
Houdini 20.5 found at /opt/hfs20.5
Creating user directories...
Downloading real 3D data for tasks...
  Stanford Bunny OBJ: 204K
  HDRI: 1.4M
  Utah Teapot OBJ: 208K
Starting Houdini license server (hserver)...
hython license check failed — scenes will not be pre-created
Houdini GUI will launch but may show a license dialog
```

---

### 3. Houdini installed and GUI launches

**Status: PASS (with license limitation)**

Houdini 20.5.684 binaries are installed at `/opt/hfs20.5`:
- `hython-bin`: 135,320 bytes (actual binary)
- `houdinifx-bin`: launches GUI
- `hserver`: 19,880,216 bytes (license proxy)
- 630 shared libraries in `dsolib/`

The GUI launches and shows "Unable to Acquire a License" dialog (screenshot `02_houdini_license_dialog.png`). This is expected without SideFX credentials.

Evidence verified via `visual_grounding` MCP tool:
> "Dialog Window: 'Unable to Acquire a License'... Error message: 'A license could not be found to run this application.' ... 'Show Details' expandable link ... 'OK' button"

---

### 4. Real data loaded and visible

**Status: PASS**

Three real 3D data files downloaded from public sources:

| File | Source | Size |
|------|--------|------|
| bunny.obj | Stanford 3D Scanning Repository | 205,917 bytes |
| teapot.obj | University of Utah | 210,614 bytes |
| venice_sunset_1k.hdr | Poly Haven | 1,440,400 bytes |

Evidence in screenshot `03_terminal_evidence.png` showing terminal with file listings, sizes, and license server diagnostic output.

---

### 5. Task setup runs without errors

**Status: PASS**

The pre_task hook for `import_obj_model` completes successfully. The OBJ data file is verified present. Without a Houdini license, the task setup completes but cannot launch Houdini with the scene pre-loaded.

---

### 6. Task start state verified via visual_grounding

**Status: PARTIAL (license-dependent)**

Interactive testing with `visual_grounding` MCP tool confirmed:
1. Desktop is responsive (GNOME running, dock visible, system tray working)
2. Houdini GUI launches from extracted binaries (shows license dialog)
3. Data files are present and accessible in `/home/ga/HoudiniProjects/data/`
4. xdotool mouse/keyboard interactions work
5. Coordinate scaling (1280x720 -> 1920x1080) works correctly

**Not verified (requires SideFX credentials):**
- Houdini fully open with scene loaded
- Scene creation via hython
- Task start state with correct Houdini view

---

### 7. Licensing requirement

**Status: BLOCKER (credentials needed)**

Houdini requires SideFX API credentials even for the free Apprentice license:

1. Create a free account at https://www.sidefx.com
2. Go to https://www.sidefx.com/services/ and create an Application
3. Copy the client_id and client_secret
4. Create `config/sidefx_credentials.env` with:
   ```
   SIDEFX_CLIENT_ID=your_client_id
   SIDEFX_CLIENT_SECRET=your_client_secret
   ```

Once credentials are provided, the install script will automatically:
- Run `sesictrl login --client-id ... --client-secret ...`
- Acquire a license from SideFX's online server
- Enable hython to create baseline and bunny scenes
- Allow the Houdini GUI to fully launch

---

## Screenshots Index

| File | Description |
|------|-------------|
| `01_desktop_after_setup.png` | Desktop after environment setup, showing Houdini FX in taskbar and launch_houdini.sh on desktop |
| `02_houdini_license_dialog.png` | Houdini GUI launched, showing "Unable to Acquire a License" dialog |
| `03_terminal_evidence.png` | Terminal showing data files listing and license server diagnostic |
| `04_final_clean_test_houdini.png` | Final clean test (env.reset use_cache=False): Houdini FX launched, license dialog visible |

## Log Files Index

| File | Description |
|------|-------------|
| `pre_start_hook.log` | Full output of install_houdini.sh (Docker extraction, deps, licensing setup) |
| `post_start_hook.log` | Full output of setup_houdini.sh (data download, directory creation, license check) |

## Key Technical Findings

1. **Docker extraction**: The `hbuild` Docker image stores Houdini at `/opt/houdini/build` with `/opt/hfs20.5` as a symlink. `docker cp` copies symlinks verbatim, so we must copy `/opt/houdini` (the actual directory) and recreate the symlink.

2. **libtinfo5 dependency**: The Houdini binary requires `libtinfo.so.5` which is not in Ubuntu 22.04 by default (it ships libtinfo6). Without `libtinfo5`, hython segfaults at startup.

3. **find -L for symlinks**: `find /opt -maxdepth 1 -type d -name "hfs*"` doesn't find `/opt/hfs20.5` because it's a symlink. Must use `find -L` to follow symlinks.

4. **Licensing architecture**: `sesinetd` is the license daemon, `hserver` is a local proxy, and `sesictrl` is the CLI admin tool. Login requires SideFX API credentials (OAuth2 client_id + client_secret).
