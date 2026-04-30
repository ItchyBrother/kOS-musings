// ============================================================================
// APOLLO-STYLE MUN LANDING SYSTEM
// kOS Version 1.5.1
// ============================================================================
// Authentic Apollo Lunar Module descent and ascent procedures
// Programs: P63 (Braking), P64 (Approach), P66 (Terminal), P12 (Ascent)
// ============================================================================

// === CONFIGURATION ===
GLOBAL MEM_CONFIG IS LEXICON(
    // Mission Parameters
    "TARGET_LAT", 1.77,                  //Farside Crater - Landing coordinates.
    "TARGET_LNG", -56.881,
    "DOI_ALTITUDE", 12000,               // Decent Orbit Insertion (DOI) burn altitude.  
    "PDI_ALTITUDE", 20000,              // Powered Descent Initiation altitude (m)
    "FINAL_APPROACH_ALT", 2000,          // High Gate altitude (m)
    "LOW_GATE_ALT", 150,                 // Low Gate altitude (m)
    "ENGINE_CUTOFF_ALT", 3,           // Descent engine cutoff altitude (m)
    "EMERGENCY_LAND_MODE", FALSE,        // Skip targeting, land immediately
    
    // Vehicle Parameters
    "DESCENT_STAGE_NAME", "Descent",    // Descent stage name tag
    "ASCENT_STAGE_NAME", "Ascent",      // Ascent stage name tag
    "LANDING_GEAR_HEIGHT", 2.5,         // Height of gear above engine (m)
    
    // Guidance Parameters
    "BRAKING_SAFETY_ALT", 2000,         // Minimum altitude for braking phase
    "RADAR_ACQUISITION_ALT", 12000,     // When landing radar should work
    "VERTICAL_VELOCITY_THRESHOLD", 0.1, // Max velocity for low gate (m/s)
    
    // Ascent Parameters
    "ASCENT_TARGET_ALT", 20000,         // Target orbit altitude (m)
    "ASCENT_TARGET_PITCH", 10,          // Initial pitch angle for ascent
    
    // Control Parameters
    "MAX_TILT_ANGLE", 45,               // Maximum tilt during approach (degrees)
    "RCS_AUTHORITY", 1.0,               // RCS translation authority
    "THROTTLE_RESPONSE", 0.1,           // Throttle change rate limiter
    
    // Testing Parameters
    "GROUND_TEST_MODE", FALSE,          // Enable ground testing (bypasses altitude checks)
    "DEBUG_MODE", FALSE                 // Enable to use DEBUG MODE.
).

// === GLOBAL STATE VARIABLES ===
GLOBAL CURRENT_PROGRAM IS "P00".        // Current program number
GLOBAL ABORT_MODE IS FALSE.             // Abort flag
GLOBAL MANUAL_THROTTLE IS FALSE.        // Manual throttle override
GLOBAL DESIRED_THROTTLE IS 0.           // Commanded throttle
GLOBAL LANDING_RADAR_ONLINE IS FALSE.   // Landing radar status
GLOBAL HIGH_GATE_PASSED IS FALSE.       // High gate flag
GLOBAL LOW_GATE_PASSED IS FALSE.        // Low gate flag
//GLOBAL DESCENT_ENGINE_OUT IS FALSE.     // Descent engine shutdown flag
GLOBAL TARGET_POSITION IS 0.            // Target position vector
GLOBAL CSM_VESSEL IS 0.                 // Command module vessel reference
GLOBAL P64_INITIAL_FACING IS SHIP:NORTH:VECTOR.  // Default facing
GLOBAL INITIAL_HEADING IS 270.          // SET INITIAL HEADING TO 270 degrees, will be correctly set in P63.

// === DISPLAY VARIABLES ===
//GLOBAL DISPLAY_MODE IS "DSKY".
GLOBAL LAST_CALLOUT_TIME IS 0.
GLOBAL LAST_ALTITUDE_CALLOUT IS 1000.

// === DEBUG VECTORS (ADD ONCE) ===
IF MEM_CONFIG["DEBUG_MODE"] {
    GLOBAL vec_surface_vel IS VECDRAW(V(0,0,0), V(0,0,0), BLUE, "Surface Vel", 1.0, TRUE, 0.2).
    GLOBAL vec_target IS VECDRAW(V(0,0,0), V(0,0,0), RED, "Target", 1.0, TRUE, 0.2).
    GLOBAL vec_thrust IS VECDRAW(V(0,0,0), V(0,0,0), GREEN, "Thrust", 1.0, TRUE, 0.2).
}

// ============================================================================
// INITIALIZATION
// ============================================================================

FUNCTION INITIALIZE {
    CLEARSCREEN.
    
    // Set up target position
    SET TARGET_POSITION TO BODY:GEOPOSITIONLATLNG(MEM_CONFIG["TARGET_LAT"], MEM_CONFIG["TARGET_LNG"]).
  
    // Configure ship control
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
    //STAGE. //Activation of LEM DESCENT STAGE.
    SHUTDOWN_DESCENT_ENGINE().
    SAS OFF.
    RCS ON.
    
    // Find CSM if in physics range
    LOCAL csm_found IS FALSE.
    LIST TARGETS IN tgt_list.
    FOR tgt IN tgt_list {
        IF tgt:ISTYPE("Vessel") AND tgt:NAME:CONTAINS("CSM") {
            SET CSM_VESSEL TO tgt.
            SET csm_found TO TRUE.
            BREAK.
        }
    }
   
    IF NOT csm_found {
        PRINT "WARNING: CSM not found for rendezvous".
        WAIT 2.
    }
    
    PRINT "===========================================".
    PRINT " KPOLLO MUN LANDING SYSTEM INITIALIZED".
    PRINT "===========================================".
    PRINT " ".
    PRINT "Target: " + ROUND(MEM_CONFIG["TARGET_LAT"],4) + "° " + ROUND(MEM_CONFIG["TARGET_LNG"],4) + "°".
    PRINT " ".
    IF MEM_CONFIG["GROUND_TEST_MODE"] {
        PRINT "** GROUND TEST MODE ENABLED **".
        PRINT " ".
    }
    PRINT "STARTUP OPTIONS:".
    PRINT "  [1] - Start Descent (DOI + PDI)".
    PRINT "  [2] - Ascent Program (P12)".
    PRINT "  [3] - Land Now.".
    PRINT "  [4] - PDI ONLY (P63, P64, P66)".
    PRINT " ".
    PRINT "IN-FLIGHT CONTROLS (work during descent):".
    PRINT "  [A] - Abort to Orbit".
    PRINT "  [S] - Abort Stage (Emergency)".
    PRINT "  [M] - Toggle Manual Throttle".
    PRINT " ".
    PRINT "Press [1] when ready for PDI...".
    PRINT "(Or [2] if starting from landed position)".
    
    WAIT UNTIL TERMINAL:INPUT:HASCHAR.
    LOCAL cmd IS TERMINAL:INPUT:GETCHAR().
    
    IF cmd = "1" {
        RETURN TRUE.
    } ELSE IF cmd = "2" {
        RETURN "ASCENT".
    } ELSE IF cmd = "3" {
        RETURN "EMERGENCY_LAND". 
    } ELSE IF cmd = "4" {
        RETURN "PDI_ONLY". 
    } ELSE {
        PRINT "Invalid selection. Please press [1] or [2].".
        RETURN FALSE.
    }
}

// ============================================================================
// DISPLAY SYSTEM
// ============================================================================

FUNCTION UPDATE_DISPLAY {
    PARAMETER prog_name, phase_name.

    // Calculate current radar altitude for event display
    LOCAL current_ralt IS GET_RADAR_ALTITUDE().
    
    // Only redraw full display every 10 updates (reduce flicker)
    // Otherwise just update values
    IF NOT (DEFINED display_counter) {
        GLOBAL display_counter IS 0.
    }
    
    LOCAL full_redraw IS FALSE.
    SET display_counter TO display_counter + 1.
    IF display_counter >= 10 {
        SET display_counter TO 0.
        SET full_redraw TO TRUE.
    }
    
    IF full_redraw {
        CLEARSCREEN.
        
        // Header
        PRINT "╔════════════════════════════════════════════╗" AT (0,0).
        PRINT "║  KPOLLO MEM - GUIDANCE COMPUTER DISPLAY    ║" AT (0,1).
        PRINT "╠════════════════════════════════════════════╣" AT (0,2).
        
        // Program and Phase
        PRINT "║ PROG: " + prog_name + "  [" + phase_name + "]" + SPACE(22 - phase_name:LENGTH) + "        ║" AT (0,3).
        PRINT "╠════════════════════════════════════════════╣" AT (0,4).
        
        // Labels
        PRINT "║ ALTITUDE (RADAR):                          ║" AT (0,5).
        PRINT "║ ALTITUDE (ASL):                            ║" AT (0,6).
        PRINT "║ VELOCITY (SURF):                           ║" AT (0,7).
        PRINT "║ VELOCITY (VERT):                           ║" AT (0,8).
        PRINT "║ VELOCITY (HORZ):                           ║" AT (0,9).
        PRINT "║ DISTANCE TO TGT:                           ║" AT (0,10).
        PRINT "║ TARGET BEARING:                            ║" AT (0,11).
        PRINT "╠════════════════════════════════════════════╣" AT (0,12).
        PRINT "║ THROTTLE:                                  ║" AT (0,13).
        PRINT "║ TWR (CURRENT):                             ║" AT (0,14).
        PRINT "║ FUEL REMAINING:                            ║" AT (0,15).
        PRINT "╠════════════════════════════════════════════╣" AT (0,16).
        PRINT "║ LANDING RADAR:                             ║" AT (0,17).
        PRINT "║ THROTTLE MODE:                             ║" AT (0,18).
        PRINT "║ HIGH GATE:                                 ║" AT (0,19).
        PRINT "║ LOW GATE:                                  ║" AT (0,20).
        PRINT "╚════════════════════════════════════════════╝" AT (0,21).
        
        IF ALT:RADAR < MEM_CONFIG["FINAL_APPROACH_ALT"] AND ALT:RADAR > MEM_CONFIG ["LOW_GATE_ALT"] {
            PRINT " [A]bort [S]tage [M]anual [H] Landing Adj" AT (0,23).
        }ELSE{        
            PRINT " [A]bort [S]tage [M]anual                " AT (0,23).
        }
    }
    
    // Always update values
    LOCAL alt_radar IS GET_RADAR_ALTITUDE().
    LOCAL alt_asl IS SHIP:ALTITUDE.
    // Target bearing and distance
    LOCAL to_target_vec IS TARGET_POSITION:POSITION - SHIP:GEOPOSITION:POSITION.
    LOCAL target_bearing IS ARCTAN2(to_target_vec:X, to_target_vec:Z).
    IF target_bearing < 0 { SET target_bearing TO target_bearing + 360. }
    

    IF alt_radar >= 0 {
        PRINT PAD_LEFT(FORMAT_NUMBER(alt_radar), 8) + " m    " AT (20,5).
    } ELSE {
        PRINT PAD_LEFT("----", 8) + " m    " AT (20,5).
    }
    PRINT PAD_LEFT(FORMAT_NUMBER(alt_asl), 8) + " m    " AT (20,6).
    
    // Velocity Data
    LOCAL vel_surface IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL vel_vertical IS VERTICALSPEED.
    LOCAL vel_horizontal IS SQRT(MAX(0, vel_surface^2 - vel_vertical^2)).
    
    PRINT PAD_LEFT(FORMAT_NUMBER(vel_surface), 8) + " m/s  " AT (20,7).
    PRINT PAD_LEFT(FORMAT_NUMBER(vel_vertical), 8) + " m/s  " AT (20,8).
    PRINT PAD_LEFT(FORMAT_NUMBER(vel_horizontal), 8) + " m/s  " AT (20,9).
    
    // Distance to Target
    LOCAL dist_to_target IS DISTANCE_TO_TARGET().
    PRINT PAD_LEFT(FORMAT_NUMBER(dist_to_target), 8) + " m    " AT (20,10).
    PRINT PAD_LEFT(ROUND(target_bearing, 0) + "°", 8) + "      " AT (20,11).
    
    // Thrust and Fuel
    LOCAL current_twr IS GET_CURRENT_TWR().
    LOCAL fuel_percent IS GET_FUEL_PERCENT().
    
    PRINT PAD_LEFT(ROUND(DESIRED_THROTTLE * 100, 1) + "%", 8) + "      " AT (20,13).
    PRINT PAD_LEFT(ROUND(current_twr, 2), 8) + "      " AT (20,14).
    PRINT PAD_LEFT(ROUND(fuel_percent, 1) + "%", 8) + "      " AT (20,15).
    
    // Status Indicators
    LOCAL radar_status IS "OFFLINE".
    IF LANDING_RADAR_ONLINE { SET radar_status TO "ONLINE". }
    
    LOCAL manual_status IS "AUTO".
    IF MANUAL_THROTTLE { SET manual_status TO "MANUAL". }
    
    PRINT SPACE(8 - radar_status:LENGTH) + radar_status + "      " AT (20,17).
    PRINT SPACE(8 - manual_status:LENGTH) + manual_status + "      " AT (20,18).
    
    // Gates Status
    IF HIGH_GATE_PASSED {
        PRINT "PASSED        " AT (20,19).
    } ELSE {
        PRINT "PENDING       " AT (20,19).
    }
    
    IF LOW_GATE_PASSED {
        PRINT "PASSED        " AT (20,20).
    } ELSE {
        PRINT "PENDING       " AT (20,20).
    }

    // Show next event countdown
    // At bottom of UPDATE_DISPLAY, replace event countdown section:

    // Show next event countdown (only if radar is valid)
    IF current_ralt >= 0 {
        IF current_ralt > 2000 {
            PRINT " NEXT: HIGH GATE at 2000m           " AT (0,26).
        } ELSE IF current_ralt > 150 {
            PRINT " NEXT: LOW GATE at 150m             " AT (0,26).
        } ELSE IF current_ralt > MEM_CONFIG["ENGINE_CUTOFF_ALT"] {
            PRINT " NEXT: CUTOFF at " + ROUND(MEM_CONFIG["ENGINE_CUTOFF_ALT"], 1) + "m     " AT (0,26).
        } ELSE {
            PRINT " LANDING IMMINENT                  " AT (0,26).
        }
    } ELSE {
        PRINT " RADAR ACQUISITION PENDING         " AT (0,26).
    }

    IF CURRENT_PROGRAM = "P66" AND MANUAL_THROTTLE {
    PRINT " WASD-Move HN-UpDown SHIFT/CTRL-Throttle" AT (0,27).
    }
}

