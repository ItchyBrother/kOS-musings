// KOS Script: circ.ks
// Establish an orbit with given apoapsis, periapsis, and orbit mode
// Version 3.6 - TTA 30-40 sec with prograde failsafe (fixed syntax)

PARAMETER target_Ap, target_Pe, orbitMode.

// Initial setup
PRINT "Establishing orbit: Target Ap = " + ROUND(target_Ap, 0) + " m, Target Pe = " + ROUND(target_Pe, 0) + " m.".
SET mu TO SHIP:BODY:MU.
SET body_radius TO SHIP:BODY:RADIUS.

// Global throttleable flag
GLOBAL throttleable IS FALSE.
GLOBAL burn_complete TO FALSE.

// Check engines
FUNCTION check_engines {
    LIST ENGINES IN myEngines.
    SET engine_active TO FALSE.
    FOR eng IN myEngines {
        IF eng:IGNITION AND NOT eng:FLAMEOUT {
            SET engine_active TO TRUE.
            SET throttleable TO NOT eng:THROTTLELOCK.
            PRINT "Active Engine: " + eng:NAME + ", Throttleable: " + throttleable AT (0, 2).
            RETURN engine_active.
        }
    }
    IF NOT engine_active AND myEngines:LENGTH > 0 {
        SET throttleable TO NOT myEngines[0]:THROTTLELOCK.
        PRINT "No active engines. First Engine: " + myEngines[0]:NAME + ", Throttleable: " + throttleable AT (0, 2).
        RETURN FALSE.
    }
    PRINT "No engines found." AT (0, 2).
    RETURN FALSE.
}

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
    PRINT "Coast to Orbit (Maneuver Node)" AT (10, 0).
    node_to_orbit(target_Ap, target_Pe).
} ELSE IF orbitMode = 1 { 
    PRINT "Throttle Adjusted Orbit" AT (10, 0).
    throttle_adjusted_to_orbit(target_Ap, target_Pe).
} ELSE IF orbitMode = 2 { 
    PRINT "Continuous Burn to Orbit" AT (10, 0).
    continuous_burn_to_orbit(target_Ap, target_Pe).
} ELSE {
    PRINT "Invalid orbitMode: " + orbitMode + ". Defaulting to Continuous Burn." AT (10, 0).
    continuous_burn_to_orbit(target_Ap, target_Pe).
}

