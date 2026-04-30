CLEARSCREEN.

// Global variables
SET TERMINAL:WIDTH TO 50.
SET TERMINAL:HEIGHT TO 36.
GLOBAL MECO_HAPPENED TO FALSE.
GLOBAL peakDynamicPressure TO 0.
GLOBAL dynamicPressureMonitorActive TO TRUE.

// Countdown
PRINT "KERBSTONE v1.1" AT (0, 0).
LOCAL countdown IS 3.
UNTIL countdown = 0 {
    PRINT "T-" + countdown AT (0, 1).
    SET countdown TO countdown - 1.
    WAIT 1.
}
PRINT "LIFTOFF!" AT (0, 1).

// Division line
PRINT "-----------------------------------------------" AT (0, 8).

// Functions to update specific information
FUNCTION updateMECOAltitude {
    PARAMETER mecoAltitude.
    PRINT "MECO Detected at " + ROUND(mecoAltitude, 0) + " meters." AT (0, 12).
}

FUNCTION updateTowerJettisonAltitude {
    PARAMETER towerAltitude.
    PRINT "Jettisoning Tower at " + ROUND(towerAltitude, 0) + " meters." AT (0, 14).
}

FUNCTION updateFinalOrbitData {
    PRINT "Final Orbital Parameters:" AT (0, 16).
    PRINT "Apoapsis: " + ROUND(SHIP:APOAPSIS, 0) + " m" AT (0, 17).
    PRINT "Periapsis: " + ROUND(SHIP:PERIAPSIS, 0) + " m" AT (0, 18).
    PRINT "Inclination: " + ROUND(SHIP:ORBIT:INCLINATION, 2) + " degrees" AT (0, 19).
    PRINT "Eccentricity: " + ROUND(SHIP:ORBIT:ECCENTRICITY, 3) AT (0, 20).
    PRINT "Remaining Liquid Fuel: " + ROUND(SHIP:LIQUIDFUEL, 0) + " units" AT (0, 21).
    PRINT "Remaining Delta-V: " + ROUND(SHIP:DELTAV:CURRENT, 0) + " m/s" AT (0, 22).
}

FUNCTION updateDebugInfo {
    PARAMETER burnDuration, dvNeeded, safetyDv, totalDv, burnStartTime, pitchAdjustment.
    PRINT "Estimated Burn Duration: " + ROUND(burnDuration, 1) + " seconds" AT (0, 24).
    PRINT "DeltaV Needed for Primary Objective: " + ROUND(dvNeeded, 0) + " m/s" AT (0, 25).
    PRINT "DeltaV for Safety Margin: " + ROUND(safetyDv, 0) + " m/s" AT (0, 26).
    PRINT "Total DeltaV Required: " + ROUND(totalDv, 0) + " m/s" AT (0, 27).
    PRINT "Burn Start Time Before Ap: " + ROUND(burnStartTime, 1) + " seconds" AT (0, 28).
    PRINT "Pitch Adjustment: " + ROUND(pitchAdjustment, 2) + " | Current Pitch: " + ROUND(SHIP:FACING:PITCH, 2) AT (0, 29).
}

// Function to check for MECO with both thrust and fuel considerations
FUNCTION checkFirstStageMECO {
    LOCAL noThrust IS TRUE.
    LOCAL noFuel IS TRUE.
    
    LIST ENGINES IN allEngines.
    FOR engine IN allEngines {
        IF engine:STAGE = 0 {
            SET noThrust TO noThrust AND (engine:FLAMEOUT OR engine:THRUST <= 0).
        }
    }
    
    // Check fuel in parts of stage 0
    LIST PARTS IN allParts.
    FOR part IN allParts {
        IF part:STAGE = 0 {
            FOR res IN part:RESOURCES {
                IF res:NAME = "LiquidFuel" AND res:AMOUNT > 0 {
                    SET noFuel TO FALSE.
                    BREAK.
                }
            }
        }
        IF NOT noFuel { BREAK. }
    }
    
    RETURN noThrust AND noFuel.
}

// Global MECO detection that will run regardless of mode
WHEN checkFirstStageMECO() THEN {
    SET MECO_HAPPENED TO TRUE.
}

// === Modularization ===
FUNCTION Mode0_Prelaunch {
    PRINT "Mode 0 - Prelaunch" AT (0, 3).
    AG10 ON.
    launchInit().
    SET MODE TO 1.
}

FUNCTION Mode1_Launch {
    PRINT "Mode 1 - Launch" AT (0, 4).
    WHEN SHIP:ALTITUDE > 300 THEN {
        PRINT "Roll Program" AT (0, 10).
        rollProgram().
    }
    
    WAIT UNTIL SHIP:ALTITUDE > 1500.
    PRINT "Starting Gravity Turn" AT (0, 10).
    adaptiveGravityTurn(80000).
  
    WAIT UNTIL MECO_HAPPENED.
    PRINT "MECO.  MAIN ENGINE CUT-OFF." AT (0, 11).
    updateMECOAltitude(SHIP:ALTITUDE).
    SET MODE TO 2.
}

