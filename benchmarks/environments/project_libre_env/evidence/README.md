# ProjectLibre Environment — Evidence Documentation

## Overview

This environment runs **ProjectLibre 1.9.3** (open-source project management software) in a QEMU VM with Xfce4 desktop. The environment uses a **real commercial construction project** ("Three-Story Office Building") sourced from the `cyclingzealot/projectlibre-jlam` GitHub repository — an authentic MS Project 2004 `.mpp` file converted to MSPDI XML via the MPXJ library.

**Real project data:**
- 146 tasks across 8 phases (General Conditions, Long Lead Procurement, Mobilize on Site, Site Grading and Utilities, Foundations, Structural Frame, etc.)
- 33 resources (G.C. General Management, G.C. Survey Crew, Excavation Contractor, Concrete Contractor, etc.)
- Project file: `/home/ga/Projects/samples/sample_project.xml` (555KB)

---

## Checklist

- [x] Real data used (no synthetic/handwritten project data)
- [x] pre_start hook: installs ProjectLibre 1.9.3, Xfce4, VNC, xdotool, wmctrl, scrot
- [x] post_start hook: configures DISPLAY, copies real project to samples directory
- [x] pre_task (setup_task.sh): fresh project copy, programmatic XML modifications, launches ProjectLibre, waits for window, maximizes
- [x] All 5 tasks verified with real construction project UIDs/names
- [x] All scripts executable (chmod +x)
- [x] Interactive testing complete (add_task_dependency demonstrated end-to-end)

---

## Environment Setup Logs

### pre_start (install.sh) — Key Steps

```
=== Installing ProjectLibre Environment ===
Installing system packages...
apt-get install -y xfce4 xfce4-terminal tightvncserver ...
Downloading ProjectLibre 1.9.3...
dpkg -i /tmp/projectlibre_1.9.3_amd64.deb
Installing VNC server...
Setting up VNC...
=== Installation complete ===
```

### post_start (setup.sh) — Key Output

```
=== Setting up ProjectLibre Environment ===
Creating ProjectLibre directories...
Setting up VNC...
Starting VNC server on display :1...
Copying real project data from assets...
  sample_project.xml: 555K Feb 20 17:19
ProjectLibre configuration set up.
Testing ProjectLibre launch...
ProjectLibre window confirmed in wmctrl
=== Setup complete. ProjectLibre ready on DISPLAY=:1 ===
```

### pre_task (setup_task.sh — add_task_dependency) — Key Output

```
=== Setting up add_task_dependency task ===
Copied sample project: /home/ga/Projects/samples/sample_project.xml → /home/ga/Projects/current_task.xml
Removed predecessor link: task 27 -> task 28 (Install storm drainage)
Project file updated successfully
Launching ProjectLibre with commercial construction project...
Waiting for ProjectLibre window...
ProjectLibre window appeared after 12s
ProjectLibre is running
Window: 0x05000003 -1 ga-VirtualPC /home/ga/Projects/current_task.xml - ProjectLibre

Task: Add FS dependency from 'Rough grade site (cut and fill)' (task 27)
         to 'Install storm drainage' (task 28)
Find both tasks in the 'Site Grading and Utilities' section.
=== Task setup complete ===
```

### XML Verification — Task 28 before setup_task.sh runs

```xml
<Task>
  <UID>28</UID>
  <Name>Install storm drainage</Name>
  <!-- NO PredecessorLink elements — dependency removed by setup script -->
</Task>
```

### XML Verification — Task 28 after agent adds dependency

```xml
<Task>
  <UID>28</UID>
  <Name>Install storm drainage</Name>
  <PredecessorLink>
    <PredecessorUID>27</PredecessorUID>
    <Type>1</Type>  <!-- Type 1 = Finish-to-Start (FS) -->
  </PredecessorLink>
</Task>
```

Verified programmatically:
```
Task 28 (Install storm drainage) has 1 predecessor links:
  - Predecessor UID: 27, Type: 1
```

