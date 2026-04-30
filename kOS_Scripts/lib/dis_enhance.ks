// ===============================================================
// display_enhancements.ks - Additional display utilities and enhancements
// Add these functions to display.ks or run as a separate file
// ===============================================================

// Enhanced message types with color-coding (using positioning for emphasis)
GLOBAL DISP_MSG_TYPES IS LEXICON(
    "INFO", "[INFO]",
    "WARN", "[WARN]", 
    "ERROR", "[ERR ]",
    "SUCCESS", "[OK  ]",
    "PHASE", "[>>>]"
).

// Advanced logging with message types
FUNCTION DISP_LOG_TYPED {
    PARAMETER message, msg_type IS "INFO".
    
    LOCAL prefix IS DISP_MSG_TYPES[msg_type].
    LOCAL formatted_time IS DISP_FORMAT_TIME(TIME:SECONDS).
    LOCAL log_entry IS formatted_time + " " + prefix + " " + message.
    
    DISP_MESSAGE_LOG:ADD(log_entry).
    
    // Keep only the last N messages
    IF DISP_MESSAGE_LOG:LENGTH > DISP_MAX_MESSAGES {
        DISP_MESSAGE_LOG:REMOVE(0).
    }
}

// Real-time performance metrics
FUNCTION DISP_DRAW_PERFORMANCE_METRICS {
    // Add this section to show system performance
    PRINT "SYSTEM PERFORMANCE" AT (40, 17).
    
    LOCAL fps IS ROUND(1 / DISP_UPDATE_INTERVAL, 1).
    LOCAL update_lag IS ROUND((TIME:SECONDS - DISP_LAST_UPDATE) * 1000, 0).
    
    PRINT "UPDATE RATE   : " + fps + " Hz" AT (40, 19).
    PRINT "SYSTEM LAG    : " + update_lag + " ms" AT (40, 20).
    PRINT "PHASE TIME    : " + DISP_FORMAT_TIME(TIME:SECONDS - DISP_PHASE_START_TIME) AT (40, 21).
}

// Approach trajectory prediction
FUNCTION DISP_CALC_TRAJECTORY_PRED {
    PARAMETER time_ahead IS 30.  // seconds
    
    IF NOT HASTARGET { RETURN LEXICON("valid", FALSE). }
    
    LOCAL future_time IS TIME:SECONDS + time_ahead.
    LOCAL ship_future_pos IS POSITIONAT(SHIP, future_time).
    LOCAL target_future_pos IS POSITIONAT(TARGET, future_time).
    LOCAL predicted_range IS (target_future_pos - ship_future_pos):MAG.
    
    LOCAL ship_future_vel IS VELOCITYAT(SHIP, future_time):ORBIT.
    LOCAL target_future_vel IS VELOCITYAT(TARGET, future_time):ORBIT.
    LOCAL predicted_rel_vel IS (ship_future_vel - target_future_vel):MAG.
    
    RETURN LEXICON(
        "valid", TRUE,
        "range", predicted_range,
        "rel_vel", predicted_rel_vel,
        "time_ahead", time_ahead
    ).
}

// Enhanced orbital data with relative information
FUNCTION DISP_DRAW_ENHANCED_ORBITAL_DATA {
    PRINT "ORBITAL COMPARISON DATA" AT (20, 10).
    PRINT "" AT (0, 11).
    
    IF NOT HASTARGET {
        PRINT "NO TARGET - ORBITAL DATA UNAVAILABLE" AT (15, 12).
        RETURN.
    }
    
    LOCAL ship_ap IS DISP_STATUS_DATA["ship_orbit"]["ap"].
    LOCAL ship_pe IS DISP_STATUS_DATA["ship_orbit"]["pe"].
    LOCAL ship_inc IS DISP_STATUS_DATA["ship_orbit"]["inc"].
    LOCAL tgt_ap IS DISP_STATUS_DATA["target_orbit"]["ap"].
    LOCAL tgt_pe IS DISP_STATUS_DATA["target_orbit"]["pe"].
    LOCAL tgt_inc IS DISP_STATUS_DATA["target_orbit"]["inc"].
    
    // Calculate differences
    LOCAL ap_diff IS ship_ap - tgt_ap.
    LOCAL pe_diff IS ship_pe - tgt_pe.
    LOCAL inc_diff IS ship_inc - tgt_inc.
    
    LOCAL ap_diff_str IS ROUND(ap_diff/1000, 2) + " km".
    LOCAL pe_diff_str IS ROUND(pe_diff/1000, 2) + " km".
    LOCAL inc_diff_str IS ROUND(inc_diff, 3) + " deg".
    
    IF ap_diff > 0 { SET ap_diff_str TO "+" + ap_diff_str. }
    IF pe_diff > 0 { SET pe_diff_str TO "+" + pe_diff_str. }
    IF inc_diff > 0 { SET inc_diff_str TO "+" + inc_diff_str. }
    
    PRINT "PARAMETER     SHIP        TARGET      DIFFERENCE" AT (4, 12).
    PRINT "APOAPSIS      " + ROUND(ship_ap/1000,1) + " km    " + ROUND(tgt_ap/1000,1) + " km    " + ap_diff_str AT (4, 13).
    PRINT "PERIAPSIS     " + ROUND(ship_pe/1000,1) + " km    " + ROUND(tgt_pe/1000,1) + " km    " + pe_diff_str AT (4, 14).
    PRINT "INCLINATION   " + ROUND(ship_inc,2) + " deg   " + ROUND(tgt_inc,2) + " deg   " + inc_diff_str AT (4, 15).
}

