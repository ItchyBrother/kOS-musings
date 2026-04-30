@LAZYGLOBAL OFF.

//RUNONCEPATH("0:/lib/utils.ks").

// ═══════════════════════════════════════════════════════
// MCC (MID-COURSE CORRECTION) - LANDING TARGETING
// Uses Trajectories mod for accurate impact prediction
// ═══════════════════════════════════════════════════════

FUNCTION EXECUTE_MCC {
    
    // === CONSTANTS ===
    LOCAL KERBIN_ROT IS 21600.
    LOCAL TOLERANCE IS 15.
    
    // === LANDING SITE DATABASE ===
    LOCAL sites IS LIST(
        LEXICON("name", "KSC Atlantic", "lat", 0, "lng", -73),
        LEXICON("name", "Nye Island", "lat", 5.7, "lng", 108.7),
        LEXICON("name", "Sandy Island", "lat", -8.2, "lng", -42.5),
        LEXICON("name", "Hazard Shallows", "lat", -14, "lng", 155.3)
    ).
    
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  MCC - MID-COURSE CORRECTION                   ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    // === SOI CHECK ===
    IF SHIP:BODY:NAME <> "Kerbin" {
        PRINT "*** ERROR: Not in Kerbin SOI ***".
        PRINT "Current SOI: " + SHIP:BODY:NAME.
        PRINT " ".
        IF SHIP:BODY:NAME = "Mun" {
            PRINT "Complete TKI burn first.".
        }
        WAIT 5.
        RETURN.
    }
    
    // === CURRENT STATE ===
    PRINT "CURRENT STATE:".
    PRINT "  SOI:         " + SHIP:BODY:NAME.
    PRINT "  Altitude:    " + UTL_FMTDIST(SHIP:ALTITUDE).
    PRINT "  Velocity:    " + ROUND(SHIP:VELOCITY:ORBIT:MAG, 1) + " m/s".
    PRINT " ".
    
    // === ORBIT INFO ===
    LOCAL peAlt IS SHIP:ORBIT:PERIAPSIS.
    LOCAL peETA IS SHIP:ORBIT:ETA:PERIAPSIS.
    
    PRINT "TRAJECTORY:".
    PRINT "  Periapsis:   " + UTL_FMTDIST(peAlt).
    PRINT "  Time to PE:  " + UTL_FMTETA(TIME:SECONDS + peETA).
    PRINT " ".
    
    // === TRAJECTORIES CHECK ===
    LOCAL hasTraj IS FALSE.
    LOCAL impactLat IS 0.
    LOCAL impactLng IS 0.
    
    IF ADDONS:TR:AVAILABLE {
        SET hasTraj TO TRUE.
        IF ADDONS:TR:HASIMPACT {
            LOCAL impactPos IS ADDONS:TR:IMPACTPOS.
            SET impactLat TO impactPos:LAT.
            SET impactLng TO impactPos:LNG.
            
            PRINT "TRAJECTORIES IMPACT:".
            PRINT "  Latitude:    " + ROUND(impactLat, 2) + " deg".
            PRINT "  Longitude:   " + ROUND(impactLng, 2) + " deg".
            PRINT " ".
        } ELSE {
            PRINT "TRAJECTORIES: No impact predicted.".
            IF peAlt > 70000 {
                PRINT "(PE above atmosphere)".
            }
            PRINT " ".
        }
    } ELSE {
        PRINT "*** Trajectories mod not available ***".
        PRINT "Using orbital prediction only.".
        PRINT " ".
        
        // Fallback to orbital prediction
        LOCAL peTime IS TIME:SECONDS + peETA.
        LOCAL pePos IS POSITIONAT(SHIP, peTime) - KERBIN:POSITION.
        SET impactLat TO KERBIN:GEOPOSITIONOF(pePos):LAT.
        LOCAL peLng IS KERBIN:GEOPOSITIONOF(pePos):LNG.
        LOCAL rotDeg IS (peETA / KERBIN_ROT) * 360.
        SET impactLng TO peLng + rotDeg.
        UNTIL impactLng <= 180 { SET impactLng TO impactLng - 360. }
        UNTIL impactLng > -180 { SET impactLng TO impactLng + 360. }
        
        PRINT "ESTIMATED LANDING:".
        PRINT "  Latitude:    " + ROUND(impactLat, 2) + " deg".
        PRINT "  Longitude:   " + ROUND(impactLng, 2) + " deg".
        PRINT " ".
    }
    
    // === SITE DISTANCES ===
    PRINT "═════════════════════════════════════════════════".
    PRINT " ".
    PRINT "LANDING SITES:".
    
    LOCAL bestIdx IS 0.
    LOCAL bestError IS 999.
    LOCAL idx IS 1.
    
    FOR site IN sites {
        LOCAL lngErr IS site["lng"] - impactLng.
        IF lngErr > 180 { SET lngErr TO lngErr - 360. }
        IF lngErr < -180 { SET lngErr TO lngErr + 360. }
        
        IF ABS(lngErr) <= TOLERANCE {
            PRINT "  " + idx + ". " + site["name"] + ": " + ROUND(lngErr, 1) + " deg - IN RANGE".
            IF ABS(lngErr) < bestError {
                SET bestError TO ABS(lngErr).
                SET bestIdx TO idx.
            }
        } ELSE {
            PRINT "  " + idx + ". " + site["name"] + ": " + ROUND(lngErr, 1) + " deg".
        }
        SET idx TO idx + 1.
    }
    PRINT " ".
    
    IF bestIdx > 0 {
        PRINT "BEST MATCH: " + sites[bestIdx-1]["name"].
        PRINT "Within tolerance - no correction needed.".
        PRINT " ".
        PRINT "═════════════════════════════════════════════════".
        WAIT 5.
        RETURN.
    }
    
    // === TARGET SELECTION ===
    PRINT "═════════════════════════════════════════════════".
    PRINT " ".
    PRINT "Select target (1-" + sites:LENGTH + ") or (X) Exit: ".
    
    LOCAL choice IS -1.
    LOCAL waiting IS TRUE.
    UNTIL NOT waiting {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL ch IS TERMINAL:INPUT:GETCHAR():TOUPPER().
            IF ch = "X" {
                PRINT "MCC cancelled.".
                WAIT 2.
                RETURN.
            }
            SET choice TO ch:TONUMBER(-1).
            IF choice >= 1 AND choice <= sites:LENGTH {
                SET waiting TO FALSE.
            }
        }
        WAIT 0.1.
    }
    
    LOCAL targetSite IS sites[choice-1].
    LOCAL targetLat IS targetSite["lat"].
    LOCAL targetLng IS targetSite["lng"].
    
    PRINT " ".
    PRINT "TARGET: " + targetSite["name"].
    PRINT "  Target Lat:  " + targetLat + " deg".
    PRINT "  Target Lng:  " + targetLng + " deg".
    PRINT " ".
    
    // === CREATE CORRECTION NODE ===
    PRINT "Creating correction node...".
    
    LOCAL burnTime IS TIME:SECONDS + 120.
    LOCAL proDV IS 0.
    LOCAL normDV IS 0.
    LOCAL radDV IS 0.
    
    // Calculate initial errors
    LOCAL lngErr IS targetLng - impactLng.
    IF lngErr > 180 { SET lngErr TO lngErr - 360. }
    IF lngErr < -180 { SET lngErr TO lngErr + 360. }
    LOCAL latErr IS targetLat - impactLat.
    
    PRINT "  Lng error:   " + ROUND(lngErr, 2) + " deg".
    PRINT "  Lat error:   " + ROUND(latErr, 2) + " deg".
    PRINT " ".
    
    // Create node
    LOCAL corrNode IS NODE(burnTime, radDV, normDV, proDV).
    ADD corrNode.
    
    // === HILL CLIMB OPTIMIZATION ===
    IF hasTraj {
        PRINT "Optimizing with Trajectories...".
        
        // Set Trajectories target
        LOCAL targetGeo IS LATLNG(targetLat, targetLng).
        ADDONS:TR:SETTARGET(targetGeo).
        
        LOCAL stepPro IS 5.
        LOCAL stepNorm IS 2.
        LOCAL bestDist IS 9999.
        LOCAL iterations IS 0.
        LOCAL maxIter IS 50.
        
        UNTIL iterations > maxIter {
            SET iterations TO iterations + 1.
            WAIT 0.1.
            
            IF NOT ADDONS:TR:HASIMPACT {
                // Need to get into atmosphere - add retrograde
                SET corrNode:PROGRADE TO corrNode:PROGRADE - 10.
                WAIT 0.1.
            } ELSE {
                LOCAL impPos IS ADDONS:TR:IMPACTPOS.
                LOCAL curLat IS impPos:LAT.
                LOCAL curLng IS impPos:LNG.
                
                SET lngErr TO targetLng - curLng.
                IF lngErr > 180 { SET lngErr TO lngErr - 360. }
                IF lngErr < -180 { SET lngErr TO lngErr + 360. }
                SET latErr TO targetLat - curLat.
                
                LOCAL dist IS SQRT(lngErr^2 + latErr^2).
                
                IF dist < 1 {
                    PRINT "  Converged! Error: " + ROUND(dist, 2) + " deg".
                    BREAK.
                }
                
                IF dist < bestDist {
                    SET bestDist TO dist.
                    // Reduce step size as we get closer
                    IF dist < 10 {
                        SET stepPro TO 1.
                        SET stepNorm TO 0.5.
                    }
                    IF dist < 5 {
                        SET stepPro TO 0.2.
                        SET stepNorm TO 0.1.
                    }
                }
                
                // Adjust prograde for longitude
                IF ABS(lngErr) > 0.5 {
                    IF lngErr > 0 {
                        SET corrNode:PROGRADE TO corrNode:PROGRADE - stepPro.
                    } ELSE {
                        SET corrNode:PROGRADE TO corrNode:PROGRADE + stepPro.
                    }
                }
                
                // Adjust normal for latitude
                IF ABS(latErr) > 0.5 {
                    IF latErr > 0 {
                        SET corrNode:NORMAL TO corrNode:NORMAL + stepNorm.
                    } ELSE {
                        SET corrNode:NORMAL TO corrNode:NORMAL - stepNorm.
                    }
                }
            }
        }
        
        PRINT "  Iterations:  " + iterations.
    } ELSE {
        // No Trajectories - use rough estimate
        SET corrNode:PROGRADE TO lngErr * -0.5.
        SET corrNode:NORMAL TO latErr * 2.
    }
    
    PRINT " ".
    PRINT "CORRECTION NODE:".
    PRINT "  Delta-V:     " + ROUND(corrNode:DELTAV:MAG, 1) + " m/s".
    PRINT "    Prograde:  " + ROUND(corrNode:PROGRADE, 1) + " m/s".
    PRINT "    Normal:    " + ROUND(corrNode:NORMAL, 1) + " m/s".
    PRINT "    Radial:    " + ROUND(corrNode:RADIALOUT, 1) + " m/s".
    PRINT " ".
    
    IF hasTraj AND ADDONS:TR:HASIMPACT {
        LOCAL finalPos IS ADDONS:TR:IMPACTPOS.
        PRINT "PREDICTED IMPACT:".
        PRINT "  Latitude:    " + ROUND(finalPos:LAT, 2) + " deg".
        PRINT "  Longitude:   " + ROUND(finalPos:LNG, 2) + " deg".
        PRINT " ".
    }
    
    PRINT "═════════════════════════════════════════════════".
    PRINT " ".
    PRINT "(E) Execute   (D) Delete Node   (X) Exit".
    
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
    PRINT "Run MCC again to verify.".

    RETURN.
}