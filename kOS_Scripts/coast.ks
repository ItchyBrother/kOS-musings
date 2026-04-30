@LAZYGLOBAL OFF.

PARAMETER MainEng IS 7, StageUllage IS -1.

// Using StageUllage to switch Action Group toggle from TRUE to FALSE.  -1 DEFAULT = TRUE/0 = FALSE.

RUNONCEPATH("0:/lib/utils.ks").
RUNONCEPATH("0:/lib/mcc.ks").

IF MainEng = 0 {
    PRINT "Parameters are Main Engine Action Group, Ullage Action Group.".
    PRINT "Run sivbimpact Main, Ullage.".
    PRINT "Default is 7 and -1.".
    WAIT UNTIL FALSE.
}

// ═══════════════════════════════════════════════════════
// APOLLO IN-FLIGHT MONITORING & CONTROL
// Barbecue Roll + Telemetry + Node Execution
// Press 'X' to exit
// ═══════════════════════════════════════════════════════

FUNCTION MAIN {
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  APOLLO IN-FLIGHT MONITORING SYSTEM            ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    PRINT "Initializing...".
    PRINT " ".
    
    // Barbecue roll setup
    LOCAL bbq_active IS FALSE.
    LOCAL target_roll_rate IS 0.3.  // deg/sec (~3 rotations/hour)
    
    PRINT "(B) Toggle Barbecue Roll".
    PRINT "(M) Mid-Course Correction (POST TKI)".
    PRINT "(N) Execute Maneuver Node (if present)".
    PRINT "(X) Exit monitoring".
    PRINT " ".
    PRINT "Starting in 3 seconds...".
    WAIT 3.
    
    // Main monitoring loop
    LOCAL running IS TRUE.
    LOCAL last_update IS TIME:SECONDS.
    
    UNTIL NOT running {
        
        // Update display every 2 seconds
        IF TIME:SECONDS - last_update > 2 {
            
            CLEARSCREEN.
            PRINT "╔════════════════════════════════════════════════╗".
            PRINT "║  APOLLO IN-FLIGHT MONITORING                   ║".
            PRINT "╚════════════════════════════════════════════════╝".
            PRINT " ".
            
            // Mission elapsed time
            PRINT "MISSION STATUS:".
            PRINT "  MET:             " + MISSIONTIME_FORMAT().
            PRINT "  Universal Time:  " + TIME_FORMAT(TIME:SECONDS).
            PRINT " ".
            
            // Position data
            PRINT "POSITION:".
            PRINT "  Altitude:        " + ROUND(SHIP:ALTITUDE/1000, 1) + " km".
            PRINT "  Velocity:        " + ROUND(SHIP:VELOCITY:ORBIT:MAG, 1) + " m/s".
            
            LOCAL dist_kerbin IS (SHIP:POSITION - KERBIN:POSITION):MAG.
            PRINT "  Distance Kerbin: " + ROUND(dist_kerbin/1000, 0) + " km".
            
            //IF TARGET = MUN {
                LOCAL dist_mun IS (SHIP:POSITION - MUN:POSITION):MAG.
                PRINT "  Distance Mun:    " + ROUND(dist_mun/1000, 0) + " km".
            //}
            PRINT " ".
            
            // Next event
            IF SHIP:ORBIT:HASNEXTPATCH {
                PRINT "NEXT EVENT:".
                PRINT "  SOI Change:      " + SHIP:ORBIT:NEXTPATCH:BODY:NAME.
                PRINT "  Time:            T+" + TIME_FORMAT(ETA:TRANSITION).
            } ELSE IF HASNODE {
                PRINT "NEXT EVENT:".
                PRINT "  Maneuver Node".
                PRINT "  Time:            T+" + TIME_FORMAT(NEXTNODE:ETA).
                PRINT "  Delta-V:         " + ROUND(NEXTNODE:DELTAV:MAG, 1) + " m/s".
            }
            PRINT " ".
            
            // Barbecue roll status
            PRINT "PASSIVE THERMAL CONTROL:".
            IF bbq_active {
                PRINT "  BBQ Roll:        ACTIVE".
                PRINT "  Roll Rate:       " + ROUND(SHIP:ANGULARVEL:MAG * (180/CONSTANT:PI), 2) + " deg/s".
            } ELSE {
                PRINT "  BBQ Roll:        INACTIVE".
            }
            PRINT " ".
            
            PRINT "═════════════════════════════════════════════════".
            PRINT " ".
            PRINT "(B) Toggle BBQ Roll  (M)id-Course Correction ".
            PRINT "(N) Execute Node     (X) Exit".
            
            SET last_update TO TIME:SECONDS.
        }
        
        // Check for commands
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
            
            IF ch = "B" {
                SET bbq_active TO NOT bbq_active.
                IF bbq_active {
                    START_BBQ_ROLL(target_roll_rate).
                } ELSE {
                    STOP_BBQ_ROLL().
                }
            // In the input handler:
            }ELSE IF ch = "M" {
                EXECUTE_MCC().
                // Return to main monitoring loop
            } ELSE IF ch = "N" {
                IF HASNODE {
                    IF StageUllage = 0{
                        ToggleEngine(MainEng, FALSE).
                        EXECUTE_NODE(FALSE, MainEng).  
                        WAIT 2.
                        ToggleEngine(MainEng, TRUE).
                    } ELSE {
                        EXECUTE_NODE(TRUE, MainEng).  //DEFAULT Action group 7 Turn ON.
                        WAIT 2.
                        ToggleEngine(MainEng, FALSE).
                    }
                }
            } ELSE IF ch = "X" {
                SET running TO FALSE.
            }
        }
        
        // Maintain barbecue roll if active
        IF bbq_active {
            MAINTAIN_BBQ_ROLL(target_roll_rate).
        }
        
        WAIT 0.1.
    }
    
    PRINT " ".
    PRINT "Monitoring terminated.".
    

    // Clean Shutdown
    UNLOCK STEERING.
    UNLOCK THROTTLE.
    SET SHIP:CONTROL:NEUTRALIZE TO TRUE.

    IF bbq_active {
        STOP_BBQ_ROLL().
    }

    RUNPATH ("0:/rcsreset.ks").
}

