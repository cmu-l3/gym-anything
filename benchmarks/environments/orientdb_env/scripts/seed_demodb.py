#!/usr/bin/env python3
"""
Seed OrientDB DemoDB with real travel agency data.
Schema matches OrientDB's official DemoDB: https://orientdb.com/docs/last/gettingstarted/demodb/
Data uses real country names, real hotel names, real restaurant names, and realistic profiles.
"""
import urllib.request
import json
import base64
import time
import sys

ROOT_PASS = "GymAnything123!"
BASE_URL = "http://localhost:2480"
AUTH = base64.b64encode(f"root:{ROOT_PASS}".encode()).decode()
HEADERS = {
    "Authorization": f"Basic {AUTH}",
    "Content-Type": "application/json"
}


def api_call(method, path, body=None):
    data = json.dumps(body).encode() if body else None
    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        data=data,
        headers=HEADERS,
        method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return resp.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        body_txt = e.read().decode(errors="replace")[:200]
        print(f"  HTTPError {e.code} for {method} {path}: {body_txt}")
        return e.code, {}
    except Exception as e:
        print(f"  Error for {method} {path}: {e}")
        return 0, {}


def sql(db, command, allow_fail=False):
    status, result = api_call("POST", f"/command/{db}/sql", {"command": command})
    if status not in (200, 201) and not allow_fail:
        print(f"  WARN: SQL returned {status} for: {command[:80]}")
    return result


def create_database():
    print("Creating demodb database...")
    status, result = api_call("POST", "/database/demodb/plocal")
    if status in (200, 201):
        print("  demodb created successfully")
    elif status == 409:
        print("  demodb already exists, skipping creation")
    else:
        print(f"  Unexpected status {status}, trying to continue...")


def create_schema():
    print("Creating DemoDB schema...")

    # Vertex classes
    vertex_classes = [
        "CREATE CLASS Countries EXTENDS V",
        "CREATE CLASS Profiles EXTENDS V",
        "CREATE CLASS Customers EXTENDS V",
        "CREATE CLASS Hotels EXTENDS V",
        "CREATE CLASS Restaurants EXTENDS V",
        "CREATE CLASS Attractions EXTENDS V",
        "CREATE CLASS ArchaeologicalSites EXTENDS Attractions",
        "CREATE CLASS Castles EXTENDS Attractions",
        "CREATE CLASS Monuments EXTENDS Attractions",
        "CREATE CLASS Orders EXTENDS V",
        "CREATE CLASS Reviews EXTENDS V",
    ]
    for cls in vertex_classes:
        sql("demodb", cls, allow_fail=True)

    # Edge classes
    edge_classes = [
        "CREATE CLASS HasFriend EXTENDS E",
        "CREATE CLASS HasProfile EXTENDS E",
        "CREATE CLASS HasCustomer EXTENDS E",
        "CREATE CLASS HasOrder EXTENDS E",
        "CREATE CLASS HasStayed EXTENDS E",
        "CREATE CLASS HasEaten EXTENDS E",
        "CREATE CLASS HasVisited EXTENDS E",
        "CREATE CLASS MadeReview EXTENDS E",
        "CREATE CLASS HasReview EXTENDS E",
    ]
    for cls in edge_classes:
        sql("demodb", cls, allow_fail=True)

    # Properties for Countries
    country_props = [
        "CREATE PROPERTY Countries.Name STRING",
        "CREATE PROPERTY Countries.Type STRING",
    ]
    for p in country_props:
        sql("demodb", p, allow_fail=True)

    # Properties for Profiles
    profile_props = [
        "CREATE PROPERTY Profiles.Email STRING",
        "CREATE PROPERTY Profiles.Name STRING",
        "CREATE PROPERTY Profiles.Surname STRING",
        "CREATE PROPERTY Profiles.Gender STRING",
        "CREATE PROPERTY Profiles.Birthday DATE",
        "CREATE PROPERTY Profiles.Nationality STRING",
    ]
    for p in profile_props:
        sql("demodb", p, allow_fail=True)

    # Properties for Hotels
    hotel_props = [
        "CREATE PROPERTY Hotels.Name STRING",
        "CREATE PROPERTY Hotels.Type STRING",
        "CREATE PROPERTY Hotels.Phone STRING",
        "CREATE PROPERTY Hotels.Latitude DOUBLE",
        "CREATE PROPERTY Hotels.Longitude DOUBLE",
        "CREATE PROPERTY Hotels.Street STRING",
        "CREATE PROPERTY Hotels.City STRING",
        "CREATE PROPERTY Hotels.Country STRING",
        "CREATE PROPERTY Hotels.Stars INTEGER",
    ]
    for p in hotel_props:
        sql("demodb", p, allow_fail=True)

    # Properties for Restaurants
    restaurant_props = [
        "CREATE PROPERTY Restaurants.Name STRING",
        "CREATE PROPERTY Restaurants.Type STRING",
        "CREATE PROPERTY Restaurants.Phone STRING",
        "CREATE PROPERTY Restaurants.Latitude DOUBLE",
        "CREATE PROPERTY Restaurants.Longitude DOUBLE",
        "CREATE PROPERTY Restaurants.Street STRING",
        "CREATE PROPERTY Restaurants.City STRING",
        "CREATE PROPERTY Restaurants.Country STRING",
    ]
    for p in restaurant_props:
        sql("demodb", p, allow_fail=True)

    # Properties for Orders
    order_props = [
        "CREATE PROPERTY Orders.OrderedId INTEGER",
        "CREATE PROPERTY Orders.Date DATE",
        "CREATE PROPERTY Orders.Status STRING",
        "CREATE PROPERTY Orders.Price DOUBLE",
    ]
    for p in order_props:
        sql("demodb", p, allow_fail=True)

    # Properties for Reviews
    review_props = [
        "CREATE PROPERTY Reviews.Stars INTEGER",
        "CREATE PROPERTY Reviews.Text STRING",
        "CREATE PROPERTY Reviews.Date DATE",
    ]
    for p in review_props:
        sql("demodb", p, allow_fail=True)

    # Indexes
    sql("demodb", "CREATE INDEX Countries.Name UNIQUE", allow_fail=True)
    sql("demodb", "CREATE INDEX Profiles.Email UNIQUE", allow_fail=True)

    print("  Schema creation complete")


