// ===============================================================
// display.ks - Optimized Mission Control Display System
// Updates individual fields without screen clearing for smooth display
// Optimized for 50x36 terminal size
// ===============================================================
//---------------------------------------------------------------------------------------
//  Function     Update Phase    Update Guidance     Log             When to use
// DISP_STATUS       YES         YES                 YES             Phase transitions
// DISP_LOG_UPDATE   NO          NO                  YES             Frequent updates
// DISP_SUCCESS      NO          NO                  YES with OK     Success event
// DISP_ERROR        NO          YES "ERROR"         YES with ERR    Errors
// DISP_WARN         NO          NO                  YES with WARN   Warnings
// DISP_SET_PHASE    YES         NO                  NO              Change Phase only
// DISP_SET_GUIDANCE NO          YES                 NO              Chg guidance only
// DISP_TICK         NO          NO                  NO              Loop Update
//---------------------------------------------------------------------------------------

// ===== GLOBAL DISPLAY STATE VARIABLES =====
GLOBAL DISP_INITIALIZED IS FALSE.
GLOBAL DISP_CURRENT_PHASE IS "STARTUP".
GLOBAL DISP_PHASE_START_TIME IS TIME:SECONDS.
GLOBAL DISP_LAST_UPDATE IS 0.
GLOBAL DISP_UPDATE_INTERVAL IS 0.1.  // Update every 0.1 seconds for smooth display
GLOBAL DISP_MESSAGE_LOG IS LIST().
GLOBAL DISP_MAX_MESSAGES IS 5.
GLOBAL DISP_STATUS_DATA IS LEXICON().
GLOBAL DISP_SCREEN_DRAWN IS FALSE.

// ===== PHASE DEFINITIONS =====
GLOBAL DISP_PHASES IS LEXICON(
    "STARTUP", "System Init",
    "TARGET_SELECT", "Target Select",
    "RESUME_CHECK", "Resume Check", 
    "RENDEZVOUS", "Rendezvous",
    "APPROACH", "Long Range",
    "WINDOW_HOLD", "Stationkeep",
    "PROMPT_200M", "Operator Input",
    "APPROACH_50M", "Close Approach",
    "BREAKOUT", "Breakout",
    "ALIGN_PORTS", "Port Align",
    "FINAL_DOCK", "Final Dock",
    "COMPLETE", "Complete"
).

// ===== INITIALIZATION FUNCTION =====
FUNCTION DISP_INIT {
    PARAMETER vessel_name IS SHIP:NAME, mission_type IS "DOCKING".
    
    SET DISP_INITIALIZED TO TRUE.
    SET DISP_PHASE_START_TIME TO TIME:SECONDS.
    SET DISP_LAST_UPDATE TO TIME:SECONDS.
    SET DISP_SCREEN_DRAWN TO FALSE.
    DISP_MESSAGE_LOG:CLEAR().
    
    // Initialize status data structure
    SET DISP_STATUS_DATA TO LEXICON(
        "vessel_name", vessel_name,
        "mission_type", mission_type,
        "target_name", "",
        "current_range", 0,
        "closing_velocity", 0,
        "relative_velocity", 0,
        "ship_orbit", LEXICON("ap", 0, "pe", 0, "inc", 0),
        "target_orbit", LEXICON("ap", 0, "pe", 0, "inc", 0),
        "rcs_fuel", 0,
        "intercept_data", LEXICON("time", 0, "distance", 0, "rel_vel", 0),
        "guidance_status", "STANDBY",
        "rcs_active", FALSE,
        "sas_active", FALSE
    ).
    
    // Draw initial screen once
    CLEARSCREEN.
    DISP_DRAW_STATIC_LAYOUT().
    SET DISP_SCREEN_DRAWN TO TRUE.
    
    DISP_LOG("Display system initialized").
}