// ═══════════════════════════════════════════════════════
// BARBECUE ROLL FUNCTIONS
// ═══════════════════════════════════════════════════════

FUNCTION START_BBQ_ROLL {
    PARAMETER target_rate.
    
    PRINT "Initiating barbecue roll...".
    
    SAS OFF.
    RCS ON.
    UNLOCK STEERING.
    SHIP:CONTROL:NEUTRALIZE.
    WAIT 1.
    
    // Single gentle pulse to start rotation
    PRINT "Starting rotation pulse...".
    SET SHIP:CONTROL:ROLL TO 0.03.
    WAIT 2.0.  // Let it spin up
    SET SHIP:CONTROL:ROLL TO 0.
    
    PRINT "BBQ roll established - coasting at constant rate".
    PRINT "Press B to toggle off when needed.".
}

FUNCTION MAINTAIN_BBQ_ROLL {
    PARAMETER target_rate.
    
    // Do absolutely NOTHING
    // Physics handles it - no friction = constant spin!
}

FUNCTION STOP_BBQ_ROLL {
    PRINT "Stopping BBQ roll...".
    
    // Counter-pulse to cancel rotation
    SET SHIP:CONTROL:ROLL TO -0.03.
    WAIT 2.0.
    SET SHIP:CONTROL:ROLL TO 0.
    
    SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
    WAIT 1.
    SAS ON.
    
    PRINT "BBQ roll stopped.".
}


// ═══════════════════════════════════════════════════════
// TIME FORMATTING
// ═══════════════════════════════════════════════════════

FUNCTION TIME_FORMAT {
    PARAMETER seconds.
    
    LOCAL hours IS FLOOR(seconds / 3600).
    LOCAL mins IS FLOOR((seconds - hours * 3600) / 60).
    LOCAL secs IS FLOOR(seconds - hours * 3600 - mins * 60).
    
    RETURN hours + ":" + mins:TOSTRING:PADLEFT(2):REPLACE(" ","0") + ":" + secs:TOSTRING:PADLEFT(2):REPLACE(" ","0").
}

FUNCTION MISSIONTIME_FORMAT {
    RETURN TIME_FORMAT(MISSIONTIME).
}

// ═══════════════════════════════════════════════════════
// MID-COURSE CORRECTION - LANDING ZONE TARGETING
// ═══════════════════════════════════════════════════════
//   NOW FOUND IN LIB mcc.ks.

// FUNCTION EXECUTE_MCC {
    
//     PRINT "CURRENTLY NOT WORKING.".
//     WAIT 10.

//     RETURN.
// }


MAIN().