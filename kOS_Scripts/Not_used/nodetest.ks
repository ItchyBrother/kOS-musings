// === TKI ROTATION TEST ===
SWITCH to 0.
LOCAL destpath TO "0:/nodetest.ks".

WAIT 10.
IF NOT EXISTS(destpath) {
    copypath ("0:/nodetest.ks", "0:/nodetest.ks").
    PRINT "PROGRAM SUCCESSFULLY COPIED.".
} ELSE {
    CLEARSCREEN.
    PRINT "*************************************".
    PRINT "    Program aleady loaded!".
    PRINT "*************************************".
    WAIT 1.
}

DELETEPATH("0:tki_test.txt").
LOG "=== TKI ROTATION TEST - " + TIME:CALENDAR + " " + TIME:CLOCK + " ===" TO "0:tki_test.txt".

FUNCTION plog {
    PARAMETER txt.
    PRINT txt.
    LOG txt TO "0:tki_test.txt".
}

SET KERBIN_ROT TO 21600.

plog("=== CURRENT STATE ===").
plog("Time: " + TIME:SECONDS).
plog("").

IF NOT HASNODE {
    plog("No maneuver node found!").
    plog("Create your TKI node and run again.").
} ELSE {
    SET nd TO NEXTNODE.
    
    SET nodeTA TO SHIP:ORBIT:TRUEANOMALY + (nd:ETA / SHIP:ORBIT:PERIOD) * 360.
    UNTIL nodeTA <= 360 { SET nodeTA TO nodeTA - 360. }
    
    plog("=== MANEUVER NODE ===").
    plog("Node ETA: " + ROUND(nd:ETA, 2) + " s (" + ROUND(nd:ETA/60, 1) + " min)").
    plog("Node True Anomaly: " + ROUND(nodeTA, 2) + " deg").
    plog("Delta-V: " + ROUND(nd:DELTAV:MAG, 2) + " m/s").
    plog("").
    
    // === FIND KERBIN ENCOUNTER ===
    SET postOrbit TO nd:ORBIT.
    SET encounterOrbit TO postOrbit.
    UNTIL NOT encounterOrbit:HASNEXTPATCH {
        SET encounterOrbit TO encounterOrbit:NEXTPATCH.
        IF encounterOrbit:BODY:NAME = "Kerbin" {
            BREAK.
        }
    }
    
    IF encounterOrbit:BODY:NAME = "Kerbin" {
        SET nodeETA TO nd:ETA.
        SET nodeTime TO TIME:SECONDS + nodeETA.
        SET peTime TO TIME:SECONDS + encounterOrbit:ETA:PERIAPSIS.
        SET transitTime TO peTime - nodeTime.
        SET totalTimeToArrival TO encounterOrbit:ETA:PERIAPSIS.
        
        SET pePos TO POSITIONAT(SHIP, peTime) - encounterOrbit:BODY:POSITION.
        SET peLat TO encounterOrbit:BODY:GEOPOSITIONOF(pePos):LAT.
        SET peLong TO encounterOrbit:BODY:GEOPOSITIONOF(pePos):LNG.
        
        // === METHOD A: Total time from NOW ===
        SET rotDegA TO (totalTimeToArrival / KERBIN_ROT) * 360.
        SET landLongA TO peLong + rotDegA.
        UNTIL landLongA <= 180 { SET landLongA TO landLongA - 360. }
        UNTIL landLongA > -180 { SET landLongA TO landLongA + 360. }
        
        // === METHOD B: Transit time only ===
        SET rotDegB TO (transitTime / KERBIN_ROT) * 360.
        SET landLongB TO peLong + rotDegB.
        UNTIL landLongB <= 180 { SET landLongB TO landLongB - 360. }
        UNTIL landLongB > -180 { SET landLongB TO landLongB + 360. }
        
        plog("=== TIMING ===").
        plog("Node ETA: " + ROUND(nodeETA, 2) + " s (" + ROUND(nodeETA/60, 1) + " min)").
        plog("Transit time: " + ROUND(transitTime, 2) + " s (" + ROUND(transitTime/3600, 2) + " h)").
        plog("Total time to PE: " + ROUND(totalTimeToArrival, 2) + " s (" + ROUND(totalTimeToArrival/3600, 2) + " h)").
        plog("").
        plog("=== PE LOCATION (raw from GEOPOSITIONOF) ===").
        plog("Latitude: " + ROUND(peLat, 4) + " deg").
        plog("Longitude: " + ROUND(peLong, 4) + " deg").
        plog("").
        plog("=== METHOD A: Rotation from NOW to PE ===").
        plog("Rotation: " + ROUND(rotDegA, 2) + " deg").
        plog("Predicted landing: " + ROUND(peLat, 4) + ", " + ROUND(landLongA, 4)).
        plog("").
        plog("=== METHOD B: Rotation from BURN to PE ===").
        plog("Rotation: " + ROUND(rotDegB, 2) + " deg").
        plog("Predicted landing: " + ROUND(peLat, 4) + ", " + ROUND(landLongB, 4)).
        plog("").
        plog("=== DIFFERENCE ===").
        plog("Method A - Method B: " + ROUND(landLongA - landLongB, 4) + " deg").
    } ELSE {
        plog("No Kerbin encounter found!").
    }
}

plog("").
plog("=== END OF TEST ===").
PRINT "→ Saved to 0:tki_test.txt".