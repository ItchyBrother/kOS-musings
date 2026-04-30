// =================================================================
// Stage 4+: Smart Deorbit with Target-Selection Menu
// Automatically refines retro/radial/normal/time and applies Δv & time offsets
// =================================================================
// Version 1.1 Change MAX_RETRO_DV and targ_adj as optional parameters.
// Version 2.0 Need to work on parachute, etc.. stuff.  See deorbit function. Add two functions HAS_CUT_EVENT & WATCH_CHUTES
// Version 2.1 Added toggle_stage for retro burn.  By default it is false.
PARAMETER MAX_RETRO_DV  IS 160.0.    // retro Δv cap (m/s)
PARAMETER targ_adj      IS -20.      // This adjusts the target.  Positive moves it EAST, Negative moves it WEST. // km; +→prograde, –→retrograde
PARAMETER toggle_stage  IS FALSE.    // If you need to STAGE to toggle the retro burn, set to TRUE.
PARAMETER agNum        IS 10.       // If toggle_stage is FALSE, this it the ACTION GROUP number that toggles the ENGINE ON/OFF.

// --- CONFIGURATION (no CSV logging) ---
SET ENTRY_ALT           TO 30000.    // periapsis (m)
SET MAX_AXIS_DV         TO 100.0.    // radial/normal Δv cap (m/s)
SET MAX_TIME_SHIFT      TO 600.0.    // node‑time shift cap (s)
SET DIST_TOL            TO 1.0.      // stop when error ≤ 1 km
SET MAX_PASSES          TO 5.        // maximum refinement passes

SET RETRO_TOL TO 0.01.
SET RAD_TOL   TO 0.01.
SET NORM_TOL  TO 0.01.
SET DT_TOL    TO 0.1.

LOCAL phi IS (SQRT(5) - 1) / 2.

// --- UTILITIES ---
FUNCTION clearNodes {
    FOR n IN ALLNODES { REMOVE n. }.
}.

FUNCTION calcBearing {
  // returns heading (° from north) from (lat1,lon1) → (lat2,lon2)
  PARAMETER lat1, lon1, lat2, lon2.

  LOCAL phi1    IS lat1 * CONSTANT:DegToRad.
  LOCAL phi2    IS lat2 * CONSTANT:DegToRad.
  LOCAL dlon    IS (lon2 - lon1) * CONSTANT:DegToRad.

  LOCAL x       IS SIN(dlon) * COS(phi2).
  LOCAL y       IS COS(phi1) * SIN(phi2)
                   - SIN(phi1) * COS(phi2) * COS(dlon).

  LOCAL theta   IS ARCTAN2(x, y).                                    // radians
  LOCAL bearing IS MOD(theta * CONSTANT:RadToDeg + 360, 360).

  IF bearing < 0 {
    SET bearing TO bearing + 360.
  }

  RETURN bearing.
}.

FUNCTION calcDistance {
    // PARAMETER a, b.
    // LOCAL dLat IS a:LAT - b:LAT.
    // LOCAL dLng IS a:LNG - b:LNG.
    // IF dLng > 180  { SET dLng TO dLng - 360. }.
    // IF dLng < -180 { SET dLng TO dLng + 360. }.
    // RETURN SQRT(dLat^2 + (dLng * COS(b:LAT * CONSTANT:DegToRad))^2) * 111.
        PARAMETER a, b.

    // redeclare myRad locally for this function
    LOCAL myRad     IS BODY:RADIUS.
    LOCAL lat1Rad   IS a:LAT * CONSTANT:DegToRad.
    LOCAL lat2Rad   IS b:LAT * CONSTANT:DegToRad.
    LOCAL dLat      IS (b:LAT - a:LAT) * CONSTANT:DegToRad.
    LOCAL dLonRaw   IS (b:LNG - a:LNG) * CONSTANT:DegToRad.
    LOCAL dLon      IS dLonRaw.

    IF dLonRaw > CONSTANT:PI {
      SET dLon TO dLonRaw - 2 * CONSTANT:PI.
    } ELSE IF dLonRaw < -CONSTANT:PI {
      SET dLon TO dLonRaw + 2 * CONSTANT:PI.
    }.

    LOCAL hav      IS SIN(dLat/2)^2
                    + COS(lat1Rad)*COS(lat2Rad)*(SIN(dLon/2)^2).
    LOCAL distM    IS 2 * myRad * ARCSIN(SQRT(hav)).  // meters

    RETURN distM / 1000.  // km
}.

FUNCTION findNodeTime {
    LOCAL period IS SHIP:ORBIT:PERIOD.
    LOCAL now    IS TIME:SECONDS.
    LOCAL step   IS period / 600.
    LOCAL bestT  IS now.
    LOCAL bestA  IS 360.
    FROM { SET t TO now. }
    UNTIL t > now + period + 1
    STEP { SET t TO t + step. }
    DO {
        LOCAL pos IS POSITIONAT(SHIP, t).
        LOCAL geo IS BODY:GEOPOSITIONOF(pos).
        LOCAL raw IS MOD(geo:LNG - TARGET_LNG + 360, 360).
        LOCAL dA  IS ABS(raw - 270).
        IF dA < bestA {
            SET bestA TO dA.
            SET bestT TO t.
        }.
    }.
    RETURN bestT.
}.