// ===== PHASE MANAGEMENT =====
FUNCTION DISP_SET_PHASE {
    PARAMETER new_phase.
    
    IF DISP_PHASES:HASKEY(new_phase) {
        SET DISP_CURRENT_PHASE TO new_phase.
        SET DISP_PHASE_START_TIME TO TIME:SECONDS.
        DISP_LOG("Phase: " + DISP_PHASES[new_phase]).
    }
}

// ===== MESSAGE LOGGING =====
FUNCTION DISP_LOG {
    PARAMETER message.
    
    LOCAL current_time IS TIME:SECONDS.
    LOCAL formatted_time IS DISP_FORMAT_TIME(current_time).
    LOCAL log_entry IS formatted_time + " " + message.
    
    DISP_MESSAGE_LOG:ADD(log_entry).
    
    IF DISP_MESSAGE_LOG:LENGTH > DISP_MAX_MESSAGES {
        DISP_MESSAGE_LOG:REMOVE(0).
    }
    
    // Update message log display immediately
    IF DISP_SCREEN_DRAWN {
        DISP_UPDATE_MESSAGE_LOG_ONLY().
    }
}

// ===== STATUS DATA MANAGEMENT =====
FUNCTION DISP_UPDATE_STATUS {
    PARAMETER key, value.
    
    IF DISP_STATUS_DATA:HASKEY(key) {
        SET DISP_STATUS_DATA[key] TO value.
    }
}

// ===== FORMATTING FUNCTIONS =====
FUNCTION DISP_FORMAT_TIME {
    PARAMETER time_val.
    
    LOCAL total_seconds IS FLOOR(time_val).
    LOCAL mission_time IS total_seconds - FLOOR(DISP_PHASE_START_TIME).
    LOCAL minutes IS FLOOR(mission_time / 60).
    LOCAL seconds IS mission_time - (minutes * 60).
    
    LOCAL min_str IS "" + minutes.
    LOCAL sec_str IS "" + seconds.
    IF minutes < 10 { SET min_str TO "0" + minutes. }
    IF seconds < 10 { SET sec_str TO "0" + seconds. }
    
    RETURN min_str + ":" + sec_str.
}

FUNCTION DISP_FORMAT_DISTANCE {
    PARAMETER meters.
    
    IF meters >= 100000 {
        RETURN ROUND(meters / 1000, 0) + "km".
    } ELSE IF meters >= 10000 {
        RETURN ROUND(meters / 1000, 1) + "km".
    } ELSE IF meters >= 1000 {
        RETURN ROUND(meters / 1000, 2) + "km".
    } ELSE {
        RETURN ROUND(meters, 0) + "m".
    }
}

FUNCTION DISP_FORMAT_VELOCITY {
    PARAMETER vel_ms.
    
    IF ABS(vel_ms) >= 100 {
        RETURN ROUND(vel_ms, 0) + "m/s".
    } ELSE {
        RETURN ROUND(vel_ms, 2) + "m/s".
    }
}

