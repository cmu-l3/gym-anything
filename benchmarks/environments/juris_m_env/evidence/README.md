# Juris-M Environment — Evidence Documentation

## Overview

Evidence screenshots demonstrating that all 5 tasks are completable by a human agent
in the Juris-M (Jurism 6.0.30m3) reference management environment.

---

## Task 1: `import_legal_references`

**Goal:** Import `supreme_court_cases.ris` from `/home/ga/Documents/` into Jurism.

| Screenshot | Description |
|---|---|
| `empty_library_import_task.png` | Start state — empty library (all items cleared by setup) |
| `import_task_success.png` | After import — 10 items visible in My Library |
| `library_with_10_items.png` | All 10 items (7 cases + 3 law review articles) loaded |

**Verification:** `export_result.sh` counts items and checks for Brown v. Board,
Miranda v. Arizona, Marbury v. Madison by name.

---

## Task 2: `create_law_collection`

**Goal:** Create a new collection in Jurism and add at least 3 legal items to it.

| Screenshot | Description |
|---|---|
| `collection_task_success.png` | "US Constitutional Law" collection with 4 items shown |

**Verification:** `export_result.sh` queries collection count and max items per collection.

---

## Task 3: `add_note_to_case`

**Goal:** Select a case (e.g., Brown v. Board of Education) and add a note to it.

| Screenshot | Description |
|---|---|
| `add_note_task_success.png` | "Brown v. Board of Education" selected, Notes tab showing "Legal Significance" note attached |

**Verification:** `export_result.sh` checks itemNotes table for a note attached to a case item.

---

## Task 4: `add_manual_case`

**Goal:** Manually add the US Supreme Court case "Roe v. Wade" (410 U.S. 113, 1973) as a Case item.

| Screenshot | Description |
|---|---|
| `add_manual_case_success.png` | Roe v. Wade added as 11th item; right panel shows Case Name, Court, and Date Decided fields filled |

**Verification:** `export_result.sh` queries the DB for an item with caseName containing "roe" and "wade",
checks court contains "supreme", date contains "1973".

---

## Task 5: `change_citation_style`

**Goal:** Change the Quick Copy citation style to OSCOLA via Edit > Preferences > Export tab.

| Screenshot | Description |
|---|---|
| `change_citation_style_success.png` | Preferences Export tab showing Item Format = "JM OSCOLA - Oxford Standard for Citation of Legal Authorities" |

**Verification:** `export_result.sh` checks `prefs.js` for `jm-oscola` in the quickCopy.setting preference.

---

## Data Quality Notes

- All 10 references are real US legal cases and law review articles (public domain)
- Supreme Court cases: Brown v. Board, Marbury v. Madison, Miranda v. Arizona, New York Times Co. v. Sullivan,
  Gideon v. Wainwright, Obergefell v. Hodges, Tinker v. Des Moines
- Law review articles: Holmes (The Path of the Law), Monaghan (Constitutional Fact Review), Poe (Due Process)
- OSCOLA (Oxford Standard for Citation of Legal Authorities) is pre-installed at
  `/home/ga/Jurism/styles/jm-oscola.csl`
