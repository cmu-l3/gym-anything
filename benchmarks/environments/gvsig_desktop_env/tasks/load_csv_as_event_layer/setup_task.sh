#!/bin/bash
echo "=== Setting up load_csv_as_event_layer task ==="

source /workspace/scripts/task_utils.sh

# 1. Create Data Directories
DATA_DIR="/home/ga/gvsig_data/earthquakes"
EXPORT_DIR="/home/ga/gvsig_data/exports"
mkdir -p "$DATA_DIR"
mkdir -p "$EXPORT_DIR"

# 2. Clean up previous run artifacts
rm -f "$EXPORT_DIR/earthquakes.shp"
rm -f "$EXPORT_DIR/earthquakes.shx"
rm -f "$EXPORT_DIR/earthquakes.dbf"
rm -f "$EXPORT_DIR/earthquakes.prj"
rm -f "$EXPORT_DIR/earthquakes.cpg"

# 3. Create the CSV file with real USGS data (Jan 2024, Mag 5.0+)
CSV_FILE="$DATA_DIR/usgs_earthquakes_2024jan.csv"
echo "Creating CSV file at $CSV_FILE..."

cat > "$CSV_FILE" << 'EOF'
time,latitude,longitude,depth,mag,magType,nst,gap,dmin,rms,net,id,updated,place,type,horizontalError,depthError,magError,magNst,status,locationSource,magSource
2024-01-01T07:10:09.673Z,37.5676,137.4043,10,5.7,mww,113,32,2.022,0.67,us,us6000m0xh,2024-01-26T21:28:46.040Z,"6 km NNW of Suzu, Japan",earthquake,5.4,1.8,0.063,24,reviewed,us,us
2024-01-01T07:12:01.373Z,37.3828,137.426,10,5.2,mww,61,64,2.203,0.78,us,us6000m0xi,2024-01-26T21:28:46.040Z,"22 km N of Anamizu, Japan",earthquake,7.7,1.8,0.091,11,reviewed,us,us
2024-01-01T07:13:58.214Z,37.3629,137.3364,10,5.4,mww,65,58,2.247,0.72,us,us6000m0xk,2024-01-26T21:28:46.040Z,"23 km N of Anamizu, Japan",earthquake,7.3,1.8,0.088,12,reviewed,us,us
2024-01-01T07:18:42.508Z,37.3005,137.3807,10,5.2,mb,77,39,2.285,0.78,us,us6000m0xl,2024-01-26T21:28:46.040Z,"17 km NNE of Anamizu, Japan",earthquake,6.2,1.9,0.052,118,reviewed,us,us
2024-01-01T07:23:09.135Z,37.0673,136.8587,10,5.1,mb,76,57,2.585,0.57,us,us6000m0xn,2024-01-26T21:28:46.040Z,"21 km ENE of Nanao, Japan",earthquake,4.7,1.9,0.039,215,reviewed,us,us
2024-01-01T07:46:17.375Z,37.2188,137.2458,10,5.2,mb,70,45,2.417,0.85,us,us6000m0xp,2024-01-26T21:28:46.040Z,"13 km NE of Anamizu, Japan",earthquake,5.4,1.8,0.038,225,reviewed,us,us
2024-01-01T07:54:05.472Z,37.2276,141.4907,37,5.5,mww,116,40,2.148,0.71,us,us6000m0xq,2024-01-26T21:28:46.040Z,"22 km E of Namie, Japan",earthquake,7.2,4.6,0.076,17,reviewed,us,us
2024-01-01T08:03:39.191Z,37.5517,137.5256,10,5.2,mb,96,52,2.023,0.7,us,us6000m0xs,2024-01-26T21:28:46.040Z,"12 km N of Suzu, Japan",earthquake,5,1.8,0.043,184,reviewed,us,us
2024-01-01T08:10:27.908Z,37.4913,137.2262,10,7.6,mww,176,28,2.152,0.69,us,us6000m0xl,2024-02-02T22:20:41.164Z,"Noto, Japan",earthquake,4.3,1.7,0.037,71,reviewed,us,us
2024-01-01T08:18:23.755Z,37.1264,136.6575,10,6.1,mww,91,33,2.571,0.61,us,us6000m0xu,2024-01-26T21:28:46.040Z,"8 km NNW of Nanao, Japan",earthquake,4.7,1.8,0.045,47,reviewed,us,us
2024-01-01T08:24:26.790Z,37.2346,136.958,10,5.6,mww,93,39,2.44,0.85,us,us6000m0xv,2024-01-26T21:28:46.040Z,"9 km NNE of Anamizu, Japan",earthquake,7.6,1.8,0.055,31,reviewed,us,us
2024-01-01T08:39:10.575Z,37.4225,137.5936,10,5.2,mb,66,63,2.14,0.66,us,us6000m0xw,2024-01-26T21:28:46.040Z,"23 km NE of Suzu, Japan",earthquake,5.8,1.9,0.045,159,reviewed,us,us
2024-01-01T08:52:12.757Z,37.5262,137.3756,10,5,mb,58,49,2.072,0.92,us,us6000m0xx,2024-01-26T21:28:46.040Z,"1 km NNW of Suzu, Japan",earthquake,6.2,1.8,0.063,80,reviewed,us,us
2024-01-01T09:44:54.020Z,37.0427,136.7589,10,5.1,mb,61,65,2.628,0.66,us,us6000m0xy,2024-01-26T21:28:46.040Z,"12 km ENE of Nanao, Japan",earthquake,4.8,1.9,0.057,99,reviewed,us,us
2024-01-01T15:21:49.034Z,34.0275,-118.2878333,9.58,2.63,ml,108,31,0.1198,0.24,ci,ci40632640,2024-01-25T01:35:43.766Z,"2 km SE of View Park-Windsor Hills, CA",earthquake,0.22,0.51,0.12,19,reviewed,ci,ci
2024-01-01T21:54:19.467Z,37.1648,136.7265,10,5,mb,51,77,2.525,0.76,us,us6000m108,2024-01-26T21:28:46.040Z,"12 km NNE of Nanao, Japan",earthquake,5.6,1.9,0.081,49,reviewed,us,us
2024-01-02T01:17:42.170Z,37.2023,136.9385,10,5.4,mww,77,50,2.476,0.6,us,us6000m10s,2024-01-26T21:28:47.040Z,"6 km N of Anamizu, Japan",earthquake,7.9,1.8,0.063,24,reviewed,us,us
2024-01-02T08:16:35.323Z,37.2847,136.8837,10,5.4,mww,69,45,2.428,0.69,us,us6000m11q,2024-01-26T21:28:47.040Z,"14 km N of Anamizu, Japan",earthquake,7.7,1.8,0.076,17,reviewed,us,us
2024-01-03T07:44:02.583Z,-19.9827,169.5937,64.29,5,mb,39,83,1.385,0.91,us,us6000m166,2024-01-18T05:50:52.040Z,"35 km ESE of Isangel, Vanuatu",earthquake,6.2,6.5,0.09,39,reviewed,us,us
2024-01-03T09:54:36.669Z,37.317,136.784,10,5.3,mww,86,37,2.428,0.75,us,us6000m16i,2024-01-26T21:28:47.040Z,"15 km NNW of Anamizu, Japan",earthquake,8.2,1.8,0.053,34,reviewed,us,us
2024-01-04T07:29:43.784Z,6.6784,127.1751,46.02,5.5,mww,62,56,1.446,0.58,us,us6000m1c5,2024-01-27T02:08:14.040Z,"97 km SE of Sarangani, Philippines",earthquake,7.8,6.8,0.075,17,reviewed,us,us
2024-01-04T23:59:16.483Z,-28.9221,-177.6713,34.01,5.6,mww,32,97,0.729,1.01,us,us6000m1em,2024-01-27T02:08:14.040Z,"Kermadec Islands, New Zealand",earthquake,9.4,3.7,0.091,12,reviewed,us,us
2024-01-05T00:55:04.285Z,28.273,56.9649,15.19,5.2,mww,99,23,4.409,0.85,us,us6000m1es,2024-01-27T02:08:14.040Z,"62 km N of Fāryāb, Iran",earthquake,7.3,4.8,0.076,17,reviewed,us,us
2024-01-05T13:40:41.259Z,37.2407,136.7584,10,5.1,mb,60,67,2.479,0.67,us,us6000m1gn,2024-01-27T02:08:14.040Z,"9 km NW of Anamizu, Japan",earthquake,6.2,1.9,0.074,59,reviewed,us,us
2024-01-06T15:08:00.675Z,37.2144,136.8286,10,5.2,mb,78,41,2.476,0.65,us,us6000m1j3,2024-01-27T02:08:15.040Z,"7 km NW of Anamizu, Japan",earthquake,5.1,1.9,0.045,160,reviewed,us,us
2024-01-07T14:48:38.283Z,-4.9392,152.9248,63.12,5.1,mb,39,52,1.678,0.63,us,us6000m1ma,2024-01-24T22:36:28.040Z,"103 km E of Kokopo, Papua New Guinea",earthquake,5.9,7.4,0.09,39,reviewed,us,us
2024-01-08T08:19:14.619Z,-2.9996,128.7905,10,5.2,mww,53,52,2.029,0.63,us,us6000m1pm,2024-01-27T19:57:42.040Z,"97 km NNE of Amahai, Indonesia",earthquake,8.2,1.8,0.078,16,reviewed,us,us
2024-01-08T09:48:01.373Z,27.3204,53.4754,10,5.2,mww,61,63,1.928,0.68,us,us6000m1pw,2024-01-27T19:57:42.040Z,"26 km SE of Mohr, Iran",earthquake,8.3,1.7,0.089,12,reviewed,us,us
2024-01-08T20:47:50.057Z,4.897,125.6865,133.72,6.7,mww,95,16,2.164,0.92,us,us6000m1r1,2024-02-03T16:04:47.348Z,"100 km SE of Sarangani, Philippines",earthquake,8.2,4.6,0.063,24,reviewed,us,us
2024-01-09T08:59:40.853Z,37.9351,137.8427,10,5.9,mww,113,31,2.09,0.68,us,us6000m1s6,2024-01-27T19:57:43.040Z,"49 km SW of Sado, Japan",earthquake,7.6,1.8,0.056,30,reviewed,us,us
2024-01-11T00:20:06.636Z,36.5298,70.612,192.6,6.4,mww,114,14,1.401,0.76,us,us6000m1x6,2024-01-31T20:21:49.040Z,"44 km SSW of Jurm, Afghanistan",earthquake,6.2,4.6,0.052,36,reviewed,us,us
2024-01-11T20:29:43.080Z,13.0645,-87.9712,71.01,5.2,mww,71,153,0.306,1.26,us,us6000m1z2,2024-01-31T20:21:49.040Z,"64 km S of La Unión, El Salvador",earthquake,4.7,6.4,0.091,12,reviewed,us,us
2024-01-11T21:48:07.491Z,-23.4475,-179.919,538.56,5.3,mww,61,60,3.585,0.73,us,us6000m1za,2024-01-31T20:21:49.040Z,"south of the Fiji Islands",earthquake,9.9,7.6,0.096,11,reviewed,us,us
2024-01-13T09:26:55.787Z,42.062,24.162,10,4.6,mb,125,48,0.852,0.95,us,us6000m231,2024-01-30T17:59:10.040Z,"6 km NNE of Pazardzhik, Bulgaria",earthquake,2.6,3.6,0.063,74,reviewed,us,us
2024-01-14T03:32:41.168Z,-19.1232,-175.0384,10,5.1,mb,30,89,3.167,0.72,us,us6000m24k,2024-01-31T20:21:49.040Z,"176 km NNE of Alo, Wallis and Futuna",earthquake,8.6,1.8,0.113,24,reviewed,us,us
2024-01-14T08:58:36.425Z,-19.0664,169.2136,220.07,5.1,mww,49,60,2.152,0.8,us,us6000m25b,2024-01-31T20:21:49.040Z,"55 km NNW of Isangel, Vanuatu",earthquake,8.4,6.4,0.071,19,reviewed,us,us
2024-01-14T20:17:28.188Z,63.9525,-22.4276,10,4.2,mb,93,66,0.228,0.8,us,us6000m26p,2024-01-30T16:53:14.040Z,"2 km SE of Grindavík, Iceland",earthquake,3.8,4.9,0.066,66,reviewed,us,us
2024-01-15T15:33:43.642Z,-4.6729,152.9234,39.69,5.2,mb,40,73,1.887,0.59,us,us6000m28n,2024-02-03T18:27:03.040Z,"117 km E of Kokopo, Papua New Guinea",earthquake,7.6,6.3,0.108,26,reviewed,us,us
2024-01-16T12:59:02.583Z,37.2435,136.9025,10,4.8,mb,43,103,2.441,0.61,us,us6000m2am,2024-02-03T18:27:03.040Z,"10 km N of Anamizu, Japan",earthquake,7.4,1.9,0.086,41,reviewed,us,us
2024-01-18T10:06:50.052Z,-18.892,-175.7629,228.05,5.1,mww,48,50,3.315,0.83,us,us6000m2g4,2024-02-03T18:27:04.040Z,"160 km NW of Alo, Wallis and Futuna",earthquake,9.4,7.8,0.078,16,reviewed,us,us
2024-01-18T23:11:56.242Z,-28.971,-176.8488,10,6.4,mww,91,37,1.385,0.7,us,us6000m2h4,2024-02-03T18:27:05.040Z,"Kermadec Islands, New Zealand",earthquake,6.2,1.7,0.066,22,reviewed,us,us
2024-01-19T06:17:15.548Z,4.868,-76.1362,118.82,5.6,mww,103,46,1.405,0.61,us,us6000m2hw,2024-02-03T18:27:05.040Z,"5 km SE of Cartago, Colombia",earthquake,7.7,4.3,0.063,24,reviewed,us,us
2024-01-19T23:48:58.267Z,18.8893,145.1764,228.66,6.1,mww,107,17,3.134,1,us,us6000m2kb,2024-02-03T18:27:05.040Z,"Pagan region, Northern Mariana Islands",earthquake,8.7,4.9,0.068,21,reviewed,us,us
2024-01-20T14:31:02.392Z,-7.2343,-71.499,617.9,6.6,mww,111,18,6.248,0.7,us,us6000m2m2,2024-02-03T18:27:06.040Z,"124 km NW of Tarauacá, Brazil",earthquake,7.6,5,0.059,28,reviewed,us,us
EOF

chown ga:ga "$CSV_FILE"
chmod 644 "$CSV_FILE"

# 4. Prepare gvSIG
# Use the countries_base project if available
PREBUILT_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
CLEAN_PROJECT="/workspace/data/projects/countries_base.gvsproj"

if [ -f "$CLEAN_PROJECT" ]; then
    cp "$CLEAN_PROJECT" "$PREBUILT_PROJECT"
    chown ga:ga "$PREBUILT_PROJECT"
fi

# Kill any existing instances
kill_gvsig

# Start gvSIG
echo "Launching gvSIG..."
if [ -f "$PREBUILT_PROJECT" ]; then
    launch_gvsig "$PREBUILT_PROJECT"
else
    launch_gvsig ""
fi

# 5. Record start time and initial state
date +%s > /tmp/task_start_time.txt
echo "Task started at $(cat /tmp/task_start_time.txt)"

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved."

echo "=== Task setup complete ==="