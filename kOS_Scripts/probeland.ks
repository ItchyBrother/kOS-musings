// Simple Mun Landing Script for kOS
// Assumes deorbit burn done manually to start descent.
// Run at 50km altitude during free-fall descent.
//
// SUICIDE BURN LOGIC:
// - Calculates trigger altitude to ensure minimum lander fuel usage
// - Accounts for: solid burn, coast phase (separation), and lander burn
// - Safety margin ensures at least 50% of lander fuel is used (configurable)

// === UTILITY FUNCTIONS ===

// Returns max descent speed based on radar altitude
FUNCTION GET_MAX_SPEED {
    PARAMETER radar_alt.
    IF radar_alt < 100 { RETURN 5. }
    ELSE IF radar_alt < 500 { RETURN 20. }
    ELSE IF radar_alt < 2000 { RETURN 40. }
    RETURN 50.
}

// Generic landing phase loop
// mode: "retrograde" uses total surface speed, "vertical" uses vertical speed only
// target_alt: loop exits when landing_radar drops below this
// display_row: which row to print telemetry on
FUNCTION LANDING_PHASE {
    PARAMETER mode.
    PARAMETER target_alt.
    PARAMETER display_row.
    PARAMETER gain IS 1.6.
    PARAMETER min_throt IS 0.
    PARAMETER ascent_limit IS 0.5.

    UNTIL landing_radar < target_alt {
        LOCAL vdown IS MAX(0, -SHIP:VERTICALSPEED).
        LOCAL hspeed IS SHIP:GROUNDSPEED.
        LOCAL max_speed IS GET_MAX_SPEED(landing_radar).

        // Choose speed reference based on mode
        LOCAL speed_ref IS vdown.
        IF mode = "retrograde" {
            SET speed_ref TO SHIP:VELOCITY:SURFACE:MAG.
        }

        // Proportional throttle calculation
        LOCAL speed_offset IS CHOOSE 3 IF mode = "retrograde" ELSE 2.
        LOCAL target_throt IS MIN(1, MAX(min_throt, (speed_ref - max_speed + speed_offset) * SHIP:MASS * gain / (SHIP:MAXTHRUST + 0.001))).

        LOCK THROTTLE TO target_throt.

        // Telemetry display
        PRINT ROUND(landing_radar, 0) + "    " AT (8, display_row).
        PRINT ROUND(vdown, 0) + "    " AT (22, display_row).
        PRINT ROUND(hspeed, 0) + "    " AT (36, display_row).
        PRINT ROUND(target_throt * 100, 0) + "%  " AT (52, display_row).

        // Emergency cutoff if ascending
        IF SHIP:VERTICALSPEED > ascent_limit {
            LOCK THROTTLE TO 0.
        }

        WAIT 0.01.
    }
}

// === MAIN SCRIPT ===

CLEARSCREEN.
PRINT "=== Mun Landing Script ===" AT (0,0).
PRINT "Waiting for Mun SOI..." AT (0,2).

WAIT UNTIL SHIP:BODY:NAME = "Mun".

PRINT "In Mun SOI!" AT (0,2).
PRINT " Waiting until 150km from surface." AT(0,3).

// --- Simple deacceleration routine run by Centaur --- //
//WAIT UNTIL SHIP:ALTITUDE <= 150000.
// PRINT "Initiating Pre-descent sequence." AT (0,4).
// RCS ON.
// SAS OFF.
// AG9 OFF. //ENGINES ON.
// LOCK STEERING TO SRFRETROGRADE.
// WAIT UNTIL SHIP:ALTITUDE <=100000.
// LOCK THROTTLE TO 1.
// WAIT UNTIL SHIP:VERTICALSPEED > -70.
// LOCK THROTTLE TO 0.
// AG9 ON. //ENGINES OFF.
// WAIT 0.2.
PRINT "Pre-descent sequence ended. " AT (0,5).
PRINT "Staging in (3) seconds."  AT (0,6).
WAIT 3.
STAGE.
CLEARSCREEN.
// ---  End of Centaur --- //

PRINT "Activating RCS on Lander" AT (0,3).
AG7 ON.  //Activates RCS/Opens RCS tanks/Set Probe as Control point.
PRINT "Waiting for 50 km altitude..." AT (0,4).

WAIT UNTIL SHIP:ALTITUDE <= 50000.

PRINT "At 50 km!" AT (0,5).
PRINT "RCS ON, Pointing RETROGRADE." AT (0,6).

RCS ON.
SAS OFF.
LOCK STEERING TO RETROGRADE.

WAIT 0.1.

