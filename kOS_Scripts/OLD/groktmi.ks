// TMI script for free return to Mun with specified periapsis
// Assumes nearly circular equatorial orbit around Kerbin
// Targets Mun periapsis altitude 20-50 km, Kerbin reentry at 30 km

CLEARSCREEN.
PRINT "Starting TMI script".

SET target_mun_alt_min TO 20. // km
SET target_mun_alt_max TO 50.
SET target_mun_alt TO 30. // ideal
SET target_ker_alt TO 30. // km

SET mun_radius TO MUN:RADIUS.
SET ker_radius TO BODY:RADIUS.

SET target_mun_pe TO mun_radius + target_mun_alt * 1000.
SET target_ker_pe TO ker_radius + target_ker_alt * 1000.

// Calculate standard Hohmann phase
SET mu TO BODY:MU.
SET r1 TO SHIP:ORBIT:SEMIMAJORAXIS.
SET r2 TO MUN:ORBIT:SEMIMAJORAXIS.
SET sma TO (r1 + r2)/2.
SET t_trans TO CONSTANT:PI * SQRT(sma^3 / mu).
SET ang_travel TO t_trans / MUN:ORBIT:PERIOD * 360.
SET standard_phase TO 180 - ang_travel.

// For free return, use negative phase
SET target_phase TO -standard_phase.

// Calculate current phase
SET current_mun_ta TO MUN:ORBIT:TRUEANOMALY.
SET current_ship_ta TO SHIP:ORBIT:TRUEANOMALY.
SET current_phase TO current_mun_ta - current_ship_ta.
IF current_phase < -180 { SET current_phase TO current_phase + 360. }
ELSE IF current_phase > 180 { SET current_phase TO current_phase - 360. }

// Angular velocities in deg/s
SET angvel_ship TO 360 / SHIP:ORBIT:PERIOD.
SET angvel_mun TO 360 / MUN:ORBIT:PERIOD.
SET delta_angvel TO angvel_ship - angvel_mun.

// Time derivative of phase
SET dphase_dt TO -delta_angvel.

// Delta phase normalized
SET delta_phase TO target_phase - current_phase.
IF delta_phase < -180 { SET delta_phase TO delta_phase + 360. }
ELSE IF delta_phase > 180 { SET delta_phase TO delta_phase - 360. }

// Time to target phase
SET base_eta TO delta_phase / dphase_dt.
IF base_eta < 0 { SET base_eta TO base_eta + (360 / delta_angvel). }

// Approximate dv
SET dv_approx TO SQRT(mu / r1) * (SQRT(2 * r2 / (r1 + r2)) - 1) + 20. // slight excess for free return

PRINT "Base eta: " + ROUND(base_eta) + " s".
PRINT "Approx dv: " + ROUND(dv_approx) + " m/s".

// Now search for best eta and dv
SET min_error TO 1e10.
SET best_eta TO base_eta.
SET best_dv TO dv_approx.
SET orbital_period TO SHIP:ORBIT:PERIOD.

SET eta_step TO 30. // seconds
SET dv_step TO 2. // m/s

FROM {local i TO -10.} UNTIL i > 10 STEP {SET i TO i + 1.} DO {
    SET this_eta TO base_eta + i * eta_step.
    IF this_eta < 0 { SET this_eta TO this_eta + orbital_period. }

    FROM {local j TO -40.} UNTIL j > 40 STEP {SET j TO j + 1.} DO {
        SET this_dv TO dv_approx + j * dv_step.

        SET test_node TO NODE(TIME:SECONDS + this_eta, 0, 0, this_dv).
        ADD test_node.

        IF test_node:ORBIT:HASNEXTPATCH AND test_node:ORBIT:NEXTPATCH:BODY:NAME = "Mun" AND test_node:ORBIT:NEXTPATCH:HASNEXTPATCH AND test_node:ORBIT:NEXTPATCH:NEXTPATCH:BODY:NAME = "Kerbin" {
            SET this_mun_pe TO test_node:ORBIT:NEXTPATCH:PERIAPSIS.
            SET this_ker_pe TO test_node:ORBIT:NEXTPATCH:NEXTPATCH:PERIAPSIS.

            SET mun_alt TO (this_mun_pe - mun_radius) / 1000.
            SET ker_alt TO (this_ker_pe - ker_radius) / 1000.

            // Error prioritizes Kerbin reentry, then Mun periapsis in range
            SET error TO ABS(ker_alt - target_ker_alt) * 100. // higher weight on Kerbin
            IF mun_alt < target_mun_alt_min OR mun_alt > target_mun_alt_max {
                SET error TO error + ABS(mun_alt - target_mun_alt) * 50.
            } ELSE {
                SET error TO error + ABS(mun_alt - target_mun_alt).
            }

            IF error < min_error {
                SET min_error TO error.
                SET best_eta TO this_eta.
                SET best_dv TO this_dv.
            }
        }

        REMOVE test_node.
    }
}

PRINT "Best eta: " + ROUND(best_eta) + " s".
PRINT "Best dv: " + ROUND(best_dv) + " m/s".

// Create the final node
SET final_node TO NODE(TIME:SECONDS + best_eta, 0, 0, best_dv).
ADD final_node.

// Warp to burn time, accounting for burn duration
LIST ENGINES IN eng_list.
SET max_thrust TO 0.
FOR eng IN eng_list {
    IF eng:IGNITION { SET max_thrust TO max_thrust + eng:MAXTHRUST. }
}
SET ship_mass TO SHIP:MASS.
SET burn_time TO best_dv * ship_mass / max_thrust.

PRINT "Burn time: " + ROUND(burn_time) + " s".
PRINT "Warping to burn".

KUNIVERSE:TIMEWARP:WARPTO(TIME:SECONDS + best_eta - burn_time / 2).

WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.

// Execute the burn
LOCK STEERING TO final_node:DELTAV.
WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, final_node:DELTAV:NORMALIZED) < 0.5.

SET start_time TO TIME:SECONDS.
LOCK THROTTLE TO 1.

WAIT UNTIL final_node:DELTAV:MAG < 1 OR TIME:SECONDS > start_time + burn_time + 5.

LOCK THROTTLE TO 0.
REMOVE final_node.

PRINT "TMI burn complete".
PRINT "Check trajectory for Mun encounter and free return".

// Script end