---

## Interactive Testing — add_task_dependency Task

### Task Description
Add a Finish-to-Start (FS) dependency from **"Rough grade site (cut and fill)"** (task row 27) to **"Install storm drainage"** (task row 28) in the Site Grading and Utilities section.

### Start State (Screenshot 04_row27_selected_before_link.png)
- ProjectLibre open with real commercial construction project (146 tasks)
- Task 28 start date: `1/3/00, 8:00 AM` (no predecessor constraint)
- Task 27 ("Rough grade site") visible in Site Grading and Utilities section

### Agent Action Steps Demonstrated
1. Click row 27 ("Rough grade site") in the task list to select it
2. Shift+click row 28 ("Install storm drainage") to select both rows (Screenshot 05)
3. Click the **Link Tasks** toolbar button (chain icon) to create FS dependency

### End State (Screenshot 03_add_task_dependency_completed.png)
- Task 28 start date changed: `1/3/00` → `2/3/00` (after task 27 finishes on 2/2/00)
- Dependency arrow visible in Gantt chart connecting rows 27 → 28
- Saved file confirms: `PredecessorLink UID=27, Type=1 (FS)`

---

## Screenshots

| File | Description |
|------|-------------|
| `01_projectlibre_gantt_add_task_dependency.png` | **Start state** for add_task_dependency: real "Three-story Office Building" project loaded, rows 27 (Rough grade site) and 28 (Install storm drainage) visible, row 28 has **no predecessor** (start date 1/3/00, unconstrained) |
| `02_projectlibre_assign_resource_to_task.png` | **Start state** for assign_resource_to_task: Resource Names column added to Gantt view showing that row 22 ("Set line and grade benchmarks", ID=22) has an **empty Resource Names cell** while adjacent rows (19–21, 23) show their contractor assignments — confirming G.C. Survey Crew was removed |
| `03_add_task_dependency_completed.png` | **Completed state**: row 28 start date changed 1/3/00 → 2/3/00 after FS dependency added, arrow visible in Gantt chart |
| `04_row27_selected_before_link.png` | Row 27 selected (step 1 of Link operation) |
| `05_rows27_28_both_selected.png` | **Both rows 27 and 28 selected simultaneously** (black highlight) — clear multi-selection before clicking the Link Tasks toolbar button |
| `06_update_task_duration_start.png` | **Start state** for update_task_duration: row 7 "Obtain building permits" visible at **4 days** duration — agent must change it to 6 days |
| `07_create_milestone_start.png` | **Start state** for create_milestone: real "Three-story Office Building" project at top of Gantt view |
| `07b_create_milestone_row44.png` | Row 44 "Strip column piers and foundation forms" selected — the task immediately before the new milestone insertion point |
| `08_add_new_task_start.png` | **Start state** for add_new_task: real construction project at top of Gantt view |
| `08b_add_new_task_row137.png` | Row 137 "Complete Final Inspections" selected — the task immediately after which "Pre-Inspection Walkthrough" must be inserted |

---

## Real Data Source

**File**: "Commercial construction project plan.mpp"
**Repository**: `cyclingzealot/projectlibre-jlam` on GitHub
**Format**: Microsoft Project Binary (.mpp), converted to MSPDI XML via MPXJ library
**Content**: Three-story commercial office building construction schedule
**Stats**: 146 tasks, 33 resources, project dates Jan–Dec 2000

Key task UIDs used in tasks:
- UID 7: "Obtain building permits" (4 days → 6 days in update_task_duration task)
- UID 22: "Set line and grade benchmarks" (resource: G.C. Survey Crew UID=7)
- UID 27: "Rough grade site (cut and fill)" (predecessor in add_task_dependency)
- UID 28: "Install storm drainage" (dependent task)
- UID 44: "Strip column piers and foundation forms" (milestone insertion point)
- UID 137: "Complete Final Inspections" (new task insertion point)
