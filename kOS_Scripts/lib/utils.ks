FUNCTION UTL_CLAMP {
  PARAMETER x, lo, hi.
  RETURN MAX(lo, MIN(hi, x)).
}

FUNCTION UTL_PAD2 {
  PARAMETER n.
  LOCAL i IS FLOOR(n).
  IF i < 10 { RETURN "0" + i. } ELSE { RETURN "" + i. }
}

FUNCTION UTL_FMTETA {
  PARAMETER ut.
  LOCAL dt IS ut - TIME:SECONDS.
  IF dt < 0 { SET dt TO 0. }
  LOCAL h IS FLOOR(dt / 3600).
  LOCAL m IS FLOOR((dt - h*3600) / 60).
  LOCAL s IS FLOOR(dt - h*3600 - m*60).
  RETURN h + ":" + UTL_PAD2(m) + ":" + UTL_PAD2(s).
}

FUNCTION UTL_FMTDIST {
  PARAMETER meters.
  IF meters >= 1000 {
    RETURN ROUND(meters / 1000.0, 3) + " km".
  } ELSE {
    RETURN ROUND(meters, 1) + " m".
  }
}

// ---- RCS DEBUG HELPERS ----
FUNCTION UTL_SET_RCS {
  PARAMETER on IS TRUE, tag IS "".
  IF on {
    IF NOT RCS { DISP_LOG_UPDATE("DBG RCS ON  [" + tag + "]."). }
    RCS ON.
  } ELSE {
    IF RCS { DISP_LOG_UPDATE("DBG RCS OFF [" + tag + "]."). }
    RCS OFF.
  }
}

// Already shared earlier, but keep it here for convenience:
FUNCTION UTL_KILL_TRANSLATION {
  SET SHIP:CONTROL:STARBOARD  TO 0.
  SET SHIP:CONTROL:TOP        TO 0.
  SET SHIP:CONTROL:FORE       TO 0.
  SET SHIP:CONTROL:PITCH      TO 0.
  SET SHIP:CONTROL:YAW        TO 0.
  SET SHIP:CONTROL:ROLL       TO 0.
  SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
}

FUNCTION SHIP_RESET {
  UNLOCK STEERING.  
  WAIT 0.5.
  SET SHIP:CONTROL:NEUTRALIZE TO TRUE.  // Resets all control inputs (including RCS translation)
  WAIT 5.
  RCS OFF. // Disables RCS thrusters
  PRINT "RCS OFF and STEERING DISABLED.".
  WAIT 0.5.
  UNLOCK ALL.
  WAIT 5.
  SAS ON.
  WAIT 1.
  PRINT "SAS TURNED ON.  STABILITY SET.".
}

// Enhanced function that waits for the message to be delivered
FUNCTION EMail2Tgt {
    PARAMETER msgContent.
    
    IF NOT HASTARGET {
        DISP_ERROR("No target vessel set.").
        RETURN FALSE.
    }
    
    SET targetConnection TO TARGET:CONNECTION.
    
    IF NOT targetConnection:ISCONNECTED {
        DISP_ERROR("Target vessel '" + TARGET:NAME + "' is not connected.").
        RETURN FALSE.
    }
    
    DISP_LOG_UPDATE("Sending message to: " + TARGET:NAME).
    DISP_LOG_UPDATE("Message type: " + msgContent[0]).
    
    targetConnection:SENDMESSAGE(msgContent).
    
    // Wait for message to be delivered (delay + 1 second buffer)
    SET deliveryTime TO targetConnection:DELAY + 1.
    DISP_LOG_UPDATE("Waiting " + deliveryTime + " seconds for delivery...").
    WAIT deliveryTime.
    DISP_SUCCESS("Message delivered to " + TARGET:NAME + ".").
    
    RETURN TRUE.
}

// ═══════════════════════════════════════════════════════
// NODE EXECUTION
// ═══════════════════════════════════════════════════════