// === SUICIDE BURN PARAMETERS ===
SET mun_g TO 1.63.                // Mun surface gravity
SET solid_twr TO 11.21.           // Solid motor TWR on Mun
SET solid_dv TO 409.              // Solid motor delta-V
SET lander_twr TO 2.53.           // Lander engines TWR on Mun
SET coast_time TO 3.0.            // Time between solid burnout and lander ignition (separation + spool-up)
SET safety_margin TO 3.5.         // Safety multiplier (2.0 = 100% extra margin) - TUNE DOWN once working

// Calculate net accelerations (TWR * g - g = net deceleration)
SET solid_accel TO solid_twr * mun_g - mun_g.    // 16.64 m/s²
SET lander_accel TO lander_twr * mun_g - mun_g.  // 2.49 m/s²

CLEARSCREEN.
PRINT "=== SUICIDE BURN CALCULATOR ===" AT (0,0).
PRINT "Safety margin: " + ROUND(safety_margin, 2) + "x (" + ROUND((safety_margin-1)*100, 0) + "% extra)" AT (0,1).
PRINT "Coast time: " + coast_time + " seconds" AT (0,2).
//PRINT "Press any key to start monitoring..." AT (0,4).
//WAIT UNTIL TERMINAL:INPUT:HASCHAR.
//TERMINAL:INPUT:GETCHAR().

CLEARSCREEN.
PRINT "=== Monitoring Descent ===" AT (0,0).
PRINT "Safety margin: " + ROUND(safety_margin, 2) + "x" AT (0,1).
PRINT "Alt (km):       VSpeed (m/s):      Trigger (km):" AT (0,3).

SET triggered TO FALSE.
UNTIL triggered {
    SET vspeed TO ABS(SHIP:VERTICALSPEED).
    
    // ITERATIVE: Find trigger altitude accounting for continued free-fall
    SET trigger_alt TO 15000.  // Initial guess
    SET converged TO FALSE.
    SET iterations TO 0.
    
    UNTIL converged OR iterations > 10 {
        // Calculate velocity at trigger altitude (accounting for free-fall from current altitude)
        LOCAL fall_distance IS SHIP:ALTITUDE - trigger_alt.
        LOCAL v_at_trigger IS SQRT(vspeed^2 + 2 * mun_g * fall_distance).
        
        // Now calculate altitude lost during burn starting from v_at_trigger
        LOCAL alt_lost IS 0.
        LOCAL v_remaining IS v_at_trigger.
        
        // Solid motor phase - using proper kinematic equation
        IF v_remaining > solid_dv {
            LOCAL solid_time IS solid_dv / solid_accel.
            // Kinematic: distance = v₀t - ½at²
            LOCAL solid_alt_lost IS v_remaining * solid_time - 0.5 * solid_accel * solid_time^2.
            SET alt_lost TO alt_lost + solid_alt_lost.
            SET v_remaining TO v_remaining - solid_dv.
            
            // Coast phase (separation + engine spool-up) - FREE FALL!
            LOCAL coast_alt_lost IS v_remaining * coast_time + 0.5 * mun_g * coast_time^2.
            LOCAL coast_dv_gained IS mun_g * coast_time.
            SET alt_lost TO alt_lost + coast_alt_lost.
            SET v_remaining TO v_remaining + coast_dv_gained.
        } ELSE {
            LOCAL solid_time IS v_remaining / solid_accel.
            LOCAL solid_alt_lost IS v_remaining * solid_time - 0.5 * solid_accel * solid_time^2.
            SET alt_lost TO alt_lost + solid_alt_lost.
            SET v_remaining TO 0.
        }
        
        // Lander engine phase - using proper kinematic equation
        IF v_remaining > 0 {
            LOCAL lander_time IS v_remaining / lander_accel.
            LOCAL lander_alt_lost IS v_remaining * lander_time - 0.5 * lander_accel * lander_time^2.
            SET alt_lost TO alt_lost + lander_alt_lost.
        }
        
        // Apply safety margin (1.5 = 50% extra trigger altitude)
        LOCAL new_trigger IS alt_lost * safety_margin.
        
        // Check convergence
        IF ABS(new_trigger - trigger_alt) < 100 {
            SET converged TO TRUE.
        }
        SET trigger_alt TO new_trigger.
        SET iterations TO iterations + 1.
    }
    
    // Display telemetry
    PRINT ROUND(SHIP:ALTITUDE/1000, 1) + "   " AT (12, 4).
    PRINT ROUND(vspeed, 0) + "   " AT (28, 4).
    PRINT ROUND(trigger_alt/1000, 1) + " km   " AT (48, 4).
    
    // Trigger suicide burn when altitude drops below calculated trigger altitude
    IF SHIP:ALTITUDE <= trigger_alt AND vspeed > 50 {
        PRINT ">>> SUICIDE BURN TRIGGERED! <<<" AT (0,5).
        PRINT "Vertical speed: " + ROUND(vspeed, 0) + " m/s" AT (0,6).
        LOCAL predicted_v IS SQRT(vspeed^2 + 2 * mun_g * (SHIP:ALTITUDE - trigger_alt)).
        PRINT "Predicted V at trigger: " + ROUND(predicted_v, 0) + " m/s" AT (0,7).
        PRINT "Coast phase: " + coast_time + "s @ ~" + ROUND(predicted_v - solid_dv, 0) + " m/s" AT (0,8).
        LOCK THROTTLE TO 0.
        AG6 ON.  //actives solid motor and activates lander engines.
        WAIT 0.1.
        SET triggered TO TRUE.
    }
    WAIT 0.1.
}

