#!/bin/bash
# Setup script for sakila_geospatial_customer_rebalancing task

echo "=== Setting up Sakila Geospatial Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure MySQL and Workbench are running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# 2. Reset Sakila Database to ensure clean state
# We set all customers to Store 1 initially so we can verify the agent actually moves them
echo "Resetting Sakila customer assignments..."
mysql -u root -p'GymAnything#2024' sakila -e "
    UPDATE customer SET store_id = 1;
    UPDATE address SET location = ST_GeomFromText('POINT(0 0)');
    DROP TABLE IF EXISTS geo_staging;
" 2>/dev/null

# 3. Generate City Coordinates CSV
# This file serves as the source of truth for the agent
echo "Generating geospatial data file..."
mkdir -p /home/ga/Documents

# Create a CSV with City, Country, Lat, Lon
# We include a mix of cities that should go to Store 1 (Americas/Europe) vs Store 2 (Asia/Oceania)
cat > /home/ga/Documents/city_coordinates.csv << EOF
city,country,latitude,longitude
Lethbridge,Canada,49.6935,-112.8418
Woodridge,Australia,-27.6333,153.1000
Sasebo,Japan,33.1667,129.7167
San Bernardino,United States,34.1083,-117.2897
Athenai,Greece,37.9838,23.7275
London,United Kingdom,51.5074,-0.1278
Sydney,Australia,-33.8688,151.2093
Hiroshima,Japan,34.3853,132.4553
Cianjur,Indonesia,-6.8225,107.1367
Curitiba,Brazil,-25.4284,-49.2733
Aurora,United States,39.7294,-104.8319
Bologna,Italy,44.4949,11.3426
Mannheim,Germany,49.4875,8.4660
Moscow,Russian Federation,55.7558,37.6173
Nantou,Taiwan,23.9167,120.6833
Abha,Saudi Arabia,18.2164,42.5053
Abu Dhabi,United Arab Emirates,24.4539,54.3773
Acua,Mexico,29.3232,-100.9522
Adana,Turkey,37.0000,35.3213
Addis Abeba,Ethiopia,9.0333,38.7000
Aden,Yemen,12.7794,45.0367
Adoni,India,15.6300,77.2800
Ahmadnagar,India,19.0800,74.7300
Akoranga,Cook Islands,-21.2333,-159.7667
Akron,United States,41.0814,-81.5190
Alipur,India,22.5333,88.3167
Alvorada,Brazil,-30.0000,-51.0833
Ambattur,India,13.1147,80.1558
Amersfoort,Netherlands,52.1550,5.3875
Amroha,India,28.9000,78.4700
Angra dos Reis,Brazil,-23.0067,-44.3181
Anpolis,Brazil,-16.3267,-48.9533
Antofagasta,Chile,-23.6500,-70.4000
Aparecida de Goinia,Brazil,-16.8231,-49.2450
Apeldoorn,Netherlands,52.2100,5.9700
Araatuba,Brazil,-21.2089,-50.4328
Arak,Iran,34.0917,49.6892
Arecibo,Puerto Rico,18.4725,-66.7158
Arlington,United States,32.7357,-97.1081
Ashgabat,Turkmenistan,37.9500,58.3833
Ashqelon,Israel,31.6693,34.5715
Asuncin,Paraguay,-25.2667,-57.6667
Atakpam,Togo,7.5500,1.0667
Atlixco,Mexico,18.9000,-98.4333
Augusta-Richmond County,United States,33.4700,-81.9750
Aurora,United States,39.7294,-104.8319
Avellaneda,Argentina,-34.6617,-58.3672
Bag,Brazil,-31.3283,-54.1069
Baicheng,China,45.6167,122.8167
Baiyin,China,36.5453,104.1683
Baku,Azerbaijan,40.4093,49.8671
Balaiha,Saudi Arabia,21.4858,39.1925
Balikesir,Turkey,39.6483,27.8826
Balurghat,India,25.2167,88.7667
Bamenda,Cameroon,5.9583,10.1575
Bandar Seri Begawan,Brunei,4.9403,114.9481
Bankura,India,23.2333,87.0667
Barcelona,Spain,41.3851,2.1734
Basel,Switzerland,47.5596,7.5886
Bat Yam,Israel,32.0167,34.7500
Batman,Turkey,37.8874,41.1322
Batna,Algeria,35.5560,6.1741
Battambang,Cambodia,13.1000,103.2000
Baybay,Philippines,10.6833,124.8000
Bayreuth,Germany,49.9456,11.5713
Bchar,Algeria,31.6167,-2.2167
Beira,Mozambique,-19.8436,34.8389
Belm,Brazil,-1.4558,-48.4903
Belize City,Belize,17.4995,-88.1976
Belle-Isle-en-Terre,France,48.5444,-3.3950
Bello,Colombia,6.3373,-75.5579
Benguela,Angola,-12.5763,13.4055
Beni-Mellal,Morocco,32.3373,-6.3498
Benin City,Nigeria,6.3350,5.6275
Bergamo,Italy,45.6983,9.6773
Berhampore,India,24.1000,88.2500
Bern,Switzerland,46.9480,7.4474
Bhavnagar,India,21.7600,72.1500
Bhilwara,India,25.3500,74.6333
Bhimavaram,India,16.5333,81.5333
Bhopal,India,23.2500,77.4167
Bhubaneswar,India,20.2700,85.8400
Bhusawal,India,21.0500,75.7667
Bijapur,India,16.8300,75.7100
Bilbays,Egypt,30.4167,31.5667
Binzhou,China,37.3667,118.0167
Birgunj,Nepal,27.0167,84.8667
Bislig,Philippines,8.2114,126.3175
Bismil,Turkey,37.8500,40.6667
Bjumbura,Burundi,-3.3822,29.3644
Blida,Algeria,36.4722,2.8333
Bloemfontein,South Africa,-29.1181,26.2231
Boa Vista,Brazil,2.8197,-60.6733
Bogra,Bangladesh,24.8500,89.3667
Boise,United States,43.6135,-116.2035
Bokaro,India,23.7833,85.9667
Bol,Chad,13.4586,14.7147
Bole,China,44.9000,82.0667
Bombay (Mumbai),India,19.0760,72.8777
Bradford,United Kingdom,53.7960,-1.7594
Braslia,Brazil,-15.7942,-47.8822
Bratislava,Slovakia,48.1486,17.1077
Brescia,Italy,45.5416,10.2118
Brest,France,48.3904,-4.4861
Brindisi,Italy,40.6327,17.9418
Brockton,United States,42.0834,-71.0184
Bucuresti,Romania,44.4323,26.1063
Buenaventura,Colombia,3.8801,-77.0312
Buenos Aires,Argentina,-34.6037,-58.3816
Bukavu,Congo, The Democratic Republic of the,-2.5000,28.8667
Cabuyao,Philippines,14.2500,121.1333
Callao,Peru,-12.0565,-77.1181
Cam Ranh,Vietnam,11.9214,109.1591
Cape Coral,United States,26.5629,-81.9495
Caracas,Venezuela,10.4806,-66.9036
Carmen,Mexico,18.6333,-91.8333
Cavite,Philippines,14.4833,120.9000
Cayenne,French Guiana,4.9333,-52.3333
Celaya,Mexico,20.5235,-100.8157
Changhwa,Taiwan,24.0833,120.5333
Changzhou,China,31.8122,119.9694
Chapra,India,25.7800,84.7300
Charlotte Amalie,Virgin Islands, U.S.,18.3425,-64.9328
Chattanooga,United States,35.0456,-85.3097
Chiayi,Taiwan,23.4801,120.4491
Chichn-Itz,Mexico,20.6833,-88.5667
Chiclayo,Peru,-6.7714,-79.8409
Chihuahua,Mexico,28.6330,-106.0691
Chimkent,Kazakstan,42.3000,69.6000
Chisinau,Moldova,47.0056,28.8575
Chittagong,Bangladesh,22.3569,91.7832
Chitungwiza,Zimbabwe,-18.0127,31.0756
Chone,Ecuador,-0.6833,-80.1000
Christchurch,New Zealand,-43.5320,172.6362
Ciomas,Indonesia,-6.6000,106.7833
Ciputat,Indonesia,-6.3000,106.7667
Citrus Heights,United States,38.7071,-121.2811
Clarksville,United States,36.5298,-87.3595
Coatzacoalcos,Mexico,18.1500,-94.4333
Coimbra,Portugal,40.2033,-8.4103
Colombo,Sri Lanka,6.9271,79.8612
Compton,United States,33.8958,-118.2201
Conakry,Guinea,9.5092,-13.7122
Coquimbo,Chile,-29.9533,-71.3436
Crdoba,Argentina,-31.4201,-64.1888
Cuauhtmoc,Mexico,28.4000,-106.8667
Cuernavaca,Mexico,18.9186,-99.2342
Cuiab,Brazil,-15.6014,-56.0976
Cuman,Venezuela,10.4535,-64.1824
Czestochowa,Poland,50.8172,19.1183
Daejeon,South Korea,36.3504,127.3845
Dagupan,Philippines,16.0433,120.3333
Dakar,Senegal,14.6928,-17.4467
Dallas,United States,32.7767,-96.7970
Daugavpils,Latvia,55.8833,26.5333
Davenport,United States,41.5236,-90.5776
Davao,Philippines,7.0731,125.6128
Dayton,United States,39.7589,-84.1916
Denizli,Turkey,37.7765,29.0864
Dhaka,Bangladesh,23.8103,90.4125
Dhanbad,India,23.7998,86.4305
Diyarbakir,Turkey,37.9144,40.2306
Djibouti,Djibouti,11.5721,43.1456
Dnu,Vietnam,16.0471,108.2067
Dodoma,Tanzania,-6.1630,35.7516
Dongying,China,37.4333,118.4917
Donostia-San Sebastin,Spain,43.3183,-1.9812
Doshisha,Japan,35.0262,135.7609
Dundee,United Kingdom,56.4620,-2.9707
Durgapur,India,23.4833,87.3167
Dzerzinsk,Russian Federation,56.2389,43.4631
East London,South Africa,-33.0153,27.9116
Ede,Netherlands,52.0500,5.6667
Edishuhur,Eritrea,15.3333,38.9333
Edirne,Turkey,41.6772,26.5557
Effon-Alaiye,Nigeria,7.7333,4.9167
El Alto,Bolivia,-16.5000,-68.1500
El Fashir,Sudan,13.6279,25.3560
El Monte,United States,34.0686,-118.0276
El Tigre,Venezuela,8.8875,-64.2454
Elista,Russian Federation,46.3078,44.2558
Ensenada,Mexico,31.8667,-116.6000
Erbil,Iraq,36.1911,44.0091
Escuintla,Guatemala,14.3050,-90.7850
Eskisehir,Turkey,39.7767,30.5206
Etawah,India,26.7700,79.0300
Ezeiza,Argentina,-34.8500,-58.5333
Faaa,French Polynesia,-17.5500,-149.6000
Faisalabad,Pakistan,31.4504,73.1350
Fatehpur,India,25.9300,80.8000
Fayetteville,United States,35.0527,-78.8784
Fez,Morocco,34.0181,-5.0078
Firozabad,India,27.1500,78.4000
Florencia,Colombia,1.6167,-75.6000
Fontana,United States,34.0922,-117.4350
Fortaleza,Brazil,-3.7327,-38.5430
Foz do Iguau,Brazil,-25.5478,-54.5881
Francistown,Botswana,-21.1661,27.5144
Fukuyama,Japan,34.4833,133.3667
Funafuti,Tuvalu,-8.5200,179.1970
Funchal,Portugal,32.6500,-16.9000
Fuyu,China,45.2000,124.8167
Fuzhou,China,26.0745,119.2965
Gainesville,United States,29.6516,-82.3248
Galati,Romania,45.4353,28.0080
Garden Grove,United States,33.7743,-117.9050
Garland,United States,32.9126,-96.6389
Gatineau,Canada,45.4765,-75.7013
Gaziantep,Turkey,37.0662,37.3833
Gijn,Spain,43.5357,-5.6615
Gingoog,Philippines,8.8283,125.1017
Githunguri,Kenya,-1.0500,36.7833
Glatube,France,43.2500,5.4000
Godhra,India,22.7800,73.6100
Goi,Japan,35.5167,140.0833
Goinia,Brazil,-16.6869,-49.2648
Goma,Congo, The Democratic Republic of the,-1.6585,29.2205
Grand Prairie,United States,32.7460,-96.9978
Graz,Austria,47.0707,15.4395
Greenboro,United States,36.0726,-79.7920
Grosswarasdorf,Austria,47.5381,16.5562
Guadalajara,Mexico,20.6597,-103.3496
Guaruj,Brazil,-23.9931,-46.2564
Guayaquil,Ecuador,-2.1710,-79.9224
Guigang,China,23.0950,109.6100
Gujrat,Pakistan,32.5739,74.0759
Gulbarga,India,17.3297,76.8343
Hadasht,Iran,36.5294,53.0333
Haiphong,Vietnam,20.8449,106.6881
Haldia,India,22.0333,88.0667
Halifax,Canada,44.6488,-63.5752
Halle/Saale,Germany,51.4828,11.9698
Hami,China,42.8167,93.5167
Hamilton,New Zealand,-37.7870,175.2793
Hanoi,Vietnam,21.0285,105.8542
Haoji,China,33.5667,112.1833
Haparanda,Sweden,65.8333,24.1333
Hebron,Israel,31.5333,35.1000
Hidalgo,Mexico,20.0911,-98.7624
Hino,Japan,35.6667,139.4000
Hiroshima,Japan,34.3853,132.4553
Hof,Germany,50.3167,11.9167
Holyoke,United States,42.2043,-72.6162
Homs,Syrian Arab Republic,34.7268,36.7234
Hong Kong,Hong Kong,22.3193,114.1694
Honiara,Solomon Islands,-9.4457,159.9729
Hsichu,Taiwan,24.8039,120.9647
Huaian,China,33.5000,119.1333
Hubli-Dharwad,India,15.3647,75.1240
Huidong,China,22.9833,114.7167
Huntsville,United States,34.7304,-86.5861
Ibirit,Brazil,-20.0219,-44.0583
Idfu,Egypt,24.9667,32.8667
Ife,Nigeria,7.4667,4.5667
Ikerre,Nigeria,7.5000,5.2167
Iligan,Philippines,8.2280,124.2453
Ilorin,Nigeria,8.5000,4.5500
Imperatriz,Brazil,-5.5264,-47.4764
Inegl,Turkey,40.0767,29.5133
Ipoh,Malaysia,4.5975,101.0901
Isesaki,Japan,36.3167,139.2000
Ivanovo,Russian Federation,57.0000,40.9667
Iwaki,Japan,37.0500,140.8833
Izumisano,Japan,34.4167,135.3000
Jabalpur,India,23.1667,79.9333
Jaipur,India,26.9124,75.7873
Jakarta,Indonesia,-6.2088,106.8456
Jalib al-Shuyukh,Kuwait,29.2667,47.9333
Jamalpur,Bangladesh,24.9167,89.9500
Jaroslavl,Russian Federation,57.6299,39.8737
Jastrzebie-Zdrj,Poland,49.9500,18.6000
Jeddah,Saudi Arabia,21.5433,39.1728
Jeonju,South Korea,35.8242,127.1480
Jhang Sadar,Pakistan,31.2698,72.3169
Jiaozuo,China,35.2167,113.2500
Jidhafs,Bahrain,26.2167,50.5500
Jinchang,China,38.5167,102.1833
Jining,China,35.4000,116.5833
Jinjiang,China,24.8167,118.5667
Jinzhou,China,41.1167,121.1167
Jodhpur,India,26.2389,73.0243
Johannesburg,South Africa,-26.2041,28.0473
Jokohama [Yokohama],Japan,35.4437,139.6380
Joliet,United States,41.5250,-88.0817
Juazeiro do Norte,Brazil,-7.2022,-39.3139
Juiz de Fora,Brazil,-21.7642,-43.3503
Juliaca,Peru,-15.5000,-70.1333
Kabul,Afghanistan,34.5553,69.2075
Kaduna,Nigeria,10.5105,7.4165
Kagoshima,Japan,31.5833,130.5500
Kahramanmaras,Turkey,37.5858,36.9371
Kaiyuan,China,42.5333,124.0333
Kaliningrad,Russian Federation,54.7104,20.4522
Kalisz,Poland,51.7611,18.0911
Kamakura,Japan,35.3167,139.5500
Kamaria,India,23.8333,80.3833
Kambalda,Australia,-31.2000,121.6667
Kamyshin,Russian Federation,50.0833,45.4167
Kanazawa,Japan,36.6000,136.6167
Kanchrapara,India,22.9500,88.4333
Kansas City,United States,39.0997,-94.5786
Kaohsiung,Taiwan,22.6163,120.3133
Karak,Jordan,31.1833,35.7000
Karnal,India,29.6800,76.9800
Katakwi,Uganda,1.9000,34.0000
Kathmandu,Nepal,27.7172,85.3240
Katihar,India,25.5333,87.5667
Kavali,India,14.9200,80.0000
Kawasaki,Japan,35.5167,139.7000
Kermanshah,Iran,34.3142,47.0650
Khabarovsk,Russian Federation,48.4802,135.0719
Khammam,India,17.2500,80.1500
Khartoum,Sudan,15.5007,32.5599
Khulna,Bangladesh,22.8456,89.5403
Kigoma,Tanzania,-4.8833,29.6333
Kimberley,South Africa,-28.7282,24.7499
Kingstown,Saint Vincent and the Grenadines,13.1500,-61.2333
Kishiwada,Japan,34.4667,135.3667
Kisumu,Kenya,-0.1000,34.7500
Kitwe,Zambia,-12.8167,28.2000
Kluang,Malaysia,2.0300,103.3200
Kolpino,Russian Federation,59.7500,30.6000
Komatsu,Japan,36.4000,136.4500
Konotop,Ukraine,51.2167,33.2000
Korla,China,41.7250,86.1750
Korolev,Russian Federation,55.9167,37.8167
Kowloon and New Kowloon,Hong Kong,22.3236,114.1688
Kragujevac,Yugoslavia,44.0167,20.9167
Krakw,Poland,50.0647,19.9450
Krasnojarsk,Russian Federation,56.0153,92.8932
Kuala Lumpur,Malaysia,3.1390,101.6869
Kumagaya,Japan,36.1500,139.3833
Kumbakonam,India,10.9600,79.3800
Kurashiki,Japan,34.5833,133.7667
Kurnool,India,15.8300,78.0500
Kursk,Russian Federation,51.7304,36.1926
Kurume,Japan,33.3167,130.5167
Kuwait City,Kuwait,29.3759,47.9774
La Paz,Bolivia,-16.4897,-68.1193
La Plata,Argentina,-34.9205,-57.9542
La Romana,Dominican Republic,18.4273,-68.9728
Lajes,Brazil,-27.8161,-50.3261
Lancaster,United States,34.6981,-118.1366
Lansing,United States,42.7325,-84.5555
Laredo,United States,27.5036,-99.5076
Lausanne,Switzerland,46.5197,6.6323
Le Mans,France,48.0061,0.1996
Lengshuijiang,China,27.6881,111.4294
Leshan,China,29.5667,103.7667
Lethbridge,Canada,49.6935,-112.8418
Libreville,Gabon,0.4162,9.4673
Lichuan,China,30.3000,108.8500
Liepaja,Latvia,56.5167,21.0167
Lilongwe,Malawi,-13.9833,33.7833
Lima,Peru,-12.0464,-77.0428
Lincoln,United States,40.8136,-96.7026
Linz,Austria,48.3069,14.2858
Lipetsk,Russian Federation,52.6031,39.5708
Livorno,Italy,43.5485,10.3106
Ljubljana,Slovenia,46.0569,14.5058
Lobito,Angola,-12.3500,13.5500
Lodz,Poland,51.7592,19.4560
London,United Kingdom,51.5074,-0.1278
London,Canada,42.9849,-81.2453
Lubumbashi,Congo, The Democratic Republic of the,-11.6667,27.4833
Lublin,Poland,51.2465,22.5684
Lungchiu,Taiwan,22.5500,120.4333
Luzinia,Brazil,-16.2525,-47.9503
Madiun,Indonesia,-7.6292,111.5175
Madrid,Spain,40.4168,-3.7038
Mahajanga,Madagascar,-15.7167,46.3167
Mainz,Germany,49.9929,8.2473
Malang,Indonesia,-7.9839,112.6214
Malm,Sweden,55.6047,13.0038
Manchester,United States,42.9956,-71.4548
Mandaluyong,Philippines,14.5792,121.0367
Mandi Bahauddin,Pakistan,32.5833,73.4833
Mannheim,Germany,49.4875,8.4660
Maracabo,Venezuela,10.6549,-71.6309
Maracana,Brazil,-3.8667,-38.6167
Maradi,Niger,13.4833,7.1000
Marikina,Philippines,14.6333,121.0983
Maring,Brazil,-23.4210,-51.9331
Masqat,Oman,23.6100,58.5400
Matamoros,Mexico,25.8833,-97.5000
Matsue,Japan,35.4667,133.0500
Mazatln,Mexico,23.2427,-106.4062
Mbandaka,Congo, The Democratic Republic of the,0.0487,18.2603
Meixian,China,24.2885,116.1219
Memphis,United States,35.1495,-90.0490
Merida,Mexico,20.9674,-89.5926
Merida,Venezuela,8.5983,-71.1450
Mexicali,Mexico,32.6278,-115.4545
Miraj,India,16.8333,74.6333
Mithi,Pakistan,24.7333,69.8000
Miyakonojo,Japan,31.7333,131.0667
Mogou,China,22.3000,111.0000
Mokpo,South Korea,34.8118,126.3922
Molodetšno,Belarus,54.3167,26.8500
Monclova,Mexico,26.9000,-101.4167
Moniwa,Japan,24.8333,121.7500
Monterrey,Mexico,25.6866,-100.3161
Morelia,Mexico,19.7059,-101.1949
Morn,Argentina,-34.6500,-58.6167
Moscow,Russian Federation,55.7558,37.6173
Mosul,Iraq,36.3400,43.1300
Multan,Pakistan,30.1575,71.5249
Munger,India,25.3833,86.4667
Mwanza,Tanzania,-2.5167,32.9000
Myingyan,Myanmar,21.4667,95.3833
Mysore,India,12.2958,76.6394
Naala-Porto,Mozambique,-14.4833,40.6667
Nabereznyje Tšelny,Russian Federation,55.7167,52.4167
Nador,Morocco,35.1667,-2.9333
Nagaon,India,26.3500,92.6833
Nagareyama,Japan,35.8500,139.9000
Nagasaki,Japan,32.7500,129.8667
Nagoya,Japan,35.1815,136.9066
Nairobi,Kenya,-1.2921,36.8219
Najafabad,Iran,32.6333,51.3667
Nakhon Sawan,Thailand,15.6987,100.1162
Nam Dinh,Vietnam,20.4167,106.1667
Namibe,Angola,-15.1961,12.1522
Nanchong,China,30.8000,106.1333
Nanded,India,19.1500,77.3000
Nanking,China,32.0603,118.7969
Nantou,Taiwan,23.9167,120.6833
Naples,Italy,40.8518,14.2681
Narayanganj,Bangladesh,23.6333,90.5000
Nashville,United States,36.1627,-86.7816
Nassau,Bahamas,25.0343,-77.3963
Natitingou,Benin,10.3042,1.3796
Ndjamena,Chad,12.1348,15.0557
Newcastle,South Africa,-27.7580,29.9318
Nezahualcyotl,Mexico,19.4007,-99.0151
Nha Trang,Vietnam,12.2388,109.1967
Nice,France,43.7102,7.2620
Niteri,Brazil,-22.8859,-43.1153
Nizamabad,India,18.6700,78.1000
Nogales,Mexico,31.3086,-110.9422
North Shoalhaven,Australia,-34.8667,150.6000
Nouma,New Caledonia,-22.2711,166.4416
Novosibirsk,Russian Federation,55.0084,82.9357
Nukualofa,Tonga,-21.1393,-175.2049
Nuernberg,Germany,49.4521,11.0767
Oaxaca,Mexico,17.0732,-96.7266
Odevce,Yugoslavia,42.5000,21.5833
Odessa,Ukraine,46.4825,30.7233
Ogbomosho,Nigeria,8.1333,4.2500
Okayama,Japan,34.6500,133.9167
Okinawa,Japan,26.3353,127.8014
Oklahoma City,United States,35.4676,-97.5164
Olomouc,Czech Republic,49.5938,17.2509
Omiya,Japan,35.9000,139.6333
Omos,Mexico,29.6833,-110.1667
Omst,Russian Federation,54.9924,73.3686
Ondo,Nigeria,7.1000,4.8333
Onomichi,Japan,34.4000,133.2000
Orizaba,Mexico,18.8500,-97.1000
Orsk,Russian Federation,51.2049,58.5668
Osaka,Japan,34.6937,135.5022
Oschoorn,Netherlands,52.5833,4.8500
Oshawa,Canada,43.8971,-78.8658
Oslo,Norway,59.9139,10.7522
Osmaniye,Turkey,37.0742,36.2467
Ostrava,Czech Republic,49.8209,18.2625
Otan Ayegbaju,Nigeria,7.9500,4.7167
Otsu,Japan,35.0167,135.8500
Oulu,Finland,65.0121,25.4651
Owerri,Nigeria,5.4833,7.0333
Oyama,Japan,36.3000,139.8000
Ozorkw,Poland,51.9667,19.2833
Paarl,South Africa,-33.7225,18.9675
Pachuca de Soto,Mexico,20.1000,-98.7500
Padaid,Indonesia,-1.2000,136.5000
Padang,Indonesia,-0.9492,100.3543
Palghat,India,10.7800,76.6500
Palu,Indonesia,-0.9000,119.8667
Panchiao,Taiwan,25.0143,121.4672
Pangkal Pinang,Indonesia,-2.1333,106.1333
Panvel,India,18.9800,73.1000
Parbhani,India,19.2700,76.7800
Pathankot,India,32.2667,75.6500
Patiala,India,30.3400,76.3800
Patras,Greece,38.2466,21.7346
Pavlodar,Kazakstan,52.3000,76.9500
Pemba,Mozambique,-12.9732,40.5178
Peoria,United States,40.6936,-89.5890
Pereira,Colombia,4.8133,-75.6961
Phnom Penh,Cambodia,11.5564,104.9282
Phoenix,United States,33.4484,-112.0740
Pilibhit,India,28.6300,79.8000
Pingxiang,China,27.6333,113.8500
Piraeus,Greece,37.9429,23.6470
Pjatigorsk,Russian Federation,44.0500,43.0667
Plock,Poland,52.5461,19.7064
Poos de Caldas,Brazil,-21.7867,-46.5667
Pontianak,Indonesia,-0.0206,109.3414
Port-au-Prince,Haiti,18.5392,-72.3350
Porto Alegre,Brazil,-30.0346,-51.2177
Portooviejo,Ecuador,-1.0544,-80.4544
Potchefstroom,South Africa,-26.7167,27.1000
Provo,United States,40.2338,-111.6585
Pudahuel,Chile,-33.4417,-70.7667
Puebla,Mexico,19.0414,-98.2063
Puerto Cabello,Venezuela,10.4667,-68.0167
Pune,India,18.5204,73.8567
Purnea,India,25.7800,87.4700
Purwakarta,Indonesia,-6.5500,107.4500
Pyongyang,North Korea,39.0392,125.7625
Qalyub,Egypt,30.1778,31.2056
Qina,Egypt,26.1667,32.7167
Qingdao,China,36.0671,120.3826
Qinhuangdao,China,39.9333,119.5833
Qom,Iran,34.6401,50.8764
Queretaro,Mexico,20.5888,-100.3899
Quezon City,Philippines,14.6760,121.0437
Quilmes,Argentina,-34.7290,-58.2637
Raipur,India,21.2514,81.6296
Rajkot,India,22.3039,70.8022
Rampur,India,28.8000,79.0300
Rancagua,Chile,-34.1701,-70.7444
Ranchi,India,23.3600,85.3300
Rasht,Iran,37.2808,49.5831
Ratlam,India,23.3333,75.0667
Rawalpindi,Pakistan,33.5973,73.0479
Reading,United Kingdom,51.4543,-0.9781
Recife,Brazil,-8.0578,-34.8829
Reggio di Calabria,Italy,38.1144,15.6506
Reims,France,49.2583,4.0317
Reynosa,Mexico,26.0924,-98.2778
Richmond Hill,Canada,43.8828,-79.4403
Riga,Latvia,56.9496,24.1052
Rio Claro,Brazil,-22.4117,-47.5614
Rio Cuarto,Argentina,-33.1232,-64.3493
Rio de Janeiro,Brazil,-22.9068,-43.1729
Riyadh,Saudi Arabia,24.7136,46.6753
Roanoke,United States,37.2710,-79.9414
Robat Karim,Iran,35.4846,51.0829
Rockford,United States,42.2711,-89.0940
Rombas,France,49.2500,6.1000
Rosario,Argentina,-32.9468,-60.6393
Rosh Haayin,Israel,32.0950,34.9567
Rostov-na-Donu,Russian Federation,47.2357,39.7015
Ruse,Bulgaria,43.8356,25.9657
Rustenburg,South Africa,-25.6685,27.2424
Ryazan,Russian Federation,54.6095,39.7126
Saarbrcken,Germany,49.2333,6.9999
Saint-Denis,Runion,-20.8789,55.4481
Saint Louis,United States,38.6270,-90.1994
Saint-Pierre,Runion,-21.3406,55.4786
Sal,Morocco,34.0333,-6.8167
Salala,Oman,17.0150,54.0924
Salamanca,Spain,40.9701,-5.6635
Salinas,United States,36.6777,-121.6555
Salzburg,Austria,47.8095,13.0550
Sambhal,India,28.5800,78.5500
San Antonio,United States,29.4241,-98.4936
San Bernardino,United States,34.1083,-117.2897
San Felipe de Puerto Plata,Dominican Republic,19.7934,-70.6884
San Felipe del Progreso,Mexico,19.7167,-99.9500
San Juan Bautista Tuxtepec,Mexico,18.0833,-96.1167
San Juan,Puerto Rico,18.4663,-66.1057
San Lorenzo,Paraguay,-25.3333,-57.5333
San Miguel de Tucumn,Argentina,-26.8241,-65.2226
Sanaa,Yemen,15.3694,44.1910
Santa Brbara dOeste,Brazil,-22.7558,-47.4147
Santa Fe,Argentina,-31.6333,-60.7000
Santiago de Chile,Chile,-33.4489,-70.6693
Santiago de Compostela,Spain,42.8782,-8.5448
Santiago de los Caballeros,Dominican Republic,19.4517,-70.6970
Santo Andr,Brazil,-23.6631,-46.5383
Sanya,China,18.2528,109.5119
Sao Bernardo do Campo,Brazil,-23.6944,-46.5654
Sao Leopoldo,Brazil,-29.7547,-51.1558
Sasebo,Japan,33.1667,129.7167
Satna,India,24.5800,80.8300
Sawhaj,Egypt,26.5500,31.7000
Serpukhov,Russian Federation,54.9167,37.4167
Sfax,Tunisia,34.7333,10.7667
Shah Alam,Malaysia,3.0738,101.5183
Shaoxing,China,30.0000,120.5833
Sharda,Pakistan,34.8000,74.1500
Sharja,United Arab Emirates,25.3573,55.4033
Sherbrooke,Canada,45.4001,-71.8991
Shikarpur,India,28.2500,78.0167
Shimoga,India,13.9300,75.5700
Shimonoseki,Japan,33.9500,130.9333
Shivapuri,India,25.4300,77.6500
Shubra al-Khayma,Egypt,30.1286,31.2422
Siegen,Germany,50.8755,8.0267
Siliguri,India,26.7100,88.4300
Simferopol,Ukraine,44.9572,34.1108
Sinas,Philippines,14.6333,121.5000
Singapore,Singapore,1.3521,103.8198
Siping,China,43.1667,124.3333
Sivas,Turkey,39.7477,37.0179
Skikda,Algeria,36.8667,6.9000
Smolensk,Russian Federation,54.7818,32.0401
So Leopoldo,Brazil,-29.7547,-51.1558
Sobral,Brazil,-3.6858,-40.3497
Sogamoso,Colombia,5.7161,-72.9303
Sokoto,Nigeria,13.0667,5.2333
Songkhla,Thailand,7.1988,100.5951
Sorocaba,Brazil,-23.5015,-47.4526
Soshanguve,South Africa,-25.5226,28.1007
South Hill,Anguilla,18.2167,-63.0833
Southampton,United Kingdom,50.9097,-1.4044
Southend-on-Sea,United Kingdom,51.5378,0.7138
Southport,United Kingdom,53.6457,-3.0065
Springs,South Africa,-26.2547,28.4428
Srinagar,India,34.0837,74.7973
Stavropol,Russian Federation,45.0428,41.9734
Steyr,Austria,48.0444,14.4255
Stockport,United Kingdom,53.4084,-2.1494
Stockton,United States,37.9577,-121.2908
Sucre,Bolivia,-19.0333,-65.2627
Suihua,China,46.6333,126.9833
Sukabumi,Indonesia,-6.9167,106.9167
Sullana,Peru,-4.9000,-80.6833
Sultanbeyli,Turkey,40.9667,29.2667
Sungai Petani,Malaysia,5.6433,100.4883
Sunnyvale,United States,37.3688,-122.0363
Surabaya,Indonesia,-7.2575,112.7521
Surakarta,Indonesia,-7.5667,110.8167
Syktyvkar,Russian Federation,61.6667,50.8167
Sylhet,Bangladesh,24.8917,91.8667
So Bernardo do Campo,Brazil,-23.6944,-46.5654
Tabriz,Iran,38.0962,46.2604
Tabuk,Philippines,17.4500,121.4500
T Tafila,Jordan,30.8333,35.6167
Taichung,Taiwan,24.1477,120.6736
Taiping,China,22.3833,113.6167
Taipei,Taiwan,25.0330,121.5654
Taiyuan,China,37.8706,112.5489
Tallahassee,United States,30.4383,-84.2807
Tama,Japan,35.6333,139.4500
Tambaram,India,12.9100,80.1400
Tambov,Russian Federation,52.7308,41.4423
Tangail,Bangladesh,24.2500,89.9167
Tanta,Egypt,30.7865,31.0004
Tapachula,Mexico,14.9000,-92.2833
Tarlac,Philippines,15.4802,120.5979
Tartu,Estonia,58.3780,26.7290
Tauranga,New Zealand,-37.6878,176.1651
Tbilis,Georgia,41.7151,44.8271
Tegucigalpa,Honduras,14.0723,-87.1921
Tehran,Iran,35.6892,51.3890
Tel Aviv-Jaffa,Israel,32.0853,34.7818
Teta,Mozambique,-16.1667,33.6000
Tianjin,China,39.3434,117.3616
Tiepling,China,42.2833,123.8333
Tiro,Lebanon,33.2667,35.2000
Tokat,Turkey,40.3167,36.5500
Tokorozawa,Japan,35.8000,139.4667
Tokyo,Japan,35.6762,139.6503
Tonghae,South Korea,37.5250,129.1167
Tonk,India,26.1700,75.7800
Torren,Mexico,25.5428,-103.4189
Touggourt,Algeria,33.1000,6.0667
Toulon,France,43.1242,5.9280
Toulouse,France,43.6047,1.4442
Tsuyama,Japan,35.0667,134.0000
Tuguegarao,Philippines,17.6133,121.7269
Tula,Russian Federation,54.2048,37.6185
Tume,Peru,-3.5667,-80.4500
Tunis,Tunisia,36.8065,10.1815
Turin,Italy,45.0703,7.6869
Udaipur,India,24.5800,73.6800
Udine,Italy,46.0619,13.2421
Ueda,Japan,36.4000,138.2500
Ujung Pandang,Indonesia,-5.1500,119.4333
Ulsan,South Korea,35.5384,129.3114
Uluberia,India,22.4700,88.1100
Umuahia,Nigeria,5.5167,7.4833
Uruapan,Mexico,19.4167,-102.0500
Usak,Turkey,38.6823,29.4082
Ust-Kamenogorsk,Kazakstan,49.9500,82.6167
Utrecht,Netherlands,52.0907,5.1214
Vaduz,Liechtenstein,47.1410,9.5209
Valenciennes,France,50.3579,3.5233
Valle de la Pascua,Venezuela,9.2150,-66.0094
Valle de Santiago,Mexico,20.4000,-101.2000
Valparai,Chile,-33.0472,-71.6127
Vancouver,Canada,49.2827,-123.1207
Varanasi (Benares),India,25.3176,82.9739
Velikije Luki,Russian Federation,56.3500,30.5167
Vidisha,India,23.5300,77.8200
Vienna,Austria,48.2082,16.3738
Vila Velha,Brazil,-20.3297,-40.2925
Vilnius,Lithuania,54.6872,25.2797
Virginia Beach,United States,36.8529,-75.9780
Vitria de Santo Anto,Brazil,-8.1189,-35.2953
Volos,Greece,39.3621,22.9422
Voronez,Russian Federation,51.6683,39.1919
Waco,United States,31.5493,-97.1467
Wajir,Kenya,1.7500,40.0500
Wakayama,Japan,34.2333,135.1667
Warren,United States,42.4775,-83.0277
Weifang,China,36.7167,119.1000
Wiesbaden,Germany,50.0782,8.2398
Windhoek,Namibia,-22.5609,17.0658
Witu,Kenya,-2.3833,40.4333
Woodridge,Australia,-27.6333,153.1000
Wroclaw,Poland,51.1079,17.0385
Xiangfan,China,32.0167,112.1333
Xintai,China,35.9000,117.7500
Xinxiang,China,35.3000,113.8667
Yerevan,Armenia,40.1872,44.5152
Yingkou,China,40.6667,122.2333
York,United Kingdom,53.9591,-1.0815
Yuzhou,China,34.1500,113.4667
Zalantun,China,48.0000,122.7167
Zamboanga,Philippines,6.9214,122.0790
Zanzibar,Tanzania,-6.1659,39.2026
Zaria,Nigeria,11.1113,7.7227
Zhezqazghan,Kazakstan,47.7833,67.7667
Zhoushan,China,30.0000,122.2000
Ziguinchor,Senegal,12.5833,-16.2667
EOF

echo "Geospatial data created at /home/ga/Documents/city_coordinates.csv ($(wc -l < /home/ga/Documents/city_coordinates.csv) rows)"

# 4. Prepare Workbench
if [ "$(is_workbench_running)" = "false" ]; then
    start_workbench
    sleep 10
fi
focus_workbench

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Agent task: Import /home/ga/Documents/city_coordinates.csv, update address locations, reassign customers to nearest store (1 or 2), and export results."