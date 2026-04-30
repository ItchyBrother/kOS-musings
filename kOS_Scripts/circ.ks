// KOS Script: circ.ks
// Establish an orbit with given apoapsis, periapsis, and orbit mode
// Version 4.14 - Modular throttle-adjusted orbit with Ap monitoring and continuous thrust
// Version 5.0 - Revised node_to_orbit function
// Version 5.1 - Add a retrograde option if the Ap or Pe is too high in node_to_orbit.
// Version 5.2 - Added failsafe so that when burning to raise Pe, Target Ap will never be exceeded. 
// Version 5.3 - Added forceRCS parameter to use just RCS for orbit adjustment. Just for orbit mode 0.
// Version 5.4 - Added better failsafe for Ap/Pe in Orbit mode 0. 
//  SET target_Ap TO 150000.
//  SET target_Pe TO 85000.
//  SET orbitMode TO 2.


PARAMETER target_Ap, target_Pe, orbitMode, forceRCS IS FALSE.
RCS OFF.
SAS OFF.

// Initial setup
PRINT "Establishing orbit: Target Ap = " + ROUND(target_Ap, 0) + " m, Target Pe = " + ROUND(target_Pe, 0) + " m.".
SET mu TO SHIP:BODY:MU.
SET body_radius TO SHIP:BODY:RADIUS.

// Global throttleable flag
GLOBAL throttleable IS FALSE.
//GLOBAL burn_complete TO FALSE.

SET engine_active TO check_engines().

CLEARSCREEN.
PRINT "Orbit Mode: " AT (0, 0).
PRINT "Target Ap: " + ROUND(target_Ap, 0) + " m" AT (0, 1).
PRINT "Target Pe: " + ROUND(target_Pe, 0) + " m" AT (0, 2).

// Atmosphere check
SET in_atmo TO SHIP:BODY:ATM:EXISTS AND SHIP:ALTITUDE < SHIP:BODY:ATM:HEIGHT.
IF in_atmo {
    PRINT "In atmosphere (height: " + ROUND(SHIP:BODY:ATM:HEIGHT, 0) + " m)." AT (0, 3).
}

// Main logic based on orbitMode
IF orbitMode = 0 { 
    PRINT "Coast to Orbit (Maneuver Node)" AT (12, 0).
    node_to_orbit(target_Ap, target_Pe, forceRCS).
} ELSE IF orbitMode = 1 { 
    PRINT "Throttle Adjusted Orbit" AT (12, 0).
    throttle_adjusted_to_orbit(target_Ap, target_Pe).
} ELSE IF orbitMode = 2 { 
    PRINT "Continuous Burn to Orbit" AT (12, 0).
    continuous_burn_to_orbit(target_Ap, target_Pe).
} ELSE {
    PRINT "Invalid orbitMode: " + orbitMode + ". Defaulting to Continuous Burn." AT (12, 0).
    continuous_burn_to_orbit(target_Ap, target_Pe).
}

// Logging Function - Separated for toggling
FUNCTION log_orbit_data {
    PARAMETER start_time, throttle_val, pitch_val, state_val, radial_vel_val, horiz_vel_val.
    
    // Log header (run once manually if needed)
    // LOG "Time,Altitude,Ap,Pe,TTA,Throttle,PitchAdjust,State,RadialVel,HorizVel" TO "orbit_log_v10.csv".
    
    SET log_line TO (TIME:SECONDS - start_time) + "," +
                    ROUND(SHIP:ALTITUDE/1000, 1) + "," +
                    ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + "," +
                    ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + "," +
                    ROUND(ETA:APOAPSIS, 1) + "," +
                    ROUND(throttle_val * 100, 1) + "," +
                    ROUND(pitch_val, 2) + "," +
                    state_val + "," +
                    ROUND(radial_vel_val, 1) + "," +
                    ROUND(horiz_vel_val, 1).
    LOG log_line TO "orbit_log_v10.csv".
}

// Check engines
FUNCTION check_engines {
    LIST ENGINES IN myEngines.
    SET engine_active TO FALSE.
    FOR eng IN myEngines {
        IF eng:IGNITION AND NOT eng:FLAMEOUT {
            SET engine_active TO TRUE.
            SET throttleable TO NOT eng:THROTTLELOCK.
            PRINT "Active Engine: " + eng:NAME + ", Throttleable: " + throttleable AT (0, 2).
            WAIT 0.1.
            RETURN engine_active.
        }
    }
    IF NOT engine_active AND myEngines:LENGTH > 0 {
        SET throttleable TO NOT myEngines[0]:THROTTLELOCK.
        PRINT "No active engines. First Engine: " + myEngines[0]:NAME + ", Throttleable: " + throttleable AT (0, 2).
        WAIT 0.1.
        RETURN FALSE.
    }
    PRINT "No engines found." AT (0, 2).
    WAIT 10.
    RETURN FALSE.
}

