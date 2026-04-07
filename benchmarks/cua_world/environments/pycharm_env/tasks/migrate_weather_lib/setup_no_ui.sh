#!/bin/bash
# Setup script for migrate_weather_lib task
# Creates a Python 2 codebase that needs migration to Python 3

echo "=== Setting up migrate_weather_lib task ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/weather_analysis"

# Clean any previous state
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/migrate_weather_lib_result.json 2>/dev/null || true
rm -f /tmp/task_start_time 2>/dev/null || true

# Create project structure
su - ga -c "mkdir -p $PROJECT_DIR/weather $PROJECT_DIR/tests $PROJECT_DIR/data"

# 1. Create Data File (NOAA ISD style sample)
cat > "$PROJECT_DIR/data/noaa_isd_sample.csv" << 'CSVEOF'
station_id,datetime,temperature_c,dewpoint_c,wind_direction_deg,wind_speed_ms,precipitation_mm,pressure_hpa,visibility_m,sky_condition
725090,2023-01-01T00:00:00,5.6,2.1,180,3.5,0.0,1015.2,16000,CLR
725090,2023-01-01T01:00:00,5.1,2.2,185,3.1,0.0,1015.5,16000,CLR
725090,2023-01-01T02:00:00,4.8,2.3,190,2.8,0.0,1015.8,16000,FEW
725090,2023-01-01T03:00:00,4.2,2.5,180,2.5,0.0,1016.1,15000,SCT
725090,2023-01-01T04:00:00,3.9,2.8,175,2.1,0.0,1016.4,14000,BKN
725090,2023-01-01T05:00:00,3.5,3.0,170,1.8,0.2,1016.5,12000,OVC
725090,2023-01-01T06:00:00,3.2,3.1,160,1.5,1.5,1016.2,8000,OVC
725090,2023-01-01T07:00:00,3.0,3.0,150,1.2,2.8,1015.9,6000,RA
725090,2023-01-01T08:00:00,3.1,3.1,140,1.5,3.2,1015.5,5000,RA
725090,2023-01-01T09:00:00,3.8,3.2,180,2.5,1.0,1015.2,7000,RA
725090,2023-01-01T10:00:00,4.5,3.0,200,3.5,0.5,1015.5,10000,BKN
725090,2023-01-01T11:00:00,5.8,2.8,220,4.5,0.0,1015.9,15000,SCT
CSVEOF

# 2. Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'REQEOF'
pytest>=7.0
REQEOF

# 3. Create Source Code (WITH PYTHON 2 BUGS)

# weather/__init__.py
touch "$PROJECT_DIR/weather/__init__.py"

# weather/parser.py
# Issues: print statement, iteritems, has_key
cat > "$PROJECT_DIR/weather/parser.py" << 'PYEOF'
import csv
import os