def seed_countries():
    print("Seeding Countries (real countries)...")
    countries = [
        ("Italy",          "European"),
        ("Germany",        "European"),
        ("France",         "European"),
        ("United Kingdom", "European"),
        ("United States",  "American"),
        ("Japan",          "Asian"),
        ("Australia",      "Oceanian"),
        ("Brazil",         "American"),
        ("Canada",         "American"),
        ("Spain",          "European"),
        ("Greece",         "European"),
        ("Netherlands",    "European"),
    ]
    for name, ctype in countries:
        sql("demodb", f"INSERT INTO Countries SET Name='{name}', Type='{ctype}'")
    print(f"  Inserted {len(countries)} countries")


def seed_profiles():
    print("Seeding Profiles (realistic users)...")
    profiles = [
        ("john.smith@example.com",   "John",     "Smith",     "Male",   "1985-03-15", "American"),
        ("maria.garcia@example.com", "Maria",    "Garcia",    "Female", "1990-07-22", "Spanish"),
        ("david.jones@example.com",  "David",    "Jones",     "Male",   "1978-11-08", "British"),
        ("sophie.martin@example.com","Sophie",   "Martin",    "Female", "1992-05-30", "French"),
        ("luca.rossi@example.com",   "Luca",     "Rossi",     "Male",   "1988-01-17", "Italian"),
        ("anna.mueller@example.com", "Anna",     "Mueller",   "Female", "1983-09-25", "German"),
        ("yuki.tanaka@example.com",  "Yuki",     "Tanaka",    "Female", "1995-04-12", "Japanese"),
        ("james.brown@example.com",  "James",    "Brown",     "Male",   "1975-08-03", "Australian"),
        ("emma.white@example.com",   "Emma",     "White",     "Female", "1991-12-19", "British"),
        ("carlos.lopez@example.com", "Carlos",   "Lopez",     "Male",   "1987-06-07", "Mexican"),
        ("piet.vanderberg@example.com","Piet",   "Vanderberg","Male",   "1980-02-14", "Dutch"),
        ("elena.petrakis@example.com","Elena",   "Petrakis",  "Female", "1993-10-28", "Greek"),
        ("thomas.schafer@example.com","Thomas",  "Schafer",   "Male",   "1970-05-05", "German"),
        ("clara.dubois@example.com", "Clara",    "Dubois",    "Female", "1989-03-21", "French"),
        ("kai.yamamoto@example.com", "Kai",      "Yamamoto",  "Male",   "1996-08-16", "Japanese"),
        # These two profiles are required for the link_records task (match OrientDB built-in DemoDB emails)
        ("domi@nek.gov",             "Isaac",    "Black",     "Male",   "1982-07-14", "American"),
        ("seari@ubu.edu",            "Rosie",    "Thornton",  "Female", "1990-11-03", "British"),
    ]
    for email, name, surname, gender, bday, nationality in profiles:
        sql("demodb", (
            f"INSERT INTO Profiles SET "
            f"Email='{email}', Name='{name}', Surname='{surname}', "
            f"Gender='{gender}', Birthday='{bday}', Nationality='{nationality}'"
        ))
    print(f"  Inserted {len(profiles)} profiles")


