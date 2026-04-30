// KOS Script: circ.ks
// Establish an orbit with given apoapsis, periapsis, and orbit mode
// Version 4.14 - Modular throttle-adjusted orbit with Ap monitoring and continuous thrust
// Version 5.0 - Revised node_to_orbit function

PARAMETER target_Ap, target_Pe, orbitMode.

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
    node_to_orbit(target_Ap, target_Pe).
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
    PARAMETER target_Ap, target_Pe.

    IF SHIP:ALTITUDE < 70000 {
        PRINT "Coasting out of atmosphere..." AT (0, 5).
        LOCK STEERING TO PROGRADE.
        WAIT UNTIL SHIP:ALTITUDE >= 70000.
    }

    // Raise Periapsis at Apoapsis
    IF SHIP:ORBIT:PERIAPSIS < target_Pe - 500 {
        PRINT "Creating maneuver node to raise Periapsis." AT (0, 6).

        SET r_ap TO SHIP:ORBIT:APOAPSIS + SHIP:BODY:RADIUS.
        SET r_pe_target TO target_Pe + SHIP:BODY:RADIUS.
        SET sma TO (r_ap + r_pe_target) / 2.
        SET v_new TO SQRT(SHIP:BODY:MU * (2 / r_ap - 1 / sma)).
        SET current_v TO VELOCITYAT(SHIP, TIME:SECONDS + ETA:APOAPSIS):ORBIT:MAG.
        SET delta_v TO v_new - current_v.

        SET node_time TO TIME:SECONDS + ETA:APOAPSIS.
        SET maneuver_node TO NODE(node_time, 0, 0, delta_v).
        ADD maneuver_node.

        PRINT "Node to raise Pe by " + ROUND(delta_v, 1) + " m/s at Ap." AT (0, 7).

        // Execute burn
        SET burn_dv TO maneuver_node:DELTAV:MAG.
        SET thrust TO SHIP:MAXTHRUST.
        SET burn_duration TO (burn_dv * SHIP:MASS) / thrust.
        SET burn_start TO node_time - (burn_duration / 2).
        SET twr TO thrust / (SHIP:MASS * SHIP:BODY:MU / (SHIP:ALTITUDE + SHIP:BODY:RADIUS)^2).
        SET lock_dv TO MIN(50, 10 * twr).

        PRINT "Burn duration: " + ROUND(burn_duration, 1) + " s" AT (0, 8).
        PRINT "TWR: " + ROUND(twr, 2) AT (0, 9).
        PRINT "Lock DV: " + ROUND(lock_dv, 1) + " m/s" AT (0, 10).

        LOCK STEERING TO maneuver_node:DELTAV.
        WAIT UNTIL TIME:SECONDS >= burn_start.
        LOCK THROTTLE TO 1.
        PRINT "Burn started to raise Pe..." AT (0, 11).

        SET K_dv TO 0.01.
        SET switched TO FALSE.

        //SET timeoutflag TO "UNKNOWN".
        SET last_remaining_dv TO maneuver_node:DELTAV:MAG.
        SET last_time TO TIME:SECONDS.

        UNTIL maneuver_node:DELTAV:MAG <= 0.1 OR SHIP:ORBIT:PERIAPSIS >= target_Pe {

            SET remaining_dv TO maneuver_node:DELTAV:MAG.
            PRINT "Remaining DV: " + ROUND(remaining_dv, 1) + " m/s" AT (0, 12).
            PRINT "Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS, 0) + " m" AT (0, 13).

            SET current_mass TO SHIP:MASS.
            SET current_thrust TO SHIP:AVAILABLETHRUST.

            IF current_thrust > 0 {
                SET acceleration TO current_thrust / current_mass.
                SET dynamic_burn_time TO remaining_dv / acceleration.
                PRINT "Est. Remaining Burn Time: " + ROUND(dynamic_burn_time, 1) + " s" AT (0, 16).
            }

            IF remaining_dv <= lock_dv AND NOT switched {
                LOCK STEERING TO SHIP:VELOCITY:ORBIT:NORMALIZED.
                SET switched TO TRUE.
                PRINT "Locked steering to velocity vector." AT (0, 14).
            }

            // DV progress fail-safe
            IF ABS(remaining_dv - last_remaining_dv) < 0.1 AND TIME:SECONDS - last_time > 5 {
                SET timeoutflag TO "ΔV not changing — burn stalled".
                BREAK.
            } ELSE {
                SET last_remaining_dv TO remaining_dv.
                SET last_time TO TIME:SECONDS.
            }

            SET current_throttle TO K_dv * remaining_dv.
            SET current_throttle TO MAX(0.1, MIN(1.0, current_throttle)).
            LOCK THROTTLE TO current_throttle.

            WAIT 0.1.
        }

        // // Diagnose what ended it
        // IF maneuver_node:DELTAV:MAG <= 0.1 {
        //     SET timeoutflag TO "ΔV completed".
        // } ELSE IF SHIP:ORBIT:PERIAPSIS >= target_Pe {
        //     SET timeoutflag TO "Pe target reached".
        // }

        // PRINT "Exited burn loop — Reason: " + timeoutflag AT (0, 22).

        LOCK THROTTLE TO 0.
        UNLOCK STEERING.
        REMOVE maneuver_node.
        PRINT "Periapsis now at " + ROUND(SHIP:ORBIT:PERIAPSIS, 0) + " m." AT (0, 15).
    }

    // Raise Apoapsis at Periapsis
    IF SHIP:ORBIT:APOAPSIS < target_Ap - 500 {
        PRINT "Creating maneuver node to raise Apoapsis." AT (0, 16).
        //WAIT UNTIL ETA:PERIAPSIS < 5.

        SET r_pe TO SHIP:ORBIT:PERIAPSIS + SHIP:BODY:RADIUS.
        SET r_ap_target TO target_Ap + SHIP:BODY:RADIUS.
        SET sma TO (r_pe + r_ap_target) / 2.
        SET v_new TO SQRT(SHIP:BODY:MU * (2 / r_pe - 1 / sma)).
        SET current_v TO VELOCITYAT(SHIP, TIME:SECONDS + ETA:PERIAPSIS):ORBIT:MAG.
        SET delta_v TO v_new - current_v.

        SET node_time TO TIME:SECONDS + ETA:PERIAPSIS.
        SET maneuver_node TO NODE(node_time, 0, 0, delta_v).
        ADD maneuver_node.

        PRINT "Node to raise Ap by " + ROUND(delta_v, 1) + " m/s at Pe." AT (0, 17).

        // Execute burn
        SET burn_dv TO maneuver_node:DELTAV:MAG.
        SET thrust TO SHIP:MAXTHRUST.
        SET burn_duration TO (burn_dv * SHIP:MASS) / thrust.
        SET burn_start TO node_time - (burn_duration / 2).
        SET twr TO thrust / (SHIP:MASS * SHIP:BODY:MU / (SHIP:ALTITUDE + SHIP:BODY:RADIUS)^2).
        SET lock_dv TO MIN(50, 10 * twr).

        PRINT "Burn duration: " + ROUND(burn_duration, 1) + " s" AT (0, 18).
        PRINT "TWR: " + ROUND(twr, 2) AT (0, 19).
        PRINT "Lock DV: " + ROUND(lock_dv, 1) + " m/s" AT (0, 20).

        LOCK STEERING TO maneuver_node:DELTAV.
        WAIT UNTIL TIME:SECONDS >= burn_start.
        LOCK THROTTLE TO 1.
        PRINT "Burn started to raise Ap..." AT (0, 21).

        SET K_dv TO 0.01.
        SET switched TO FALSE.

        UNTIL maneuver_node:DELTAV:MAG <= 0.5 
         OR SHIP:ORBIT:APOAPSIS >= target_Ap {
            SET remaining_dv TO maneuver_node:DELTAV:MAG.
            PRINT "Remaining DV: " + ROUND(remaining_dv, 1) + " m/s" AT (0, 22).
            PRINT "Ap: " + ROUND(SHIP:ORBIT:APOAPSIS, 0) + " m" AT (0, 23).

            IF remaining_dv <= lock_dv AND NOT switched {
                LOCK STEERING TO SHIP:VELOCITY:ORBIT:NORMALIZED.
                SET switched TO TRUE.
                PRINT "Locked steering to velocity vector." AT (0, 24).
                WAIT 10.
            }

            SET current_throttle TO K_dv * remaining_dv.
            SET current_throttle TO MAX(0.1, MIN(1.0, current_throttle)).
            LOCK THROTTLE TO current_throttle.

            WAIT 0.1.
        }

        LOCK THROTTLE TO 0.
        UNLOCK STEERING.
        REMOVE maneuver_node.
        PRINT "Apoapsis now at " + ROUND(SHIP:ORBIT:APOAPSIS, 0) + " m." AT (0, 25).
    }

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
FUNCTION continuous_burn_to_orbit {
    PARAMETER target_Ap, target_Pe.
    LOCAL fuel_critical IS FALSE.
    LOCAL burn_start_alt IS SHIP:ALTITUDE.
    LOCAL start_time IS TIME:SECONDS.
    LOCK THROTTLE TO 1.0.
    PRINT "Sustainer burn initiated at " + ROUND(burn_start_alt/1000, 1) + " km." AT (0, 5).

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

    LOCAL pitch_adjust IS 0.
    LOCAL target_heading IS 90.
    LOCAL safety_ap_limit IS target_Ap * .10 + target_Ap.
    
    UNLOCK STEERING.

    UNTIL (SHIP:ORBIT:PERIAPSIS >= target_Pe) OR fuel_critical {
        LOCAL current_thrust IS SHIP:AVAILABLETHRUST.
        LOCAL current_mass IS SHIP:MASS.
        LOCAL delta_v_left IS avg_isp * g0 * LN(current_mass / SHIP:DRYMASS).
        IF current_thrust = 0 {
            SET burn_time_left TO 0.
        }ELSE {        
            SET burn_time_left TO (current_mass - SHIP:DRYMASS) * (avg_isp * g0) / current_thrust.
        }
        IF burn_time_left < 5 OR current_thrust <= 0 {
            SET fuel_critical TO TRUE.
            PRINT "Fuel critical or depleted." AT (0, 7).
            BREAK.
        }

        LOCAL current_ap IS SHIP:ORBIT:APOAPSIS.
        LOCAL vert_vel IS VDOT(SHIP:VELOCITY:ORBIT, SHIP:UP:VECTOR).

        // Pitch logic (restored from original)
        IF current_ap >= 120000 { 
            IF vert_vel < 0 {
                SET pitch_adjust TO MIN(15, -vert_vel / 2).
            } ELSE IF vert_vel > 50 {
                SET pitch_adjust TO MAX(-15, -vert_vel / 3).
            } ELSE {
                IF current_ap > 130000 AND SHIP:ORBIT:PERIAPSIS > 65000 AND SHIP:ORBIT:PERIAPSIS < 85000 {
                    SET pitch_adjust TO 10.
                } ELSE {
                    SET pitch_adjust TO 0.
                }
            }
        } ELSE {
            IF vert_vel < 0 {
                SET pitch_adjust TO MIN(15, -vert_vel / 2).
            } ELSE IF vert_vel <= 200 {
                SET pitch_adjust TO -35 + (200 - vert_vel) / 6.
            } ELSE {
                LOCAL time_since_start IS TIME:SECONDS - start_time.
                IF time_since_start < 5 {
                    SET pitch_adjust TO -35 * (time_since_start / 5).
                } ELSE {
                    SET pitch_adjust TO -35.
                }
            }
        }

        LOCK STEERING TO HEADING(target_heading, pitch_adjust, 0).

        // Primary cutoff (unchanged)
        IF current_ap > target_Ap AND vert_vel > 0 AND vert_vel < 50 AND SHIP:ORBIT:PERIAPSIS > 65000 AND SHIP:ALTITUDE > 65000 {
            LOCK THROTTLE TO 0.0.
            PRINT "Cutoff: Ap > " + target_Ap + ", VertVel 0-50 m/s, Pe > 65 km." AT (0, 20).
            BREAK.
        }
        // Safety cutoff
        IF current_ap > safety_ap_limit AND SHIP:ALTITUDE < target_Pe {
            LOCK THROTTLE TO 0.0.
            PRINT "Fail-safe: Ap > " + ROUND(safety_ap_limit/1000, 1) + " km below " + ROUND(target_Pe /1000, 1) +" km." AT (0, 20).
            BREAK.
        }

        // Simplified display
        CLEARSCREEN.
        PRINT "Continous Burn to Orbit" AT (0,0).
        PRINT "Sustainer Burn Status" AT (0, 1).
        PRINT "---------------------" AT (0, 2).
        PRINT "Altitude: " + ROUND(SHIP:ALTITUDE/1000, 1) + " km" AT (0, 3).
        PRINT "Ap:       " + ROUND(current_ap/1000, 1) + " km" AT (0, 4).
        PRINT "Pe:       " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0, 5).
        PRINT "DeltaV:   " + ROUND(delta_v_left, 1) + " m/s" AT (0, 6).
        PRINT "Pitch:    " + ROUND(pitch_adjust, 1) + "°" AT (0, 7).
        PRINT "VertVel:  " + ROUND(vert_vel, 1) + " m/s" AT (0, 8).
        
        WAIT 0.1.

        // Secondary cutoff
        IF current_ap >= target_Ap AND SHIP:ORBIT:PERIAPSIS >= target_Pe {
            LOCK THROTTLE TO 0.0.
            PRINT "Target orbit achieved." AT (0, 20).
            BREAK.
        }
    }

    LOCK THROTTLE TO 0.0.
    SET SHIP:CONTROL:PILOTMAINTHROTTLE TO 0.
    // UNLOCK STEERING.
    // SAS ON.
    // SET SASMODE TO "PROGRADE".
    PRINT "SECO at " + ROUND(SHIP:ALTITUDE/1000, 1) + " km." AT (0, 22).
}