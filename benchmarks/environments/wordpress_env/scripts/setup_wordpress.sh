#!/bin/bash
# WordPress Setup Script (post_start hook)
# Starts MariaDB via Docker, runs WordPress installer via WP-CLI,
# imports real sample content from WordPress Theme Unit Test data, launches Firefox
#
# Default admin credentials: admin / Admin1234!

echo "=== Setting up WordPress ==="

# Configuration
WP_DIR="/var/www/html/wordpress"
WP_URL="http://localhost/"
ADMIN_USER="admin"
ADMIN_PASS="Admin1234!"
ADMIN_EMAIL="admin@example.com"
DB_HOST="127.0.0.1"
DB_PORT="3306"
DB_NAME="wordpress"
DB_USER="wordpress"
DB_PASS="wordpresspass"

# Function to wait for MariaDB to be ready
wait_for_mariadb() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for MariaDB to be ready..."

    while [ $elapsed -lt $timeout ]; do
        if docker exec wordpress-mariadb mysqladmin ping -h localhost -uroot -prootpass 2>/dev/null | grep -q "alive"; then
            echo "MariaDB is ready after ${elapsed}s"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        echo "  Waiting for MariaDB... ${elapsed}s"
    done

    echo "WARNING: MariaDB readiness check timed out after ${timeout}s"
    return 1
}

# Function to wait for WordPress web to be ready
wait_for_wordpress() {
    local timeout=${1:-120}
    local elapsed=0

    echo "Waiting for WordPress web interface to be ready..."

    while [ $elapsed -lt $timeout ]; do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$WP_URL" 2>/dev/null)
        if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "302" ] || [ "$HTTP_CODE" = "301" ]; then
            echo "WordPress web is ready after ${elapsed}s (HTTP $HTTP_CODE)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo "  Waiting... ${elapsed}s (HTTP $HTTP_CODE)"
    done

    echo "WARNING: WordPress readiness check timed out after ${timeout}s"
    return 1
}

# ============================================================
# 1. Start MariaDB via Docker Compose
# ============================================================
echo "Setting up Docker Compose configuration..."
mkdir -p /home/ga/wordpress
cp /workspace/config/docker-compose.yml /home/ga/wordpress/
chown -R ga:ga /home/ga/wordpress

echo "Starting MariaDB container..."
cd /home/ga/wordpress
docker-compose pull
docker-compose up -d

# Wait for MariaDB
wait_for_mariadb 120

echo "Docker container status:"
docker-compose ps

# ============================================================
# 2. Configure WordPress via WP-CLI
# ============================================================
echo ""
echo "Configuring WordPress..."

cd "$WP_DIR"

# Create wp-config.php
wp config create \
    --dbname="$DB_NAME" \
    --dbuser="$DB_USER" \
    --dbpass="$DB_PASS" \
    --dbhost="$DB_HOST:$DB_PORT" \
    --allow-root 2>&1

# Install WordPress
echo "Running WordPress installation..."
wp core install \
    --url="$WP_URL" \
    --title="My WordPress Blog" \
    --admin_user="$ADMIN_USER" \
    --admin_password="$ADMIN_PASS" \
    --admin_email="$ADMIN_EMAIL" \
    --skip-email \
    --allow-root 2>&1

INSTALL_EXIT=$?
if [ $INSTALL_EXIT -ne 0 ]; then
    echo "WARNING: WordPress installer exited with code $INSTALL_EXIT"
    # Check if it's already installed
    if wp core is-installed --allow-root 2>/dev/null; then
        echo "WordPress is already installed"
    else
        echo "ERROR: WordPress installation failed."
        exit 1
    fi
fi

# Set permalink structure
echo "Setting permalink structure..."
wp rewrite structure '/%postname%/' --allow-root 2>&1
wp rewrite flush --allow-root 2>&1

# CRITICAL: Create .htaccess manually (WP can't write it when running as root)
echo "Creating .htaccess for permalink support..."
cat > "$WP_DIR/.htaccess" << 'HTACCESSEOF'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HTACCESSEOF
chown www-data:www-data "$WP_DIR/.htaccess"
chmod 644 "$WP_DIR/.htaccess"

# Restart Apache to pick up .htaccess
systemctl restart apache2
sleep 2

# ============================================================
# 3. Configure WordPress Settings
# ============================================================
echo ""
echo "Configuring WordPress settings..."

