-- Chinook Database Schema for PostgreSQL 13 (source database)
-- Source: https://github.com/lerocha/chinook-database (MIT License)
-- The Chinook database models a digital media store with real business data.
-- It was originally created for use as an alternative to the Northwind database.

-- Artists table
CREATE TABLE IF NOT EXISTS "Artist" (
    "ArtistId"  SERIAL PRIMARY KEY,
    "Name"      VARCHAR(120)
);

-- Albums table
CREATE TABLE IF NOT EXISTS "Album" (
    "AlbumId"   SERIAL PRIMARY KEY,
    "Title"     VARCHAR(160) NOT NULL,
    "ArtistId"  INTEGER NOT NULL REFERENCES "Artist"("ArtistId")
);

-- Media types table
CREATE TABLE IF NOT EXISTS "MediaType" (
    "MediaTypeId"   SERIAL PRIMARY KEY,
    "Name"          VARCHAR(120)
);

-- Genres table
CREATE TABLE IF NOT EXISTS "Genre" (
    "GenreId"   SERIAL PRIMARY KEY,
    "Name"      VARCHAR(120)
);

-- Tracks table
CREATE TABLE IF NOT EXISTS "Track" (
    "TrackId"       SERIAL PRIMARY KEY,
    "Name"          VARCHAR(200) NOT NULL,
    "AlbumId"       INTEGER REFERENCES "Album"("AlbumId"),
    "MediaTypeId"   INTEGER NOT NULL REFERENCES "MediaType"("MediaTypeId"),
    "GenreId"       INTEGER REFERENCES "Genre"("GenreId"),
    "Composer"      VARCHAR(220),
    "Milliseconds"  INTEGER NOT NULL,
    "Bytes"         INTEGER,
    "UnitPrice"     NUMERIC(10,2) NOT NULL
);

-- Customers table
CREATE TABLE IF NOT EXISTS "Customer" (
    "CustomerId"    SERIAL PRIMARY KEY,
    "FirstName"     VARCHAR(40) NOT NULL,
    "LastName"      VARCHAR(20) NOT NULL,
    "Company"       VARCHAR(80),
    "Address"       VARCHAR(70),
    "City"          VARCHAR(40),
    "State"         VARCHAR(40),
    "Country"       VARCHAR(40),
    "PostalCode"    VARCHAR(10),
    "Phone"         VARCHAR(24),
    "Fax"           VARCHAR(24),
    "Email"         VARCHAR(60) NOT NULL,
    "SupportRepId"  INTEGER
);

-- Employees table
CREATE TABLE IF NOT EXISTS "Employee" (
    "EmployeeId"    SERIAL PRIMARY KEY,
    "LastName"      VARCHAR(20) NOT NULL,
    "FirstName"     VARCHAR(20) NOT NULL,
    "Title"         VARCHAR(30),
    "ReportsTo"     INTEGER REFERENCES "Employee"("EmployeeId"),
    "BirthDate"     TIMESTAMP,
    "HireDate"      TIMESTAMP,
    "Address"       VARCHAR(70),
    "City"          VARCHAR(40),
    "State"         VARCHAR(40),
    "Country"       VARCHAR(40),
    "PostalCode"    VARCHAR(10),
    "Phone"         VARCHAR(24),
    "Fax"           VARCHAR(24),
    "Email"         VARCHAR(60)
);

-- Invoices table
CREATE TABLE IF NOT EXISTS "Invoice" (
    "InvoiceId"         SERIAL PRIMARY KEY,
    "CustomerId"        INTEGER NOT NULL REFERENCES "Customer"("CustomerId"),
    "InvoiceDate"       TIMESTAMP NOT NULL,
    "BillingAddress"    VARCHAR(70),
    "BillingCity"       VARCHAR(40),
    "BillingState"      VARCHAR(40),
    "BillingCountry"    VARCHAR(40),
    "BillingPostalCode" VARCHAR(10),
    "Total"             NUMERIC(10,2) NOT NULL
);

-- Invoice line items
CREATE TABLE IF NOT EXISTS "InvoiceLine" (
    "InvoiceLineId" SERIAL PRIMARY KEY,
    "InvoiceId"     INTEGER NOT NULL REFERENCES "Invoice"("InvoiceId"),
    "TrackId"       INTEGER NOT NULL REFERENCES "Track"("TrackId"),
    "UnitPrice"     NUMERIC(10,2) NOT NULL,
    "Quantity"      INTEGER NOT NULL
);

