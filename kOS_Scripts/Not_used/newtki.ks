// === TKI (TRANS-KERBIN INJECTION) MISSION PLANNER ===
//DELETEPATH("0:tki_log.txt").
LOG "=== TKI MISSION LOG - " + TIME:CALENDAR + " " + TIME:CLOCK + " ===" TO "0:tki_log.txt".

FUNCTION plog {
    PARAMETER txt.
    PRINT txt.
    LOG txt TO "0:tki_log.txt".
}

// === LANDING SITE DATABASE ===
SET sites TO LIST(
    LEXICON("name", "KSC Atlantic", "lat", 0, "long", -73),
    LEXICON("name", "Nye Island", "lat", 5.7, "long", 108.7),
    LEXICON("name", "Sandy Island", "lat", -8.2, "long", -42.5),
    LEXICON("name", "Hazard Shallows", "lat", -14, "long", 155.3)
).

// === CONSTANTS ===
SET KERBIN_ROT TO 21600.
SET TOLERANCE TO 15.
SET MAX_ETA TO 10.

// === CURRENT ORBIT ===
plog("=== CURRENT ORBIT ===").
plog("Body: " + SHIP:BODY:NAME).
plog("Apoapsis: " + ROUND(SHIP:ORBIT:APOAPSIS/1000, 2) + " km").
plog("Periapsis: " + ROUND(SHIP:ORBIT:PERIAPSIS/1000, 2) + " km").
plog("Period: " + ROUND(SHIP:ORBIT:PERIOD, 2) + " s (" + ROUND(SHIP:ORBIT:PERIOD/60, 1) + " min)").
plog("Inclination: " + ROUND(SHIP:ORBIT:INCLINATION, 4) + " deg").
plog("").

// === BURN WINDOW ===
SET currentTA TO SHIP:ORBIT:TRUEANOMALY.
SET orbitPeriod TO SHIP:ORBIT:PERIOD.

SET targetTA TO 90.
SET taToGo TO targetTA - currentTA.
IF taToGo < 0 { SET taToGo TO taToGo + 360. }
SET timeToWindow TO (taToGo / 360) * orbitPeriod.

SET inWindow TO (currentTA >= 45 AND currentTA <= 135).

plog("=== BURN WINDOW ===").
plog("Current True Anomaly: " + ROUND(currentTA, 2) + " deg").
IF inWindow {
    plog("STATUS: IN BURN WINDOW NOW (TA 45-135)").
} ELSE {
    plog("Time to burn window: " + ROUND(timeToWindow/60, 1) + " min").
}
plog("").

// === LANDING SITES ===
plog("=== LANDING SITES ===").
FROM {LOCAL i IS 0.} UNTIL i >= sites:LENGTH STEP {SET i TO i+1.} DO {
    plog((i+1) + ". " + sites[i]["name"] + " (Lat: " + sites[i]["lat"] + ", Long: " + sites[i]["long"] + ")").
}
plog("").