FUNCTION analyticRetro {
    LOCAL rNow IS SHIP:BODY:POSITION:MAG.
    LOCAL mu   IS BODY:MASS * CONSTANT:G.
    LOCAL rp   IS BODY:RADIUS + ENTRY_ALT.
    LOCAL aNew IS (SHIP:ORBIT:APOAPSIS + rp) / 2.
    LOCAL vNow IS SHIP:VELOCITY:ORBIT:MAG.
    LOCAL vNew IS SQRT(mu * (2 / rNow - 1 / aNew)).
    LOCAL dv   IS vNow - vNew.
    RETURN MAX(0, MIN(MAX_RETRO_DV, dv)).
}.

FUNCTION getFullLine {
    LOCAL s IS "".
    UNTIL FALSE {
        IF TERMINAL:INPUT:HASCHAR {
            LOCAL c IS TERMINAL:INPUT:GETCHAR().
            IF c = TERMINAL:INPUT:ENTER {
                BREAK.
            } ELSE IF c = TERMINAL:INPUT:BACKSPACE {
                IF s:LENGTH > 0 {
                    SET s TO LEFT(s, s:LENGTH - 1).
                    PRINT CHR(8) + " " + CHR(8).
                }.
            } ELSE {
                SET s TO s + c.
                PRINT c.
            }.
        }.
        WAIT 0.01.
    }.
    PRINT "".
    RETURN s.
}.

FUNCTION parseAngle {
    PARAMETER s.
    LOCAL parts IS s:SPLIT(" ").
    IF parts:LENGTH = 3 {
        LOCAL d   IS parts[0]:TONUMBER().
        LOCAL m   IS parts[1]:TONUMBER().
        LOCAL sec IS parts[2]:TONUMBER().
        LOCAL sign IS 1.
        IF d < 0 { SET sign TO -1. }.
        RETURN sign * (ABS(d) + m/60 + sec/3600).
    } ELSE {
        RETURN s:TONUMBER().
    }.
}.

// evalNode with two‑phase wait to ensure fresh impact
FUNCTION evalNode {
    PARAMETER dvR, dvX, dvN, dt.
    clearNodes().
    ADD NODE(burnTime + dt, dvX, dvN, -dvR).
    ADDONS:TR:SETTARGET(LATLNG(TARGET_LAT, TARGET_LNG)).
    WAIT 0.1.
    UNTIL ADDONS:TR:HASIMPACT {
        WAIT 0.1.
    }.
    LOCAL hitLat IS ADDONS:TR:IMPACTPOS:LAT.
    LOCAL hitLon IS ADDONS:TR:IMPACTPOS:LNG.
    IF SHIP:BODY:ATM:EXISTS {
        SET hitLon TO hitLon - (hitLon - TARGET_LNG) * 0.1.
    }.
    RETURN calcDistance(LATLNG(hitLat, hitLon), LATLNG(TARGET_LAT, TARGET_LNG)).
}.

FUNCTION golden {
    PARAMETER axis, lo, hi, tol.
    LOCAL c  IS hi - phi * (hi - lo).
    LOCAL d  IS lo + phi * (hi - lo).
    LOCAL fC IS 1e9.
    LOCAL fD IS 1e9.
    IF axis = "retro" {
        SET fC TO evalNode(c, bestRad, bestNorm, bestDT).
        SET fD TO evalNode(d, bestRad, bestNorm, bestDT).
    } ELSE IF axis = "radial" {
        SET fC TO evalNode(bestRetro, c, bestNorm, bestDT).
        SET fD TO evalNode(bestRetro, d, bestNorm, bestDT).
    } ELSE IF axis = "normal" {
        SET fC TO evalNode(bestRetro, bestRad, c, bestDT).
        SET fD TO evalNode(bestRetro, bestRad, d, bestDT).
    } ELSE {
        SET fC TO evalNode(bestRetro, bestRad, bestNorm, c).
        SET fD TO evalNode(bestRetro, bestRad, bestNorm, d).
    }.
    LOCAL i IS 0.
    UNTIL (hi - lo) < tol OR i > 40 {
        IF fC < fD {
            SET hi TO d.
            SET d  TO c.
            SET fD TO fC.
            SET c  TO hi - phi * (hi - lo).
            // re-evaluate fC
            IF axis = "retro" {
                SET fC TO evalNode(c, bestRad, bestNorm, bestDT).
            } ELSE IF axis = "radial" {
                SET fC TO evalNode(bestRetro, c, bestNorm, bestDT).
            } ELSE IF axis = "normal" {
                SET fC TO evalNode(bestRetro, bestRad, c, bestDT).
            } ELSE {
                SET fC TO evalNode(bestRetro, bestRad, bestNorm, c).
            }.
        } ELSE {
            SET lo TO c.
            SET c  TO d.
            SET fC TO fD.
            SET d  TO lo + phi * (hi - lo).
            // re-evaluate fD
            IF axis = "retro" {
                SET fD TO evalNode(d, bestRad, bestNorm, bestDT).
            } ELSE IF axis = "radial" {
                SET fD TO evalNode(bestRetro, d, bestNorm, bestDT).
            } ELSE IF axis = "normal" {
                SET fD TO evalNode(bestRetro, bestRad, d, bestDT).
            } ELSE {
                SET fD TO evalNode(bestRetro, bestRad, bestNorm, d).
            }.
        }.
        SET i TO i + 1.
    }.
    IF fC < fD {
        RETURN LIST(c, fC).
    } ELSE {
        RETURN LIST(d, fD).
    }.
}.

