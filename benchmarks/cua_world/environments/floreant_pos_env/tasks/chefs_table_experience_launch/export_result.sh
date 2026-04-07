#!/bin/bash
echo "=== Exporting chefs_table_experience_launch results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot before killing app
take_screenshot /tmp/task_final.png

# 2. Stop Floreant POS to release the Derby database lock
echo "Stopping Floreant POS for database verification..."
kill_floreant
sleep 3

# 3. Find Derby JAR and database path
DERBY_CP=""
for jar in derby.jar derbytools.jar derbyshared.jar; do
    found=$(find /opt/floreantpos -name "$jar" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        DERBY_CP="${DERBY_CP}:${found}"
    fi
done
# Also add versioned jars
for found in $(find /opt/floreantpos/lib -name "derby*.jar" 2>/dev/null); do
    DERBY_CP="${DERBY_CP}:${found}"
done
DERBY_CP="${DERBY_CP#:}"
echo "Derby classpath: $DERBY_CP"

DB_PATH=$(find /opt/floreantpos/database -maxdepth 4 -name "service.properties" 2>/dev/null | head -1 | xargs dirname 2>/dev/null)
if [ -z "$DB_PATH" ]; then
    DB_PATH="/opt/floreantpos/database/derby-server/posdb"
fi
echo "Derby DB path: $DB_PATH"

if [ -z "$DERBY_CP" ]; then
    echo '{"error": "Derby JARs not found"}' > /tmp/task_result.json
    exit 0
fi

# 4. Create Java verification program
cat > /tmp/VerifyChefsTable.java << 'JAVAEOF'
import java.sql.*;

public class VerifyChefsTable {
    static String esc(String s) {
        if (s == null) return "null";
        return "\"" + s.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }
    public static void main(String[] args) {
        String dbPath = args[0];
        String url = "jdbc:derby:" + dbPath + ";create=false";
        StringBuilder j = new StringBuilder();
        j.append("{\n");

        try {
            Class.forName("org.apache.derby.jdbc.EmbeddedDriver");
            Connection c = DriverManager.getConnection(url);
            Statement s = c.createStatement();
            ResultSet r;

            // 1. CHEFS TABLE floor
            r = s.executeQuery("SELECT ID, NAME FROM SHOP_FLOOR WHERE UPPER(NAME) LIKE '%CHEF%TABLE%'");
            if (r.next()) {
                j.append("  \"floor_exists\": true,\n");
                j.append("  \"floor_id\": ").append(r.getInt("ID")).append(",\n");
                j.append("  \"floor_name\": ").append(esc(r.getString("NAME"))).append(",\n");
            } else {
                j.append("  \"floor_exists\": false,\n  \"floor_id\": -1,\n");
            }
            r.close();

            // 2. Tables on floor
            r = s.executeQuery("SELECT ST.TABLE_NUMBER, ST.CAPACITY, ST.FLOOR_ID, SF.NAME AS FLOOR_NAME " +
                "FROM SHOP_TABLE ST LEFT JOIN SHOP_FLOOR SF ON ST.FLOOR_ID = SF.ID " +
                "ORDER BY ST.FLOOR_ID, ST.TABLE_NUMBER");
            j.append("  \"tables\": [\n");
            boolean firstT = true;
            while (r.next()) {
                if (!firstT) j.append(",\n");
                j.append("    {\"table_number\": ").append(esc(r.getString("TABLE_NUMBER")));
                j.append(", \"capacity\": ").append(r.getInt("CAPACITY"));
                j.append(", \"floor_id\": ").append(r.getInt("FLOOR_ID"));
                j.append(", \"floor_name\": ").append(esc(r.getString("FLOOR_NAME"))).append("}");
                firstT = false;
            }
            j.append("\n  ],\n");
            r.close();

            // 3. PREMIUM TAX
            r = s.executeQuery("SELECT ID, NAME, RATE FROM TAX WHERE UPPER(NAME) LIKE '%PREMIUM%'");
            if (r.next()) {
                j.append("  \"tax_exists\": true,\n");
                j.append("  \"tax_id\": ").append(r.getInt("ID")).append(",\n");
                j.append("  \"tax_name\": ").append(esc(r.getString("NAME"))).append(",\n");
                j.append("  \"tax_rate\": ").append(r.getDouble("RATE")).append(",\n");
            } else {
                j.append("  \"tax_exists\": false,\n  \"tax_id\": -1,\n  \"tax_rate\": 0.0,\n");
            }
            r.close();

            // 4. CHEFS TABLE MENU category
            r = s.executeQuery("SELECT ID, NAME FROM MENU_CATEGORY WHERE UPPER(NAME) LIKE '%CHEF%TABLE%'");
            if (r.next()) {
                j.append("  \"category_exists\": true,\n");
                j.append("  \"category_name\": ").append(esc(r.getString("NAME"))).append(",\n");
            } else {
                j.append("  \"category_exists\": false,\n");
            }
            r.close();

            // 5. Wagyu Tasting menu item
            r = s.executeQuery("SELECT ID, NAME, PRICE, TAX_ID FROM MENU_ITEM WHERE UPPER(NAME) LIKE '%WAGYU%TASTING%'");
            if (r.next()) {
                j.append("  \"item_exists\": true,\n");
                j.append("  \"item_id\": ").append(r.getInt("ID")).append(",\n");
                j.append("  \"item_name\": ").append(esc(r.getString("NAME"))).append(",\n");
                j.append("  \"item_price\": ").append(r.getDouble("PRICE")).append(",\n");
                int taxId = r.getInt("TAX_ID");
                j.append("  \"item_tax_id\": ").append(r.wasNull() ? -1 : taxId).append(",\n");
            } else {
                j.append("  \"item_exists\": false,\n  \"item_price\": 0.0,\n  \"item_tax_id\": -1,\n");
            }
            r.close();

            // 6. Wagyu Beef A5 inventory item
            r = s.executeQuery("SELECT NAME, TOTAL_PACKAGES, TOTAL_RECEPIE_UNITS FROM INVENTORY_ITEM WHERE UPPER(NAME) LIKE '%WAGYU%BEEF%'");
            if (r.next()) {
                j.append("  \"inventory_exists\": true,\n");
                j.append("  \"inventory_name\": ").append(esc(r.getString("NAME"))).append(",\n");
                j.append("  \"stock\": ").append(r.getInt("TOTAL_PACKAGES")).append(",\n");
                j.append("  \"recipe_units\": ").append(r.getDouble("TOTAL_RECEPIE_UNITS")).append(",\n");
            } else {
                j.append("  \"inventory_exists\": false,\n  \"stock\": -1,\n");
            }
            r.close();

            // 7. Preparation modifier group
            r = s.executeQuery("SELECT ID, NAME FROM MENU_MODIFIER_GROUP WHERE UPPER(NAME) LIKE '%PREPARATION%'");
            int modGrpId = -1;
            if (r.next()) {
                modGrpId = r.getInt("ID");
                j.append("  \"mod_group_exists\": true,\n");
                j.append("  \"mod_group_id\": ").append(modGrpId).append(",\n");
            } else {
                j.append("  \"mod_group_exists\": false,\n  \"mod_group_id\": -1,\n");
            }
            r.close();

            // 8. Modifiers (Rare, Medium, Well Done)
            r = s.executeQuery("SELECT NAME, PRICE, GROUP_ID FROM MENU_MODIFIER WHERE UPPER(NAME) IN ('RARE', 'MEDIUM', 'WELL DONE')");
            j.append("  \"modifiers\": [\n");
            boolean firstM = true;
            while (r.next()) {
                if (!firstM) j.append(",\n");
                j.append("    {\"name\": ").append(esc(r.getString("NAME")));
                j.append(", \"price\": ").append(r.getDouble("PRICE"));
                j.append(", \"group_id\": ").append(r.getInt("GROUP_ID")).append("}");
                firstM = false;
            }
            j.append("\n  ],\n");
            r.close();

            // 9. Modifier-item link (MENUITEM_MODIFIERGROUP)
            // MENUITEM_MODIFIERGROUP_ID = menu item ID, MODIFIER_GROUP = modifier group ID
            r = s.executeQuery(
                "SELECT MIMG.MIN_QUANTITY, MIMG.MAX_QUANTITY, MIMG.MODIFIER_GROUP, MIMG.MENUITEM_MODIFIERGROUP_ID " +
                "FROM MENUITEM_MODIFIERGROUP MIMG " +
                "JOIN MENU_ITEM MI ON MIMG.MENUITEM_MODIFIERGROUP_ID = MI.ID " +
                "WHERE UPPER(MI.NAME) LIKE '%WAGYU%TASTING%'");
            if (r.next()) {
                j.append("  \"link_exists\": true,\n");
                j.append("  \"link_min\": ").append(r.getInt("MIN_QUANTITY")).append(",\n");
                j.append("  \"link_max\": ").append(r.getInt("MAX_QUANTITY")).append(",\n");
                j.append("  \"link_modifier_group_id\": ").append(r.getInt("MODIFIER_GROUP")).append(",\n");
            } else {
                j.append("  \"link_exists\": false,\n");
            }
            r.close();

            // 10. Recent settled tickets with Wagyu Tasting
            r = s.executeQuery(
                "SELECT T.ID, T.TOTAL_PRICE, T.TICKET_TYPE " +
                "FROM TICKET T JOIN TICKET_ITEM TI ON T.ID = TI.TICKET_ID " +
                "WHERE UPPER(TI.ITEM_NAME) LIKE '%WAGYU%TASTING%' AND T.SETTLED = 1 " +
                "ORDER BY T.ID DESC FETCH FIRST 1 ROWS ONLY");
            int ticketId = -1;
            if (r.next()) {
                ticketId = r.getInt("ID");
                j.append("  \"ticket_found\": true,\n");
                j.append("  \"ticket_id\": ").append(ticketId).append(",\n");
                j.append("  \"ticket_total\": ").append(r.getDouble("TOTAL_PRICE")).append(",\n");
                j.append("  \"ticket_type\": ").append(esc(r.getString("TICKET_TYPE"))).append(",\n");
            } else {
                j.append("  \"ticket_found\": false,\n  \"ticket_id\": -1,\n");
            }
            r.close();

            // 11. Payment type for ticket
            if (ticketId > 0) {
                r = s.executeQuery("SELECT PAYMENT_TYPE FROM TRANSACTIONS WHERE TICKET_ID = " + ticketId);
                if (r.next()) {
                    j.append("  \"payment_type\": ").append(esc(r.getString("PAYMENT_TYPE"))).append(",\n");
                } else {
                    j.append("  \"payment_type\": null,\n");
                }
                r.close();
            } else {
                j.append("  \"payment_type\": null,\n");
            }

            // 12. All taxes for cross-reference
            r = s.executeQuery("SELECT ID, NAME, RATE FROM TAX ORDER BY ID");
            j.append("  \"all_taxes\": [\n");
            boolean firstTx = true;
            while (r.next()) {
                if (!firstTx) j.append(",\n");
                j.append("    {\"id\": ").append(r.getInt("ID"));
                j.append(", \"name\": ").append(esc(r.getString("NAME")));
                j.append(", \"rate\": ").append(r.getDouble("RATE")).append("}");
                firstTx = false;
            }
            j.append("\n  ],\n");
            r.close();

            j.append("  \"export_complete\": true\n");
            c.close();

        } catch (Exception e) {
            j.append("  \"error\": ").append(esc(e.getMessage())).append(",\n");
            j.append("  \"export_complete\": false\n");
        }

        j.append("}\n");

        try {
            java.io.FileWriter fw = new java.io.FileWriter("/tmp/task_result.json");
            fw.write(j.toString());
            fw.close();
            System.out.println(j.toString());
        } catch (Exception e) {
            System.err.println("Failed to write result: " + e.getMessage());
        }
    }
}
JAVAEOF

# 5. Compile and run
echo "Compiling verification program..."
javac -cp "$DERBY_CP" /tmp/VerifyChefsTable.java -d /tmp/ 2>&1

if [ $? -eq 0 ]; then
    echo "Running database verification..."
    java -cp "/tmp:$DERBY_CP" VerifyChefsTable "$DB_PATH" 2>&1
else
    echo "Compilation failed, creating error result"
    echo '{"error": "Java compilation failed", "export_complete": false}' > /tmp/task_result.json
fi

# Ensure result file has correct permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

# Cleanup
rm -f /tmp/VerifyChefsTable.java /tmp/VerifyChefsTable.class 2>/dev/null || true

echo "=== Export complete ==="
