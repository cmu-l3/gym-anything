# Task: Custom Extraction Product Audit

## Domain Context

**Occupation**: Senior E-commerce SEO Analyst
**Industry**: Digital Marketing / E-commerce (Online Merchants, Search Marketing Strategists)
**Tool Feature**: Screaming Frog Custom Extraction (CSS selectors)

Real e-commerce SEO analysts routinely use Screaming Frog's Custom Extraction feature to pull product-specific metadata (prices, ratings, availability) alongside standard on-page SEO signals (titles, H1 tags, meta descriptions). This combined data lets them correlate product catalog attributes with SEO performance — for example, checking whether low-rated or out-of-stock products still rank for competitive keywords that would be better served by in-stock products.

## Goal

Crawl `https://books.toscrape.com/` with **Custom Extraction** configured to extract:
- Product price using CSS selector `.price_color`
- Product star rating using CSS selector `.star-rating` (extract the `class` attribute)

After the crawl, export:
1. **Custom Extraction CSV** — contains URL + extracted price + extracted rating per page
2. **Internal HTML pages CSV** — standard on-page SEO report with titles, H1, meta descriptions

Both CSV files must be saved to `~/Documents/SEO/exports/`.

## What Success Looks Like

- Screaming Frog has crawled `books.toscrape.com`
- A CSV exists in `~/Documents/SEO/exports/` (created after task started) containing a custom extraction column with values like `£12.34` (pound sterling prices) or rating class values like `star-rating Three`
- The custom extraction CSV has ≥20 rows of product page data
- A second CSV exists in `~/Documents/SEO/exports/` that is the standard internal HTML report

## Verification Strategy

1. Find the most recently created CSV files in `~/Documents/SEO/exports/` (after task start)
2. Identify the custom extraction CSV by checking for column content matching price data (£ symbol) or rating class data
3. Verify the custom extraction CSV has ≥20 data rows with books.toscrape.com URLs
4. Check that a second CSV exists with standard internal columns (Title 1, Meta Description 1, H1-1)
5. Verify at least one extracted column contains non-empty values

## SF Feature Details

**Configuration → Custom Extraction** dialog:
- Click `+` to add an extraction rule
- Set Name (e.g., "Price"), Source = "CSS Path", CSS Path = `.price_color`, Extract = "Text"
- Add a second rule: Name = "Rating", Source = "CSS Path", CSS Path = `.star-rating`, Extract = "Attribute: class"
- Enable the "Custom Extraction" checkbox before crawling

**Exporting**: After crawl completes, use the "Custom" tab → Export, or use Bulk Export options.

## Anti-Gaming Notes

- Task start timestamp recorded in `/tmp/task_start_time`
- Only CSVs modified AFTER task start count
- Domain check: CSVs must contain `books.toscrape.com` URLs
- Custom extraction column must have non-empty extracted values (rules out exporting wrong tab)