class WeatherParser:
    def __init__(self, filepath):
        self.filepath = filepath
        self.data = []

    def load_data(self):
        if not os.path.exists(self.filepath):
            raise IOError("File not found")
        
        # Python 2 print statement (SyntaxError in Py3)
        print "Loading weather data from %s" % self.filepath
        
        with open(self.filepath, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                parsed_row = self._parse_row(row)
                if parsed_row:
                    self.data.append(parsed_row)
        
        print "Loaded %d records" % len(self.data)
        return self.data

    def _parse_row(self, row):
        # Python 2 dict.has_key (AttributeError in Py3)
        if not row.has_key('station_id'):
            return None
            
        try:
            return {
                'station_id': row['station_id'],
                'temp': float(row['temperature_c']),
                'precip': float(row['precipitation_mm']),
                'wind_spd': float(row['wind_speed_ms'])
            }
        except ValueError:
            return None

    def get_metadata(self):
        meta = {'source': 'NOAA', 'type': 'ISD', 'version': '1.0'}
        result = []
        # Python 2 iteritems (AttributeError in Py3)
        for k, v in meta.iteritems():
            result.append("%s: %s" % (k, v))
        return "\n".join(result)
PYEOF

# weather/statistics.py
# Issues: reduce (builtin in Py2, needs functools in Py3), filter/map return iterators
cat > "$PROJECT_DIR/weather/statistics.py" << 'PYEOF'
class ClimateStats:
    def __init__(self, data):
        self.data = data

    def get_mean_temperature(self):
        if not self.data:
            return 0.0
        # Python 2 map returns list, Py3 returns iterator
        # If treated as list (indexing), it fails
        temps = map(lambda x: x['temp'], self.data)
        return sum(temps) / len(temps)

    def get_total_precipitation(self):
        if not self.data:
            return 0.0
        # Python 2 reduce is builtin, Py3 moved to functools
        precips = [x['precip'] for x in self.data]
        return reduce(lambda a, b: a + b, precips, 0.0)

    def get_rainy_days_count(self):
        # Python 2 filter returns list, Py3 returns iterator
        # len() on iterator raises TypeError
        rainy = filter(lambda x: x['precip'] > 0.0, self.data)
        return len(rainy)
    
    def get_max_wind_speed(self):
        winds = [x['wind_spd'] for x in self.data]
        return max(winds)
PYEOF

# weather/report.py
# Issues: unicode type, except syntax, basestring
cat > "$PROJECT_DIR/weather/report.py" << 'PYEOF'
import datetime

class WeatherReport:
    def __init__(self, stats):
        self.stats = stats

    def generate_summary(self, title):
        # Python 2 basestring (NameError in Py3)
        if not isinstance(title, basestring):
            raise TypeError("Title must be a string")
            
        try:
            mean_temp = self.stats.get_mean_temperature()
            total_precip = self.stats.get_total_precipitation()
            
            report = "Report: %s\n" % title
            report += "Mean Temp: %.1f C\n" % mean_temp
            report += "Total Precip: %.1f mm\n" % total_precip
            
            # Python 2 unicode (NameError in Py3)
            return unicode(report)
            
        # Python 2 except syntax (SyntaxError in Py3)
        except Exception, e:
            return "Error generating report: %s" % str(e)
PYEOF

# weather/utils.py
# Issues: raw_input, xrange
cat > "$PROJECT_DIR/weather/utils.py" << 'PYEOF'
def get_user_confirmation(prompt):
    # Python 2 raw_input (NameError in Py3)
    response = raw_input(prompt + " [y/n]: ")
    return response.lower() == 'y'

def generate_sequence(n):
    # Python 2 xrange (NameError in Py3)
    return [i * 2 for i in xrange(n)]
PYEOF

# 4. Create Tests (These must pass after migration)
cat > "$PROJECT_DIR/tests/__init__.py" << 'PYEOF'
PYEOF

cat > "$PROJECT_DIR/tests/test_parser.py" << 'PYEOF'
import pytest
import os
from weather.parser import WeatherParser

@pytest.fixture
def sample_csv(tmp_path):
    f = tmp_path / "test.csv"
    f.write_text("station_id,temperature_c,precipitation_mm,wind_speed_ms\n123,20.5,0.0,5.2\n123,21.0,1.2,4.8")
    return str(f)

def test_load_data(sample_csv):
    parser = WeatherParser(sample_csv)
    data = parser.load_data()
    assert len(data) == 2
    assert data[0]['temp'] == 20.5

def test_metadata():
    parser = WeatherParser("dummy")
    meta = parser.get_metadata()
    assert "source: NOAA" in meta
    assert "type: ISD" in meta

def test_parse_row_missing_key():
    parser = WeatherParser("dummy")
    # Simulate a row missing keys
    row = {'temperature_c': '10', 'precipitation_mm': '0', 'wind_speed_ms': '1'}
    assert parser._parse_row(row) is None
PYEOF

cat > "$PROJECT_DIR/tests/test_statistics.py" << 'PYEOF'
import pytest
from weather.statistics import ClimateStats

@pytest.fixture
def stats():
    data = [
        {'temp': 10.0, 'precip': 0.0, 'wind_spd': 5.0},
        {'temp': 20.0, 'precip': 10.0, 'wind_spd': 15.0},
        {'temp': 15.0, 'precip': 5.0, 'wind_spd': 10.0}
    ]
    return ClimateStats(data)

def test_mean_temperature(stats):
    assert stats.get_mean_temperature() == 15.0

def test_total_precipitation(stats):
    assert stats.get_total_precipitation() == 15.0

def test_rainy_days_count(stats):
    assert stats.get_rainy_days_count() == 2

def test_max_wind_speed(stats):
    assert stats.get_max_wind_speed() == 15.0
    
def test_empty_data():
    s = ClimateStats([])
    assert s.get_mean_temperature() == 0.0
    assert s.get_total_precipitation() == 0.0
PYEOF

cat > "$PROJECT_DIR/tests/test_report.py" << 'PYEOF'
import pytest
from weather.report import WeatherReport
from weather.statistics import ClimateStats

class MockStats:
    def get_mean_temperature(self): return 25.0
    def get_total_precipitation(self): return 100.0

def test_generate_summary_valid():
    rep = WeatherReport(MockStats())
    summary = rep.generate_summary("Test Report")
    assert "Test Report" in summary
    assert "25.0 C" in summary
    assert isinstance(summary, str)

def test_generate_summary_invalid_title():
    rep = WeatherReport(MockStats())
    with pytest.raises(TypeError):
        rep.generate_summary(123)

def test_exception_handling():
    # Force an error in stats
    class BrokenStats:
        def get_mean_temperature(self): raise ValueError("Oops")
    
    rep = WeatherReport(BrokenStats())
    summary = rep.generate_summary("Bad")
    assert "Error generating report" in summary
    assert "Oops" in summary
PYEOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Record start time
date +%s > /tmp/task_start_time

# Setup PyCharm project

# Take initial screenshot

echo "=== Task setup complete ==="
