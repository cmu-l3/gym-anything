#!/bin/bash
echo "=== Setting up record_vaccination task ==="
source /workspace/scripts/task_utils.sh

# Ensure ASM3 is running and accessible
wait_for_http "${ASM_BASE_URL}/login" 60

# Ensure we have an animal named 'Buddy' in the database
BUDDY_EXISTS=$(asm_query "SELECT COUNT(*) FROM animal WHERE AnimalName = 'Buddy'" 2>/dev/null | tr -d ' ')
if [ "$BUDDY_EXISTS" = "0" ] || [ -z "$BUDDY_EXISTS" ]; then
    log "Creating animal 'Buddy' for this task..."
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
        2, 'Buddy',
        0, 0, 0, 0,
        3, 1, 2, 0,
        0, 0,
        'D2024001', 'D001', '',
        CURRENT_TIMESTAMP - INTERVAL '3 years', 1,
        1, 0, '',
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
        CURRENT_TIMESTAMP, 'Labrador Retriever',
        'user', CURRENT_TIMESTAMP, 'user', CURRENT_TIMESTAMP
    )" 2>/dev/null || log "WARNING: Could not create Buddy record"
fi

# Record whether Buddy has any existing vaccinations
BUDDY_ID=$(asm_query "SELECT ID FROM animal WHERE AnimalName = 'Buddy' LIMIT 1" 2>/dev/null | tr -d ' ')
if [ -n "$BUDDY_ID" ]; then
    INITIAL_VAX=$(asm_query "SELECT COUNT(*) FROM animalvaccination WHERE AnimalID = ${BUDDY_ID}" 2>/dev/null | tr -d ' ' || echo "0")
    echo "${INITIAL_VAX}" > /tmp/initial_vaccination_count.txt
    echo "${BUDDY_ID}" > /tmp/buddy_animal_id.txt
    log "Buddy ID: ${BUDDY_ID}, existing vaccinations: ${INITIAL_VAX}"
fi

# Restart Firefox, auto-login, and show the ASM3 dashboard
restart_firefox_logged_in "${ASM_BASE_URL}/main"
sleep 2

take_screenshot /tmp/task_start_vaccination.png
log "Task setup complete. Firefox showing ASM3 main page with animal list."

echo "=== record_vaccination task setup complete ==="
