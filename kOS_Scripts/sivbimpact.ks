@LAZYGLOBAL OFF.

PARAMETER MainEng IS 9, StageUllage IS 8.

// Using MainEng to switch Action Group toggle from TRUE to FALSE.  -1 = FALSE/ Otherwise True.

RUNONCEPATH("0:/lib/utils.ks").

IF MainEng = 0 {
    PRINT "Parameters are Main Engine Action Group, Ullage Action Group.".
    PRINT "Run sivbimpact Main, Ullage.".
    PRINT "Default is 9 and 8.".
    WAIT UNTIL FALSE.
}
RCS ON.

//AG9 ON.  //turning off Third Stage engines as it will not be used.
// ═══════════════════════════════════════════════════════
// APOLLO S-IVB IMPACT SCRIPT
// Run after CSM separation
// ═══════════════════════════════════════════════════════

FUNCTION DISPLAY_HEADER {
    PARAMETER title.
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  APOLLO S-IVB IMPACT MANEUVER                  ║".
    PRINT "╠════════════════════════════════════════════════╣".
    PRINT "║  " + title.
    LOCAL padding IS 47 - title:LENGTH.
    FROM {LOCAL i IS 0.} UNTIL i >= padding STEP {SET i TO i + 1.} DO {
        PRINT " " AT(0,0).
    }
    PRINT "║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
}

