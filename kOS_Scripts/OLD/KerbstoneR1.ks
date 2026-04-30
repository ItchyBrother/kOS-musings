// Refactored KOS Script for Kerbstone v1 with Adjustments

// Constants
SET LAUNCH_PITCH TO 87.        // 3 degrees east from vertical
SET START_TURN_ALT TO 1500.   // Gravity turn starts at 1.5 km
SET PHASE_ONE_ALT TO 15000.   // Phase one ends at 15 km
SET PHASE_TWO_ALT TO 30000.   // Phase two ends at 30 km
SET TARGET_ORBIT TO 75000.    // Target periapsis for orbit
SET TARGET_AP TO 60000.       // Target apoapsis for gravity turn
SET COUNTDOWN_START TO 3.     // Countdown start time

// Functions
FUNCTION countdown {
    PARAMETER startTime.
    PRINT "Starting Countdown...".
    LOCAL cd1 IS startTime.
    FROM {LOCAL countdown IS cd1.} UNTIL countdown = 0 STEP {SET countdown TO countdown - 1.} DO {
        PRINT "T-" + countdown AT (0, 2).
        WAIT 1.
    }
    PRINT "LIFTOFF!" AT (0, 3).
}

FUNCTION gravityTurn {
    PARAMETER targetAltitude.
    LOCAL pitch IS 90.
    LOCAL targetPitch IS 90.

    PRINT "Starting Gravity Turn to Apoapsis: " + targetAltitude.

    UNTIL SHIP:APOAPSIS > targetAltitude {
        IF SHIP:ALTITUDE > START_TURN_ALT {
            IF SHIP:ALTITUDE < PHASE_ONE_ALT {
                SET targetPitch TO MAX(30, 90 - ((SHIP:ALTITUDE - START_TURN_ALT) / (PHASE_ONE_ALT - START_TURN_ALT) * 45)).
            } ELSE IF SHIP:ALTITUDE < PHASE_TWO_ALT {
                SET targetPitch TO MAX(0, 30 - ((SHIP:ALTITUDE - PHASE_ONE_ALT) / (PHASE_TWO_ALT - PHASE_ONE_ALT) * 15)).
            } ELSE {
                SET targetPitch TO MAX(-20, 0 - ((SHIP:ALTITUDE - PHASE_TWO_ALT) / 5000)).
            }

            SET pitch TO pitch * 0.7 + targetPitch * 0.3.
            LOCK STEERING TO HEADING(90, pitch).

            PRINT "Current Pitch: " + ROUND(SHIP:FACING:PITCH, 2) + " deg" AT (0, 7).
            PRINT "Apoapsis: " + ROUND(SHIP:APOAPSIS, 0) + " m   Periapsis: " + ROUND(SHIP:PERIAPSIS, 0) + " m" AT (0, 8).
        }
        WAIT 0.01.
    }
    PRINT "Gravity Turn Completed" AT (0, 6).
}

FUNCTION circularization {
    PRINT "Calculating Circularization Burn...".
    SET GM TO SHIP:BODY:MU.
    SET rd TO SHIP:APOAPSIS + SHIP:BODY:RADIUS.
    SET v_current TO SHIP:VELOCITY:ORBIT:MAG.
    SET v_needed TO SQRT(GM / rd).

    SET dv_needed TO v_needed - v_current.
    SET max_acceleration TO SHIP:AVAILABLETHRUST / SHIP:MASS.
    SET burn_duration TO dv_needed / max_acceleration.

    PRINT "Delta-V Needed: " + ROUND(dv_needed, 2) + " m/s".
    PRINT "Estimated Burn Time: " + ROUND(burn_duration, 2) + " seconds".

    WAIT UNTIL ETA:APOAPSIS < (burn_duration / 2).
    LOCK THROTTLE TO 1.0.
    PRINT "Starting Circularization near Apoapsis" AT (0, 16).

    UNTIL SHIP:PERIAPSIS > TARGET_ORBIT AND SHIP:ORBIT:ECCENTRICITY < 0.1 {
        PRINT "Periapsis: " + ROUND(SHIP:PERIAPSIS, 0) + " m  Eccentricity: " + ROUND(SHIP:ORBIT:ECCENTRICITY, 3) + "  Delta-V Left: " + ROUND(SHIP:DELTAV:CURRENT, 0) + " m/s" AT (0, 17).
        WAIT 0.1.
    }
    LOCK THROTTLE TO 0.
    PRINT "Orbit Achieved!" AT (0, 18).
}

// Main Program
CLEARSCREEN.
PRINT "KERBSTONE v1".
PRINT "Countdown:".

// Countdown
countdown(COUNTDOWN_START).

// Launch
PRINT "Initiating Launch Sequence...".
LOCK STEERING TO HEADING(90, LAUNCH_PITCH).
STAGE.
LOCK THROTTLE TO 1.0.
WAIT 2.

// Roll Program
WHEN SHIP:ALTITUDE > 300 THEN {
    PRINT "Roll Program." AT (0, 4).
    LOCK STEERING TO HEADING(90, 90).
}

// Tower Jettison
WHEN SHIP:ALTITUDE > 50000 THEN {
    PRINT "Tower Jettisoning!".
    AG1 ON.
}

// Gravity Turn
WAIT UNTIL SHIP:ALTITUDE > START_TURN_ALT.
PRINT "Starting Gravity Turn" AT (0, 5).
gravityTurn(TARGET_AP).

// Staging
WAIT UNTIL SHIP:ALTITUDE > 70000.
PRINT "Staging at " + ROUND(SHIP:ALTITUDE, 0) + " m." AT (0, 12).
LOCK THROTTLE TO 0.
IF STAGE:READY {
    STAGE.
    WAIT 1.
    PRINT "Stage Executed" AT (0, 15).
} ELSE {
    PRINT "Stage Not Ready" AT (0, 15).
}

// Circularization
circularization().

// Final Parameters
PRINT "Final Orbital Parameters:" AT (0, 19).
PRINT "Apoapsis: " + ROUND(SHIP:APOAPSIS, 0) + " m" AT (0, 20).
PRINT "Periapsis: " + ROUND(SHIP:PERIAPSIS, 0) + " m" AT (0, 21).
PRINT "Inclination: " + ROUND(SHIP:ORBIT:INCLINATION, 2) + " degrees" AT (0, 22).
PRINT "Eccentricity: " + ROUND(SHIP:ORBIT:ECCENTRICITY, 3) AT (0, 23).
PRINT "Remaining Liquid Fuel: " + ROUND(SHIP:LIQUIDFUEL, 0) + " units" AT (0, 24).
PRINT "Remaining Delta-V: " + ROUND(SHIP:DELTAV:CURRENT, 0) + " m/s" AT (0, 25).

PRINT "Program completed." AT (0, 26).

// End of Script
UNTIL FALSE {
    WAIT 0.1.
}
