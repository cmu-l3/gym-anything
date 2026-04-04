#!/bin/bash
set -e
echo "=== Setting up Espresso UI Tests Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

PROJECT_DIR="/home/ga/AndroidStudioProjects/TipCalculatorApp"

# Clean up any previous attempt
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/app/src/main/java/com/example/tipcalculator"
mkdir -p "$PROJECT_DIR/app/src/main/res/layout"
mkdir -p "$PROJECT_DIR/app/src/main/res/values"
mkdir -p "$PROJECT_DIR/app/src/main/res/mipmap-hdpi"
mkdir -p "$PROJECT_DIR/gradle/wrapper"

echo "Creating project files..."

# 1. settings.gradle
cat > "$PROJECT_DIR/settings.gradle" << 'EOF'
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "TipCalculatorApp"
include ':app'
EOF

# 2. Root build.gradle
cat > "$PROJECT_DIR/build.gradle" << 'EOF'
plugins {
    id 'com.android.application' version '8.2.0' apply false
    id 'org.jetbrains.kotlin.android' version '1.9.22' apply false
}
EOF

# 3. App build.gradle - INTENTIONALLY MISSING ESPRESSO DEPENDENCIES
cat > "$PROJECT_DIR/app/build.gradle" << 'EOF'
plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
}

android {
    namespace 'com.example.tipcalculator'
    compileSdk 34

    defaultConfig {
        applicationId "com.example.tipcalculator"
        minSdk 24
        targetSdk 34
        versionCode 1
        versionName "1.0"
        
        // Agent must verify/ensure this is set, though we provide it to be nice
        testInstrumentationRunner "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            minifyEnabled false
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
        }
    }
    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = '17'
    }
}

dependencies {
    implementation 'androidx.core:core-ktx:1.12.0'
    implementation 'androidx.appcompat:appcompat:1.6.1'
    implementation 'com.google.android.material:material:1.11.0'
    implementation 'androidx.constraintlayout:constraintlayout:2.1.4'
    
    // Unit testing dependencies (provided)
    testImplementation 'junit:junit:4.13.2'
    
    // MISSING: androidTestImplementation dependencies for Espresso
}
EOF

# 4. Create empty proguard rules
touch "$PROJECT_DIR/app/proguard-rules.pro"

# 5. AndroidManifest.xml
cat > "$PROJECT_DIR/app/src/main/AndroidManifest.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application
        android:allowBackup="true"
        android:icon="@mipmap/ic_launcher"
        android:label="@string/app_name"
        android:supportsRtl="true"
        android:theme="@style/Theme.MaterialComponents.DayNight.DarkActionBar">
        <activity
            android:name=".MainActivity"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
EOF

# 6. Layout: activity_main.xml
cat > "$PROJECT_DIR/app/src/main/res/layout/activity_main.xml" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<ScrollView xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:app="http://schemas.android.com/apk/res-auto"
    xmlns:tools="http://schemas.android.com/tools"
    android:layout_width="match_parent"
    android:layout_height="match_parent">

    <androidx.constraintlayout.widget.ConstraintLayout
        android:layout_width="match_parent"
        android:layout_height="wrap_content"
        android:padding="16dp"
        tools:context=".MainActivity">

        <com.google.android.material.textfield.TextInputLayout
            android:id="@+id/cost_of_service_layout"
            android:layout_width="match_parent"
            android:layout_height="wrap_content"
            android:hint="@string/cost_of_service"
            app:layout_constraintTop_toTopOf="parent">

            <com.google.android.material.textfield.TextInputEditText
                android:id="@+id/cost_of_service"
                android:layout_width="match_parent"
                android:layout_height="wrap_content"
                android:inputType="numberDecimal" />
        </com.google.android.material.textfield.TextInputLayout>

        <TextView
            android:id="@+id/service_question"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="16dp"
            android:text="@string/how_was_the_service"
            app:layout_constraintStart_toStartOf="parent"
            app:layout_constraintTop_toBottomOf="@id/cost_of_service_layout" />

        <RadioGroup
            android:id="@+id/tip_options"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:orientation="vertical"
            app:layout_constraintStart_toStartOf="parent"
            app:layout_constraintTop_toBottomOf="@id/service_question">

            <RadioButton
                android:id="@+id/option_twenty_percent"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="Amazing (20%)" />

            <RadioButton
                android:id="@+id/option_eighteen_percent"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:text="Good (18%)" />

            <RadioButton
                android:id="@+id/option_fifteen_percent"
                android:layout_width="wrap_content"
                android:layout_height="wrap_content"
                android:checked="true"
                android:text="OK (15%)" />
        </RadioGroup>

        <com.google.android.material.switchmaterial.SwitchMaterial
            android:id="@+id/round_up_switch"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_marginTop="16dp"
            android:checked="true"
            android:text="@string/round_up_tip"
            app:layout_constraintEnd_toEndOf="parent"
            app:layout_constraintStart_toStartOf="parent"
            app:layout_constraintTop_toBottomOf="@id/tip_options" />

        <Button
            android:id="@+id/calculate_button"
            android:layout_width="0dp"
            android:layout_height="wrap_content"
            android:layout_marginTop="16dp"
            android:text="@string/calculate"
            app:layout_constraintEnd_toEndOf="parent"
            app:layout_constraintStart_toStartOf="parent"
            app:layout_constraintTop_toBottomOf="@id/round_up_switch" />

        <TextView
            android:id="@+id/tip_result"
            android:layout_width="wrap_content"
            android:layout_height="wrap_content"
            android:layout_marginTop="16dp"
            android:text="@string/tip_amount"
            android:textSize="20sp"
            app:layout_constraintEnd_toEndOf="parent"
            app:layout_constraintTop_toBottomOf="@id/calculate_button" />

    </androidx.constraintlayout.widget.ConstraintLayout>
