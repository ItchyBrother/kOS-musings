@LAZYGLOBAL OFF.

RUNONCEPATH("0:/lib/utils.ks").

FUNCTION DISPLAY_HEADER {
    PARAMETER title.
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  APOLLO MISSION CONTROL - TKI PROGRAM          ║".
    PRINT "╠════════════════════════════════════════════════╣".
    LOCAL header_line IS "║  " + title.
    LOCAL padding IS 48 - title:LENGTH - 2.  // Adjust for "║  " and "║"
    SET header_line TO header_line + SPACESTRING(padding) + "║".
    PRINT header_line.
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
}

FUNCTION SPACESTRING {
    PARAMETER len.
    LOCAL s IS "".
    FROM {LOCAL i IS 0.} UNTIL i >= len STEP {SET i TO i + 1.} DO {
        SET s TO s + " ".
    }
    RETURN s.
}

// Calculate great circle distance between two lat/lng points
FUNCTION GREAT_CIRCLE_DISTANCE {
    PARAMETER lat1, lng1, lat2, lng2.
    LOCAL lat1_rad IS lat1 * CONSTANT:DEGTORAD.
    LOCAL lat2_rad IS lat2 * CONSTANT:DEGTORAD.
    LOCAL dlng_rad IS (lng2 - lng1) * CONSTANT:DEGTORAD.
    LOCAL a IS SIN((lat2_rad - lat1_rad)/2)^2 + COS(lat1_rad) * COS(lat2_rad) * SIN(dlng_rad/2)^2.
    LOCAL c IS 2 * ARCTAN2(SQRT(a), SQRT(1-a)).
    LOCAL distance IS KERBIN:RADIUS * c.
    RETURN distance.
}

// FIXED: Get Pe coordinates accounting for body rotation during Kerbin patch only
FUNCTION GET_PE_COORDINATES_AT_TIME {
    PARAMETER orbit_patch.
    
    // Time from NOW to Pe (on the Kerbin patch)
    LOCAL pe_eta IS orbit_patch:ETA:PERIAPSIS.
    
    // Time from NOW to entering Kerbin SOI (from CURRENT orbit)
    LOCAL entry_eta IS ETA:TRANSITION.
    
    // Time WITHIN Kerbin SOI (from entry to Pe)
    LOCAL timeDif IS pe_eta - entry_eta.  // NOW USES entry_eta
    
    PRINT "DEBUG: Entry in " + ROUND(entry_eta/3600, 2) + "h, Pe in " + ROUND(pe_eta/3600, 2) + "h, Within SOI: " + ROUND(timeDif/3600, 2) + "h".
    
    LOCAL pe_time IS TIME:SECONDS + pe_eta.
    LOCAL ship_pos IS POSITIONAT(SHIP, pe_time).
    LOCAL kerbin_pos IS POSITIONAT(KERBIN, pe_time).
    LOCAL pe_pos_rel IS ship_pos - kerbin_pos.
    
    LOCAL geo IS KERBIN:GEOPOSITIONOF(pe_pos_rel).
    
    LOCAL angle IS (timeDif / KERBIN:ROTATIONPERIOD) * 360.
    LOCAL corrected_lng IS geo:LNG - angle.
    
    // Normalize
    SET corrected_lng TO MOD(corrected_lng + 1080, 360) - 180.
    
    RETURN LEXICON("lat", geo:LAT, "lng", corrected_lng).
}