FUNCTION FORMAT_NUMBER {
    PARAMETER num.
    IF num >= 1000 {
        RETURN ROUND(num, 0):TOSTRING.
    } ELSE IF num >= 100 {
        RETURN ROUND(num, 1):TOSTRING.
    } ELSE IF num >= 10 {
        RETURN ROUND(num, 2):TOSTRING.
    } ELSE {
        RETURN ROUND(num, 3):TOSTRING.
    }
}

FUNCTION SPACE {
    PARAMETER count.
    LOCAL result IS "".
    FROM {LOCAL i IS 0.} UNTIL i >= count STEP {SET i TO i + 1.} DO {
        SET result TO result + " ".
    }
    RETURN result.
}

// Add near other utility functions
FUNCTION FORMAT_TIME {
    PARAMETER seconds.
    
    LOCAL hours IS FLOOR(seconds / 3600).
    LOCAL remaining IS seconds - (hours * 3600).
    LOCAL minutes IS FLOOR(remaining / 60).
    LOCAL secs IS FLOOR(remaining - (minutes * 60)).
    
    // Convert to strings FIRST
    LOCAL hours_str IS "" + hours.
    LOCAL min_str IS "" + minutes.
    LOCAL sec_str IS "" + secs.
    
    // NOW pad the strings
    SET min_str TO PAD_LEFT(min_str, 2, "0").
    SET sec_str TO PAD_LEFT(sec_str, 2, "0").
    
    RETURN hours_str + ":" + min_str + ":" + sec_str.
}

FUNCTION PAD_LEFT {
    PARAMETER input, width, pad_char IS " ".
    
    // Force conversion to string
    LOCAL str IS "" + input.
    
    UNTIL str:LENGTH >= width {
        SET str TO pad_char + str.
    }
    
    RETURN str.
}

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

// Add these functions near the top with other utility functions

FUNCTION ACTIVATE_DESCENT_ENGINE {
    LIST ENGINES IN eng_list.
    FOR eng IN eng_list {
        IF eng:TAG = "Descent" {
            eng:ACTIVATE.
            CALLOUT("DESCENT ENGINE ACTIVATED").
            RETURN TRUE.
        }
    }
    CALLOUT("WARNING: DESCENT ENGINE NOT FOUND").
    RETURN FALSE.
}

FUNCTION SHUTDOWN_DESCENT_ENGINE {
    LIST ENGINES IN eng_list.
    FOR eng IN eng_list {
        IF eng:TAG = "Descent" {
            eng:SHUTDOWN.
            CALLOUT("DESCENT ENGINE SHUTDOWN").
            RETURN TRUE.
        }
    }
    RETURN FALSE.
}

FUNCTION SAFE_DESCENT_ENGINE {
    CALLOUT("SAFING DESCENT ENGINE").
    
    LOCAL descent_engine_found IS FALSE.
    
    LIST ENGINES IN eng_list.
    FOR eng IN eng_list {
        IF eng:TAG = "descent" {
            SET eng:THRUSTLIMIT TO 0.
            SET descent_engine_found TO TRUE.
            PRINT "Descent engine thrust limited to 0%".
        }
    }
    
    IF NOT descent_engine_found {
        PRINT "WARNING: Descent engine not found by tag".
    }
    
    RETURN descent_engine_found.
}

FUNCTION GET_RADAR_ALTITUDE {
    LOCAL h IS SHIP:ALTITUDE - SHIP:GEOPOSITION:TERRAINHEIGHT.
    IF h > 0 AND h < MEM_CONFIG["RADAR_ACQUISITION_ALT"] {
        IF NOT LANDING_RADAR_ONLINE {
            SET LANDING_RADAR_ONLINE TO TRUE.
            CALLOUT("LANDING RADAR").
        }
        RETURN h.
    }
    RETURN -1.
}

FUNCTION GET_CURRENT_TWR {
    LOCAL thrust IS SHIP:AVAILABLETHRUST.
    
    // If engines not firing, use max thrust
    IF thrust < 0.1 {
        SET thrust TO SHIP:MAXTHRUST.
    }
    
    // Still zero? Emergency fallback
    IF thrust < 0.1 {
        RETURN 2.0.  // Safe minimum estimate
    }
    
    LOCAL smass IS SHIP:MASS.
    LOCAL gravity IS BODY:MU / (BODY:RADIUS + SHIP:ALTITUDE)^2.
    
    LOCAL twr IS thrust / (smass * gravity).
    
    // Sanity check
    IF twr < 0.1 {
        RETURN 2.0.
    }
    
    RETURN twr.
}

FUNCTION GET_FUEL_PERCENT {
    LOCAL enabled_amt IS 0.
    LOCAL enabled_cap IS 0.

    // Use SAME variable name and logic as debug
    LIST PARTS IN all_parts.
    FOR p IN all_parts {
        FOR r IN p:RESOURCES {
            IF (r:NAME = "LiquidFuel" OR r:NAME = "Oxidizer") AND r:ENABLED {
                SET enabled_amt TO enabled_amt + r:AMOUNT.
                SET enabled_cap TO enabled_cap + r:CAPACITY.
            }
        }
    }

    IF enabled_cap = 0 {
        RETURN 0.
    }

    RETURN ROUND((enabled_amt / enabled_cap) * 100, 1).
}

FUNCTION ENABLE_ALL_RESOURCES {
    CALLOUT("ENABLING ALL RESOURCES").
    
    LOCAL resources_enabled IS 0.
    
    LIST PARTS IN all_parts.
    FOR p IN all_parts {
        FOR r IN p:RESOURCES {
            IF NOT r:ENABLED {
                SET r:ENABLED TO TRUE.
                SET resources_enabled TO resources_enabled + 1.
                //PRINT "Enabled: " + r:NAME + " in " + p:NAME.
            }
        }
    }
    
    IF resources_enabled > 0 {
        CALLOUT("ENABLED " + resources_enabled + " RESOURCES").
        //PRINT " ".
        //PRINT resources_enabled + " resources enabled for abort.".
    } ELSE {
        CALLOUT("ALL RESOURCES ALREADY ENABLED").
    }
    
    RETURN resources_enabled.
}

FUNCTION DISTANCE_TO_TARGET {
    LOCAL ship_pos IS SHIP:GEOPOSITION.
    LOCAL delta_lat IS (TARGET_POSITION:LAT - ship_pos:LAT) * 3.14159 / 180.
    LOCAL delta_lng IS (TARGET_POSITION:LNG - ship_pos:LNG) * 3.14159 / 180.
    LOCAL dist IS BODY:RADIUS * SQRT(delta_lat^2 + delta_lng^2).
    RETURN dist.
}

FUNCTION CALLOUT {
    PARAMETER message.
    LOCAL current_time IS TIME:SECONDS.
    
    IF current_time - LAST_CALLOUT_TIME > 1 {
        PRINT " ".
        PRINT ">>> " + message + " <<<" AT (0,30).
        SET LAST_CALLOUT_TIME TO current_time.
    }
}

FUNCTION ALTITUDE_CALLOUTS {
    LOCAL ralt IS GET_RADAR_ALTITUDE().
    
    IF ralt < LAST_ALTITUDE_CALLOUT {
        IF ralt <= 100 AND LAST_ALTITUDE_CALLOUT > 100 {
            CALLOUT("ALTITUDE 100").
            SET LAST_ALTITUDE_CALLOUT TO 100.
        } ELSE IF ralt <= 75 AND LAST_ALTITUDE_CALLOUT > 75 {
            CALLOUT("75").
            SET LAST_ALTITUDE_CALLOUT TO 75.
        } ELSE IF ralt <= 50 AND LAST_ALTITUDE_CALLOUT > 50 {
            CALLOUT("50").
            SET LAST_ALTITUDE_CALLOUT TO 50.
        } ELSE IF ralt <= 40 AND LAST_ALTITUDE_CALLOUT > 40 {
            CALLOUT("40").
            SET LAST_ALTITUDE_CALLOUT TO 40.
        } ELSE IF ralt <= 30 AND LAST_ALTITUDE_CALLOUT > 30 {
            CALLOUT("30").
            SET LAST_ALTITUDE_CALLOUT TO 30.
        } ELSE IF ralt <= 20 AND LAST_ALTITUDE_CALLOUT > 20 {
            CALLOUT("20").
            SET LAST_ALTITUDE_CALLOUT TO 20.
        } ELSE IF ralt <= 10 AND LAST_ALTITUDE_CALLOUT > 10 {
            CALLOUT("10").
            SET LAST_ALTITUDE_CALLOUT TO 10.
        } ELSE IF ralt <= 5 AND LAST_ALTITUDE_CALLOUT > 5 {
            CALLOUT("5").
            SET LAST_ALTITUDE_CALLOUT TO 5.
        }
    }
}

FUNCTION CHECK_ABORT_INPUTS {
    IF TERMINAL:INPUT:HASCHAR {
        LOCAL cmd IS TERMINAL:INPUT:GETCHAR().
        
        IF cmd = "a" OR cmd = "A" {
            SET ABORT_MODE TO TRUE.
            CALLOUT("ABORT INITIATED").
            RETURN "ABORT".
        } ELSE IF cmd = "s" OR cmd = "S" {
            CALLOUT("ABORT STAGE").
            RETURN "ABORT_STAGE".
        } ELSE IF cmd = "m" OR cmd = "M" {
            SET MANUAL_THROTTLE TO NOT MANUAL_THROTTLE.
            IF MANUAL_THROTTLE {
                CALLOUT("MANUAL THROTTLE").
            } ELSE {
                CALLOUT("AUTO THROTTLE").
            }
        }
    }
    RETURN "NONE".
}

