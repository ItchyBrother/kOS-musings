CLEARSCREEN.
// Ensure we're in the flight scene
IF KUNIVERSE:ACTIVEVESSEL <> SHIP OR NOT (STATUS = "ORBITING" OR STATUS = "FLYING" OR STATUS = "SUB_ORBITAL" OR STATUS = "LANDED" OR STATUS = "SPLASHED") {
    PRINT "Error: Script must run in flight mode on an active vessel.".
    WAIT 5.
    REBOOT.
}

// Initialize
PRINT "Scanning for orbiting vessels in current SOI...".
LOCAL mySOI IS SHIP:OBT:BODY.  // Your ship's SOI body (e.g., Kerbin).
PRINT "Your SOI: " + mySOI:NAME.

// List all targetable objects
LOCAL allTargets IS LIST().
LIST TARGETS IN allTargets.
PRINT "Total targets detected: " + allTargets:LENGTH.

// Filter for vessels in the same SOI with STATUS = "ORBITING"
LOCAL soiVessels IS LIST().
FOR tgt IN allTargets {
    IF tgt:TYPENAME = "Vessel" AND tgt:OBT:BODY = mySOI AND tgt:NAME <> SHIP:NAME AND tgt:STATUS = "ORBITING" {
        soiVessels:ADD(tgt).
    }
}

// Debug: List filtered vessels before sorting
PRINT "Orbiting vessels found in " + mySOI:NAME + ":".
IF soiVessels:LENGTH = 0 {
    PRINT "  None found.".
} ELSE {
    FOR ves IN soiVessels {
        LOCAL dist IS ROUND((SHIP:POSITION - ves:POSITION):MAG / 1000, 1).
        PRINT "  - " + ves:NAME + " (Distance: " + dist + " km, Status: " + ves:STATUS + ")".
        IF ABS(dist - 48) < 1 {
            PRINT "    ^-- Possible match for your 48 km vessel!".
        }
    }
}

IF soiVessels:LENGTH = 0 {
    PRINT "No orbiting vessels found in " + mySOI:NAME + ".".
    PRINT "Debug: Expected vessel at 48 km not detected, not orbiting, or not in " + mySOI:NAME + ".".
    PRINT "Debug: KSP's default physics range is ~22.5 km in orbit.".
    PRINT "Debug: Vessel may be unloaded if >22.5 km away. Move closer or use a mod to extend physics range.".
    PRINT "Try manual targeting (replace 'vessel_name' with the actual name):".
    PRINT "SET TARGET TO VESSEL('vessel_name').".
} ELSE {
    // Manual bubble sort by distance (closest first)
    PRINT "Sorting vessels by distance...".
    LOCAL n IS soiVessels:LENGTH.
    FROM {LOCAL i IS 0.} UNTIL i >= n - 1 STEP {SET i TO i + 1.} DO {
        FROM {LOCAL j IS 0.} UNTIL j >= n - i - 1 STEP {SET j TO j + 1.} DO {
            LOCAL distA IS (SHIP:POSITION - soiVessels[j]:POSITION):MAG.
            LOCAL distB IS (SHIP:POSITION - soiVessels[j + 1]:POSITION):MAG.
            IF distA > distB {
                // Swap elements
                LOCAL temp IS soiVessels[j].
                SET soiVessels[j] TO soiVessels[j + 1].
                SET soiVessels[j + 1] TO temp.
            }
        }
    }
    
    PRINT "Found " + soiVessels:LENGTH + " orbiting vessels in " + mySOI:NAME + " (sorted by distance):".
    FROM {LOCAL i IS 0.} UNTIL i >= soiVessels:LENGTH STEP {SET i TO i + 1.} DO {
        LOCAL ves IS soiVessels[i].
        PRINT (i + 1) + ": " + ves:NAME + " (Distance: " + ROUND((SHIP:POSITION - ves:POSITION):MAG / 1000, 1) + " km, Status: " + ves:STATUS + ")".
    }
    
    // Input using GETCHAR
    PRINT "Enter number (1-" + soiVessels:LENGTH + ") and press Enter, or any non-digit to cancel:".
    LOCAL inputStr IS "".
    UNTIL FALSE {
        LOCAL ch IS TERMINAL:INPUT:GETCHAR().
        IF ch = TERMINAL:INPUT:RETURN {
            BREAK.
        } ELSE IF ch:TONUMBER(-1) >= 0 AND ch:TONUMBER(-1) <= 9 {
            SET inputStr TO inputStr + ch.
            PRINT ch AT (TERMINAL:WIDTH - 10, TERMINAL:HEIGHT - 1).  // Echo input
        } ELSE {
            SET inputStr TO "".  // Cancel on non-digit
            BREAK.
        }
    }
    LOCAL choice IS inputStr:TONUMBER(-1).  // Convert to number, default -1 if invalid
    
    IF choice >= 1 AND choice <= soiVessels:LENGTH {
        LOCAL selectedVes IS soiVessels[choice - 1].
        SET TARGET TO selectedVes.
        PRINT "Target set to: " + selectedVes:NAME.
    } ELSE {
        PRINT "Invalid input or cancelled.".
    }
}
WAIT 0.  // Yield to allow target update