FUNCTION findBestOffset {
    PARAMETER lo, hi, tol.
    LOCAL c  IS hi - phi * (hi - lo).
    LOCAL d  IS lo + phi * (hi - lo).
    LOCAL fC IS evalNode(bestRetro + c, bestRad, bestNorm, bestDT).
    LOCAL fD IS evalNode(bestRetro + d, bestRad, bestNorm, bestDT).
    LOCAL i IS 0.
    UNTIL (hi - lo) < tol OR i > 30 {
        IF fC < fD {
            SET hi TO d.
            SET d  TO c.
            SET fD TO fC.
            SET c  TO hi - phi * (hi - lo).
            SET fC TO evalNode(bestRetro + c, bestRad, bestNorm, bestDT).
        } ELSE {
            SET lo TO c.
            SET c  TO d.
            SET fC TO fD.
            SET d  TO lo + phi * (hi - lo).
            SET fD TO evalNode(bestRetro + d, bestRad, bestNorm, bestDT).
        }.
        SET i TO i + 1.
    }.
    IF fC < fD {
        RETURN LIST(c, fC).
    } ELSE {
        RETURN LIST(d, fD).
    }.
}.

FUNCTION ToggleEngine {
    PARAMETER agNum, state IS TRUE.  // state = TRUE for ON, FALSE for OFF
    
    IF agNum = 1 { IF state { AG1 ON. } ELSE { AG1 OFF. } }
    ELSE IF agNum = 2 { IF state { AG2 ON. } ELSE { AG2 OFF. } }
    ELSE IF agNum = 3 { IF state { AG3 ON. } ELSE { AG3 OFF. } }
    ELSE IF agNum = 4 { IF state { AG4 ON. } ELSE { AG4 OFF. } }
    ELSE IF agNum = 5 { IF state { AG5 ON. } ELSE { AG5 OFF. } }
    ELSE IF agNum = 6 { IF state { AG6 ON. } ELSE { AG6 OFF. } }
    ELSE IF agNum = 7 { IF state { AG7 ON. } ELSE { AG7 OFF. } }
    ELSE IF agNum = 8 { IF state { AG8 ON. } ELSE { AG8 OFF. } }
    ELSE IF agNum = 9 { IF state { AG9 ON. } ELSE { AG9 OFF. } }
    ELSE IF agNum = 10 { IF state { AG10 ON. } ELSE { AG10 OFF. } }
}

// --- UTIL: Shift a lat/lon by distKm kilometers along a given bearing (deg) ---
FUNCTION ShiftPoint {
    PARAMETER lat0, lon0, distKm, bearingDeg.

    // Planet radius (m)
    LOCAL myRad       IS BODY:RADIUS.
    // Angular distance (rad)
    LOCAL angDist     IS (distKm * 1000) / myRad.
    // Bearing in radians
    LOCAL bearingRad  IS bearingDeg * CONSTANT:DegToRad.
    // Origin in radians
    LOCAL latRad1     IS lat0 * CONSTANT:DegToRad.
    LOCAL lonRad1     IS lon0 * CONSTANT:DegToRad.

    // Destination latitude (rad)
    LOCAL latRad2     IS ARCSIN(
                           SIN(latRad1) * COS(angDist)
                         + COS(latRad1) * SIN(angDist) * COS(bearingRad)
                       ).
    // Destination longitude (rad)
    LOCAL lonRad2     IS lonRad1
                       + ARCTAN2(
                           SIN(bearingRad) * SIN(angDist) * COS(latRad1),
                           COS(angDist) - SIN(latRad1) * SIN(latRad2)
                         ).

    // Convert back to degrees
    LOCAL outLat      IS latRad2 * CONSTANT:RadToDeg.
    LOCAL outLon      IS lonRad2 * CONSTANT:RadToDeg.

    RETURN LIST(outLat, outLon).
}.

FUNCTION StageWithRetry {
    PARAMETER maxRetries IS 5.
    
    LOCAL partCountBefore IS SHIP:PARTS:LENGTH.
    LOCAL attempts IS 0.
    
    UNTIL SHIP:PARTS:LENGTH < partCountBefore OR attempts >= maxRetries {
        STAGE.
        WAIT 0.5.
        SET attempts TO attempts + 1.
    }
    
    RETURN SHIP:PARTS:LENGTH < partCountBefore.
}