</ScrollView>
EOF

# 7. strings.xml
cat > "$PROJECT_DIR/app/src/main/res/values/strings.xml" << 'EOF'
<resources>
    <string name="app_name">Tip Calculator</string>
    <string name="cost_of_service">Cost of Service</string>
    <string name="how_was_the_service">How was the service?</string>
    <string name="round_up_tip">Round up tip?</string>
    <string name="calculate">Calculate</string>
    <string name="tip_amount">Tip Amount</string>
    <string name="tip_amount_result">Tip Amount: %s</string>
</resources>
EOF

# 8. Create a placeholder icon
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' > "$PROJECT_DIR/app/src/main/res/mipmap-hdpi/ic_launcher.png"

# 9. MainActivity.kt
cat > "$PROJECT_DIR/app/src/main/java/com/example/tipcalculator/MainActivity.kt" << 'EOF'
package com.example.tipcalculator

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.google.android.material.switchmaterial.SwitchMaterial
import com.google.android.material.textfield.TextInputEditText
import android.widget.Button
import android.widget.RadioGroup
import android.widget.TextView
import java.text.NumberFormat
import kotlin.math.ceil

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        findViewById<Button>(R.id.calculate_button).setOnClickListener { calculateTip() }
    }

    private fun calculateTip() {
        val costEditText = findViewById<TextInputEditText>(R.id.cost_of_service)
        val stringInTextField = costEditText.text.toString()
        val cost = stringInTextField.toDoubleOrNull()
        if (cost == null || cost == 0.0) {
            displayTip(0.0)
            return
        }
        val tipOptions = findViewById<RadioGroup>(R.id.tip_options)
        val tipPercentage = when (tipOptions.checkedRadioButtonId) {
            R.id.option_twenty_percent -> 0.20
            R.id.option_eighteen_percent -> 0.18
            else -> 0.15
        }
        var tip = tipPercentage * cost
        val roundUpSwitch = findViewById<SwitchMaterial>(R.id.round_up_switch)
        if (roundUpSwitch.isChecked) {
            tip = ceil(tip)
        }
        displayTip(tip)
    }

    private fun displayTip(tip: Double) {
        val formattedTip = NumberFormat.getCurrencyInstance().format(tip)
        val tipResult = findViewById<TextView>(R.id.tip_result)
        tipResult.text = getString(R.string.tip_amount_result, formattedTip)
    }
}
EOF

# 10. Setup Gradle Wrapper
cat > "$PROJECT_DIR/gradle/wrapper/gradle-wrapper.properties" << 'EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.2-bin.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
EOF

# Copy wrapper jar if available, or download
WRAPPER_JAR="$PROJECT_DIR/gradle/wrapper/gradle-wrapper.jar"
if [ -f "/usr/share/java/gradle-wrapper.jar" ]; then
    cp "/usr/share/java/gradle-wrapper.jar" "$WRAPPER_JAR"
elif [ -f "/opt/android-studio/plugins/gradle/lib/gradle-wrapper.jar" ]; then
     cp "/opt/android-studio/plugins/gradle/lib/gradle-wrapper.jar" "$WRAPPER_JAR"
else
    # Fallback to download
    curl -sSL "https://raw.githubusercontent.com/gradle/gradle/v8.2.0/gradle/wrapper/gradle-wrapper.jar" -o "$WRAPPER_JAR" 2>/dev/null || true
fi

# Create gradlew script
cat > "$PROJECT_DIR/gradlew" << 'EOF'
#!/bin/sh
APP_HOME=$( cd "${0%/*}" && pwd -P ) || exit
CLASSPATH=$APP_HOME/gradle/wrapper/gradle-wrapper.jar
if [ ! -x "$APP_HOME/gradle/wrapper/gradle-wrapper.jar" ]; then
    echo "Error: wrapper jar not found"
    exit 1
fi
exec java "-Dorg.gradle.appname=gradlew" -classpath "$CLASSPATH" org.gradle.wrapper.GradleWrapperMain "$@"
EOF
chmod +x "$PROJECT_DIR/gradlew"

# 11. gradle.properties
cat > "$PROJECT_DIR/gradle.properties" << 'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
android.nonTransitiveRClass=true
EOF

# 12. local.properties
cat > "$PROJECT_DIR/local.properties" << 'EOF'
sdk.dir=/opt/android-sdk
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Pre-build logic: verify project compiles (ignoring tests)
echo "Verifying initial project state..."
cd "$PROJECT_DIR"
su - ga -c "export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; export ANDROID_SDK_ROOT=/opt/android-sdk; ./gradlew assembleDebug --no-daemon" > /tmp/prebuild.log 2>&1 || {
    echo "WARNING: Pre-build failed. Project might be invalid."
    tail -n 20 /tmp/prebuild.log
}

# Open project in Android Studio
setup_android_studio_project "$PROJECT_DIR" "TipCalculatorApp" 120

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="