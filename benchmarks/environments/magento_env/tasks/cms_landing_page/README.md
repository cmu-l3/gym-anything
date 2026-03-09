# CMS Landing Page Task

## Overview

This task tests a Magento admin's ability to create structured CMS content — a combination of a reusable static block and a full landing page that embeds it. It reflects real workflows performed by content marketing managers and web merchandisers who build campaign landing pages for seasonal collections.

**Domain context**: Home décor and lifestyle brands frequently launch seasonal collection pages tied to campaigns. The Magento CMS static block + page pattern is the standard workflow: create a reusable promotional block (often used in multiple places), then build a dedicated landing page that references it. This tests knowledge of Magento's widget/block directive system.

## Goal

Create two linked CMS items:

**CMS Static Block:**
- Identifier: `autumn-collection-featured`
- Title: `Autumn Collection Featured Products`
- Status: Enabled
- Content: Valid HTML with an `<h2>` heading, a paragraph, and a list (`<ul>` or `<ol>`) of at least 3 product categories

**CMS Page:**
- Title: `Autumn Collection 2024`
- URL Key: `autumn-collection-2024`
- Status: Enabled, All Store Views, Layout: 1 column
- Meta Title: `Autumn Collection 2024 | NestWell Home`
- Content must include: `{{block id="autumn-collection-featured"}}`

Both must be saved. The page content must reference the block by its exact identifier.

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Static block with identifier `autumn-collection-featured` exists and is enabled | 20 |
| Block content contains valid HTML (h2 + paragraph + list) | 15 |
| CMS page with URL key `autumn-collection-2024` exists and is enabled | 20 |
| Page meta title contains `Autumn Collection 2024` | 15 |
| Page content contains `{{block id="autumn-collection-featured"}}` directive | 30 |

**Pass threshold: 60 points**

## Verification Strategy

- `setup_task.sh` records initial counts of `cms_block` and `cms_page` rows
- `export_result.sh` queries `cms_block` by `identifier='autumn-collection-featured'`, checks content for HTML tags (`<h2`, `<ul`, `<ol`, `<li`), queries `cms_page` by `identifier='autumn-collection-2024'`, checks page content for the block directive string
- `verifier.py` scores each criterion independently; the block directive check is the highest-value criterion (30 pts) since it proves the linking relationship was established

## Database Schema Reference

```sql
-- CMS blocks
SELECT block_id, title, identifier, is_active, CHAR_LENGTH(content)
FROM cms_block WHERE identifier='autumn-collection-featured';

-- Block content for HTML validation
SELECT content FROM cms_block WHERE block_id=<block_id>;

-- CMS pages
SELECT page_id, title, identifier, is_active, layout_update_xml,
       meta_title, meta_description, CHAR_LENGTH(content)
FROM cms_page WHERE identifier='autumn-collection-2024';

-- Page content for directive check
SELECT content FROM cms_page WHERE page_id=<page_id>;
```

## Edge Cases

- The block directive must be `{{block id="autumn-collection-featured"}}` (exact double-quotes and no spaces around the id value). Some agents may use widget tags instead — the verifier checks for the `block id=` pattern.
- The URL key field in Magento admin is called "URL Key" but the database column is `identifier` in the `cms_page` table.
- An agent that creates the block but forgets the page, or creates the page without the directive, will earn partial credit (up to 35 pts without the 30-pt directive criterion).
