// Countdown
PRINT "Launch in...".
FROM {local countdown is 5.} UNTIL countdown = 0 STEP {SET countdown to countdown - 1.} DO {
    PRINT "..." + countdown.
    WAIT 1.
}

// Lock steering to up
LOCK STEERING TO UP.

// Initial stage setup
STAGE. // Activate first stage
LOCK THROTTLE TO 0.
WAIT 5.

// Second stage activation
STAGE. // Activate second stage
LOCK THROTTLE TO 1. // Full throttle

// Function to check if stage is exhausted
FUNCTION stageWhenEmpty {
    LIST ENGINES IN myEngines.
    FOR eng IN myEngines {
        IF eng:FLAMEOUT {
            WAIT 2. // 2 second delay before staging
            PRINT "Staging due to flameout.".
            STAGE.
            RETURN TRUE.
        }
    }
    RETURN FALSE.
}

// Variables for altitude and apoapsis checks
SET hasReachedTargetAltitude to FALSE.
SET hasReachedHighAltitude to FALSE.

// Main loop for staging and altitude checks
UNTIL SHIP:STATUS = "LANDED" {
    IF stageWhenEmpty() {
        WAIT 0.1. // Small delay to prevent rapid staging if multiple engines flame out at once
    }

    // Throttle control based on apoapsis
    IF SHIP:APOAPSIS > 71000 AND NOT hasReachedTargetAltitude {
        PRINT "Apoapsis above 70,000 meters, setting throttle to 0.".
        LOCK THROTTLE TO 0.
        SET hasReachedTargetAltitude to TRUE.
    }

    // Stage at 70,000 meters
    IF SHIP:ALTITUDE > 70000 AND NOT hasReachedHighAltitude {
        PRINT "Reached 70,000 meters, staging.".
        STAGE.
        LOCK THROTTLE TO 0.33. // Set throttle to 1/3
        SET hasReachedHighAltitude to TRUE.
    }

    // Throttle to 0 after passing 80,000 meters
    IF SHIP:ALTITUDE > 80000 {
        PRINT "Passed 80,000 meters, setting throttle to 0.".
        LOCK THROTTLE TO 0.
    }

    // Final stage activation
    IF SHIP:ALTITUDE < 3000 AND hasReachedHighAltitude {
        PRINT "Activating final stage under 3000 meters.".
        STAGE.
    }

    // Check if the ship has landed
    IF SHIP:STATUS = "LANDED" {
        PRINT "Ship has landed. Script ending.".
        BREAK.
    }

    WAIT 0.01. // Small wait to not overload the CPU
}

PRINT "Mission sequence completed!".