# Set timezone
wp option update timezone_string "America/Los_Angeles" --allow-root 2>&1

# Set date/time format
wp option update date_format "F j, Y" --allow-root 2>&1
wp option update time_format "g:i a" --allow-root 2>&1

# Set blog description
wp option update blogdescription "A WordPress blog for testing and demonstrations" --allow-root 2>&1

# Enable comments moderation
wp option update comment_moderation 1 --allow-root 2>&1

# Set posts per page
wp option update posts_per_page 10 --allow-root 2>&1

# ============================================================
# 4. Install and Configure Theme
# ============================================================
echo ""
echo "Installing and activating theme..."

# Install and activate Twenty Twenty-Four theme (modern default)
wp theme install twentytwentyfour --activate --allow-root 2>&1 || \
wp theme activate twentytwentyfour --allow-root 2>&1 || \
wp theme activate twentytwentythree --allow-root 2>&1 || true

# ============================================================
# 5. Import WordPress Theme Unit Test Data (REAL data)
# ============================================================
echo ""
echo "Importing WordPress Theme Unit Test data (official test data)..."

# Install WordPress Importer plugin
wp plugin install wordpress-importer --activate --allow-root 2>&1

# Download WordPress Theme Unit Test Data (official sample content from WordPress.org)
# This is the standard test data used by theme developers
THEME_UNIT_TEST_URL="https://raw.githubusercontent.com/WPTT/theme-unit-test/master/themeunittestdata.wordpress.xml"
SAMPLE_DATA_FILE="/tmp/wordpress-theme-unit-test.xml"

echo "Downloading Theme Unit Test data from WordPress.org..."
curl -sL "$THEME_UNIT_TEST_URL" -o "$SAMPLE_DATA_FILE" 2>/dev/null || \
wget -q "$THEME_UNIT_TEST_URL" -O "$SAMPLE_DATA_FILE" 2>/dev/null || true

if [ -f "$SAMPLE_DATA_FILE" ] && [ -s "$SAMPLE_DATA_FILE" ]; then
    echo "Importing Theme Unit Test data..."
    wp import "$SAMPLE_DATA_FILE" --authors=create --allow-root 2>&1 || {
        echo "Theme Unit Test import had some warnings (this is normal)"
    }
    rm -f "$SAMPLE_DATA_FILE"
    echo "Theme Unit Test data imported!"
else
    echo "Could not download Theme Unit Test data, creating sample content manually..."
fi

# ============================================================
# 6. Create Additional Sample Content via WP-CLI
# ============================================================
echo ""
echo "Creating additional sample content..."

# Create categories
echo "Creating categories..."
wp term create category "Technology" --description="Posts about technology and software" --allow-root 2>&1 || true
wp term create category "Travel" --description="Travel stories and tips" --allow-root 2>&1 || true
wp term create category "Lifestyle" --description="Lifestyle and personal development" --allow-root 2>&1 || true
wp term create category "News" --description="Latest news and updates" --allow-root 2>&1 || true
wp term create category "Tutorials" --description="How-to guides and tutorials" --allow-root 2>&1 || true

# Create tags
echo "Creating tags..."
wp term create post_tag "wordpress" --allow-root 2>&1 || true
wp term create post_tag "blogging" --allow-root 2>&1 || true
wp term create post_tag "tips" --allow-root 2>&1 || true
wp term create post_tag "guide" --allow-root 2>&1 || true
wp term create post_tag "featured" --allow-root 2>&1 || true

# Create sample posts with real content
echo "Creating sample blog posts..."

wp post create --post_type=post --post_status=publish --post_title="Getting Started with WordPress" \
    --post_content="<p>Welcome to WordPress! This is your first step into the world of content management systems. WordPress powers over 40% of all websites on the internet, making it the most popular CMS in the world.</p>
<h2>Why Choose WordPress?</h2>
<p>WordPress offers several advantages:</p>
<ul>
<li>Easy to use and learn</li>
<li>Highly customizable with themes and plugins</li>
<li>Strong community support</li>
<li>SEO-friendly out of the box</li>
</ul>
<p>In this blog, we'll explore various topics related to WordPress development, blogging best practices, and digital content creation.</p>" \
    --post_author=1 --allow-root 2>&1 || true

wp post create --post_type=post --post_status=publish --post_title="10 Essential WordPress Plugins Every Site Needs" \
    --post_content="<p>Building a successful WordPress site requires the right tools. Here are our top 10 plugin recommendations for 2024:</p>