// Function for Coast to Orbit with Maneuver Node (orbitMode = 0)
FUNCTION node_to_orbit {
    PARAMETER target_Ap, target_Pe.

    IF engine_active AND SHIP:ORBIT:APOAPSIS < target_Ap {
        PRINT "Burning to target apoapsis..." AT (0, 5).
        LOCK STEERING TO PROGRADE.
        LOCK THROTTLE TO 1.0.
        UNTIL SHIP:ORBIT:APOAPSIS >= target_Ap {
            PRINT "Ap: " + ROUND(SHIP:ORBIT:APOAPSIS, 0) + " m" AT (0, 10).
            PRINT "Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS, 0) + " m" AT (0, 11).
            WAIT 0.1.
        }
        LOCK THROTTLE TO 0.0.
        PRINT "SECO at " + ROUND(SHIP:ALTITUDE, 0) + " m." AT (0, 12).
    }

    IF SHIP:ALTITUDE < 70000 {
        PRINT "Coasting out of atmosphere..." AT (0, 5).
        LOCK STEERING TO PROGRADE.
        WAIT UNTIL SHIP:ALTITUDE >= 70000.
    }

    SET r_ap TO target_Ap + body_radius.
    SET sma TO (target_Ap + target_Pe + 2 * body_radius) / 2.
    SET v_ap TO SQRT(mu * (2 / r_ap - 1 / sma)).
    SET current_v TO VELOCITYAT(SHIP, TIME:SECONDS + ETA:APOAPSIS):ORBIT:MAG.
    SET delta_v TO v_ap - current_v.
    SET node_time TO TIME:SECONDS + ETA:APOAPSIS.
    SET maneuver_node TO NODE(node_time, 0, 0, delta_v).
    ADD maneuver_node.
    PRINT "Maneuver node created: Delta-V = " + ROUND(delta_v, 1) + " m/s at Ap." AT (0, 13).

    SET burn_dv TO maneuver_node:DELTAV:MAG.
    SET thrust TO SHIP:MAXTHRUST.
    SET burn_duration TO (burn_dv * SHIP:MASS) / thrust.
    SET burn_start TO node_time - (burn_duration / 2).
    SET twr TO thrust / (SHIP:MASS * SHIP:BODY:MU / (SHIP:ALTITUDE + body_radius)^2).
    SET lock_dv TO MIN(50, 10 * twr).

    PRINT "Burn duration: " + ROUND(burn_duration, 1) + " s" AT (0, 14).
    PRINT "TWR: " + ROUND(twr, 2) AT (0, 15).
    PRINT "Lock DV: " + ROUND(lock_dv, 1) + " m/s" AT (0, 16).

    LOCK STEERING TO maneuver_node:DELTAV.
    WAIT UNTIL TIME:SECONDS >= burn_start.
    LOCK THROTTLE TO 1.0.
    PRINT "Burn started..." AT (0, 17).

    SET switched TO FALSE.
    UNTIL maneuver_node:DELTAV:MAG <= 0 OR SHIP:ORBIT:PERIAPSIS >= target_Pe {
        SET remaining_dv TO maneuver_node:DELTAV:MAG.
        PRINT "Remaining DV: " + ROUND(remaining_dv, 1) + " m/s" AT (0, 18).
        PRINT "Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS, 0) + " m" AT (0, 19).
        IF remaining_dv <= lock_dv AND NOT switched {
            LOCK STEERING TO SHIP:VELOCITY:ORBIT:NORMALIZED.
            SET switched TO TRUE.
            PRINT "Locked steering to velocity vector." AT (0, 20).
        }
        WAIT 0.1.
    }
    LOCK THROTTLE TO 0.0.
    UNLOCK STEERING.
    REMOVE maneuver_node.
    PRINT "Orbit established. Ap: " + ROUND(SHIP:ORBIT:APOAPSIS, 0) + " m, Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS, 0) + " m." AT (0, 21).
}

// Function to handle Pe burn separately
FUNCTION adjust_periapsis {
    PARAMETER target_Pe.

    IF burn_complete OR SHIP:ORBIT:PERIAPSIS >= target_Pe - 500 {
        RETURN.
    }

    PRINT "Coasting to apoapsis..." AT (0, 7).
    WAIT UNTIL ETA:APOAPSIS <= 10.
    LOCK STEERING TO PROGRADE.
    SET current_throttle TO 0.0.
    LOCK THROTTLE TO current_throttle.

    UNTIL SHIP:ORBIT:PERIAPSIS >= target_Pe - 500 OR SHIP:MAXTHRUST <= 0 OR ETA:APOAPSIS < -120 {
        SET pe_error TO (target_Pe - SHIP:ORBIT:PERIAPSIS) / 5000.
        SET throttle_val TO MAX(0.1, MIN(1.0, pe_error)).

        IF throttle_val > current_throttle {
            SET current_throttle TO MIN(throttle_val, current_throttle + 0.05).
        } ELSE {
            SET current_throttle TO MAX(throttle_val, current_throttle - 0.05).
        }

        LOCK THROTTLE TO current_throttle.
        SET twr TO SHIP:MAXTHRUST / (SHIP:MASS * SHIP:BODY:MU / (SHIP:ALTITUDE + body_radius)^2).

        PRINT "Raising Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0, 13).
        PRINT "Throttle: " + ROUND(current_throttle * 100, 1) + "%" AT (0, 11).
        PRINT "ETA Ap: " + ROUND(ETA:APOAPSIS, 1) + " s" AT (0, 18).
        PRINT "TWR at Pe burn: " + ROUND(twr, 2) AT (0, 19).

        WAIT 0.1.
    }

    // Ensure throttle is off
    SET current_throttle TO 0.0.
    LOCK THROTTLE TO current_throttle.
    UNLOCK STEERING.
    UNLOCK THROTTLE.

    PRINT "Pe burn complete (or failed)." AT (0, 20).

    // ENSURE burn is marked as complete, even if unsuccessful
    SET burn_complete TO TRUE.  

    RETURN.
}