FUNCTION CHECK_MANUAL_CONTROLS {
    // In manual mode, allow RCS translation
    // WASD for horizontal, HN for vertical
    
    IF NOT MANUAL_THROTTLE {
        RETURN.
    }
    
    IF TERMINAL:INPUT:HASCHAR {
        LOCAL cmd IS TERMINAL:INPUT:GETCHAR().
        
        // Translation controls
        IF cmd = "w" OR cmd = "W" {
            SET SHIP:CONTROL:FORE TO 1.
            WAIT 0.3.
            SET SHIP:CONTROL:FORE TO 0.
        } ELSE IF cmd = "s" OR cmd = "S" {
            SET SHIP:CONTROL:FORE TO -1.
            WAIT 0.3.
            SET SHIP:CONTROL:FORE TO 0.
        } ELSE IF cmd = "a" OR cmd = "A" {
            SET SHIP:CONTROL:STARBOARD TO -1.
            WAIT 0.3.
            SET SHIP:CONTROL:STARBOARD TO 0.
        } ELSE IF cmd = "d" OR cmd = "D" {
            SET SHIP:CONTROL:STARBOARD TO 1.
            WAIT 0.3.
            SET SHIP:CONTROL:STARBOARD TO 0.
        } ELSE IF cmd = "h" OR cmd = "H" {
            SET SHIP:CONTROL:TOP TO 1.
            WAIT 0.3.
            SET SHIP:CONTROL:TOP TO 0.
        } ELSE IF cmd = "n" OR cmd = "N" {
            SET SHIP:CONTROL:TOP TO -1.
            WAIT 0.3.
            SET SHIP:CONTROL:TOP TO 0.
        }
    }
}

FUNCTION SAFE_THROTTLE {
    PARAMETER target_throttle.
    
    IF MANUAL_THROTTLE {
        // In manual mode, read what the pilot is setting
        // Don't override it
        SET DESIRED_THROTTLE TO SHIP:CONTROL:PILOTMAINTHROTTLE.
        RETURN.
    }
    
    LOCAL delta IS target_throttle - DESIRED_THROTTLE.
    LOCAL max_change IS MEM_CONFIG["THROTTLE_RESPONSE"].
    
    IF ABS(delta) > max_change {
        IF delta > 0 {
            SET DESIRED_THROTTLE TO DESIRED_THROTTLE + max_change.
        } ELSE {
            SET DESIRED_THROTTLE TO DESIRED_THROTTLE - max_change.
        }
    } ELSE {
        SET DESIRED_THROTTLE TO target_throttle.
    }
    
    SET DESIRED_THROTTLE TO MAX(0, MIN(1, DESIRED_THROTTLE)).
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO DESIRED_THROTTLE.
}

FUNCTION CALCULATE_LAUNCH_AZIMUTH {
    PARAMETER target_vessel IS CSM_VESSEL.
    
    LOCAL ship_lat IS SHIP:GEOPOSITION:LAT.
    
    PRINT "=== LAUNCH AZIMUTH CALCULATION ===".
    PRINT "Ship latitude: " + ROUND(ship_lat, 3) + "°".
    
    // Default fallback
    LOCAL launch_az IS 270.
    
    IF target_vessel:ISTYPE("Vessel") {
        // Get target's velocity to determine direction
        LOCAL target_vel IS VELOCITYAT(target_vessel, TIME):ORBIT.
        LOCAL north_comp IS VDOT(target_vel, SHIP:NORTH:VECTOR).
        LOCAL east_comp IS VDOT(target_vel, VCRS(SHIP:UP:VECTOR, SHIP:NORTH:VECTOR)).
        
        // Calculate heading from velocity
        LOCAL target_heading IS ARCTAN2(east_comp, north_comp).
        IF target_heading < 0 { SET target_heading TO target_heading + 360. }
        
        PRINT "CSM heading: " + ROUND(target_heading, 1) + "°".
        PRINT "CSM inclination: " + ROUND(target_vessel:ORBIT:INCLINATION, 3) + "°".
        
        // Determine if retrograde
        LOCAL is_retrograde IS (east_comp < 0).
        
        // Calculate from orbital mechanics
        LOCAL target_inc IS target_vessel:ORBIT:INCLINATION.
        IF is_retrograde { SET target_inc TO 180 - target_inc. }
        
        // Only calculate if feasible
        IF ABS(ship_lat) <= ABS(target_inc) {
            LOCAL azimuth_arg IS SIN(target_inc) / COS(ship_lat).
            SET azimuth_arg TO MAX(-1, MIN(1, azimuth_arg)).
            LOCAL base_az IS ARCCOS(azimuth_arg).
            
            // Two options
            LOCAL option1 IS base_az.
            LOCAL option2 IS 180 - base_az.
            
            IF is_retrograde {
                SET option1 TO 360 - option1.
                SET option2 TO 360 - option2.
            }
            
            // Pick closest to target's actual heading
            LOCAL diff1 IS ABS(option1 - target_heading).
            LOCAL diff2 IS ABS(option2 - target_heading).
            IF diff1 > 180 { SET diff1 TO 360 - diff1. }
            IF diff2 > 180 { SET diff2 TO 360 - diff2. }
            
            IF diff1 < diff2 {
                SET launch_az TO option1.
                PRINT "Using option 1: " + ROUND(option1, 1) + "° (diff: " + ROUND(diff1, 1) + "°)".
            } ELSE {
                SET launch_az TO option2.
                PRINT "Using option 2: " + ROUND(option2, 1) + "° (diff: " + ROUND(diff2, 1) + "°)".
            }
        } ELSE {
            // If math fails, use direct heading
            SET launch_az TO target_heading.
            PRINT "Using direct heading (inclination not feasible from this latitude)".
        }
    }
    
    PRINT "LAUNCH AZIMUTH: " + ROUND(launch_az, 1) + "°".
    RETURN launch_az.
}

// ============================================================================
// STEERING FUNCTIONS
// ============================================================================

FUNCTION GET_RETROGRADE_STEERING {
    RETURN SHIP:SRFRETROGRADE.
}

FUNCTION GET_PROGRADE_STEERING {
    RETURN SHIP:SRFPROGRADE.
}

FUNCTION GET_LANDING_STEERING {
    PARAMETER horizontal_correction_factor IS 1.0.
    
    // Get velocity vector (pointing in direction of motion)
    LOCAL vel_vec IS SHIP:VELOCITY:SURFACE.
    
    // If moving very slowly, just point up
    IF vel_vec:MAG < 1 {
        RETURN SHIP:UP.
    }
    
    // Calculate correction toward target
    LOCAL to_target IS TARGET_POSITION:POSITION - SHIP:GEOPOSITION:POSITION.
    
    // Project correction onto horizontal plane (don't mess with vertical)
    LOCAL up_vec IS SHIP:UP:VECTOR.
    LOCAL to_target_horizontal IS to_target - (VDOT(to_target, up_vec) * up_vec).
    
    // Normalize and scale by factor
    IF to_target_horizontal:MAG > 1 {
        SET to_target_horizontal TO to_target_horizontal:NORMALIZED * horizontal_correction_factor * 10.
    }
    
    // Combine velocity with small horizontal correction
    LOCAL steering_vec IS vel_vec + to_target_horizontal.
    
    // Point opposite to this vector (retrograde with correction)
    IF steering_vec:MAG > 0.1 {
        RETURN LOOKDIRUP(-steering_vec:NORMALIZED, up_vec).
    } ELSE {
        RETURN SHIP:UP.
    }
}

FUNCTION GET_VERTICAL_STEERING {
    RETURN SHIP:UP.
}

FUNCTION DOI_STEERING {
    // 90 % pure retrograde, 10 % horizontal correction toward the landing site
    LOCAL retro   IS -SHIP:VELOCITY:ORBIT:NORMALIZED.

    LOCAL to_tgt  IS TARGET_POSITION:POSITION - SHIP:GEOPOSITION:POSITION.
    LOCAL to_up      IS SHIP:UP:VECTOR.
    LOCAL horiz   IS to_tgt - VDOT(to_tgt, to_up) * to_up.   // flatten to surface plane

    IF horiz:MAG > 0 { SET horiz TO horiz:NORMALIZED * 0.1. }  // max 5.7 degrees tilt

    RETURN (retro * 0.9 + horiz):NORMALIZED.
}

// ============================================================================
// ABORT HANDLERS
// ============================================================================

FUNCTION HANDLE_ABORT_TO_ORBIT {
    CALLOUT("ABORT - RETURNING TO INITIAL ORBIT").
    MEM_ABORT().  
    RETURN "ORBIT".
}

FUNCTION HANDLE_ABORT_STAGE {
    CALLOUT("ABORT STAGE - EMERGENCY").
    ENABLE_ALL_RESOURCES().
    // Stage immediately
    LOCK THROTTLE TO 0.
    WAIT 0.1.
    STAGE.
    STAGE.
    WAIT 0.3.
    MEM_ABORT().   
 
    
    RETURN "ORBIT".
}

//MAIN ABORT HANDLER//
FUNCTION MEM_ABORT{
    
    ENABLE_ALL_RESOURCES().
    
    // Kill throttle
    LOCK THROTTLE TO 0.
    WAIT 1.
    
    // Determine if high or low altitude abort
    IF SHIP:ALTITUDE > 10000 {
        // HIGH ALTITUDE ABORT - Just circularize
        
        // If falling, stop the descent first
        IF VERTICALSPEED < -5 {
            LOCK STEERING TO HEADING (270, 90, 180).
            LOCK THROTTLE TO 1.
            //SAFE_THROTTLE(1.0).
            WAIT UNTIL VERTICALSPEED > 0.
            LOCK THROTTLE TO 0.
            //SAFE_THROTTLE(0).
        }
        
        // Point prograde and raise periapsis
        LOCK STEERING TO HEADING(INITIAL_HEADING, 15, 180).
        WAIT 3.
        
        CALLOUT("CIRCULARIZING ORBIT").
        UNTIL SHIP:PERIAPSIS > INITIAL_PERIAPSIS - 500 {
            //SAFE_THROTTLE(0.8).
            LOCK THROTTLE TO 0.5.
            WAIT 0.01.
        }
        
        //SAFE_THROTTLE(0).//
        LOCK THROTTLE TO 0.
        UNLOCK STEERING.
        CALLOUT("ORBIT RESTORED").
        
    } ELSE {
        // LOW ALTITUDE ABORT - Need to ascend
        
        CALLOUT("LOW ALTITUDE ABORT - ASCENDING").
        
        // Point up and climb to safety
        LOCK STEERING TO HEADING(270, 90, 180).
        //SAFE_THROTTLE(1.0).
        LOCK THROTTLE TO 1.
        
        WAIT UNTIL SHIP:APOAPSIS > 2000 AND VERTICALSPEED > 10.
        
        // Now gravity turn in original orbital direction
        CALLOUT("MATCHING ORIGINAL HEADING").
        
        // Gravity turn
        LOCAL start_alt IS SHIP:ALTITUDE.
        LOCAL end_alt IS INITIAL_APOAPSIS.
        LOCAL DESCENTDONE TO FALSE.
        
        UNTIL SHIP:APOAPSIS > INITIAL_APOAPSIS - 500 {
            LOCAL current_alt IS SHIP:ALTITUDE.
            LOCAL pitch_fraction IS MIN(1, (current_alt - start_alt) / (end_alt - start_alt)).
            LOCAL target_pitch IS 15 - (pitch_fraction * 15).  // 85° down to 5°
            
            UNLOCK STEERING.
            LOCK STEERING TO HEADING(INITIAL_HEADING, target_pitch, 180).
            
            //SAFE_THROTTLE(1.0).
            LOCK THROTTLE TO 1.
            WAIT 0.01.

            IF NOT DESCENTDONE AND STAGE:LIQUIDFUEL < 0.1 {
                LOCK THROTTLE TO 0.
                WAIT 1.
                CALLOUT ("DECENT STAGE DEPLETED - STAGING").
                SET DESCENTDONE TO TRUE.
                STAGE.
                WAIT 0.5.
            }

            
        }
        
        //SAFE_THROTTLE(0).
        LOCK THROTTLE TO 0.
        WAIT 1.
        CALLOUT("APOAPSIS REACHED").
        IF NOT DESCENTDONE {
            STAGE.
            WAIT 1.
            SET DESCENTDONE TO TRUE.
        }

        // Circularize at apoapsis
        WAIT UNTIL ETA:APOAPSIS < 0.
        
        UNLOCK STEERING.
        LOCK STEERING TO HEADING(INITIAL_HEADING, 0).
        WAIT 3.
        
        CALLOUT("CIRCULARIZING").
        
        UNTIL SHIP:PERIAPSIS > INITIAL_PERIAPSIS - 500 {
            //SAFE_THROTTLE(1.0).
            LOCK THROTTLE TO 0.5.
            WAIT 0.01.
        }
        
        //SAFE_THROTTLE(0).
        LOCK THROTTLE TO 0.
        UNLOCK ALL.
        UNLOCK STEERING.
        CALLOUT("ORBIT RESTORED").
    }

}

