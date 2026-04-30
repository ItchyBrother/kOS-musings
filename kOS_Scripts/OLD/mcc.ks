@LAZYGLOBAL OFF.

RUNONCEPATH("0:/lib/utils.ks").

// =====================================================
// CONFIGURATION
// =====================================================

GLOBAL TARGET_PE_ALT IS 30000.  // Target Pe altitude (30 km optimal)
GLOBAL ATMOSPHERIC_CORRECTION IS 31.  // Degrees correction for atmospheric descent

// Recovery zones
GLOBAL RECOVERY_ZONES IS LIST(
    LEXICON("name", "KSC Atlantic", "lat", 0, "lng", -73),
    LEXICON("name", "Nye Island", "lat", 5.7, "lng", 108.7),
    LEXICON("name", "Sandy Island", "lat", -8.2, "lng", -42.5),
    LEXICON("name", "Hazard Shallows", "lat", -14, "lng", 155.3)
).

// =====================================================
// UTILITY FUNCTIONS
// =====================================================

FUNCTION normalize_angle {
    PARAMETER angle.
    SET angle TO MOD(angle, 360).
    IF angle < 0 { SET angle TO angle + 360. }
    RETURN angle.
}

FUNCTION normalize_longitude {
    PARAMETER lng.
    UNTIL lng >= -180 { SET lng TO lng + 360. }
    UNTIL lng <= 180 { SET lng TO lng - 360. }
    RETURN lng.
}