FUNCTION PodRCS {
    LOCAL enabled IS 0.
    
    // Step 1: Toggle RCS on all command pods
    FOR p IN SHIP:PARTS {
        IF p:HASMODULE("ModuleCommand") {
            IF p:HASMODULE("ModuleRCS") OR p:HASMODULE("ModuleRCSFX") {
                LOCAL moduleName IS "ModuleRCS".
                IF p:HASMODULE("ModuleRCSFX") { SET moduleName TO "ModuleRCSFX". }
                
                LOCAL rcsModule IS p:GETMODULE(moduleName).
                
                IF rcsModule:ALLACTIONNAMES:CONTAINS("Toggle RCS Thrust") {
                    rcsModule:DOACTION("Toggle RCS Thrust", TRUE).
                    PRINT "Toggled RCS on: " + p:TITLE.
                    SET enabled TO enabled + 1.
                }
            }
        }
    }
    
    IF enabled = 0 {
        PRINT "No command pod RCS found.".
        RETURN FALSE.
    }
    
    // Step 2: Verify RCS is actually on by testing it
    PRINT "Verifying RCS is active...".
    
    LOCAL monoBefore IS SHIP:MONOPROPELLANT.
    PRINT "MonoProp before test: " + ROUND(monoBefore, 2).
    
    // Enable global RCS and fire a brief roll
    RCS ON.
    WAIT 0.1.
    
    SET SHIP:CONTROL:ROLL TO 0.3.  // Gentle roll
    WAIT 0.5.  // Fire for half a second
    SET SHIP:CONTROL:ROLL TO 0.
    
    WAIT 0.5.  // Let it settle
    
    LOCAL monoAfter IS SHIP:MONOPROPELLANT.
    PRINT "MonoProp after test: " + ROUND(monoAfter, 2).
    
    LOCAL monoUsed IS monoBefore - monoAfter.
    
    IF monoUsed > 0.01 {
        PRINT "RCS VERIFIED ACTIVE - used " + ROUND(monoUsed, 3) + " units.".
        RETURN TRUE.
    } ELSE {
        PRINT "RCS NOT ACTIVE - no monoprop consumed!".
        PRINT "Toggling again...".
        
        // Toggle again (maybe we turned it off by accident)
        FOR p IN SHIP:PARTS {
            IF p:HASMODULE("ModuleCommand") {
                IF p:HASMODULE("ModuleRCS") OR p:HASMODULE("ModuleRCSFX") {
                    LOCAL moduleName IS "ModuleRCS".
                    IF p:HASMODULE("ModuleRCSFX") { SET moduleName TO "ModuleRCSFX". }
                    
                    LOCAL rcsModule IS p:GETMODULE(moduleName).
                    IF rcsModule:ALLACTIONNAMES:CONTAINS("Toggle RCS Thrust") {
                        rcsModule:DOACTION("Toggle RCS Thrust", TRUE).
                    }
                }
            }
        }
        
        // Test again
        SET monoBefore TO SHIP:MONOPROPELLANT.
        SET SHIP:CONTROL:ROLL TO 0.3.
        WAIT 0.5.
        SET SHIP:CONTROL:ROLL TO 0.
        WAIT 0.5.
        SET monoAfter TO SHIP:MONOPROPELLANT.
        SET monoUsed TO monoBefore - monoAfter.
        
        IF monoUsed > 0.01 {
            PRINT "RCS NOW ACTIVE after second toggle - used " + ROUND(monoUsed, 3) + " units.".
            RETURN TRUE.
        } ELSE {
            PRINT "RCS STILL NOT ACTIVE - may not have monoprop or RCS thrusters.".
            RETURN FALSE.
        }
    }
}

// Arms all parachutes (makes them wait for deployment conditions)
FUNCTION ARM_CHUTES {
  PARAMETER drogueWord IS "Drogue".
  PARAMETER mainWord IS "Main".
  
  LOCAL droguesArmed IS 0.
  LOCAL mainsArmed IS 0.
  
  LIST PARTS IN parts.
  FOR p IN parts {
    IF p:HASMODULE("ModuleParachute") {
      LOCAL m IS p:GETMODULE("ModuleParachute").
      LOCAL title IS p:TITLE.
      
      // Check if chute needs arming (look for "Deploy" or "Arm" events)
      IF m:HASEVENT("Deploy Chute") OR m:HASEVENT("Arm Parachute") OR m:HASEVENT("Deploy") {
        
        // Arm it
        IF m:HASEVENT("Deploy Chute") {
          m:DOEVENT("Deploy Chute").
        } ELSE IF m:HASEVENT("Arm Parachute") {
          m:DOEVENT("Arm Parachute").
        } ELSE IF m:HASEVENT("Deploy") {
          m:DOEVENT("Deploy").
        }
        
        IF title:FIND(drogueWord) >= 0 {
          PRINT "Armed drogue: " + title.
          SET droguesArmed TO droguesArmed + 1.
        } ELSE IF title:FIND(mainWord) >= 0 {
          PRINT "Armed main: " + title.
          SET mainsArmed TO mainsArmed + 1.
        }
      }
    } ELSE IF p:HASMODULE("RealChuteModule") {
      LOCAL m IS p:GETMODULE("RealChuteModule").
      LOCAL title IS p:TITLE.
      
      // RealChute uses different events
      IF m:HASEVENT("Deploy chute") OR m:HASEVENT("Arm parachute") {
        IF m:HASEVENT("Deploy chute") {
          m:DOEVENT("Deploy chute").
        } ELSE IF m:HASEVENT("Arm parachute") {
          m:DOEVENT("Arm parachute").
        }
        
        IF title:FIND(drogueWord) >= 0 {
          PRINT "Armed drogue (RealChute): " + title.
          SET droguesArmed TO droguesArmed + 1.
        } ELSE IF title:FIND(mainWord) >= 0 {
          PRINT "Armed main (RealChute): " + title.
          SET mainsArmed TO mainsArmed + 1.
        }
      }
    }
  }
  
  PRINT "Total armed: " + droguesArmed + " drogues, " + mainsArmed + " mains.".
}

