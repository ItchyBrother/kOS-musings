@LAZYGLOBAL OFF.

RUNONCEPATH("0:/lib/utils.ks").

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

FUNCTION GREAT_CIRCLE_DISTANCE {
    PARAMETER lat1, lng1, lat2, lng2.
    LOCAL lat1_rad IS lat1 * CONSTANT:DEGTORAD.
    LOCAL lat2_rad IS lat2 * CONSTANT:DEGTORAD.
    LOCAL dlng_rad IS (lng2 - lng1) * CONSTANT:DEGTORAD.
    LOCAL a IS SIN((lat2_rad - lat1_rad)/2)^2 + COS(lat1_rad) * COS(lat2_rad) * SIN(dlng_rad/2)^2.
    LOCAL c IS 2 * ARCTAN2(SQRT(a), SQRT(1-a)).
    RETURN KERBIN:RADIUS * c.
}

FUNCTION EXECUTE_MCC {
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  MID-COURSE CORRECTION - PHASED APPROACH      ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    // Recovery zones
    LOCAL zones IS LIST(
        LEXICON("name", "KSC Atlantic", "lat", 0, "lng", -73),
        LEXICON("name", "Nye Island", "lat", 5.7, "lng", 108.7),
        LEXICON("name", "Sandy Island", "lat", -8.2, "lng", -42.5),
        LEXICON("name", "Hazard Shallows", "lat", -14, "lng", 155.3)
    ).
    
    // Get current trajectory
    LOCAL current IS PREDICT_LANDING_COORDINATES().
    
    IF NOT current["valid"] {
        PRINT "Cannot predict landing - not in Kerbin SOI!".
        RETURN.
    }
    
    PRINT "CURRENT TRAJECTORY:".
    PRINT "  Landing: " + ROUND(current["lat"], 1) + "° / " + ROUND(current["lng"], 1) + "°".
    PRINT "  Pe:      " + ROUND(SHIP:PERIAPSIS/1000, 1) + " km".
    PRINT "  Ap:      " + ROUND(SHIP:APOAPSIS/1000, 1) + " km".
    PRINT " ".
    
    // Show zones
    PRINT "RECOVERY ZONES:".
    LOCAL zone_num IS 1.
    FOR zone IN zones {
        LOCAL dist IS GREAT_CIRCLE_DISTANCE(
            current["lat"], current["lng"],
            zone["lat"], zone["lng"]
        ).
        PRINT "  (" + zone_num + ") " + zone["name"] + ": " + ROUND(dist/1000, 0) + " km".
        SET zone_num TO zone_num + 1.
    }
    
    PRINT " ".
    PRINT "Select target (1-4) or (X) to exit: ".
    
    LOCAL selection IS -1.
    LOCAL selected IS FALSE.
    
    UNTIL selected {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
            IF ch = "X" {
                PRINT "MCC cancelled.".
                RETURN.
            } ELSE IF ch >= "1" AND ch <= "4" {
                SET selection TO ch:TOSCALAR(0) - "1":TOSCALAR(0).
                SET selected TO TRUE.
            }
        }
        WAIT 0.1.
    }
    
    LOCAL target_zone IS zones[selection].
    PRINT "Selected: " + target_zone["name"].
    WAIT 1.
    
    // ═══════════════════════════════════════════════════════
    // PHASE 1: LONGITUDE CORRECTION
    // ═══════════════════════════════════════════════════════
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  PHASE 1: LONGITUDE CORRECTION                 ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    LOCAL dlng IS target_zone["lng"] - current["lng"].
    
    // Normalize to shortest path
    IF dlng > 180 { SET dlng TO dlng - 360. }
    IF dlng < -180 { SET dlng TO dlng + 360. }
    
    PRINT "Current longitude:  " + ROUND(current["lng"], 1) + "°".
    PRINT "Target longitude:   " + ROUND(target_zone["lng"], 1) + "°".
    PRINT "Difference:         " + ROUND(dlng, 1) + "°".
    PRINT " ".
    
    // EMPIRICAL: 1 m/s prograde = +0.156° longitude (EAST)
    LOCAL lng_dv IS dlng / 0.156.
    
    // Cap at reasonable value
    SET lng_dv TO MAX(-80, MIN(80, lng_dv)).
    
    PRINT "Calculated correction: " + ROUND(lng_dv, 1) + " m/s prograde".
    
    IF lng_dv > 0 {
        PRINT "  (Prograde = shift EAST)".
    } ELSE {
        PRINT "  (Retrograde = shift WEST)".
    }
    
    PRINT " ".
    PRINT "WARNING: This will change Pe altitude!".
    PRINT "         (We'll fix it in Phase 2)".
    PRINT " ".
    
    IF ABS(lng_dv) < 2 {
        PRINT "Longitude already very close - skipping Phase 1.".
        WAIT 2.
    } ELSE {
        PRINT "(P) PROCEED   (S) SKIP   (X) ABORT".
        
        SET selected TO FALSE.
        LOCAL skip_phase1 IS FALSE.
        
        UNTIL selected {
            IF TERMINAL:INPUT:HASCHAR {
                LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
                IF ch = "P" {
                    SET selected TO TRUE.
                } ELSE IF ch = "S" {
                    SET skip_phase1 TO TRUE.
                    SET selected TO TRUE.
                } ELSE IF ch = "X" {
                    PRINT "MCC aborted.".
                    RETURN.
                }
            }
            WAIT 0.1.
        }
        
        IF NOT skip_phase1 {
            // Create and execute longitude correction node
            LOCAL lng_node IS NODE(TIME:SECONDS + 60, 0, 0, lng_dv).
            ADD lng_node.
            
            PRINT " ".
            PRINT "Executing longitude correction...".
            
            LOCAL use_engine IS ABS(lng_dv) > 15.
            EXECUTE_NODE(use_engine, 7).
            
            WAIT 2.
            
            // Get new trajectory
            SET current TO PREDICT_LANDING_COORDINATES().
            
            PRINT " ".
            PRINT "After Phase 1:".
            PRINT "  New landing: " + ROUND(current["lat"], 1) + "° / " + ROUND(current["lng"], 1) + "°".
            PRINT "  New Pe:      " + ROUND(SHIP:PERIAPSIS/1000, 1) + " km".
            
            WAIT 3.
        }
    }
    