// Progress bar for current phase
FUNCTION DISP_DRAW_PROGRESS_BAR {
    PARAMETER current_val, max_val, bar_width IS 30, row IS 8.
    
    LOCAL progress IS UTL_CLAMP(current_val / max_val, 0, 1).
    LOCAL filled_chars IS FLOOR(progress * bar_width).
    
    LOCAL bar_str IS "[".
    FROM {LOCAL i IS 0.} UNTIL i >= bar_width STEP {SET i TO i + 1.} DO {
        IF i < filled_chars {
            SET bar_str TO bar_str + "=".
        } ELSE IF i = filled_chars AND progress < 1 {
            SET bar_str TO bar_str + ">".
        } ELSE {
            SET bar_str TO bar_str + " ".
        }
    }
    SET bar_str TO bar_str + "] " + ROUND(progress * 100, 1) + "%".
    
    PRINT bar_str AT (4, row).
}

// Alert system for critical conditions
FUNCTION DISP_CHECK_ALERTS {
    LOCAL alerts IS LIST().
    
    IF HASTARGET {
        LOCAL myrange IS DISP_STATUS_DATA["current_range"].
        LOCAL closing IS DISP_STATUS_DATA["closing_velocity"].
        LOCAL rel_vel IS DISP_STATUS_DATA["relative_velocity"].
        
        // Collision warning
        IF myrange < 100 AND closing > 2 {
            alerts:ADD("COLLISION WARNING - HIGH CLOSING RATE").
        }
        
        // High relative velocity warning
        IF myrange < 1000 AND rel_vel > 10 {
            alerts:ADD("HIGH RELATIVE VELOCITY").
        }
        
        // Low fuel warnings
        IF DISP_STATUS_DATA["rcs_fuel"] < 10 {
            alerts:ADD("LOW RCS FUEL").
        }
        
        // Misaligned orbit warnings
        LOCAL inc_diff IS ABS(DISP_STATUS_DATA["ship_orbit"]["inc"] - DISP_STATUS_DATA["target_orbit"]["inc"]).
        IF inc_diff > 1.0 {
            alerts:ADD("INCLINATION MISMATCH > 1 DEG").
        }
    }
    
    RETURN alerts.
}

// Draw alerts section
FUNCTION DISP_DRAW_ALERTS {
    LOCAL alerts IS DISP_CHECK_ALERTS().
    
    IF alerts:LENGTH > 0 {
        PRINT "*** ALERTS ***" AT (50, 17).
        LOCAL alert_row IS 18.
        FOR alert IN alerts {
            IF alert_row < 23 {  // Don't overflow into other sections
                PRINT "! " + alert AT (50, alert_row).
                SET alert_row TO alert_row + 1.
            }
        }
    }
}

// Enhanced status display with phase-specific information
FUNCTION DISP_DRAW_PHASE_SPECIFIC {
    LOCAL phase_row IS 6.
    
    IF DISP_CURRENT_PHASE = "APPROACH" {
        LOCAL S IS APP_RELSTATE().
        LOCAL eta_to_ca IS 0.
        
        IF DEFINED INTERCEPT_T AND INTERCEPT_T > TIME:SECONDS {
            SET eta_to_ca TO INTERCEPT_T - TIME:SECONDS.
        }
        
        PRINT "APPROACH PHASE - ETA TO CA: " + ROUND(eta_to_ca, 0) + "s" AT (4, phase_row + 1).
        
        // Show approach progress based on range
        IF S["d"] > 0 {
            LOCAL approach_progress IS (10000 - S["d"]) / 10000.  // Assume starting from 10km
            DISP_DRAW_PROGRESS_BAR(approach_progress * 100, 100, 25, phase_row + 2).
        }
        
    } ELSE IF DISP_CURRENT_PHASE = "WINDOW_HOLD" {
        PRINT "STATIONKEEPING ACTIVE - MAINTAINING 200-400M WINDOW" AT (4, phase_row + 1).
        
    } ELSE IF DISP_CURRENT_PHASE = "FINAL_DOCK" {
        LOCAL S IS APP_RELSTATE().
        PRINT "FINAL DOCKING - RANGE: " + DISP_FORMAT_DISTANCE(S["d"]) AT (4, phase_row + 1).
        
        // Docking progress based on decreasing range
        IF S["d"] < 100 AND S["d"] > 0 {
            LOCAL dock_progress IS (100 - S["d"]) / 100.
            DISP_DRAW_PROGRESS_BAR(dock_progress * 100, 100, 25, phase_row + 2).
        }
    }
}

