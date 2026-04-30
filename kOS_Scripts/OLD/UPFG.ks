// Version: 1.6

// Define Target Orbit Parameters
SET targetApoapsis TO 80000. // Target Apoapsis in meters
SET targetPeriapsis TO 80000. // Target Periapsis in meters for circular orbit

// Initial Setup
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0. // Ensure throttle is at 0 before countdown
LOCK THROTTLE TO 0. // Lock throttle to 0 during countdown

// Function to calculate drag force
FUNCTION estimateDrag {
    PARAMETER surfVelocity. // Surface-relative velocity magnitude

    // Approximate atmospheric density
    LOCAL atmDensity IS BODY:ATM:(ALTITUDE).
    IF atmDensity = 0 { RETURN 0. } // No drag above the atmosphere

    // Assume constant drag coefficient and area for simplicity
    LOCAL dragCoefficient IS 0.3. // Estimated value
    LOCAL crossSectionalArea IS 10.0. // Estimated cross-sectional area in m²

    RETURN 0.5 * atmDensity * (surfVelocity ^ 2) * dragCoefficient * crossSectionalArea.
}

// Function to display telemetry
FUNCTION DisplayTelemetry {
    CLEARSCREEN.
    PRINT "UNIFIED POWERED FLIGHT GUIDANCE ALGORITHM". // Title
    PRINT "VEHICLE : " + SHIP:NAME.
    PRINT "". // Spacer

    PRINT "M.E.T. : " + ROUND(MISSIONTIME, 0) + " s         CURRENT STATUS : ASCENT". 
    PRINT "". // Spacer

    PRINT "SURFACE DATA". // Surface data block
    PRINT "SURFACE ALT : " + ROUND(ALT:RADAR, 2) + " m        DOWNRANGE DST : " + ROUND(SHIP:GEOPOSITION:LAT, 2) + " deg".
    PRINT "VERTICAL SPD: " + ROUND(VERTICALSPEED, 2) + " m/s    HORIZ SPD      : " + ROUND(SHIP:VELOCITY:SURFACE:MAG, 2) + " m/s".

    LOCAL azimuth IS VANG(SHIP:FACING:VECTOR, NORTH:VECTOR). // Angle from north (azimuth)
    LOCAL aoa IS VANG(SHIP:FACING:VECTOR, SHIP:VELOCITY:SURFACE). // Angle of attack

    PRINT "SURF PITCH  : " + ROUND(SHIP:FACING:PITCH, 2) + " deg   INERT AZIMUTH  : " + ROUND(azimuth, 2) + " deg".
    PRINT "VERTICAL AOA: " + ROUND(aoa, 2) + " deg        HORIZ AOA      : " + ROUND(aoa, 2) + " deg".
    PRINT "". // Spacer
}

// Countdown
PRINT "Countdown Initiated.".
FROM {LOCAL countdown IS 3.} UNTIL countdown = 0 STEP {SET countdown TO countdown - 1.} DO {
    PRINT "T-" + countdown.
    WAIT 1.
}
PRINT "Liftoff!". // Notify liftoff

// Start engines after countdown
LOCK THROTTLE TO 1.0.

// Function to calculate stage data
FUNCTION evaluateStage {
    RETURN LIST(
        SHIP:MASS,                   // Total mass of the ship
        SHIP:MAXTHRUST,              // Max thrust available
        estimateDrag(SHIP:VELOCITY:SURFACE:MAG), // Drag force estimate
        STAGE:LIQUIDFUEL,            // Remaining liquid fuel in the current stage
        STAGE:OXIDIZER,              // Remaining oxidizer in the current stage
        STAGE:LIQUIDFUEL * 0.005 + STAGE:OXIDIZER * 0.005, // Total remaining propellant
        SHIP:MAXTHRUST / (SHIP:MASS * 9.81) // Thrust-to-weight ratio
    ).
}

// Function for pitch in gravity turn
FUNCTION pitchForGravityTurn {
    PARAMETER currentAlt.
    PARAMETER targetAlt.

    LOCAL pitch IS 90 - (currentAlt * 80 / targetAlt).
    IF pitch < 5 { SET pitch TO 5. }  // Minimum pitch to avoid zero angle

    // Adjust pitch for drag only if in atmosphere
    IF ALTITUDE < BODY:ATM:HEIGHT {
        LOCAL dragForce IS estimateDrag(SHIP:VELOCITY:SURFACE:MAG).
        SET pitch TO pitch - (dragForce / 10000). // Adjust based on drag
    }

    RETURN pitch.
}

// Main Ascent Loop with stage evaluation
LOCK STEERING TO HEADING(90, pitchForGravityTurn(ALTITUDE, targetApoapsis)).
UNTIL APOAPSIS >= targetApoapsis {
    LOCAL stageInfo IS evaluateStage().

    PRINT "Current Stage: " + STAGE:NUMBER + " - Mass: " + ROUND(stageInfo[0], 2) + "t, Thrust: " + ROUND(stageInfo[1], 2) + "kN, Drag: " + ROUND(stageInfo[2], 2) + "N".
    
    // Stage only when out of fuel in current stage
    IF stageInfo[3] < 0.1 AND stageInfo[4] < 0.1 { // Check if fuel and oxidizer are depleted
        PRINT "Staging...".
        STAGE.
        WAIT 1.
    }

    WAIT 0.01. // Small wait to reduce CPU load
}

// Coast to apoapsis
LOCK THROTTLE TO 0.
WAIT UNTIL ALTITUDE > BODY:ATM:HEIGHT.

// Circularization at apoapsis
LOCK STEERING TO SHIP:PROGRADE. // Align with prograde for circularization
WAIT UNTIL ETA:APOAPSIS < 30.

// Burn until circularized, evaluating the final stage
LOCK THROTTLE TO 1.0.
UNTIL PERIAPSIS >= targetPeriapsis - 100 {
    LOCAL finalStageInfo IS evaluateStage().
    PRINT "Final Stage Evaluation - Mass: " + ROUND(finalStageInfo[0], 2) + "t, Thrust: " + ROUND(finalStageInfo[1], 2) + "kN, TWR: " + ROUND(finalStageInfo[6], 2).
    WAIT 0.1.
}

// Cleanup
UNLOCK THROTTLE.
UNLOCK STEERING.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.

PRINT "Orbit achieved at: " + ROUND(ORBIT:APOAPSIS, 0) + "m Apoapsis, " + ROUND(ORBIT:PERIAPSIS, 0) + "m Periapsis".
