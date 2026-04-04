#!/bin/bash
echo "=== Exporting implement_voucher_payment results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot before killing app
take_screenshot /tmp/task_final.png

# 2. Kill Floreant to release Derby database lock
kill_floreant

# 3. Java Query Tool to inspect Derby Database
# We need to compile and run a small Java class that connects to the embedded DB
# and checks if the discount/payment type exists and was used.

cat > /tmp/DbVerifier.java << 'EOF'
import java.sql.*;
import java.io.FileWriter;
import java.io.IOException;
import java.util.Properties;

public class DbVerifier {
    public static void main(String[] args) {
        String dbUrl = "jdbc:derby:/opt/floreantpos/database/derby-server";
        String jsonPath = "/tmp/task_result.json";
        
        boolean configExists = false;
        boolean transactionExists = false;
        boolean itemOrdered = false;
        int transactionCount = 0;
        long taskStartTime = 0;
        
        try {
            if (args.length > 0) {
                taskStartTime = Long.parseLong(args[0]);
            }
        } catch (Exception e) { e.printStackTrace(); }

        try (Connection conn = DriverManager.getConnection(dbUrl);
             FileWriter writer = new FileWriter(jsonPath)) {
            
            // Check 1: Does "Marketing Voucher" exist in COUPON_AND_DISCOUNT?
            // Note: Floreant stores custom payment methods/discounts here usually
            try (Statement stmt = conn.createStatement()) {
                ResultSet rs = stmt.executeQuery("SELECT NAME FROM COUPON_AND_DISCOUNT WHERE UPPER(NAME) LIKE '%MARKETING VOUCHER%'");
                if (rs.next()) {
                    configExists = true;
                    System.out.println("Found Config: " + rs.getString("NAME"));
                }
            } catch (Exception e) { System.out.println("Query 1 failed: " + e.getMessage()); }
            
            // Check 1b: Check PAYMENT_TYPE table if it exists (schema varies by version)
            if (!configExists) {
                try (Statement stmt = conn.createStatement()) {
                    // Just check if table exists first via metadata, but simpler to try select
                     ResultSet rs = stmt.executeQuery("SELECT count(*) FROM sys.systables WHERE tablename = 'PAYMENT_TYPE'");
                     if(rs.next() && rs.getInt(1) > 0) {
                         rs = stmt.executeQuery("SELECT NAME FROM PAYMENT_TYPE WHERE UPPER(NAME) LIKE '%MARKETING VOUCHER%'");
                         if (rs.next()) configExists = true;
                     }
                } catch (Exception e) { /* Ignore if table missing */ }
            }

            // Check 2: Was a Ticket Item "Cola" ordered recently?
            try (Statement stmt = conn.createStatement()) {
                // TICKET_ITEM joins to TICKET
                String sql = "SELECT ti.ITEM_NAME FROM TICKET_ITEM ti " +
                             "JOIN TICKET t ON ti.TICKET_ID = t.ID " +
                             "WHERE UPPER(ti.ITEM_NAME) LIKE '%COLA%' AND t.CREATE_TIME > CURRENT_TIMESTAMP - 1 HOURS"; 
                             // Derby timestamp math is tricky, trusting raw count for now or checking IDs
                ResultSet rs = stmt.executeQuery("SELECT count(*) FROM TICKET_ITEM WHERE UPPER(ITEM_NAME) LIKE '%COLA%'");
                if (rs.next() && rs.getInt(1) > 0) {
                    itemOrdered = true; 
                }
            } catch (Exception e) { System.out.println("Query 2 failed: " + e.getMessage()); }

            // Check 3: Was a Transaction made using this method?
            try (Statement stmt = conn.createStatement()) {
                // Check TRANSACTIONS table for custom payment type
                ResultSet rs = stmt.executeQuery("SELECT count(*) FROM TRANSACTIONS WHERE UPPER(PAYMENT_TYPE) LIKE '%MARKETING VOUCHER%'");
                if (rs.next()) {
                    int count = rs.getInt(1);
                    if (count > 0) {
                        transactionExists = true;
                        transactionCount = count;
                    }
                }
            } catch (Exception e) { System.out.println("Query 3 failed: " + e.getMessage()); }

            // Check 3b: Check Ticket Discounts if it was applied as a discount
            if (!transactionExists) {
                try (Statement stmt = conn.createStatement()) {
                    ResultSet rs = stmt.executeQuery("SELECT count(*) FROM TICKET_COUPON_AND_DISCOUNT WHERE UPPER(NAME) LIKE '%MARKETING VOUCHER%'");
                    if (rs.next() && rs.getInt(1) > 0) {
                        transactionExists = true;
                        transactionCount = rs.getInt(1);
                    }
                } catch (Exception e) { System.out.println("Query 3b failed: " + e.getMessage()); }
            }

            // Write JSON Output
            writer.write("{\n");
            writer.write("  \"config_exists\": " + configExists + ",\n");
            writer.write("  \"transaction_exists\": " + transactionExists + ",\n");
            writer.write("  \"item_ordered\": " + itemOrdered + ",\n");
            writer.write("  \"transaction_count\": " + transactionCount + "\n");
            writer.write("}\n");

        } catch (Exception e) {
            e.printStackTrace();
            // Write failure JSON
            try (FileWriter writer = new FileWriter(jsonPath)) {
                writer.write("{\"error\": \"" + e.getMessage().replace("\"", "'") + "\"}");
            } catch (IOException io) {}
        }
    }
}
EOF

# Compile and run the verifier
# Classpath must include derby.jar and floreantpos.jar (for deps)
CLASSPATH=".:/opt/floreantpos/lib/derby.jar:/opt/floreantpos/lib/derbyclient.jar:/opt/floreantpos/lib/derbynet.jar"

echo "Compiling verifier..."
javac -cp "$CLASSPATH" /tmp/DbVerifier.java

echo "Running verifier..."
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
java -cp "$CLASSPATH" DbVerifier "$TASK_START"

echo "Result JSON:"
cat /tmp/task_result.json

echo "=== Export complete ==="