<ol>
<li><strong>Yoast SEO</strong> - Optimize your content for search engines</li>
<li><strong>WP Super Cache</strong> - Speed up your site with caching</li>
<li><strong>Akismet</strong> - Protect against spam comments</li>
<li><strong>Wordfence</strong> - Security and firewall protection</li>
<li><strong>Contact Form 7</strong> - Easy form creation</li>
<li><strong>UpdraftPlus</strong> - Automated backups</li>
<li><strong>Jetpack</strong> - All-in-one site management</li>
<li><strong>WooCommerce</strong> - E-commerce functionality</li>
<li><strong>Elementor</strong> - Visual page builder</li>
<li><strong>MonsterInsights</strong> - Google Analytics integration</li>
</ol>
<p>Each plugin serves a specific purpose and together they form a solid foundation for any WordPress website.</p>" \
    --post_author=1 --allow-root 2>&1 || true

wp post create --post_type=post --post_status=publish --post_title="The Art of Writing Engaging Blog Content" \
    --post_content="<p>Creating content that resonates with your audience is both an art and a science. Here are proven strategies for writing blog posts that people actually want to read.</p>
<h2>Start with a Hook</h2>
<p>Your opening sentence should grab attention immediately. Ask a question, share a surprising fact, or tell a brief story.</p>
<h2>Structure Your Content</h2>
<p>Use headings, subheadings, bullet points, and short paragraphs. Most readers scan content before deciding to read it fully.</p>
<h2>Add Value</h2>
<p>Every post should answer a question, solve a problem, or provide entertainment. Ask yourself: what will readers gain from this?</p>
<h2>End with a Call to Action</h2>
<p>Tell your readers what to do next - leave a comment, share the post, or explore related content.</p>" \
    --post_author=1 --allow-root 2>&1 || true

wp post create --post_type=post --post_status=draft --post_title="Draft: Upcoming Features We're Excited About" \
    --post_content="<p>This is a draft post containing information about features we're planning to write about. This content is not yet ready for publication.</p>
<p>Topics to cover:</p>
<ul>
<li>WordPress 6.5 block editor improvements</li>
<li>New theme.json features</li>
<li>Performance enhancements</li>
</ul>" \
    --post_author=1 --allow-root 2>&1 || true

# Create sample pages
echo "Creating sample pages..."

wp post create --post_type=page --post_status=publish --post_title="About Us" \
    --post_content="<h2>Welcome to Our Blog</h2>
<p>We are passionate about WordPress and helping others succeed online. Our team has been working with WordPress since its early days, and we love sharing our knowledge with the community.</p>
<h3>Our Mission</h3>
<p>To provide valuable, actionable content that helps WordPress users of all skill levels create better websites.</p>
<h3>What We Cover</h3>
<ul>
<li>WordPress tutorials and guides</li>
<li>Theme and plugin reviews</li>
<li>Best practices for site management</li>
<li>Performance optimization tips</li>
</ul>" \
    --post_author=1 --allow-root 2>&1 || true

wp post create --post_type=page --post_status=publish --post_title="Contact" \
    --post_content="<h2>Get in Touch</h2>
<p>We'd love to hear from you! Whether you have questions, suggestions, or just want to say hello, feel free to reach out.</p>
<h3>Contact Information</h3>
<p><strong>Email:</strong> contact@example.com</p>
<p><strong>Address:</strong> 123 Main Street, San Francisco, CA 94105</p>
<p>We typically respond to inquiries within 24-48 hours.</p>" \
    --post_author=1 --allow-root 2>&1 || true

wp post create --post_type=page --post_status=publish --post_title="Privacy Policy" \
    --post_content="<h2>Privacy Policy</h2>
<p>Last updated: January 2024</p>
<h3>Information We Collect</h3>
<p>We collect information you provide directly to us, such as when you create an account, submit a form, or contact us.</p>
<h3>How We Use Your Information</h3>
<p>We use the information we collect to provide, maintain, and improve our services.</p>
<h3>Contact Us</h3>
<p>If you have any questions about this Privacy Policy, please contact us at privacy@example.com.</p>" \
    --post_author=1 --allow-root 2>&1 || true