// ═══════════════════════════════════════════════════════
// PHASE 2: PE RESTORATION
// ═══════════════════════════════════════════════════════

CLEARSCREEN.
PRINT "╔════════════════════════════════════════════════╗".
PRINT "║  PHASE 2: PE RESTORATION                       ║".
PRINT "╚════════════════════════════════════════════════╝".
PRINT " ".

LOCAL current_pe IS SHIP:PERIAPSIS.
LOCAL target_pe IS 32000.  // Target 32 km
LOCAL pe_error IS current_pe - target_pe.

PRINT "Current Pe:  " + ROUND(current_pe/1000, 1) + " km".
PRINT "Target Pe:   " + ROUND(target_pe/1000, 1) + " km".
PRINT "Error:       " + ROUND(pe_error/1000, 1) + " km".
PRINT " ".

IF ABS(pe_error) < 3000 {
    PRINT "Pe already acceptable (within ±3 km) - skipping Phase 2.".
    WAIT 2.
} ELSE {
    // Burn at CURRENT position (we're inbound to Pe)
    // Retrograde lowers Pe, Prograde raises Pe
    // Rough estimate: adjust as needed based on testing
    LOCAL pe_dv IS -(pe_error / 1000) * 1.0.  // May need tuning
    
    // Cap it
    SET pe_dv TO MAX(-60, MIN(60, pe_dv)).
    
    PRINT "Calculated correction: " + ROUND(pe_dv, 1) + " m/s NOW".
    
    IF pe_error > 0 {
        PRINT "  (Pe too high - burn retrograde to lower)".
    } ELSE {
        PRINT "  (Pe too low - burn prograde to raise)".
    }
    
    PRINT " ".
    PRINT "NOTE: This will shift longitude slightly (~" + ROUND(ABS(pe_dv) * 0.156, 1) + "°)".
    PRINT " ".
    PRINT "(P) PROCEED   (S) SKIP   (X) ABORT".
    
    SET selected TO FALSE.
    LOCAL skip_phase2 IS FALSE.
    
    UNTIL selected {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
            IF ch = "P" {
                SET selected TO TRUE.
            } ELSE IF ch = "S" {
                SET skip_phase2 TO TRUE.
                SET selected TO TRUE.
            } ELSE IF ch = "X" {
                PRINT "MCC aborted.".
                RETURN.
            }
        }
        WAIT 0.1.
    }
    
    IF NOT skip_phase2 {
        // Create node at current position + 60 seconds
        LOCAL pe_node IS NODE(TIME:SECONDS + 60, 0, 0, pe_dv).
        ADD pe_node.
        
        PRINT " ".
        PRINT "Executing Pe restoration...".
        
        LOCAL use_engine IS ABS(pe_dv) > 15.
        EXECUTE_NODE(use_engine, 7).
        
        WAIT 2.
        
        // Get new trajectory
        SET current TO PREDICT_LANDING_COORDINATES().
        
        PRINT " ".
        PRINT "After Phase 2:".
        PRINT "  New landing: " + ROUND(current["lat"], 1) + "° / " + ROUND(current["lng"], 1) + "°".
        PRINT "  New Pe:      " + ROUND(SHIP:PERIAPSIS/1000, 1) + " km".
        
        WAIT 3.
    }
}
    
    // ═══════════════════════════════════════════════════════
    // PHASE 3: LATITUDE CORRECTION
    // ═══════════════════════════════════════════════════════
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  PHASE 3: LATITUDE CORRECTION                  ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    LOCAL dlat IS target_zone["lat"] - current["lat"].
    
    PRINT "Current latitude:   " + ROUND(current["lat"], 1) + "°".
    PRINT "Target latitude:    " + ROUND(target_zone["lat"], 1) + "°".
    PRINT "Difference:         " + ROUND(dlat, 1) + "°".
    PRINT " ".
    
    // EMPIRICAL: 1 m/s normal = -0.338° latitude (sign flipped)
    LOCAL lat_dv IS dlat / (-0.338).
    
    // Cap it
    SET lat_dv TO MAX(-40, MIN(40, lat_dv)).
    
    PRINT "Calculated correction: " + ROUND(lat_dv, 1) + " m/s normal".
    
    IF lat_dv > 0 {
        PRINT "  (Normal = shift SOUTH due to sign flip)".
    } ELSE {
        PRINT "  (Anti-normal = shift NORTH)".
    }
    
    PRINT " ".
    PRINT "NOTE: Minimal Pe impact from this burn.".
    PRINT " ".
    
    IF ABS(lat_dv) < 2 {
        PRINT "Latitude already very close - skipping Phase 3.".
        WAIT 2.
    } ELSE {
        PRINT "(P) PROCEED   (S) SKIP   (X) ABORT".
        
        SET selected TO FALSE.
        LOCAL skip_phase3 IS FALSE.
        
        UNTIL selected {
            IF TERMINAL:INPUT:HASCHAR {
                LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
                IF ch = "P" {
                    SET selected TO TRUE.
                } ELSE IF ch = "S" {
                    SET skip_phase3 TO TRUE.
                    SET selected TO TRUE.
                } ELSE IF ch = "X" {
                    PRINT "MCC aborted.".
                    RETURN.
                }
            }
            WAIT 0.1.
        }
        
        IF NOT skip_phase3 {
            // Create latitude correction node
            LOCAL lat_node IS NODE(TIME:SECONDS + 60, lat_dv, 0, 0).
            ADD lat_node.
            
            PRINT " ".
            PRINT "Executing latitude correction...".
            
            LOCAL use_engine IS ABS(lat_dv) > 15.
            EXECUTE_NODE(use_engine, 7).
            
            WAIT 2.
        }
    }
    
    // ═══════════════════════════════════════════════════════
    // FINAL RESULTS
    // ═══════════════════════════════════════════════════════
    
    SET current TO PREDICT_LANDING_COORDINATES().
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  MCC COMPLETE                                  ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    PRINT "FINAL TRAJECTORY:".
    PRINT "  Landing: " + ROUND(current["lat"], 1) + "° / " + ROUND(current["lng"], 1) + "°".
    PRINT "  Pe:      " + ROUND(SHIP:PERIAPSIS/1000, 1) + " km".
    PRINT " ".
    
    PRINT "TARGET: " + target_zone["name"].
    PRINT "  Coords:  " + ROUND(target_zone["lat"], 1) + "° / " + ROUND(target_zone["lng"], 1) + "°".
    PRINT " ".
    
    LOCAL final_dist IS GREAT_CIRCLE_DISTANCE(
        current["lat"], current["lng"],
        target_zone["lat"], target_zone["lng"]
    ).
    
    PRINT "MISS DISTANCE: " + ROUND(final_dist/1000, 0) + " km".
    PRINT " ".
    
    IF final_dist < 300000 {
        PRINT "✓ EXCELLENT - Within direct recovery range!".
    } ELSE IF final_dist < 800000 {
        PRINT "✓ GOOD - Recoverable with some effort.".
    } ELSE IF final_dist < 2000000 {
        PRINT "⚠ FAIR - Consider another MCC iteration.".
    } ELSE {
        PRINT "⚠ POOR - Major error, needs investigation.".
    }
    
    PRINT " ".
    PRINT "Run MCC again if refinement needed.".
    
    WAIT 5.
}

FUNCTION MAIN {
    EXECUTE_MCC().
}

MAIN().