@LAZYGLOBAL OFF.

FUNCTION MAIN {
    CLEARSCREEN.
    PRINT "TEI EXECUTION".
    PRINT " ".
    
    IF NOT HASNODE {
        PRINT "ERROR: No maneuver node found!".
        PRINT "Run TEI_SEARCH first.".
        RETURN.
    }
    
    LOCAL nd IS NEXTNODE.
    
    PRINT "Node dV: " + ROUND(nd:DELTAV:MAG, 1) + " m/s".
    PRINT "Time: T+" + ROUND(nd:ETA/60, 1) + " min".
    PRINT " ".
    
    // Check/activate SM engine
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
    
    IF f = 0 {
        PRINT "Activating AG7...".
        AG7 ON.
        WAIT 1.
        
        SET f TO 0.
        SET isp TO 0.
        FOR eng IN eng_list {
            IF eng:IGNITION {
                SET f TO f + eng:AVAILABLETHRUST.
                SET isp TO isp + eng:ISP * eng:AVAILABLETHRUST.
            }
        }
    }
    
    IF f = 0 {
        PRINT "ERROR: No engine!".
        RETURN.
    }
    
    SET isp TO isp / f.
    LOCAL bt IS (SHIP:MASS * 9.81 * isp * (1 - CONSTANT:E^(-nd:DELTAV:MAG/(9.81*isp)))) / f.
    
    PRINT "Burn: " + ROUND(bt, 1) + "s".
    PRINT " ".
    PRINT "Press any key to proceed...".
    TERMINAL:INPUT:GETCHAR().
    
    // Orient
    SAS OFF.
    RCS ON.
    LOCK STEERING TO nd:DELTAV.
    WAIT UNTIL VANG(SHIP:FACING:FOREVECTOR, nd:DELTAV) < 2.
    
    PRINT "Waiting for burn window...".
    WAIT UNTIL nd:ETA < bt/2.
    
    PRINT "IGNITION!".
    
    // Execute
    UNTIL nd:DELTAV:MAG < 0.5 {
        LOCAL thr IS MIN(1, nd:DELTAV:MAG / 10).
        LOCK THROTTLE TO thr.
        WAIT 0.01.
    }
    
    LOCK THROTTLE TO 0.
    WAIT 0.5.
    UNLOCK STEERING.
    UNLOCK THROTTLE.
    REMOVE nd.
    
    PRINT "TEI complete!".
}

MAIN().