// === CHECK FOR NODE ===
IF NOT HASNODE {
    plog("=== NO MANEUVER NODE ===").
    plog("1. Create TKI node at TA ~90 deg").
    plog("2. Warp to node ETA < " + MAX_ETA + " seconds").
    plog("3. Run TKI again for accurate prediction").
} ELSE {
    SET nd TO NEXTNODE.
    
    SET nodeTA TO SHIP:ORBIT:TRUEANOMALY + (nd:ETA / SHIP:ORBIT:PERIOD) * 360.
    UNTIL nodeTA <= 360 { SET nodeTA TO nodeTA - 360. }
    
    plog("=== MANEUVER NODE ===").
    plog("Node ETA: " + ROUND(nd:ETA, 2) + " s").
    plog("Node True Anomaly: " + ROUND(nodeTA, 2) + " deg").
    plog("Delta-V: " + ROUND(nd:DELTAV:MAG, 2) + " m/s").
    plog("  Prograde: " + ROUND(nd:PROGRADE, 2) + " m/s").
    plog("  Normal: " + ROUND(nd:NORMAL, 2) + " m/s").
    plog("  Radial: " + ROUND(nd:RADIALOUT, 2) + " m/s").
    plog("").
    
    // === CHECK ETA ===
    IF nd:ETA > MAX_ETA {
        plog("*** NODE ETA TOO HIGH ***").
        plog("Warp to ETA < " + MAX_ETA + " seconds, then run TKI again.").
        plog("Prediction unreliable until then.").
    } ELSE {
        // === FIND KERBIN ENCOUNTER ===
        SET postOrbit TO nd:ORBIT.
        SET encounterOrbit TO postOrbit.
        UNTIL NOT encounterOrbit:HASNEXTPATCH {
            SET encounterOrbit TO encounterOrbit:NEXTPATCH.
            IF encounterOrbit:BODY:NAME = "Kerbin" {
                BREAK.
            }
        }
        
        IF encounterOrbit:BODY:NAME <> "Kerbin" {
            plog("No Kerbin encounter! Adjust your node.").
        } ELSE {
            SET nodeTime TO TIME:SECONDS + nd:ETA.
            SET peTime TO TIME:SECONDS + encounterOrbit:ETA:PERIAPSIS.
            SET transitTime TO peTime - nodeTime.
            
            SET pePos TO POSITIONAT(SHIP, peTime) - encounterOrbit:BODY:POSITION.
            SET peLat TO encounterOrbit:BODY:GEOPOSITIONOF(pePos):LAT.
            SET peLong TO encounterOrbit:BODY:GEOPOSITIONOF(pePos):LNG.
            
            SET rotDeg TO (transitTime / KERBIN_ROT) * 360.
            SET landLong TO peLong + rotDeg.
            UNTIL landLong <= 180 { SET landLong TO landLong - 360. }
            UNTIL landLong > -180 { SET landLong TO landLong + 360. }
            
            plog("=== KERBIN ENCOUNTER ===").
            plog("PE Altitude: " + ROUND(encounterOrbit:PERIAPSIS/1000, 2) + " km").
            plog("Transit time: " + ROUND(transitTime/3600, 2) + " h").
            plog("").
            plog("=== PREDICTED LANDING ===").
            plog("Latitude: " + ROUND(peLat, 4) + " deg").
            plog("Longitude: " + ROUND(landLong, 4) + " deg").
            plog("").
            
            // === DISTANCE TO EACH SITE ===
            plog("=== DISTANCE TO SITES ===").
            SET bestSite TO "".
            SET bestError TO 999.
            
            FROM {LOCAL i IS 0.} UNTIL i >= sites:LENGTH STEP {SET i TO i+1.} DO {
                SET site TO sites[i].
                SET longErr TO site["long"] - landLong.
                IF longErr > 180 { SET longErr TO longErr - 360. }
                IF longErr < -180 { SET longErr TO longErr + 360. }
                
                IF ABS(longErr) <= TOLERANCE {
                    plog(site["name"] + ": " + ROUND(longErr, 1) + " deg - IN RANGE").
                    IF ABS(longErr) < bestError {
                        SET bestError TO ABS(longErr).
                        SET bestSite TO site["name"].
                    }
                } ELSE {
                    plog(site["name"] + ": " + ROUND(longErr, 1) + " deg").
                }
            }
            
            plog("").
            IF bestSite <> "" {
                plog("=== BEST MATCH: " + bestSite + " ===").
                plog("EXECUTE BURN NOW!").
            } ELSE {
                plog("=== NO SITE IN RANGE ===").
                plog("Delete node, wait 1 orbit, try again.").
                plog("(Each orbit shifts landing ~42 deg East)").
            }
        }
    }
}

plog("").
plog("=== END OF LOG ===").
PRINT "→ Saved to 0:tki_log.txt".