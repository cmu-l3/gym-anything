#!/bin/bash
set -e
echo "=== Setting up split_into_modules task ==="

source /workspace/scripts/task_utils.sh

PROJECT_NAME="petclinic-mono"
PROJECT_DIR="/home/ga/IdeaProjects/$PROJECT_NAME"

# Create project directory
mkdir -p "$PROJECT_DIR/src/main/java/com/petclinic/model"
mkdir -p "$PROJECT_DIR/src/main/java/com/petclinic/service"
mkdir -p "$PROJECT_DIR/src/main/java/com/petclinic/util"
mkdir -p "$PROJECT_DIR/src/main/java/com/petclinic/app"

# 1. Create POM
cat > "$PROJECT_DIR/pom.xml" <<EOF
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>com.petclinic</groupId>
    <artifactId>petclinic-mono</artifactId>
    <version>1.0-SNAPSHOT</version>

    <properties>
        <maven.compiler.source>17</maven.compiler.source>
        <maven.compiler.target>17</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>

    <dependencies>
        <!-- No external dependencies for this simplified version -->
    </dependencies>
</project>
EOF

# 2. Create Model classes
cat > "$PROJECT_DIR/src/main/java/com/petclinic/model/Pet.java" <<EOF
package com.petclinic.model;
import java.time.LocalDate;
public class Pet {
    private String name;
    private LocalDate birthDate;
    public String getName() { return name; }
    public void setName(String name) { this.name = name; }
}
EOF

cat > "$PROJECT_DIR/src/main/java/com/petclinic/model/Owner.java" <<EOF
package com.petclinic.model;
import java.util.List;
import java.util.ArrayList;
public class Owner {
    private String firstName;
    private String lastName;
    private List<Pet> pets = new ArrayList<>();
    public List<Pet> getPets() { return pets; }
}
EOF

# 3. Create Util classes
cat > "$PROJECT_DIR/src/main/java/com/petclinic/util/DateFormatter.java" <<EOF
package com.petclinic.util;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
public class DateFormatter {
    public static String format(LocalDate date) {
        return date.format(DateTimeFormatter.ISO_DATE);
    }
}
EOF

# 4. Create Service classes
cat > "$PROJECT_DIR/src/main/java/com/petclinic/service/ClinicService.java" <<EOF
package com.petclinic.service;
import com.petclinic.model.Owner;
import com.petclinic.model.Pet;
import java.util.List;
public interface ClinicService {
    void saveOwner(Owner owner);
    Pet findPetById(int id);
}
EOF

cat > "$PROJECT_DIR/src/main/java/com/petclinic/service/ClinicServiceImpl.java" <<EOF
package com.petclinic.service;
import com.petclinic.model.Owner;
import com.petclinic.model.Pet;
public class ClinicServiceImpl implements ClinicService {
    @Override
    public void saveOwner(Owner owner) {
        System.out.println("Saving owner " + owner);
    }
    @Override
    public Pet findPetById(int id) {
        return new Pet();
    }
}
EOF

# 5. Create App class
cat > "$PROJECT_DIR/src/main/java/com/petclinic/app/PetClinicApp.java" <<EOF
package com.petclinic.app;
import com.petclinic.service.ClinicService;
import com.petclinic.service.ClinicServiceImpl;
import com.petclinic.model.Owner;
import com.petclinic.util.DateFormatter;
import java.time.LocalDate;

public class PetClinicApp {
    public static void main(String[] args) {
        ClinicService service = new ClinicServiceImpl();
        Owner owner = new Owner();
        service.saveOwner(owner);
        System.out.println("Date: " + DateFormatter.format(LocalDate.now()));
        System.out.println("PetClinic Application Started");
    }
}
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Initialize Git to allow agent to use VCS if desired
su - ga -c "cd $PROJECT_DIR && git init && git add . && git commit -m 'Initial commit of monolith'"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Setup IntelliJ project
setup_intellij_project "$PROJECT_DIR" "petclinic-mono" 120

# Initial Screenshot
take_screenshot /tmp/task_start.png

echo "=== Setup complete ==="