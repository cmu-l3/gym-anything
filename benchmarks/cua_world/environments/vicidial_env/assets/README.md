# Vicidial Environment Assets

## us_senate_senators_cfm_2026-02-14.xml

Source: U.S. Senate "Senators' Contact Information" XML export.

Downloaded on: 2026-02-14.

## us_senators_vicidial_leads_2026-02-14.csv

Derived from the XML above and formatted for Vicidial lead imports with columns:

- `phone_number`
- `first_name`
- `last_name`
- `state`
- `comments`

This is real public contact information (Senate office phone numbers), not synthetic data.

## us_senators_vicidial_standard_format_list9001_2026-02-14.csv

Derived from the XML above and formatted for Vicidial's List Loader "Standard Format"
(no header row, 100 lead rows).

This file includes `list_id=9001` in-column, so it can be imported directly once the
corresponding Vicidial list is created in the UI.