-- Playlists table
CREATE TABLE IF NOT EXISTS "Playlist" (
    "PlaylistId"    SERIAL PRIMARY KEY,
    "Name"          VARCHAR(120)
);

-- Playlist tracks junction
CREATE TABLE IF NOT EXISTS "PlaylistTrack" (
    "PlaylistId"    INTEGER NOT NULL REFERENCES "Playlist"("PlaylistId"),
    "TrackId"       INTEGER NOT NULL REFERENCES "Track"("TrackId"),
    PRIMARY KEY ("PlaylistId", "TrackId")
);

-- ============================================================
-- Seed data (subset of real Chinook data)
-- ============================================================

INSERT INTO "Artist" ("Name") VALUES
    ('AC/DC'), ('Accept'), ('Aerosmith'), ('Alanis Morissette'), ('Alice In Chains'),
    ('Antônio Carlos Jobim'), ('Apocalyptica'), ('Audioslave'), ('BackBeat'),
    ('Billy Cobham'), ('Black Label Society'), ('Black Sabbath'), ('Body Count'),
    ('Bruce Dickinson'), ('Buddy Guy'), ('Caetano Veloso'), ('Chico Buarque'),
    ('Chico Science & Nação Zumbi'), ('Cidade Negra'), ('Cláudio Zoli'),
    ('David Bowie'), ('Deep Purple'), ('Def Leppard'), ('Djavan'), ('Eric Clapton'),
    ('Faith No More'), ('Frank Zappa & Captain Beefheart'), ('Funk Como Le Gusta'),
    ('Gilberto Gil'), ('Green Day'), ('Guns N'' Roses'), ('Incognito'),
    ('Iron Maiden'), ('James Brown'), ('Jamiroquai'), ('João Gilberto'),
    ('Joe Satriani'), ('Jorge Ben'), ('Jimi Hendrix'), ('Joe Satriani'),
    ('Led Zeppelin'), ('Lenny Kravitz'), ('Luciana Souza/Romero Lubambo'),
    ('Miles Davis'), ('Milton Nascimento & Lô Borges'), ('Nirvana'),
    ('Os Mutantes'), ('Pearl Jam'), ('Pink Floyd'), ('Queen'), ('R.E.M.'),
    ('Raimundos'), ('Raul Seixas'), ('Red Hot Chili Peppers'), ('Rush'),
    ('Santana'), ('Skank'), ('Smashing Pumpkins'), ('Soundgarden'), ('The Clash'),
    ('The Cult'), ('The Doors'), ('The Police'), ('The Rolling Stones'),
    ('Tim Maia'), ('Titãs'), ('U2'), ('Van Halen'), ('Various Artists'),
    ('Vinícius De Moraes'), ('Xis')
ON CONFLICT DO NOTHING;

INSERT INTO "MediaType" ("Name") VALUES
    ('MPEG audio file'), ('Protected AAC audio file'), ('Protected MPEG-4 video file'),
    ('Purchased AAC audio file'), ('AAC audio file')
ON CONFLICT DO NOTHING;

INSERT INTO "Genre" ("Name") VALUES
    ('Rock'), ('Jazz'), ('Metal'), ('Alternative & Punk'), ('Rock And Roll'),
    ('Blues'), ('Latin'), ('Reggae'), ('Pop'), ('Soundtrack'), ('Bossa Nova'),
    ('Easy Listening'), ('Heavy Metal'), ('R&B/Soul'), ('Electronica/Dance'),
    ('World'), ('Hip Hop/Rap'), ('Science Fiction'), ('TV Shows'), ('Sci Fi & Fantasy'),
    ('Drama'), ('Comedy'), ('Alternative'), ('Classical'), ('Opera')
ON CONFLICT DO NOTHING;