FUNCTION EXECUTE_NODE {
  PARAMETER toggle_stage, agNum, target_pe IS -1.
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  MANEUVER NODE EXECUTION                       ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    LOCAL nd IS NEXTNODE.
    
    PRINT "NODE PARAMETERS:".
    PRINT "  Time to burn:    T+" + ROUND(nd:ETA/60, 1) + " min".
    PRINT "  Delta-V:         " + ROUND(nd:DELTAV:MAG, 1) + " m/s".
    PRINT " ".
    


    // Calculate burn time
    LOCAL dv IS nd:DELTAV:MAG.
    LOCAL isp IS 0.
    LOCAL thrust IS 0.

    IF toggle_stage {
      ToggleEngine(agNum, TRUE).
      WAIT 0.5.
    }
    
    LOCAL eng_list IS LIST().
    LIST ENGINES IN eng_list.
    FOR eng IN eng_list {
        IF eng:IGNITION {
            SET thrust TO thrust + eng:AVAILABLETHRUST.
            SET isp TO isp + (eng:ISP * eng:AVAILABLETHRUST).
        }
    }
    
    //PRINT "DEBUG: Thrust = " + thrust + ", ISP = " + isp.  // ADD THIS DEBUG

    LOCAL burn_duration IS 0.
    IF thrust > 0 {
        SET isp TO isp / thrust.
        LOCAL ve IS isp * 9.81.
        SET burn_duration TO ve * SHIP:MASS * (1 - CONSTANT:E^(-dv/ve)) / thrust.
    }
    
    LOCAL half_burn IS burn_duration / 2.
    
    PRINT "  Burn duration:   " + ROUND(burn_duration, 1) + " sec".
    PRINT " ".
    
    PRINT "(P) PROCEED   (C) CANCEL".
    
    LOCAL confirmed IS FALSE.
    UNTIL confirmed {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
            IF ch = "P" {
                SET confirmed TO TRUE.
            } ELSE IF ch = "C" {
                PRINT "Node execution cancelled.".
                WAIT 2.
                RETURN.
            }
        }
        WAIT 0.1.
    }
    
    // Orient to node
    PRINT "Orienting to burn attitude...".
    SAS OFF.
    RCS ON.
    LOCK STEERING TO nd:DELTAV.
    
    WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, nd:DELTAV) < 1.0.
    
    // Wait for burn time
    WAIT UNTIL nd:ETA <= half_burn.

    PRINT "IGNITION!".
    
    // Execute burn
    UNTIL nd:DELTAV:MAG < 0.5 {
        LOCAL dv_remaining IS nd:DELTAV:MAG.

        // If target_pe was specified, monitor it
      IF target_pe > 0 {
          IF SHIP:ORBIT:HASNEXTPATCH AND SHIP:ORBIT:NEXTPATCH:BODY = KERBIN {
              LOCAL current_pe IS SHIP:ORBIT:NEXTPATCH:PERIAPSIS.
              
              // Cut burn if we hit target Pe (±3km tolerance)
              IF ABS(current_pe - target_pe) < 3000 AND current_pe > (target_pe - 1000) {
                  PRINT "Target Pe achieved: " + ROUND(current_pe/1000, 1) + " km - CUTOFF".
                  BREAK.
              }
          }
      }    
      
                // Smooth throttle control
        LOCAL throttle_setting IS 0.
        IF dv_remaining > 20 {
            SET throttle_setting TO 1.0.
        } ELSE IF dv_remaining > 10 {
            SET throttle_setting TO 0.5 + (dv_remaining - 10) / 20.
        } ELSE IF dv_remaining > 5 {
            SET throttle_setting TO 0.25 + (dv_remaining - 5) / 20.
        } ELSE IF dv_remaining > 2 {
            SET throttle_setting TO 0.1 + (dv_remaining - 2) / 20.
        } ELSE IF dv_remaining > 0.5 {
            SET throttle_setting TO 0.05 + (dv_remaining - 0.5) / 30.
        } ELSE {
            SET throttle_setting TO MAX(0.01, dv_remaining / 50).
        }


        LOCK THROTTLE TO throttle_setting.
        LOCK STEERING TO nd:DELTAV.
        
        WAIT 0.01.
    }
    
    LOCK THROTTLE TO 0.
       IF toggle_stage {
      ToggleEngine(agNum, FALSE).
    }
    UNLOCK STEERING.
    UNLOCK THROTTLE.

    // CRITICAL: Clear all control inputs
    SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
    WAIT 1.
    
    REMOVE nd.
    SAS ON.
    PRINT "Burn complete!".
    WAIT 3.
}


FUNCTION ToggleEngine {
    PARAMETER agNum, state IS TRUE.  // state = TRUE for ON, FALSE for OFF
    IF agNum = -1 {  } // -1 Action Group not used.
    ELSE IF agNum = 1 { IF state { AG1 ON. } ELSE { AG1 OFF. } }
    ELSE IF agNum = 2 { IF state { AG2 ON. } ELSE { AG2 OFF. } }
    ELSE IF agNum = 3 { IF state { AG3 ON. } ELSE { AG3 OFF. } }
    ELSE IF agNum = 4 { IF state { AG4 ON. } ELSE { AG4 OFF. } }
    ELSE IF agNum = 5 { IF state { AG5 ON. } ELSE { AG5 OFF. } }
    ELSE IF agNum = 6 { IF state { AG6 ON. } ELSE { AG6 OFF. } }
    ELSE IF agNum = 7 { IF state { AG7 ON. } ELSE { AG7 OFF. } }
    ELSE IF agNum = 8 { IF state { AG8 ON. } ELSE { AG8 OFF. } }
    ELSE IF agNum = 9 { IF state { AG9 ON. } ELSE { AG9 OFF. } }
    ELSE IF agNum = 10 { IF state { AG10 ON. } ELSE { AG10 OFF. } }
}