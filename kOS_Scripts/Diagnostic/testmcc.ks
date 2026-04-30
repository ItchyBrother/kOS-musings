@LAZYGLOBAL OFF.

RUNONCEPATH("0:/lib/utils.ks").

// Same prediction function (we'll use it even if it's wrong - consistency is key)
FUNCTION PREDICT_LANDING_COORDINATES {
    IF NOT (SHIP:BODY = KERBIN) {
        PRINT "ERROR: Not in Kerbin SOI!".
        RETURN LEXICON("lat", 0, "lng", 0, "valid", FALSE).
    }
    
    LOCAL pe_eta IS ETA:PERIAPSIS.
    LOCAL pe_time IS TIME:SECONDS + pe_eta.
    
    LOCAL ship_pos IS POSITIONAT(SHIP, pe_time).
    LOCAL kerbin_pos IS POSITIONAT(KERBIN, pe_time).
    LOCAL pe_rel IS ship_pos - kerbin_pos.
    
    LOCAL geo IS KERBIN:GEOPOSITIONOF(pe_rel).
    
    LOCAL rotation_degrees IS (pe_eta / KERBIN:ROTATIONPERIOD) * 360.
    LOCAL landing_lng IS geo:LNG - rotation_degrees.
    
    UNTIL landing_lng >= -180 { SET landing_lng TO landing_lng + 360. }
    UNTIL landing_lng <= 180 { SET landing_lng TO landing_lng - 360. }
    
    RETURN LEXICON("lat", geo:LAT, "lng", landing_lng, "valid", TRUE).
}

FUNCTION RUN_CALIBRATION_TEST {
    PARAMETER test_name, normal_dv, prograde_dv.
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  MCC CALIBRATION TEST                          ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    PRINT "TEST: " + test_name.
    PRINT "  Normal dV:    " + normal_dv + " m/s".
    PRINT "  Prograde dV:  " + prograde_dv + " m/s".
    PRINT " ".
    
    // Measure BEFORE
    LOCAL before IS PREDICT_LANDING_COORDINATES().
    
    IF NOT before["valid"] {
        PRINT "ERROR: Not in Kerbin SOI!".
        RETURN.
    }
    
    PRINT "BEFORE BURN:".
    PRINT "  Landing prediction: " + ROUND(before["lat"], 2) + "° / " + ROUND(before["lng"], 2) + "°".
    PRINT "  Pe altitude:        " + ROUND(SHIP:PERIAPSIS/1000, 1) + " km".
    PRINT "  Ap altitude:        " + ROUND(SHIP:APOAPSIS/1000, 1) + " km".
    PRINT "  Period:             " + ROUND(SHIP:ORBIT:PERIOD/3600, 2) + " hours".
    PRINT " ".
    
    PRINT "Press (P) to proceed with test burn, (X) to skip...".
    
    LOCAL proceed IS FALSE.
    UNTIL proceed {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
            IF ch = "P" {
                SET proceed TO TRUE.
            } ELSE IF ch = "X" {
                PRINT "Test skipped.".
                RETURN.
            }
        }
        WAIT 0.1.
    }
    
    // Create test node
    LOCAL test_node IS NODE(TIME:SECONDS + 30, normal_dv, 0, prograde_dv).
    ADD test_node.
    
    PRINT "Executing test burn in 30 seconds...".
    PRINT " ".
    
    // Determine if we need main engine
    LOCAL total_dv IS SQRT(normal_dv^2 + prograde_dv^2).
    LOCAL use_engine IS total_dv > 5.
    
    IF use_engine {
        EXECUTE_NODE(TRUE, 7).  // Use SM engine
    } ELSE {
        EXECUTE_NODE(FALSE, 0).  // RCS only
    }
    
    WAIT 2.
    
    // Measure AFTER
    LOCAL after IS PREDICT_LANDING_COORDINATES().
    
    PRINT " ".
    PRINT "AFTER BURN:".
    PRINT "  Landing prediction: " + ROUND(after["lat"], 2) + "° / " + ROUND(after["lng"], 2) + "°".
    PRINT "  Pe altitude:        " + ROUND(SHIP:PERIAPSIS/1000, 1) + " km".
    PRINT "  Ap altitude:        " + ROUND(SHIP:APOAPSIS/1000, 1) + " km".
    PRINT "  Period:             " + ROUND(SHIP:ORBIT:PERIOD/3600, 2) + " hours".
    PRINT " ".
    
    // Calculate changes
    LOCAL dlat IS after["lat"] - before["lat"].
    LOCAL dlng IS after["lng"] - before["lng"].
    
    // Handle longitude wraparound
    IF dlng > 180 { SET dlng TO dlng - 360. }
    IF dlng < -180 { SET dlng TO dlng + 360. }
    
    PRINT "═══════════════════════════════════════════════".
    PRINT "RESULTS:".
    PRINT "  Latitude change:    " + ROUND(dlat, 2) + "°".
    PRINT "  Longitude change:   " + ROUND(dlng, 2) + "°".
    PRINT " ".
    
    IF normal_dv <> 0 {
        PRINT "  Lat per m/s:        " + ROUND(dlat / normal_dv, 3) + "°/m/s".
    }
    IF prograde_dv <> 0 {
        PRINT "  Lng per m/s:        " + ROUND(dlng / prograde_dv, 3) + "°/m/s".
    }
    
    PRINT "═══════════════════════════════════════════════".
    PRINT " ".
    PRINT "Record these results!".
    PRINT " ".
    PRINT "Press any key to continue...".
    TERMINAL:INPUT:GETCHAR().
}

FUNCTION MAIN {
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  MCC CALIBRATION PROGRAM                       ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    PRINT "This program will run systematic tests to measure".
    PRINT "how burns affect landing coordinates.".
    PRINT " ".
    PRINT "RECOMMENDED TEST SEQUENCE:".
    PRINT "  1. +10 m/s prograde (how does longitude change?)".
    PRINT "  2. -10 m/s retrograde (reverse test)".
    PRINT "  3. +10 m/s normal (how does latitude change?)".
    PRINT "  4. -10 m/s anti-normal (reverse test)".
    PRINT " ".
    PRINT "Record ALL results to build correction formulas.".
    PRINT " ".
    PRINT "IMPORTANT: You need enough propellant for ~40 m/s".
    PRINT "           of testing (4 burns).".
    PRINT " ".
    PRINT "Press (P) to begin test sequence, (X) to exit...".
    
    LOCAL start IS FALSE.
    UNTIL start {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
            IF ch = "P" {
                SET start TO TRUE.
            } ELSE IF ch = "X" {
                PRINT "Calibration cancelled.".
                RETURN.
            }
        }
        WAIT 0.1.
    }
    
    // Run test sequence
    RUN_CALIBRATION_TEST("TEST 1: +10 m/s Prograde", 0, 10).
    RUN_CALIBRATION_TEST("TEST 2: -10 m/s Retrograde", 0, -10).
    RUN_CALIBRATION_TEST("TEST 3: +10 m/s Normal", 10, 0).
    RUN_CALIBRATION_TEST("TEST 4: -10 m/s Anti-Normal", -10, 0).
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  CALIBRATION COMPLETE                          ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    PRINT "Review your results and calculate:".
    PRINT " ".
    PRINT "  degrees_per_prograde_ms = average from tests 1&2".
    PRINT "  degrees_per_normal_ms = average from tests 3&4".
    PRINT " ".
    PRINT "Use these values in the MCC correction formulas!".
    PRINT " ".
    
    WAIT 5.
}

MAIN().