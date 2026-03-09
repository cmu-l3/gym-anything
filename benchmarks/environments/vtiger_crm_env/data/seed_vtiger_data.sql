-- Vtiger CRM Realistic Data Seed
-- This SQL seeds data directly into the Vtiger CRM database tables.
-- Data represents a realistic mid-size technology consulting company.
-- Note: Vtiger uses a CRM entity model with vtiger_crmentity as the master table.
-- Each record needs an entry in vtiger_crmentity + module-specific tables.

-- We'll seed data via the PHP seeder (seed_data.php) which uses Vtiger's
-- internal APIs for proper record creation. This SQL file serves as a
-- supplemental/fallback data source and for reference.

-- The PHP seeder handles:
-- - Organizations (Accounts): 15 real-world companies
-- - Contacts: 25 contacts across those organizations
-- - Deals (Potentials): 12 active deals
-- - Products: 10 technology products/services
-- - Tickets (HelpDesk): 8 support tickets
-- - Calendar Events: 5 scheduled meetings/calls

SELECT 'SQL seed file loaded - primary seeding done via PHP' AS status;
