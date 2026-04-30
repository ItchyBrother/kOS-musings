// ======= Classical Orbital Rendezvous System with Display Integration =======
// Implements proper rendezvous sequence: Inclination → Orbit Matching → Phasing → Intercept

// ------------------ CONFIG ------------------
SET RDV_CFG_NODE_MIN_LEAD      TO 20.
SET RDV_CFG_TARGET_RANGE       TO AP_ACTIVE_RANGE.
SET RDV_CFG_MAX_RVEL           TO AP_PREBRAKE_VHIGH.
SET RDV_CFG_WARP               TO AP_WARPFACTOR.
SET RDV_CFG_VERBOSE            TO AP_DEBUG.
SET RDV_CFG_RENDER_RANGE       TO 2300.
SET RDV_CFG_COAST_RANGE        TO 2700.
SET RDV_CFG_RVEL_ADJUST_RANGE  TO 5000.
SET RDV_CFG_MIN_PERIAPSIS      TO 71000.
SET RDV_CFG_INCLINATION_TOL    TO 0.5.
SET RDV_CFG_ORBIT_MATCH_TOL    TO 5000.
SET RDV_CFG_SCAN_ORBITS        TO 10.

// Global intercept variables
IF NOT (DEFINED INTERCEPT_T) { GLOBAL INTERCEPT_T IS 0. }
IF NOT (DEFINED INTERCEPT_D) { GLOBAL INTERCEPT_D IS 0. }
IF NOT (DEFINED INTERCEPT_VR) { GLOBAL INTERCEPT_VR IS 0. }

// ------------------ UTILITY FUNCTIONS ------------------

FUNCTION _rdv_print {
    PARAMETER msg.
    IF RDV_CFG_VERBOSE {
        DISP_LOG_UPDATE("[RDV] " + msg).
    }
}

FUNCTION _rdv_execute_node {
    IF NOT HASNODE {
        RETURN FALSE.
    }
    
    LOCAL node_data IS NEXTNODE.
    LOCAL dv_total IS node_data:DELTAV:MAG.
    
    IF dv_total < 0.02 {
        REMOVE NEXTNODE.
        RETURN TRUE.
    }
    
    LOCAL burn_time IS dv_total / 0.5.
    SET burn_time TO MAX(5, MIN(burn_time, 120)).
    
    LOCAL start_time IS node_data:TIME - (burn_time / 2).
    LOCAL prealign_time IS start_time - 15.
    
    DISP_LOG_UPDATE("Executing " + ROUND(dv_total, 2) + "m/s RCS burn").
    DISP_LOG_UPDATE("ETA: " + ROUND(node_data:TIME - TIME:SECONDS, 0) + "s").
    
    IF RDV_CFG_WARP {
        WARPTO(prealign_time - 2).
    }
    WAIT UNTIL TIME:SECONDS >= prealign_time.
    
    DISP_LOG_UPDATE("Aligning for burn").
    RCS OFF.
    LOCK STEERING TO node_data:DELTAV:NORMALIZED.
    WAIT UNTIL VANG(SHIP:FACING:VECTOR, node_data:DELTAV) < 2.
    WAIT UNTIL TIME:SECONDS >= start_time.
    
    DISP_LOG_UPDATE("Burn in progress").
    RCS ON.
    SET SHIP:CONTROL:NEUTRALIZE TO FALSE.
    
    LOCAL last_update IS TIME:SECONDS.
    UNTIL node_data:DELTAV:MAG < 0.01 OR TIME:SECONDS > (node_data:TIME + burn_time * 3) {
        LOCK STEERING TO node_data:DELTAV:NORMALIZED.
        LOCAL remaining_dv IS node_data:DELTAV:MAG.
        
        LOCAL throttle_val IS 1.0.
        IF remaining_dv < 5.0 { SET throttle_val TO 0.8. }
        IF remaining_dv < 2.0 { SET throttle_val TO 0.6. }
        IF remaining_dv < 1.0 { SET throttle_val TO 0.4. }
        IF remaining_dv < 0.5 { SET throttle_val TO 0.2. }
        IF remaining_dv < 0.1 { SET throttle_val TO 0.1. }
        
        SET SHIP:CONTROL:FORE TO throttle_val.
        
        IF TIME:SECONDS - last_update >= 3 {
            DISP_LOG_UPDATE("Burn: " + ROUND(remaining_dv, 2) + "m/s remaining").
            SET last_update TO TIME:SECONDS.
        }
        DISP_TICK().
        
        WAIT 0.02.
    }
    
    SET SHIP:CONTROL:FORE TO 0.
    SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
    UNLOCK STEERING.
    RCS OFF.
    
    LOCAL final_dv IS node_data:DELTAV:MAG.
    IF final_dv > 0.1 {
        DISP_WARN("Burn incomplete: " + ROUND(final_dv, 2) + "m/s remaining").
        DISP_LOG_UPDATE("Close enough for orbital mechanics").
    } ELSE {
        DISP_SUCCESS("Burn complete").
    }
    
    REMOVE NEXTNODE.
    
    WAIT 3.
    RETURN TRUE.
}

