# Task: Configure Editorial Workflow

## Domain Context
**Occupation:** Managing Editor / Content Strategist
**Rationale:** Editors managing content teams use WordPress to assign posts to specific authors, schedule publications for future dates, and manage the editorial pipeline. This requires navigating Posts, Users, and Categories across multiple post creation cycles.

## Goal
Create three posts assigned to different team members with specific scheduling and status configurations.

## Expected End State
1. Post "Q1 2026 Revenue Analysis"
   - Author: editor
   - Category: News
   - Status: future (scheduled)
   - Scheduled date: 2026-03-15 09:00
   - Content: 50+ words about quarterly revenue

2. Post "Spring Product Launch Preview"
   - Author: author
   - Category: Technology
   - Status: future (scheduled)
   - Scheduled date: 2026-03-20 10:00
   - Content: 50+ words about product launches

3. Post "Annual Team Building Event Recap"
   - Author: contributor
   - Category: Lifestyle
   - Status: pending (Pending Review)
   - Content: 50+ words about a team event

## Setup (setup_task.sh)
- Ensures users editor, author, contributor exist with correct roles
- Ensures categories News, Technology, Lifestyle exist
- Cleans up posts from previous runs
- Records baseline post count

## Verification Strategy
7 programmatic criteria (70 pts total):
1. Post 1 exists (5 pts)
2. Post 1 author=editor, category=News (10 pts)
3. Post 1 scheduled for 2026-03-15 (10 pts)
4. Post 2 exists with author=author, category=Technology (10 pts)
5. Post 2 scheduled for 2026-03-20 (10 pts)
6. Post 3 exists with author=contributor, category=Lifestyle (10 pts)
7. Post 3 status=pending (15 pts)

VLM checks (30 pts).

Pass threshold: score >= 70 AND all 3 posts found.

## Schema Reference
- Posts: `wp_posts` — post_title, post_status, post_date, post_author
- Authors: `wp_users` — user_login, ID
- Categories: `wp_terms` + `wp_term_taxonomy` + `wp_term_relationships`

## Edge Cases
- WordPress stores scheduled posts with status "future" and post_date in the future
- Contributors cannot publish posts directly — the admin must create the post and set the author
- The agent must change the author dropdown in the post editor (Gutenberg sidebar)
- Date matching checks YYYY-MM-DD prefix only (time may vary slightly)