// Returns TRUE once a chute is actually out (semi/full) because "Cut" becomes available.
FUNCTION HAS_CUT_EVENT {
  PARAMETER m.
  RETURN m:HASEVENT("Cut Parachute") OR m:HASEVENT("Cut Chute") OR m:HASEVENT("Cut").
}

FUNCTION WATCH_CHUTES {
  PARAMETER drogueWord IS "Drogue".
  PARAMETER mainWord   IS "Main".

  LOCAL drogues IS LIST().
  LOCAL mains   IS LIST().

  LIST PARTS IN parts.
  FOR p IN parts {
    IF p:HASMODULE("ModuleParachute") {
      LOCAL m IS p:GETMODULE("ModuleParachute").
      LOCAL title IS p:TITLE.
      IF title:FIND(drogueWord) >= 0 {
        drogues:ADD(m).
      } ELSE IF title:FIND(mainWord) >= 0 {
        mains:ADD(m).
      } ELSE {
        mains:ADD(m).
      }
    } ELSE IF p:HASMODULE("RealChuteModule") {
      LOCAL m IS p:GETMODULE("RealChuteModule").
      LOCAL title IS p:TITLE.
      IF title:FIND(drogueWord) >= 0 {
        drogues:ADD(m).
      } ELSE IF title:FIND(mainWord) >= 0 {
        mains:ADD(m).
      } ELSE {
        mains:ADD(m).
      }
    }
  }

  IF drogues:LENGTH = 0 { PRINT "WATCH_CHUTES: no drogues found ('" + drogueWord + "').". }
  IF mains:LENGTH   = 0 { PRINT "WATCH_CHUTES: no mains found ('" + mainWord + "').". }

  // 1) Print once when any drogue deploys (Cut event appears)
  LOCAL drogueAnnounced IS FALSE.
  UNTIL drogueAnnounced OR drogues:LENGTH = 0 {
    FOR d IN drogues {
      IF HAS_CUT_EVENT(d) {
        PRINT "Drogue deployed on " + d:PART:TITLE + ".".
        SET drogueAnnounced TO TRUE.
        BREAK.
      }
    }
    WAIT 0.1.
  }

  // 2) When any main deploys, pulse AG1 to cut drogues and print once
  LOCAL mainHandled IS FALSE.
  UNTIL mainHandled OR mains:LENGTH = 0 {
    FOR m IN mains {
      IF HAS_CUT_EVENT(m) {
        PRINT "Main deployed on " + m:PART:TITLE + " — cutting drogue(s).".
        FOR d IN drogues {
          IF HAS_CUT_EVENT(d) {d:DOEVENT("Cut Parachute").}
        }
        SET mainHandled TO TRUE.
        BREAK.
      }
    }
    WAIT 0.1.
  }
}