// ===== DRAW STATIC LAYOUT (ONCE) =====
FUNCTION DISP_DRAW_STATIC_LAYOUT {
    LOCAL header_line IS "=".
    FROM {LOCAL i IS 0.} UNTIL i >= 48 STEP {SET i TO i + 1.} DO {
        SET header_line TO header_line + "=".
    }
    
    LOCAL dash_line IS "-".
    FROM {LOCAL i IS 0.} UNTIL i >= 48 STEP {SET i TO i + 1.} DO {
        SET dash_line TO dash_line + "-".
    }
    
    // Header
    PRINT header_line AT (0, 0).
    PRINT "FLIGHT GUIDANCE SYSTEM" AT (10, 1).
    PRINT "  " + DISP_STATUS_DATA["vessel_name"] + " | " + DISP_STATUS_DATA["mission_type"] AT (0, 2).
    PRINT header_line AT (0, 3).
    
    // Mission Status (labels only)
    PRINT "MET:       | PHASE:                          " AT (1, 4).
    PRINT "STATUS:                                      " AT (1, 5).
    
    // Orbital Data
    PRINT dash_line AT (0, 6).
    PRINT "ORBIT DATA" AT (1, 7).
    PRINT "         SHIP      TARGET" AT (1, 8).
    PRINT "AP:                      " AT (1, 9).
    PRINT "PE:                      " AT (1, 10).
    PRINT "INC:                     " AT (1, 11).
    
    // Approach Data
    PRINT dash_line AT (0, 12).
    PRINT "APPROACH DATA" AT (1, 13).
    PRINT "TARGET:                                      " AT (1, 14).
    PRINT "RANGE:                                       " AT (1, 15).
    PRINT "REL VEL:                                     " AT (1, 16).
    PRINT "CLOSING:                                     " AT (1, 17).
    
    // Vehicle Status
    PRINT dash_line AT (0, 18).
    PRINT "VEHICLE & INTERCEPT" AT (1, 19).
    PRINT "RCS:     | SAS:     | FUEL:                 " AT (1, 20).
    PRINT "INTERCEPT T:                                 " AT (1, 21).
    PRINT "INTERCEPT D:                                 " AT (1, 22).
    PRINT "INTERCEPT V:                                 " AT (1, 23).
    
    // Guidance Status
    PRINT dash_line AT (0, 24).
    PRINT "GUIDANCE:                                    " AT (1, 25).
    
    // Message Log
    PRINT dash_line AT (0, 26).
    PRINT "MESSAGE LOG:" AT (1, 27).
    
    // Initialize message log lines
    LOCAL i IS 0.
    UNTIL i >= DISP_MAX_MESSAGES {
        PRINT "                                              " AT (1, 28 + i).
        SET i TO i + 1.
    }
}

// ===== UPDATE INDIVIDUAL FIELDS (NO SCREEN CLEAR) =====
FUNCTION DISP_UPDATE_REALTIME_DATA {
    // Update ship orbit data
    LOCAL ship_orbit IS DISP_STATUS_DATA["ship_orbit"].
    SET ship_orbit["ap"] TO SHIP:ORBIT:APOAPSIS.
    SET ship_orbit["pe"] TO SHIP:ORBIT:PERIAPSIS.
    SET ship_orbit["inc"] TO SHIP:ORBIT:INCLINATION.
    
    // Update target data if available
    IF HASTARGET {
        SET DISP_STATUS_DATA["target_name"] TO TARGET:NAME.
        LOCAL target_orbit IS DISP_STATUS_DATA["target_orbit"].
        SET target_orbit["ap"] TO TARGET:ORBIT:APOAPSIS.
        SET target_orbit["pe"] TO TARGET:ORBIT:PERIAPSIS.
        SET target_orbit["inc"] TO TARGET:ORBIT:INCLINATION.
        
        LOCAL range_vec IS TARGET:POSITION.
        SET DISP_STATUS_DATA["current_range"] TO range_vec:MAG.
        
        LOCAL rel_vel_vec IS SHIP:VELOCITY:ORBIT - TARGET:VELOCITY:ORBIT.
        SET DISP_STATUS_DATA["relative_velocity"] TO rel_vel_vec:MAG.
        SET DISP_STATUS_DATA["closing_velocity"] TO VDOT(rel_vel_vec, range_vec:NORMALIZED).
    }
    
    SET DISP_STATUS_DATA["rcs_active"] TO RCS.
    SET DISP_STATUS_DATA["sas_active"] TO SAS.
    
    IF SHIP:MONOPROPELLANT > 0 {
        SET DISP_STATUS_DATA["rcs_fuel"] TO SHIP:MONOPROPELLANT.
    }
}