// ============================================================================
// HELICOPTER MODE SUPPORT FUNCTIONS
// ============================================================================

FUNCTION GET_HELICOPTER_STEERING {
    PARAMETER target_descent_rate IS -5.
    PARAMETER max_tilt_angle IS 15.
    PARAMETER translation_gain IS 0.1.
    
    LOCAL up_vec IS SHIP:UP:VECTOR.
    LOCAL target_pos IS TARGET_POSITION:POSITION.
    LOCAL current_pos IS SHIP:GEOPOSITION:POSITION.
    
    // Calculate position error
    LOCAL position_error IS target_pos - current_pos.
    LOCAL horiz_pos_error IS position_error - (VDOT(position_error, up_vec) * up_vec).
    LOCAL horiz_distance IS horiz_pos_error:MAG.
    
    // Calculate current horizontal velocity
    LOCAL current_vel IS SHIP:VELOCITY:SURFACE.
    LOCAL horiz_vel IS current_vel - (VDOT(current_vel, up_vec) * up_vec).
    
    // Calculate DESIRED horizontal velocity to reach target
    LOCAL time_to_ground IS 999.
    IF VERTICALSPEED < -1 {
        LOCAL ralt IS GET_RADAR_ALTITUDE().
        IF ralt <= 0 { SET ralt TO ALT:RADAR. }
        SET time_to_ground TO ralt / ABS(VERTICALSPEED).
    }
    
    LOCAL desired_vel IS V(0,0,0).
    IF time_to_ground > 5 AND time_to_ground < 120 {
        // We have time - calculate velocity needed to reach target
        SET desired_vel TO horiz_pos_error / time_to_ground.
        
        // Limit desired velocity
        IF desired_vel:MAG > 10 {
            SET desired_vel TO desired_vel:NORMALIZED * 10.
        }
    }
    
    // Calculate VELOCITY error (this is what we tilt to fix!)
    LOCAL vel_error IS desired_vel - horiz_vel.
    LOCAL vel_error_mag IS vel_error:MAG.
    
    LOCAL desired_tilt_angle IS 0.
    LOCAL tilt_direction IS V(0, 0, 0).
    
    IF vel_error_mag > 0.5 {
        // Tilt in direction of velocity error
        SET tilt_direction TO vel_error:NORMALIZED.
        SET desired_tilt_angle TO MIN(max_tilt_angle, vel_error_mag * translation_gain * 3).
    }
    
    IF desired_tilt_angle > 0.5 {
        LOCAL tilt_rad IS desired_tilt_angle * CONSTANT:DEGTORAD.
        LOCAL vert_component IS COS(tilt_rad).
        LOCAL horiz_component IS SIN(tilt_rad).
        LOCAL steering_vec IS (up_vec * vert_component) + (tilt_direction * horiz_component).
        RETURN steering_vec:NORMALIZED.
    } ELSE {
        RETURN up_vec.
    }
}

FUNCTION GET_HELICOPTER_THROTTLE {
    PARAMETER base_throttle.
    PARAMETER current_steering_vec.
    
    LOCAL up_vec IS SHIP:UP:VECTOR.
    LOCAL tilt_angle IS VANG(current_steering_vec, up_vec).
    LOCAL tilt_rad IS tilt_angle * CONSTANT:DEGTORAD.
    LOCAL throttle_multiplier IS 1 / COS(tilt_rad).
    LOCAL compensated_throttle IS base_throttle * throttle_multiplier.
    RETURN MIN(1.0, compensated_throttle).
}

// ============================================================================
// DEBUG VECTORS
// ============================================================================

FUNCTION UPDATE_DEBUG_VECTORS {
    LOCAL start_pos IS SHIP:POSITION. //+ (SHIP:UP:VECTOR * 100).
    SET vec_surface_vel:START TO start_pos.
    SET vec_surface_vel:VECTOR TO SHIP:VELOCITY:SURFACE * 5.
    SET vec_target:START TO start_pos.
    SET vec_target:VECTOR TO (TARGET_POSITION:POSITION - SHIP:POSITION).
    SET vec_thrust:START TO start_pos.
    SET vec_thrust:VECTOR TO SHIP:FACING:VECTOR * 15.
}

// ============================================================================
// P63 - BRAKING PHASE
// ============================================================================

