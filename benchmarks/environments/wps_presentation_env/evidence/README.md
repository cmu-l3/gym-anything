# WPS Presentation Environment — Evidence Documentation

## Environment Summary

- **App**: WPS Office Presentation (`wpp`), version 11.1.0.11723
- **Data**: Real 48-slide Apache HTTP Server performance analysis deck (`2411-Performance_Up.pptx`)
  from the Apache POI test corpus (Apache License 2.0)
- **Base image**: `ubuntu-gnome-systemd_highres` (1920×1080 GNOME desktop)
- **Hooks**: pre_start (install) → post_start (setup/warm-up) → pre_task (per-task)

## End-to-End Test Results

Fresh `env.reset(use_cache=False)` timing:
- Total: ~129s
- pre_start + post_start: ~117s (WPS install ~80s + PPTX download + warm-up)
- pre_task: ~12s (kill/reset/launch/wait for WPS to open)

## Task Start States (all verified on 1920×1080)

| Task | Start State | Screenshot | Notes |
|------|-------------|------------|-------|
| edit_title_slide | WPS on slide 1, no dialogs | task_edit_title_slide_start_state.png | |
| add_new_slide | WPS on slide 48 (last slide), no dialogs | task_add_new_slide_start_state.png | |
| insert_text_box | WPS on slide 2, no dialogs | task_insert_text_box_start_state.png | |
| apply_design_theme | WPS on slide 1, no dialogs | task_apply_design_theme_start_state.png | Identical state to edit_title_slide (both correctly start at slide 1 of unmodified file) |
| export_to_pdf | WPS on slide 1, no dialogs | task_export_to_pdf_start_state.png | |

**Note on tasks 1 and 4**: `edit_title_slide` and `apply_design_theme` have identical start states — both begin with WPS on slide 1 of the unmodified `performance.pptx`. Their start-state screenshots are pixel-identical because the application state is genuinely identical. This is correct, not an error.

## Interactive Task Completability Evidence

All 5 tasks were interactively demonstrated and confirmed completable.

---

### Task 1: edit_title_slide ✓

**Goal**: Change slide 1 title to "Apache Performance Benchmark Report"

**Steps demonstrated**:
1. WPS on slide 1 (original title: "Apache Performance Tuning")
2. Clicked the title placeholder, selected all existing text
3. Typed "Apache Performance Benchmark Report"
4. Clicked outside to deselect, saved with Ctrl+S

**Screenshots**:

| File | Shows |
|------|-------|
| `task_edit_title_slide_start_state.png` | WPS on slide 1, original title "Apache Performance Tuning" |
| `task_edit_title_slide_title_typed.png` | New title "Apache Performance Benchmark Report" in edit mode (Drawing Tools tab active) |
| `task_edit_title_slide_completed.png` | Slide 1 with new title rendered, deselected, thumbnail updated, file saved |

---

### Task 2: add_new_slide ✓

**Goal**: Add slide at end with title "Summary and Conclusions"

**Steps demonstrated**:
1. WPS on slide 48 (last slide, "Further Reading" bibliography)
2. Right-clicked last slide thumbnail → "New Slide" → blank slide 49 added
3. Clicked the title placeholder on slide 49, typed "Summary and Conclusions"
4. Saved with Ctrl+S

**Screenshots**:

| File | Shows |
|------|-------|
| `task_add_new_slide_start_state.png` | WPS on slide 48 "Further Reading" (bibliography of Apache books) — confirmed last slide |
| `task_add_new_slide_slide_added.png` | Blank slide 49 added, Slide Properties panel open on right — **no title yet** (this is the intermediate state immediately after inserting the slide, before typing the title) |
| `task_add_new_slide_completed.png` | Slide 49 with "Summary and Conclusions" title typed, thumbnail updated, file saved |

---

### Task 3: insert_text_box ✓

**Goal**: Insert text box on slide 2 with "Performance data collected 2024"

**Steps demonstrated**:
1. WPS on slide 2 (Apache performance description with ApacheCon branding)
2. Clicked Insert tab → Text Box tool
3. Drew a wide text box on slide 2 (lower portion)
4. Typed "Performance data collected 2024" — text fits on one line in the wide text box
5. Clicked outside to deselect the text box
6. Saved with Ctrl+S

**Screenshots**:

| File | Shows |
|------|-------|
| `task_insert_text_box_start_state.png` | WPS on slide 2, original content (no text box), Home tab active |
| `task_insert_text_box_text_typed.png` | Text box in edit mode (cursor active inside), "Performance data collected 2024" typed on one line, Drawing Tools tab active in ribbon |
| `task_insert_text_box_text_deselected.png` | Text box deselected, text "Performance data collected 2024" visible on slide 2 without selection handles |
| `task_insert_text_box_completed.png` | File saved (no asterisk in tab), text box deselected, text fully visible on slide 2 |

The `text_typed` and `completed` screenshots are **distinctly different**: `text_typed` shows the text cursor active inside the box (Drawing Tools ribbon active), while `completed` shows the saved state with the text box deselected and no unsaved indicator in the tab.

---

### Task 4: apply_design_theme ✓

**Goal**: Apply a built-in WPS design theme to all slides

**Steps demonstrated**:
1. WPS on slide 1 (original ApacheCon custom styling)
2. Clicked Design tab → selected "Blue Waves" theme from the theme gallery
3. Theme applied to all 48 slides
4. Saved with Ctrl+S

**Screenshots**:

| File | Shows |
|------|-------|
| `task_apply_design_theme_start_state.png` | WPS on slide 1, original ApacheCon theme (dark blue bottom bar, logo) |
| `task_apply_design_theme_applied.png` | "Blue Waves" theme applied — slide thumbnails all updated with new blue gradient design, Design tab active |
| `task_apply_design_theme_completed.png` | Theme persists, file saved |

---

### Task 5: export_to_pdf ✓

**Goal**: Export presentation as PDF using WPS "Export to PDF" feature

**Steps demonstrated**:
1. WPS on slide 1
2. Clicked WPS menu button (top-left hamburger menu) → selected "Export to PDF"
3. "Export PDF File" dialog opened with default path `/home/ga/Documents/presentations/performance.pdf`
4. Clicked OK to export all 48 slides
5. Progress dialog confirmed: "Exporting PDF file is completed."

**Verification** (via SSH):
```
$ file /home/ga/Documents/presentations/performance.pdf
/home/ga/Documents/presentations/performance.pdf: PDF document, version 1.7, 48 pages
$ ls -la /home/ga/Documents/presentations/performance.pdf
-rw-rw-r-- 1 ga ga 955369 Feb 20 07:42 /home/ga/Documents/presentations/performance.pdf
```

**Screenshots**:

| File | Shows |
|------|-------|
| `task_export_to_pdf_start_state.png` | WPS on slide 1, no existing PDF |
| `task_export_to_pdf_dialog_open.png` | "Export PDF File" dialog with path field showing `/home/ga/Documents/presentations/performance.pdf` |
| `task_export_to_pdf_completed.png` | "Exporting PDF file is completed." success dialog over slide |

---

## Key Technical Findings from Interactive Testing

### First-Run Dialogs (handled by post_start warm-up)

1. **EULA dialog** — "Kingsoft Office Software License Agreement and Privacy Policy"
   - Native Qt window, appears on first WPS launch after installation
   - WPS simultaneously opens Firefox to display the EULA web page
   - **Fix**: Kill Firefox, raise EULA window, click checkbox at (645, 648), click "I Confirm" at (1290, 648)
   - `xdotool key --window` does NOT work (Qt ignores XSendEvent for Tab/Space)
   - Mouse clicks via `xdotool mousemove X Y click 1` DO work

2. **"WPS Office" file format check dialog**
   - Appears on first PPTX open (not on bare `wpp` launch)
   - **Fix**: warm-up launches `wpp performance.pptx` (not just `wpp`), then clicks OK at (1280, 630)

### Dialog Coordinates on 1920×1080

- EULA dialog: checkbox at (645, 648), "I Confirm" at (1290, 648)
- "WPS Office" format check dialog: OK button at approximately (1280, 630)
- Export PDF File dialog: OK button at approximately (1208, 798)

### wait_for_wps False-Positive Fix

Original pattern `grep -qi "wps\|presentation\|kingsoft"` matched the EULA dialog title
("Kingsoft Office Software License Agreement"), causing false-positive detection before
the file was actually loaded.

**Fix**: Match only on `grep -q "performance\.pptx"` — this only matches when the
PPTX file is shown in the window title, guaranteeing the file is fully loaded.

### PDF Export Notes

- WPS PDF export works natively via Menu button → Export to PDF
- Default export filename: `performance.pdf` (strips `.pptx` extension from source)
- Export path: `/home/ga/Documents/presentations/performance.pdf`
- Export produces valid PDF 1.7, 48 pages, ~955KB
- `wpspdf` CLI exists at `/opt/kingsoft/wps-office/office6/wpspdf` but requires DISPLAY (not headless)