// ===== UPDATE ONLY DYNAMIC FIELDS =====
FUNCTION DISP_UPDATE_FIELDS {
    // Update MET and Phase
    LOCAL phase_display IS DISP_PHASES[DISP_CURRENT_PHASE].
    PRINT DISP_FORMAT_TIME(TIME:SECONDS) + " | PHASE: " + phase_display + "    " AT (6, 4).
    
    // Update Status
    PRINT DISP_STATUS_DATA["guidance_status"] + "            " AT (9, 5).
    
    // Update Orbital Data
    LOCAL ship_orbit IS DISP_STATUS_DATA["ship_orbit"].
    LOCAL ship_ap_str IS DISP_FORMAT_DISTANCE(ship_orbit["ap"]).
    LOCAL ship_pe_str IS DISP_FORMAT_DISTANCE(ship_orbit["pe"]).
    LOCAL ship_inc_str IS ROUND(ship_orbit["inc"], 2) + "d".
    
    LOCAL tgt_ap_str IS "N/A   ".
    LOCAL tgt_pe_str IS "N/A   ".
    LOCAL tgt_inc_str IS "N/A   ".
    
    IF HASTARGET {
        LOCAL target_orbit IS DISP_STATUS_DATA["target_orbit"].
        SET tgt_ap_str TO DISP_FORMAT_DISTANCE(target_orbit["ap"]) + "   ".
        SET tgt_pe_str TO DISP_FORMAT_DISTANCE(target_orbit["pe"]) + "   ".
        SET tgt_inc_str TO ROUND(target_orbit["inc"], 2) + "d   ".
    }
    
    PRINT ship_ap_str + "         " + tgt_ap_str AT (6, 9).
    PRINT ship_pe_str + "        " + tgt_pe_str AT (6, 10).
    PRINT ship_inc_str + "         " + tgt_inc_str AT (6, 11).
    
    // Update Approach Data
    LOCAL target_str IS "NONE            ".
    LOCAL range_str IS "NO TARGET       ".
    LOCAL rel_vel_str IS "N/A             ".
    LOCAL closing_str IS "N/A             ".
    
    IF HASTARGET {
        SET target_str TO DISP_STATUS_DATA["target_name"] + "                    ".
        SET range_str TO DISP_FORMAT_DISTANCE(DISP_STATUS_DATA["current_range"]) + "           ".
        SET rel_vel_str TO DISP_FORMAT_VELOCITY(DISP_STATUS_DATA["relative_velocity"]) + "           ".
        SET closing_str TO DISP_FORMAT_VELOCITY(DISP_STATUS_DATA["closing_velocity"]) + "           ".
    }
    
    PRINT target_str AT (10, 14).
    PRINT range_str AT (10, 15).
    PRINT rel_vel_str AT (11, 16).
    PRINT closing_str AT (11, 17).
    
    // Update Vehicle Status
    LOCAL rcs_status IS "OFF".
    LOCAL sas_status IS "OFF".
    IF DISP_STATUS_DATA["rcs_active"] { SET rcs_status TO "ON ". }
    IF DISP_STATUS_DATA["sas_active"] { SET sas_status TO "ON ". }
    
    LOCAL rcs_fuel_str IS ROUND(DISP_STATUS_DATA["rcs_fuel"], 1) + "L     ".
    LOCAL intercept_data IS DISP_STATUS_DATA["intercept_data"].
    
    PRINT rcs_status + " | SAS: " + sas_status + " | FUEL: " + rcs_fuel_str AT (6, 20).
    PRINT ROUND(intercept_data["time"], 1) + "s       " AT (15, 21).
    PRINT DISP_FORMAT_DISTANCE(intercept_data["distance"]) + "       " AT (15, 22).
    PRINT DISP_FORMAT_VELOCITY(intercept_data["rel_vel"]) + "       " AT (15, 23).
    
    // Update Guidance Status
    LOCAL guidance_msg IS "NOMINAL            ".
    IF DISP_CURRENT_PHASE = "COMPLETE" {
        SET guidance_msg TO "MISSION COMPLETE   ".
    } ELSE IF DISP_CURRENT_PHASE = "FINAL_DOCK" {
        SET guidance_msg TO "FINAL DOCKING      ".
    } ELSE IF DISP_CURRENT_PHASE = "APPROACH" {
        SET guidance_msg TO "AUTOMATED APPROACH ".
    }
    
    PRINT guidance_msg AT (11, 25).
}

