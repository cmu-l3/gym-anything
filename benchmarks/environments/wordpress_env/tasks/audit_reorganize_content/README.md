# Task: Audit and Reorganize Content

## Domain Context
**Occupation:** Archivist (SOC 25-4011.00) / Content Strategist
**Rationale:** Archivists and content strategists regularly audit WordPress sites where imported or accumulated content has been miscategorized, left in draft, or contaminated with spam. This task simulates a realistic bulk content reorganization workflow.

## Goal
Fix a set of miscategorized posts, delete spam, publish drafts, and add tags to legitimate content. The agent must edit multiple posts individually, making changes across categories, tags, and status.

## Expected End State
1. "Cloud Computing Trends 2026" → Technology category, published, tagged "featured"
2. "AI in Software Development" → Technology category, tagged "featured"
3. "Weekend Hiking Trail Guide" → Lifestyle category, tagged "featured"
4. "Healthy Meal Prep Ideas" → Lifestyle category, tagged "featured"
5. "Breaking: Local Business Awards Announced" → News category, published, tagged "featured"
6. "V1agra Ch3ap Online Buy Now!!!" → deleted/trashed

## Setup (setup_task.sh)
Creates 6 posts (all by admin, all in Uncategorized):
- Posts 1, 2 as drafts (should be published)
- Posts 3, 4 as published (category change only)
- Post 5 as draft (should be published + recategorized)
- Post 6 as published spam (should be deleted)

Content is programmatic task scaffolding — hand-written professional text providing realistic starting content for the agent to work with.

## Verification Strategy
7 programmatic criteria (10 pts each = 70 pts):
1. "Cloud Computing Trends 2026" in Technology + published (10 pts)
2. "AI in Software Development" in Technology (10 pts)
3. "Weekend Hiking Trail Guide" in Lifestyle (10 pts)
4. "Healthy Meal Prep Ideas" in Lifestyle (10 pts)
5. "Breaking: Local Business Awards" in News + published (10 pts)
6. Spam post deleted/trashed (10 pts)
7. "featured" tag on all 5 legitimate posts (10 pts)

VLM checks (30 pts).

Pass threshold: score >= 70 AND spam deleted AND at least 4 of 5 recategorized.

## Schema Reference
- Posts: `wp_posts` — post_title, post_status, post_type
- Categories: `wp_terms` + `wp_term_taxonomy WHERE taxonomy='category'` + `wp_term_relationships`
- Tags: `wp_terms` + `wp_term_taxonomy WHERE taxonomy='post_tag'` + `wp_term_relationships`

## Edge Cases
- Agent may use Quick Edit or full editor to change categories
- Category reassignment should remove "Uncategorized" (export checks for this)
- Spam post detection: checks for post NOT existing with non-trash status
- Tag "featured" already exists in the system (created by setup_wordpress.sh)
- Posts 1 and 5 need both recategorization AND status change (draft → publish)