# Create sample users
echo "Creating sample users..."
wp user create editor editor@example.com --role=editor --first_name="Emma" --last_name="Editor" --user_pass="Editor123!" --allow-root 2>&1 || true
wp user create author author@example.com --role=author --first_name="Alex" --last_name="Author" --user_pass="Author123!" --allow-root 2>&1 || true
wp user create contributor contributor@example.com --role=contributor --first_name="Chris" --last_name="Contributor" --user_pass="Contributor123!" --allow-root 2>&1 || true

echo "Sample content created!"
echo "Post count: $(wp post list --post_type=post --post_status=any --format=count --allow-root 2>/dev/null)"
echo "Page count: $(wp post list --post_type=page --post_status=any --format=count --allow-root 2>/dev/null)"
echo "User count: $(wp user list --format=count --allow-root 2>/dev/null)"

# ============================================================
# 7. Install auto-login MU-plugin for test environment
# ============================================================
echo "Installing auto-login MU-plugin..."
mkdir -p "$WP_DIR/wp-content/mu-plugins"
cat > "$WP_DIR/wp-content/mu-plugins/auto-login.php" << 'MULOGINEOF'
<?php
/**
 * Auto-login MU-plugin for test environments.
 * Logs in as admin when ?autologin=admin is in the URL.
 * This is only for automated testing in QEMU environments.
 */
add_action('init', function() {
    if (isset($_GET['autologin']) && $_GET['autologin'] === 'admin' && !is_user_logged_in()) {
        $user = get_user_by('login', 'admin');
        if ($user) {
            wp_set_current_user($user->ID);
            wp_set_auth_cookie($user->ID, true);
            $redirect = remove_query_arg('autologin');
            if (empty($redirect) || $redirect === home_url('/')) {
                $redirect = admin_url();
            }
            wp_safe_redirect($redirect);
            exit;
        }
    }
});
MULOGINEOF
chown www-data:www-data "$WP_DIR/wp-content/mu-plugins/auto-login.php"
chmod 644 "$WP_DIR/wp-content/mu-plugins/auto-login.php"

# ============================================================
# 8. Fix permissions
# ============================================================
echo "Fixing permissions..."
chown -R www-data:www-data "$WP_DIR"
chmod -R 755 "$WP_DIR"
mkdir -p "$WP_DIR/wp-content/uploads"
chmod -R 777 "$WP_DIR/wp-content/uploads" 2>/dev/null || true

# ============================================================
# 9. Restart Apache
# ============================================================
echo ""
echo "Restarting Apache..."
systemctl restart apache2

# Wait for WordPress to be accessible
wait_for_wordpress 120

# ============================================================
# 10. Create utility script for database queries
# ============================================================
cat > /usr/local/bin/wp-db-query << 'DBQUERYEOF'
#!/bin/bash
# Execute SQL query against WordPress database (via Docker MariaDB)
docker exec wordpress-mariadb mysql -u wordpress -pwordpresspass wordpress -e "$1"
DBQUERYEOF
chmod +x /usr/local/bin/wp-db-query

# ============================================================
# 11. Set up Firefox profile for user 'ga'
# ============================================================
echo "Setting up Firefox profile..."
FIREFOX_PROFILE_DIR="/home/ga/.mozilla/firefox"
sudo -u ga mkdir -p "$FIREFOX_PROFILE_DIR/default-release"

# Create Firefox profiles.ini
cat > "$FIREFOX_PROFILE_DIR/profiles.ini" << 'FFPROFILE'
[Install4F96D1932A9F858E]
Default=default-release
Locked=1

[Profile0]
Name=default-release
IsRelative=1
Path=default-release
Default=1

[General]
StartWithLastProfile=1
Version=2
FFPROFILE
chown ga:ga "$FIREFOX_PROFILE_DIR/profiles.ini"

# Create user.js to configure Firefox
cat > "$FIREFOX_PROFILE_DIR/default-release/user.js" << 'USERJS'
// Disable first-run screens and welcome pages
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("browser.aboutwelcome.enabled", false);
user_pref("browser.rights.3.shown", true);
user_pref("datareporting.policy.dataSubmissionPolicyBypassNotification", true);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
user_pref("browser.shell.checkDefaultBrowser", false);
user_pref("browser.shell.didSkipDefaultBrowserCheckOnFirstRun", true);

// Set homepage to WordPress admin
user_pref("browser.startup.homepage", "http://localhost/wp-admin/");
user_pref("browser.startup.page", 1);