FUNCTION PROGRAM_63 {
    SET CURRENT_PROGRAM TO "P63".
    SET warp_cancelled TO FALSE.

    // Save initial orbit parameters for abort
    GLOBAL INITIAL_APOAPSIS IS SHIP:APOAPSIS.
    GLOBAL INITIAL_PERIAPSIS IS SHIP:PERIAPSIS.
    // Save orbital heading (direction of MOTION, not facing)
    LOCAL vel_vec IS SHIP:VELOCITY:ORBIT.
    LOCAL vel_horizontal IS VXCL(SHIP:UP:VECTOR, vel_vec).  // Remove vertical component

    // Get heading from horizontal velocity
    SET INITIAL_HEADING TO VANG(SHIP:NORTH:VECTOR, vel_horizontal).

    // Check if west or east
    LOCAL cross IS VCRS(SHIP:NORTH:VECTOR, vel_horizontal).
    IF VDOT(cross, SHIP:UP:VECTOR) < 0 {
        SET INITIAL_HEADING TO 360 - INITIAL_HEADING.
    }

    CALLOUT("ORBIT PARAMETERS SAVED").
    
    // Check if already landed
    IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
        CALLOUT("ERROR: ALREADY LANDED").
        PRINT " ".
        PRINT "Cannot start descent - vessel is already on the surface.".
        PRINT "Use [2] for ascent instead.".
        WAIT 3.
        RETURN "ABORT".
    } 

        // Ensure we're in a reasonable orbit (skip check if ground test mode)
    IF NOT MEM_CONFIG["GROUND_TEST_MODE"] AND SHIP:ALTITUDE < MEM_CONFIG["BRAKING_SAFETY_ALT"] {
        CALLOUT("ALTITUDE TOO LOW FOR PDI").
        PRINT " ".
        PRINT "Altitude: " + ROUND(SHIP:ALTITUDE, 0) + "m".
        PRINT "Minimum required: " + MEM_CONFIG["BRAKING_SAFETY_ALT"] + "m".
        PRINT " ".
        PRINT "Get to " + MEM_CONFIG["PDI_ALTITUDE"] + "m orbit before starting descent.".
        WAIT 3.
        RETURN "ABORT".
    }

    // === COAST TO PDI – TWR-ADAPTIVE WITH ORBITAL POSITION CHECK ===
    IF NOT EMERGENCY_LAND_MODE {
        CALLOUT("COASTING TO PDI POINT").
        LOCAL last_range IS DISTANCE_TO_TARGET().
        LOCAL pdi_triggered IS FALSE.
        LOCAL trigger_reason IS "".
        LOCAL warp_cancelled IS FALSE.

        UNTIL pdi_triggered {
            UPDATE_DISPLAY("P63", "COAST TO PDI").

            LOCAL tgtrange IS DISTANCE_TO_TARGET().
            LOCAL horiz_speed IS SHIP:VELOCITY:SURFACE:MAG.
            LOCAL approaching IS (tgtrange < last_range).
            SET last_range TO tgtrange.
            
            // ==== TWR-BASED ADAPTIVE TRIGGER ====
            LOCAL g IS BODY:MU / (BODY:RADIUS + SHIP:ALTITUDE)^2.
            LOCAL max_accel IS SHIP:MAXTHRUST / SHIP:MASS.
            LOCAL current_twr IS max_accel / g.
            
            LOCAL base_trigger_alt IS 14000.
            LOCAL twr_bonus IS (current_twr - 2.0) * 1500.
            LOCAL trigger_altitude IS base_trigger_alt - twr_bonus.
            SET trigger_altitude TO MAX(10000, MIN(16000, trigger_altitude)).
            
            // ==== PRACTICAL TIME CALCULATION ====
            LOCAL time_to_pdi IS 9999.
            
            // After DOI, your periapsis is over the target
            // So use ETA:PERIAPSIS as baseline
            LOCAL time_to_pe IS ETA:PERIAPSIS.
            
            IF approaching {
                // We're on the descending side toward periapsis/target
                // Calculate based on how close we are to trigger conditions
                
                // Distance factor: how much range to close?
                LOCAL range_time IS 9999.
                IF horiz_speed > 50 {
                    SET range_time TO (tgtrange - 30000) / horiz_speed.
                }
                
                // Altitude factor: how much altitude to lose?
                LOCAL alt_time IS 9999.
                LOCAL current_vert_speed IS ABS(VERTICALSPEED).
                IF current_vert_speed > 1 AND SHIP:ALTITUDE > trigger_altitude {
                    LOCAL alt_margin IS SHIP:ALTITUDE - trigger_altitude.
                    SET alt_time TO alt_margin / current_vert_speed.
                }
                
                // Use whichever takes longer (both must be satisfied)
                IF range_time < 9999 AND alt_time < 9999 {
                    SET time_to_pdi TO MAX(range_time, alt_time).
                } ELSE IF range_time < 9999 {
                    SET time_to_pdi TO range_time.
                } ELSE IF alt_time < 9999 {
                    SET time_to_pdi TO alt_time.
                } ELSE {
                    // Fall back to periapsis time
                    SET time_to_pdi TO time_to_pe.
                }
                
                // Cap it so it doesn't go beyond periapsis
                IF time_to_pdi > time_to_pe {
                    SET time_to_pdi TO time_to_pe.
                }
                
            } ELSE {
                // Not approaching yet - we're on the other side of orbit
                // PDI will happen after we pass periapsis
                SET time_to_pdi TO time_to_pe + 60.  // Add buffer time after Pe
            }
            
            // Sanity checks
            IF time_to_pdi < 0 { SET time_to_pdi TO 10. }
            IF time_to_pdi > 9999 { SET time_to_pdi TO 9999. }
            
            // ==== DISPLAY ====
            PRINT "Time to PDI: " + FORMAT_TIME(time_to_pdi) + "          " AT (0,26).
            PRINT "Range: " + ROUND(tgtrange/1000,1) + " km  V-vert: " + ROUND(ABS(VERTICALSPEED),1) + " m/s     " AT (0,27).
            PRINT "TWR: " + ROUND(current_twr, 2) + "  Trigger: " + ROUND(trigger_altitude/1000, 1) + " km    " AT (0,28).
            PRINT "ETA:Pe: " + ROUND(time_to_pe, 0) + "s  Alt: " + ROUND(SHIP:ALTITUDE/1000, 1) + " km    " AT (0,29).
                     
            // ==== PDI TRIGGER LOGIC - 40KM RANGE ====

            LOCAL time_to_pe IS ETA:PERIAPSIS.
            LOCAL near_periapsis IS (time_to_pe < 180).  // Within 3 minutes

            LOCAL optimal_trigger_range IS 32500.  // Was 30000, now 40000
            LOCAL optimal_trigger_alt IS trigger_altitude.

            // PRIMARY TRIGGER - Fire when approaching Pe with good geometry
            IF near_periapsis
            AND tgtrange < optimal_trigger_range
            AND approaching 
            AND horiz_speed > 100 {
                SET pdi_triggered TO TRUE.
                SET trigger_reason TO "PERIAPSIS OPTIMAL".
            }

            // Safety Floor 1: Very close to periapsis
            ELSE IF time_to_pe < 60
                    AND tgtrange < 32500  // Slightly less than primary
                    AND approaching {
                SET pdi_triggered TO TRUE.
                SET trigger_reason TO "PERIAPSIS WINDOW 60s".
            }

            // Safety Floor 2: Altitude floor + reasonable range
            ELSE IF SHIP:ALTITUDE < 10000 
                    AND tgtrange < 32500 
                    AND approaching {
                SET pdi_triggered TO TRUE.
                SET trigger_reason TO "ALTITUDE FLOOR 10KM".
            }

            // Safety Floor 3: Range floor + reasonable altitude  
            ELSE IF tgtrange < 30000  // Closer range requirement
                    AND SHIP:ALTITUDE < trigger_altitude + 2000
                    AND approaching {
                SET pdi_triggered TO TRUE.
                SET trigger_reason TO "RANGE FLOOR 30KM".
            }

            // Safety Floor 4: Emergency - very low
            ELSE IF SHIP:ALTITUDE < 7000 
                    AND tgtrange < 32500 {
                SET pdi_triggered TO TRUE.
                SET trigger_reason TO "EMERGENCY 7KM".
            }

            // Safety Floor 5: Fuel critical
            ELSE IF GET_FUEL_PERCENT() < 20 
                    AND tgtrange < 32500 
                    AND SHIP:ALTITUDE < 14000 {
                SET pdi_triggered TO TRUE.
                SET trigger_reason TO "FUEL CRITICAL".
            }

            /////////////////////////////////////////////
            
            // Display status
            IF approaching {
                IF time_to_pdi < 60 {
                    PRINT ">>> PDI in " + ROUND(time_to_pdi, 0) + " seconds <<<          " AT (0,30).
                } ELSE IF time_to_pdi < 300 {
                    PRINT ">>> APPROACHING - " + ROUND(time_to_pdi/60, 1) + " min to PDI <<<   " AT (0,30).
                } ELSE {
                    PRINT "APPROACHING target...                   " AT (0,30).
                }
            } ELSE {
                PRINT "COASTING to periapsis...                " AT (0,30).
            }
            
            // ----- Warp cancel -----
            IF time_to_pdi <= 180 AND time_to_pdi > 0 AND time_to_pdi < 9999 {
                IF NOT warp_cancelled {
                    KUNIVERSE:TIMEWARP:CANCELWARP().
                    WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
                    PRINT "Warp cancelled – PDI in < 3 min." AT (0,31).
                    SET warp_cancelled TO TRUE.
                }
            }

            WAIT 0.5.
        }

        CALLOUT("STARTING PDI - " + trigger_reason).
        PRINT " " AT (0,30).
        PRINT "PDI TRIGGER: " + trigger_reason + "                    " AT (0,31).
        WAIT 2.
    }

    // ORIENT FIRST - Apollo style (back to surface)
    CALLOUT("ORIENTING FOR PDI").
    LOCK STEERING TO GET_RETROGRADE_STEERING().
    WAIT 4.  // Give it time to orient with engines OFF
         
    // Retract landing gear if not already landed (for orbit start)
    IF SHIP:STATUS <> "LANDED" AND SHIP:STATUS <> "SPLASHED" {
        CALLOUT("LANDING GEAR EXTENDED").
        GEAR ON.  // This should extend the landing gear and ladder.  Toggle for landing gear.
    }
    WAIT 2.
    CALLOUT("PRECHECKS COMPLETE").
    ACTIVATE_DESCENT_ENGINE().
    //STAGE.  // TURN ON DESCENT ENGINE
    SET SHIP:CONTROL:FORE TO 1.

    CALLOUT("PROGRAM 63 - BRAKING").
    WAIT 2.
    
    // Begin braking burn
    CALLOUT("PDI - POWERED DESCENT INITIATION").
    
    // Activate descent engine
    SET DESIRED_THROTTLE TO 0.5.
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.5.

    SET SHIP:CONTROL:FORE TO 0.

    //LOCAL target_velocity IS 0.
    LOCAL braking_complete IS FALSE.

       UNTIL braking_complete {
        UPDATE_DISPLAY("P63", "BRAKING PHASE").
        //UPDATE_DEBUG_VECTORS(). // <--DEBUG VECTORS

        LOCAL ralt IS GET_RADAR_ALTITUDE().
        IF ralt <= 0 {
            SET ralt TO SHIP:ALTITUDE - SHIP:GEOPOSITION:TERRAINHEIGHT.
        }
        
        LOCAL vel_surface IS SHIP:VELOCITY:SURFACE:MAG.
        LOCAL vel_vertical IS VERTICALSPEED.
        LOCAL vel_horizontal IS SQRT(MAX(0, vel_surface^2 - vel_vertical^2)).
             
                // === STEERING: CORRECTION ONLY AT HIGH ALTITUDE ===
        LOCAL target_pos IS TARGET_POSITION:POSITION.
        LOCAL current_pos IS SHIP:GEOPOSITION:POSITION.
        LOCAL up_vec IS SHIP:UP:VECTOR.

        LOCAL to_target IS target_pos - current_pos.
        LOCAL to_target_horiz IS to_target - (VDOT(to_target, up_vec) * up_vec).
        LOCAL range_horiz IS to_target_horiz:MAG.

        LOCAL current_vel IS SHIP:VELOCITY:SURFACE.
        LOCAL current_vel_horiz IS current_vel - (VDOT(current_vel, up_vec) * up_vec).

        LOCAL vel_to_target_angle IS VANG(current_vel_horiz, to_target_horiz).
        LOCAL overshot IS vel_to_target_angle > 90.

        LOCAL retro_vec IS SHIP:SRFRETROGRADE:VECTOR.

        // CRITICAL: Only correct when HIGH altitude (> 1000m above High Gate)
        IF ralt > 3000 AND NOT overshot {
            // Still high - apply correction
            LOCAL desired_direction IS to_target_horiz:NORMALIZED.
            LOCAL current_direction IS current_vel_horiz:NORMALIZED.
            LOCAL angle_error IS VANG(current_direction, desired_direction).
            
            LOCAL max_correction_angle IS 20.
            LOCAL correction_strength IS MIN(1, angle_error / max_correction_angle).
            
            LOCAL vel_error_dir IS desired_direction - current_direction.
            IF vel_error_dir:MAG > 0.01 {
                SET vel_error_dir TO vel_error_dir:NORMALIZED.
            }
            
            LOCAL correction_amount IS correction_strength * 0.3.
            LOCAL steering_vec IS (retro_vec * (1 - correction_amount)) + (vel_error_dir * correction_amount).
            
            LOCK STEERING TO steering_vec:NORMALIZED.
            PRINT "Correcting - Alt: " + ROUND(ralt, 0) + "m        " AT (0,28).
            
        } ELSE {
            // Low altitude or overshot - PURE RETROGRADE ONLY
            LOCK STEERING TO retro_vec.
            IF ralt <= 5000 {
                PRINT "ATTITUDE LOCKED.                         " AT (0,28).
            } ELSE {
                PRINT "OVERSHOT - TARGET HOLDING ATTITUDE       " AT (0,28).
            }
        }


        // === THROTTLE CONTROL - GENTLER BRAKING ===
        LOCAL alt_to_gate IS ralt - MEM_CONFIG["FINAL_APPROACH_ALT"].

        // More aggressive targets - stay faster longer
        LOCAL target_horiz_vel IS 0.
        IF alt_to_gate > 5000 {
            SET target_horiz_vel TO 120.  // Was 80
        } ELSE IF alt_to_gate > 3000 {
            SET target_horiz_vel TO 80 + (alt_to_gate - 3000) / 2000 * 40.
        } ELSE IF alt_to_gate > 1000 {
            SET target_horiz_vel TO 60 + (alt_to_gate - 1000) / 2000 * 20.
        } ELSE IF alt_to_gate > 0 {
            SET target_horiz_vel TO 40 + (alt_to_gate / 1000) * 20.
        }

        LOCAL horiz_error_vel IS vel_horizontal - target_horiz_vel.

        // === BASE THROTTLE FROM VELOCITY PROFILE ===
        LOCAL base_throttle IS 0.35 + (horiz_error_vel * 0.01).

        // === PREDICTIVE THROTTLE ADJUSTMENT ===
        // Calculate where we'll land with current trajectory
        LOCAL time_to_ground IS 999.
        IF vel_vertical < -1 {
            SET time_to_ground TO MIN(300, ralt / ABS(vel_vertical)).
        }

        LOCAL predicted_landing IS SHIP:GEOPOSITION:POSITION + (SHIP:VELOCITY:SURFACE * time_to_ground).
        LOCAL landing_error IS (predicted_landing - TARGET_POSITION:POSITION):MAG.

        // Adjustment based on prediction
        LOCAL throttle_adjustment IS 0.
        IF landing_error > 1000 {
            // Overshooting - brake HARDER
            SET throttle_adjustment TO MIN(0.15, landing_error / 10000).
        } ELSE IF landing_error < 500 {
            // Might undershoot - brake SOFTER
            SET throttle_adjustment TO -0.05.
        }

        LOCAL throttle_cmd IS base_throttle + throttle_adjustment.
        SET throttle_cmd TO MAX(0.15, MIN(0.85, throttle_cmd)).

        PRINT "Pred. error: " + ROUND(landing_error/1000, 1) + " km, Thr adj: " + ROUND(throttle_adjustment, 2) + "     " AT (0,30).

        SAFE_THROTTLE(throttle_cmd).

        ALTITUDE_CALLOUTS().

        // // === VERTICAL VELOCITY SLOWDOWN FOR P64 HANDOFF ===
        // IF ralt < 4000 {
        //     // Target gentler descent as we approach High Gate
        //     LOCAL target_vert_vel IS -20.0.
        //     IF ralt < 3000 {
        //         SET target_vert_vel TO -15.0.
        //     }
            
        //     LOCAL vert_error IS VERTICALSPEED - target_vert_vel.
            
        //     // If falling too fast, reduce throttle
        //     IF vert_error < -5 {
        //         LOCAL current_throttle IS SHIP:CONTROL:PILOTMAINTHROTTLE.
        //         LOCAL throttle_reduction IS MIN(0.15, ABS(vert_error) / 100).
        //         SET SHIP:CONTROL:PILOTMAINTHROTTLE TO MAX(0.25, current_throttle - throttle_reduction).
        //     }
        //     // If not falling fast enough, increase throttle slightly
        //     ELSE IF vert_error > 5 {
        //         LOCAL current_throttle IS SHIP:CONTROL:PILOTMAINTHROTTLE.
        //         LOCAL throttle_increase IS MIN(0.10, vert_error / 100).
        //         SET SHIP:CONTROL:PILOTMAINTHROTTLE TO MIN(0.85, current_throttle + throttle_increase).
        //     }
        // }
        
        // Exit at High Gate
        IF ralt < MEM_CONFIG["FINAL_APPROACH_ALT"] {
            SET braking_complete TO TRUE.
            CALLOUT("HIGH GATE").
        }
        
        LOCAL abort_check IS CHECK_ABORT_INPUTS().
        IF abort_check = "ABORT" OR abort_check = "ABORT_STAGE" {
            RETURN abort_check.
        }
    
    WAIT 0.01.
    }
    
    RETURN "CONTINUE".
}

// ============================================================================
// P64 - APPROACH PHASE (SIMPLIFIED)
// ============================================================================
// PURPOSE: Transition from P63 braking to P66 final descent
// START: High Gate (~2000m), some horizontal velocity (~25 m/s)
// END: Low Gate (125m), minimal horizontal (<3 m/s), gentle descent (~-8 m/s)
// ============================================================================