FUNCTION Mode2_Circ {
    PRINT "Mode 2 - Circularization" AT (0, 5).
    
    WAIT UNTIL SHIP:ALTITUDE > 50000.
    PRINT "Tower Jettison." AT (0, 13).
    jettisonTower().
    updateTowerJettisonAltitude(SHIP:ALTITUDE).
    
    WAIT UNTIL SHIP:ALTITUDE > 70000.
    highAltitudeStage().

    LOCK STEERING TO SHIP:PROGRADE.
    AG9 ON.
    circularizeOrbit().
    SET MODE TO 3.
}

FUNCTION Mode3_FinalOrbit {
    PRINT "Mode 3 - Final Orbital Insertions" AT (0, 6).
    AG2 ON.
    RCS ON.
    LOCK STEERING TO SHIP:RETROGRADE.
    WAIT 30.
    RCS OFF.
    updateFinalOrbitData().
    PRINT "Program completed." AT (0, 15).
}

// === Error Handling ===
FUNCTION safeStage {
    IF NOT STAGE:READY {
        PRINT "Stage not ready, waiting..." AT (0, 10).
        WAIT UNTIL STAGE:READY.
    }
    STAGE.
}

// === Dynamic Adjustments ===
FUNCTION adaptiveGravityTurn {
    PARAMETER targetAltitude.
    LOCAL pitch IS 90.
    LOCAL targetPitch IS 90.
    LOCAL startAltitude IS 1500.
    SET peakDynamicPressure TO 0.
    SET dynamicPressureMonitorActive TO TRUE.

    UNTIL SHIP:APOAPSIS > targetAltitude {
        SET currentAltitude TO SHIP:ALTITUDE.
        SET currentVerticalSpeed TO VDOT(SHIP:VELOCITY:SURFACE, SHIP:UP:VECTOR).
        
        IF currentAltitude < startAltitude {
            SET targetPitch TO 90.
        } ELSE IF currentAltitude < 10000 {
            SET targetPitch TO MAX(45, 90 - ((currentAltitude - startAltitude) / (10000 - startAltitude)) * 45).
        } ELSE {
            SET targetPitch TO MAX(5, 45 - ((currentAltitude - 10000) / 17000) * 40).
            SET targetPitch TO targetPitch - ((SHIP:APOAPSIS - targetAltitude) / 10000).
        }
        
        SET pitch TO pitch * 0.6 + targetPitch * 0.4.
        
        LOCK STEERING TO HEADING(90, pitch).

        // Dynamic Pressure Monitoring 
        IF currentAltitude < BODY:ATM:HEIGHT {
            SET airDensity TO BODY:ATM:ALTITUDEPRESSURE(SHIP:ALTITUDE).
            SET currentDynamicPressure TO 0.5 * airDensity * (SHIP:VELOCITY:SURFACE:MAG)^2.
            
            IF currentDynamicPressure > peakDynamicPressure {
                SET peakDynamicPressure TO currentDynamicPressure.
            } ELSE {
                SET dynamicPressureMonitorActive TO FALSE.
            }
            
            IF dynamicPressureMonitorActive {
                PRINT "Dynamic Pressure: " + ROUND(currentDynamicPressure, 2) + " Pa" AT (0, 30).
            } ELSE {
                PRINT "Peak Dynamic Pressure: " + ROUND(peakDynamicPressure, 2) + " Pa" AT (0, 30).
            }
        }

        WAIT 0.01.
    }
}

// === Performance Optimization & Code Reusability ===
FUNCTION launchInit {
    LOCK STEERING TO HEADING(270, 93).
    STAGE.
    LOCK THROTTLE TO 1.0.
    WAIT 2.
}

FUNCTION rollProgram {
    LOCK STEERING TO HEADING(90, 90).
}

FUNCTION jettisonTower {
    AG1 ON.
}

FUNCTION highAltitudeStage {
    LOCK THROTTLE TO 0.
    safeStage().
}

