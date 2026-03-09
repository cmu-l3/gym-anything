#!/bin/bash
set -e

echo "=== Setting up SEO Migration Sitemap Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Create Directories
mkdir -p /home/ga/Desktop
mkdir -p /home/ga/Diagrams/exports
chown -R ga:ga /home/ga/Diagrams

# 1. Generate Site Audit CSV
cat > /home/ga/Desktop/site_audit_data.csv << 'CSVEOF'
URL,Page Title,Monthly Views,Bounce Rate,Status
/,Home,45000,35%,200
/about,About Us,1200,45%,200
/contact,Contact Us,850,20%,200
/returns,Returns Policy,85,15%,200
/shop/mens/hiking-boots,Men's Hiking Boots,3200,40%,200
/shop/womens/hiking-boots,Women's Hiking Boots,2800,42%,200
/shop/mens/jackets,Men's Jackets,1500,50%,200
/shop/womens/jackets,Women's Jackets,1400,48%,200
/shop/mens/discontinued-boots,Clearance Boots 2021,45,85%,200
/shop/accessories/wipes,Lens Wipes,12,90%,200
/blog/top-10-trails,Top 10 Trails,5000,60%,200
/blog/2018/company-picnic,Company Picnic 2018,8,95%,200
/blog/gear-guide-2024,Gear Guide 2024,1200,55%,200
/legacy-sitemap,HTML Sitemap,30,80%,200
/shop/camping/tents,Tents,2100,30%,200
/shop/camping/sleeping-bags,Sleeping Bags,1800,35%,200
CSVEOF

# 2. Generate Migration Strategy Brief
cat > /home/ga/Desktop/migration_strategy_brief.txt << 'TXTEOF'
CONFIDENTIAL - MIGRATION STRATEGY BRIEF
Project: Summit Outdoor Gear - Platform Migration

1. CONSOLIDATION RULES
   We are moving away from gender-based top-level categories.
   - Combine "/shop/mens/hiking-boots" and "/shop/womens/hiking-boots" into a single new category: "Footwear".
   - Combine "/shop/mens/jackets" and "/shop/womens/jackets" into a new category: "Apparel".
   - Keep "Camping" as a top-level category.

2. CONTENT PRUNING (SEO CLEANUP)
   - Prune ANY page with less than 100 monthly views.
   - EXCEPTION: Always keep core utility pages (Contact, Returns, Terms) regardless of traffic.

3. BLOG RESTRUCTURING
   - Move all blog posts under a new section called "Journal".
   - Do not migrate dated/irrelevant posts (apply the <100 views rule strictly to blog posts).

4. NEW PAGES
   - We need a new "Brands" landing page to highlight our partners.

5. VISUAL SITEMAP REQUIREMENTS
   Please map out this target structure in draw.io.
   - Use BLUE boxes for pages we are keeping (e.g., Home, Contact).
   - Use ORANGE boxes for the consolidated categories (Footwear, Apparel).
   - Use GREEN boxes for completely new pages (Brands, Journal).
TXTEOF

# Set permissions
chown ga:ga /home/ga/Desktop/site_audit_data.csv
chown ga:ga /home/ga/Desktop/migration_strategy_brief.txt

# Ensure draw.io is NOT running
pkill -f drawio 2>/dev/null || true

# Launch draw.io (optional, agent can launch it, but helpful to have it ready)
# We won't launch it here to let the agent drive the full interaction, 
# but we ensure the environment is clean.

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="