// =====================================================
// LANDING PREDICTION - KERBIN SOI
// =====================================================

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
    
    // Calculate rotation using FULL ETA (prevents "rotation = 0" bug)
    LOCAL total_hours IS pe_eta / 3600.
    LOCAL total_rotation_degrees IS total_hours * 60.
    LOCAL rotation_degrees IS MOD(total_rotation_degrees, 360).
    
    // Calculate velocity at Pe to adjust atmospheric correction
    LOCAL v_at_pe IS SQRT(KERBIN:MU * (2/(KERBIN:RADIUS + SHIP:PERIAPSIS) - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
    
    // Scale atmospheric correction based on approach velocity
    LOCAL base_velocity IS 2800.
    LOCAL velocity_scale IS base_velocity / v_at_pe.
    LOCAL atmospheric_correction IS ATMOSPHERIC_CORRECTION * velocity_scale.
    
    // Landing longitude with velocity-adjusted atmospheric correction
    LOCAL landing_lng IS normalize_longitude(geo:LNG - rotation_degrees + atmospheric_correction).
    
    RETURN LEXICON(
        "lat", geo:LAT, 
        "lng", landing_lng, 
        "valid", TRUE,
        "pe_lng", geo:LNG,
        "rotation", rotation_degrees,
        "atmo_correction", atmospheric_correction,
        "velocity_at_pe", v_at_pe,
        "is_eccentric", SHIP:ORBIT:APOAPSIS > 1000000
    ).
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

// =====================================================
// MUN ORBIT PLANNING
// =====================================================

FUNCTION calculate_solar_angle_at_landing {
    PARAMETER landing_lat, landing_lng, arrival_time.
    
    // Get absolute longitude at landing time
    LOCAL kerbin_rotation_angle IS normalize_angle((arrival_time / KERBIN:ROTATIONPERIOD) * 360).
    LOCAL absolute_lng IS normalize_angle(landing_lng + kerbin_rotation_angle).
    
    // Get landing position
    LOCAL landing_geo IS KERBIN:GEOPOSITIONLATLNG(landing_lat, absolute_lng).
    LOCAL landing_pos IS landing_geo:POSITION.
    
    // Sun direction relative to landing site
    LOCAL sun_dir IS (SUN:POSITION - (KERBIN:POSITION + landing_pos)):NORMALIZED.
    LOCAL surface_normal IS landing_pos:NORMALIZED.
    
    // Calculate solar elevation
    LOCAL cos_angle IS VDOT(surface_normal, sun_dir).
    LOCAL solar_elev IS 90 - ARCCOS(MAX(-1, MIN(1, cos_angle))).
    
    RETURN solar_elev.
}

FUNCTION get_time_of_day_string {
    PARAMETER solar_elev.
    
    IF solar_elev > 40 {
        RETURN "daylight".
    } ELSE IF solar_elev > 10 {
        RETURN "late afternoon".
    } ELSE IF solar_elev > -5 {
        RETURN "sunset".
    } ELSE IF solar_elev > -18 {
        RETURN "twilight".
    } ELSE {
        RETURN "night".
    }
}

FUNCTION calculate_return_options_from_mun {
    IF SHIP:BODY <> MUN {
        PRINT "ERROR: Must be in Mun orbit!".
        RETURN LIST().
    }
    
    PRINT "Analyzing return trajectories...".
    PRINT " ".
    
    // Current orbit info
    LOCAL mun_orbit_period IS SHIP:ORBIT:PERIOD.
    
    // Calculate Hohmann transfer
    LOCAL r1 IS MUN:ORBIT:SEMIMAJORAXIS.
    LOCAL r2 IS KERBIN:RADIUS + TARGET_PE_ALT.
    LOCAL a_transfer IS (r1 + r2) / 2.
    LOCAL transfer_time IS CONSTANT:PI * SQRT(a_transfer^3 / KERBIN:MU).
    
    // Approximate time in Kerbin SOI before Pe
    LOCAL time_to_pe_in_soi IS 1800.  // ~30 minutes
    
    // Kerbin rotation during one Mun orbit
    LOCAL kerbin_rotation_per_orbit IS (mun_orbit_period / KERBIN:ROTATIONPERIOD) * 360.
    
    PRINT "Transfer time: " + ROUND(transfer_time/60, 1) + " minutes".
    PRINT "Mun orbit period: " + ROUND(mun_orbit_period/60, 1) + " minutes".
    PRINT "Kerbin rotation per Mun orbit: " + ROUND(kerbin_rotation_per_orbit, 1) + "°".
    PRINT " ".
    PRINT "Calculating landing windows...".
    PRINT " ".
    
    LOCAL options IS LIST().
    
    // For each landing site
    FOR zone IN RECOVERY_ZONES {
        LOCAL best_option IS LEXICON("error", 99999, "orbits", -1).
        
        // Check orbit delays 0-15
        FROM {LOCAL orbits IS 0.} UNTIL orbits > 15 STEP {SET orbits TO orbits + 1.} DO {
            // Departure time for this orbit delay
            LOCAL departure_time IS TIME:SECONDS + (orbits * mun_orbit_period).
            
            // Arrival at Kerbin SOI
            LOCAL arrival_kerbin_soi IS departure_time + transfer_time.
            
            // Pe time (approximate)
            LOCAL pe_time IS arrival_kerbin_soi + time_to_pe_in_soi.
            
            // Calculate Pe longitude at this time
            LOCAL kerbin_rotation_at_pe IS normalize_angle((pe_time / KERBIN:ROTATIONPERIOD) * 360).
            LOCAL pe_longitude IS 0.  // Will be at current Mun->Kerbin angle, but approximate
            
            // For simplicity, use current angle to Kerbin as baseline
            LOCAL to_kerbin IS KERBIN:POSITION - SHIP:POSITION.
            LOCAL base_angle IS ARCTAN2(to_kerbin:X, to_kerbin:Z).
            SET pe_longitude TO normalize_longitude(base_angle + (orbits * kerbin_rotation_per_orbit)).
            
            // Time to Pe from Pe position (for rotation calc)
            LOCAL time_to_pe_seconds IS time_to_pe_in_soi.
            LOCAL time_to_pe_hours IS FLOOR(time_to_pe_seconds / 3600).
            LOCAL time_to_pe_minutes IS FLOOR(MOD(time_to_pe_seconds, 3600) / 60).
            LOCAL rotation_degrees IS (time_to_pe_hours * 60) + (time_to_pe_minutes * 1).
            
            // Predicted landing longitude
            LOCAL landing_lng IS normalize_longitude(pe_longitude - rotation_degrees + ATMOSPHERIC_CORRECTION).
            
            // Error from target
            LOCAL target_lng IS zone["lng"].
            LOCAL lng_error IS ABS(landing_lng - target_lng).
            IF lng_error > 180 { SET lng_error TO 360 - lng_error. }
            
            // Track best option for this zone
            IF lng_error < best_option["error"] {
                // Calculate solar angle at landing
                LOCAL landing_time IS pe_time + rotation_degrees * 60.  // Approximate
                LOCAL solar_angle IS calculate_solar_angle_at_landing(zone["lat"], zone["lng"], landing_time).
                
                SET best_option TO LEXICON(
                    "zone", zone,
                    "orbits", orbits,
                    "error", lng_error,
                    "departure_time", departure_time,
                    "landing_time", landing_time,
                    "solar_angle", solar_angle,
                    "time_of_day", get_time_of_day_string(solar_angle)
                ).
            }
        }
        
        // Add best option for this zone
        IF best_option["orbits"] >= 0 {
            options:ADD(best_option).
        }
    }
    
    // Sort by orbit delay (earliest first)
    LOCAL sorted IS LIST().
    UNTIL options:LENGTH = 0 {
        LOCAL earliest_idx IS 0.
        LOCAL earliest_orbits IS options[0]["orbits"].
        FROM {LOCAL i IS 1.} UNTIL i >= options:LENGTH STEP {SET i TO i + 1.} DO {
            IF options[i]["orbits"] < earliest_orbits {
                SET earliest_idx TO i.
                SET earliest_orbits TO options[i]["orbits"].
            }
        }
        sorted:ADD(options[earliest_idx]).
        options:REMOVE(earliest_idx).
    }
    
    RETURN sorted.
}

FUNCTION display_return_menu {
    PARAMETER options.
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  MUN RETURN PLANNING                           ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    PRINT "Current Status:".
    PRINT "  Altitude: " + ROUND(SHIP:ALTITUDE/1000, 1) + " km".
    PRINT "  Orbit Period: " + ROUND(SHIP:ORBIT:PERIOD/60, 1) + " minutes".
    PRINT " ".
    
    PRINT "═════════════════════════════════════════════════".
    PRINT "LANDING SITE OPTIONS".
    PRINT "═════════════════════════════════════════════════".
    PRINT " ".
    
    LOCAL option_num IS 1.
    FOR opt IN options {
        LOCAL zone IS opt["zone"].
        LOCAL orbits_text IS "".
        IF opt["orbits"] = 0 {
            SET orbits_text TO "Now".
        } ELSE {
            LOCAL orbit_word IS " orbit".
            IF opt["orbits"] > 1 { SET orbit_word TO " orbits". }
            SET orbits_text TO opt["orbits"] + orbit_word.
        }
        
        LOCAL time_eta IS opt["departure_time"] - TIME:SECONDS.
        
        PRINT "(" + option_num + ") " + zone["name"].
        PRINT "    Delay: " + orbits_text + " (T+" + ROUND(time_eta/60, 0) + "m)".
        PRINT "    Landing: " + opt["time_of_day"] + " (" + ROUND(opt["solar_angle"], 0) + "° sun)".
        PRINT "    Accuracy: " + ROUND(opt["error"], 1) + "° from target".
        PRINT " ".
        
        SET option_num TO option_num + 1.
    }
    
    PRINT "═════════════════════════════════════════════════".
    PRINT " ".
    PRINT "Select option (1-" + options:LENGTH + ") or (X) to cancel: ".
    
    RETURN options.
}

FUNCTION create_return_maneuver {
    PARAMETER option.
    
    CLEARSCREEN.
    PRINT "═════════════════════════════════════════".
    PRINT "RETURN BURN GUIDANCE".
    PRINT "═════════════════════════════════════════".
    PRINT " ".
    PRINT "Target: " + option["zone"]["name"].
    PRINT "Orbit Delay: " + option["orbits"] + " orbits".
    PRINT "Departure: T+" + ROUND((option["departure_time"] - TIME:SECONDS)/60, 0) + " minutes".
    PRINT "Landing: " + option["time_of_day"].
    PRINT " ".
    
    // Estimate delta-v needed
    LOCAL r_orbit IS SHIP:ORBIT:SEMIMAJORAXIS.
    LOCAL v_circular IS SQRT(MUN:MU / r_orbit).
    LOCAL v_escape IS SQRT(2 * MUN:MU / r_orbit).
    LOCAL dv_estimate IS (v_escape * 0.92) - v_circular.
    
    PRINT "MANUAL NODE CREATION INSTRUCTIONS:".
    PRINT "═════════════════════════════════════════".
    PRINT " ".
    PRINT "1. Wait until T+" + ROUND((option["departure_time"] - TIME:SECONDS)/60, 0) + " minutes".
    PRINT "   (or create node now for that time)".
    PRINT " ".
    PRINT "2. Create maneuver node at departure time:".
    PRINT "   - Start with ~" + ROUND(ABS(dv_estimate), 0) + " m/s RETROGRADE".
    PRINT "   - Adjust until you see Kerbin intercept".
    PRINT "   - Target Pe at Kerbin: 25-35 km".
    PRINT " ".
    PRINT "3. Fine-tune the node:".
    PRINT "   - Move node time earlier/later for better geometry".
    PRINT "   - Adjust prograde/retrograde for Pe altitude".
    PRINT "   - May need " + ROUND(ABS(dv_estimate)-20, 0) + "-" + ROUND(ABS(dv_estimate)+20, 0) + " m/s total".
    PRINT " ".
    PRINT "4. Execute when ready.".
    PRINT " ".
    PRINT "TIP: Burn when Mun is on the 'trailing' side of".
    PRINT "     its orbit around Kerbin (slows you down relative".
    PRINT "     to Kerbin, causing you to fall inward).".
    PRINT " ".
    PRINT "═════════════════════════════════════════".
    PRINT " ".
    PRINT "Create a placeholder node at departure time? (Y/N): ".
    
    LOCAL create_placeholder IS FALSE.
    UNTIL FALSE {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
            IF ch = "Y" {
                SET create_placeholder TO TRUE.
                BREAK.
            } ELSE IF ch = "N" {
                PRINT "Create node manually when ready.".
                PRINT " ".
                PRINT "Remember:".
                PRINT "  - Depart at T+" + ROUND((option["departure_time"] - TIME:SECONDS)/60, 0) + "m".
                PRINT "  - Target " + option["zone"]["name"].
                PRINT "  - Landing: " + option["time_of_day"].
                RETURN.
            }
        }
        WAIT 0.1.
    }
    
    IF create_placeholder {
        // Create a starting point node that user must adjust
        LOCAL node_time IS option["departure_time"].
        IF node_time < TIME:SECONDS + 60 {
            SET node_time TO TIME:SECONDS + 60.
        }
        
        // Start with rough estimate - user MUST adjust this
        LOCAL placeholder_node IS NODE(node_time, 0, 0, dv_estimate).
        ADD placeholder_node.
        
        PRINT " ".
        PRINT "Placeholder node created!".
        PRINT " ".
        PRINT "⚠ IMPORTANT: This is just a starting point!".
        PRINT "   You MUST adjust the node to get a Kerbin intercept.".
        PRINT " ".
        PRINT "   - Click on node to edit".
        PRINT "   - Adjust prograde/retrograde".
        PRINT "   - Move node time if needed".
        PRINT "   - Look for Kerbin intercept with Pe 25-35 km".
        PRINT " ".
        PRINT "Once you have a good intercept, execute the node.".
    }
}

// =====================================================
// MID-COURSE CORRECTION (KERBIN SOI)
// =====================================================

FUNCTION EXECUTE_MCC {
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  MID-COURSE CORRECTION - PHASED APPROACH      ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
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
    IF current["is_eccentric"] {
        PRINT "  ⚠ Eccentric orbit - prediction accuracy reduced".
    }
    PRINT " ".
    PRINT "PREDICTION METHOD:".
    PRINT "  Pe longitude: " + ROUND(current["pe_lng"], 1) + "°".
    PRINT "  - Rotation: " + ROUND(current["rotation"], 1) + "°".
    PRINT "  + Atmospheric: +" + ROUND(current["atmo_correction"], 1) + "°".
    PRINT "    (adjusted for " + ROUND(current["velocity_at_pe"], 0) + " m/s)".
    PRINT " ".
    
    // Show zones
    PRINT "RECOVERY ZONES:".
    LOCAL zone_num IS 1.
    FOR zone IN RECOVERY_ZONES {
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
    
    LOCAL target_zone IS RECOVERY_ZONES[selection].
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
    LOCAL target_pe IS TARGET_PE_ALT.
    LOCAL pe_error IS current_pe - target_pe.
    
    PRINT "Current Pe:  " + ROUND(current_pe/1000, 1) + " km".
    PRINT "Target Pe:   " + ROUND(target_pe/1000, 1) + " km".
    PRINT "Error:       " + ROUND(pe_error/1000, 1) + " km".
    PRINT " ".
    
    IF ABS(pe_error) < 3000 {
        PRINT "Pe already acceptable (within ±3 km) - skipping Phase 2.".
        WAIT 2.
    } ELSE {
        LOCAL pe_dv IS -(pe_error / 1000) * 1.0.
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
            LOCAL pe_node IS NODE(TIME:SECONDS + 60, 0, 0, pe_dv).
            ADD pe_node.
            
            PRINT " ".
            PRINT "Executing Pe restoration...".
            
            LOCAL use_engine IS ABS(pe_dv) > 15.
            EXECUTE_NODE(use_engine, 7).
            
            WAIT 2.
            
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
    PRINT "Prediction used: Pe_lng - rotation + atmo_correction".
    PRINT "  (Atmospheric correction scaled by approach velocity)".
    PRINT " ".
    PRINT "NOTE: MCC corrections can affect prediction accuracy.".
    PRINT "      Typical error with corrections: ±5-10°".
    PRINT "      Eccentric orbits: ±10-15°".
    PRINT "      For best accuracy, minimize burns and circularize.".
    
    WAIT 5.
}

// =====================================================
// MAIN PROGRAM
// =====================================================

FUNCTION MAIN {
    IF SHIP:BODY = MUN {
        // Planning mode from Mun orbit
        LOCAL options IS calculate_return_options_from_mun().
        
        IF options:LENGTH = 0 {
            PRINT "ERROR: Could not calculate return options.".
            RETURN.
        }
        
        display_return_menu(options).
        
        // Wait for selection
        LOCAL selected IS FALSE.
        LOCAL selection IS -1.
        
        UNTIL selected {
            IF TERMINAL:INPUT:HASCHAR {
                LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
                IF ch = "X" {
                    PRINT "Return planning cancelled.".
                    RETURN.
                } ELSE IF ch >= "1" AND ch <= options:LENGTH:TOSTRING() {
                    SET selection TO ch:TOSCALAR(0) - "1":TOSCALAR(0).
                    SET selected TO TRUE.
                }
            }
            WAIT 0.1.
        }
        
        LOCAL chosen_option IS options[selection].
        PRINT "Selected: " + chosen_option["zone"]["name"].
        WAIT 1.
        
        // Create maneuver node
        create_return_maneuver(chosen_option).
        
    } ELSE IF SHIP:BODY = KERBIN {
        // MCC mode in Kerbin SOI
        EXECUTE_MCC().
    } ELSE {
        PRINT "ERROR: Must be in Mun or Kerbin SOI!".
    }
}

MAIN().
