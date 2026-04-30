//Temp start up script for S-IVB stage.

//Turning processor on.
copypath("0:/LOI.ks", "1:/LOI.ks").
copypath("0:/TKI.ks", "1:/TKI.ks").
copypath("0:/coast.ks", "1:/coast.ks").
//copypath("0:/coast.ks", "1:/coast.ks").
PROCESSOR("SATV"):ACTIVATE().
// // Writing config file for SIV-B stage.  1 for deorbit to Kerbin.  2 for Mun impact.
//LOG "2" TO "mission.txt" ON PROCESSOR("SATV"):VOLUME.
WAIT 1.
// // Activation of SIV-B stage processor.
// PROCESSOR("SATV"):ACTIVATE().
PRINT "S-IVB Processor Activated        " AT (0, 16).

//Capsule seperation.
WAIT 5.
AG7 ON.
RCS ON.
PRINT "CSM Separation                   " AT (0, 17).
SET SHIP:CONTROL:FORE TO 1.
WAIT 2.
SET SHIP:CONTROL:FORE TO 0.
LOCK THROTTLE TO 0.

//end program.