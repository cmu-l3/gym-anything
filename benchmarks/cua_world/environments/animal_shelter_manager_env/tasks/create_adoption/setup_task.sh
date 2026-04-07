#!/bin/bash
echo "=== Setting up create_adoption task ==="
source /workspace/scripts/task_utils.sh

# Ensure ASM3 is running and accessible
wait_for_http "${ASM_BASE_URL}/login" 60

# Ensure we have a cat named 'Whiskers' in the database
WHISKERS_EXISTS=$(asm_query "SELECT COUNT(*) FROM animal WHERE AnimalName = 'Whiskers'" 2>/dev/null | tr -d ' ')
if [ "$WHISKERS_EXISTS" = "0" ] || [ -z "$WHISKERS_EXISTS" ]; then
    log "Creating animal 'Whiskers' for this task..."
    asm_query "INSERT INTO animal (
        ID, AnimalTypeID, AnimalName,
        NonShelterAnimal, CrueltyCase, BondedAnimalID, BondedAnimal2ID,
        BaseColourID, SpeciesID, BreedID, Breed2ID,
        CrossBreed, CoatType,
        ShelterCode, ShortCode, AcceptanceNumber,
        DateOfBirth, EstimatedDOB,
        Sex, Identichipped, IdentichipNumber,
        Tattoo, TattooNumber, SmartTag, SmartTagType,
        Neutered, CombiTested, CombiTestResult,
        HeartwormTested, HeartwormTestResult, FLVResult,
        Declawed, OwnersVetID, CurrentVetID,
        OriginalOwnerID, BroughtInByOwnerID,
        DateBroughtIn, EntryReasonID,
        PutToSleep, PTSReasonID, IsDOA, IsTransfer,
        IsGoodWithCats, IsGoodWithDogs, IsGoodWithChildren,
        IsHouseTrained, IsNotAvailableForAdoption,
        HasSpecialNeeds, ShelterLocation, DiedOffShelter,
        Size, Archived, ActiveMovementID,
        MostRecentEntryDate, BreedName,
        CreatedBy, CreatedDate, LastChangedBy, LastChangedDate
    ) VALUES (
        (SELECT COALESCE(MAX(ID),0)+1 FROM animal),
        11, 'Whiskers',
        0, 0, 0, 0,
        2, 2, 100, 0,
        0, 0,
        'C2024001', 'C001', '',
        CURRENT_TIMESTAMP - INTERVAL '1 year', 1,
        0, 0, '',
        0, '', 0, 0,
        1, 0, 0,
        0, 0, 0,
        0, 0, 0,
        0, 0,
        CURRENT_TIMESTAMP, 7,
        0, 0, 0, 0,
        0, 0, 0,
        0, 0,
        0, 1, 0,
        2, 0, 0,
        CURRENT_TIMESTAMP, 'Domestic Short Hair',
        'user', CURRENT_TIMESTAMP, 'user', CURRENT_TIMESTAMP
    )" 2>/dev/null || log "WARNING: Could not create Whiskers record"
fi

# Ensure we have a person named 'Margaret Johnson' in the database
MARGARET_EXISTS=$(asm_query "SELECT COUNT(*) FROM owner WHERE OwnerSurname = 'Johnson' AND OwnerForenames = 'Margaret'" 2>/dev/null | tr -d ' ')
if [ "$MARGARET_EXISTS" = "0" ] || [ -z "$MARGARET_EXISTS" ]; then
    log "Creating person 'Margaret Johnson' for this task..."
    asm_query "INSERT INTO owner (ID, OwnerType, OwnerTitle, OwnerInitials, OwnerForenames, OwnerSurname, OwnerName, OwnerAddress, OwnerTown, OwnerCounty, OwnerPostcode, HomeTelephone, MobileTelephone, EmailAddress, IDCheck, CreatedBy, CreatedDate, LastChangedBy, LastChangedDate, RecordVersion)
    VALUES (
        (SELECT COALESCE(MAX(ID),0)+1 FROM owner),
        1, 'Mrs', 'M', 'Margaret', 'Johnson', 'Mrs Margaret Johnson',
        '1100 Congress Avenue', 'Austin', 'TX', '78701',
        '512-555-0142', '512-555-0143', 'margaret.johnson@email.com',
        1, 'user', CURRENT_TIMESTAMP, 'user', CURRENT_TIMESTAMP, 0
    )" 2>/dev/null || log "WARNING: Could not create Margaret Johnson record"
fi

# Remove any existing adoption for Whiskers (clean state)
WHISKERS_ID=$(asm_query "SELECT ID FROM animal WHERE AnimalName = 'Whiskers' LIMIT 1" 2>/dev/null | tr -d ' ')
if [ -n "$WHISKERS_ID" ]; then
    asm_query "DELETE FROM adoption WHERE AnimalID = ${WHISKERS_ID}" 2>/dev/null || true
    # Ensure Whiskers is not marked as adopted
    asm_query "UPDATE animal SET Archived = 0, ActiveMovementType = 0, ActiveMovementID = 0 WHERE ID = ${WHISKERS_ID}" 2>/dev/null || true
    echo "${WHISKERS_ID}" > /tmp/whiskers_animal_id.txt
fi

MARGARET_ID=$(asm_query "SELECT ID FROM owner WHERE OwnerSurname = 'Johnson' AND OwnerForenames = 'Margaret' LIMIT 1" 2>/dev/null | tr -d ' ')
echo "${MARGARET_ID}" > /tmp/margaret_owner_id.txt

log "Whiskers ID: ${WHISKERS_ID}, Margaret ID: ${MARGARET_ID}"

# Restart Firefox, auto-login, and show the ASM3 dashboard
restart_firefox_logged_in "${ASM_BASE_URL}/main"
sleep 2

take_screenshot /tmp/task_start_adoption.png
log "Task setup complete. Firefox showing ASM3 main page."

echo "=== create_adoption task setup complete ==="
