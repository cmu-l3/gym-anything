# Ekylibre Environment — Evidence Documentation

Verified working on: 2026-02-21
Ekylibre version: 4.24.0
URL: http://demo.ekylibre.farm:3000
Admin credentials: admin@ekylibre.org / 12345678
Farm data: GAEC JOULIN (real French farm, Charente-Maritime)

## Screenshots

### Environment Evidence

| File | Page | Notes |
|------|------|-------|
| `01_dashboard.png` | General Dashboard (Tableau de bord général) | Shows all modules: Tiers, Comptabilité, Achats, Stocks, Production, RH, Outils, Configuration + weather/sensor chart |
| `02_animals.png` | Animals list (/backend/animals) | 171 animals loaded from GAEC JOULIN demo data; shows breed, sex, weight |
| `03_interventions.png` | Interventions (/backend/interventions) | Shows kanban view for 2023 campaign: Planifiée (0), En cours (0), Terminées (2), Validée (0); 2 "Pulvérisation" interventions from demo data visible with land parcels ZC#01, ZC#02, ZC#06, ZC#07, ZC#10, ZC#19 assigned to David JOULIN; 40 total interventions across years 2016-2023 |
| `04_entities.png` | Entities/Contacts (/backend/entities) | Supplier and client contacts loaded from demo data |
| `05_journal_entries.png` | Accounting journals list (/backend/journal_entries → /backend/journals) | Comptabilité module; note: /backend/journal_entries redirects to journals list; journal entries (écritures) are accessed per-journal |
| `06_workers.png` | Workers (/backend/workers) | Farm workers/employees list |
| `07_equipments.png` | Equipment (/backend/equipments) | Farm equipment list with serial numbers, profiles, and maintenance status |

### Task Start-State Screenshots

| File | Task | URL | Notes |
|------|------|-----|-------|
| `08_task_activity_budget_form.png` | add_activity_budget | /backend/activity_budgets/new?activity_id=3&campaign_id=8 | "Nouveau budget : Blé tendre d'hiver 2023" form; activity_id and campaign_id params are REQUIRED (without them the route returns 500) |
| `09_task_entities_new_form.png` | add_supplier_contact | /backend/entities/new | "Nouvelle organisation" form |
| `10_task_interventions_new_form.png` | record_intervention | /backend/interventions/new | Intervention procedure type selector |
| `11_task_animals_new_form.png` | register_animal | /backend/animals/new?variant_id=152 | "Nouvel animal" full form with Génisse (heifer) pre-selected; shows Nom, Race (Bovin), Né(e) le, Date de sortie, Identification section with Numéro d'identification and Numéro de travail; variant_id=152 REQUIRED to skip article selector step and show full form |
| `12_task_purchases_new_form.png` | create_purchase_order | /backend/purchase_invoices/new | "Nouvelle facture" (new purchase invoice) form; NOTE: /backend/purchases/new and /backend/purchase_orders/new both return 404; correct route is /backend/purchase_invoices |

## URL Notes (Ekylibre 4.18.2 / 4.24.0)

| Intended Page | Working URL | Notes |
|---------------|-------------|-------|
| Activity budget form | `/backend/activity_budgets/new?activity_id=N&campaign_id=N` | Params required; without them → 500 |
| Journals/accounting | `/backend/journals` | `/backend/journal_entries` redirects here |
| Purchase form | `/backend/purchase_invoices/new` | `/backend/purchases` and `/backend/purchase_orders` → 404 |
| Activities list (2023) | `/backend/activities` then navigate to 2023 | Shows Blé tendre d'hiver under Production végétale; campaign_id= URL param is ignored (uses session) |
| Animal new form (full) | `/backend/animals/new?variant_id=152` | variant_id=152=Génisse; without variant_id shows only Article selector (step 1 of 2 — not the full form) |
| Animals | `/backend/animals` | 171 bovines from GAEC JOULIN data |
| Entities | `/backend/entities` | 99 contacts (suppliers, clients) |

## first_run Summary

The `first_run` rake task loaded 47 data loaders from the GAEC JOULIN demo farm dataset:
- `base`: 1 company entity (farm)
- `entities`: 99 supplier/client contacts
- `animals`: 171 animals (bovine breeds)
- `equipments`: farm machinery
- `workers`: farm employees
- `land_parcels`: cadastral parcels (via georeadings)
- `interventions`: farm interventions
- `productions`: crop/livestock productions
- `accountancy`: chart of accounts, journal entries
- `bank_statements`, `cash_transfers`, `deliveries`, `purchases`, `sales`: business transactions
- `analyses`, `buildings`: additional farm data

## Compatibility Fixes Applied

All fixes are baked into the Dockerfile and setup_ekylibre.sh for fresh deployments.

1. **apartment.rb** — `persistent_schemas = %w[postgis lexicon public]`
   PostGIS functions (ST_AsEWKT, ST_MakeValid) are in `public` schema. Apartment's
   search_path must include `public`, otherwise all geometry operations fail in tenant context.

2. **shape_corrector.rb** — nil guard in `postgis_geometries_extraction`
   `return None() if int_type.nil?` added after `}[geometry_type]` hash lookup.
   Prevents `ST_CollectionExtract(geom, )` SQL syntax error when `geometry_type = :any`.

3. **/usr/share/proj/epsg** — PROJ4 text-format CRS file
   PROJ 7.x removed this file; only `proj.db` (SQLite) remains. The `rgeo-proj4` gem's
   `Proj4Data` class reads `/usr/share/proj/epsg` to look up CRS definitions.
   The telepac loader transforms EPSG:2154 (Lambert-93) → EPSG:4326 (WGS84).

4. **freezer.rb** — `pdf_format?` uses magic bytes instead of regex
   `File.open(file_path, 'rb') { |f| f.read(8) }.to_s.start_with?('%PDF-')`
   The original regex `/\A\%PDF-\d+(\.\d+)?$/` fails on PDFs with Windows `\r\n` line
   endings because `$` matches before `\n` but not before `\r`.

5. **poppler-utils + ghostscript** — PDF processing pipeline
   `pdftotext` (poppler-utils) for Docsplit text extraction. `gs` (ghostscript) for
   GraphicsMagick to convert PDF pages to images for attachment thumbnails.