// Main function
FUNCTION throttle_adjusted_to_orbit {
    PARAMETER target_Ap, target_Pe.

    IF NOT engine_active {
        PRINT "Engine not active. Checking again..." AT (0, 5).
        SET engine_active TO check_engines().
        IF NOT engine_active {
            PRINT "Cannot perform burn." AT (0, 6).
            RETURN.
        }
    }

    IF burn_complete {
        PRINT "Burn already completed. Exiting." AT (0, 6).
        RETURN.
    }

    PRINT "Starting burn sequence..." AT (0, 4).
    LOCK STEERING TO PROGRADE.
    PRINT "Throttle-adjusted burn: Ap " + ROUND(target_Ap/1000, 1) + " km, Pe " + ROUND(target_Pe/1000, 1) + " km" AT (0, 5).

    // Apoapsis Burn Logic
    SET throttle_val TO 0.5.
    SET current_throttle TO 0.0.
    LOCK THROTTLE TO current_throttle.
    UNTIL SHIP:ORBIT:APOAPSIS >= target_Ap OR SHIP:MAXTHRUST <= 0 {
        SET tta TO ETA:APOAPSIS.
        SET throttle_val TO MAX(0.1, MIN(1.0, (target_Ap - SHIP:ORBIT:APOAPSIS) / 10000)).
        
        IF throttle_val > current_throttle {
            SET current_throttle TO MIN(throttle_val, current_throttle + 0.02).  // Smoother change
        } ELSE {
            SET current_throttle TO MAX(throttle_val, current_throttle - 0.02).
        }

        LOCK THROTTLE TO current_throttle.
        WAIT 0.1.
    }
    LOCK THROTTLE TO 0.0.
    PRINT "Phase 1 complete. Ap reached." AT (0, 17).

    // Call Periapsis Adjustment BEFORE setting burn_complete
    adjust_periapsis(target_Pe).

    // Mark burn as complete only after both phases
    SET burn_complete TO TRUE.

    // Final cleanup
    UNLOCK STEERING.
    UNLOCK THROTTLE.
    PRINT "Orbit established. Ap: " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 1) + " km, Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 1) + " km" AT (0, 21).
    PRINT "Script terminated." AT (0, 22).
    RETURN.
}


// Function for Continuous Burn to Orbit (orbitMode = 2)
FUNCTION continuous_burn_to_orbit {
    PARAMETER target_Ap, target_Pe.

    IF NOT engine_active {
        PRINT "Engine not active. Cannot perform continuous burn." AT (0, 5).
        RETURN.
    }

    LOCK STEERING TO PROGRADE.
    LOCK THROTTLE TO 1.0.
    PRINT "Continuous burn to target orbit (binary throttle)..." AT (0, 5).

    SET ap_tolerance TO target_Ap * 0.1.
    SET pe_tolerance TO target_Pe * 0.1.

    UNTIL SHIP:ORBIT:APOAPSIS >= target_Ap - 10000 {
        PRINT "Current Ap: " + ROUND(SHIP:ORBIT:APOAPSIS, 0) + " m" AT (0, 10).
        WAIT 0.1.
    }
    LOCK THROTTLE TO 0.0.
    WAIT UNTIL ETA:APOAPSIS <= 10.

    LOCK THROTTLE TO 1.0.
    UNTIL SHIP:ORBIT:PERIAPSIS >= target_Pe {
        PRINT "Raising Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS, 0) + " m" AT (0, 11).
        WAIT 0.1.
    }
    LOCK THROTTLE TO 0.0.
    UNLOCK STEERING.
    PRINT "Orbit established. Ap: " + ROUND(SHIP:ORBIT:APOAPSIS, 0) + " m, Pe: " + ROUND(SHIP:ORBIT:PERIAPSIS, 0) + " m." AT (0, 12).
}