def seed_hotels():
    print("Seeding Hotels (real hotels with accurate data)...")
    hotels = [
        # (Name, Type, Phone, Lat, Lon, Street, City, Country, Stars)
        ("Hotel Artemide",       "Boutique",  "+39-06-4884-6000",  41.8981, 12.4989, "Via Nazionale 22",          "Rome",            "Italy",          4),
        ("Hotel Adlon Kempinski","Luxury",    "+49-30-2261-0",     52.5163, 13.3791, "Unter den Linden 77",       "Berlin",          "Germany",        5),
        ("Hotel de Crillon",     "Palace",    "+33-1-44-71-15-00", 48.8679,  2.3215, "10 Place de la Concorde",   "Paris",           "France",         5),
        ("The Savoy",            "Luxury",    "+44-20-7836-4343",  51.5099, -0.1201, "Strand",                    "London",          "United Kingdom", 5),
        ("The Plaza Hotel",      "Historic",  "+1-212-759-3000",   40.7645,-73.9744, "768 Fifth Avenue",          "New York",        "United States",  5),
        ("Park Hyatt Tokyo",     "Luxury",    "+81-3-5322-1234",   35.6858,139.6909, "3-7-1-2 Nishi Shinjuku",    "Tokyo",           "Japan",          5),
        ("Four Seasons Sydney",  "Luxury",    "+61-2-9250-3100",  -33.8611,151.2112, "199 George Street",         "Sydney",          "Australia",      5),
        ("Copacabana Palace",    "Historic",  "+55-21-2548-7070", -22.9683,-43.1842, "Av. Atlantica 1702",        "Rio de Janeiro",  "Brazil",         5),
        ("Hotel Arts Barcelona", "Modern",    "+34-93-221-1000",   41.3860,  2.1965, "Carrer de la Marina 19-21", "Barcelona",       "Spain",          5),
        ("Grande Bretagne Hotel","Historic",  "+30-210-333-0000",  37.9754, 23.7367, "Syntagma Square 1",         "Athens",          "Greece",         5),
        ("Intercontinental Amsterdam","Luxury","+31-20-655-6262",  52.3702,  4.9076, "Professor Tulpplein 1",     "Amsterdam",       "Netherlands",    5),
        ("Fairmont Le Manoir",   "Chateau",   "+33-1-44-90-80-00", 48.8742,  2.3087, "3 Rue de Rivoli",           "Paris",           "France",         4),
        ("Hotel Villa d Este",   "Lakeside",  "+39-031-3481",      45.9675,  9.2036, "Via Regina 40",             "Cernobbio",       "Italy",          5),
        ("Baglioni Hotel Luna",  "Boutique",  "+39-041-528-9840",  45.4331, 12.3386, "San Marco 1243",            "Venice",          "Italy",          5),
        ("Melia Berlin",         "Business",  "+49-30-2060-790",   52.5200, 13.3861, "Friedrichstrasse 103",      "Berlin",          "Germany",        4),
    ]
    for row in hotels:
        name, htype, phone, lat, lon, street, city, country, stars = row
        sql("demodb", (
            f"INSERT INTO Hotels SET Name='{name}', Type='{htype}', Phone='{phone}', "
            f"Latitude={lat}, Longitude={lon}, Street='{street}', "
            f"City='{city}', Country='{country}', Stars={stars}"
        ))
    print(f"  Inserted {len(hotels)} hotels")


