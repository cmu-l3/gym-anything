#!/bin/bash
echo "=== Exporting localize_frontend_spanish task result ==="

source /workspace/scripts/task_utils.sh
APP_DIR="/opt/socioboard/socioboard-web-php"

# Take final screenshot BEFORE messing with caches
take_screenshot /tmp/task_final.png

# Force clear caches to ensure we are testing the actual code state
echo "Clearing Laravel caches..."
cd "$APP_DIR"
sudo -u ga php artisan config:clear > /dev/null 2>&1 || true
sudo -u ga php artisan view:clear > /dev/null 2>&1 || true
sleep 2

# 1. Fetch the rendered HTML of the login page
echo "Fetching rendered HTML..."
curl -sL http://localhost/login > /tmp/login_page.html

# 2. Check for the translated strings in the rendered HTML
# (Using partial matching to avoid unicode/encoding character mismatches)
HTML_HAS_CORREO=$(grep -i -E "correo electr|correo electronico" /tmp/login_page.html | wc -l)
HTML_HAS_CONTRA=$(grep -i "contrase" /tmp/login_page.html | wc -l)
HTML_HAS_INICIAR=$(grep -i "iniciar sesi" /tmp/login_page.html | wc -l)

# 3. Check for HARDCODED translations in the view files (Anti-Gaming Check)
# A proper i18n implementation should have 0 matches here.
VIEWS_HARDCODED=$(grep -r -i -E "correo electr|correo electronico|contrase|iniciar sesi" resources/views/ 2>/dev/null | wc -l)

# 4. Check that the translations exist in the language directory
if [ -d "resources/lang/es" ]; then
    LANG_DIR_EXISTS="true"
    LANG_HAS_TRANS=$(grep -r -i -E "correo electr|correo electronico|contrase|iniciar sesi" resources/lang/es/ 2>/dev/null | wc -l)
else
    LANG_DIR_EXISTS="false"
    LANG_HAS_TRANS=0
fi

# 5. Check if the default locale was configured
LOCALE_IN_ENV=$(grep -i "^APP_LOCALE=es" .env 2>/dev/null | wc -l)
LOCALE_IN_APP=$(grep -iE "'locale'\s*=>\s*'es'|\"locale\"\s*=>\s*\"es\"" config/app.php 2>/dev/null | wc -l)

if [ "$LOCALE_IN_ENV" -gt 0 ] || [ "$LOCALE_IN_APP" -gt 0 ]; then
    LOCALE_SET="true"
else
    LOCALE_SET="false"
fi

# 6. Check modification timestamps (Anti-Gaming Check)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
LANG_CREATED_DURING_TASK="false"

if [ "$LANG_DIR_EXISTS" = "true" ]; then
    LANG_MTIME=$(stat -c %Y resources/lang/es 2>/dev/null || echo "0")
    if [ "$LANG_MTIME" -gt "$TASK_START" ]; then
        LANG_CREATED_DURING_TASK="true"
    fi
fi

# Build the JSON output
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat << EOF > "$TEMP_JSON"
{
    "html_has_correo": $HTML_HAS_CORREO,
    "html_has_contra": $HTML_HAS_CONTRA,
    "html_has_iniciar": $HTML_HAS_INICIAR,
    "views_hardcoded": $VIEWS_HARDCODED,
    "lang_dir_exists": $LANG_DIR_EXISTS,
    "lang_has_trans": $LANG_HAS_TRANS,
    "locale_set": $LOCALE_SET,
    "lang_created_during_task": $LANG_CREATED_DURING_TASK,
    "task_start_time": $TASK_START
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="