FUNCTION deorbit {
    // === PREPARE ===
    LOCAL mnode        IS ALLNODES[0].
    LOCAL alignLead    IS 90.    // sec before burn to cancel warp & align
    LOCAL burnAbs      IS burnTime + bestDT + dtOffset.

    // 1) cancel timewarp
    WAIT UNTIL TIME:SECONDS >= (burnAbs - alignLead).
    SET WARP TO 0.
    WAIT 1.

    // 2) RCS‑only alignment to burn vector
    PRINT "RCS on, SAS off — aligning to burn vector...".
    RCS ON.
    SAS OFF.
    LOCK STEERING TO mnode:BURNVECTOR.
    UNTIL VANG(SHIP:FACING:VECTOR, mnode:BURNVECTOR) < 0.5 {
        WAIT 0.1.
    }
    PRINT "— aligned.".

    // 3) stage retro pack
    // Added a variable to test for retropack or not.
    IF toggle_stage{
        WAIT 10.
        PRINT "Retropack Activated.".
        STAGE.
    } ELSE {
        ToggleEngine(agNum, TRUE).
        PRINT "Engine Activated for reentry.".
    }    

    // 4) Calculations & Wait until start of deorbit burn.

    // Looking at each engine and summing up vacuum-ISP.
    LIST ENGINES IN myEngines.                   // Getting all the engine parts.
    LOCAL sumISP    IS 0.
    LOCAL cnt       IS 0.
    FOR eng IN myEngines {
        SET sumISP TO sumISP + eng:VACUUMISP.
        SET cnt TO cnt + 1.
    }.
    IF cnt = 0 {
        PRINT "ERROR: No engines found!".
        RETURN.
    }

    LOCAL dv        IS mnode:DeltaV:MAG.    // m/s
    LOCAL thrustN   IS SHIP:MAXTHRUST.      // kN
    LOCAL isp       IS sumISP / cnt.        // s
    LOCAL mass0     IS SHIP:MASS * 1000.    // kg
    LOCAL g0        IS 9.80665.             // m/s²

    // compute mass flow (kg/s) and turn burn duration (s)
    LOCAL massFlow  IS (thrustN * 1000) / (isp * g0).
    LOCAL burnTime2 IS (mass0 / massFlow) * (1 - (constant:E ^ (-dv / (isp * g0)))).
    
    // half-burn is the time from start midpoint (for ETA comparison)
    LOCAL halfBurn  IS burnTime2 / 2.

    PRINT "Waiting until start of node. ".
    WAIT UNTIL mnode:ETA <= halfBurn.
    
    // // 5) execute burn
    // PRINT "Retro burn...".
    // LOCK THROTTLE TO 1.
    // UNTIL mnode:DeltaV:mag <= 15 {
    //     WAIT 0.1.
    // }
    // // hold current facing to avoid chasing node
    // LOCAL holdVec IS SHIP:FACING:VECTOR.
    // LOCK STEERING TO holdVec.
    // UNTIL mnode:DeltaV:mag <= 1 {
    //     WAIT 0.1.
    // }
    // LOCK THROTTLE TO 0.
    // PRINT "Burn complete.".
    // clearNodes().
    // IF NOT toggle_stage{
    //     ToggleEngine(agNum, FALSE).
    //     PRINT "Engine shutdown/Deactivated.".
    // }

    // 5) execute burn with throttle control to prevent overshoot
    PRINT "Retro burn starting...".

    // Calculate initial values
    LOCAL maxAccel IS SHIP:MAXTHRUST / SHIP:MASS.
    LOCAL burnTimeRemaining IS mnode:DELTAV:MAG / maxAccel.

    PRINT "Estimated burn time: " + ROUND(burnTimeRemaining, 1) + "s".

    // Phase 1: Full throttle until getting close
    LOCK THROTTLE TO 1.
    UNTIL mnode:DELTAV:MAG <= 50 {
        PRINT "Remaining dV: " + ROUND(mnode:DELTAV:MAG, 1) + " m/s    " AT (0, 20).
        WAIT 0.1.
    }

    // Phase 2: Reduce throttle as we approach target
    PRINT "Throttling down for precision...".
    UNTIL mnode:DELTAV:MAG <= 15 {
        // Throttle proportional to remaining dV (min 0.3 to avoid flame-out)
        LOCAL targetThrottle IS MAX(0.3, mnode:DELTAV:MAG / 50).
        LOCK THROTTLE TO targetThrottle.
        PRINT "Remaining dV: " + ROUND(mnode:DELTAV:MAG, 1) + " m/s  Throttle: " + ROUND(targetThrottle * 100) + "%    " AT (0, 20).
        WAIT 0.05.
    }

    // Phase 3: Hold current facing to avoid chasing the node
    PRINT "Final approach - holding attitude...".
    LOCAL holdVec IS SHIP:FACING:VECTOR.
    LOCK STEERING TO holdVec.

    // Very low throttle for final approach
    UNTIL mnode:DELTAV:MAG <= 2 {
        LOCAL currentAccel IS SHIP:AVAILABLETHRUST / SHIP:MASS.
        LOCAL stoppingDistance IS mnode:DELTAV:MAG.
        
        // Calculate safe throttle (accounts for engine response time)
        LOCAL safeThrottle IS MIN(0.2, stoppingDistance / 10).
        LOCK THROTTLE TO MAX(0.05, safeThrottle).
        
        PRINT "Remaining dV: " + ROUND(mnode:DELTAV:MAG, 2) + " m/s    " AT (0, 20).
        WAIT 0.05.
    }

    // Cut throttle
    LOCK THROTTLE TO 0.
    PRINT "Burn complete. Final error: " + ROUND(mnode:DELTAV:MAG, 2) + " m/s".
    clearNodes().

    IF NOT toggle_stage {
        ToggleEngine(agNum, FALSE).
        PRINT "Engine shutdown/Deactivated.".
    }
    WAIT 30.

    // 6) re‑align to surface normal (+normal)
    PRINT "Re‑aligning to surface normal...".
    LOCK STEERING TO VCRS(SHIP:VELOCITY:ORBIT, BODY:POSITION).
    UNTIL VANG(
        SHIP:FACING:VECTOR,
        VCRS(SHIP:VELOCITY:ORBIT, BODY:POSITION)
    ) < 0.5 {
        WAIT 0.1.
    }
    PRINT "— aligned; holding 5 s.".
    WAIT 5.
    IF toggle_stage{
        PRINT "Jettisoning retro pack...".
    } ELSE {
        PRINT "Jettisoning Service Module....".
        IF NOT StageWithRetry(3) {
            PRINT "CRITICAL FAILURE!".  
            PRINT "Staging has failed. Handing over manual control.".
            REBOOT.
        }
    }
    PodRCS().  //Check all command pods and enables RCS.
    RCS ON.
    WAIT 10.

    // 7) align to surface‑retro
    PRINT "Aligning to surface‑retrograde...".
    LOCK STEERING TO RETROGRADE.

    // 8) cut RCS & steering at 40 km
    WAIT UNTIL SHIP:ALTITUDE <= 40000.
    PRINT "≤40 km — RCS & steering OFF.".
    RCS OFF.
    UNLOCK STEERING.

    // 9) Chute deployment
    WAIT UNTIL SHIP:ALTITUDE <= 15000.
    STAGE.  // ARMS CHUTES. If there is a cover, this eject it at this time to expose chutes.
    // WATCH_CHUTES function will watch deployment as set in VAB.
    ARM_CHUTES("Drogue", "Main").
    WATCH_CHUTES().

    // 10) splashdown report 
    WAIT UNTIL SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED".
    LOCAL curLat IS SHIP:LATITUDE.
    LOCAL curLon IS SHIP:LONGITUDE.
    LOCAL landErr IS calcDistance(
        LATLNG(curLat, curLon),
        LATLNG(Org_TARGET_LAT, Org_TARGET_LNG)
    ).

    LOCAL bearing IS calcBearing(
    curLat, curLon,
    Org_TARGET_LAT, Org_TARGET_LNG
    ).

    PRINT "Splash at " 
        + ROUND(curLAT,6) + "°, " 
        + ROUND(curLon,6) + "°".
    PRINT "Dist to Target: " + ROUND(landErr,3) + " km".
    PRINT "Dir to Target:  " + ROUND(bearing,1) + "°".
    WAIT 10.
    
    // 11) shutdown
    PRINT "Deorbit sequence complete. Shutting down kOS.".
    SHUTDOWN.
}

