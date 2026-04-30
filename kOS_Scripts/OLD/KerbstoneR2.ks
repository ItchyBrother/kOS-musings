CLEARSCREEN.

// Function to initialize the launch sequence
FUNCTION launchInit {
    LOCK STEERING TO HEADING(90, 87).
    STAGE.
    LOCK THROTTLE TO 1.0.
    WAIT 2.
}

// Function for roll program
FUNCTION rollProgram {
    LOCK STEERING TO HEADING(90, 90).
}

// Function to jettison escape tower
FUNCTION jettisonTower {
    AG1 ON.
}

// Gravity Turn function
FUNCTION gravityTurn {
    PARAMETER targetAltitude.
    LOCAL pitch IS 90.
    LOCAL targetPitch IS 90.
    LOCAL startTurnAltitude IS 1500.
    LOCAL phaseOneAltitude IS 15000.
    LOCAL phaseTwoAltitude IS 30000.
    
    UNTIL SHIP:APOAPSIS > targetAltitude {
        IF SHIP:ALTITUDE > startTurnAltitude {
            IF SHIP:ALTITUDE < phaseOneAltitude {
                SET targetPitch TO MAX(30, 90 - ((SHIP:ALTITUDE - startTurnAltitude) / (phaseOneAltitude - startTurnAltitude) * 45)).
            } ELSE IF SHIP:ALTITUDE < phaseTwoAltitude {
                SET targetPitch TO MAX(0, 30 - ((SHIP:ALTITUDE - phaseOneAltitude) / (phaseTwoAltitude - phaseOneAltitude) * 15)).
            } ELSE {
                SET targetPitch TO MAX(-20, 0 - ((SHIP:ALTITUDE - phaseTwoAltitude) / 5000)).
            }
            SET pitch TO pitch * 0.7 + targetPitch * 0.3.
            LOCK STEERING TO HEADING(90, pitch).
        }
        WAIT 0.01.
    }
}

// Function for staging at high altitude
FUNCTION highAltitudeStage {
    LOCK THROTTLE TO 0.
    IF STAGE:READY {
        STAGE.
        WAIT 1.
    }
}

// Function for circularization burn
FUNCTION circularizeOrbit {
    SET GM TO SHIP:BODY:MU.
    SET rd TO SHIP:APOAPSIS + SHIP:BODY:RADIUS.
    SET v_current TO SHIP:VELOCITY:ORBIT:MAG.
    SET v_needed TO SQRT(GM / rd).
    SET dv_needed TO v_needed - v_current.
    SET max_acceleration TO SHIP:AVAILABLETHRUST / SHIP:MASS.
    SET burn_duration TO dv_needed / max_acceleration.

    WAIT UNTIL ETA:APOAPSIS < (burn_duration / 2).
    LOCK THROTTLE TO 1.0.

    UNTIL SHIP:PERIAPSIS > 75000 AND SHIP:ORBIT:ECCENTRICITY < 0.1 {
        WAIT 0.1.
    }
    LOCK THROTTLE TO 0.
}

// Main execution
SET MODE TO 0.

// Countdown timer
PRINT "KERBSTONE v1".
PRINT "Countdown:" AT (0, 1).
FROM {local countdown is 3.} UNTIL countdown = 0 STEP {SET countdown to countdown - 1.} DO {
    PRINT "T-" + countdown AT (0, 2).
    WAIT 1.
}

// Mode 0 - Prelaunch
IF MODE = 0 {
    PRINT "Mode 0 - Prelaunch" AT (0, 3).
    launchInit().
    SET MODE TO 1.
}

// Mode 1 - Launch
IF MODE = 1 {
    PRINT "Mode 1 - Launch" AT (0, 4).
    WHEN SHIP:ALTITUDE > 300 THEN {
        rollProgram().
    }
    WHEN SHIP:ALTITUDE > 50000 THEN {
        jettisonTower().
    }
    WAIT UNTIL SHIP:ALTITUDE > 1500.
    gravityTurn(60000).
    WAIT UNTIL SHIP:ALTITUDE > 70000.
    highAltitudeStage().
    SET MODE TO 2.
}

// Mode 2 - MECO
IF MODE = 2 {
    PRINT "Mode 2 - MECO" AT (0, 5).
    LOCK STEERING TO SHIP:PROGRADE.
    circularizeOrbit().
    SET MODE TO 3.
}

// Mode 3 - Final Orbital Insertions
IF MODE = 3 {
    PRINT "Mode 3 - Final Orbital Insertions" AT (0, 6).
    AG2 ON.
    RCS ON.
    LOCK STEERING TO SHIP:RETROGRADE.
    WAIT 60.
    AG3 ON.
    RCS OFF.
    
    // Print final orbital parameters
    PRINT "Final Orbital Parameters:" AT (0, 8).
    PRINT "Apoapsis: " + ROUND(SHIP:APOAPSIS, 0) + " m" AT (0, 9).
    PRINT "Periapsis: " + ROUND(SHIP:PERIAPSIS, 0) + " m" AT (0, 10).
    PRINT "Inclination: " + ROUND(SHIP:ORBIT:INCLINATION, 2) + " degrees" AT (0, 11).
    PRINT "Eccentricity: " + ROUND(SHIP:ORBIT:ECCENTRICITY, 3) AT (0, 12).
    PRINT "Remaining Liquid Fuel: " + ROUND(SHIP:LIQUIDFUEL, 0) + " units" AT (0, 13).
    PRINT "Remaining Delta-V: " + ROUND(SHIP:DELTAV:CURRENT, 0) + " m/s" AT (0, 14).
    
    PRINT "Program completed." AT (0, 15).
    PRINT 1/0.
    UNTIL FALSE {
        WAIT 0.1. 
    }
}