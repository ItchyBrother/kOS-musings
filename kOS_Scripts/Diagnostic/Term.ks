LIST PARTS IN partsList.

FOR part IN partsList {
    IF part:HASMODULE("ModuleEngines") OR part:HASMODULE("ModuleEnginesFX") {
        PRINT "Part Name: " + part:NAME.
        PRINT "Title:     " + part:TITLE.
        PRINT "-----------".
        WAIT 0.1.
    }
}

// FOR part IN partsList {
//     IF part:HASMODULE("ModuleEnginesFX") AND part:NAME = "liquidEngine.v2" {
//         PRINT "Part Name: " + part:NAME.
//         PRINT "Title:     " + part:TITLE.
//        // LOCAL engMod IS part:GETMODULE("ModuleEnginesFX").
//         //PRINT "Max Thrust: " + engMod:GETFIELD("maxThrust") + " kN".
//         PRINT "-----------".
//         WAIT 0.1.
//     }
// }

// // Clear the screen to start with a clean slate
// CLEARSCREEN.

// // Define variables for telemetry
// //SET MISSIONTIME TO 0.
// //SET ALT:RADAR TO 0.
// //SET VERTICALSPEED TO 0.
// SET PITCH TO 0.
// //SET GROUNDSPEED TO 0.
// // SET ORBIT:APOAPSIS TO 0.
// // SET ORBIT:PERIAPSIS TO 0.
// // SET ORBIT:VELOCITY:MAG TO 0.
// // SET STAGE:THRUST TO 0.
// // SET STAGE:THRUSTLIMIT TO 0.
// SET terminal:width TO 50. // Set terminal width to 36 characters

// // Initialize cursor position
// LOCAL cursorY IS 0.

// // Function to print a dividing line
// FUNCTION printDivideLine {
//   PARAMETER lineChar IS "=", lineLength IS terminal:width.
//   LOCAL line IS "".
//   UNTIL line:length >= lineLength {
//     SET line TO line + lineChar.
//   }
//   PRINT line AT (0, cursorY).
//   SET cursorY TO cursorY + 1.
// }

// // Function to print a section header
// FUNCTION printSectionHeader {
//   PARAMETER sectionTitle.
//   printDivideLine().
//   PRINT "| " + sectionTitle + " |" AT (0, cursorY).
//   SET cursorY TO cursorY + 1.
//   printDivideLine().
// }

// // Function to format and print telemetry data
// FUNCTION printTelemetry {
//   PARAMETER title, value, unit, column IS 0.
//   //PRINT title + ": " + ROUND(value, 2) + " " + unit AT (column, cursorY).
//   PRINT title + ": " + " " + unit AT (column, cursorY).
//   SET cursorY TO cursorY + 1.
// }

// // Main telemetry display function
// FUNCTION PRINT_TELEMETRY {
//   SET cursorY TO 0. // Reset cursor position
//   printSectionHeader("General Info").
//   printTelemetry("M.E.T.", MISSIONTIME, "s").
//   printTelemetry("CURRENT STATUS", "OPEN LOOP ASCENT", "").
  
//   printSectionHeader("Surface Data").
//   printTelemetry("SURFACE ALT", ALT:RADAR, "km").
//   printTelemetry("VERTICAL SPD", VERTICALSPEED, "m/s").
//   printTelemetry("SURF PITCH", PITCH, "deg").
//   printTelemetry("HORIZ SPD", GROUNDSPEED, "m/s", terminal:width / 2).
  
//   printSectionHeader("Current Orbit Data").
//   printTelemetry("APOAPSIS", ORBIT:APOAPSIS, "km").
//   printTelemetry("PERIAPSIS", ORBIT:PERIAPSIS, "km").
//   printTelemetry("ORB VELOCITY", ORBIT:VELOCITY, "m/s").
  
//   printSectionHeader("Target Orbit Data").
//   printTelemetry("APOAPSIS", 345, "km").
//   printTelemetry("PERIAPSIS", 180, "km").
//   printTelemetry("ORB VELOCITY", 7864.7, "m/s").
  
//   printSectionHeader("Vehicle Data").
//   printTelemetry("STG THRUST", "STAGE:THRUST", "kN").
//   printTelemetry("STG THR", "STAGE:THRUSTLIMIT * 100", "%").
  
//   printSectionHeader("Message Box").
//   PRINT "PITCHING DOWNRANGE" AT (0, cursorY).
//   SET cursorY TO cursorY + 1.
  
//   WAIT 1. // Pause to allow reading before clearing
//   CLEARSCREEN.
// }

// // Loop to update telemetry every second
// UNTIL FALSE {
//   PRINT_TELEMETRY().
// }