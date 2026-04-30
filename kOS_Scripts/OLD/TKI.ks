@LAZYGLOBAL OFF.

// ═══════════════════════════════════════════════════════
// APOLLO TEI SEARCH - Find optimal return trajectory
// Creates maneuver node, then use TEI_EXEC to execute
// ═══════════════════════════════════════════════════════

FUNCTION MAIN {
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  APOLLO TEI TRAJECTORY SEARCH                  ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    SET TARGET TO KERBIN.
    
    LOCAL target_kerbin_pe IS 30000.  // 30km for reentry
    
    PRINT "Searching for optimal return trajectory...".
    PRINT "Target Kerbin Pe: 30 km".
    PRINT " ".
    
    // Calculate base escape dV
    LOCAL radius IS SHIP:ALTITUDE + SHIP:BODY:RADIUS.
    LOCAL mu IS SHIP:BODY:MU.
    LOCAL v_current IS SQRT(mu / radius).
    LOCAL v_escape IS SQRT(2 * mu / radius).
    LOCAL base_dv IS (v_escape - v_current) + 80.  // Escape + margin
    
    // Search different burn timings
    LOCAL best_time IS 0.
    LOCAL best_dv IS 0.
    LOCAL best_score IS 999999999.
    LOCAL found_any IS FALSE.
    
    LOCAL period IS SHIP:ORBIT:PERIOD.
    LOCAL time_step IS period / 30.  // 30 positions around orbit
    
    FROM {LOCAL offset IS 0.} UNTIL offset > period STEP {SET offset TO offset + time_step.} DO {
        
        LOCAL test_time IS TIME:SECONDS + offset.
        
        // Try different dV values at each position
        FROM {LOCAL dv_offset IS -40.} UNTIL dv_offset > 40 STEP {SET dv_offset TO dv_offset + 10.} DO {
            
            UNTIL NOT HASNODE {
                REMOVE NEXTNODE.
                WAIT 0.05.
            }
            
            LOCAL test_dv IS base_dv + dv_offset.
            LOCAL test_node IS NODE(test_time, 0, 0, test_dv).
            ADD test_node.
            WAIT 0.1.
            
            // Check if we get Kerbin encounter
            IF test_node:ORBIT:HASNEXTPATCH AND test_node:ORBIT:NEXTPATCH:BODY = KERBIN {
                LOCAL kerbin_pe IS test_node:ORBIT:NEXTPATCH:PERIAPSIS.
                
                // Score based on how close to 30km target
                LOCAL score IS ABS(kerbin_pe - target_kerbin_pe).
                
                IF score < best_score {
                    PRINT "Better at T+" + ROUND(offset/60, 1) + "min: Kerbin Pe=" + ROUND(kerbin_pe/1000, 1) + "km".
                    
                    SET best_score TO score.
                    SET best_time TO test_time.
                    SET best_dv TO test_dv.
                    SET found_any TO TRUE.
                }
            }
            
            REMOVE test_node.
        }
    }
    
    UNTIL NOT HASNODE {
        REMOVE NEXTNODE.
    }
    
    IF NOT found_any {
        PRINT " ".
        PRINT "ERROR: No Kerbin return trajectory found!".
        PRINT "May need to wait for better orbital geometry.".
        RETURN.
    }
    
    // Create final node
    LOCAL tei_node IS NODE(best_time, 0, 0, best_dv).
    ADD tei_node.
    WAIT 0.2.
    
    LOCAL final_kerbin_pe IS tei_node:ORBIT:NEXTPATCH:PERIAPSIS.
    
    PRINT " ".
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  OPTIMAL TEI TRAJECTORY FOUND                 ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    PRINT "MANEUVER NODE CREATED:".
    PRINT "  Time to burn:    T+" + ROUND(tei_node:ETA/60, 1) + " min".
    PRINT "  Delta-V:         " + ROUND(best_dv, 1) + " m/s".
    PRINT "  Kerbin Pe:       " + ROUND(final_kerbin_pe/1000, 1) + " km".
    PRINT " ".
    PRINT "Copy TEI_EXEC to local storage before losing comms:".
    //PRINT "  COPYPATH(\"0:/tei_exec.ks\", \"1:/tei_exec.ks\").".
    PRINT " ".
    //PRINT "Then run: RUNPATH(\"1:/tei_exec.ks\").".
}

MAIN().