FUNCTION PROGRAM_64 {
    SET CURRENT_PROGRAM TO "P64".
    CALLOUT("PROGRAM 64 - APPROACH").
    
    // Save initial facing direction for P66
    GLOBAL P64_INITIAL_FACING IS SHIP:VELOCITY:SURFACE:NORMALIZED.
    IF SHIP:VELOCITY:SURFACE:MAG < 1 {
        SET P64_INITIAL_FACING TO SHIP:NORTH:VECTOR.
    }
    
    LOCAL approach_complete IS FALSE.
    LOCAL phase IS 1.  // Track which phase we're in for display
    
    UNTIL approach_complete {
        UPDATE_DISPLAY("P64", "APPROACH PHASE").
        
        // === STATE CALCULATION ===
        LOCAL ralt IS ALT:RADAR.
        IF ralt <= 0 {
            SET ralt TO SHIP:ALTITUDE - SHIP:GEOPOSITION:TERRAINHEIGHT.
        }
        
        LOCAL vel_vertical IS VERTICALSPEED.
        LOCAL vel_surface IS SHIP:VELOCITY:SURFACE:MAG.
        LOCAL vel_horizontal IS SQRT(MAX(0, vel_surface^2 - vel_vertical^2)).
        
        // Altitude above Low Gate (our reference point)
        LOCAL alt_above_lg IS ralt - MEM_CONFIG["LOW_GATE_ALT"].
        
        // ====================================================================
        // PHASE DETERMINATION
        // ====================================================================
        
        IF alt_above_lg > 1000 {
            SET phase TO 1.  // High altitude
        } ELSE IF alt_above_lg > 300 {
            SET phase TO 2.  // Medium altitude
        } ELSE {
            SET phase TO 3.  // Final approach to Low Gate
        }
        
        // ====================================================================
        // STEERING CONTROL - SMOOTH TRANSITION
        // ====================================================================
        
        LOCAL steering_vec IS SHIP:UP:VECTOR.  // Default: vertical
        
        IF phase = 1 {
            // PHASE 1: Still killing horizontal - use retrograde with vertical blend
            IF vel_horizontal > 10 {
                // Significant horizontal velocity - mostly retrograde
                LOCAL retro_vec IS SHIP:SRFRETROGRADE:VECTOR.
                LOCAL up_vec IS SHIP:UP:VECTOR.
                LOCAL blend_factor IS MIN(1, vel_horizontal / 20).  // 0-1 scale
                SET steering_vec TO (retro_vec * blend_factor + up_vec * (1 - blend_factor)):NORMALIZED.
            } ELSE {
                // Horizontal nearly killed - mostly vertical
                SET steering_vec TO SHIP:UP:VECTOR.
            }
            
        } ELSE IF phase = 2 {
            // PHASE 2: Finishing horizontal kill - gentle retrograde blend
            IF vel_horizontal > 5 {
                LOCAL retro_vec IS SHIP:SRFRETROGRADE:VECTOR.
                LOCAL up_vec IS SHIP:UP:VECTOR.
                LOCAL blend_factor IS vel_horizontal / 10.  // Gentler blend
                SET steering_vec TO (retro_vec * blend_factor + up_vec * (1 - blend_factor)):NORMALIZED.
            } ELSE {
                // Essentially vertical now
                SET steering_vec TO SHIP:UP:VECTOR.
            }
            
        } ELSE {
            // PHASE 3: Kill any remaining horizontal before P66
            IF vel_horizontal > 3 {
                // Still have horizontal - blend retrograde to kill it
                LOCAL retro_vec IS SHIP:SRFRETROGRADE:VECTOR.
                LOCAL up_vec IS SHIP:UP:VECTOR.
                
                // Blend based on how much horizontal we have
                LOCAL blend_factor IS MIN(1, vel_horizontal / 10).
                SET steering_vec TO (retro_vec * blend_factor + up_vec * (1 - blend_factor)):NORMALIZED.
                
                PRINT "Phase 3: KILLING HORIZONTAL (" + ROUND(vel_horizontal, 1) + " m/s)    " AT (0, 25).
            } ELSE {
                // Horizontal nearly zero - pure vertical
                SET steering_vec TO SHIP:UP:VECTOR.
                PRINT "Phase 3: LOW ALT - PREPARE P66              " AT (0, 25).
            }
        }
        
        // Apply steering with saved facing direction
        LOCK STEERING TO LOOKDIRUP(steering_vec, P64_INITIAL_FACING).
        
        // ====================================================================
        // TARGET DESCENT RATE - THREE PHASE PROFILE
        // ====================================================================
        
        LOCAL target_vert_vel IS 0.
        
        IF phase = 1 {
            // PHASE 1: High altitude - faster descent, focus on killing horizontal
            // Linear decrease from -25 m/s at 1875m to -18 m/s at 1000m
            IF alt_above_lg > 1500 {
                SET target_vert_vel TO -60.0.
            } ELSE {
                // Blend from -25 to -18 over 500m
                LOCAL factor IS (alt_above_lg - 1000) / 500.  // 1.0 at 1500m, 0.0 at 1000m
                SET target_vert_vel TO -50.0 - (factor * 7.0).  // -18 to -25
            }
            
        } ELSE IF phase = 2 {
            // PHASE 2: Medium altitude - moderate descent
            // Linear decrease from -18 m/s at 1000m to -10 m/s at 300m
            LOCAL factor IS (alt_above_lg - 300) / 700.  // 1.0 at 1000m, 0.0 at 300m
            SET target_vert_vel TO -40.0 - (factor * 8.0).  // -10 to -18
            
        } ELSE {
            // PHASE 3: Low altitude - gentle descent for P66 handoff
            // Linear decrease from -10 m/s at 300m to -6 m/s at 125m
            IF alt_above_lg > 200 {
                LOCAL factor IS (alt_above_lg - 50) / 250.  // 1.0 at 300m, 0.0 at 50m
                SET target_vert_vel TO -20.0 - (factor * 4.0).  // -6 to -10
            } ELSE {
                // Very close to Low Gate - steady gentle descent
                SET target_vert_vel TO -5.0.
            }
        }
        
        // ====================================================================
        // THROTTLE CONTROL
        // ====================================================================
        
        // Calculate hover throttle
        LOCAL g IS BODY:MU / (BODY:RADIUS + SHIP:ALTITUDE)^2.
        LOCAL max_accel IS SHIP:MAXTHRUST / SHIP:MASS.
        
        // Safety check
        IF max_accel < 0.1 OR SHIP:MAXTHRUST < 1 {
            CALLOUT("FUEL EXHAUSTED").
            SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
            WAIT UNTIL SHIP:STATUS = "LANDED".
            RETURN "LANDED".
        }
        
        LOCAL hover_throttle IS g / max_accel.
        
        // Proportional control for descent rate
        LOCAL vert_error IS vel_vertical - target_vert_vel.
        LOCAL throttle_cmd IS hover_throttle - (vert_error * 0.5).  //Was 0.35, now 0.5 for more response
        
        // Dynamic throttle limits based on phase
        LOCAL min_throttle IS MAX(0.05, hover_throttle * 0.3).
        LOCAL max_throttle IS MIN(0.95, hover_throttle * 1.8).
        
        // Tighter limits in Phase 3 for smooth handoff
        IF phase = 3 {
            SET min_throttle TO MAX(0.15, hover_throttle * 0.5).
            SET max_throttle TO MIN(0.98, hover_throttle * 3.0).
        }
        
        SET throttle_cmd TO MAX(min_throttle, MIN(max_throttle, throttle_cmd)).
        SAFE_THROTTLE(throttle_cmd).
        
        // ====================================================================
        // CALLOUTS AND DISPLAY
        // ====================================================================
        
        // High Gate callout
        IF NOT HIGH_GATE_PASSED AND ralt <= MEM_CONFIG["FINAL_APPROACH_ALT"] {
            SET HIGH_GATE_PASSED TO TRUE.
            CALLOUT("HIGH GATE").
        }
        
        ALTITUDE_CALLOUTS().
        
        // Phase-specific display
        LOCAL phase_name IS "UNKNOWN".
        IF phase = 1 {
            SET phase_name TO "HIGH ALT - KILL HORIZ".
        } ELSE IF phase = 2 {
            SET phase_name TO "MEDIUM ALT - TRANSITION".
        } ELSE {
            SET phase_name TO "LOW ALT - PREPARE P66".
        }
        
        PRINT "Phase " + phase + ": " + phase_name + "              " AT (0, 27).
        PRINT "H-vel: " + ROUND(vel_horizontal, 1) + " m/s  Target: " + ROUND(target_vert_vel, 1) + " m/s      " AT (0, 28).
        PRINT "Alt above LG: " + ROUND(alt_above_lg, 0) + "m  Throttle: " + ROUND(throttle_cmd*100, 0) + "%      " AT (0, 29).
        
        // Fuel warning
        LOCAL fuel_pct IS GET_FUEL_PERCENT().
        IF fuel_pct < 15 {
            PRINT ">>> FUEL: " + ROUND(fuel_pct, 1) + "% <<<              " AT (0, 30).
        }
    
        // ====================================================================
        // EXIT CONDITION - REACH LOW GATE
        // ====================================================================
        
        IF ralt < MEM_CONFIG["LOW_GATE_ALT"] + 5 {  // Small buffer to prevent oscillation
            SET approach_complete TO TRUE.
            CALLOUT("LOW GATE").
            
            // Log handoff conditions for debugging
            PRINT "P64 HANDOFF: Alt=" + ROUND(ralt, 1) + " H-vel=" + ROUND(vel_horizontal, 1) + " V-vel=" + ROUND(vel_vertical, 1) + "     " AT (0, 30).
        }
        
        // ====================================================================
        // ABORT CHECK
        // ====================================================================
        
        LOCAL abort_check IS CHECK_ABORT_INPUTS().
        IF abort_check = "ABORT" OR abort_check = "ABORT_STAGE" {
            RETURN abort_check.
        }
        
        WAIT 0.01.
    }
    
    RETURN "CONTINUE".
}

// ============================================================================
// P66 - TERMINAL DESCENT (WITH HELICOPTER MODE)
// ============================================================================