// --- MAIN SCRIPT ---
CLEARSCREEN.
PRINT "=== Stage 4+: Smart Deorbit ===".
PRINT "The following parameters are being used:". PRINT " ".
PRINT "Max DeltaV to use: " + MAX_RETRO_DV.
PRINT "Target Adjust: " + targ_adj. 
PRINT "Toggle Stage: " + toggle_stage.
PRINT "AG to Stage: " + agNum.
PRINT "If any of these are off, press CTRL+C to cancel and start over.".
PRINT "Format is 'run deorbit(max_retro, target_adj, toggle_stage[DEFAULT FALSE], AG[DEFAULT IS 10.]).".
PRINT "When ready to proceed, press any key...".
SET dummy TO TERMINAL:INPUT:GETCHAR().
WAIT 1.
UNSET dummy.
CLEARSCREEN.
PRINT "=== Stage 4+: Smart Deorbit ===".
RCS ON.
SAS OFF.
LOCK STEERING TO RETROGRADE.
// Target selection
LOCAL selStr     IS "".
LOCAL choice     IS 0.
LOCAL TARGET_LAT IS 0.
LOCAL TARGET_LNG IS 0.
LOCAL Org_TARGET_LAT IS 0.
LOCAL Org_TARGET_LNG IS 0. 

PRINT " 1) KSC (lat -0.0972, lon -74.5577)".
PRINT " 2) Island Airfield (lat -1.5233, lon -71.9111)".
PRINT " 3) Custom…".

UNTIL choice = 1 OR choice = 2 OR choice = 3 {
    PRINT "Enter 1, 2, or 3:".
    SET selStr TO TERMINAL:INPUT:GETCHAR().
    IF selStr = "1" OR selStr = "2" OR selStr = "3" {
        SET choice TO selStr:TONUMBER().
    } ELSE {
        PRINT "Invalid; enter 1, 2, 3.".
        WAIT 1.
    }.
}

IF choice = 1 {
    SET TARGET_LAT TO -0.0972.
    SET TARGET_LNG TO -74.5577.
    SET Org_TARGET_LAT TO TARGET_LAT.
    SET Org_TARGET_LNG TO TARGET_LNG.
} ELSE IF choice = 2 {
    SET TARGET_LAT TO -1.5233.
    SET TARGET_LNG TO -71.9111.
    SET Org_TARGET_LAT TO TARGET_LAT.
    SET Org_TARGET_LNG TO TARGET_LNG.
} ELSE {
    PRINT "Enter latitude (deg/min/sec or decimal):".
    SET TARGET_LAT TO parseAngle(getFullLine()).
    PRINT "Enter longitude (deg/min/sec or decimal):".
    SET TARGET_LNG TO parseAngle(getFullLine()).
    PRINT "Target: " + ROUND(TARGET_LAT,5) + "°, " + ROUND(TARGET_LNG,5).
    SET Org_TARGET_LAT TO TARGET_LAT.
    SET Org_TARGET_LNG TO TARGET_LNG.
}

IF NOT ADDONS:TR:AVAILABLE {
    PRINT "ERROR: Trajectories mod missing!".
    WAIT UNTIL FALSE.
}

//COMPUTING GROUND TRACK

// Get the surface‐frame velocity vector
LOCAL surfVel    IS SHIP:VELOCITY:SURFACE.

// East (X) and north (Y) components
LOCAL vx         IS surfVel:X.
LOCAL vy         IS surfVel:Y.

// Compute bearing from north, clockwise:
//   ARCTAN2(y, x) gives angle from +X‑axis (east).
//   Swapping passes (vx, vy) yields angle from +Y (north).
LOCAL trackAzRad IS ARCTAN2(vx, vy).
LOCAL trackAzDeg IS trackAzRad * CONSTANT:RadToDeg.

// Normalize to 0–360°
IF trackAzDeg < 0 {
    SET trackAzDeg TO trackAzDeg + 360.
}

// Shift the target along that bearing by targ_adj km
LOCAL tmp IS ShiftPoint(TARGET_LAT, TARGET_LNG, targ_adj, trackAzDeg).
SET TARGET_LAT TO tmp[0].
SET TARGET_LNG TO tmp[1].

// END OF COMPUTING GROUND TRACK

ADDONS:TR:SETTARGET(LATLNG(TARGET_LAT, TARGET_LNG)).

// Initial node guess
SET burnTime  TO findNodeTime().
SET bestRetro TO analyticRetro().
clearNodes().
ADD NODE(burnTime, 0, 0, -bestRetro).
ADDONS:TR:SETTARGET(LATLNG(TARGET_LAT, TARGET_LNG)).
WAIT 0.1.
UNTIL ADDONS:TR:HASIMPACT { WAIT 0.1. }.