def seed_restaurants():
    print("Seeding Restaurants (real restaurants)...")
    restaurants = [
        # (Name, Type, Phone, Lat, Lon, Street, City, Country)
        ("Da Enzo al 29",           "Traditional Italian", "+39-06-581-2260",   41.8902, 12.4672, "Via dei Vascellari 29",    "Rome",      "Italy"),
        ("Lorenz Adlon Esszimmer",  "Fine Dining",         "+49-30-2261-1960",  52.5163, 13.3789, "Unter den Linden 77",      "Berlin",    "Germany"),
        ("Le Cinq",                 "French Gastronomic",  "+33-1-49-52-71-54", 48.8728,  2.3091, "31 Avenue George V",       "Paris",     "France"),
        ("Sketch",                  "Contemporary",        "+44-20-7659-4500",  51.5135, -0.1438, "9 Conduit Street",         "London",    "United Kingdom"),
        ("Per Se",                  "New American",        "+1-212-823-9335",   40.7685,-73.9827, "10 Columbus Circle",       "New York",  "United States"),
        ("Narisawa",                "Innovative Japanese", "+81-3-5785-0799",   35.6701,139.7249, "2-6-15 Minami-Aoyama",     "Tokyo",     "Japan"),
        ("Quay Restaurant",         "Australian Seafood",  "+61-2-9251-5600",  -33.8580,151.2044, "Upper Level Overseas Pax Terminal", "Sydney", "Australia"),
        ("Roberta Sudbrack",        "Brazilian Contemporary","+55-21-3874-0139",-22.9640,-43.2017,"Av. Lineu de Paula Machado 916","Rio de Janeiro","Brazil"),
        ("Tickets",                 "Spanish Tapas",       "+34-93-292-4253",   41.3738,  2.1502, "Avinguda del Paral-lel 164","Barcelona","Spain"),
        ("Spondi",                  "French Mediterranean","+30-210-756-4021",  37.9781, 23.7467, "Pyrronos 5",               "Athens",    "Greece"),
        ("Vinkeles",                "Contemporary Dutch",  "+31-20-530-2010",   52.3639,  4.8875, "Keizersgracht 384",        "Amsterdam", "Netherlands"),
    ]
    for row in restaurants:
        name, rtype, phone, lat, lon, street, city, country = row
        sql("demodb", (
            f"INSERT INTO Restaurants SET Name='{name}', Type='{rtype}', Phone='{phone}', "
            f"Latitude={lat}, Longitude={lon}, Street='{street}', "
            f"City='{city}', Country='{country}'"
        ))
    print(f"  Inserted {len(restaurants)} restaurants")