FUNCTION PROGRAM_66 {
    SET CURRENT_PROGRAM TO "P66".
    CALLOUT("PROGRAM 66 - TERMINAL DESCENT").
    SET LOW_GATE_PASSED TO TRUE.
    
    // Use facing from P64
    LOCAL facing_direction IS SHIP:NORTH:VECTOR.
    IF DEFINED P64_INITIAL_FACING {
        SET facing_direction TO P64_INITIAL_FACING.
    }
    
    GEAR ON.
    
    // === HELICOPTER MODE CONFIGURATION ===
    LOCAL helicopter_enabled IS TRUE.
    LOCAL max_tilt IS 15.              // Conservative starting value
    LOCAL translation_gain IS 0.1.     // Moderate aggressiveness
    
    // === SAFETY THRESHOLDS ===
    LOCAL min_altitude_for_helicopter IS 15.     // Don't tilt below this altitude
    LOCAL min_fuel_for_helicopter IS 15.         // Disable helicopter below this fuel %
    LOCAL critical_fuel_threshold IS 10.         // Extra warnings below this
    LOCAL emergency_fuel_threshold IS 5.         // Prepare for fuel exhaustion
    
    CALLOUT("FINAL DESCENT - HELICOPTER MODE ACTIVE").
    
    UNTIL ALT:RADAR <= MEM_CONFIG["ENGINE_CUTOFF_ALT"] AND ALT:RADAR > 0 {
        UPDATE_DISPLAY("P66", "FINAL DESCENT").
        
        LOCAL ralt IS ALT:RADAR.
        LOCAL vel_vert IS VERTICALSPEED.
        LOCAL fuel_pct IS GET_FUEL_PERCENT().
        
        // === CALCULATE HORIZONTAL ERROR ===
        LOCAL target_pos IS TARGET_POSITION:POSITION.
        LOCAL current_pos IS SHIP:GEOPOSITION:POSITION.
        LOCAL up_vec IS SHIP:UP:VECTOR.
        LOCAL position_error IS target_pos - current_pos.
        LOCAL horiz_error IS position_error - (VDOT(position_error, up_vec) * up_vec).
        LOCAL horiz_distance IS horiz_error:MAG.
        
        // === ADAPTIVE DESCENT RATE (your original logic) ===
        LOCAL target_descent_rate IS -5.0.
        IF ralt < 30 {
            SET target_descent_rate TO -2.0.
        }
        IF ralt < 10 {
            SET target_descent_rate TO -1.0.
        }
        
        // === ADAPTIVE HELICOPTER PARAMETERS ===
        // More aggressive at high altitude, gentler as we descend
        IF ralt > 100 {
            SET max_tilt TO 20.
            SET translation_gain TO 0.15.
        } ELSE IF ralt > 50 {
            SET max_tilt TO 15.
            SET translation_gain TO 0.12.
        } ELSE IF ralt > 30 {
            SET max_tilt TO 12.
            SET translation_gain TO 0.10.
        } ELSE IF ralt > min_altitude_for_helicopter {
            SET max_tilt TO 8.
            SET translation_gain TO 0.08.
        }
        
        // === SAFETY CHECKS - DISABLE HELICOPTER MODE ===
        LOCAL can_use_helicopter IS TRUE.
        LOCAL disable_reason IS "".
        
        IF ralt < min_altitude_for_helicopter {
            SET can_use_helicopter TO FALSE.
            SET disable_reason TO "ALT TOO LOW".
        }
        
        IF fuel_pct < min_fuel_for_helicopter {
            SET can_use_helicopter TO FALSE.
            SET disable_reason TO "LOW FUEL".
        }
        
        IF NOT helicopter_enabled {
            SET can_use_helicopter TO FALSE.
            SET disable_reason TO "DISABLED".
        }
        
        // === AGGRESSIVE HORIZONTAL KILL BELOW 150M ===
        IF ralt < 150 {
            IF horiz_distance > 3 {
                // Still have horizontal - use AGGRESSIVE helicopter mode to kill it
                SET can_use_helicopter TO TRUE.
                
                // More aggressive parameters for final approach
                SET max_tilt TO 20.  // Aggressive tilt allowed
                SET translation_gain TO 0.3.  // Very aggressive gain
                
                // Use helicopter steering to kill horizontal fast
                LOCAL steering_vec IS GET_HELICOPTER_STEERING(target_descent_rate, max_tilt, translation_gain).
                LOCK STEERING TO LOOKDIRUP(steering_vec, facing_direction).
                
                PRINT "FINAL 150M - KILLING HORIZONTAL             " AT (0, 25).
                
            } ELSE {
                // Horizontal nearly zero - pure vertical now
                LOCK STEERING TO LOOKDIRUP(SHIP:UP:VECTOR, facing_direction).
                SET can_use_helicopter TO FALSE.
                SET disable_reason TO "VERTICAL FINAL".
                
                PRINT "FINAL 150M - PURE VERTICAL                  " AT (0, 25).
            }
        }

        // === STEERING CONTROL ===
        LOCAL steering_vec IS SHIP:UP:VECTOR.  // Default: vertical
        LOCAL current_tilt IS 0.
        
        IF can_use_helicopter AND horiz_distance > 3 {
            // Use helicopter mode
            SET steering_vec TO GET_HELICOPTER_STEERING(target_descent_rate, max_tilt, translation_gain).
            SET current_tilt TO VANG(steering_vec, up_vec).
            
            // Apply facing direction (rotate around up vector)
            LOCK STEERING TO LOOKDIRUP(steering_vec, facing_direction).
            
        } ELSE {
            // Pure vertical descent
            LOCK STEERING TO LOOKDIRUP(SHIP:UP:VECTOR, facing_direction).
        }
        
        // === CALCULATE HOVER THROTTLE (your original logic) ===
        LOCAL g IS BODY:MU / (BODY:RADIUS + SHIP:ALTITUDE)^2.
        LOCAL max_accel IS SHIP:MAXTHRUST / SHIP:MASS.
        
        // Safety check (your original)
        IF max_accel < 0.1 OR SHIP:MAXTHRUST < 1 {
            CALLOUT("FUEL EXHAUSTED").
            SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
            WAIT UNTIL SHIP:STATUS = "LANDED".
            RETURN "LANDED".
        }
        
        LOCAL hover_throttle IS g / max_accel.
        
        // Correction for target descent rate (your original)
        LOCAL vel_error IS vel_vert - target_descent_rate.
        LOCAL throttle_cmd IS hover_throttle - (vel_error * 0.25).
        
        // === APPLY HELICOPTER THROTTLE COMPENSATION ===
        IF can_use_helicopter AND horiz_distance > 3 {
            SET throttle_cmd TO GET_HELICOPTER_THROTTLE(throttle_cmd, steering_vec).
        }
        
        // === DYNAMIC LIMITS (your original) ===
        LOCAL min_throttle IS MAX(0.05, hover_throttle * 0.4).
        LOCAL max_throttle IS MIN(0.9, hover_throttle * 1.4).
        SET throttle_cmd TO MAX(min_throttle, MIN(max_throttle, throttle_cmd)).
        
        // === MANUAL MODE CHECK (your original) ===
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL cmd IS TERMINAL:INPUT:GETCHAR().
            IF cmd = "m" OR cmd = "M" {
                SET MANUAL_THROTTLE TO NOT MANUAL_THROTTLE.
                IF MANUAL_THROTTLE {
                    CALLOUT("MANUAL CONTROL").
                } ELSE {
                    CALLOUT("AUTO CONTROL").
                }
            }
            // NEW: Toggle helicopter mode with 'H' key
            IF cmd = "h" OR cmd = "H" {
                SET helicopter_enabled TO NOT helicopter_enabled.
                IF helicopter_enabled {
                    CALLOUT("HELICOPTER MODE ENABLED").
                } ELSE {
                    CALLOUT("HELICOPTER MODE DISABLED").
                }
            }
        }
        
        // === APPLY THROTTLE ===
        IF NOT MANUAL_THROTTLE {
            SET SHIP:CONTROL:PILOTMAINTHROTTLE TO throttle_cmd.
        }
        
        // === ALTITUDE CALLOUTS (your original) ===
        ALTITUDE_CALLOUTS().

        // === DISPLAY - ENHANCED WITH HELICOPTER INFO ===
        LOCAL mode_text IS "VERTICAL".
        IF can_use_helicopter AND horiz_distance > 3 {
            SET mode_text TO "HELICOPTER".
        } ELSE IF NOT can_use_helicopter {
            SET mode_text TO "VERT (" + disable_reason + ")".
        }
        
        PRINT "Mode: " + mode_text + "     Tilt: " + ROUND(current_tilt, 1) + "°         " AT (0, 27).
        PRINT "Horiz error: " + ROUND(horiz_distance, 1) + "m  Max tilt: " + max_tilt + "°     " AT (0, 28).
        PRINT "Throttle: " + ROUND(throttle_cmd * 100, 0) + "%  Fuel: " + ROUND(fuel_pct, 1) + "%       " AT (0, 29).
        PRINT "Alt: " + ROUND(ralt, 1) + "m  V-vert: " + ROUND(vel_vert, 1) + " m/s (tgt " + ROUND(target_descent_rate, 1) + ")   " AT (0, 30).
        
        // === FUEL WARNINGS (your original + enhanced) ===
        IF fuel_pct < critical_fuel_threshold {
            PRINT "█████████████████████████████████████████████" AT (0,0).
            PRINT "█ CRITICAL FUEL █ CRITICAL FUEL █ CRITICAL █" AT (0,1).
            PRINT "█████████████████████████████████████████████" AT (0,2).
            
            // Extra safety: Disable helicopter mode in critical fuel
            IF fuel_pct < emergency_fuel_threshold {
                PRINT "█████ FUEL EXHAUSTION IMMINENT █████" AT (0,3).
                SET helicopter_enabled TO FALSE.  // Force vertical descent
            }
        }
        
        WAIT 0.02.
    }
    
    // === ENGINE CUTOFF (your original) ===
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
    CALLOUT("ENGINE CUTOFF").
    RCS OFF.
    WAIT UNTIL SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED".
    
    UNLOCK STEERING.
    CALLOUT("CONTACT LIGHT").
    SHUTDOWN_DESCENT_ENGINE().
    WAIT 0.5.
    SAFE_DESCENT_ENGINE().
    WAIT 0.5.
    CALLOUT("WE HAVE LANDED!").
    
    RETURN "LANDED".
}

// ============================================================================
// P12 - ASCENT GUIDANCE
// ============================================================================

FUNCTION PROGRAM_12 {
    SET CURRENT_PROGRAM TO "P12".
    CALLOUT("PROGRAM 12 - ASCENT GUIDANCE").
    WAIT 5.
    SAFE_DESCENT_ENGINE().  // Setting descent stage thrust to 0.
    CALLOUT("DESCENT ENGINE THRUST DISABLED").
    WAIT 5.
    ENABLE_ALL_RESOURCES().  // Enabling all fuel/RCS.
    CALLOUT ("<<< ASCENT STAGE ACTIVE >>>").
    WAIT 5.

    UNLOCK THROTTLE.
    WAIT 0.5.

    // Check if CSM present
    LOCAL target_apo IS MEM_CONFIG["ASCENT_TARGET_ALT"].
    LOCAL target_peri IS MEM_CONFIG["ASCENT_TARGET_ALT"].

    LOCAL launch_azimuth IS 270.
    
    IF CSM_VESSEL:ISTYPE("Vessel") {
        SET target_apo TO CSM_VESSEL:APOAPSIS.
        SET target_peri TO CSM_VESSEL:PERIAPSIS.

        // Calculate proper launch azimuth to match CSM inclination.
        SET launch_azimuth TO CALCULATE_LAUNCH_AZIMUTH(CSM_VESSEL).
        PRINT "Launch azimuth is: " + launch_azimuth.
        CALLOUT("MATCHING CSM ORBIT").
    } ELSE {
        CALLOUT("NO CSM - STANDARD ASCENT").
    }
     
    // Safety check for pad
    IF (SHIP:STATUS = "LANDED" OR SHIP:STATUS = "PRELAUNCH") AND SHIP:VELOCITY:SURFACE:MAG < 0.1 {
        IF BODY:NAME = "Kerbin" AND SHIP:ALTITUDE < 1000 {
            CALLOUT("ERROR: CANNOT START FROM PAD").
            WAIT 3.
            RETURN "ERROR".
        }
    }
    
    PRINT "Target Orbit is: Ap: " + (ROUND(target_apo) / 1000) + " Pe: " + (ROUND(target_peri) /1000) AT (0, 29).
    PRINT "LAUNCH IN 5 SECONDS."  AT (0, 30).

    // Stage
    IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
        WAIT 1.
        SAS OFF.
        RCS ON.
        SET SHIP:CONTROL:FORE TO 1.
    }
    WAIT 4.
    CALLOUT("LIFTOFF!").
    
    // Vertical climb
    LOCK STEERING TO SHIP:FACING.
    STAGE.
    WAIT 0.1.
    STAGE.
    WAIT 0.1.
    LOCK THROTTLE TO 1.
    AG5 ON.
    WAIT 0.1.
    //SAFE_THROTTLE(1.0).
    WAIT 2.
    SET SHIP:CONTROL:FORE TO 0.

    WAIT UNTIL ALT:RADAR > 1000.
    LOCK STEERING TO HEADING(launch_azimuth, 90, 180).
    CALLOUT("PITCH OVER").
    
    // Gravity turn
    LOCAL start_alt IS 2000.
    
    UNTIL SHIP:APOAPSIS >= target_peri {
        UPDATE_DISPLAY("P12", "ASCENT TO ORBIT").
        
        LOCAL current_alt IS SHIP:ALTITUDE.
        
        // Pitch: 90° at 1000m → 5° at 20000m
        LOCAL pitch_fraction IS MIN(1, (current_alt - start_alt) / (target_peri - start_alt)).
        LOCAL target_pitch IS 15 - (pitch_fraction * 15).  // 85° down to 5°
        
        LOCK STEERING TO HEADING(launch_azimuth, target_pitch, 180).  // Head EAST (90), not west (270)
        LOCK THROTTLE TO 1.0.
        
        WAIT 0.01.
    }
    
    // Apoapsis reached - cut throttle
    //SAFE_THROTTLE(0).
    LOCK THROTTLE TO 0.
    CALLOUT("APOAPSIS REACHED").
    
    // Coast to apoapsis
    WAIT UNTIL ETA:APOAPSIS < 25.
    
    // Circularization
    UNLOCK STEERING.
    LOCK STEERING TO SHIP:PROGRADE.
    WAIT 3.
    
    WAIT UNTIL ETA:APOAPSIS < 5.

    CALLOUT("CIRCULARIZATION").
    
    UNTIL SHIP:PERIAPSIS > target_peri - 500 {
        LOCK THROTTLE TO 0.5.
        IF SHIP:APOAPSIS > target_apo + 1000 AND SHIP:PERIAPSIS > 15000 {
            SET target_peri TO SHIP:ALTITUDE.
        }
        //SAFE_THROTTLE(1.0).
        WAIT 0.01.
    }
    
    // Orbit achieved - STOP ENGINE
    //SAFE_THROTTLE(0).
    LOCK THROTTLE TO 0.
    UNLOCK STEERING.
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
    
    CALLOUT("ORBIT ACHIEVED").
    
    RETURN "ORBIT".
}