FUNCTION _rdv_safe_periapsis {
    PARAMETER target_pe.
    RETURN MAX(RDV_CFG_MIN_PERIAPSIS, target_pe).
}

FUNCTION _rdv_time_to_an {
    LOCAL ship_inc IS SHIP:ORBIT:INCLINATION.
    LOCAL target_inc IS TARGET:ORBIT:INCLINATION.
    LOCAL ship_lan IS SHIP:ORBIT:LAN.
    LOCAL target_lan IS TARGET:ORBIT:LAN.
    
    LOCAL lan_diff IS target_lan - ship_lan.
    IF lan_diff < 0 { SET lan_diff TO lan_diff + 360. }
    IF lan_diff > 180 { SET lan_diff TO lan_diff - 360. }
    
    LOCAL ship_argpe IS SHIP:ORBIT:ARGUMENTOFPERIAPSIS.
    LOCAL ship_ta IS SHIP:ORBIT:TRUEANOMALY.
    LOCAL angle_from_an IS ship_argpe + ship_ta.
    
    IF angle_from_an < 0 { SET angle_from_an TO angle_from_an + 360. }
    IF angle_from_an > 360 { SET angle_from_an TO angle_from_an - 360. }
    
    LOCAL angle_to_an IS 360 - angle_from_an.
    IF angle_to_an > 360 { SET angle_to_an TO angle_to_an - 360. }
    
    LOCAL mean_motion IS 360 / SHIP:ORBIT:PERIOD.
    LOCAL time_to_an IS angle_to_an / mean_motion.
    
    RETURN time_to_an.
}

FUNCTION _rdv_time_to_dn {
    LOCAL time_to_an IS _rdv_time_to_an().
    LOCAL time_to_dn IS time_to_an + (SHIP:ORBIT:PERIOD / 2).
    IF time_to_dn > SHIP:ORBIT:PERIOD { SET time_to_dn TO time_to_dn - SHIP:ORBIT:PERIOD. }
    RETURN time_to_dn.
}

// ------------------ EXISTING ENCOUNTER CHECK ------------------

FUNCTION _rdv_check_existing_encounters {
    DISP_LOG_UPDATE("Checking existing encounters").
    
    LOCAL scan_intercepts IS _rdv_scan_intercepts(15, 400).
    LOCAL best_existing IS _rdv_find_best_intercept(scan_intercepts).
    
    DISP_LOG_UPDATE("Best: " + ROUND(best_existing["distance"]/1000, 2) + "km @ " + ROUND(best_existing["rel_velocity"], 1) + "m/s").
    DISP_LOG_UPDATE("ETA: " + ROUND(best_existing["eta"]/3600, 1) + " hours").
    
    IF best_existing["distance"] <= RDV_CFG_RENDER_RANGE AND best_existing["rel_velocity"] <= RDV_CFG_MAX_RVEL {
        DISP_SUCCESS("Excellent encounter found").
        SET INTERCEPT_T TO best_existing["time"].
        SET INTERCEPT_D TO best_existing["distance"].
        SET INTERCEPT_VR TO best_existing["rel_velocity"].
        RETURN "excellent".
    }
    
    IF best_existing["distance"] <= 5000 AND best_existing["rel_velocity"] <= (RDV_CFG_MAX_RVEL * 1.5) {
        DISP_SUCCESS("Very good encounter found").
        SET INTERCEPT_T TO best_existing["time"].
        SET INTERCEPT_D TO best_existing["distance"].
        SET INTERCEPT_VR TO best_existing["rel_velocity"].
        RETURN "very_good".
    }
    
    IF best_existing["distance"] <= 15000 AND best_existing["rel_velocity"] <= (RDV_CFG_MAX_RVEL * 2) {
        DISP_LOG_UPDATE("Acceptable encounter found").
        SET INTERCEPT_T TO best_existing["time"].
        SET INTERCEPT_D TO best_existing["distance"].
        SET INTERCEPT_VR TO best_existing["rel_velocity"].
        RETURN "acceptable".
    }
    
    DISP_LOG_UPDATE("No good encounters - will create one").
    RETURN "none".
}

// ------------------ STEP 1: INCLINATION MATCHING ------------------

FUNCTION _rdv_match_inclination {
    DISP_LOG_UPDATE("Step 1: Inclination matching").
    
    LOCAL ship_inc IS SHIP:ORBIT:INCLINATION.
    LOCAL target_inc IS TARGET:ORBIT:INCLINATION.
    LOCAL inc_diff IS ABS(ship_inc - target_inc).
    
    DISP_LOG_UPDATE("Ship: " + ROUND(ship_inc, 2) + "° Target: " + ROUND(target_inc, 2) + "°").
    DISP_LOG_UPDATE("Difference: " + ROUND(inc_diff, 2) + "°").
    
    IF inc_diff < RDV_CFG_INCLINATION_TOL {
        DISP_SUCCESS("Inclination within tolerance").
        RETURN TRUE.
    }
    
    LOCAL an_eta IS _rdv_time_to_an().
    LOCAL dn_eta IS _rdv_time_to_dn().
    
    LOCAL use_an IS an_eta < dn_eta.
    LOCAL node_eta IS an_eta.
    IF NOT use_an { SET node_eta TO dn_eta. }
    
    IF node_eta < RDV_CFG_NODE_MIN_LEAD {
        SET node_eta TO node_eta + SHIP:ORBIT:PERIOD.
    }
    
    LOCAL node_type IS "AN".
    IF NOT use_an { SET node_type TO "DN". }
    
    DISP_LOG_UPDATE("Using " + node_type + " in " + ROUND(node_eta, 0) + "s").
    
    LOCAL target_normal IS TARGET:ORBIT:INCLINATION - SHIP:ORBIT:INCLINATION.
    
    LOCAL inc_node IS NODE(TIME:SECONDS + node_eta, 0, target_normal, 0).
    ADD inc_node.
    
    RETURN _rdv_execute_node().
}