// Function for Coast to Orbit with Maneuver Node (orbitMode = 0)
FUNCTION node_to_orbit {
    PARAMETER target_Ap, target_Pe, forceRCS.
    
    IF forceRCS {
        RCS ON.
    }

    IF SHIP:ALTITUDE < 70000 {
        PRINT "Pending atmosphere exit..." AT (0, 5).
        LOCK STEERING TO PROGRADE.
        WAIT UNTIL SHIP:ALTITUDE >= 70000.
    }

    // Raise Periapsis at Apoapsis
    IF SHIP:ORBIT:PERIAPSIS < target_Pe - 500 OR SHIP:ORBIT:PERIAPSIS > target_Pe + 1000 {
        PRINT "Creating maneuver node to raise Periapsis." AT (0, 6).

        SET r_ap TO SHIP:ORBIT:APOAPSIS + SHIP:BODY:RADIUS.
        SET r_pe_target TO target_Pe + SHIP:BODY:RADIUS.
        SET sma TO (r_ap + r_pe_target) / 2.
        SET v_new TO SQRT(SHIP:BODY:MU * (2 / r_ap - 1 / sma)).
        SET current_v TO VELOCITYAT(SHIP, TIME:SECONDS + ETA:APOAPSIS):ORBIT:MAG.
        SET delta_v TO v_new - current_v.

        SET is_retrograde_pe TO FALSE.
        IF SHIP:ORBIT:PERIAPSIS > target_Pe + 1000 {
            SET delta_v TO -ABS(delta_v).
            SET is_retrograde_pe TO TRUE.
            PRINT ">>>> RETOGRADE bur to LOWER Pe <<<<" AT (0, 7).
        } ELSE {
            PRINT ">>>> PROGRADE burn to RAISE Pe <<<<" AT (0, 7).
        }

        SET node_time TO TIME:SECONDS + ETA:APOAPSIS.
        SET maneuver_node TO NODE(node_time, 0, 0, delta_v).
        ADD maneuver_node.

        PRINT "Node to raise Pe by " + ROUND(delta_v, 1) + " m/s at Ap." AT (0, 7).

        SET burn_dv TO maneuver_node:DELTAV:MAG.
        SET thrust TO SHIP:MAXTHRUST.
        
        IF NOT forceRCS {
            IF thrust <= 0 {
                SET forceRCS TO TRUE.
            } ELSE {
            SET burn_duration TO (burn_dv * SHIP:MASS) / thrust.
            SET burn_start TO node_time - (burn_duration / 2).      
            SET twr TO thrust / (SHIP:MASS * SHIP:BODY:MU / (SHIP:ALTITUDE + SHIP:BODY:RADIUS)^2).
            SET lock_dv TO MIN(50, 10 * twr).

            PRINT "Burn duration: " + ROUND(burn_duration, 1) + " s" AT (0, 8).
            PRINT "TWR: " + ROUND(twr, 2) AT (0, 9).
            PRINT "Lock DV: " + ROUND(lock_dv, 1) + " m/s" AT (0, 10).
            }
        }

        IF forceRCS{ 
            SET burn_start to node_time.
            SET lock_dv TO 10.
            RCS ON.
        }

        LOCK STEERING TO maneuver_node:DELTAV.
        WAIT UNTIL TIME:SECONDS >= burn_start.
        LOCK THROTTLE TO 1.
        PRINT "Burn started to raise Pe..." AT (0, 11).

        SET K_dv TO 0.01.
        SET switched TO FALSE.
        SET last_remaining_dv TO maneuver_node:DELTAV:MAG.
        SET last_time TO TIME:SECONDS.

        UNTIL maneuver_node:DELTAV:MAG <= 0.1 
           OR (NOT is_retrograde_pe AND SHIP:ORBIT:PERIAPSIS >= target_Pe) //{
           OR (is_retrograde_pe AND SHIP:ORBIT:PERIAPSIS <= target_Pe + 1000)
           OR (NOT is_retrograde_pe AND SHIP:ORBIT:APOAPSIS > target_Ap + 1000) {  // <--- Added fail-safe: abort if Ap is exceeded

            SET remaining_dv TO maneuver_node:DELTAV:MAG.
            PRINT "Remaining DV: " + ROUND(remaining_dv, 1) + " m/s" AT (0, 12).
            PRINT "Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS, 0) + " m" AT (0, 13).
            PRINT "Ap: " + ROUND(SHIP:ORBIT:APOAPSIS, 0) + " m" AT (0, 14).  // <--- New print

            SET current_mass TO SHIP:MASS.
            SET current_thrust TO SHIP:AVAILABLETHRUST.

            IF current_thrust > 0 {
                SET acceleration TO current_thrust / current_mass.
                SET dynamic_burn_time TO remaining_dv / acceleration.
                PRINT "Est. Remaining Burn Time: " + ROUND(dynamic_burn_time, 1) + " s" AT (0, 16).
            }

            IF remaining_dv <= lock_dv AND NOT switched {
                IF is_retrograde_pe {
                    LOCK STEERING TO RETROGRADE.
                    PRINT "Locked steering to retrograde." AT (0, 17).
                } ELSE {
                LOCK STEERING TO SHIP:VELOCITY:ORBIT:NORMALIZED.
                PRINT "Locked steering to velocity vector." AT (0, 17).
                }
                SET switched TO TRUE.
            }

            IF ABS(remaining_dv - last_remaining_dv) < 0.1 AND TIME:SECONDS - last_time > 5 {
                BREAK.
            } ELSE {
                SET last_remaining_dv TO remaining_dv.
                SET last_time TO TIME:SECONDS.
            }

            IF forceRCS {
                LOCK THROTTLE TO 1.
            } ELSE {
            SET current_throttle TO K_dv * remaining_dv.
            SET current_throttle TO MAX(0.1, MIN(1.0, current_throttle)).
            LOCK THROTTLE TO current_throttle.
            }
            WAIT 0.1.
        }

        LOCK THROTTLE TO 0.
        UNLOCK STEERING.
        REMOVE maneuver_node.
        PRINT "Periapsis now at " + ROUND(SHIP:ORBIT:PERIAPSIS, 0) + " m." AT (0, 18).
    }

    // Raise or Lower Apoapsis at Periapsis
    IF SHIP:ORBIT:APOAPSIS < target_Ap - 500 OR SHIP:ORBIT:APOAPSIS > target_Ap + 500 {
        PRINT "Creating maneuver node to adjust Apoapsis." AT (0, 16).

        SET r_pe TO SHIP:ORBIT:PERIAPSIS + SHIP:BODY:RADIUS.
        SET r_ap_target TO target_Ap + SHIP:BODY:RADIUS.
        SET sma TO (r_pe + r_ap_target) / 2.
        SET v_new TO SQRT(SHIP:BODY:MU * (2 / r_pe - 1 / sma)).
        SET current_v TO VELOCITYAT(SHIP, TIME:SECONDS + ETA:PERIAPSIS):ORBIT:MAG.
        SET delta_v TO v_new - current_v.

        // IF too high, invert delta_v to retrograde the burn
        SET is_retrograde TO FALSE.
        IF SHIP:ORBIT:APOAPSIS > target_Ap + 500 {
            SET delta_v TO -ABS(delta_v). // Ensure retrograde
            SET is_retrograde TO TRUE.
        }

        SET node_time TO TIME:SECONDS + ETA:PERIAPSIS.
        SET maneuver_node TO NODE(node_time, 0, 0, delta_v).
        ADD maneuver_node.

        PRINT "Node to adjust Ap by " + ROUND(delta_v, 1) + " m/s at Pe." AT (0, 17).

        SET burn_dv TO maneuver_node:DELTAV:MAG.
        SET thrust TO SHIP:MAXTHRUST.
        
        IF NOT forceRCS {
            IF thrust <= 0 {
                SET forceRCS TO TRUE.
            } ELSE {
            SET burn_duration TO (burn_dv * SHIP:MASS) / thrust.
            SET burn_start TO node_time - (burn_duration / 2).
            SET twr TO thrust / (SHIP:MASS * SHIP:BODY:MU / (SHIP:ALTITUDE + SHIP:BODY:RADIUS)^2).
            SET lock_dv TO MIN(50, 10 * twr).

            PRINT "Burn duration: " + ROUND(burn_duration, 1) + " s" AT (0, 18).
            PRINT "TWR: " + ROUND(twr, 2) AT (0, 19).
            PRINT "Lock DV: " + ROUND(lock_dv, 1) + " m/s" AT (0, 20).
            }
        }

        IF forceRCS {
            SET burn_start TO node_time.
            SET lock_dv to 10.
            RCS ON.
        }

        LOCK STEERING TO maneuver_node:DELTAV.
        WAIT UNTIL TIME:SECONDS >= burn_start.
        LOCK THROTTLE TO 1.
        PRINT "Burn started to adjust Ap..." AT (0, 21).

        SET K_dv TO 0.01.
        SET switched TO FALSE.
        SET last_remaining_dv TO maneuver_node:DELTAV:MAG.
        SET last_time TO TIME:SECONDS.

        //UNTIL maneuver_node:DELTAV:MAG <= 0.5 OR ABS(SHIP:ORBIT:APOAPSIS - target_Ap) <= 500 {
        UNTIL maneuver_node:DELTAV:MAG <= 0.5 
        OR (NOT is_retrograde AND SHIP:ORBIT:APOAPSIS >= target_Ap - 1000)
        OR (is_retrograde AND SHIP:ORBIT:APOAPSIS <= target_Ap + 1000) {
            SET remaining_dv TO maneuver_node:DELTAV:MAG.
            PRINT "Remaining DV: " + ROUND(remaining_dv, 1) + " m/s" AT (0, 22).
            PRINT "Ap: " + ROUND(SHIP:ORBIT:APOAPSIS, 0) + " m" AT (0, 23).

            IF remaining_dv <= lock_dv AND NOT switched {
                // Only lock to velocity vector if it's a prograde burn
                IF is_retrograde{
                    LOCK STEERING TO RETROGRADE.
                    PRINT "Locked steering to retograde." AT (0, 24).

                }
                IF delta_v > 0 {
                    LOCK STEERING TO SHIP:VELOCITY:ORBIT:NORMALIZED.
                    PRINT "Locked steering to velocity vector." AT (0, 24).
                }
                SET switched TO TRUE.
            }

            IF ABS(remaining_dv - last_remaining_dv) < 0.1 AND TIME:SECONDS - last_time > 5 {
                BREAK.
            } ELSE {
                SET last_remaining_dv TO remaining_dv.
                SET last_time TO TIME:SECONDS.
            }

            IF forceRCS {
                LOCK THROTTLE TO 1.
            } ELSE {
            SET current_throttle TO K_dv * remaining_dv.
            SET current_throttle TO MAX(0.1, MIN(1.0, current_throttle)).
            LOCK THROTTLE TO current_throttle.
            }
            WAIT 0.1.
        }

        LOCK THROTTLE TO 0.
        UNLOCK STEERING.
        REMOVE maneuver_node.
        PRINT "Apoapsis now at " + ROUND(SHIP:ORBIT:APOAPSIS, 0) + " m." AT (0, 25).
    }
    RCS OFF.
    // Final check
    PRINT "Final Orbit: Ap = " + ROUND(SHIP:ORBIT:APOAPSIS, 0) + " m, Pe = " + ROUND(SHIP:ORBIT:PERIAPSIS, 0) + " m." AT (0, 26).
}