WAIT 1.  // Give solid motor time to spool up

PRINT "Solid rocket ignited. Waiting for burnout..." AT (0,10).
PRINT "Fuel remaining:          " AT (0,11).

LOCK THROTTLE TO 0.  // Keep lander engine OFF during solid burn

// Wait for solid fuel to deplete
UNTIL SHIP:SOLIDFUEL < 1 {
    PRINT ROUND(SHIP:SOLIDFUEL, 0) + "   " AT (17, 11).
    WAIT 0.1.
}

//PRINT "DEBUG - Fuel depleted!" AT (0,13).

PRINT ">>> BURNOUT DETECTED <<<" AT (0,15).
PRINT "Altitude: " + ROUND(SHIP:ALTITUDE, 0) + "m" AT (0,16).
PRINT "Vertical Speed: " + ROUND(ABS(SHIP:VERTICALSPEED), 0) + " m/s" AT (0,17).

// Calculate if lander can stop from here
LOCAL remaining_v IS ABS(SHIP:VERTICALSPEED).
LOCAL stop_dist IS remaining_v^2 / (2 * lander_accel).
PRINT "Lander needs: " + ROUND(stop_dist, 0) + "m to stop" AT (0,18).
PRINT "We have: " + ROUND(SHIP:ALTITUDE, 0) + "m available" AT (0,19).

IF stop_dist > SHIP:ALTITUDE {
    PRINT "*** WARNING: INSUFFICIENT ALTITUDE ***" AT (0,20).
}

PRINT "Waiting " + coast_time + "s to eject booster..." AT (0,21).

WAIT coast_time.

AG5 ON.
WAIT 0.1.
PRINT "Booster ejected!" AT (0,23).

PRINT "Post-coast altitude: " + ROUND(SHIP:ALTITUDE, 0) + "m" AT (0,24).
PRINT "Post-coast velocity: " + ROUND(ABS(SHIP:VERTICALSPEED), 0) + " m/s" AT (0,25).

// Recalculate if lander can stop from here
SET remaining_v TO ABS(SHIP:VERTICALSPEED).
SET stop_dist TO remaining_v^2 / (2 * lander_accel).
LOCAL actual_burn_time IS remaining_v / lander_accel.
PRINT "Lander NOW needs: " + ROUND(stop_dist, 0) + "m" AT (0,26).
PRINT "Margin: " + ROUND((SHIP:ALTITUDE / stop_dist - 1) * 100, 0) + "% extra altitude" AT (0,27).

GEAR ON.
PRINT "GEAR DOWN!" AT (0,28).

WAIT 0.1.

// === SOFT LANDING PHASE ===
CLEARSCREEN.
PRINT "=== SOFT LANDING PHASE ===" AT (0,0).
PRINT "Radar:          VDown:          HSpeed:          Throttle:" AT (0,4).

SET radar_h TO 2.
LOCK landing_radar TO ALT:RADAR - radar_h.
RCS ON.

// Phase 1: Retrograde burn - kills all velocity
LOCK STEERING TO SHIP:SRFRETROGRADE.
PRINT "Phase 1: Retrograde decel" AT (0,2).
LANDING_PHASE("retrograde", 120, 5, 2.0, 0.02, 1).

// Phase 2: Vertical soft touchdown
LOCK THROTTLE TO 0.
LOCK STEERING TO UP.
PRINT "Phase 2: Vertical soft land" AT (0,2).
LANDING_PHASE("vertical", radar_h + 1, 5, 1.6, 0, 0.5).

// === SHUTDOWN ===
LOCK THROTTLE TO 0.
UNLOCK STEERING.
UNLOCK THROTTLE.
RCS OFF.

CLEARSCREEN.
PRINT "=== LANDED SUCCESSFULLY ON MUN! ===" AT (0,0).
PRINT "Status: " + SHIP:STATUS AT (0,2).
PRINT "Altitude: " + ROUND(SHIP:ALTITUDE, 1) + " m" AT (0,3).
PRINT "Vertical Speed: " + ROUND(SHIP:VERTICALSPEED, 1) + " m/s" AT (0,4).

WAIT 10.
