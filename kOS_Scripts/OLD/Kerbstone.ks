CLEARSCREEN.

// Clear the screen
PRINT "KERBSTONE v1".
PRINT "Countdown:".

// Countdown for 3 seconds
FROM {local countdown is 3.} UNTIL countdown = 0 STEP {SET countdown to countdown - 1.} DO {
    PRINT "T-" + countdown AT (0,2).
    WAIT 1.
}

// Initial setup - pitch 3 degrees east at launch
LOCK STEERING TO HEADING(90, 87). // 87 degrees pitch = 3 degrees from vertical, heading east
STAGE. // Ignite engines for liftoff
PRINT "LIFTOFF!" AT (0, 3).
LOCK THROTTLE TO 1.0. // Fixed throttle at max since engine isn't adjustable
WAIT 2. // Allow for initial ascent stabilization

// Roll at 300 meters to face downrange with front, then point vessel straight up
WHEN SHIP:ALTITUDE > 300 THEN {
    PRINT "Roll Program." AT (0, 4).
    LOCK STEERING TO HEADING(90, 90). // Roll to face front east, pitch to vertical
}

// Jettison escape tower at 50,000 meters
WHEN SHIP:ALTITUDE > 50000 THEN {
    PRINT "Tower Jettisoning!".
    AG1 ON. // Activate action group 1 for tower jettison
}

// Function for Gravity Turn - controlled turn east for 80km apoapsis, considering drag
FUNCTION gravityTurn {
    PARAMETER targetAltitude.
    LOCAL pitch IS 90. 
    LOCAL targetPitch IS 90.
    LOCAL startTurnAltitude IS 1500. // Start gravity turn at 1.5 km
    LOCAL phaseOneAltitude IS 15000. // First phase of turn ends at 15 km
    LOCAL phaseTwoAltitude IS 30000. // Second phase ends at 30 km
    
    UNTIL SHIP:APOAPSIS > targetAltitude {
        IF SHIP:ALTITUDE > startTurnAltitude {
            IF SHIP:ALTITUDE < phaseOneAltitude {
                // From 1500 meters to 15 km, pitch moves gradually from 90 to 45 degrees
                SET targetPitch TO MAX(30, 90 - ((SHIP:ALTITUDE - startTurnAltitude) / (phaseOneAltitude - startTurnAltitude) * 45)).
            } ELSE IF SHIP:ALTITUDE < phaseTwoAltitude {
                // From 15 km to 30 km, pitch moves gradually from 45 to 30 degrees accounting for drag
                SET targetPitch TO MAX(0, 30 - ((SHIP:ALTITUDE - phaseOneAltitude) / (phaseTwoAltitude - phaseOneAltitude) * 15)).
            } ELSE {
                // Above 30 km, adjust pitch for final apoapsis, minimize drag effect
                // More aggressive pitch reduction to achieve lower periapsis
                SET targetPitch TO MAX(-20, 0 - ((SHIP:ALTITUDE - phaseTwoAltitude) / 5000)).
            }
            SET pitch TO pitch * 0.7 + targetPitch * 0.3. // Smooth pitch transition
            LOCK STEERING TO HEADING(90, pitch). // Maintain eastward flight, adjust pitch

            // Real-time feedback
            PRINT "Current Pitch: " + ROUND(SHIP:FACING:PITCH, 2) + " deg" AT (0, 7).
            PRINT "Apoapsis: " + ROUND(SHIP:APOAPSIS, 0) + " m   Periapsis: " + ROUND(SHIP:PERIAPSIS, 0) + " m" AT (0, 8).
        }
        WAIT 0.01.
    }
    PRINT "EXIT GRAVITY TURN FUNCTION" AT (0, 6).
}

// Start gravity turn once above 1.5 km altitude
WAIT UNTIL SHIP:ALTITUDE > 1500.
PRINT "Starting Gravity Turn" AT (0, 5).
gravityTurn(60000).  // Trying 60 km

// Staging at 70,000 meters with added checks and debug info
WAIT UNTIL SHIP:ALTITUDE > 70000.
PRINT "Current Altitude: " + ROUND(SHIP:ALTITUDE, 0) + " m." AT (0, 11).
PRINT "Staging at " + ROUND(SHIP:ALTITUDE, 0) + " m." AT (0, 12).
LOCK THROTTLE TO 0.
PRINT "Throttle Locked to 0" AT (0, 13).
PRINT "Current Stage: " + STAGE:NUMBER AT (0, 14).
IF STAGE:READY {
    STAGE.
    WAIT 1.
    PRINT "Stage Executed" AT (0, 15).
} ELSE {
    PRINT "Stage Not Ready" AT (0, 15).
}

// Calculate optimal start for raising Periapsis above 75,000m

// Lock steering to prograde early to start turning in the right direction
LOCK STEERING TO SHIP:PROGRADE.

// Calculate necessary Delta-V for circularization
SET GM TO SHIP:BODY:MU. // Gravitational parameter of the body
SET rd TO SHIP:APOAPSIS + SHIP:BODY:RADIUS. // Radius at apoapsis
SET v_current TO SHIP:VELOCITY:ORBIT:MAG. // Current velocity at apoapsis
SET v_needed TO SQRT(GM / rd). // Velocity needed for circular orbit at this altitude

// Delta-V required
SET dv_needed TO v_needed - v_current.

// Estimate burn time (this is simplified and doesn't account for mass change)
SET max_acceleration TO SHIP:AVAILABLETHRUST / SHIP:MASS.
SET burn_duration TO dv_needed / max_acceleration.

// Wait until we are close to apoapsis, accounting for half the burn duration
WAIT UNTIL ETA:APOAPSIS < (burn_duration / 2).

// Full throttle for circularization burn
LOCK THROTTLE TO 1.0.
PRINT "Starting Circularization near Apoapsis" AT (0, 16).

UNTIL SHIP:PERIAPSIS > 75000 AND SHIP:ORBIT:ECCENTRICITY < 0.1 {
    PRINT "Periapsis: " + ROUND(SHIP:PERIAPSIS, 0) + " m  Eccentricity: " + ROUND(SHIP:ORBIT:ECCENTRICITY, 3) + "  Delta-V Left: " + ROUND(SHIP:DELTAV:CURRENT, 0) + " m/s" AT (0, 17).
    WAIT 0.1.
}

LOCK THROTTLE TO 0. // Stop engines after circularization
//DISABLE GYROS
AG2 ON.
RCS ON.
LOCK STEERING TO SHIP:RETROGRADE.
WAIT 30.
RCS OFF.
PRINT "Orbit Achieved!" AT (0, 18).

// Print final orbital parameters, fuel, Delta-V left
PRINT "Final Orbital Parameters:" AT (0, 19).
PRINT "Apoapsis: " + ROUND(SHIP:APOAPSIS, 0) + " m" AT (0, 20).
PRINT "Periapsis: " + ROUND(SHIP:PERIAPSIS, 0) + " m" AT (0, 21).
PRINT "Inclination: " + ROUND(SHIP:ORBIT:INCLINATION, 2) + " degrees" AT (0, 22).
PRINT "Eccentricity: " + ROUND(SHIP:ORBIT:ECCENTRICITY, 3) AT (0, 23).
PRINT "Remaining Liquid Fuel: " + ROUND(SHIP:LIQUIDFUEL, 0) + " units" AT (0, 24).
PRINT "Remaining Delta-V: " + ROUND(SHIP:DELTAV:CURRENT, 0) + " m/s" AT (0, 25).

PRINT "Program completed." AT (0, 26).
PRINT 1/0.
// End of script, no more actions
UNTIL FALSE {
    WAIT 0.1. 
}