def seed_attractions():
    print("Seeding Attractions (real archaeological sites, castles, monuments)...")
    # Archaeological Sites
    arch_sites = [
        ("Colosseum",            "Ancient Amphitheatre",  41.8902, 12.4922, "Piazza del Colosseo 1",     "Rome",     "Italy"),
        ("Acropolis of Athens",  "Ancient Citadel",       37.9715, 23.7257, "Acropolis Hill",            "Athens",   "Greece"),
        ("Pompeii",              "Roman Archaeological",  40.7510, 14.4860, "Via Villa dei Misteri 2",   "Naples",   "Italy"),
        ("Stonehenge",           "Prehistoric Monument",  51.1789, -1.8262, "Amesbury",                  "Wiltshire","United Kingdom"),
    ]
    for name, atype, lat, lon, street, city, country in arch_sites:
        sql("demodb", (
            f"INSERT INTO ArchaeologicalSites SET Name='{name}', Type='{atype}', "
            f"Latitude={lat}, Longitude={lon}, Street='{street}', "
            f"City='{city}', Country='{country}'"
        ))

    # Castles
    castles = [
        ("Neuschwanstein Castle", "Romanesque Revival",  47.5576, 10.7498, "Neuschwansteinstr. 20", "Schwangau",     "Germany"),
        ("Edinburgh Castle",      "Royal Fortress",       55.9486, -3.1999, "Castlehill",            "Edinburgh",     "United Kingdom"),
        ("Chateau de Chambord",   "Renaissance Chateau",  47.6161,  1.5169, "Chambord",              "Loire-et-Cher", "France"),
        ("Bran Castle",           "Gothic Castle",        45.5153, 25.3672, "Str. General Traian Mosoiu 24", "Bran", "Romania"),
    ]
    for name, ctype, lat, lon, street, city, country in castles:
        sql("demodb", (
            f"INSERT INTO Castles SET Name='{name}', Type='{ctype}', "
            f"Latitude={lat}, Longitude={lon}, Street='{street}', "
            f"City='{city}', Country='{country}'"
        ))

    # Monuments
    monuments = [
        ("Eiffel Tower",       "Iron Lattice Tower",   48.8584,  2.2945, "Champ de Mars 5",           "Paris",    "France"),
        ("Statue of Liberty",  "Copper Statue",        40.6892,-74.0445, "Liberty Island",            "New York", "United States"),
        ("Brandenburg Gate",   "Neoclassical Monument",52.5163, 13.3777, "Pariser Platz",             "Berlin",   "Germany"),
        ("Sagrada Familia",    "Basilica",             41.4036,  2.1744, "Carrer de Mallorca 401",    "Barcelona","Spain"),
        ("Big Ben",            "Gothic Clock Tower",   51.5007, -0.1246, "Westminster Bridge Rd",     "London",   "United Kingdom"),
        ("Parthenon",          "Ancient Temple",       37.9715, 23.7257, "Acropolis Hill",            "Athens",   "Greece"),
    ]
    for name, mtype, lat, lon, street, city, country in monuments:
        sql("demodb", (
            f"INSERT INTO Monuments SET Name='{name}', Type='{mtype}', "
            f"Latitude={lat}, Longitude={lon}, Street='{street}', "
            f"City='{city}', Country='{country}'"
        ))
    print("  Inserted archaeological sites, castles, and monuments")


def seed_customers_and_orders():
    print("Seeding Customers and Orders...")
    # Make first 8 profiles into customers
    result = sql("demodb", "SELECT @rid FROM Profiles LIMIT 8")
    profile_rids = []
    if result and "result" in result:
        profile_rids = [r["@rid"] for r in result["result"]]

    for rid in profile_rids:
        sql("demodb", f"INSERT INTO Customers SET OrderedId=1")
        sql("demodb", f"CREATE EDGE HasProfile FROM (SELECT FROM Customers ORDER BY @rid DESC LIMIT 1) TO {rid}", allow_fail=True)

    # Insert Orders with realistic travel booking data
    orders = [
        (1,  "2024-03-15", "Completed", 1250.00),
        (2,  "2024-04-20", "Completed", 890.50),
        (3,  "2024-05-10", "Pending",   2100.00),
        (4,  "2024-05-25", "Completed", 450.75),
        (5,  "2024-06-01", "Cancelled", 780.00),
        (6,  "2024-06-15", "Completed", 1560.00),
        (7,  "2024-07-04", "Pending",   3200.00),
        (8,  "2024-07-20", "Completed", 675.25),
        (9,  "2024-08-08", "Completed", 990.00),
        (10, "2024-08-30", "Pending",   1870.50),
    ]
    for oid, date, status, price in orders:
        sql("demodb", f"INSERT INTO Orders SET OrderedId={oid}, Date='{date}', Status='{status}', Price={price}")
    print(f"  Inserted {len(orders)} orders")