// ------------------ STEP 2: ORBIT ALIGNMENT ------------------

FUNCTION _rdv_align_orbits {
    DISP_LOG_UPDATE("Step 2: Orbit alignment").
    
    LOCAL ship_ap IS SHIP:ORBIT:APOAPSIS.
    LOCAL ship_pe IS SHIP:ORBIT:PERIAPSIS.
    LOCAL target_ap IS TARGET:ORBIT:APOAPSIS.
    LOCAL target_pe IS TARGET:ORBIT:PERIAPSIS.
    
    DISP_LOG_UPDATE("Ship: " + ROUND(ship_pe/1000, 1) + "x" + ROUND(ship_ap/1000, 1) + "km").
    DISP_LOG_UPDATE("Target: " + ROUND(target_pe/1000, 1) + "x" + ROUND(target_ap/1000, 1) + "km").
    
    // Phase 2a: Match apoapsis at target periapsis
    LOCAL target_ap_alt IS target_pe.
    LOCAL ap_diff IS ABS(ship_ap - target_ap_alt).
    
    IF ap_diff > RDV_CFG_ORBIT_MATCH_TOL {
        DISP_LOG_UPDATE("Adjusting Ap to " + ROUND(target_ap_alt/1000, 1) + "km").
        
        LOCAL pe_burn_eta IS SHIP:ORBIT:ETA:PERIAPSIS.
        IF pe_burn_eta < RDV_CFG_NODE_MIN_LEAD {
            SET pe_burn_eta TO pe_burn_eta + SHIP:ORBIT:PERIOD.
        }
        
        LOCAL current_v_at_pe IS SQRT(SHIP:ORBIT:BODY:MU * (2/(SHIP:ORBIT:PERIAPSIS + SHIP:ORBIT:BODY:RADIUS) - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
        LOCAL target_sma IS ((target_ap_alt + SHIP:ORBIT:BODY:RADIUS) + (SHIP:ORBIT:PERIAPSIS + SHIP:ORBIT:BODY:RADIUS)) / 2.
        LOCAL target_v_at_pe IS SQRT(SHIP:ORBIT:BODY:MU * (2/(SHIP:ORBIT:PERIAPSIS + SHIP:ORBIT:BODY:RADIUS) - 1/target_sma)).
        LOCAL dv_prograde IS target_v_at_pe - current_v_at_pe.
        
        LOCAL ap_node IS NODE(TIME:SECONDS + pe_burn_eta, 0, 0, dv_prograde).
        ADD ap_node.
        
        IF NOT _rdv_execute_node() { RETURN FALSE. }
        DISP_TICK().
    }
    
    // Phase 2b: Match periapsis at target apoapsis
    LOCAL target_pe_alt IS target_ap.
    SET target_pe_alt TO _rdv_safe_periapsis(target_pe_alt).
    LOCAL pe_diff IS ABS(SHIP:ORBIT:PERIAPSIS - target_pe_alt).
    
    IF pe_diff > RDV_CFG_ORBIT_MATCH_TOL {
        DISP_LOG_UPDATE("Adjusting Pe to " + ROUND(target_pe_alt/1000, 1) + "km").
        
        LOCAL ap_burn_eta IS SHIP:ORBIT:ETA:APOAPSIS.
        IF ap_burn_eta < RDV_CFG_NODE_MIN_LEAD {
            SET ap_burn_eta TO ap_burn_eta + SHIP:ORBIT:PERIOD.
        }
        
        LOCAL current_v_at_ap IS SQRT(SHIP:ORBIT:BODY:MU * (2/(SHIP:ORBIT:APOAPSIS + SHIP:ORBIT:BODY:RADIUS) - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
        LOCAL target_sma IS ((SHIP:ORBIT:APOAPSIS + SHIP:ORBIT:BODY:RADIUS) + (target_pe_alt + SHIP:ORBIT:BODY:RADIUS)) / 2.
        LOCAL target_v_at_ap IS SQRT(SHIP:ORBIT:BODY:MU * (2/(SHIP:ORBIT:APOAPSIS + SHIP:ORBIT:BODY:RADIUS) - 1/target_sma)).
        LOCAL dv_prograde IS target_v_at_ap - current_v_at_ap.
        
        LOCAL pe_node IS NODE(TIME:SECONDS + ap_burn_eta, 0, 0, dv_prograde).
        ADD pe_node.
        
        IF NOT _rdv_execute_node() { RETURN FALSE. }
        DISP_TICK().
    }
    
    DISP_SUCCESS("Orbit alignment complete").
    RETURN TRUE.
}

// ------------------ STEP 3: RELATIVE POSITION ANALYSIS ------------------

FUNCTION _rdv_analyze_relative_position {
    DISP_LOG_UPDATE("Step 3: Position analysis").
    
    LOCAL ship_ta IS SHIP:ORBIT:TRUEANOMALY.
    LOCAL target_ta IS TARGET:ORBIT:TRUEANOMALY.
    
    IF ship_ta < 0 { SET ship_ta TO ship_ta + 360. }
    IF target_ta < 0 { SET target_ta TO target_ta + 360. }
    
    LOCAL angle_diff IS target_ta - ship_ta.
    IF angle_diff < -180 { SET angle_diff TO angle_diff + 360. }
    IF angle_diff > 180 { SET angle_diff TO angle_diff - 360. }
    
    LOCAL target_ahead IS angle_diff > 0.
    
    DISP_LOG_UPDATE("Ship TA: " + ROUND(ship_ta, 1) + "° Target TA: " + ROUND(target_ta, 1) + "°").
    DISP_LOG_UPDATE("Angular diff: " + ROUND(angle_diff, 1) + "°").
    
    IF target_ahead {
        DISP_LOG_UPDATE("Target AHEAD - catch-up strategy").
    } ELSE {
        DISP_LOG_UPDATE("Target BEHIND - wait strategy").
    }
    
    RETURN target_ahead.
}

// ------------------ STEP 3A/3B: PHASING ORBIT SETUP ------------------

FUNCTION _rdv_setup_phasing_orbit {
    PARAMETER target_ahead.
    
    LOCAL step_label IS "A".
    IF NOT target_ahead { SET step_label TO "B". }
    DISP_LOG_UPDATE("Step 3" + step_label + ": Phasing orbit setup").
    
    LOCAL target_ap IS TARGET:ORBIT:APOAPSIS.
    LOCAL target_pe IS TARGET:ORBIT:PERIAPSIS.
    LOCAL ship_ap IS SHIP:ORBIT:APOAPSIS.
    LOCAL ship_pe IS SHIP:ORBIT:PERIAPSIS.
    
    LOCAL target_ap_alt IS 0.
    LOCAL target_pe_alt IS 0.
    
    IF target_ahead {
        SET target_ap_alt TO target_ap.
        SET target_pe_alt TO _rdv_safe_periapsis(target_pe - 10000).
        DISP_LOG_UPDATE("Catch-up: Ap=" + ROUND(target_ap_alt/1000, 1) + "km Pe=" + ROUND(target_pe_alt/1000, 1) + "km").
    } ELSE {
        SET target_ap_alt TO target_ap + 10000.
        SET target_pe_alt TO _rdv_safe_periapsis(target_pe - 5000).
        DISP_LOG_UPDATE("Wait: Ap=" + ROUND(target_ap_alt/1000, 1) + "km Pe=" + ROUND(target_pe_alt/1000, 1) + "km").
    }
    
    // Adjust apoapsis first
    LOCAL ap_diff IS ABS(ship_ap - target_ap_alt).
    IF ap_diff > 1000 {
        DISP_LOG_UPDATE("Adjusting apoapsis for phasing").
        
        LOCAL pe_burn_eta IS SHIP:ORBIT:ETA:PERIAPSIS.
        IF pe_burn_eta < RDV_CFG_NODE_MIN_LEAD {
            SET pe_burn_eta TO pe_burn_eta + SHIP:ORBIT:PERIOD.
        }
        
        LOCAL current_v_at_pe IS SQRT(SHIP:ORBIT:BODY:MU * (2/(SHIP:ORBIT:PERIAPSIS + SHIP:ORBIT:BODY:RADIUS) - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
        LOCAL target_sma IS ((target_ap_alt + SHIP:ORBIT:BODY:RADIUS) + (SHIP:ORBIT:PERIAPSIS + SHIP:ORBIT:BODY:RADIUS)) / 2.
        LOCAL target_v_at_pe IS SQRT(SHIP:ORBIT:BODY:MU * (2/(SHIP:ORBIT:PERIAPSIS + SHIP:ORBIT:BODY:RADIUS) - 1/target_sma)).
        LOCAL dv_prograde IS target_v_at_pe - current_v_at_pe.
        
        LOCAL ap_node IS NODE(TIME:SECONDS + pe_burn_eta, 0, 0, dv_prograde).
        ADD ap_node.
        
        IF NOT _rdv_execute_node() { RETURN FALSE. }
        DISP_TICK().
    }
    
    // Adjust periapsis second
    LOCAL pe_diff IS ABS(SHIP:ORBIT:PERIAPSIS - target_pe_alt).
    IF pe_diff > 1000 {
        DISP_LOG_UPDATE("Adjusting periapsis for phasing").
        
        LOCAL ap_burn_eta IS SHIP:ORBIT:ETA:APOAPSIS.
        IF ap_burn_eta < RDV_CFG_NODE_MIN_LEAD {
            SET ap_burn_eta TO ap_burn_eta + SHIP:ORBIT:PERIOD.
        }
        
        LOCAL current_v_at_ap IS SQRT(SHIP:ORBIT:BODY:MU * (2/(SHIP:ORBIT:APOAPSIS + SHIP:ORBIT:BODY:RADIUS) - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
        LOCAL target_sma IS ((SHIP:ORBIT:APOAPSIS + SHIP:ORBIT:BODY:RADIUS) + (target_pe_alt + SHIP:ORBIT:BODY:RADIUS)) / 2.
        LOCAL target_v_at_ap IS SQRT(SHIP:ORBIT:BODY:MU * (2/(SHIP:ORBIT:APOAPSIS + SHIP:ORBIT:BODY:RADIUS) - 1/target_sma)).
        LOCAL dv_prograde IS target_v_at_ap - current_v_at_ap.
        
        LOCAL pe_node IS NODE(TIME:SECONDS + ap_burn_eta, 0, 0, dv_prograde).
        ADD pe_node.
        
        IF NOT _rdv_execute_node() { RETURN FALSE. }
        DISP_TICK().
    }
    
    DISP_SUCCESS("Phasing orbit established").
    RETURN TRUE.
}

// ------------------ STEP 4: INTERCEPT SCANNING ------------------

FUNCTION _rdv_scan_intercepts {
    PARAMETER scan_orbits IS 10, samples_per_orbit IS 200.
    
    LOCAL intercepts IS LIST().
    LOCAL ship_period IS SHIP:ORBIT:PERIOD.
    
    LOCAL current_scan_start IS TIME:SECONDS + 60.
    LOCAL current_scan_end IS current_scan_start + 1800.
    
    LOCAL best_distance IS 999999999.
    LOCAL best_time IS current_scan_start.
    LOCAL best_rel_vel IS 0.
    
    LOCAL step IS (current_scan_end - current_scan_start) / (samples_per_orbit * 2).
    
    FOR sample IN RANGE(0, samples_per_orbit * 2) {
        LOCAL check_time IS current_scan_start + (sample * step).
        LOCAL ship_pos IS POSITIONAT(SHIP, check_time).
        LOCAL target_pos IS POSITIONAT(TARGET, check_time).
        LOCAL distance IS (target_pos - ship_pos):MAG.
        
        IF distance < best_distance {
            SET best_distance TO distance.
            SET best_time TO check_time.
            
            LOCAL ship_vel IS VELOCITYAT(SHIP, check_time):ORBIT.
            LOCAL target_vel IS VELOCITYAT(TARGET, check_time):ORBIT.
            SET best_rel_vel TO (target_vel - ship_vel):MAG.
        }
        
        DISP_TICK().
    }
    
    LOCAL near_term_intercept IS LEXICON().
    SET near_term_intercept["orbit"] TO 0.
    SET near_term_intercept["time"] TO best_time.
    SET near_term_intercept["distance"] TO best_distance.
    SET near_term_intercept["rel_velocity"] TO best_rel_vel.
    SET near_term_intercept["eta"] TO best_time - TIME:SECONDS.
    
    intercepts:ADD(near_term_intercept).
    
    FOR orbit_num IN RANGE(1, scan_orbits + 1) {
        LOCAL scan_start IS TIME:SECONDS + (ship_period * (orbit_num - 0.1)).
        LOCAL scan_end IS scan_start + (ship_period * 0.2).
        
        SET best_distance TO 999999999.
        SET best_time TO scan_start.
        SET best_rel_vel TO 0.
        
        SET step TO (scan_end - scan_start) / samples_per_orbit.
        
        FOR sample IN RANGE(0, samples_per_orbit) {
            LOCAL check_time IS scan_start + (sample * step).
            LOCAL ship_pos IS POSITIONAT(SHIP, check_time).
            LOCAL target_pos IS POSITIONAT(TARGET, check_time).
            LOCAL distance IS (target_pos - ship_pos):MAG.
            
            IF distance < best_distance {
                SET best_distance TO distance.
                SET best_time TO check_time.
                
                LOCAL ship_vel IS VELOCITYAT(SHIP, check_time):ORBIT.
                LOCAL target_vel IS VELOCITYAT(TARGET, check_time):ORBIT.
                SET best_rel_vel TO (target_vel - ship_vel):MAG.
            }
            
            IF MOD(sample, 20) = 0 { DISP_TICK(). }
        }
        
        LOCAL intercept_data IS LEXICON().
        SET intercept_data["orbit"] TO orbit_num.
        SET intercept_data["time"] TO best_time.
        SET intercept_data["distance"] TO best_distance.
        SET intercept_data["rel_velocity"] TO best_rel_vel.
        SET intercept_data["eta"] TO best_time - TIME:SECONDS.
        
        intercepts:ADD(intercept_data).
    }
    
    RETURN intercepts.
}

FUNCTION _rdv_find_best_intercept {
    PARAMETER intercepts.
    
    LOCAL best_intercept IS LEXICON().
    SET best_intercept["distance"] TO 999999999.
    
    FOR intercept IN intercepts {
        IF intercept["distance"] < best_intercept["distance"] {
            SET best_intercept TO intercept.
        }
    }
    
    RETURN best_intercept.
}

// ------------------ STEP 4: ITERATIVE PHASING ------------------

FUNCTION _rdv_iterative_phasing {
    DISP_LOG_UPDATE("Step 4: Iterative phasing").
    
    LOCAL max_iterations IS 10.
    LOCAL iteration IS 0.
    LOCAL best_distance IS 999999999.
    LOCAL consecutive_poor_results IS 0.
    
    UNTIL iteration >= max_iterations OR consecutive_poor_results >= 3 {
        SET iteration TO iteration + 1.
        DISP_LOG_UPDATE("Phasing iteration " + iteration + "/10").
        
        LOCAL intercepts IS _rdv_scan_intercepts(RDV_CFG_SCAN_ORBITS).
        LOCAL best_intercept IS _rdv_find_best_intercept(intercepts).
        
        DISP_LOG_UPDATE("Best: " + ROUND(best_intercept["distance"]/1000, 1) + "km @ " + ROUND(best_intercept["rel_velocity"], 1) + "m/s").
        DISP_LOG_UPDATE("ETA: " + ROUND(best_intercept["eta"]/3600, 1) + " hours").
        
        IF best_intercept["distance"] <= RDV_CFG_RENDER_RANGE {
            DISP_SUCCESS("Intercept within render range").
            
            SET INTERCEPT_T TO best_intercept["time"].
            SET INTERCEPT_D TO best_intercept["distance"].
            SET INTERCEPT_VR TO best_intercept["rel_velocity"].
            
            RETURN TRUE.
        }
        
        IF best_intercept["distance"] < best_distance {
            SET best_distance TO best_intercept["distance"].
            SET consecutive_poor_results TO 0.
            DISP_LOG_UPDATE("Improvement - continuing").
        } ELSE {
            SET consecutive_poor_results TO consecutive_poor_results + 1.
            DISP_LOG_UPDATE("No improvement " + consecutive_poor_results + "/3").
        }
        
        DISP_LOG_UPDATE("Converging orbit").
        LOCAL target_ap IS TARGET:ORBIT:APOAPSIS.
        LOCAL target_pe IS TARGET:ORBIT:PERIAPSIS.
        LOCAL ship_ap IS SHIP:ORBIT:APOAPSIS.
        LOCAL ship_pe IS SHIP:ORBIT:PERIAPSIS.
        
        LOCAL new_ap IS ship_ap + ((target_ap - ship_ap) * 0.3).
        LOCAL new_pe IS _rdv_safe_periapsis(ship_pe + ((target_pe - ship_pe) * 0.3)).
        
        DISP_LOG_UPDATE("New orbit: " + ROUND(new_pe/1000, 1) + "x" + ROUND(new_ap/1000, 1) + "km").
        
        LOCAL pe_burn_eta IS SHIP:ORBIT:ETA:PERIAPSIS.
        IF pe_burn_eta < RDV_CFG_NODE_MIN_LEAD {
            SET pe_burn_eta TO pe_burn_eta + SHIP:ORBIT:PERIOD.
        }
        
        LOCAL current_v_at_pe IS SQRT(SHIP:ORBIT:BODY:MU * (2/(SHIP:ORBIT:PERIAPSIS + SHIP:ORBIT:BODY:RADIUS) - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
        LOCAL target_sma IS ((new_ap + SHIP:ORBIT:BODY:RADIUS) + (SHIP:ORBIT:PERIAPSIS + SHIP:ORBIT:BODY:RADIUS)) / 2.
        LOCAL target_v_at_pe IS SQRT(SHIP:ORBIT:BODY:MU * (2/(SHIP:ORBIT:PERIAPSIS + SHIP:ORBIT:BODY:RADIUS) - 1/target_sma)).
        LOCAL dv_prograde IS target_v_at_pe - current_v_at_pe.
        
        IF ABS(dv_prograde) > 0.5 {
            LOCAL phase_node IS NODE(TIME:SECONDS + pe_burn_eta, 0, 0, dv_prograde).
            ADD phase_node.
            _rdv_execute_node().
        }
        
        DISP_LOG_UPDATE("Waiting for effects").
        IF RDV_CFG_WARP {
            WARPTO(TIME:SECONDS + SHIP:ORBIT:PERIOD * 0.48).
        } ELSE {
            LOCAL wait_start IS TIME:SECONDS.
            UNTIL TIME:SECONDS - wait_start > SHIP:ORBIT:PERIOD * 0.5 {
                DISP_TICK().
                WAIT 1.
            }
        }
    }
    
    DISP_WARN("Max iterations reached").
    
    LOCAL final_intercepts IS _rdv_scan_intercepts(RDV_CFG_SCAN_ORBITS).
    LOCAL final_best IS _rdv_find_best_intercept(final_intercepts).
    
    SET INTERCEPT_T TO final_best["time"].
    SET INTERCEPT_D TO final_best["distance"].
    SET INTERCEPT_VR TO final_best["rel_velocity"].
    
    RETURN final_best["distance"] <= (RDV_CFG_RENDER_RANGE * 10).
}

// ------------------ STEP 5: RELATIVE VELOCITY REDUCTION ------------------

FUNCTION _rdv_reduce_relative_velocity {
    PARAMETER target_time.
    
    DISP_LOG_UPDATE("Step 5: Velocity reduction").
    
    LOCAL approach_time IS target_time.
    LOCAL time_to_intercept IS approach_time - TIME:SECONDS.
    
    LOCAL passes IS 3.
    LOCAL pass_interval IS time_to_intercept / passes.
    
    FOR pass IN RANGE(1, passes + 1) {
        LOCAL check_time IS TIME:SECONDS + (pass * pass_interval).
        
        IF check_time >= approach_time - 60 { BREAK. }
        
        DISP_LOG_UPDATE("Velocity reduction pass " + pass + "/3").
        
        LOCAL ship_vel IS VELOCITYAT(SHIP, approach_time):ORBIT.
        LOCAL target_vel IS VELOCITYAT(TARGET, approach_time):ORBIT.
        LOCAL rel_vel_vec IS target_vel - ship_vel.
        LOCAL rel_vel_mag IS rel_vel_vec:MAG.
        
        DISP_LOG_UPDATE("Rel vel at intercept: " + ROUND(rel_vel_mag, 1) + "m/s").
        
        IF rel_vel_mag <= RDV_CFG_MAX_RVEL {
            DISP_SUCCESS("Relative velocity acceptable").
            BREAK.
        }
        
        LOCAL burn_time IS check_time.
        LOCAL reduction_factor IS 0.4.
        LOCAL dv_needed IS rel_vel_vec * reduction_factor.
        
        LOCAL prograde_dv IS VDOT(dv_needed, VELOCITYAT(SHIP, burn_time):ORBIT:NORMALIZED).
        LOCAL normal_dv IS VDOT(dv_needed, VCRS(VELOCITYAT(SHIP, burn_time):ORBIT, POSITIONAT(SHIP, burn_time)):NORMALIZED).
        LOCAL radial_dv IS VDOT(dv_needed, VCRS(VELOCITYAT(SHIP, burn_time):ORBIT, VCRS(VELOCITYAT(SHIP, burn_time):ORBIT, POSITIONAT(SHIP, burn_time))):NORMALIZED).
        
        DISP_LOG_UPDATE("Burn: P=" + ROUND(prograde_dv, 2) + " N=" + ROUND(normal_dv, 2) + " R=" + ROUND(radial_dv, 2)).
        
        LOCAL rvel_node IS NODE(burn_time, radial_dv, normal_dv, prograde_dv).
        ADD rvel_node.
        
        IF RDV_CFG_WARP {
            WARPTO(burn_time - 30).
        }
        _rdv_execute_node().
        
        WAIT 5.
    }
    
    DISP_SUCCESS("Velocity reduction complete").
    RETURN TRUE.
}

// ------------------ MAIN ENTRY POINT ------------------

FUNCTION RENDEZVOUS_EXECUTE {
    PARAMETER target_range IS 800.
    
    IF NOT HASTARGET {
        DISP_ERROR("No target selected").
        RETURN FALSE.
    }
    
    DISP_LOG_UPDATE("Classical Orbital Rendezvous").
    DISP_LOG_UPDATE("Target: " + TARGET:NAME).
    DISP_LOG_UPDATE("Target range: " + target_range + "m").
    
    SET RDV_CFG_TARGET_RANGE TO target_range.
    
    // Check for existing good encounters first
    LOCAL encounter_status IS _rdv_check_existing_encounters().
    
    IF encounter_status = "excellent" {
        DISP_SUCCESS("Using excellent existing encounter").
        DISP_LOG_UPDATE("No modifications needed").
        DISP_LOG_UPDATE("Sep: " + ROUND(INTERCEPT_D, 0) + "m").
        DISP_LOG_UPDATE("Rel vel: " + ROUND(INTERCEPT_VR, 1) + "m/s").
        DISP_LOG_UPDATE("ETA: " + ROUND((INTERCEPT_T - TIME:SECONDS)/60, 1) + "min").
        RETURN TRUE.
    }
    
    IF encounter_status = "very_good" {
        DISP_SUCCESS("Using very good encounter").
        IF (INTERCEPT_T - TIME:SECONDS) > 1800 {
            DISP_LOG_UPDATE("Applying velocity reduction").
            _rdv_reduce_relative_velocity(INTERCEPT_T).
        }
        DISP_LOG_UPDATE("Sep: " + ROUND(INTERCEPT_D, 0) + "m").
        DISP_LOG_UPDATE("Rel vel: " + ROUND(INTERCEPT_VR, 1) + "m/s").
        DISP_LOG_UPDATE("ETA: " + ROUND((INTERCEPT_T - TIME:SECONDS)/60, 1) + "min").
        RETURN TRUE.
    }
    
    IF encounter_status = "acceptable" {
        DISP_LOG_UPDATE("Acceptable encounter - light tuning").
        
        IF (INTERCEPT_T - TIME:SECONDS) > 3600 AND INTERCEPT_D > 8000 {
            DISP_LOG_UPDATE("Attempting adjustment burn").
            LOCAL target_ap IS TARGET:ORBIT:APOAPSIS.
            LOCAL ship_ap IS SHIP:ORBIT:APOAPSIS.
            
            IF ABS(ship_ap - target_ap) > 2000 {
                LOCAL pe_burn_eta IS SHIP:ORBIT:ETA:PERIAPSIS.
                IF pe_burn_eta > 300 {
                    LOCAL current_v_at_pe IS SQRT(SHIP:ORBIT:BODY:MU * (2/(SHIP:ORBIT:PERIAPSIS + SHIP:ORBIT:BODY:RADIUS) - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
                    LOCAL target_sma IS ((target_ap + SHIP:ORBIT:BODY:RADIUS) + (SHIP:ORBIT:PERIAPSIS + SHIP:ORBIT:BODY:RADIUS)) / 2.
                    LOCAL target_v_at_pe IS SQRT(SHIP:ORBIT:BODY:MU * (2/(SHIP:ORBIT:PERIAPSIS + SHIP:ORBIT:BODY:RADIUS) - 1/target_sma)).
                    LOCAL dv_prograde IS (target_v_at_pe - current_v_at_pe) * 0.3.
                    
                    IF ABS(dv_prograde) > 1 {
                        LOCAL gentle_node IS NODE(TIME:SECONDS + pe_burn_eta, 0, 0, dv_prograde).
                        ADD gentle_node.
                        _rdv_execute_node().
                        
                        LOCAL new_intercepts IS _rdv_scan_intercepts(10).
                        LOCAL new_best IS _rdv_find_best_intercept(new_intercepts).
                        SET INTERCEPT_T TO new_best["time"].
                        SET INTERCEPT_D TO new_best["distance"].
                        SET INTERCEPT_VR TO new_best["rel_velocity"].
                    }
                }
            }
        }
        DISP_LOG_UPDATE("Using encounter: " + ROUND(INTERCEPT_D, 0) + "m").
        DISP_LOG_UPDATE("Rel vel: " + ROUND(INTERCEPT_VR, 1) + "m/s").
        DISP_LOG_UPDATE("ETA: " + ROUND((INTERCEPT_T - TIME:SECONDS)/60, 1) + "min").
        RETURN TRUE.
    }
    
    // No good encounter - full sequence
    DISP_LOG_UPDATE("Full rendezvous sequence required").
    
    // Step 1
    IF NOT _rdv_match_inclination() {
        DISP_ERROR("Inclination matching failed").
        RETURN FALSE.
    }
    
    // Step 2
    IF NOT _rdv_align_orbits() {
        DISP_ERROR("Orbit alignment failed").
        RETURN FALSE.
    }
    
    // Step 3
    LOCAL target_ahead IS _rdv_analyze_relative_position().
    
    // Step 3A/3B
    IF NOT _rdv_setup_phasing_orbit(target_ahead) {
        DISP_ERROR("Phasing orbit setup failed").
        RETURN FALSE.
    }
    
    // Step 4
    IF NOT _rdv_iterative_phasing() {
        DISP_WARN("Phasing incomplete - using fallback").
        
        LOCAL fallback_intercepts IS _rdv_scan_intercepts(20, 300).
        LOCAL fallback_best IS _rdv_find_best_intercept(fallback_intercepts).
        
        DISP_LOG_UPDATE("Fallback: " + ROUND(fallback_best["distance"]/1000, 1) + "km @ " + ROUND(fallback_best["rel_velocity"], 1) + "m/s").
        
        IF fallback_best["distance"] <= (RDV_CFG_RENDER_RANGE * 10) {
            DISP_LOG_UPDATE("Accepting fallback intercept").
            SET INTERCEPT_T TO fallback_best["time"].
            SET INTERCEPT_D TO fallback_best["distance"].
            SET INTERCEPT_VR TO fallback_best["rel_velocity"].
        } ELSE {
            DISP_ERROR("No acceptable intercept found").
            DISP_LOG_UPDATE("Manual intervention required").
            RETURN FALSE.
        }
    }
    
    // Step 5
    IF INTERCEPT_D <= (RDV_CFG_RENDER_RANGE * 5) {
        IF NOT _rdv_reduce_relative_velocity(INTERCEPT_T) {
            DISP_WARN("Velocity reduction incomplete").
        }
    } ELSE {
        DISP_LOG_UPDATE("Skipping velocity reduction - too distant").
    }
    
    DISP_SUCCESS("Rendezvous setup complete").
    DISP_LOG_UPDATE("Sep: " + ROUND(INTERCEPT_D, 0) + "m").
    DISP_LOG_UPDATE("Rel vel: " + ROUND(INTERCEPT_VR, 1) + "m/s").
    DISP_LOG_UPDATE("ETA: " + ROUND((INTERCEPT_T - TIME:SECONDS)/60, 1) + "min").
    
    RETURN TRUE.
}

// Export for backward compatibility
FUNCTION REFINE_DECIDE_AND_PHASE {
    PARAMETER pickIn IS LEXICON(), targetRange IS 800, maxWaitSec IS 7200, nMin IS 2, nMax IS 4.
    RETURN RENDEZVOUS_EXECUTE(targetRange).
}