// ===== UPDATE MESSAGE LOG ONLY =====
FUNCTION DISP_UPDATE_MESSAGE_LOG_ONLY {
    LOCAL start_line IS 28.
    LOCAL i IS 0.
    
    // Clear all message lines first
    UNTIL i >= DISP_MAX_MESSAGES {
        PRINT "                                              " AT (1, start_line + i).
        SET i TO i + 1.
    }
    
    // Print current messages
    SET i TO 0.
    FOR msg IN DISP_MESSAGE_LOG {
        IF i < DISP_MAX_MESSAGES {
            LOCAL display_msg IS msg.
            IF msg:LENGTH > 46 {
                SET display_msg TO msg:SUBSTRING(0, 43) + "...".
            }
            PRINT display_msg AT (1, start_line + i).
            SET i TO i + 1.
        }
    }
}

// ===== MAIN UPDATE FUNCTION =====
FUNCTION DISP_UPDATE {
    IF NOT DISP_INITIALIZED { RETURN. }
    IF NOT DISP_SCREEN_DRAWN { RETURN. }
    
    LOCAL now IS TIME:SECONDS.
    IF now - DISP_LAST_UPDATE < DISP_UPDATE_INTERVAL { RETURN. }
    SET DISP_LAST_UPDATE TO now.
    
    // Update real-time data
    DISP_UPDATE_REALTIME_DATA().
    
    // Update only the dynamic fields (no screen clear)
    DISP_UPDATE_FIELDS().
}

// ===== FORCE REDRAW FUNCTION =====
// Use this after operations that overwrite the display (like target_picker)
FUNCTION DISP_FORCE_REDRAW {
    IF NOT DISP_INITIALIZED { RETURN. }
    
    CLEARSCREEN.
    DISP_DRAW_STATIC_LAYOUT().
    DISP_UPDATE_REALTIME_DATA().
    DISP_UPDATE_FIELDS().
    DISP_UPDATE_MESSAGE_LOG_ONLY().
    
    SET DISP_SCREEN_DRAWN TO TRUE.
}

// ===== UTILITY FUNCTIONS FOR OTHER SCRIPTS =====
FUNCTION DISP_SET_INTERCEPT {
    PARAMETER intercept_time, intercept_distance, intercept_rel_vel.
    
    LOCAL intercept_data IS DISP_STATUS_DATA["intercept_data"].
    SET intercept_data["time"] TO intercept_time.
    SET intercept_data["distance"] TO intercept_distance.
    SET intercept_data["rel_vel"] TO intercept_rel_vel.
}

FUNCTION DISP_SET_GUIDANCE {
    PARAMETER mystatus.
    DISP_UPDATE_STATUS("guidance_status", mystatus).
}

FUNCTION DISP_STATUS {
    PARAMETER phase IS "", message IS "", guidance IS "".
    
    IF phase <> "" { DISP_SET_PHASE(phase). }
    IF message <> "" { DISP_LOG(message). }
    IF guidance <> "" { DISP_SET_GUIDANCE(guidance). }
    DISP_UPDATE().
}

FUNCTION DISP_TICK {
    DISP_UPDATE().
}

FUNCTION DISP_LOG_UPDATE {
    PARAMETER message.
    DISP_LOG(message).
}

FUNCTION DISP_SUCCESS {
    PARAMETER message.
    DISP_LOG("[OK] " + message).
}

FUNCTION DISP_ERROR {
    PARAMETER message.
    DISP_LOG("[ERR] " + message).
    DISP_SET_GUIDANCE("ERROR").
    DISP_UPDATE().
}

FUNCTION DISP_WARN {
    PARAMETER message.
    DISP_LOG("[WARN] " + message).
    DISP_SET_GUIDANCE("WARNING").
    DISP_UPDATE().
}