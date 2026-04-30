@LAZYGLOBAL OFF.
// Minimal LOI - Circularize at Mun Pe

CLEARSCREEN.
PRINT "LOI - Waiting for periapsis...".

SET TARGET TO MUN.

// Wait until near Pe
WAIT UNTIL ETA:PERIAPSIS < 180.

// Calculate circ burn
LOCAL mun_r IS SHIP:BODY:RADIUS + SHIP:PERIAPSIS.
LOCAL v_current IS SQRT(SHIP:BODY:MU * (2/mun_r - 1/SHIP:ORBIT:SEMIMAJORAXIS)).
LOCAL v_circular IS SQRT(SHIP:BODY:MU / mun_r).
LOCAL dv IS v_circular - v_current.

PRINT "Creating node: " + ROUND(dv, 1) + " m/s".

// Create node at Pe
LOCAL nd IS NODE(TIME:SECONDS + ETA:PERIAPSIS, 0, 0, dv).
ADD nd.

// Calculate burn time
LOCAL f IS 0.
LOCAL isp IS 0.
LOCAL eng_list IS LIST().
LIST ENGINES IN eng_list.
FOR eng IN eng_list {
    IF eng:IGNITION {
        SET f TO f + eng:AVAILABLETHRUST.
        SET isp TO isp + eng:ISP * eng:AVAILABLETHRUST.
    }
}
SET isp TO isp / f.
LOCAL bt IS (SHIP:MASS * 9.81 * isp * (1 - CONSTANT:E^(-dv/(9.81*isp)))) / f.

PRINT "Burn: " + ROUND(bt, 1) + "s".
PRINT " ".
PRINT "Orient and press any key...".
TERMINAL:INPUT:GETCHAR().

// Orient
SAS OFF.
RCS ON.
LOCK STEERING TO nd:DELTAV.
WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, nd:DELTAV) < 2.

// Wait for burn
WAIT UNTIL nd:ETA < bt/2.
AG7 ON.
PRINT "IGNITION!".

// Execute
UNTIL nd:DELTAV:MAG < 0.5 {
    LOCAL thr IS MIN(1, nd:DELTAV:MAG / 10).
    LOCK THROTTLE TO thr.
    WAIT 0.01.
}

LOCK THROTTLE TO 0.
AG7 OFF.
UNLOCK STEERING.
UNLOCK THROTTLE.
REMOVE nd.

PRINT "LOI complete!".