// Comprehensive update function that can replace DISP_UPDATE
FUNCTION DISP_UPDATE_COMPREHENSIVE {
    IF NOT DISP_INITIALIZED { RETURN. }
    
    LOCAL now IS TIME:SECONDS.
    IF now - DISP_LAST_UPDATE < DISP_UPDATE_INTERVAL { RETURN. }
    SET DISP_LAST_UPDATE TO now.
    
    // Update real-time data
    DISP_UPDATE_REALTIME_DATA().
    
    CLEARSCREEN.
    
    // Draw all sections
    DISP_DRAW_HEADER().
    DISP_DRAW_MISSION_STATUS().
    DISP_DRAW_ENHANCED_ORBITAL_DATA().
    DISP_DRAW_APPROACH_DATA().
    DISP_DRAW_VEHICLE_STATUS().
    DISP_DRAW_PHASE_SPECIFIC().
    DISP_DRAW_ALERTS().
    DISP_DRAW_PERFORMANCE_METRICS().
    DISP_DRAW_MESSAGE_LOG().
}

// Quick preset functions for common status updates
FUNCTION DISP_APPROACH_UPDATE {
    PARAMETER myrange, closing_vel, rel_vel.
    
    DISP_UPDATE_STATUS("current_range", myrange).
    DISP_UPDATE_STATUS("closing_velocity", closing_vel).
    DISP_UPDATE_STATUS("relative_velocity", rel_vel).
    DISP_UPDATE().
}

FUNCTION DISP_PHASE_CHANGE {
    PARAMETER new_phase, description.
    
    DISP_SET_PHASE(new_phase).
    DISP_LOG_TYPED(description, "PHASE").
    DISP_UPDATE().
}

FUNCTION DISP_ERROR {
    PARAMETER error_msg.
    
    DISP_LOG_TYPED(error_msg, "ERROR").
    DISP_SET_GUIDANCE("ERROR").
    DISP_UPDATE().
}

FUNCTION DISP_SUCCESS {
    PARAMETER success_msg.
    
    DISP_LOG_TYPED(success_msg, "SUCCESS").
    DISP_UPDATE().
}

// Integration helpers for existing functions
FUNCTION APP_RELSTATE_WITH_DISPLAY {
    LOCAL S IS APP_RELSTATE().
    
    // Update display data every time we calculate relative state
    DISP_UPDATE_STATUS("current_range", S["d"]).
    DISP_UPDATE_STATUS("closing_velocity", S["closing"]).
    DISP_UPDATE_STATUS("relative_velocity", S["v"]:MAG).
    
    RETURN S.
}

// Modified approach function example with integrated display
FUNCTION APPROACH_RCS_DISPLAY_INTEGRATED {
    PARAMETER renderRange IS AP_RENDER_RANGE, unused IS 0, planUT IS 0, strictLead IS 0.
    
    DISP_PHASE_CHANGE("APPROACH", "Beginning long-range RCS approach").
    
    // Store original function result while updating display throughout
    LOCAL approach_start_time IS TIME:SECONDS.
    LOCAL last_display_update IS TIME:SECONDS.
    
    // Phase A: Velocity Capture with display updates
    DISP_LOG_TYPED("Phase A: Velocity capture initiated", "INFO").
    
    // You would integrate these display calls into the actual APPROACH_RCS loops
    UNTIL FALSE {
        // Your existing approach logic here
        LOCAL S IS APP_RELSTATE_WITH_DISPLAY().
        
        // Update display every second during approach
        IF TIME:SECONDS - last_display_update >= 1.0 {
            DISP_LOG_TYPED("Range: " + DISP_FORMAT_DISTANCE(S["d"]) + ", Closing: " + DISP_FORMAT_VELOCITY(S["closing"]), "INFO").
            DISP_UPDATE().
            SET last_display_update TO TIME:SECONDS.
        }
        
        // Your approach completion logic
        IF S["d"] <= renderRange { BREAK. }
        
        WAIT 0.1.
    }
    
    DISP_SUCCESS("Approach phase completed successfully").
    RETURN TRUE.
}