// Throttle and Pitch adjusted orbit function.
// Version 10 - Smooth Throttle and Pitch Control, No Coasting
FUNCTION throttle_adjusted_to_orbit {
    PARAMETER target_Ap, target_Pe.

    // Configuration
    SET min_throttle TO 0.1.       // Minimum throttle to avoid coasting
    SET max_throttle TO 1.0.       // Maximum throttle
    SET target_tta TO 35.          // Target TTA in seconds
    SET K_tta TO 0.01.             // Throttle gain for TTA control
    SET K_pe TO 0.05.              // Pitch gain for Pe control
    SET K_ap TO 0.001.             // Throttle gain for final Ap adjustment
    SET atmo_height TO SHIP:BODY:ATM:HEIGHT. // 70 km for Kerbin
    SET tolerance TO 500.          // +/- 500 meters tolerance
    SET fail_safe_Ap TO target_Ap * .10 + target_Ap.   // 10% over target_Ap for fail-safe

    // Initial Setup
    SET twr TO SHIP:AVAILABLETHRUST / (SHIP:MASS * SHIP:BODY:MU / (SHIP:ALTITUDE + SHIP:BODY:RADIUS)^2).
    SET current_throttle TO MIN(1.0, 0.6 / twr). // Initial throttle based on TWR
    LOCK THROTTLE TO current_throttle.
    SET pitch_adjust TO 0.
    LOCK STEERING TO PROGRADE + R(0, pitch_adjust, 0).
    SET start_time TO TIME:SECONDS.

    // Initial Display
    PRINT "Targeting Ap " + ROUND(target_Ap/1000, 1) + " km, Pe " + ROUND(target_Pe/1000, 1) + " km" AT (0, 4).
    PRINT "Fail Safe is: " + ROUND(fail_safe_Ap) + " km".  
    WAIT 10.  //FOR DEBUG
    // Main Loop
    SET fail_safe_triggered TO FALSE.
    UNTIL (SHIP:ORBIT:APOAPSIS >= target_Ap - tolerance AND SHIP:ORBIT:PERIAPSIS >= target_Pe - tolerance) OR fail_safe_triggered {
        IF SHIP:AVAILABLETHRUST <= 0 {
            LOCK THROTTLE TO 0. UNLOCK THROTTLE. UNLOCK STEERING.
            PRINT "No thrust. Aborting." AT (0, 6). RETURN.
        }

        // Calculations
        SET twr TO SHIP:AVAILABLETHRUST / (SHIP:MASS * SHIP:BODY:MU / (SHIP:ALTITUDE + SHIP:BODY:RADIUS)^2).
        SET radial_vel TO VDOT(SHIP:VELOCITY:ORBIT, SHIP:UP:VECTOR).
        SET horiz_vel TO VDOT(SHIP:VELOCITY:ORBIT, SHIP:SRFPROGRADE:VECTOR).
        SET current_tta TO ETA:APOAPSIS.

        // Fail-Safe
        IF SHIP:ORBIT:APOAPSIS > fail_safe_Ap {
            SET current_throttle TO min_throttle. // Minimum thrust instead of 0
            SET fail_safe_triggered TO TRUE.
            SET state TO "Fail-Safe".
            PRINT "Fail-Safe: Ap > " + ROUND(fail_safe_Ap/1000, 1) + " km" AT (0, 6).
        } ELSE {
            // State Logic
            IF SHIP:ORBIT:APOAPSIS < atmo_height {
                // Step 1: Escape Atmosphere
                SET current_throttle TO 0.5.
                SET pitch_adjust TO 10.
                SET state TO "Escape Atmosphere".
            } ELSE IF SHIP:ORBIT:PERIAPSIS < target_Pe - tolerance {
                // Step 2: Smoothly Control TTA and Raise Pe
                SET tta_error TO target_tta - current_tta.
                SET pe_error TO target_Pe - SHIP:ORBIT:PERIAPSIS.
                SET throttle_adjustment TO K_tta * tta_error.
                SET current_throttle TO current_throttle + throttle_adjustment.
                SET current_throttle TO MAX(min_throttle, MIN(max_throttle, current_throttle)).
                SET pitch_adjust TO K_pe * pe_error / 1000.
                SET pitch_adjust TO MAX(-10, MIN(20, pitch_adjust)).
                SET state TO "Control TTA and Raise Pe".
            } ELSE {
                // Step 3: Finalize Ap with Horizontal Burn
                SET ap_error TO target_Ap - SHIP:ORBIT:APOAPSIS.
                SET current_throttle TO K_ap * ap_error.
                SET current_throttle TO MAX(min_throttle, MIN(max_throttle, current_throttle)).
                SET pitch_adjust TO 0.
                SET state TO "Finalize Ap".
            }
        }

        // Apply Controls
        LOCK THROTTLE TO current_throttle.
        LOCK STEERING TO PROGRADE + R(0, pitch_adjust, 0).

        // Optional Logging - Uncomment to enable
        // log_orbit_data(start_time, current_throttle, pitch_adjust, state, radial_vel, horiz_vel).

        // Display
        CLEARSCREEN.
        PRINT "Throttle Adjusted Burn to Orbit" AT (0,0).
        PRINT "Sustainer Burn Status" AT (0, 1).
        PRINT "---------------------" AT (0, 2).
        PRINT "Altitude: " + ROUND(SHIP:ALTITUDE/1000, 1) + " km" AT (0, 7).
        PRINT "Ap: " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km" AT (0, 8).
        PRINT "Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0, 9).
        PRINT "TTA: " + ROUND(current_tta, 1) + " s" AT (0, 10).
        PRINT "Throttle: " + ROUND(current_throttle * 100, 1) + "%" AT (0, 11).
        PRINT "Pitch: " + ROUND(pitch_adjust, 1) + " deg" AT (0, 12).
        PRINT "State: " + state AT (0, 13).

        WAIT 0.1.
    }

    // Cleanup
    LOCK THROTTLE TO 0.
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
    UNLOCK THROTTLE.
    UNLOCK STEERING.
    PRINT "Final Ap: " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km" AT (0, 14).
    PRINT "Final Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0, 15).
    IF fail_safe_triggered { PRINT "Terminated: Fail-Safe." AT (0, 16). }
    ELSE { PRINT "Orbit achieved." AT (0, 16). }
}