FUNCTION circularizeOrbit {
    LOCAL start_deltav IS SHIP:DELTAV:CURRENT.
    LOCAL safety_deltav IS start_deltav * 0.1.
    LOCAL min_periapsis IS 75000.
    LOCAL burn_start_time IS TIME:SECONDS.
    LOCAL original_apoapsis IS SHIP:APOAPSIS.
    LOCAL burn_initiated IS FALSE.
    LOCAL burn_start_actual IS 0.  // To record when the burn actually starts
    LOCAL max_apo_increase IS 5000.  // Allow only a 5 km increase in apoapsis
    LOCAL apoapsis_passed IS FALSE.
    LOCAL last_eta_ap IS ETA:APOAPSIS.

    // Calculate DeltaV needed for circularization
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL r_ap IS SHIP:ORBIT:APOAPSIS + SHIP:BODY:RADIUS.
    LOCAL v_current IS SHIP:VELOCITY:ORBIT:MAG.
    LOCAL v_needed IS SQRT(mu / r_ap).  // For a circular orbit at apoapsis
    LOCAL dv_needed IS v_needed - v_current.

    // Estimate burn duration with a safety factor for a more conservative start
    LOCAL estimated_burn_duration IS dv_needed / (SHIP:AVAILABLETHRUST / SHIP:MASS).

    // Wait until we are close enough to apoapsis to calculate
    WAIT UNTIL ETA:APOAPSIS < 30.  // Starts burn preparation 30 seconds before apoapsis
    
    LOCK STEERING TO SHIP:PROGRADE.

    IF (SHIP:DELTAV:CURRENT - safety_deltav) > 0 {
        LOCK THROTTLE TO 0.0.  // Start with throttle at 0 to prepare for burn

        // Burn initiation logic with more conservative timing
        SET burn_start_time TO TIME:SECONDS + ETA:APOAPSIS - (estimated_burn_duration * 0.9).  // Start burn a bit earlier
        UNTIL burn_initiated {
            IF TIME:SECONDS >= burn_start_time {
                SET burn_initiated TO TRUE.
                SET burn_start_actual TO TIME:SECONDS.
                LOCK THROTTLE TO 1.0.
                PRINT "Burn Start Time Before Ap: " + ROUND(ETA:APOAPSIS, 1) + " seconds" AT (0, 28).
            } ELSE IF TIME:SECONDS >= (burn_start_time - 10) {  // Start a small burn 10 seconds earlier to fine-tune
                LOCK THROTTLE TO 0.1.
                PRINT "Pre-Burn Adjustment Starting" AT (0, 29).
            }
            WAIT 0.01.
        }

        LOCAL burn_end_time IS 0.
        
        // Main burn logic with refined pitch adjustments and DeltaV safety check
        UNTIL (SHIP:PERIAPSIS >= min_periapsis AND ABS(SHIP:APOAPSIS - SHIP:PERIAPSIS) < 2000) OR (start_deltav - SHIP:DELTAV:CURRENT) > (start_deltav - (safety_deltav + 50)) {
            // Check DeltaV safety margin, but allow for a little more usage
            IF SHIP:DELTAV:CURRENT < (safety_deltav + 50) {  
                BREAK.
            }
            
            // Check if apoapsis increase is too high
            IF SHIP:APOAPSIS > (original_apoapsis + max_apo_increase) {
                LOCK THROTTLE TO 0.  // Stop burn if apoapsis increases too much
                BREAK.
            }
            
            // Check if we've passed apoapsis by comparing with last ETA
            IF NOT apoapsis_passed AND ETA:APOAPSIS < 0 {
                SET apoapsis_passed TO TRUE.
            }
            
            // Adjust pitch to keep on top of Ap
            LOCAL pitch_adjustment IS 0.
            IF ETA:APOAPSIS < 0.5 AND NOT apoapsis_passed {
                SET pitch_adjustment TO 0.5.  // Small positive pitch if apoapsis is very close but not passed
            } ELSE IF ETA:APOAPSIS < 5 AND NOT apoapsis_passed {
                SET pitch_adjustment TO 0.2.  // Even smaller positive pitch if apoapsis is close but not passed
            } ELSE IF apoapsis_passed {
                SET pitch_adjustment TO 0.6.  // More aggressive positive pitch after passing apoapsis
            } ELSE IF ETA:APOAPSIS > 15 {
                SET pitch_adjustment TO -0.2.  // Small negative pitch if apoapsis is far ahead
            } ELSE IF ETA:APOAPSIS > 10 {
                SET pitch_adjustment TO -0.5.  // Moderate negative pitch if apoapsis is ahead
            }
            
            // Debug print to see pitch adjustments
            PRINT "Pitch Adjustment: " + ROUND(pitch_adjustment, 2) + " | ETA Apoapsis: " + ROUND(ETA:APOAPSIS, 2) + " | Current Ap: " + ROUND(SHIP:APOAPSIS, 0) + " m | Apoapsis Passed: " + apoapsis_passed AT (0, 31).
            
            LOCK STEERING TO SHIP:PROGRADE + R(0, pitch_adjustment, 0).
            
            WAIT 0.01.
        }
        
        SET burn_end_time TO TIME:SECONDS.
        LOCK THROTTLE TO 0.
        LOCK STEERING TO SHIP:PROGRADE.  // Reset steering to prograde after burn

        LOCAL actual_burn_duration IS burn_end_time - burn_start_actual.
        PRINT "Circularization Burn Completed." AT (0, 34).
        updateDebugInfo(estimated_burn_duration, dv_needed, safety_deltav, dv_needed + safety_deltav, ETA:APOAPSIS, pitch_adjustment).
    } ELSE {
        PRINT "Not enough DeltaV to safely circularize orbit." AT (0, 34).
    }
}

// === Main Script ===
SET MODE TO 0.

//PRINT "Countdown:" AT (0, 12).
//LOCAL countdown IS 3.
//UNTIL countdown = 0 {
//    PRINT "T-" + countdown AT (0, 13).
//    SET countdown TO countdown - 1.
//    WAIT 1.
//}

//PRINT "LIFTOFF!" AT (0, 13).

Mode0_Prelaunch().
Mode1_Launch().
Mode2_Circ().
Mode3_FinalOrbit().

UNTIL FALSE {
    WAIT 0.1. 
}