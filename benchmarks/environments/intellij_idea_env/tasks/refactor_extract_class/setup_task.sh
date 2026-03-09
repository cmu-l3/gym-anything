#!/bin/bash
set -e
echo "=== Setting up refactor_extract_class task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/IdeaProjects/ecommerce-legacy"
mkdir -p "$PROJECT_DIR"

# 1. Generate the Maven Project Structure
echo "Generating project files..."

# pom.xml
cat > "$PROJECT_DIR/pom.xml" << 'POMEOF'
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.ecommerce</groupId>
    <artifactId>ecommerce-legacy</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
    </properties>

    <dependencies>
        <dependency>
            <groupId>junit</groupId>
            <artifactId>junit</artifactId>
            <version>4.13.2</version>
            <scope>test</scope>
        </dependency>
    </dependencies>
</project>
POMEOF

# Directory structure
mkdir -p "$PROJECT_DIR/src/main/java/com/ecommerce/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/ecommerce/service"
mkdir -p "$PROJECT_DIR/src/test/java/com/ecommerce/service"

# Address.java
cat > "$PROJECT_DIR/src/main/java/com/ecommerce/model/Address.java" << 'JAVAEOF'
package com.ecommerce.model;

public class Address {
    private String street;
    private String city;
    private String zipCode;
    private String country;

    public Address(String street, String city, String zipCode, String country) {
        this.street = street;
        this.city = city;
        this.zipCode = zipCode;
        this.country = country;
    }

    public String getStreet() { return street; }
    public String getCity() { return city; }
    public String getZipCode() { return zipCode; }
    public String getCountry() { return country; }
}
JAVAEOF

# Customer.java
cat > "$PROJECT_DIR/src/main/java/com/ecommerce/model/Customer.java" << 'JAVAEOF'
package com.ecommerce.model;

public class Customer {
    private String id;
    private String name;
    private Address address;

    public Customer(String id, String name, Address address) {
        this.id = id;
        this.name = name;
        this.address = address;
    }
    
    public String getName() { return name; }
    public Address getAddress() { return address; }
}
JAVAEOF

# CustomerService.java (The God Class to refactor)
cat > "$PROJECT_DIR/src/main/java/com/ecommerce/service/CustomerService.java" << 'JAVAEOF'
package com.ecommerce.service;

import com.ecommerce.model.Address;
import com.ecommerce.model.Customer;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

public class CustomerService {

    private final Map<String, Customer> customerDb = new HashMap<>();

    // --- Address Validation Logic (TO BE EXTRACTED) ---
    private static final List<String> VALID_COUNTRY_CODES = List.of("US", "CA", "UK", "FR", "DE");
    private final Map<String, Pattern> zipCodePatterns;

    public CustomerService() {
        this.zipCodePatterns = new HashMap<>();
        this.zipCodePatterns.put("US", Pattern.compile("^\\d{5}(-\\d{4})?$"));
        this.zipCodePatterns.put("CA", Pattern.compile("^[A-Za-z]\\d[A-Za-z] \\d[A-Za-z]\\d$"));
        this.zipCodePatterns.put("UK", Pattern.compile("^[A-Z]{1,2}\\d[A-Z\\d]? ?\\d[A-Z]{2}$"));
    }

    // --- Customer Management Logic (TO KEEP) ---
    public void addCustomer(Customer customer) {
        if (!validateAddress(customer.getAddress())) {
            throw new IllegalArgumentException("Invalid address for customer");
        }
        customerDb.put(customer.getName(), customer); // Simplified ID usage
        System.out.println("Customer added: " + customer.getName());
    }

    public Customer getCustomer(String name) {
        return customerDb.get(name);
    }

    // --- Methods to Extract ---

    public boolean validateAddress(Address address) {
        if (address == null) return false;
        if (!VALID_COUNTRY_CODES.contains(address.getCountry())) {
            return false;
        }
        Pattern pattern = zipCodePatterns.get(address.getCountry());
        if (pattern != null) {
            return pattern.matcher(address.getZipCode()).matches();
        }
        return true; // Default to true if no pattern defined
    }

    public String formatAddressLabel(Address address) {
        String region = resolveRegion(address.getCountry());
        return String.format("%s\n%s, %s\n%s (%s)",
                address.getStreet(),
                address.getCity(),
                address.getZipCode(),
                address.getCountry(),
                region);
    }

    private String resolveRegion(String country) {
        if ("US".equals(country) || "CA".equals(country)) return "North America";
        if ("UK".equals(country) || "FR".equals(country) || "DE".equals(country)) return "Europe";
        return "Unknown";
    }
}
JAVAEOF

# CustomerServiceTest.java
cat > "$PROJECT_DIR/src/test/java/com/ecommerce/service/CustomerServiceTest.java" << 'JAVAEOF'
package com.ecommerce.service;

import com.ecommerce.model.Address;
import com.ecommerce.model.Customer;
import org.junit.Test;
import static org.junit.Assert.*;

public class CustomerServiceTest {

    @Test
    public void testValidUSAddress() {
        CustomerService service = new CustomerService();
        Address addr = new Address("123 Main St", "New York", "10001", "US");
        assertTrue("Valid US address should pass", service.validateAddress(addr));
    }

    @Test
    public void testInvalidUSAddress() {
        CustomerService service = new CustomerService();
        Address addr = new Address("123 Main St", "New York", "ABCDE", "US");
        assertFalse("Invalid US zip should fail", service.validateAddress(addr));
    }

    @Test
    public void testFormatLabel() {
        CustomerService service = new CustomerService();
        Address addr = new Address("10 Downing St", "London", "SW1A 2AA", "UK");
        String label = service.formatAddressLabel(addr);
        assertTrue(label.contains("Europe"));
        assertTrue(label.contains("UK"));
    }

    @Test(expected = IllegalArgumentException.class)
    public void testAddCustomerWithBadAddress() {
        CustomerService service = new CustomerService();
        Address addr = new Address("Bad St", "City", "000", "US"); // Invalid zip
        service.addCustomer(new Customer("1", "John", addr));
    }
}
JAVAEOF

chown -R ga:ga "$PROJECT_DIR"

# 2. Record Initial State
date +%s > /tmp/task_start_time.txt
# Checksum of the God Class to detect changes later
md5sum "$PROJECT_DIR/src/main/java/com/ecommerce/service/CustomerService.java" > /tmp/initial_source_hash.txt

# 3. Setup IntelliJ
setup_intellij_project "$PROJECT_DIR" "ecommerce-legacy" 180

# 4. Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="