// Function for Continuous Burn to Orbit (orbitMode = 2)
// Version 6.3 - Mercury-Atlas Sustainer, Dynamic Pitch with Smooth Initial Ramp
// Version 6.4 - Added atmospheric escape phase for low-TWR vehicles
FUNCTION continuous_burn_to_orbit {
    PARAMETER target_Ap, target_Pe.
    LOCAL fuel_critical IS FALSE.
    LOCAL last_pitch_cmd IS 0.
    LOCK THROTTLE TO 1.0.
    PRINT "Sustainer burn initiated at " + ROUND(SHIP:ALTITUDE/1000, 1) + " km." AT (0, 5).

    LIST ENGINES IN myEngines.
    LOCAL avg_isp IS 0.
    LOCAL active_engine_count IS 0.

    FOR eng IN myEngines {
        IF eng:IGNITION AND NOT eng:FLAMEOUT {
            SET avg_isp TO avg_isp + eng:ISP.
            SET active_engine_count TO active_engine_count + 1.
        }
    }
    IF active_engine_count > 0 { SET avg_isp TO avg_isp / active_engine_count. }
    ELSE { 
        SET avg_isp TO 300.
        PRINT "Warning: Using fallback Isp = 300 s." AT (0, 6).
    }

    LOCAL g0 IS 9.80665.
    LOCAL safety_ap_limit IS target_Ap * .10 + target_Ap.
    LOCAL atmo_height IS SHIP:BODY:ATM:HEIGHT.

    // **NEW: Determine if we need atmospheric escape phase**
    LOCAL initial_ap IS SHIP:ORBIT:APOAPSIS.
    LOCAL needs_atmo_escape IS initial_ap < atmo_height + 5000.
    LOCAL atmo_escape_complete IS FALSE.

    // Target Ap should reach target_Pe altitude during escape phase
    LOCAL atmo_escape_target IS target_Pe.

    // But ensure it's at least 15km above atmosphere for safety
    IF atmo_escape_target < atmo_height + 25000 {
        SET atmo_escape_target TO atmo_height + 25000.
    }

    // TTA management parameters
    LOCAL target_tta IS 45.  // Target time-to-apoapsis in seconds

    IF needs_atmo_escape {
        PRINT "LOW INITIAL AP DETECTED: " + ROUND(initial_ap/1000, 1) + " km" AT (0, 7).
        PRINT "Atmospheric escape mode active." AT (0, 8).
        PRINT "Escape Target Ap: " + ROUND(atmo_escape_target/1000, 1) + " km" AT (0, 9).
        PRINT "Target TTA: " + ROUND(target_tta, 0) + " seconds" AT (0, 10).
        WAIT 3.
    }

    UNLOCK STEERING.

    UNTIL fuel_critical {
        LOCAL current_thrust IS SHIP:AVAILABLETHRUST.
        LOCAL current_mass IS SHIP:MASS.
        LOCAL delta_v_left IS avg_isp * g0 * LN(current_mass / SHIP:DRYMASS).
        IF current_thrust = 0 {
            SET burn_time_left TO 0.
        } ELSE {        
            SET burn_time_left TO (current_mass - SHIP:DRYMASS) * (avg_isp * g0) / current_thrust.
        }
        IF burn_time_left < 10 OR current_thrust <= 0 {
            SET fuel_critical TO TRUE.
            PRINT "Fuel critical or depleted." AT (0, 7).
            BREAK.
        }

        LOCAL altNow IS SHIP:ALTITUDE.
        LOCAL peNow IS SHIP:ORBIT:PERIAPSIS.
        LOCAL current_ap IS SHIP:ORBIT:APOAPSIS.
        LOCAL vert_vel IS VDOT(SHIP:VELOCITY:ORBIT, SHIP:UP:VECTOR).
        LOCAL current_tta IS ETA:APOAPSIS.
        LOCAL pitch_adjust IS 0.

        // **PHASE 1 - ATMOSPHERIC ESCAPE WITH TTA CONTROL**
        IF needs_atmo_escape AND NOT atmo_escape_complete {
            IF current_ap >= atmo_escape_target * 0.98 {
                SET atmo_escape_complete TO TRUE.
                PRINT "Atmospheric escape complete! Ap = " + ROUND(current_ap/1000, 1) + " km" AT (0, 11).
                PRINT "Transitioning to normal insertion..." AT (0, 12).
                WAIT 2.
            } ELSE {
                // **TTA-based pitch control**
                LOCAL tta_error IS current_tta - target_tta.
                LOCAL Kp_tta IS 0.5.  // TTA proportional gain - tune this
                
                // Base pitch on how close we are to target Ap
                LOCAL ap_progress IS current_ap / atmo_escape_target.
                LOCAL base_pitch IS 25.  // Start steep
                
                // Gradually reduce pitch as Ap grows
                IF ap_progress > 0.3 {
                    SET base_pitch TO 25 * (1 - ((ap_progress - 0.3) / 0.7)).
                    SET base_pitch TO MAX(0, base_pitch).  // Don't go negative yet
                }
                
                // Adjust pitch based on TTA error
                // If TTA too short (< target), pitch up to raise Ap more
                // If TTA too long (> target), pitch down to flatten trajectory
                LOCAL tta_adjustment IS -Kp_tta * tta_error.
                SET pitch_adjust TO base_pitch + tta_adjustment.
                
                // Clamp pitch to reasonable range
                SET pitch_adjust TO MIN(30, MAX(-10, pitch_adjust)).
                
                // Safety: If Ap getting too close to target, flatten aggressively
                IF current_ap > atmo_escape_target * 0.9 {
                    SET pitch_adjust TO MIN(pitch_adjust, -5).
                }
                IF current_ap > atmo_escape_target * 0.95 {
                    SET pitch_adjust TO MIN(pitch_adjust, -15).
                }
                
                LOCK STEERING TO HEADING(90, pitch_adjust).
                
                // Display for escape phase
                CLEARSCREEN.
                PRINT "Continuous Burn to Orbit" AT (0,0).
                PRINT "PHASE: Atmospheric Escape (TTA Control)" AT (0, 1).
                PRINT "---------------------" AT (0, 2).
                PRINT "Escape Ap: " + ROUND(atmo_escape_target/1000, 1) + " km" AT (0, 3).
                PRINT "Target TTA: " + ROUND(target_tta, 0) + " s" AT (0, 4).
                PRINT "---------------------" AT (0, 5).
                PRINT "Altitude:  " + ROUND(altNow/1000, 1) + " km" AT (0, 6).
                PRINT "Ap:        " + ROUND(current_ap/1000, 1) + " km (" + ROUND(ap_progress * 100, 0) + "%)" AT (0, 7).
                PRINT "Pe:        " + ROUND(peNow/1000, 1) + " km" AT (0, 8).
                PRINT "TTA:       " + ROUND(current_tta, 1) + " s" AT (0, 9).
                PRINT "TTA Error: " + ROUND(tta_error, 1) + " s" AT (0, 10).
                PRINT "DeltaV:    " + ROUND(delta_v_left, 1) + " m/s" AT (0, 11).
                PRINT "Pitch:     " + ROUND(pitch_adjust, 1) + "°" AT (0, 12).
                PRINT "VertVel:   " + ROUND(vert_vel, 1) + " m/s" AT (0, 13).
                
                WAIT 0.1.
            }
        }
        
        // **PHASE 2 - NORMAL ORBITAL INSERTION**
        IF NOT needs_atmo_escape OR atmo_escape_complete {
            
            // Dynamic Pe target based on altitude
            LOCAL effective_target_Pe IS target_Pe.
            
            IF altNow < atmo_height {
                LOCAL atmo_factor IS 1 - (altNow / atmo_height).
                LOCAL pe_overshoot IS 8000 * atmo_factor.
                SET effective_target_Pe TO target_Pe + pe_overshoot.
            } ELSE IF altNow < atmo_height + 10000 {
                SET effective_target_Pe TO target_Pe + 3000.
            } ELSE {
                SET effective_target_Pe TO target_Pe.
            }

            // Inline VV target schedule
            LOCAL vv_tgt IS 600.
            IF altNow >= 30000 { SET vv_tgt TO 500. }
            IF altNow >= 40000 { SET vv_tgt TO 360. }
            IF altNow >= 50000 { SET vv_tgt TO 160. }
            IF altNow >= 60000 { SET vv_tgt TO 80. }
            IF altNow >= 80000 { SET vv_tgt TO 20. }
            IF altNow >= 100000 { SET vv_tgt TO 5. }
            IF altNow >= 120000 { SET vv_tgt TO 0. }

            IF peNow > effective_target_Pe * 0.95 { SET vv_tgt TO 0. }

            // Error & Proportional pitch command controller
            LOCAL vv_err IS vert_vel - vv_tgt.
            LOCAL Kp IS 0.04.
            LOCAL pitch_cmd IS -Kp * vv_err.

            // PRIORITIZE Ap HOLD
            IF current_ap >= target_Ap * 0.75 {
                IF current_ap < target_Ap * 0.85 {
                    SET pitch_cmd TO MIN(pitch_cmd, -15).
                }
                ELSE IF current_ap < target_Ap * .95 {
                    SET pitch_cmd TO MIN(pitch_cmd, -25).
                }
                ELSE {
                    SET pitch_cmd TO MIN(pitch_cmd, -40).
                }
            }

            IF SHIP:ORBIT:PERIAPSIS >= effective_target_Pe * 0.95 {
                IF current_ap > target_Ap * 1.02 { SET pitch_cmd TO MIN(pitch_cmd, -35). }
                IF current_ap > target_Ap * 1.05 { SET pitch_cmd TO MIN(pitch_cmd, -45). }
            }

            SET pitch_cmd TO MIN(15, MAX(-35, pitch_cmd)).
            SET pitch_adjust TO (0.5 * last_pitch_cmd) + (0.5 * pitch_cmd).
            SET last_pitch_cmd TO pitch_adjust.

            LOCK STEERING TO HEADING(90, pitch_adjust).

            // Primary cutoff
            IF current_ap >= target_Ap * 0.98 AND SHIP:ORBIT:PERIAPSIS >= effective_target_Pe {
                LOCK THROTTLE TO 0.0.
                PRINT "PRIMARY CUTOFF: Ap=" + ROUND(current_ap/1000, 1) + " km, Pe=" + ROUND(peNow/1000, 1) + " km" AT (0, 19).
                BREAK.
            }

            // Safety cutoff
            IF current_ap > safety_ap_limit {
                LOCK THROTTLE TO 0.0.
                PRINT "FAIL-SAFE CUTOFF: Ap > " + ROUND(safety_ap_limit/1000, 1) + " km" AT (0, 19).
                BREAK.
            }

            // Display for normal phase
            CLEARSCREEN.
            PRINT "Continuous Burn to Orbit" AT (0,0).
            PRINT "PHASE: Orbital Insertion" AT (0, 1).
            PRINT "---------------------" AT (0, 2).
            PRINT "Target Ap: " + ROUND(target_Ap/1000, 1) + " km" AT (0, 3).
            PRINT "Target Pe: " + ROUND(target_Pe/1000, 1) + " km" AT (0, 4).
            PRINT "---------------------" AT (0, 5).
            PRINT "Altitude:  " + ROUND(altNow/1000, 1) + " km" AT (0, 6).
            PRINT "Ap:        " + ROUND(current_ap/1000, 1) + " km" AT (0, 7).
            PRINT "Pe:        " + ROUND(peNow/1000, 1) + " km" AT (0, 8).
            PRINT "DeltaV:    " + ROUND(delta_v_left, 1) + " m/s" AT (0, 9).
            PRINT "Pitch:     " + ROUND(pitch_adjust, 1) + "°" AT (0, 10).
            PRINT "VertVel:   " + ROUND(vert_vel, 1) + " m/s" AT (0, 11).
            IF altNow < atmo_height {
                PRINT "Eff Pe Tgt: " + ROUND(effective_target_Pe/1000, 1) + " km" AT (0, 12).
            }

            // Secondary Safety cutoff
            IF current_ap > target_Ap AND SHIP:ORBIT:PERIAPSIS >= effective_target_Pe {
                LOCK THROTTLE TO 0.0.
                PRINT "SECONDARY SAFETY CUTOFF: Target orbit achieved." AT (0, 20).
                BREAK.
            }
            
            WAIT 0.1.
        }
    }

    LOCK THROTTLE TO 0.0.
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
    PRINT "SECO at " + ROUND(SHIP:ALTITUDE/1000, 1) + " km." AT (0, 24).
    PRINT "Final Ap: " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km" AT (0, 25).
    PRINT "Final Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0, 26).

}