def create_graph_edges():
    print("Creating graph edges (HasFriend, HasStayed, HasEaten)...")

    # HasFriend edges between profiles
    friend_pairs = [
        ("john.smith@example.com",    "maria.garcia@example.com"),
        ("john.smith@example.com",    "david.jones@example.com"),
        ("maria.garcia@example.com",  "sophie.martin@example.com"),
        ("luca.rossi@example.com",    "anna.mueller@example.com"),
        ("yuki.tanaka@example.com",   "kai.yamamoto@example.com"),
        ("emma.white@example.com",    "david.jones@example.com"),
        ("carlos.lopez@example.com",  "john.smith@example.com"),
        ("thomas.schafer@example.com","anna.mueller@example.com"),
        ("elena.petrakis@example.com","sophie.martin@example.com"),
        ("piet.vanderberg@example.com","thomas.schafer@example.com"),
    ]
    for email1, email2 in friend_pairs:
        sql("demodb", (
            f"CREATE EDGE HasFriend FROM "
            f"(SELECT FROM Profiles WHERE Email='{email1}') TO "
            f"(SELECT FROM Profiles WHERE Email='{email2}')"
        ), allow_fail=True)

    # HasStayed edges: Profiles → Hotels
    stays = [
        ("john.smith@example.com",   "The Plaza Hotel"),
        ("john.smith@example.com",   "Hotel Adlon Kempinski"),
        ("maria.garcia@example.com", "Hotel Arts Barcelona"),
        ("david.jones@example.com",  "The Savoy"),
        ("sophie.martin@example.com","Hotel de Crillon"),
        ("luca.rossi@example.com",   "Hotel Artemide"),
        ("anna.mueller@example.com", "Melia Berlin"),
        ("yuki.tanaka@example.com",  "Park Hyatt Tokyo"),
        ("james.brown@example.com",  "Four Seasons Sydney"),
        ("emma.white@example.com",   "The Savoy"),
        ("elena.petrakis@example.com","Grande Bretagne Hotel"),
    ]
    for email, hotel in stays:
        sql("demodb", (
            f"CREATE EDGE HasStayed FROM "
            f"(SELECT FROM Profiles WHERE Email='{email}') TO "
            f"(SELECT FROM Hotels WHERE Name='{hotel}')"
        ), allow_fail=True)

    # HasEaten edges: Profiles → Restaurants
    eats = [
        ("john.smith@example.com",   "Per Se"),
        ("sophie.martin@example.com","Le Cinq"),
        ("david.jones@example.com",  "Sketch"),
        ("luca.rossi@example.com",   "Da Enzo al 29"),
        ("yuki.tanaka@example.com",  "Narisawa"),
        ("maria.garcia@example.com", "Tickets"),
        ("elena.petrakis@example.com","Spondi"),
    ]
    for email, rest in eats:
        sql("demodb", (
            f"CREATE EDGE HasEaten FROM "
            f"(SELECT FROM Profiles WHERE Email='{email}') TO "
            f"(SELECT FROM Restaurants WHERE Name='{rest}')"
        ), allow_fail=True)

    print("  Graph edges created")


def verify_seeding():
    print("\nVerifying seeded data...")
    checks = [
        ("Countries",     "SELECT COUNT(*) as cnt FROM Countries"),
        ("Profiles",      "SELECT COUNT(*) as cnt FROM Profiles"),
        ("Hotels",        "SELECT COUNT(*) as cnt FROM Hotels"),
        ("Restaurants",   "SELECT COUNT(*) as cnt FROM Restaurants"),
        ("Orders",        "SELECT COUNT(*) as cnt FROM Orders"),
    ]
    for label, query in checks:
        result = sql("demodb", query)
        count = result.get("result", [{}])[0].get("cnt", "?") if result else "?"
        print(f"  {label}: {count} records")


def main():
    # Wait for OrientDB REST API to be ready
    print("Waiting for OrientDB API to be ready...")
    for attempt in range(60):
        try:
            status, _ = api_call("GET", "/listDatabases")
            if status == 200:
                print(f"  OrientDB ready after {attempt * 2}s")
                break
        except Exception:
            pass
        time.sleep(2)
    else:
        print("ERROR: OrientDB did not become ready in time")
        sys.exit(1)

    create_database()
    time.sleep(2)  # Let DB initialize
    create_schema()
    seed_countries()
    seed_profiles()
    seed_hotels()
    seed_restaurants()
    seed_attractions()
    seed_customers_and_orders()
    create_graph_edges()
    verify_seeding()
    print("\nDemoDB seeding complete!")


if __name__ == "__main__":
    main()
