#!/bin/bash
echo "=== Exporting build_dynamic_localization_system result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# Check if TiddlyWiki components exist
SYS_STR_EXISTS=$(tiddler_exists "SystemStrings")
LANG_SET_EXISTS=$(tiddler_exists "Language Settings")
DASHBOARD_EXISTS=$(tiddler_exists "Home Dashboard")

# Check type of SystemStrings
SYS_STR_TYPE=""
if [ "$SYS_STR_EXISTS" = "true" ]; then
    SYS_STR_TYPE=$(get_tiddler_field "SystemStrings" "type" | tr -d '\r')
fi

# Look for macro tiddler
MACRO_EXISTS="false"
MACRO_REF_SYS_STR="false"
MACRO_FILES=$(find "$TIDDLER_DIR" -maxdepth 1 -name "*.tid" ! -name '$__*' -exec grep -l "^tags:.*$:/tags/Macro" {} \; 2>/dev/null || echo "")

for f in $MACRO_FILES; do
    MACRO_EXISTS="true"
    if grep -q "SystemStrings" "$f"; then
        MACRO_REF_SYS_STR="true"
        break
    fi
done

# =================================================================
# DYNAMIC RENDERING VERIFICATION
# =================================================================
# To test dynamic rendering without interrupting the live server,
# we copy the wiki directory, inject the state variable programmatically,
# and use the Node.js CLI to render the dashboard to HTML.
# =================================================================

TEST_DIR="/tmp/test_wiki"
rm -rf "$TEST_DIR"
cp -r /home/ga/mywiki "$TEST_DIR"
chown -R ga:ga "$TEST_DIR"

EN_WELCOME="false"; EN_TICKET="false"; EN_KB="false"
ES_WELCOME="false"; ES_TICKET="false"; ES_KB="false"
FR_WELCOME="false"; FR_TICKET="false"; FR_KB="false"

# Helper function to render and parse output
test_language_render() {
    local lang=$1
    local output_file="rendered_${lang}.html"
    
    # Force the state tiddler to the desired language
    cat > "$TEST_DIR/tiddlers/\$__state_language.tid" << EOF
title: $:/state/language

$lang
EOF
    chown ga:ga "$TEST_DIR/tiddlers/\$__state_language.tid"

    # Render the dashboard HTML
    su - ga -c "cd $TEST_DIR && tiddlywiki . --render 'Home Dashboard' '$output_file' text/html" >/dev/null 2>&1
    
    local html=""
    if [ -f "$TEST_DIR/output/$output_file" ]; then
        html=$(cat "$TEST_DIR/output/$output_file")
    fi
    echo "$html"
}

if [ "$DASHBOARD_EXISTS" = "true" ]; then
    echo "Testing EN rendering..."
    HTML_EN=$(test_language_render "en")
    echo "$HTML_EN" | grep -q "Welcome to the IT Support Portal" && EN_WELCOME="true"
    echo "$HTML_EN" | grep -q "Submit a New Ticket" && EN_TICKET="true"
    echo "$HTML_EN" | grep -q "Browse Knowledge Base" && EN_KB="true"

    echo "Testing ES rendering..."
    HTML_ES=$(test_language_render "es")
    echo "$HTML_ES" | grep -q "Bienvenido al Portal de Soporte de TI" && ES_WELCOME="true"
    echo "$HTML_ES" | grep -q "Enviar un nuevo ticket" && ES_TICKET="true"
    echo "$HTML_ES" | grep -q "Explorar la base de conocimientos" && ES_KB="true"

    echo "Testing FR rendering..."
    HTML_FR=$(test_language_render "fr")
    echo "$HTML_FR" | grep -q "Bienvenue sur le portail d'assistance informatique" && FR_WELCOME="true"
    echo "$HTML_FR" | grep -q "Soumettre un nouveau ticket" && FR_TICKET="true"
    echo "$HTML_FR" | grep -q "Parcourir la base de connaissances" && FR_KB="true"
    
    # ANTI-GAMING CHECK: Check if EN render illegally contains Spanish text (hardcoded)
    EN_HAS_ES="false"
    echo "$HTML_EN" | grep -q "Bienvenido al Portal" && EN_HAS_ES="true"
fi

JSON_RESULT=$(cat << EOF
{
    "sys_str_exists": $SYS_STR_EXISTS,
    "sys_str_type": "$SYS_STR_TYPE",
    "lang_set_exists": $LANG_SET_EXISTS,
    "dashboard_exists": $DASHBOARD_EXISTS,
    "macro_exists": $MACRO_EXISTS,
    "macro_references_dict": $MACRO_REF_SYS_STR,
    "en_render": {
        "has_welcome": $EN_WELCOME,
        "has_ticket": $EN_TICKET,
        "has_kb": $EN_KB,
        "has_es_leak": $EN_HAS_ES
    },
    "es_render": {
        "has_welcome": $ES_WELCOME,
        "has_ticket": $ES_TICKET,
        "has_kb": $ES_KB
    },
    "fr_render": {
        "has_welcome": $FR_WELCOME,
        "has_ticket": $FR_TICKET,
        "has_kb": $FR_KB
    },
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "$JSON_RESULT" "/tmp/localization_result.json"

echo "Result saved to /tmp/localization_result.json"
cat /tmp/localization_result.json
echo "=== Export complete ==="