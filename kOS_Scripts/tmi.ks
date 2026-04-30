@LAZYGLOBAL OFF.

PARAMETER MainEng IS 9, StageUllage IS 8.

RUNONCEPATH("0:/lib/utils.ks").

IF MainEng = 0 {
    PRINT "Parameters are Main Engine Action Group, Ullage Action Group.".
    PRINT "Run sivbimpact Main, Ullage.".
    PRINT "Default is 9 and 8.".
    WAIT UNTIL FALSE.
}

// ═══════════════════════════════════════════════════════
// HELPER FUNCTIONS
// ═══════════════════════════════════════════════════════

FUNCTION DISPLAY_HEADER {
    PARAMETER title.
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  APOLLO MISSION CONTROL - TMI PROGRAM          ║".
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

// ═══════════════════════════════════════════════════════
// MAIN PROGRAM
// ═══════════════════════════════════════════════════════

FUNCTION MAIN {
    
    // Target parameters
    GLOBAL TARGET_MUN_PE IS 20000.
    GLOBAL TARGET_MUN_PE_MAX IS 50000.
    GLOBAL TARGET_KERBIN_PE IS 30000.
    
    SET TARGET TO MUN.
    
    // ═══════════════════════════════════════════════════════
    // STEP 1: Calculate initial node position
    // ═══════════════════════════════════════════════════════
    
    DISPLAY_HEADER("CALCULATING TRAJECTORY").
    
    PRINT "Step 1: Calculating initial node position...".
    
    LOCAL ship_pos IS SHIP:POSITION - BODY:POSITION.
    LOCAL mun_pos IS MUN:POSITION - BODY:POSITION.
    
    LOCAL angle_to_mun IS VANG(ship_pos, mun_pos).
    LOCAL cross_check IS VDOT(VCRS(ship_pos, mun_pos), SHIP:BODY:ANGULARVEL).
    IF cross_check < 0 {
        SET angle_to_mun TO 360 - angle_to_mun.
    }
    
    LOCAL target_angle IS angle_to_mun + 180.
    IF target_angle >= 360 SET target_angle TO target_angle - 360.
    
    LOCAL time_to_opposite IS (target_angle / 360) * SHIP:ORBIT:PERIOD.
    IF time_to_opposite < 60 SET time_to_opposite TO time_to_opposite + SHIP:ORBIT:PERIOD.
    
    LOCAL base_time IS TIME:SECONDS + time_to_opposite.
    
    // Calculate dV for 13,500 km apoapsis
    LOCAL target_apoapsis IS 13500000.
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL r_current IS SHIP:ALTITUDE + SHIP:BODY:RADIUS.
    LOCAL a_target IS (r_current + target_apoapsis) / 2.
    LOCAL v_target IS SQRT(mu * (2/r_current - 1/a_target)).
    LOCAL v_current IS SQRT(mu / r_current).
    LOCAL base_dv IS v_target - v_current.
    
    PRINT "  Base time: T+" + ROUND((base_time - TIME:SECONDS)/60, 1) + " min".
    PRINT "  Base dV: " + ROUND(base_dv, 1) + " m/s".
    PRINT " ".
    
    // ═══════════════════════════════════════════════════════
    // STEP 2: Grid search for free return encounter
    // ═══════════════════════════════════════════════════════
    
    PRINT "Step 2: Searching for free return encounter...".
    PRINT " ".
    
    LOCAL best_time IS 0.
    LOCAL best_dv IS 0.
    LOCAL best_score IS 999999999.
    LOCAL found_any IS FALSE.
    
    LOCAL time_search_range IS SHIP:ORBIT:PERIOD * 0.50.  // Search 1/2 orbit
    LOCAL time_step IS SHIP:ORBIT:PERIOD / 40.
    
    FROM {LOCAL time_offset IS 0.} UNTIL time_offset > time_search_range STEP {SET time_offset TO time_offset + time_step.} DO {
        
        LOCAL test_time IS base_time + time_offset.
        
        FROM {LOCAL dv_offset IS -50.} UNTIL dv_offset > 50 STEP {SET dv_offset TO dv_offset + 10.} DO {
            
            UNTIL NOT HASNODE {
                REMOVE NEXTNODE.
                WAIT 0.05.
            }
            
            LOCAL test_dv IS base_dv + dv_offset.
            LOCAL test_node IS NODE(test_time, 0, 0, test_dv).
            ADD test_node.
            WAIT 0.1.
            
            IF test_node:ORBIT:HASNEXTPATCH AND test_node:ORBIT:NEXTPATCH:BODY = MUN {
                IF test_node:ORBIT:NEXTPATCH:HASNEXTPATCH AND test_node:ORBIT:NEXTPATCH:NEXTPATCH:BODY = KERBIN {
                    
                    // Check for retrograde flyby (front approach)
                    LOCAL encounter_inclination IS test_node:ORBIT:NEXTPATCH:INCLINATION.
                    IF encounter_inclination > 90 {
                        // Correct side - proceed with scoring
                        LOCAL mun_pe IS test_node:ORBIT:NEXTPATCH:PERIAPSIS.
                        LOCAL ker_pe IS test_node:ORBIT:NEXTPATCH:NEXTPATCH:PERIAPSIS.
                        
                        LOCAL ker_error IS ABS(ker_pe - TARGET_KERBIN_PE).
                        LOCAL mun_error IS 0.
                        
                        IF mun_pe < TARGET_MUN_PE OR mun_pe > TARGET_MUN_PE_MAX {
                            SET mun_error TO ABS(mun_pe - TARGET_MUN_PE) * 10.
                        } ELSE {
                            SET mun_error TO ABS(mun_pe - TARGET_MUN_PE).
                        }
                        
                        LOCAL score IS ker_error * 100 + mun_error.
                        
                        IF score < best_score {
                            LOCAL node_clock IS 6 + (time_offset / SHIP:ORBIT:PERIOD * 12).
                            IF node_clock > 12 SET node_clock TO node_clock - 12.
                            
                            //PRINT "Better at ~" + ROUND(node_clock,1) + " o'clock: Mun=" + ROUND(mun_pe/1000,1) + "km, Kerbin=" + ROUND(ker_pe/1000,1) + "km".
                            
                            SET best_score TO score.
                            SET best_time TO test_time.
                            SET best_dv TO test_dv.
                            SET found_any TO TRUE.
                        }
                    }
                }
            }
            
            REMOVE test_node.
        }
    }
    
    UNTIL NOT HASNODE {
        REMOVE NEXTNODE.
    }
    
    IF NOT found_any {
        PRINT "ERROR: No free return trajectory found!".
        PRINT "Script terminated.".
        RETURN.
    }
    
    // Recreate the best node
    LOCAL tmi_node IS NODE(best_time, 0, 0, best_dv).
    ADD tmi_node.
    WAIT 0.2.
    
    // ═══════════════════════════════════════════════════════
    // STEP 3: Pre-burn display and confirmation
    // ═══════════════════════════════════════════════════════
    
    DISPLAY_HEADER("TRAJECTORY SOLUTION FOUND").
    
    LOCAL final_mun_pe IS tmi_node:ORBIT:NEXTPATCH:PERIAPSIS.
    LOCAL final_ker_pe IS tmi_node:ORBIT:NEXTPATCH:NEXTPATCH:PERIAPSIS.
    
    PRINT "CURRENT ORBIT:".
    PRINT "  Altitude:        " + ROUND(SHIP:ALTITUDE/1000, 1) + " km".
    PRINT "  Period:          " + ROUND(SHIP:ORBIT:PERIOD/60, 1) + " min".
    PRINT "  Velocity:        " + ROUND(SHIP:VELOCITY:ORBIT:MAG, 1) + " m/s".
    PRINT " ".
    
    PRINT "MANEUVER NODE:".
    PRINT "  Time to burn:    T+" + ROUND((tmi_node:ETA)/60, 1) + " min".
    PRINT "  Prograde:        " + ROUND(tmi_node:PROGRADE, 1) + " m/s".
    PRINT "  Radial:          " + ROUND(tmi_node:RADIALOUT, 1) + " m/s".
    PRINT "  Total Delta-V:   " + ROUND(tmi_node:DELTAV:MAG, 1) + " m/s".
    PRINT " ".
    
    PRINT "PROJECTED ENCOUNTER:".
    PRINT "  Mun Periapsis:   " + ROUND(final_mun_pe/1000, 1) + " km".
    PRINT "  Kerbin Return:   " + ROUND(final_ker_pe/1000, 1) + " km".
    PRINT " ".
    
    // Calculate burn duration
    LOCAL isp IS 0.
    LOCAL thrust IS 0.
    LOCAL shipmass IS SHIP:MASS.
    
    LOCAL eng_list IS LIST().
    LIST ENGINES IN eng_list.
    FOR eng IN eng_list {
        IF eng:IGNITION {
            SET thrust TO thrust + eng:AVAILABLETHRUST.
            SET isp TO isp + (eng:ISP * eng:AVAILABLETHRUST).
        }
    }
    
    LOCAL burn_duration IS 0.
    IF thrust > 0 {
        SET isp TO isp / thrust.
        LOCAL ve IS isp * 9.81.
        LOCAL dv IS tmi_node:DELTAV:MAG.
        SET burn_duration TO ve * shipmass * (1 - CONSTANT:E^(-dv/ve)) / thrust.
    }
    
    LOCAL half_burn IS burn_duration / 2.
    
    PRINT "BURN PARAMETERS:".
    PRINT "  Duration:        " + ROUND(burn_duration, 1) + " sec".
    PRINT "  Ignition:        T+" + ROUND((tmi_node:ETA - half_burn)/60, 1) + " min".
    PRINT " ".
    
    PRINT "═══════════════════════════════════════════════════".
    PRINT " ".
    PRINT "(P) PROCEED WITH BURN".
    PRINT "(C) CANCEL AND ABORT".
    PRINT " ".
    PRINT "Awaiting confirmation...".
    
    LOCAL confirmed IS FALSE.
    UNTIL confirmed {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
            IF ch = "P" {
                SET confirmed TO TRUE.
                PRINT " ".
                PRINT "BURN SEQUENCE CONFIRMED - PROCEEDING".
            } ELSE IF ch = "C" {
                PRINT " ".
                PRINT "MISSION ABORTED BY FLIGHT DIRECTOR".
                REMOVE tmi_node.
                RETURN.
            }
        }
        WAIT 0.1.
    }
    
    // ═══════════════════════════════════════════════════════
    // STEP 4: Burn execution sequence
    // ═══════════════════════════════════════════════════════
    
    DISPLAY_HEADER("BURN EXECUTION SEQUENCE").
    
    PRINT "Maintaining prograde attitude. You may warp manually.".
    SAS OFF.
    LOCK STEERING TO PROGRADE.
    
    WAIT UNTIL tmi_node:ETA <= 300.
    
    PRINT "T-5 minutes - canceling warp if active...".
    KUNIVERSE:TIMEWARP:CANCELWARP().
    WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
    
    PRINT "Orienting to burn attitude...".
    RCS OFF.
    
    LOCK STEERING TO tmi_node:DELTAV.
    
    WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, tmi_node:DELTAV) < 1.0.
    
    PRINT "Attitude locked. Waiting for burn window...".
    PRINT " ".
    
    // Wait until time for countdown
    WAIT UNTIL tmi_node:ETA <= (half_burn + 30).
    
    // CHECK Third stage Engine STATUS BEFORE ULLAGE SEQUENCE
    // We make sure it is ON, then Turn it OFF.
    PRINT "Checking J-2 engine status...".
    LOCAL j2_is_on IS FALSE.
    LOCAL eng_list IS LIST().
    LIST ENGINES IN eng_list.

    FOR eng IN eng_list {
        // J-2 has high thrust (>100kN) - ullage motors are ~20kN
        IF eng:MAXTHRUST > 100000 {
            IF eng:IGNITION {
                SET j2_is_on TO TRUE.
                PRINT "Third stage Engine: ONLINE".
            } ELSE {
                PRINT "Third stage Engine: OFFLINE - Activating...".
                //AG9 OFF.  // Turn on
                ToggleEngine(MainEng, FALSE).
                WAIT 2.
                SET j2_is_on TO TRUE.
            }
            BREAK.
        }
    }

    //IF NOT j2_is_on {
    //    PRINT "WARNING: J-2 Engine not found!".
    //}

    WAIT 1.

    // Countdown from 10
    PRINT " ".
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║           TMI BURN COUNTDOWN                   ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    FROM {LOCAL count IS 10.} UNTIL count = 0 STEP {SET count TO count - 1.} DO {
        PRINT "T-" + count + " seconds...".
        WAIT 1.
    }
    
    PRINT " ".
    PRINT "IGNITION SEQUENCE STARTED".
    
    // S-IVB Ullage Sequence
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║           S-IVB ULLAGE SEQUENCE                ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    PRINT "S-IVB J-2 Engine SHUTDOWN for ullage".
    //AG9 ON.
    ToggleEngine(MainEng, TRUE).
    WAIT 1.
    
    PRINT "Ullage Motors FIRING".
    LOCK THROTTLE TO 1.
    //AG8 OFF.
    ToggleEngine(StageUllage,FALSE).
    WAIT 5.
    
    PRINT "S-IVB J-2 Engine RESTART".
    //AG9 OFF.
    ToggleEngine(MainEng, FALSE).
    WAIT 2.
    
    PRINT "Ullage Motors SHUTDOWN".
    //AG8 ON.
    ToggleEngine(StageUllage, TRUE).
    WAIT 1.
    
    PRINT " ".
    PRINT "IGNITION!".
    
    // Initialize burn monitoring variables
    LOCAL target_mun_pe IS TARGET_MUN_PE.  // 20km target
    LOCAL best_mun_pe IS 999999999.  // Track best Pe achieved
    LOCAL dv0 IS tmi_node:DELTAV.
    LOCAL max_dv IS dv0:MAG * 1.1.

    // Burn monitoring with Mun Pe tracking
    LOCAL start_time IS TIME:SECONDS.
    LOCAL last_update IS TIME:SECONDS.

    UNTIL tmi_node:DELTAV:MAG < 0.1 {
        
        LOCAL dv_remaining IS tmi_node:DELTAV:MAG.
        LOCAL dv_burned IS max_dv - dv_remaining.
        
        // Safety check
        IF dv_burned > max_dv {
            PRINT "SAFETY CUTOFF: Maximum dV exceeded!".
            BREAK.
        }
        
        // Monitor Mun Pe with geometry verification
        IF SHIP:ORBIT:HASNEXTPATCH AND SHIP:ORBIT:NEXTPATCH:BODY = MUN {
            LOCAL current_mun_pe IS SHIP:ORBIT:NEXTPATCH:PERIAPSIS.
            LOCAL encounter_inclination IS SHIP:ORBIT:NEXTPATCH:INCLINATION.
            
            // Only track Pe if we're on the correct side (retrograde/front)
            IF encounter_inclination > 90 {
                IF ABS(current_mun_pe - target_mun_pe) < ABS(best_mun_pe - target_mun_pe) {
                    SET best_mun_pe TO current_mun_pe.
                }
                
                IF ABS(current_mun_pe - target_mun_pe) < 5000 {
                    IF current_mun_pe > best_mun_pe + 3000 {
                        PRINT "Mun Pe optimal (front approach): " + ROUND(best_mun_pe/1000, 1) + " km - CUTOFF".
                        BREAK.
                    }
                }
            } ELSE {
                PRINT "WARNING: Wrong approach side - continuing burn".
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
        
        IF TIME:SECONDS - last_update > 1 {
            LOCAL elapsed IS TIME:SECONDS - start_time.
            LOCAL status_line IS "Burn: " + ROUND(elapsed, 1) + "s | dV: " + ROUND(dv_remaining, 1) + " m/s | Thr: " + ROUND(throttle_setting * 100, 0) + "%".
            
            IF SHIP:ORBIT:HASNEXTPATCH AND SHIP:ORBIT:NEXTPATCH:BODY = MUN {
                LOCAL current_mun_pe IS SHIP:ORBIT:NEXTPATCH:PERIAPSIS.
                SET status_line TO status_line + " | Mun Pe: " + ROUND(current_mun_pe/1000, 1) + " km".
            }
            
            PRINT status_line.
            SET last_update TO TIME:SECONDS.
        }
        
        LOCK STEERING TO tmi_node:DELTAV.
        WAIT 0.01.
    }
    
    LOCK THROTTLE TO 0.
    ToggleEngine(MainEng, TRUE).
    //AG9 ON.  // Turn OFF third stage.
    UNLOCK STEERING.
    UNLOCK THROTTLE.
    SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
    SAS ON.
    
    WAIT 1.
    
    REMOVE tmi_node.
    
    // ═══════════════════════════════════════════════════════
    // STEP 5: Post-burn trajectory analysis
    // ═══════════════════════════════════════════════════════
    
    WAIT 2.
    
    DISPLAY_HEADER("BURN COMPLETE - TRAJECTORY ANALYSIS").
    
    LOCAL actual_mun_pe IS 0.
    LOCAL actual_ker_pe IS 0.
    LOCAL time_to_mun IS 0.
    
    IF SHIP:ORBIT:HASNEXTPATCH AND SHIP:ORBIT:NEXTPATCH:BODY = MUN {
        SET actual_mun_pe TO SHIP:ORBIT:NEXTPATCH:PERIAPSIS.
        SET time_to_mun TO ETA:TRANSITION.
        
        IF SHIP:ORBIT:NEXTPATCH:HASNEXTPATCH AND SHIP:ORBIT:NEXTPATCH:NEXTPATCH:BODY = KERBIN {
            SET actual_ker_pe TO SHIP:ORBIT:NEXTPATCH:NEXTPATCH:PERIAPSIS.
        }
    }
    
    PRINT "TRAJECTORY STATUS:".
    PRINT "  Mun Encounter:   T+" + ROUND(time_to_mun/3600, 1) + " hours".
    PRINT "  Mun Periapsis:   " + ROUND(actual_mun_pe/1000, 1) + " km".
    PRINT "  Kerbin Return:   " + ROUND(actual_ker_pe/1000, 1) + " km".
    PRINT " ".
    
    LOCAL mun_error IS ABS(actual_mun_pe - TARGET_MUN_PE).
    LOCAL ker_error IS ABS(actual_ker_pe - TARGET_KERBIN_PE).
    
    PRINT "DEVIATION FROM TARGET:".
    PRINT "  Mun Pe Error:    " + ROUND(mun_error/1000, 1) + " km".
    PRINT "  Kerbin Pe Error: " + ROUND(ker_error/1000, 1) + " km".
    PRINT " ".
    
    LOCAL needs_mcc IS FALSE.
    PRINT "MID-COURSE CORRECTION ASSESSMENT:".
    
    IF actual_mun_pe < TARGET_MUN_PE OR actual_mun_pe > TARGET_MUN_PE_MAX {
        PRINT "  ⚠ Mun flyby outside acceptable range".
        PRINT "    Recommend MCC to adjust approach".
        SET needs_mcc TO TRUE.
    }
    
    IF actual_ker_pe < 25000 {
        PRINT "  ⚠ Kerbin return too LOW - atmospheric impact".
        PRINT "    CRITICAL: MCC required to raise periapsis".
        SET needs_mcc TO TRUE.
    } ELSE IF actual_ker_pe > 80000 {
        PRINT "  ⚠ Kerbin return too HIGH - may escape SOI".
        PRINT "    Recommend MCC to lower periapsis".
        SET needs_mcc TO TRUE.
    }
    
    IF NOT needs_mcc {
        PRINT "  ✓ Trajectory nominal - no MCC required".
        PRINT "  ✓ Free return trajectory confirmed".
    }
    
    PRINT " ".
    PRINT "═══════════════════════════════════════════════════".
    PRINT " ".
    PRINT "TRANS-MUNAR INJECTION COMPLETE".
    PRINT "Coasting to Mun encounter...".

    // ═══════════════════════════════════════════════════════
    // STEP 6: Transposition and Docking
    // ═══════════════════════════════════════════════════════

    WAIT 10.
    PRINT "".
    PRINT "When ready, press ENTER to being.".
    PRINT "Transportion and Docking".
    PRINT "(else CTLR+C to END).".
    PRINT "".

    LOCAL inputStr IS "".
    UNTIL inputStr:CONTAINS(TERMINAL:INPUT:RETURN) {
        IF TERMINAL:INPUT:HASCHAR{
            SET inputStr TO inputStr + TERMINAL:INPUT:GETCHAR().
        }
        WAIT 0.1.
    }

    TERMINAL:INPUT:CLEAR.
    PROCESSOR("SATV"):ACTIVATE().
    AG7 ON.  //Stages protective shell/Activates Engine.
    PRINT "Stage CSM from SIV-B Stage.".
    WAIT 0.2.
    AG4 ON.
    WAIT 0.1.
    AG7 OFF. // Turn off Engine as we are now free.
    AG10 OFF. // Turn on RCS of CSM.
    RCS ON.
    WAIT 0.1.
    SET SHIP:CONTROL:FORE TO 1.
    WAIT 2.
    SET SHIP:CONTROL:FORE TO 0.

    PRINT "CSM Pilot has control.".
    UNLOCK ALL.
    PRINT ">>>>>> PROGRAM END <<<<<<<".

}

// ═══════════════════════════════════════════════════════
// PROGRAM START
// ═══════════════════════════════════════════════════════

MAIN().