SET bestDist TO evalNode(bestRetro, 0, 0, 0).
PRINT "Initial err=" + ROUND(bestDist,3) + " km".

LOCAL bestRad  IS 0.
LOCAL bestNorm IS 0.
LOCAL bestDT   IS 0.

FROM { SET pass TO 1. }
UNTIL pass > MAX_PASSES OR bestDist <= DIST_TOL
STEP { SET pass TO pass + 1. }
DO {
    IF bestDist <= DIST_TOL { BREAK. }.
    PRINT "".
    PRINT "Pass " + pass + " (err=" + ROUND(bestDist,3) + " km)".

    LOCAL rRes IS golden("retro",
                        MAX(0, bestRetro - 20),
                        MIN(MAX_RETRO_DV, bestRetro + 20),
                        RETRO_TOL).
    SET bestRetro TO rRes[0].
    SET bestDist  TO rRes[1].
    PRINT "Retro:  " + ROUND(bestRetro,3) + " m/s".

    LOCAL xRes IS golden("radial",
                        MAX(-MAX_AXIS_DV, bestRad - 10),
                        MIN(MAX_AXIS_DV, bestRad + 10),
                        RAD_TOL).
    SET bestRad  TO xRes[0].
    SET bestDist TO xRes[1].
    PRINT "Radial: " + ROUND(bestRad,3)   + " m/s".

    LOCAL nRes IS golden("normal",
                        MAX(-MAX_AXIS_DV, bestNorm - 10),
                        MIN(MAX_AXIS_DV, bestNorm + 10),
                        NORM_TOL).
    SET bestNorm TO nRes[0].
    SET bestDist TO nRes[1].
    PRINT "Normal: " + ROUND(bestNorm,3)  + " m/s".

    LOCAL tRes IS golden("time",
                        MAX(-MAX_TIME_SHIFT, bestDT - 60),
                        MIN(MAX_TIME_SHIFT, bestDT + 60),
                        DT_TOL).
    SET bestDT   TO tRes[0].
    SET bestDist TO tRes[1].
    PRINT "Time:   Δt=" + ROUND(bestDT,3) + " s".

    WAIT 0.1.
}.

// Original node
clearNodes().
ADD NODE(burnTime + bestDT, bestRad, bestNorm, -bestRetro).
ADDONS:TR:SETTARGET(LATLNG(TARGET_LAT, TARGET_LNG)).
WAIT 0.1.
UNTIL ADDONS:TR:HASIMPACT { WAIT 0.1. }.

LOCAL finalIP  IS ADDONS:TR:IMPACTPOS.
LOCAL finalErr IS calcDistance(
    LATLNG(finalIP:LAT, finalIP:LNG),
    LATLNG(TARGET_LAT, TARGET_LNG)
).

PRINT "=== BEFORE OFFSET ===".
PRINT "Err=" + ROUND(finalErr,3) + " km".

// Automatic 1‑D search for perfect retro Δv offset
LOCAL offRes    IS findBestOffset(-20, 20, 0.1).
LOCAL bestOffset IS offRes[0].
LOCAL offsetErr  IS offRes[1].
PRINT "Auto‑offset = " + ROUND(bestOffset,2)
    + " m/s; err=" + ROUND(offsetErr,3) + " km".

// Compensated node (Δv offset only)
clearNodes().
ADD NODE(
  burnTime + bestDT,
  bestRad,
  bestNorm,
 -(bestRetro + bestOffset)
).
ADDONS:TR:SETTARGET(LATLNG(TARGET_LAT, TARGET_LNG)).
WAIT 0.1.
UNTIL ADDONS:TR:HASIMPACT { WAIT 0.1. }.

LOCAL adjIP  IS ADDONS:TR:IMPACTPOS.
LOCAL adjErr IS calcDistance(
    LATLNG(adjIP:LAT, adjIP:LNG),
    LATLNG(TARGET_LAT, TARGET_LNG)
).

PRINT "=== AFTER OFFSET ===".
PRINT "Err=" + ROUND(adjErr,3) + " km".

// Along‑track time adjustment to correct east‑west error
LOCAL groundSpeedKmS IS SHIP:VELOCITY:SURFACE:MAG / 1000.
LOCAL dtOffset      IS adjErr / groundSpeedKmS.
PRINT "Applying dtOffset = " + ROUND(dtOffset,3) + " s.".

// Final node with time shift
clearNodes().
ADD NODE(
  burnTime + bestDT + dtOffset,
  bestRad,
  bestNorm,
 -(bestRetro + bestOffset)
).
ADDONS:TR:SETTARGET(LATLNG(TARGET_LAT, TARGET_LNG)).
WAIT 0.1.
UNTIL ADDONS:TR:HASIMPACT { WAIT 0.1. }.

LOCAL finalIP2  IS ADDONS:TR:IMPACTPOS.
LOCAL finalErr2 IS calcDistance(
    LATLNG(finalIP2:LAT, finalIP2:LNG),
    LATLNG(TARGET_LAT, TARGET_LNG)
).

PRINT "=== AFTER TIME ADJUST ===".
PRINT "Err=" + ROUND(finalErr2,3) + " km".

// Final sequence.
deorbit().