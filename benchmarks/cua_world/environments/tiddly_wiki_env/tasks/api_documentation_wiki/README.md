# api_documentation_wiki

## Overview

**Occupation**: Computer User Support Specialists / Technical Writers
**Difficulty**: hard
**Domain**: Technical Documentation

A technical writer creating REST API documentation for a library management system using TiddlyWiki. This reflects how technical writers use knowledge management tools to organize and maintain API documentation for software systems.

## Goal

Create 5 interconnected tiddlers forming a complete API documentation wiki:

1. **Library API - Overview** — System intro; table of resource types: Resource | Description | Base Endpoint | Supported Methods
2. **Library API - Authentication Guide** — Auth methods; table: Method | When to Use | How to Include | Expiry Policy; includes at least one code example using backtick monospace (`` `code` ``)
3. **Library API - Endpoints Reference** — Core reference with 8+ endpoints grouped by resource (Books, Patrons, Loans); table: HTTP Method | Endpoint Path | Description | Auth Required | Request Body | Response
4. **Library API - Error Codes Reference** — 8+ error codes; table: HTTP Status | Error Code | Error Message | Description | How to Resolve (covers 400, 401, 403, 404, 409, 422, 429, 500)
5. **Library API - Changelog** — 4+ version history entries; table: Version | Release Date | Type | Changes Summary | Breaking Changes; uses `!!` for major version headings

All 5 tiddlers must be tagged `API-Documentation` and `LibrarySystem`, contain `!!` headings, tables, and wikilinks.

## Success Criteria

- All 5 tiddlers exist by exact title
- Each has `API-Documentation` and `LibrarySystem` tags
- Endpoints Reference has 8+ non-header table rows
- Error Codes has 8+ non-header table rows
- Changelog has 4+ non-header table rows
- Auth Guide contains a code example (backtick or `{{{` monospace)
- Each has at least 120 words
- GUI saves confirmed in server log
- Score ≥ 60, found_count ≥ 4, api_tagged ≥ 4, gui_save = true

## Row Count Requirements

The export script counts non-header table rows (lines starting with `|` but not `|!`) in:
- **Endpoints Reference**: need ≥ 8 rows (8 pts for ≥8; 4 pts for ≥4)
- **Error Codes Reference**: need ≥ 8 rows (6 pts for ≥8; 3 pts for ≥4)
- **Changelog**: need ≥ 4 rows (4 pts for ≥4; 2 pts for ≥2)

## Code Example Detection

The Auth Guide tiddler is checked for backtick characters (`` ` ``) or TiddlyWiki code block syntax (`{{{...}}}`). Either satisfies the code example requirement (+4 pts).

## Verification Strategy

**Export script** (`export_result.sh`): Scans all 5 tiddlers. Counts table rows for Endpoints, Error Codes, and Changelog tiddlers. Checks Auth tiddler for code examples.

**Verifier** (`verifier.py`): Multi-criterion scoring:
| Criterion | Points |
|-----------|--------|
| Each tiddler found (×5) | 8 pts each = 40 |
| API-Documentation tag (1/tiddler, cap 5) | 5 |
| LibrarySystem tag (1/tiddler, cap 5) | 5 |
| Tables (2/tiddler, cap 10) | 10 |
| Endpoints ≥8 rows = 8, ≥4 = 4 | 8 |
| Error codes ≥8 rows = 6, ≥4 = 3 | 6 |
| Changelog ≥4 rows = 4, ≥2 = 2 | 4 |
| Auth code example | 4 |
| Wikilinks (1/tiddler, cap 4) | 4 |
| Word count ≥120 (1/tiddler, cap 5) | 5 |
| GUI save | 14 |
| **Total (max 105, capped at 100)** | **100** |

## Tag Normalization

`API-Documentation` tag: verifier checks for `api-documentation`, `apidocumentation`, or any tag containing `api` (case-insensitive). `LibrarySystem` checked similarly.

## Anti-Gaming

Requires `gui_save_detected = true` to pass. Server log checked for: "Library API", "API", "Auth", "Endpoint", "Error Code", "Changelog", "Overview".