// Quick feasibility check for landing zones
FUNCTION CHECK_ZONE_FEASIBILITY {
    PARAMETER target_lat, target_lng, base_dv.
    
    PRINT "  Analyzing " + ROUND(target_lat, 1) + "°, " + ROUND(target_lng, 1) + "° (this takes a moment)...".
    
    LOCAL best_distance IS 999999999.
    LOCAL period IS SHIP:ORBIT:PERIOD.
    LOCAL time_step IS period / 36.  // Match main search resolution
    
    FROM {LOCAL offset IS 0.} UNTIL offset > period STEP {SET offset TO offset + time_step.} DO {
        LOCAL test_time IS TIME:SECONDS + offset.
        
        FROM {LOCAL dv_offset IS -60.} UNTIL dv_offset > 120 STEP {SET dv_offset TO dv_offset + 8.} DO {
            UNTIL NOT HASNODE {
                REMOVE NEXTNODE.
                WAIT 0.05.
            }
            
            LOCAL test_dv IS base_dv + dv_offset.
            LOCAL test_node IS NODE(test_time, 0, 0, test_dv).
            ADD test_node.
            WAIT 0.05.
            
            IF test_node:ORBIT:HASNEXTPATCH AND test_node:ORBIT:NEXTPATCH:BODY = KERBIN {
                LOCAL pe IS test_node:ORBIT:NEXTPATCH:PERIAPSIS.
                
                IF pe > 20000 AND pe < 40000 {
                    LOCAL pe_coords IS GET_PE_COORDINATES_AT_TIME(test_node:ORBIT:NEXTPATCH).
                    LOCAL distance IS GREAT_CIRCLE_DISTANCE(
                        pe_coords["lat"], pe_coords["lng"],
                        target_lat, target_lng
                    ).
                    
                    IF distance < best_distance {
                        SET best_distance TO distance.
                    }
                }
            }
            
            REMOVE test_node.
        }
    }
    
    UNTIL NOT HASNODE {
        REMOVE NEXTNODE.
    }
    
    RETURN best_distance.
}