// Disable update checks
user_pref("app.update.enabled", false);
user_pref("app.update.auto", false);

// Disable password saving prompts
user_pref("signon.rememberSignons", false);
user_pref("signon.autofillForms", false);

// Disable sidebar and other popups
user_pref("sidebar.revamp", false);
user_pref("sidebar.verticalTabs", false);
user_pref("browser.sidebar.dismissed", true);
user_pref("browser.vpn_promo.enabled", false);
user_pref("browser.messaging-system.whatsNewPanel.enabled", false);
user_pref("browser.uitour.enabled", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons", false);
user_pref("browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features", false);
user_pref("extensions.pocket.enabled", false);
user_pref("identity.fxaccounts.enabled", false);
USERJS
chown ga:ga "$FIREFOX_PROFILE_DIR/default-release/user.js"

# Set ownership of Firefox profile
chown -R ga:ga "$FIREFOX_PROFILE_DIR"

# Create desktop shortcut
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/WordPress.desktop << 'DESKTOPEOF'
[Desktop Entry]
Name=WordPress Admin
Comment=WordPress Administration Dashboard
Exec=firefox http://localhost/wp-admin/
Icon=firefox
StartupNotify=true
Terminal=false
Type=Application
Categories=Office;
DESKTOPEOF
chown ga:ga /home/ga/Desktop/WordPress.desktop
chmod +x /home/ga/Desktop/WordPress.desktop

# ============================================================
# 12. Launch Firefox
# ============================================================
echo "Launching Firefox with WordPress admin (auto-login)..."
su - ga -c "DISPLAY=:1 firefox 'http://localhost/wp-admin/?autologin=admin' > /tmp/firefox_wordpress.log 2>&1 &"

# Wait for Firefox window to appear
sleep 5
FIREFOX_STARTED=false
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox\|mozilla"; then
        FIREFOX_STARTED=true
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

if [ "$FIREFOX_STARTED" = true ]; then
    # Maximize Firefox window
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox\|mozilla" | head -1 | awk '{print $1}')
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    fi

    # Wait for WordPress admin page to fully render
    echo "Waiting for WordPress admin page to fully render..."
    PAGE_LOADED=false

    for i in {1..60}; do
        WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
        if echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
            PAGE_LOADED=true
            echo "WordPress Dashboard detected in window title after ${i}s"
            echo "Window title: $WINDOW_TITLE"
            break
        elif echo "$WINDOW_TITLE" | grep -qi "wordpress.*—.*mozilla"; then
            PAGE_LOADED=true
            echo "WordPress page detected in window title after ${i}s"
            echo "Window title: $WINDOW_TITLE"
            break
        fi
        sleep 1
    done

    if [ "$PAGE_LOADED" = false ]; then
        echo "WARNING: WordPress admin page title not detected after 60s"
        echo "Current window title: $(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i firefox)"
        echo "Attempting to refresh the page..."
        DISPLAY=:1 xdotool key F5 2>/dev/null || true
        sleep 10
    fi

    # Additional wait for page rendering
    echo "Waiting additional 10s for page rendering..."
    sleep 10

    # Take verification screenshot
    echo "Taking verification screenshot..."
    DISPLAY=:1 import -window root /tmp/setup_verification.png 2>/dev/null || true

    # Log final window state
    echo "Final window list:"
    DISPLAY=:1 wmctrl -l 2>/dev/null || true
fi

echo ""
echo "=== WordPress Setup Complete ==="
echo ""
echo "WordPress is running at: $WP_URL"
echo "Admin panel: ${WP_URL}wp-admin/"
echo ""
echo "Login Credentials:"
echo "  Admin: ${ADMIN_USER} / ${ADMIN_PASS}"
echo "  Editor: editor / Editor123!"
echo "  Author: author / Author123!"
echo ""
echo "Pre-loaded Content:"
echo "  - Theme Unit Test data (posts, pages, comments, media)"
echo "  - 5 categories (Technology, Travel, Lifestyle, News, Tutorials)"
echo "  - 5 tags (wordpress, blogging, tips, guide, featured)"
echo "  - Sample blog posts and pages"
echo "  - 4 users (admin, editor, author, contributor)"
echo ""
echo "Database access (via Docker):"
echo "  wp-db-query \"SELECT COUNT(*) FROM wp_posts WHERE post_type='post'\""
echo ""