INSERT INTO "Employee" ("LastName", "FirstName", "Title", "BirthDate", "HireDate", "Address", "City", "State", "Country", "PostalCode", "Phone", "Fax", "Email")
VALUES
    ('Adams', 'Andrew', 'General Manager', '1962-02-18', '2002-08-14', '11120 Jasper Ave NW', 'Edmonton', 'AB', 'Canada', 'T5K 2N1', '+1 (780) 428-9482', '+1 (780) 428-3457', 'andrew@chinookcorp.com'),
    ('Edwards', 'Nancy', 'Sales Manager', '1958-12-08', '2002-05-01', '825 8 Ave SW', 'Calgary', 'AB', 'Canada', 'T2P 2T3', '+1 (403) 262-3443', '+1 (403) 262-3322', 'nancy@chinookcorp.com'),
    ('Peacock', 'Jane', 'Sales Support Agent', '1973-08-29', '2002-04-01', '1111 6 Ave SW', 'Calgary', 'AB', 'Canada', 'T2P 5M5', '+1 (403) 262-3443', '+1 (403) 262-6712', 'jane@chinookcorp.com'),
    ('Park', 'Margaret', 'Sales Support Agent', '1947-09-19', '2003-05-03', '683 10 Street SW', 'Calgary', 'AB', 'Canada', 'T2P 5G3', '+1 (403) 263-4423', '+1 (403) 263-4289', 'margaret@chinookcorp.com'),
    ('Johnson', 'Steve', 'Sales Support Agent', '1965-03-03', '2003-10-17', '7727B 41 Ave', 'Calgary', 'AB', 'Canada', 'T3B 1Y7', '1 (780) 836-9987', '1 (780) 836-9543', 'steve@chinookcorp.com'),
    ('Mitchell', 'Michael', 'IT Manager', '1973-07-01', '2003-10-17', '5827 Bowness Road NW', 'Calgary', 'AB', 'Canada', 'T3B 0C5', '+1 (403) 246-9887', '+1 (403) 246-9899', 'michael@chinookcorp.com'),
    ('King', 'Robert', 'IT Staff', '1970-05-29', '2004-01-02', '590 Columbia Boulevard West', 'Lethbridge', 'AB', 'Canada', 'T1K 5N8', '+1 (403) 456-9986', '+1 (403) 456-8485', 'robert@chinookcorp.com'),
    ('Callahan', 'Laura', 'IT Staff', '1968-01-09', '2004-03-04', '923 7 ST NW', 'Lethbridge', 'AB', 'Canada', 'T1H 1Y8', '+1 (403) 467-3351', '+1 (403) 467-8772', 'laura@chinookcorp.com')
ON CONFLICT DO NOTHING;

INSERT INTO "Customer" ("FirstName", "LastName", "Company", "Address", "City", "State", "Country", "PostalCode", "Phone", "Email", "SupportRepId")
VALUES
    ('Luís', 'Gonçalves', 'Embraer - Empresa Brasileira de Aeronáutica S.A.', 'Av. Brigadeiro Faria Lima, 2170', 'São José dos Campos', 'SP', 'Brazil', '12227-000', '+55 (12) 3923-5555', 'luisg@embraer.com.br', 3),
    ('Leonie', 'Köhler', NULL, 'Theodor-Heuss-Straße 34', 'Stuttgart', NULL, 'Germany', '70174', '+49 0711 2842222', 'leonekohler@surfeu.de', 5),
    ('François', 'Tremblay', NULL, '1498 rue Bélanger', 'Montréal', 'QC', 'Canada', 'H2G 1A7', '+1 (514) 721-4711', 'ftremblay@gmail.com', 3),
    ('Bjørn', 'Hansen', NULL, 'Ullevålsveien 14', 'Oslo', NULL, 'Norway', '0171', '+47 22 44 22 22', 'bjorn.hansen@yahoo.no', 4),
    ('František', 'Wichterlová', 'JetBrains s.r.o.', 'Klanova 9/506', 'Prague', NULL, 'Czech Republic', '14700', '+420 2 4172 5555', 'frantisekw@jetbrains.com', 4),
    ('Helena', 'Holý', NULL, 'Rilská 3174/6', 'Prague', NULL, 'Czech Republic', '14300', '+420 2 4177 0449', 'hholy@gmail.com', 5),
    ('Astrid', 'Gruber', NULL, 'Rotenturmstraße 4, 1010 Innere Stadt', 'Vienne', NULL, 'Austria', '1010', '+43 01 5134505', 'astrid.gruber@apple.at', 5),
    ('Daan', 'Peeters', NULL, 'Grétrystraat 63', 'Brussels', NULL, 'Belgium', '1000', '+32 02 219 03 03', 'daan_peeters@apple.be', 4),
    ('Kara', 'Nielsen', NULL, 'Sønder Boulevard 51', 'Copenhagen', NULL, 'Denmark', '1720', '+453 3331 9991', 'kara.nielsen@jubii.dk', 4),
    ('Eduardo', 'Martins', 'Woodstock Discos', 'Rua Dr. Falcão Filho, 155', 'São Paulo', 'SP', 'Brazil', '01007-010', '+55 (11) 3033-5446', 'eduardo@woodstock.com.br', 3)
ON CONFLICT DO NOTHING;
