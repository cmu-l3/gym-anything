# Microsoft Word 2010 Environment — Evidence Documentation

## Environment Overview

- **Environment ID**: `microsoft_word_starter_env@0.1`
- **Application**: Microsoft Word 2010 (from Office 2010 Professional Plus ISO)
- **Base**: Windows 11 QEMU VM (1280x720)
- **Installation**: MSI-based silent install via `setup.exe /config office_config.xml`
- **No login, no activation, no sign-in required**

## Checklist Verification

### 1. Installation script completes without errors

The `install_word_starter.ps1` (pre_start hook) downloads the Office 2010 ISO from Internet Archive,
mounts it, and runs a silent Word-only installation. Output:

```
=== Installing Microsoft Word 2010 ===
Downloading Office 2010 ISO from Internet Archive (~731MB)...
Download complete (WebRequest).
ISO size: 731 MB
Mounting ISO...
ISO mounted at drive: F:
Running Office 2010 setup (Word only, silent install)...
Setup exited with code: 0
Unmounting ISO...
Verifying installation...
Word 2010 installed at: C:\Program Files (x86)\Microsoft Office\Office14\WINWORD.EXE
  Version: 14.0.4734.1000
  Size: 1422168 bytes
=== Word 2010 installation successful ===
```

**Key finding**: Office 2010 Starter (Click-to-Run) FAILS on Windows 11 due to App-V 4.x/5.x
incompatibility. The MSI-based Office 2010 Professional Plus install works without issues.

### 2. Setup script completes without errors

The `setup_word_starter.ps1` (post_start hook) copies data files, suppresses OneDrive,
sets registry keys, and performs a warm-up launch. Full transcript:

```
=== Setting up Word 2010 environment ===
Data files copied to: C:\Users\Docker\Desktop\WordTasks
Disabling OneDrive...
OneDrive uninstalled.
Setting Office 14.0 registry keys...
Warming up Word 2010 (first-run cycle)...
Word executable: C:\Program Files (x86)\Microsoft Office\Office14\WINWORD.EXE
First-run dialog dismissal attempted.
Word warm-up complete.
Available data files in C:\Users\Docker\Desktop\WordTasks:
  - census_press_release.docx
  - company_memo_draft.docx
  - meeting_notes_raw.docx
=== Word 2010 environment setup complete ===
```

### 3. Application visible in screenshot — no dialogs

See: `01_word_2010_blank_launch.png`

Word 2010 launches cleanly with:
- Full ribbon (Home, Insert, Page Layout, References, Mailings, Review, View)
- Styles panel (Normal, No Spacing, Heading 1, Heading 2, Title, Subtitle)
- Clean document area
- **No activation dialogs, no sign-in prompts, no first-run popups**

### 4. Task start states verified (all 3 tasks)

#### format_headings (Easy)
See: `02_format_headings_start_state.png`

- Document: `census_press_release.docx` loaded
- Content: US Census Bureau press release (CB24-SFS.17) about income/poverty 2023
- All text in Normal style (plain, unformatted) — ready for heading application
- 2 pages, 413 words

#### format_table (Medium)
See: `03_format_table_start_state.png`

- Document: `meeting_notes_raw.docx` loaded
- Content: Regional Sales Team Meeting Notes with quarterly revenue figures
- Q1-Q4 data visible ($45,200, $52,100, $48,900, $61,300)
- Plain text format — ready for table creation

#### create_business_letter (Medium)
See: `04_create_business_letter_start_state.png`

- Blank document (Document1)
- Clean Word interface ready for letter composition
- All styles and formatting tools accessible in ribbon

### 5. Task setup runs without errors

The `format_headings/setup_task.ps1` runs the full pipeline:

```
=== Setting up format_headings task ===
Data file ready at: C:\Users\Docker\Desktop\WordTasks\census_press_release.docx
Word executable: C:\Program Files (x86)\Microsoft Office\Office14\WINWORD.EXE
Launching Word via scheduled task (interactive desktop)...
Dismissing dialogs via PyAutoGUI server...
Dialog dismissal complete.
Word is running (PID: 7988)
=== format_headings task setup complete ===
```

### 6. End-to-end pipeline verified

See: `05_format_headings_e2e_final.png`

After running the complete setup pipeline (setup_word_starter.ps1 post_start + format_headings setup_task.ps1),
the document opens in the correct state with no residual dialogs.

### 7. Task is completable interactively

Demonstrated by completing part of the format_headings task:

1. **Selected title** "U.S. Census Bureau News" → See: `06_task_interactive_select_title.png`
2. **Applied Heading 1** → Title changed to large blue text → See: `07_task_interactive_heading1_applied.png`
3. **Applied Heading 2** to "Overview" section → See: `08_task_interactive_heading2_applied.png`
4. **Saved with Ctrl+S** → File saved without additional dialogs → See: `09_task_saved_ctrl_s.png`

The task is completable via:
- Click to position cursor in text
- Home/Shift+End to select line
- Click heading style in ribbon Styles panel
- Ctrl+S to save

## Screenshots Index

| # | File | Description |
|---|------|-------------|
| 01 | `01_word_2010_blank_launch.png` | Word 2010 first launch — clean, no dialogs |
| 02 | `02_format_headings_start_state.png` | Census press release document loaded |
| 03 | `03_format_table_start_state.png` | Meeting notes document loaded |
| 04 | `04_create_business_letter_start_state.png` | Blank document for letter |
| 05 | `05_format_headings_e2e_final.png` | Full pipeline — clean task start |
| 06 | `06_task_interactive_select_title.png` | Title text selected |
| 07 | `07_task_interactive_heading1_applied.png` | Heading 1 applied to title |
| 08 | `08_task_interactive_heading2_applied.png` | Heading 2 applied to Overview |
| 09 | `09_task_saved_ctrl_s.png` | Document saved with Ctrl+S |

## Technical Notes

### Office 2010 Installation
- **Source**: Internet Archive (`archive.org/details/office2010nokeyneeded_201908`)
- **Type**: Office 2010 Professional Plus, MSI-based (NOT Click-to-Run)
- **Install path**: `C:\Program Files (x86)\Microsoft Office\Office14\WINWORD.EXE`
- **Version**: 14.0.4734.1000
- **Config**: `office_config.xml` installs Word only (all other apps disabled via OptionState)

### Why NOT Office 2010 Starter
Office 2010 Starter uses Click-to-Run (App-V 4.x virtualization). Windows 11 has built-in
App-V 5.x which is incompatible. Error: "Microsoft Application Virtualization is installed
in an incompatible configuration." Removing App-V registry keys does not fix it.

### Why NOT Office 365
Office 365 (via ODT) shows an undismissable "Sign in to get started with Excel/Word" dialog
that requires a Microsoft account. Not usable for automated environments.

### Document Recovery Panel
When Word is force-killed (e.g., during warm-up), the next launch shows a "Document Recovery"
panel on the left side. The Close button is at approximately (216, 628) in 1280x720 coordinates.
This is handled by `Dismiss-WordDialogsBestEffort` in `task_utils.ps1`.

### PyAutoGUI Coordinates (1280x720)
- Document area center: (640, 400)
- Heading 1 in Styles panel: (~833, 85)
- Heading 2 in Styles panel: (~900, 85)
- Document Recovery Close button: (~216, 628)
