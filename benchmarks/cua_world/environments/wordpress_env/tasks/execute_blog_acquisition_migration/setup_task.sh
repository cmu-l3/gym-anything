#!/bin/bash
# Setup script for execute_blog_acquisition_migration task

echo "=== Setting up Blog Acquisition Migration task ==="

source /workspace/scripts/task_utils.sh

# Record task start timestamp
date +%s > /tmp/task_start_timestamp
chmod 666 /tmp/task_start_timestamp

# 1. Install and activate WordPress Importer
echo "Ensuring WordPress Importer is active..."
cd /var/www/html/wordpress
wp plugin install wordpress-importer --activate --allow-root 2>&1

# 2. Generate the WXR export file for the agent to import
echo "Generating CloudNova export file..."
mkdir -p /home/ga/Documents

cat > /home/ga/Documents/cloudnova_export.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8" ?>
<rss version="2.0"
	xmlns:excerpt="http://wordpress.org/export/1.2/excerpt/"
	xmlns:content="http://purl.org/rss/1.0/modules/content/"
	xmlns:wfw="http://wellformedweb.org/CommentAPI/"
	xmlns:dc="http://purl.org/dc/elements/1.1/"
	xmlns:wp="http://wordpress.org/export/1.2/"
>
<channel>
	<title>CloudNova</title>
	<link>http://cloudnova.local</link>
	<description>Cloud Infrastructure Startup</description>
	<pubDate>Mon, 01 Jan 2024 00:00:00 +0000</pubDate>
	<language>en-US</language>
	<wp:wxr_version>1.2</wp:wxr_version>
	<wp:base_site_url>http://cloudnova.local</wp:base_site_url>
	<wp:base_blog_url>http://cloudnova.local</wp:base_blog_url>

	<wp:author><wp:author_id>1</wp:author_id><wp:author_login><![CDATA[johndoe]]></wp:author_login><wp:author_email><![CDATA[john@cloudnova.local]]></wp:author_email><wp:author_display_name><![CDATA[John Doe]]></wp:author_display_name><wp:author_first_name><![CDATA[John]]></wp:author_first_name><wp:author_last_name><![CDATA[Doe]]></wp:author_last_name></wp:author>

	<item>
		<title>Welcome to CloudNova</title>
		<link>http://cloudnova.local/welcome/</link>
		<pubDate>Mon, 01 Jan 2024 10:00:00 +0000</pubDate>
		<dc:creator><![CDATA[johndoe]]></dc:creator>
		<description></description>
		<content:encoded><![CDATA[We are excited to launch CloudNova! Join us in revolutionizing cloud infrastructure.]]></content:encoded>
		<excerpt:encoded><![CDATA[]]></excerpt:encoded>
		<wp:post_id>10</wp:post_id>
		<wp:post_date><![CDATA[2024-01-01 10:00:00]]></wp:post_date>
		<wp:post_date_gmt><![CDATA[2024-01-01 10:00:00]]></wp:post_date_gmt>
		<wp:comment_status><![CDATA[closed]]></wp:comment_status>
		<wp:ping_status><![CDATA[closed]]></wp:ping_status>
		<wp:post_name><![CDATA[welcome]]></wp:post_name>
		<wp:status><![CDATA[publish]]></wp:status>
		<wp:post_parent>0</wp:post_parent>
		<wp:menu_order>0</wp:menu_order>
		<wp:post_type><![CDATA[post]]></wp:post_type>
		<wp:post_password><![CDATA[]]></wp:post_password>
		<wp:is_sticky>0</wp:is_sticky>
		<category domain="category" nicename="engineering"><![CDATA[Engineering]]></category>
	</item>
	<item>
		<title>5 Tips for Cloud Security</title>
		<link>http://cloudnova.local/cloud-security/</link>
		<pubDate>Tue, 02 Jan 2024 10:00:00 +0000</pubDate>
		<dc:creator><![CDATA[johndoe]]></dc:creator>
		<description></description>
		<content:encoded><![CDATA[Security is important. Here are 5 tips for maintaining a secure environment...]]></content:encoded>
		<wp:post_id>11</wp:post_id>
		<wp:post_date><![CDATA[2024-01-02 10:00:00]]></wp:post_date>
		<wp:post_date_gmt><![CDATA[2024-01-02 10:00:00]]></wp:post_date_gmt>
		<wp:status><![CDATA[publish]]></wp:status>
		<wp:post_type><![CDATA[post]]></wp:post_type>
		<category domain="category" nicename="engineering"><![CDATA[Engineering]]></category>
	</item>
	<item>
		<title>Scaling Microservices Architecture</title>
		<link>http://cloudnova.local/scaling-microservices/</link>
		<pubDate>Wed, 03 Jan 2024 10:00:00 +0000</pubDate>
		<dc:creator><![CDATA[johndoe]]></dc:creator>
		<description></description>
		<content:encoded><![CDATA[Microservices allow us to scale individual components effectively.]]></content:encoded>
		<wp:post_id>12</wp:post_id>
		<wp:post_date><![CDATA[2024-01-03 10:00:00]]></wp:post_date>
		<wp:post_date_gmt><![CDATA[2024-01-03 10:00:00]]></wp:post_date_gmt>
		<wp:status><![CDATA[publish]]></wp:status>
		<wp:post_type><![CDATA[post]]></wp:post_type>
		<category domain="category" nicename="engineering"><![CDATA[Engineering]]></category>
	</item>
	<item>
		<title>Draft: Internal Q3 Strategy</title>
		<link>http://cloudnova.local/?p=13</link>
		<pubDate>Thu, 04 Jan 2024 10:00:00 +0000</pubDate>
		<dc:creator><![CDATA[johndoe]]></dc:creator>
		<description></description>
		<content:encoded><![CDATA[CONFIDENTIAL: Our acquisition targets for Q3 are highly sensitive and must not be leaked to the public.]]></content:encoded>
		<wp:post_id>13</wp:post_id>
		<wp:post_date><![CDATA[2024-01-04 10:00:00]]></wp:post_date>
		<wp:post_date_gmt><![CDATA[2024-01-04 10:00:00]]></wp:post_date_gmt>
		<wp:status><![CDATA[draft]]></wp:status>
		<wp:post_type><![CDATA[post]]></wp:post_type>
	</item>
</channel>
</rss>
EOF

chown ga:ga /home/ga/Documents/cloudnova_export.xml
chmod 644 /home/ga/Documents/cloudnova_export.xml
echo "Export file created at /home/ga/Documents/cloudnova_export.xml"

# 3. Ensure Firefox is running
echo "Checking Firefox status..."
if ! pgrep -x "firefox" > /dev/null 2>&1; then
    echo "Firefox not running, starting..."
    su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/' > /tmp/firefox_restart.log 2>&1 &"
    sleep 10
fi

# 4. Focus and maximize Firefox
WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla\|wordpress" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="