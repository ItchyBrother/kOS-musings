@LAZYGLOBAL OFF.

RUNONCEPATH("0:/lib/utils.ks").

// ═══════════════════════════════════════════════════════
// TKI (TRANS-KERBIN INJECTION) - MUN ESCAPE
// Creates escape node opposite Kerbin for optimal escape
// ═══════════════════════════════════════════════════════

FUNCTION MAIN {
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  TKI - TRANS-KERBIN INJECTION                  ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    // === SOI CHECK ===
    IF SHIP:BODY:NAME <> "Mun" {
        PRINT "*** ERROR: Not in Mun SOI ***".
        PRINT "Current SOI: " + SHIP:BODY:NAME.
        WAIT 5.
        RETURN.
    }
    
    // === CURRENT ORBIT ===
    PRINT "CURRENT ORBIT:".
    PRINT "  Body:        " + SHIP:BODY:NAME.
    PRINT "  Apoapsis:    " + UTL_FMTDIST(SHIP:ORBIT:APOAPSIS).
    PRINT "  Periapsis:   " + UTL_FMTDIST(SHIP:ORBIT:PERIAPSIS).
    PRINT "  Period:      " + ROUND(SHIP:ORBIT:PERIOD/60, 1) + " min".
    PRINT "  Inclination: " + ROUND(SHIP:ORBIT:INCLINATION, 2) + " deg".
    PRINT " ".
    
    // === FIND ANTI-KERBIN POSITION ===
    // Scan orbit to find when ship is opposite Kerbin from Mun
    // Goal: ship ---- Mun ---- Kerbin (angle ~180°)
    
    LOCAL orbitPeriod IS SHIP:ORBIT:PERIOD.
    LOCAL bestTime IS 0.
    LOCAL bestAngle IS 0.
    LOCAL scanStep IS orbitPeriod / 36.  // 10-degree increments
    
    FROM {LOCAL t IS 30.} UNTIL t > orbitPeriod + 30 STEP {SET t TO t + scanStep.} DO {
        LOCAL futureTime IS TIME:SECONDS + t.
        LOCAL shipPos IS POSITIONAT(SHIP, futureTime) - MUN:POSITION.
        LOCAL kerbinPos IS KERBIN:POSITION - MUN:POSITION.
        
        // Angle between ship and Kerbin as seen from Mun
        LOCAL angle IS VANG(shipPos, kerbinPos).
        
        // We want angle closest to 180 (opposite Kerbin)
        IF angle > bestAngle {
            SET bestAngle TO angle.
            SET bestTime TO t.
        }
    }
    
    // Fine-tune around best time
    LOCAL fineStart IS bestTime - scanStep.
    LOCAL fineEnd IS bestTime + scanStep.
    LOCAL fineStep IS scanStep / 10.
    
    FROM {LOCAL t IS fineStart.} UNTIL t > fineEnd STEP {SET t TO t + fineStep.} DO {
        LOCAL futureTime IS TIME:SECONDS + t.
        LOCAL shipPos IS POSITIONAT(SHIP, futureTime) - MUN:POSITION.
        LOCAL kerbinPos IS KERBIN:POSITION - MUN:POSITION.
        LOCAL angle IS VANG(shipPos, kerbinPos).
        
        IF angle > bestAngle {
            SET bestAngle TO angle.
            SET bestTime TO t.
        }
    }
    
    LOCAL timeToAntiKerbin IS bestTime.
    
    PRINT "BURN POSITION:".
    PRINT "  Ship-Mun-Kerbin angle: " + ROUND(bestAngle, 1) + " deg".
    PRINT "  Time to burn pos:      " + UTL_FMTETA(TIME:SECONDS + timeToAntiKerbin).
    PRINT " ".
    
    PRINT "═════════════════════════════════════════════════".
    PRINT " ".
    
    // === NODE CHECK ===
    IF HASNODE {
        LOCAL nd IS NEXTNODE.
        
        PRINT "EXISTING NODE:".
        PRINT "  Node ETA:    " + UTL_FMTETA(TIME:SECONDS + nd:ETA).
        PRINT "  Delta-V:     " + ROUND(nd:DELTAV:MAG, 1) + " m/s".
        PRINT "    Prograde:  " + ROUND(nd:PROGRADE, 1) + " m/s".
        PRINT "    Normal:    " + ROUND(nd:NORMAL, 1) + " m/s".
        PRINT "    Radial:    " + ROUND(nd:RADIALOUT, 1) + " m/s".
        PRINT " ".
        
        // Check trajectory
        LOCAL postOrbit IS nd:ORBIT.
        IF postOrbit:HASNEXTPATCH {
            LOCAL nextBody IS postOrbit:NEXTPATCH:BODY:NAME.
            IF nextBody = "Kerbin" {
                LOCAL kerbinOrbit IS postOrbit:NEXTPATCH.
                PRINT "KERBIN TRAJECTORY:".
                PRINT "  Apoapsis:    " + UTL_FMTDIST(kerbinOrbit:APOAPSIS).
                PRINT "  Periapsis:   " + UTL_FMTDIST(kerbinOrbit:PERIAPSIS).
                PRINT " ".
                
                IF kerbinOrbit:PERIAPSIS < 70000 {
                    PRINT "*** WARNING: Direct reentry ***".
                    PRINT "Reduce prograde for MCC capability.".
                } ELSE IF kerbinOrbit:PERIAPSIS > 200000 {
                    PRINT "Good high orbit for MCC.".
                } ELSE {
                    PRINT "Acceptable orbit for MCC.".
                }
            } ELSE {
                PRINT "Escapes to: " + nextBody.
            }
        } ELSE {
            PRINT "*** NO ESCAPE - add prograde ***".
        }
        
        PRINT " ".
        PRINT "(E) Execute   (D) Delete Node   (X) Exit".
        
    } ELSE {
        PRINT "Creating escape node at anti-Kerbin...".
        PRINT " ".
        
        // Burn time at anti-Kerbin position
        LOCAL burnTime IS TIME:SECONDS + timeToAntiKerbin.
        
        // Start with ~200 m/s prograde (minimal escape)
        LOCAL proDV IS 200.
        LOCAL normDV IS 0.
        LOCAL radDV IS 0.
        
        // Create test node
        LOCAL escapeNode IS NODE(burnTime, radDV, normDV, proDV).
        ADD escapeNode.
        
        // Iterate to find good escape trajectory
        LOCAL attempts IS 0.
        LOCAL escapeOK IS FALSE.
        
        UNTIL escapeOK OR attempts > 30 {
            SET attempts TO attempts + 1.
            WAIT 0.1.
            
            IF escapeNode:ORBIT:HASNEXTPATCH {
                LOCAL nextBody IS escapeNode:ORBIT:NEXTPATCH:BODY:NAME.
                IF nextBody = "Kerbin" {
                    LOCAL kPe IS escapeNode:ORBIT:NEXTPATCH:PERIAPSIS.
                    
                    IF kPe > 100000 {
                        SET escapeOK TO TRUE.
                    } ELSE IF kPe < 70000 {
                        // Direct reentry - reduce prograde
                        SET proDV TO proDV - 5.
                        SET escapeNode:PROGRADE TO proDV.
                    } ELSE {
                        // Marginal but acceptable
                        SET escapeOK TO TRUE.
                    }
                } ELSE {
                    // Escaping to wrong body
                    SET proDV TO proDV - 10.
                    SET escapeNode:PROGRADE TO proDV.
                }
            } ELSE {
                // No escape - add prograde
                SET proDV TO proDV + 10.
                SET escapeNode:PROGRADE TO proDV.
            }
        }
        
        IF escapeOK {
            LOCAL kerbinOrbit IS escapeNode:ORBIT:NEXTPATCH.
            PRINT "ESCAPE NODE CREATED:".
            PRINT "  Burn time:   " + UTL_FMTETA(TIME:SECONDS + escapeNode:ETA).
            PRINT "  Delta-V:     " + ROUND(proDV, 1) + " m/s prograde".
            PRINT " ".
            PRINT "KERBIN TRAJECTORY:".
            PRINT "  Apoapsis:    " + UTL_FMTDIST(kerbinOrbit:APOAPSIS).
            PRINT "  Periapsis:   " + UTL_FMTDIST(kerbinOrbit:PERIAPSIS).
        } ELSE {
            PRINT "*** Could not create valid escape ***".
            PRINT "Manually adjust node.".
        }
        
        PRINT " ".
        PRINT "(E) Execute   (D) Delete Node   (X) Exit".
    }
    
    // === INPUT LOOP ===
    LOCAL running IS TRUE.
    UNTIL NOT running {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
            IF ch = "E" AND HASNODE {
                EXECUTE_NODE(TRUE, 7).
                SET running TO FALSE.
            } ELSE IF ch = "D" AND HASNODE {
                REMOVE NEXTNODE.
                PRINT "Node deleted.".
                WAIT 1.
                SET running TO FALSE.
            } ELSE IF ch = "X" {
                SET running TO FALSE.
            }
        }
        WAIT 0.1.
    }
    
    PRINT " ".
    PRINT "TKI complete. Run MCC after SOI change.".
}

MAIN().