FUNCTION MAIN {
    
    SET TARGET TO MUN.
    
    // ═══════════════════════════════════════════════════════
    // STEP 1: Check current trajectory
    // ═══════════════════════════════════════════════════════
    
    DISPLAY_HEADER("TRAJECTORY ANALYSIS").
    
    IF NOT (SHIP:ORBIT:HASNEXTPATCH AND SHIP:ORBIT:NEXTPATCH:BODY = MUN) {
        PRINT "ERROR: No Mun encounter detected!".
        PRINT "Run TMI script first.".
        RETURN.
    }
    
    LOCAL current_mun_pe IS SHIP:ORBIT:NEXTPATCH:PERIAPSIS.
    LOCAL mun_radius IS MUN:RADIUS.
    LOCAL current_altitude IS current_mun_pe.  // PERIAPSIS is already altitude!

    
    PRINT "CURRENT MUN ENCOUNTER:".
    PRINT "  Periapsis:       " + ROUND(current_mun_pe/1000, 1) + " km".
    PRINT "  Altitude:        " + ROUND(current_altitude/1000, 1) + " km".
    PRINT "  Time to Mun:     T+" + ROUND(ETA:TRANSITION/3600, 1) + " hours".
    PRINT " ".
    
    // IF current_altitude < 5000 {
    //     PRINT "Trajectory already on impact course!".
    //     PRINT "No correction needed.".
    //     RETURN.
    // }
    IF current_mun_pe < 1000 {  // Pe within 1km of surface
        PRINT "Trajectory already on impact course!".
        PRINT "Altitude: " + ROUND(current_altitude/1000, 1) + " km".
        PRINT "No correction needed.".
        RETURN.
    }
    
    LOCAL dv_estimate IS SQRT(current_altitude / 50).
    
    PRINT "CORRECTION REQUIRED:".
    PRINT "  Target:          Surface impact (0 km)".
    PRINT "  Estimated dV:    ~" + ROUND(dv_estimate, 1) + " m/s".
    PRINT " ".
    
    PRINT "═══════════════════════════════════════════════════".
    PRINT " ".
    PRINT "(P) PROCEED WITH IMPACT BURN".
    PRINT "(C) CANCEL".
    PRINT " ".
    PRINT "Awaiting confirmation...".
    
    LOCAL confirmed IS FALSE.
    UNTIL confirmed {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
            IF ch = "P" {
                SET confirmed TO TRUE.
                PRINT " ".
                PRINT "BURN CONFIRMED - PROCEEDING".
            } ELSE IF ch = "C" {
                PRINT " ".
                PRINT "MANEUVER CANCELLED".
                RETURN.
            }
        }
        WAIT 0.1.
    }
    
    // ═══════════════════════════════════════════════════════
    // STEP 2: Orient S-IVB
    // ═══════════════════════════════════════════════════════
    
    DISPLAY_HEADER("S-IVB ORIENTATION").
    
    PRINT "Orienting S-IVB for correction burn...".
    SAS OFF.
    RCS OFF.
    
    LOCK STEERING TO RETROGRADE.
    
    WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, RETROGRADE:FOREVECTOR) < 2.0.
    
    PRINT "Orientation locked to retrograde.".
    PRINT " ".
    PRINT "Starting ullage motors in 3 seconds...".
    WAIT 3.
    
    // ═══════════════════════════════════════════════════════
    // STEP 3: Ullage correction burn
    // ═══════════════════════════════════════════════════════
    
    DISPLAY_HEADER("ULLAGE CORRECTION BURN").
    
    LOCAL mun_radius IS MUN:RADIUS.
    
    PRINT "Ullage motors FIRING...".
    PRINT " ".
    
    //AG8 OFF.  // Fire ullage motors
    IF MainEng = -1 {
        ToggleEngine(StageUllage, FALSE).
    } ELSE {
        ToggleEngine(StageUllage, TRUE).
    }
    LOCK THROTTLE TO 1.
    LOCAL burn_start IS TIME:SECONDS.
    LOCAL last_update IS TIME:SECONDS.
    
    // Burn until Pe reaches surface
    UNTIL SHIP:ORBIT:NEXTPATCH:PERIAPSIS <= 1000 {
        
        IF TIME:SECONDS - last_update > 1 {
            LOCAL elapsed IS TIME:SECONDS - burn_start.
            LOCAL current_pe IS SHIP:ORBIT:NEXTPATCH:PERIAPSIS.
            LOCAL pe_altitude IS current_pe / 1000.
            
            PRINT "Burn: " + ROUND(elapsed, 1) + "s | Mun Pe: " + ROUND(pe_altitude, 1) + " km".
            SET last_update TO TIME:SECONDS.
        }
        
        // Safety cutoff after 60 seconds
        IF TIME:SECONDS - burn_start > 60 {
            PRINT " ".
            PRINT "Safety cutoff - maximum burn time reached".
            BREAK.
        }
        
        WAIT 0.1.
    }
    
    //AG8 ON.  // Shut off ullage motors
    IF MainEng = -1 {
        ToggleEngine(StageUllage, TRUE).
    } ELSE {
        ToggleEngine(StageUllage, FALSE).
    }
    LOCK THROTTLE TO 0.
    PRINT " ".
    PRINT "Ullage motors SHUTDOWN.".
    
    // ═══════════════════════════════════════════════════════
    // STEP 4: Verify impact trajectory
    // ═══════════════════════════════════════════════════════
    
    WAIT 2.
    
    DISPLAY_HEADER("IMPACT TRAJECTORY CONFIRMED").
    
    LOCAL final_pe IS SHIP:ORBIT:NEXTPATCH:PERIAPSIS.
    LOCAL final_altitude IS final_pe / 1000.
    
    PRINT "FINAL TRAJECTORY:".
    PRINT "  Mun Periapsis:   " + ROUND(final_pe/1000, 1) + " km".
    PRINT "  Altitude:        " + ROUND(final_altitude, 1) + " km".
    PRINT " ".
    
    IF final_altitude < 1 {
        PRINT "  ✓ IMPACT TRAJECTORY CONFIRMED".
        PRINT "  ✓ S-IVB will impact Mun surface".
    } ELSE {
        PRINT "  ⚠ Altitude still above surface".
        PRINT "  ⚠ May require additional correction".
    }
    
    PRINT " ".
    PRINT "══════════════════════════════════════════════════".
    PRINT " ".
    PRINT "S-IVB IMPACT MANEUVER COMPLETE".
    
    RCS OFF.
    UNLOCK STEERING.
}

MAIN().