// ============================================================================
// P17 - DESCENT ORBIT INSERTION (DOI) - IMPROVED
// ============================================================================

FUNCTION PROGRAM_17 {
    SET CURRENT_PROGRAM TO "P17".
    CALLOUT("PROGRAM 17 - DESCENT ORBIT INSERTION").

    WAIT 5.
    GEAR ON.
    CALLOUT("EXTENDING LANDING GEAR").
    WAIT 5.

    LOCAL target_pe_alt IS MEM_CONFIG["DOI_ALTITUDE"].
    LOCAL ready_for_burn IS FALSE.
    LOCAL warp_cancelled IS FALSE.

    // ---------------------------------------------------------
    // 1. COAST TO BURN POINT - POSITION VECTOR METHOD
    // ---------------------------------------------------------
    UNTIL ready_for_burn {
        UPDATE_DISPLAY("P17","COAST TO DOI POINT").

        // Get position vectors
        LOCAL ship_pos IS SHIP:POSITION - BODY:POSITION.
        LOCAL target_pos IS TARGET_POSITION:POSITION - BODY:POSITION.
        
        // Angular separation between ship and target
        LOCAL angle_to_target IS VANG(ship_pos, target_pos).
        
        // We want to burn when angle = 180° (opposite side from target)
        LOCAL angle_error IS ABS(angle_to_target - 180).
        
        // Calculate time to burn point - FIXED LOGIC
        LOCAL time_to_burn IS 9999.
        LOCAL period IS 2 * CONSTANT:PI * SQRT(SHIP:ORBIT:SEMIMAJORAXIS^3 / BODY:MU).
        
        LOCAL angle_remaining IS 0.
        IF angle_to_target < 180 {
            // Haven't reached burn point yet
            SET angle_remaining TO 180 - angle_to_target.
        } ELSE {
            // Passed burn point, need to go around
            SET angle_remaining TO 360 - (angle_to_target - 180).
        }
        
        SET time_to_burn TO (angle_remaining / 360) * period.
        
        // ---- Display ----
        PRINT "Time to DOI: " + FORMAT_TIME(time_to_burn) + "          " AT (0,25).
        PRINT "Angle to target: " + ROUND(angle_to_target, 1) + "°          " AT (0,26).
        PRINT "Need to travel: " + ROUND(angle_remaining, 1) + "° (to 180° point)   " AT (0,27).

        // ---- Warp handling ----
        IF time_to_burn <= 180 {
            IF NOT warp_cancelled {
                KUNIVERSE:TIMEWARP:CANCELWARP().
                WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.               
                GEAR ON.
                RCS ON.
                LOCK STEERING TO SHIP:RETROGRADE.
                SET warp_cancelled TO TRUE.
                PRINT "Warp cancelled – DOI in < 3 min." AT (0,28).
            }
        } 

        // ---- Ready when within 5 degrees of 180° from target ----
        IF angle_error < 5 {
            SET ready_for_burn TO TRUE.
        }

        WAIT 0.2.
    }

    // ---------------------------------------------------------
    // 2. BURN
    // ---------------------------------------------------------
    CALLOUT("DOI BURN – LOWERING PERIAPSIS").
    ACTIVATE_DESCENT_ENGINE().
    LOCK STEERING TO DOI_STEERING().
    WAIT 3.
    CALLOUT("PRECHECKS COMPLETE").
    SET SHIP:CONTROL:FORE TO 1.
    WAIT 2.
    SAFE_THROTTLE(0.4).
    SET SHIP:CONTROL:FORE TO 0.

    UNTIL SHIP:PERIAPSIS <= target_pe_alt + 200 {
        UPDATE_DISPLAY("P17","DOI BURN").

        LOCAL cur_pe IS SHIP:PERIAPSIS.
        LOCAL pe_err IS target_pe_alt - cur_pe.
        LOCAL throttle_cmd IS MIN(1.0, MAX(0.3, pe_err/1200)).

        SAFE_THROTTLE(throttle_cmd).

        PRINT "Target Pe: " + ROUND(target_pe_alt,0) + " m" AT (0,24).
        PRINT "Current Pe: " + ROUND(cur_pe,0) + " m" AT (0,25).
        PRINT "Throttle: " + ROUND(throttle_cmd*100,0) + "%" AT (0,26).

        WAIT 0.01.
    }

    SAFE_THROTTLE(0).
    SET DESIRED_THROTTLE TO 0.
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
    WAIT 3.
    LOCK STEERING TO RETROGRADE.
    CALLOUT("DOI COMPLETE – DESCENT ORBIT ESTABLISHED").
    SHUTDOWN_DESCENT_ENGINE().

    PRINT "Descent orbit: " + ROUND(SHIP:APOAPSIS/1000,1) + " x " + ROUND(SHIP:PERIAPSIS/1000,1) + " km" AT (0,25).
    PRINT "Press [1] to continue to PDI..." AT (0,26).

    WAIT UNTIL TERMINAL:INPUT:HASCHAR.
    IF TERMINAL:INPUT:GETCHAR() = "1" { RETURN "CONTINUE". }
    RETURN "ABORT".
}

// ============================================================================
// MAIN EXECUTION
// ============================================================================

CLEARSCREEN.
LOCAL init_result IS INITIALIZE().

IF init_result = TRUE {

    LOCAL run_mission IS TRUE.
    
    // GROUND TEST MODE - Just show display, don't fly
    IF MEM_CONFIG["GROUND_TEST_MODE"] {
        CALLOUT("GROUND TEST MODE - DISPLAY ONLY").
        SET run_mission TO FALSE.
        
        LOCAL test_running IS TRUE.
        UNTIL NOT test_running {
            UPDATE_DISPLAY("TEST", "GROUND TEST MODE").
            
            // Show fuel calculations
            LOCAL fuel_pct IS GET_FUEL_PERCENT().
            PRINT "Fuel: " + ROUND(fuel_pct, 1) + "%" AT (0,27).
            
            // Allow exit
            IF TERMINAL:INPUT:HASCHAR {
                LOCAL cmd IS TERMINAL:INPUT:GETCHAR().
                IF cmd = "q" OR cmd = "Q" {
                    SET test_running TO FALSE.
                }
            }
            
            WAIT 0.1.
        }
        
        PRINT "Ground test complete.".
    } 

    // NORMAL FLIGHT MODE - Only run if not in ground test
    IF run_mission {
        // Standard descent sequence
        LOCAL result IS "CONTINUE".
        SET EMERGENCY_LAND_MODE TO FALSE.
        
        // Execute DOI First
        SET result TO PROGRAM_17().

        // Execute descent sequence
        IF result = "CONTINUE" {
        SET result TO PROGRAM_63().
        }
        
        IF result = "CONTINUE" {
            SET result TO PROGRAM_64().
        }
        
        IF result = "CONTINUE" {
            SET result TO PROGRAM_66().
        }
        
        // Handle results
        IF result = "ABORT" {
            HANDLE_ABORT_TO_ORBIT().
        } ELSE IF result = "ABORT_STAGE" {
            HANDLE_ABORT_STAGE().
        } ELSE IF result = "LANDED" {
            PRINT " " AT (0,24).
            PRINT "=======================================" AT (0,25).
            PRINT "           LANDING COMPLETE            " AT (0,26).
            PRINT "=======================================" AT (0,27).
            // PRINT "Press [2] for ascent when ready..." AT (0,28).
            // WAIT UNTIL TERMINAL:INPUT:HASCHAR.
            // LOCAL cmd IS TERMINAL:INPUT:GETCHAR().
            
            // IF cmd = "2" {
            //     PROGRAM_12().
            // }
        }
    }

// MOVE THESE OUTSIDE - Same level as first IF
} ELSE IF init_result = "ASCENT" {
    // Direct to ascent
    PROGRAM_12().
    
} ELSE IF init_result = "EMERGENCY_LAND" {
    // Emergency land - full sequence but no targeting
    SET EMERGENCY_LAND_MODE TO TRUE.
    
    LOCAL result IS "CONTINUE".
    
    // Execute full descent sequence
    SET result TO PROGRAM_63().
    
    IF result = "CONTINUE" {
        SET result TO PROGRAM_64().
    }
    
    IF result = "CONTINUE" {
        SET result TO PROGRAM_66().
    }
    
    // Handle results same as normal
    IF result = "ABORT" {
        HANDLE_ABORT_TO_ORBIT().
    } ELSE IF result = "ABORT_STAGE" {
        HANDLE_ABORT_STAGE().
    } ELSE IF result = "LANDED" {
        PRINT " " AT (0,24).
        PRINT "=======================================" AT (0,25).
        PRINT "          LANDING COMPLETE             " AT (0,26).
        PRINT "=======================================" AT (0,27).
        // PRINT "Press [2] for ascent when ready..." AT (0,28).
        // WAIT UNTIL TERMINAL:INPUT:HASCHAR.
        // LOCAL cmd IS TERMINAL:INPUT:GETCHAR().
        
        // IF cmd = "2" {
        //     PROGRAM_12().
        // }
    }
    
} ELSE IF init_result = "PDI_ONLY" {
    // PDI only - skip DOI, go straight to targeted descent
    SET EMERGENCY_LAND_MODE TO FALSE.
    
    LOCAL result IS "CONTINUE".
    
    SET result TO PROGRAM_63().
    
    IF result = "CONTINUE" {
        SET result TO PROGRAM_64().
    }
    
    IF result = "CONTINUE" {
        SET result TO PROGRAM_66().
    }
    
    IF result = "ABORT" {
        HANDLE_ABORT_TO_ORBIT().
    } ELSE IF result = "ABORT_STAGE" {
        HANDLE_ABORT_STAGE().
    } ELSE IF result = "LANDED" {
        PRINT " " AT (0,24).
        PRINT "=======================================" AT (0,25).
        PRINT " LANDING COMPLETE" AT (0,26).
        PRINT "=======================================" AT (0,27).
        // PRINT "Press [2] for ascent when ready..." AT (0,28).
        // WAIT UNTIL TERMINAL:INPUT:HASCHAR.
        // LOCAL cmd IS TERMINAL:INPUT:GETCHAR().
        
        // IF cmd = "2" {
        //     PROGRAM_12().
        // }
    }  
    
} ELSE {
    PRINT "Initialization failed.".
}

PRINT " ".
PRINT "Mission complete. System shutdown.".
UNLOCK STEERING.
UNLOCK ALL.
SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.