FUNCTION MAIN {
    
    // Default parameters
    LOCAL target_kerbin_pe IS 30000.  // 30km target was 22380
    LOCAL pe_tolerance IS 2000.       // ±5km acceptable
    LOCAL use_landing_zone IS FALSE.
    LOCAL target_lat IS 0.
    LOCAL target_lng IS -73.
    LOCAL zone_name IS "KSC Atlantic".
    
    // Pre-defined landing zones
    LOCAL zones IS LIST(
        LEXICON("name", "KSC Atlantic", "lat", 0, "lng", -73, "desc", "Primary - KSC to Island waters"),
        LEXICON("name", "Nye Island", "lat", 5.7, "lng", 108.7, "desc", "Nye Island recovery area"),
        LEXICON("name", "Sandy Island", "lat", -8.2, "lng", -42.5, "desc", "Sandy Island site"),
        LEXICON("name", "Hazard Shallows", "lat", -14, "lng", 155.3, "desc", "Hazard Shallows site")
    ).
    
    // ═══════════════════════════════════════════════════════
    // ANALYZE ZONE FEASIBILITY
    // ═══════════════════════════════════════════════════════
    
    DISPLAY_HEADER("ANALYZING LANDING ZONES").
    
    SET TARGET TO KERBIN.
    ToggleEngine(7, FALSE).
    
    PRINT "Calculating base escape parameters...".
    LOCAL radius IS SHIP:ALTITUDE + SHIP:BODY:RADIUS.
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL v_current IS SQRT(mu / radius).
    LOCAL v_escape IS SQRT(2 * mu / radius).
    LOCAL base_dv IS (v_escape - v_current) + 80.
    PRINT "Base dV: " + ROUND(base_dv, 1) + " m/s".
    PRINT " ".
    
    PRINT "Checking landing zone feasibility from current orbit...".
    PRINT "(Thorough analysis - this will take 2-3 minutes)".
    PRINT " ".
    
    // Check each zone
    FOR zone IN zones {
        LOCAL distance IS CHECK_ZONE_FEASIBILITY(zone["lat"], zone["lng"], base_dv).
        SET zone["feasibility"] TO distance.
        
        LOCAL zstatus IS "".
        IF distance < 200000 {
            SET zstatus TO "EXCELLENT".
        } ELSE IF distance < 500000 {
            SET zstatus TO "GOOD".
        } ELSE IF distance < 1000000 {
            SET zstatus TO "POSSIBLE".
        } ELSE {
            SET zstatus TO "POOR".
        }
        SET zone["zstatus"] TO zstatus.
    }
    
    PRINT "Analysis complete!".
    WAIT 2.
    
    // ═══════════════════════════════════════════════════════
    // CONFIGURATION MENU
    // ═══════════════════════════════════════════════════════
    
    DISPLAY_HEADER("TKI CONFIGURATION").
    
    PRINT "TRANS-KERBIN INJECTION PARAMETERS".
    PRINT " ".
    PRINT "Current Settings:".
    PRINT "  Target Kerbin Pe:    " + ROUND(target_kerbin_pe/1000, 1) + " km".
    LOCAL mode_text IS "BASIC - Pe only".
    IF use_landing_zone {
        SET mode_text TO "SELECTED - " + zone_name.
    }
    PRINT "  Mode:                " + mode_text.
    IF use_landing_zone {
        PRINT "  Landing Zone:        " + ROUND(target_lat, 1) + "° / " + ROUND(target_lng, 1) + "°".
    }
    PRINT " ".
    PRINT "Note: Rotation during 6-8hr transit IS accounted for".
    PRINT " ".
    PRINT "══════════════════════════════════════════════════".
    PRINT " ".
    PRINT "LANDING ZONE SELECTION:".
    PRINT " ".
    
    LOCAL zone_num IS 1.
    FOR zone IN zones {
        PRINT "(" + zone_num + ") " + zone["name"] + " - " + zone["zstatus"].
        PRINT "    " + zone["desc"].
        PRINT "    " + ROUND(zone["lat"], 1) + "° / " + ROUND(zone["lng"], 1) + "°".
        PRINT "    Best approach: ~" + ROUND(zone["feasibility"]/1000, 0) + " km miss".
        PRINT " ".
        SET zone_num TO zone_num + 1.
    }
    
    PRINT "(B) Basic Mode - Optimize Pe only (no zone)".
    PRINT " ".
    PRINT "(P) PROCEED with current settings".
    PRINT "(X) EXIT".
    PRINT " ".
    
    LOCAL menu_active IS TRUE.
    UNTIL NOT menu_active {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
            
            IF ch = "1" {
                SET use_landing_zone TO TRUE.
                SET zone_name TO zones[0]["name"].
                SET target_lat TO zones[0]["lat"].
                SET target_lng TO zones[0]["lng"].
                PRINT "Selected: " + zone_name.
                WAIT 1.
            } ELSE IF ch = "2" {
                SET use_landing_zone TO TRUE.
                SET zone_name TO zones[1]["name"].
                SET target_lat TO zones[1]["lat"].
                SET target_lng TO zones[1]["lng"].
                PRINT "Selected: " + zone_name.
                WAIT 1.
            } ELSE IF ch = "3" {
                SET use_landing_zone TO TRUE.
                SET zone_name TO zones[2]["name"].
                SET target_lat TO zones[2]["lat"].
                SET target_lng TO zones[2]["lng"].
                PRINT "Selected: " + zone_name.
                WAIT 1.
            } ELSE IF ch = "4" {
                SET use_landing_zone TO TRUE.
                SET zone_name TO zones[3]["name"].
                SET target_lat TO zones[3]["lat"].
                SET target_lng TO zones[3]["lng"].
                PRINT "Selected: " + zone_name.
                WAIT 1.
            } ELSE IF ch = "B" {
                SET use_landing_zone TO FALSE.
                PRINT "Mode: BASIC (Pe optimization only)".
                WAIT 1.
            } ELSE IF ch = "P" {
                SET menu_active TO FALSE.
            } ELSE IF ch = "X" {
                PRINT "TKI aborted.".
                RETURN.
            }
            
            IF menu_active {
                DISPLAY_HEADER("TKI CONFIGURATION").
                PRINT "TRANS-KERBIN INJECTION PARAMETERS".
                PRINT " ".
                PRINT "Current Settings:".
                PRINT "  Target Kerbin Pe:    " + ROUND(target_kerbin_pe/1000, 1) + " km".
                SET mode_text TO "BASIC - Pe only".
                IF use_landing_zone {
                    SET mode_text TO "SELECTED - " + zone_name.
                }
                PRINT "  Mode:                " + mode_text.
                IF use_landing_zone {
                    PRINT "  Landing Zone:        " + ROUND(target_lat, 1) + "° / " + ROUND(target_lng, 1) + "°".
                }
                PRINT " ".
                PRINT "══════════════════════════════════════════════════".
                PRINT " ".
                PRINT "LANDING ZONE SELECTION:".
                PRINT " ".
                
                SET zone_num TO 1.
                FOR zone IN zones {
                    PRINT "(" + zone_num + ") " + zone["name"] + " - " + zone["zstatus"].
                    PRINT "    " + zone["desc"].
                    PRINT "    " + ROUND(zone["lat"], 1) + "° / " + ROUND(zone["lng"], 1) + "°".
                    PRINT "    Best: ~" + ROUND(zone["feasibility"]/1000, 0) + " km".
                    PRINT " ".
                    SET zone_num TO zone_num + 1.
                }
                
                PRINT "(B) Basic Mode".
                PRINT " ".
                PRINT "(P) PROCEED   (X) EXIT".
                PRINT " ".
            }
        }
        WAIT 0.1.
    }

    // User selected a zone - but geometry may have changed
    // Re-check the selected zone with current position
    IF use_landing_zone {
        PRINT " ".
        PRINT "Re-checking " + zone_name + " from current position...".
        
        LOCAL current_feasibility IS CHECK_ZONE_FEASIBILITY(target_lat, target_lng, base_dv).
        
        LOCAL current_status IS "".
        IF current_feasibility < 200000 {
            SET current_status TO "EXCELLENT".
        } ELSE IF current_feasibility < 500000 {
            SET current_status TO "GOOD".
        } ELSE IF current_feasibility < 1000000 {
            SET current_status TO "POSSIBLE".
        } ELSE {
            SET current_status TO "POOR".
        }
        
        PRINT "Current status: " + current_status + " (~" + ROUND(current_feasibility/1000, 0) + " km best approach)".
        PRINT " ".
        
        IF current_status = "POOR" {
            PRINT "WARNING: Zone geometry has degraded since initial check.".
            PRINT "Consider waiting another orbit for better geometry.".
            PRINT " ".
            PRINT "(C) Cancel and wait  (P) Proceed anyway".
            
            LOCAL confirm IS FALSE.
            UNTIL confirm {
                IF TERMINAL:INPUT:HASCHAR {
                    LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
                    IF ch = "C" {
                        PRINT "Waiting for better geometry...".
                        RETURN.
                    } ELSE IF ch = "P" {
                        SET confirm TO TRUE.
                    }
                }
                WAIT 0.1.
            }
        }
    }
    
    // ═══════════════════════════════════════════════════════
    // TRAJECTORY SEARCH - IMPROVED
    // ═══════════════════════════════════════════════════════
    
    DISPLAY_HEADER("CALCULATING OPTIMAL TRAJECTORY").
    
    SET mode_text TO "BASIC - Pe Optimization".
    IF use_landing_zone {
        SET mode_text TO "SELECTED - " + zone_name.
    }
    PRINT "Mode: " + mode_text.
    IF use_landing_zone {
        PRINT "Target: " + ROUND(target_lat, 1) + "° / " + ROUND(target_lng, 1) + "°".
    }
    PRINT " ".
    
    PRINT "Searching for optimal burn window...".
    PRINT " ".
    
    LOCAL best_time IS 0.
    LOCAL best_dv IS 0.
    LOCAL best_score IS 999999999.
    LOCAL best_pe_lat IS 0.
    LOCAL best_pe_lng IS 0.
    LOCAL found_any IS FALSE.
    LOCAL period IS SHIP:ORBIT:PERIOD.
    LOCAL time_step IS period / 36.  // Finer resolution: 36 positions
    
    FROM {LOCAL offset IS 0.} UNTIL offset > period STEP {SET offset TO offset + time_step.} DO {
        
        LOCAL test_time IS TIME:SECONDS + offset.
        
        // More dV range for better Pe accuracy
        FROM {LOCAL dv_offset IS -60.} UNTIL dv_offset > 120 STEP {SET dv_offset TO dv_offset + 8.} DO {
            
            UNTIL NOT HASNODE {
                REMOVE NEXTNODE.
                WAIT 0.05.
            }
            
            LOCAL test_dv IS base_dv + dv_offset.
            LOCAL test_node IS NODE(test_time, 0, 0, test_dv).
            ADD test_node.
            WAIT 0.1.
            
            IF test_node:ORBIT:HASNEXTPATCH AND test_node:ORBIT:NEXTPATCH:BODY = KERBIN {
                LOCAL kerbin_pe IS test_node:ORBIT:NEXTPATCH:PERIAPSIS.
                
                // Only consider if Pe is somewhat reasonable (20-50km range)
                IF kerbin_pe > 28000 AND kerbin_pe < 40000 {
                    LOCAL pe_coords IS GET_PE_COORDINATES_AT_TIME(test_node:ORBIT:NEXTPATCH).
                    
                    LOCAL score IS 0.
                    
                    IF use_landing_zone {
                        LOCAL distance_to_target IS GREAT_CIRCLE_DISTANCE(
                            pe_coords["lat"], pe_coords["lng"],
                            target_lat, target_lng
                        ).
                        LOCAL pe_error IS ABS(kerbin_pe - target_kerbin_pe).
                        
                        SET score TO distance_to_target + pe_error * 500.
                        
                    } ELSE {
                        SET score TO ABS(kerbin_pe - target_kerbin_pe).
                    }
                    
                    IF score < best_score {
                        IF use_landing_zone {
                            LOCAL dist_km IS GREAT_CIRCLE_DISTANCE(pe_coords["lat"], pe_coords["lng"], target_lat, target_lng) / 1000.
                            PRINT "T+" + ROUND(offset/60,1) + "min | Pe=" + ROUND(kerbin_pe/1000,1) + "km | " + ROUND(pe_coords["lat"],1) + "°/" + ROUND(pe_coords["lng"],1) + "° | " + ROUND(dist_km,0) + "km".
                        } ELSE {
                            PRINT "T+" + ROUND(offset/60, 1) + "min | Pe=" + ROUND(kerbin_pe/1000, 1) + "km | dV=" + ROUND(test_dv, 1).
                        }
                        
                        SET best_score TO score.
                        SET best_time TO test_time.
                        SET best_dv TO test_dv.
                        SET best_pe_lat TO pe_coords["lat"].
                        SET best_pe_lng TO pe_coords["lng"].
                        SET found_any TO TRUE.
                    }
                }
            }
            
            REMOVE test_node.
        }
    }
    
    UNTIL NOT HASNODE {
        REMOVE NEXTNODE.
    }
    
    IF NOT found_any {
        PRINT " ".
        PRINT "ERROR: No suitable return trajectory found!".
        PRINT "Geometry may have changed - try waiting another orbit.".
        RETURN.
    }
    
    // Create best node
    LOCAL tki_node IS NODE(best_time, 0, 0, best_dv).
    ADD tki_node.
    WAIT 0.2.
    
    LOCAL final_kerbin_pe IS tki_node:ORBIT:NEXTPATCH:PERIAPSIS.
    
    // ═══════════════════════════════════════════════════════
    // PRE-BURN CONFIRMATION
    // ═══════════════════════════════════════════════════════
    
    DISPLAY_HEADER("TRAJECTORY SOLUTION FOUND").
    
    PRINT "MANEUVER NODE:".
    PRINT "  Time to burn:     T+" + ROUND((tki_node:ETA)/60, 1) + " min".
    PRINT "  Delta-V:          " + ROUND(tki_node:DELTAV:MAG, 1) + " m/s".
    PRINT " ".
    
    PRINT "PROJECTED RETURN:".
    PRINT "  Kerbin Periapsis: " + ROUND(final_kerbin_pe/1000, 1) + " km".
    
    IF use_landing_zone {
        PRINT "  Landing Zone:     " + zone_name.
        PRINT "  Landing coords:   " + ROUND(best_pe_lat, 1) + "° / " + ROUND(best_pe_lng, 1) + "°".
        LOCAL final_distance IS GREAT_CIRCLE_DISTANCE(best_pe_lat, best_pe_lng, target_lat, target_lng).
        PRINT "  Miss distance:    " + ROUND(final_distance/1000, 0) + " km".
        
        IF final_distance < 100000 {
            PRINT "  Status: EXCELLENT - direct recovery possible".
        } ELSE IF final_distance < 300000 {
            PRINT "  Status: GOOD - within recovery range".
        } ELSE IF final_distance < 800000 {
            PRINT "  Status: MCC recommended for precision".
        } ELSE {
            PRINT "  Status: POOR - major MCC required".
        }
    }
    
    PRINT " ".
    PRINT "══════════════════════════════════════════════════".
    PRINT " ".
    PRINT "(P) PROCEED WITH BURN".
    PRINT "(C) CANCEL AND ABORT".
    PRINT " ".
    
    LOCAL confirmed IS FALSE.
    UNTIL confirmed {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
            IF ch = "P" {
                SET confirmed TO TRUE.
                PRINT "BURN CONFIRMED".
            } ELSE IF ch = "C" {
                PRINT "MISSION ABORTED".
                REMOVE tki_node.
                RETURN.
            }
        }
        WAIT 0.1.
    }
    
    // Execute burn
    WAIT 1.
    EXECUTE_NODE(TRUE, 7, 30000).
    
    // ═══════════════════════════════════════════════════════
    // POST-BURN ANALYSIS
    // ═══════════════════════════════════════════════════════
    
    WAIT 2.
    
    DISPLAY_HEADER("BURN COMPLETE - TRAJECTORY ANALYSIS").
    
    IF SHIP:ORBIT:HASNEXTPATCH AND SHIP:ORBIT:NEXTPATCH:BODY = KERBIN {
        LOCAL actual_pe IS SHIP:ORBIT:NEXTPATCH:PERIAPSIS.
        
        //LOCAL pe_eta IS SHIP:ORBIT:NEXTPATCH:ETA:PERIAPSIS.
        //LOCAL transition_eta IS SHIP:ORBIT:NEXTPATCH:PREVIOUSPATCH:ETA:TRANSITION.
        //LOCAL timeDif IS pe_eta - entry_eta. 
        
        PRINT "TRAJECTORY STATUS:".
        PRINT "  Kerbin Encounter: Confirmed".
        PRINT "  Kerbin Periapsis: " + ROUND(actual_pe/1000, 1) + " km".
        
        // Try to get coordinates using the function
        LOCAL actual_coords IS LEXICON("lat", 0, "lng", 0).
        SET actual_coords TO GET_PE_COORDINATES_AT_TIME(SHIP:ORBIT:NEXTPATCH).
        
        PRINT "  Predicted coords: " + ROUND(actual_coords["lat"], 2) + "° / " + ROUND(actual_coords["lng"], 2) + "°".
        
        IF use_landing_zone {
            PRINT "  Target coords:    " + ROUND(target_lat, 2) + "° / " + ROUND(target_lng, 2) + "°".
            PRINT "  Target zone:      " + zone_name.
            
            LOCAL dist IS GREAT_CIRCLE_DISTANCE(actual_coords["lat"], actual_coords["lng"], target_lat, target_lng).
            PRINT "  Predicted miss:   " + ROUND(dist/1000, 0) + " km".
        }
        
        // PRINT " ".
        // PRINT "DEBUG INFO:".
        // PRINT "  Transit time:     ~" + ROUND(SHIP:ORBIT:NEXTPATCH:ETA:PERIAPSIS/3600, 1) + " hours".
        // PRINT "  SOI to Pe time:   ~" + ROUND(timeDif/3600, 1) + " hours".
        
        PRINT " ".
        
        LOCAL pe_error IS ABS(actual_pe - target_kerbin_pe).
        IF pe_error < pe_tolerance {
            PRINT "  ✓ Periapsis nominal (" + ROUND(pe_error/1000, 1) + " km error)".
        } ELSE IF actual_pe < 25000 {
            PRINT "  ⚠ Pe TOO LOW - steep reentry".
        } ELSE IF actual_pe > 45000 {
            PRINT "  ⚠ Pe TOO HIGH - may skip atmosphere".
        } ELSE {
            PRINT "  ⚠ Pe off target by " + ROUND(pe_error/1000, 1) + " km".
        }
        
    } ELSE {
        PRINT "WARNING: No Kerbin encounter detected!".
        PRINT "Burn insufficient - major correction required.".
    }

    PRINT " ".
    PRINT "═══════════════════════════════════════════════════".
    PRINT " ".
    PRINT "TRANS-KERBIN INJECTION COMPLETE".
    PRINT " ".
    PRINT "Note predicted vs actual landing when you splash down!".
    PRINT "Recommend: Run coast.ks for in-flight monitoring".
    PRINT "           MCC capability for fine-tuning (if needed)".

    WAIT 3.
    SHIP_RESET().

}

MAIN().