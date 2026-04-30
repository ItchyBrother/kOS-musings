// KOS Script: engine_check.ks
// Diagnostic to check engine properties

CLEARSCREEN.
PRINT "Engine Diagnostic Running...".

LIST ENGINES IN myEngines.

IF myEngines:LENGTH = 0 {
    PRINT "No engines found.".
} ELSE {
    FOR eng IN myEngines {
        PRINT " ".
        PRINT "Engine: " + eng:NAME.
        PRINT "Ignition: " + eng:IGNITION.
        PRINT "Flameout: " + eng:FLAMEOUT.
        PRINT "Max Thrust: " + ROUND(eng:MAXTHRUST, 2) + " kN".
        PRINT "Throttle Lock: " + eng:THROTTLELOCK.
        PRINT "Available Thrust: " + ROUND(eng:AVAILABLETHRUST, 2) + " kN".
        IF eng:HASMODULE("ModuleEngines") {
            SET eng_module TO eng:GETMODULE("ModuleEngines").
            PRINT "Has ModuleEngines: Yes".
            PRINT "Throttle (Module): " + ROUND(eng_module:GETFIELD("throttle"), 2).
        } ELSE {
            PRINT "Has ModuleEngines: No".
        }
    }
}

PRINT " ".
PRINT "Press any key to exit...".
WAIT UNTIL TERMINAL:INPUT:HASCHAR.
TERMINAL:INPUT:GETCHAR().

// CLEARSCREEN.
// PRINT "Script Version 1.9" AT (0, 0).
// PRINT "Fueling/Detanking Control" AT (0, 1).

// SET basePart TO SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall")[0].
// SET capsuleDrainPart TO SHIP:PARTSTAGGED("CapsuleDrain")[0]. // kOS tag on capsule FTE-1
// SET lvDrainPart TO SHIP:PARTSTAGGED("LVDrain")[0].           // kOS tag on LV FTE-1

// // Debug all modules
// PRINT "Base modules: " + basePart:MODULES:JOIN(", ") AT (0, 2).
// SET fuelMod TO 0.
// SET drainCapsule TO 0. // Mono on capsule
// SET drainLV TO 0.     // LF/OX on LV
// LOCAL modIndex IS 0.

// // Fueling on base
// FOR mod IN basePart:MODULES {
//     IF mod = "ModuleResourceConverter" {
//         SET tempMod TO basePart:GETMODULE(mod).
//         PRINT "Base Module " + modIndex + " (Converter): " AT (0, 5).
//         PRINT "  Actions: " + tempMod:ALLACTIONNAMES:JOIN(", ") AT (0, 6).
//         PRINT "  Fields: " + tempMod:ALLFIELDS:JOIN(", ") AT (0, 7).
//         IF tempMod:ALLFIELDS:CONTAINS("debugTag") {
//             PRINT "  DebugTag: " + tempMod:GETFIELD("debugTag") AT (0, 8).
//         }
//         SET fuelMod TO tempMod.
//         PRINT "Assigned FuelingSystem (index " + modIndex + ")" AT (0, 9).
//     }
//     SET modIndex TO modIndex + 1.
// }

// // Drain on capsule
// SET modIndex TO 0.
// FOR mod IN capsuleDrainPart:MODULES {
//     IF mod = "ModuleResourceDrain" {
//         SET tempMod TO capsuleDrainPart:GETMODULE(mod).
//         PRINT "Capsule Module " + modIndex + " (Drain): " AT (0, 10).
//         PRINT "  Actions: " + tempMod:ALLACTIONNAMES:JOIN(", ") AT (0, 11).
//         PRINT "  Fields: " + tempMod:ALLFIELDS:JOIN(", ") AT (0, 12).
//         SET drainCapsule TO tempMod.
//         PRINT "Assigned DrainCapsule (Mono, index " + modIndex + ")" AT (0, 13).
//     }
//     SET modIndex TO modIndex + 1.
// }

// // Drain on LV
// SET modIndex TO 0.
// IF SHIP:PARTSTAGGED("LVDrain"):LENGTH > 0 {
//     FOR mod IN lvDrainPart:MODULES {
//         IF mod = "ModuleResourceDrain" {
//             SET tempMod TO lvDrainPart:GETMODULE(mod).
//             PRINT "LV Module " + modIndex + " (Drain): " AT (0, 15).
//             PRINT "  Actions: " + tempMod:ALLACTIONNAMES:JOIN(", ") AT (0, 16).
//             PRINT "  Fields: " + tempMod:ALLFIELDS:JOIN(", ") AT (0, 17).
//             SET drainLV TO tempMod.
//             PRINT "Assigned DrainLV (LF/OX, index " + modIndex + ")" AT (0, 18).
//         }
//         SET modIndex TO modIndex + 1.
//     }
// }

// IF fuelMod = 0 OR drainCapsule = 0 {
//     PRINT "Error: Didn’t assign FuelingSystem or DrainCapsule" AT (0, 19).
//     PRINT "Available modules:" AT (0, 20).
//     SET modIndex TO 0.
//     FOR mod IN basePart:MODULES {
//         IF mod = "ModuleResourceConverter" {
//             PRINT "Base Module " + modIndex + ": " + basePart:GETMODULE(mod):ALLACTIONNAMES:JOIN(", ") AT (0, 21 + modIndex).
//             SET modIndex TO modIndex + 1.
//         }
//     }
//     SET modIndex TO 0.
//     FOR mod IN capsuleDrainPart:MODULES {
//         IF mod = "ModuleResourceDrain" {
//             PRINT "Capsule Module " + modIndex + ": " + capsuleDrainPart:GETMODULE(mod):ALLACTIONNAMES:JOIN(", ") AT (0, 22 + modIndex).
//             SET modIndex TO modIndex + 1.
//         }
//     }
//     IF SHIP:PARTSTAGGED("LVDrain"):LENGTH > 0 {
//         SET modIndex TO 0.
//         FOR mod IN lvDrainPart:MODULES {
//             IF mod = "ModuleResourceDrain" {
//                 PRINT "LV Module " + modIndex + ": " + lvDrainPart:GETMODULE(mod):ALLACTIONNAMES:JOIN(", ") AT (0, 23 + modIndex).
//                 SET modIndex TO modIndex + 1.
//             }
//         }
//     }
// } ELSE {
//     // Get tank capacities
//     SET lfCap TO 0. SET oxCap TO 0. SET monoCap TO 0.
//     FOR res IN SHIP:RESOURCES {
//         IF res:NAME = "LiquidFuel" { SET lfCap TO res:CAPACITY. }
//         IF res:NAME = "Oxidizer" { SET oxCap TO res:CAPACITY. }
//         IF res:NAME = "MonoPropellant" { SET monoCap TO res:CAPACITY. }
//     }
//     PRINT "Capacities - LF: " + lfCap + " OX: " + oxCap + " Mono: " + monoCap AT (0, 2).
//     PRINT "Press 0 to toggle, 9 to abort" AT (0, 3).

//     // Initial state
//     LOCAL initRow IS 20.
//     PRINT "Initial LF: " + SHIP:LIQUIDFUEL + " OX: " + SHIP:OXIDIZER + " Mono: " + SHIP:MONOPROPELLANT + " EC: " + SHIP:ELECTRICCHARGE AT (0, initRow).

//     // Fueling to 100%
//     LOCAL fuelRow IS 23.
//     PRINT "Starting fueling..." AT (0, fuelRow).
//     IF fuelMod:HASACTION("Start Fueling") {
//         fuelMod:DOACTION("Start Fueling", TRUE).
//         PRINT "FuelingSystem started (camel case)" AT (0, fuelRow + 1).
//     } ELSE {
//         PRINT "FuelingSystem: Blind trigger..." AT (0, fuelRow + 1).
//         fuelMod:DOACTION("Start Fueling", TRUE).
//     }
//     UNTIL SHIP:LIQUIDFUEL >= lfCap AND SHIP:OXIDIZER >= oxCap AND SHIP:MONOPROPELLANT >= monoCap {
//         PRINT "Fueling: LF: " + SHIP:LIQUIDFUEL + " OX: " + SHIP:OXIDIZER + " Mono: " + SHIP:MONOPROPELLANT + " EC: " + SHIP:ELECTRICCHARGE AT (0, fuelRow + 2).
//         IF TERMINAL:INPUT:HASCHAR {
//             SET key TO TERMINAL:INPUT:GETCHAR().
//             IF key = "0" {
//                 fuelMod:DOACTION("Toggle Fueling", TRUE).
//                 PRINT "Fueling toggled (on/off)" AT (0, 4).
//             }
//             IF key = "9" {
//                 fuelMod:DOACTION("Stop Fueling", TRUE).
//                 PRINT "Fueling aborted - switching to detanking" AT (0, 4).
//                 BREAK.
//             }
//         }
//         WAIT 0.5.
//     }
//     fuelMod:DOACTION("Stop Fueling", TRUE).
//     PRINT "Fueling complete. Final LF: " + SHIP:LIQUIDFUEL + " OX: " + SHIP:OXIDIZER + " Mono: " + SHIP:MONOPROPELLANT AT (0, fuelRow + 3).

//     // Wait before detanking
//     WAIT 2.

//     // Detanking to 0%
//     LOCAL detankRow IS 27.
//     PRINT "Starting detanking..." AT (0, detankRow).
//     IF drainCapsule:HASACTION("drain") {
//         drainCapsule:DOACTION("drain", TRUE).
//         PRINT "DrainCapsule started (lowercase)" AT (0, detankRow + 1).
//     } ELSE {
//         PRINT "DrainCapsule: Blind trigger..." AT (0, detankRow + 1).
//         drainCapsule:DOACTION("drain", TRUE).
//     }
//     IF drainLV <> 0 AND drainLV:HASACTION("drain") {
//         drainLV:DOACTION("drain", TRUE).
//         PRINT "DrainLV started (lowercase)" AT (0, detankRow + 2).
//     } ELSE IF drainLV <> 0 {
//         PRINT "DrainLV: Blind trigger..." AT (0, detankRow + 2).
//         drainLV:DOACTION("drain", TRUE).
//     }
//     UNTIL SHIP:LIQUIDFUEL <= 0 AND SHIP:OXIDIZER <= 0 AND SHIP:MONOPROPELLANT <= 0 {
//         PRINT "Detanking: LF: " + SHIP:LIQUIDFUEL + " OX: " + SHIP:OXIDIZER + " Mono: " + SHIP:MONOPROPELLANT + " EC: " + SHIP:ELECTRICCHARGE AT (0, detankRow + 3).
//         IF TERMINAL:INPUT:HASCHAR {
//             SET key TO TERMINAL:INPUT:GETCHAR().
//             IF key = "0" {
//                 drainCapsule:DOACTION("toggle draining", TRUE).
//                 IF drainLV <> 0 { drainLV:DOACTION("toggle draining", TRUE). }
//                 PRINT "Detanking toggled (on/off)" AT (0, 4).
//             }
//             IF key = "9" {
//                 drainCapsule:DOACTION("stop draining", TRUE).
//                 IF drainLV <> 0 { drainLV:DOACTION("stop draining", TRUE). }
//                 PRINT "Detanking aborted" AT (0, 4).
//                 BREAK.
//             }
//         }
//         WAIT 0.5.
//     }
//     drainCapsule:DOACTION("stop draining", TRUE).
//     IF drainLV <> 0 { drainLV:DOACTION("stop draining", TRUE). }
//     PRINT "Detanking complete. Final LF: " + SHIP:LIQUIDFUEL + " OX: " + SHIP:OXIDIZER + " Mono: " + SHIP:MONOPROPELLANT AT (0, detankRow + 4).
// }
// // Script to workaround fueling control on AM_MLP_FlatLaunchBaseSmall
// SET basePart TO SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall")[0].
// PRINT "Targeting part: " + basePart:NAME.

// // Find both generators and the launch clamp
// LOCAL gen1 IS 0.
// LOCAL gen2 IS 0.
// LOCAL clamp IS 0.
// FOR moduleName IN basePart:ALLMODULES {
//     IF moduleName = "ModuleGenerator" {
//         IF gen1 = 0 {
//             SET gen1 TO basePart:GETMODULE(moduleName).
//             PRINT "Found Generator 1 (ElectricCharge).".
//         } ELSE {
//             SET gen2 TO basePart:GETMODULE(moduleName).
//             PRINT "Found Generator 2 (Fueling).".
//         }
//     }
//     IF moduleName = "LaunchClamp" {
//         SET clamp TO basePart:GETMODULE(moduleName).
//         PRINT "Found LaunchClamp module.".
//     }
// }

// // Test 1: Activate Generator 1 to see if it unlocks Generator 2
// IF gen1:HASACTION("activate generator") {
//     gen1:DOACTION("activate generator", TRUE).
//     PRINT "Activated Generator 1. Checking Generator 2...".
//     WAIT 1.
//     PRINT "Gen 2 Events: " + gen2:ALLEVENTNAMES:JOIN(", ").
//     PRINT "Gen 2 Actions: " + gen2:ALLACTIONNAMES:JOIN(", ").
// } ELSE {
//     PRINT "Generator 1 already active or no activation action.".
// }

// // Test 2: Stage the clamp to trigger fueling
// IF clamp:HASEVENT("release Clamp") {
//     PRINT "Staging clamp to test fueling...".
//     clamp:DOEVENT("Release Clamp").
//     WAIT 2. // Give it a moment to kick in
// } ELSE {
//     PRINT "No 'Release Clamp' event found.".
// }

// // Test 3: Monitor fuel levels to detect manual start
// PRINT "Monitoring fuel to detect manual start...".
// PRINT "Click 'Start Fueling' in-game when ready.".
// SET initialLF TO SHIP:LIQUIDFUEL.
// SET initialOX TO SHIP:OXIDIZER.
// SET fuelingDetected TO FALSE.
// UNTIL fuelingDetected {
//     IF SHIP:LIQUIDFUEL > initialLF + 5 OR SHIP:OXIDIZER > initialOX + 5 {
//         SET fuelingDetected TO TRUE.
//         PRINT "Fueling detected! Monitoring for 5 seconds...".
//     }
//     WAIT 0.1.
// }
// SET startTime TO TIME:SECONDS.
// UNTIL TIME:SECONDS > startTime + 5 {
//     PRINT "LiquidFuel: " + SHIP:LIQUIDFUEL + " | Oxidizer: " + SHIP:OXIDIZER.
//     WAIT 1.
// }

// // Attempt to stop manually if possible
// PRINT "Click 'Stop Fueling' in-game, then press 1 to check state...".
// WAIT UNTIL TERMINAL:INPUT:HASCHAR.
// PRINT "Post-stop state:".
// PRINT "  Gen 2 Events: " + gen2:ALLEVENTNAMES:JOIN(", ").
// PRINT "  Gen 2 Actions: " + gen2:ALLACTIONNAMES:JOIN(", ").
// PRINT "  Gen 2 Fields: " + gen2:ALLFIELDNAMES:JOIN(", ").

// // Script to diagnose and control fueling on AM_MLP_FlatLaunchBaseSmall
// SET basePart TO SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall")[0].
// PRINT "Targeting part: " + basePart:NAME.

// // Find the second ModuleGenerator
// LOCAL genCount IS 0.
// LOCAL fuelingGen IS 0.
// FOR moduleName IN basePart:ALLMODULES {
//     IF moduleName = "ModuleGenerator" {
//         SET genCount TO genCount + 1.
//         IF genCount = 2 {
//             SET fuelingGen TO basePart:GETMODULE(moduleName).
//             PRINT "Found fueling generator (Generator 2).".
//         }
//     }
// }

// IF fuelingGen = 0 {
//     PRINT "Error: Second ModuleGenerator not found. Aborting.".
// } ELSE {
//     // Initial state
//     PRINT "Initial state:".
//     PRINT "  Events: " + fuelingGen:ALLEVENTNAMES:JOIN(", ").
//     PRINT "  Actions: " + fuelingGen:ALLACTIONNAMES:JOIN(", ").
//     PRINT "  Fields: " + fuelingGen:ALLFIELDNAMES:JOIN(", ").
//     FOR field IN fuelingGen:ALLFIELDNAMES {
//         PRINT "    " + field + ": " + fuelingGen:GETFIELD(field).
//     }

//     // Prompt for manual activation
//     PRINT "Please click 'Start Fueling' in-game, then press 1...".
//     WAIT UNTIL TERMINAL:INPUT:HASCHAR.

//     // Post-manual state
//     PRINT "After manual 'Start Fueling':".
//     PRINT "  Events: " + fuelingGen:ALLEVENTNAMES:JOIN(", ").
//     PRINT "  Actions: " + fuelingGen:ALLACTIONNAMES:JOIN(", ").
//     PRINT "  Fields: " + fuelingGen:ALLFIELDNAMES:JOIN(", ").
//     FOR field IN fuelingGen:ALLFIELDNAMES {
//         PRINT "    " + field + ": " + fuelingGen:GETFIELD(field).
//     }

//     // Test stopping if possible
//     IF fuelingGen:HASEVENT("Stop Fueling") {
//         fuelingGen:DOEVENT("Stop Fueling").
//         PRINT "Triggered 'Stop Fueling' event.".
//     } ELSE IF fuelingGen:HASACTION("Stop Fueling") {
//         fuelingGen:DOACTION("Stop Fueling", TRUE).
//         PRINT "Triggered 'Stop Fueling' action.".
//     } ELSE {
//         PRINT "No 'Stop Fueling' found either.".
//     }

//     // Monitor fuel to confirm state
//     PRINT "Monitoring fuel levels for 5 seconds...".
//     SET startTime TO TIME:SECONDS.
//     UNTIL TIME:SECONDS > startTime + 5 {
//         PRINT "LiquidFuel: " + SHIP:LIQUIDFUEL + " | Oxidizer: " + SHIP:OXIDIZER.
//         WAIT 1.
//     }
// }
// // Script in Kerbal Space Program with kOS to activate fueling on AM_MLP_FlatLaunchBaseSmall
// SET basePart TO SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall")[0].
// PRINT "Targeting part: " + basePart:NAME.

// // Find and target the second ModuleGenerator
// LOCAL genCount IS 0.
// LOCAL fuelingGen IS 0.
// FOR moduleName IN basePart:ALLMODULES {
//     IF moduleName = "ModuleGenerator" {
//         SET genCount TO genCount + 1.
//         SET genModule TO basePart:GETMODULE(moduleName).
//         IF genCount = 2 { // Second generator is the fueling one
//             SET fuelingGen TO genModule.
//             PRINT "Found fueling generator (Generator 2).".
//         }
//     }
// }

// IF fuelingGen = 0 {
//     PRINT "Error: Second ModuleGenerator not found. Aborting.".
// } ELSE {
//     // Inspect initial state
//     PRINT "Initial state:".
//     PRINT "  Events: " + fuelingGen:ALLEVENTNAMES:JOIN(", ").
//     PRINT "  Actions: " + fuelingGen:ALLACTIONNAMES:JOIN(", ").
//     PRINT "  Fields: " + fuelingGen:ALLFIELDNAMES:JOIN(", ").

//     // Attempt to trigger fueling
//     IF fuelingGen:HASEVENT("Start Fueling") {
//         fuelingGen:DOEVENT("Start Fueling").
//         PRINT "Triggered 'Start Fueling' event.".
//     } ELSE IF fuelingGen:HASACTION("Start Fueling") {
//         fuelingGen:DOACTION("Start Fueling", TRUE).
//         PRINT "Triggered 'Start Fueling' action.".
//     } ELSE {
//         PRINT "No 'Start Fueling' event or action found. Trying lowercase...".
//         IF fuelingGen:HASEVENT("start fueling") {
//             fuelingGen:DOEVENT("start fueling").
//             PRINT "Triggered 'start fueling' event.".
//         } ELSE IF fuelingGen:HASACTION("start fueling") {
//             fuelingGen:DOACTION("start fueling", TRUE).
//             PRINT "Triggered 'start fueling' action.".
//         } ELSE {
//             PRINT "Still no match. Manual check required.".
//             PRINT "Please click 'Start Fueling' in-game, then press 1...".
//             WAIT UNTIL TERMINAL:INPUT:HASCHAR.
//             PRINT "Post-manual state:".
//             PRINT "  Events: " + fuelingGen:ALLEVENTNAMES:JOIN(", ").
//             PRINT "  Actions: " + fuelingGen:ALLACTIONNAMES:JOIN(", ").
//             PRINT "  Fields: " + fuelingGen:ALLFIELDNAMES:JOIN(", ").
//         }
//     }

//     // Monitor fuel levels to confirm
//     PRINT "Monitoring fuel levels for 5 seconds...".
//     SET startTime TO TIME:SECONDS.
//     UNTIL TIME:SECONDS > startTime + 5 {
//         PRINT "LiquidFuel: " + SHIP:LIQUIDFUEL + " | Oxidizer: " + SHIP:OXIDIZER.
//         WAIT 1.
//     }
// }
// SET basePart TO SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall")[0].
// PRINT "Part: " + basePart:NAME.
// PRINT "Type: " + basePart:TYPENAME. // Should say LaunchClampValue or Part
// PRINT "All Modules: " + basePart:ALLMODULES:JOIN(", ").

// // // Test first generator
// SET gen1 TO basePart:GETMODULE("ModuleGenerator").
// PRINT "Generator 1 Events: " + gen1:ALLEVENTNAMES:JOIN(", ").
// PRINT "Generator 1 Actions: " + gen1:ALLACTIONNAMES:JOIN(", ").


// lookingforParts().
// testGenerators().
// findFuelingParts().
// findFuelingModule().
// testFueling().
// testGenerator2().
// testAllModules().
// desperateFuelSearch().

// FUNCTION desperateFuelSearch {
//     SET basePart TO SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall")[0].
    
//     // Activate generators
//     LOCAL genCount IS 0.
//     FOR moduleName IN basePart:ALLMODULES {
//         IF moduleName = "ModuleGenerator" {
//             SET genCount TO genCount + 1.
//             SET genModule TO basePart:GETMODULE(moduleName).
//             IF genModule:ALLACTIONNAMES:CONTAINS("activate generator") {
//                 genModule:DOACTION("activate generator", TRUE).
//                 PRINT "Activated generator " + genCount.
//             }
//         }
//     }

//     // Try anything with "fuel"
//     FOR moduleName IN basePart:ALLMODULES {
//         SET mymod TO basePart:GETMODULE(moduleName).
//         FOR event IN mymod:ALLEVENTNAMES {
//             IF event:CONTAINS("fuel") {
//                 mymod:DOEVENT(event).
//                 PRINT "Triggered event " + event + " on " + moduleName.
//             }
//         }
//         FOR action IN mymod:ALLACTIONNAMES {
//             IF action:CONTAINS("fuel") {
//                 mymod:DOACTION(action, TRUE).
//                 PRINT "Triggered action " + action + " on " + moduleName.
//             }
//         }
//     }
//     PRINT "No fuel events/actions found. Manual click required?".
// }


// FUNCTION testAllModules {
//     SET basePart TO SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall")[0].
    
//     // Activate generators
//     LOCAL genCount IS 0.
//     FOR moduleName IN basePart:ALLMODULES {
//         IF moduleName = "ModuleGenerator" {
//             SET genCount TO genCount + 1.
//             SET genModule TO basePart:GETMODULE(moduleName).
//             IF genModule:ALLACTIONNAMES:CONTAINS("activate generator") {
//                 genModule:DOACTION("activate generator", TRUE).
//                 PRINT "Activated generator " + genCount.
//             }
//         }
//     }

//     // Check all modules before
//     PRINT "Before clicking 'Start Fueling':".
//     FOR moduleName IN basePart:ALLMODULES {
//         SET mymod TO basePart:GETMODULE(moduleName).
//         PRINT "  Module: " + moduleName.
//         PRINT "    Events: " + mymod:ALLEVENTNAMES:JOIN(", ").
//         PRINT "    Actions: " + mymod:ALLACTIONNAMES:JOIN(", ").
//         PRINT "    Fields: " + mymod:ALLFIELDNAMES:JOIN(", ").
//     }

//     PRINT "Click 'Start Fueling' in-game, then press 1...".
//     WAIT UNTIL TERMINAL:INPUT:HASCHAR.

//     // Check all modules after
//     PRINT "After clicking 'Start Fueling':".
//     FOR moduleName IN basePart:ALLMODULES {
//         SET mymod TO basePart:GETMODULE(moduleName).
//         PRINT "  Module: " + moduleName.
//         PRINT "    Events: " + mymod:ALLEVENTNAMES:JOIN(", ").
//         PRINT "    Actions: " + mymod:ALLACTIONNAMES:JOIN(", ").
//         PRINT "    Fields: " + mymod:ALLFIELDNAMES:JOIN(", ").
//     }
// }

// FUNCTION testGenerator2 {
//     SET basePart TO SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall")[0].
//     LOCAL genCount IS 0.
//     FOR moduleName IN basePart:ALLMODULES {
//         IF moduleName = "ModuleGenerator" {
//             SET genCount TO genCount + 1.
//             IF genCount = 2 { // Second generator
//                 SET genModule TO basePart:GETMODULE(moduleName).
//                 PRINT "Generator 2 Before:".
//                 PRINT "  Events: " + genModule:ALLEVENTNAMES:JOIN(", ").
//                 PRINT "  Actions: " + genModule:ALLACTIONNAMES:JOIN(", ").
//                 PRINT "  Fields: " + genModule:ALLFIELDNAMES:JOIN(", ").
//                 PRINT "Click 'Start Fueling' in-game, then press 1...".
//                 WAIT UNTIL TERMINAL:INPUT:HASCHAR.
//                 PRINT "Generator 2 After:".
//                 PRINT "  Events: " + genModule:ALLEVENTNAMES:JOIN(", ").
//                 PRINT "  Actions: " + genModule:ALLACTIONNAMES:JOIN(", ").
//                 PRINT "  Fields: " + genModule:ALLFIELDNAMES:JOIN(", ").
//             }
//         }
//     }
// }

// FUNCTION testFueling {
//     SET basePart TO SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall")[0].
    
//     // Activate generators
//     LOCAL genCount IS 0.
//     FOR moduleName IN basePart:ALLMODULES {
//         IF moduleName = "ModuleGenerator" {
//             SET genCount TO genCount + 1.
//             SET genModule TO basePart:GETMODULE(moduleName).
//             IF genModule:ALLACTIONNAMES:CONTAINS("activate generator") {
//                 genModule:DOACTION("activate generator", TRUE).
//                 PRINT "Activated generator " + genCount.
//             }
//         }
//     }

//     // Test LaunchClamp
//     SET clampModule TO basePart:GETMODULE("LaunchClamp").
//     PRINT "Before: Events: " + clampModule:ALLEVENTNAMES:JOIN(", ").
//     PRINT "Before: Actions: " + clampModule:ALLACTIONNAMES:JOIN(", ").
//     PRINT "Before: Fields: " + clampModule:ALLFIELDNAMES:JOIN(", ").
    
//     // Try common variations
//     IF clampModule:ALLEVENTNAMES:CONTAINS("Start Fueling") {
//         clampModule:DOEVENT("Start Fueling").
//         PRINT "Started fueling (event).".
//     } ELSE IF clampModule:ALLACTIONNAMES:CONTAINS("Start Fueling") {
//         clampModule:DOACTION("Start Fueling", TRUE).
//         PRINT "Started fueling (action).".
//     } ELSE {
//         PRINT "No Start Fueling in LaunchClamp. Checking after manual click...".
//         PRINT "Click 'Start Fueling' in-game, then press 1 to continue...".
//         WAIT UNTIL TERMINAL:INPUT:HASCHAR.
//         PRINT "After: Events: " + clampModule:ALLEVENTNAMES:JOIN(", ").
//         PRINT "After: Actions: " + clampModule:ALLACTIONNAMES:JOIN(", ").
//         PRINT "After: Fields: " + clampModule:ALLFIELDNAMES:JOIN(", ").
//     }
// }

// FUNCTION testGenerators {
//     SET basePart TO SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall")[0].
//     PRINT "Testing " + basePart:NAME + " (" + basePart:TYPENAME + ")".
//     LOCAL genCount IS 0.
//     FOR moduleName IN basePart:ALLMODULES {
//         IF moduleName = "ModuleGenerator" {
//             SET genCount TO genCount + 1.
//             SET genModule TO basePart:GETMODULE(moduleName).
//             PRINT "Generator " + genCount + ": ".
//             PRINT "  Events: " + genModule:ALLEVENTNAMES:JOIN(", ").
//             PRINT "  Actions: " + genModule:ALLACTIONNAMES:JOIN(", ").
//             IF genModule:ALLACTIONNAMES:CONTAINS("activate generator") {
//                 genModule:DOACTION("activate generator", TRUE).
//                 PRINT "  Activated generator " + genCount.
//                 WAIT 1. // Brief pause to let it settle
//                 PRINT "  New Events: " + genModule:ALLEVENTNAMES:JOIN(", ").
//                 PRINT "  New Actions: " + genModule:ALLACTIONNAMES:JOIN(", ").
//             } ELSE {
//                 PRINT "  No activate action—already active or unavailable.".
//             }
//         }
//     }
// }

// FUNCTION findFuelingParts {
//     LIST PARTS IN p.
//     PRINT "Scanning all parts for fueling options...".
//     LOCAL lineCount IS 0.
//     LOCAL maxLines IS 30.

//     FOR part IN p {
//         IF lineCount >= maxLines {
//             PRINT "Press 1 to continue, 0 to exit...".
//             WAIT UNTIL TERMINAL:INPUT:HASCHAR.
//             SET input TO TERMINAL:INPUT:GETCHAR().
//             IF input = "0" RETURN.
//             CLEARSCREEN.
//             SET lineCount TO 0.
//             PRINT "Scanning all parts for fueling options...".
//         }
        
//         PRINT "Part: " + part:NAME.
//         SET lineCount TO lineCount + 1.
//         FOR moduleName IN part:ALLMODULES {
//             SET mymod TO part:GETMODULE(moduleName).
//             LOCAL eventsStr IS mymod:ALLEVENTNAMES:JOIN(", "):TOLOWER().
//             LOCAL actionsStr IS mymod:ALLACTIONNAMES:JOIN(", "):TOLOWER().
//             LOCAL fieldsStr IS mymod:ALLFIELDNAMES:JOIN(", "):TOLOWER().
//             IF eventsStr:CONTAINS("fuel") OR actionsStr:CONTAINS("fuel") OR fieldsStr:CONTAINS("fuel") {
//                 PRINT "  Module: " + moduleName.
//                 SET lineCount TO lineCount + 1.
//                 PRINT "    Events: " + mymod:ALLEVENTNAMES:JOIN(", ").
//                 SET lineCount TO lineCount + 1.
//                 PRINT "    Actions: " + mymod:ALLACTIONNAMES:JOIN(", ").
//                 SET lineCount TO lineCount + 1.
//                 PRINT "    Fields: " + mymod:ALLFIELDNAMES:JOIN(", ").
//                 SET lineCount TO lineCount + 1.
//             }
//             IF lineCount >= maxLines {
//                 PRINT "Press 1 to continue, 0 to exit...".
//                 WAIT UNTIL TERMINAL:INPUT:HASCHAR.
//                 SET input TO TERMINAL:INPUT:GETCHAR().
//                 IF input = "0" RETURN.
//                 CLEARSCREEN.
//                 SET lineCount TO 0.
//                 PRINT "Scanning all parts for fueling options...".
//             }
//         }
//     }
//     PRINT "Scan complete. Press 1 to exit...".
//     WAIT UNTIL TERMINAL:INPUT:HASCHAR.
// }

// FUNCTION findFuelingModule {
//     SET basePart TO SHIP:PARTSNAMED("AM.MLP.FlatLaunchBaseSmall")[0].
//     PRINT "Inspecting " + basePart:NAME + " (" + basePart:TYPENAME + ")".
//     FOR moduleName IN basePart:ALLMODULES {
//         SET mymod TO basePart:GETMODULE(moduleName).
//         PRINT "Module: " + moduleName.
//         PRINT "  Events: " + mymod:ALLEVENTNAMES:JOIN(", ").
//         PRINT "  Actions: " + mymod:ALLACTIONNAMES:JOIN(", ").
//         PRINT "  Fields: " + mymod:ALLFIELDNAMES:JOIN(", ").
//     }
// }

// // Troubleshooting function to find items that can be toggled.
// FUNCTION lookingforParts {
//     LIST PARTS IN p.
//     LOCAL filteredParts IS LIST().
    
//     // Filter parts that start with "AM.MLP"
//     FOR part IN p {
//         IF part:NAME:STARTSWITH("AM.MLP") {
//             filteredParts:ADD(part).
//         }
//     }

//     SET index TO 0.
//     SET step TO 10. // Parts per page
//     SET lineCount TO 0.
//     SET maxLines TO 30. // Max lines before pausing

//     IF filteredParts:LENGTH = 0 {
//         PRINT "No parts found starting with 'AM.MLP'.".
//         RETURN.
//     }

//     UNTIL index >= filteredParts:LENGTH {
//         CLEARSCREEN.
//         SET lineCount TO 0.
//         PRINT "Showing parts " + index + " to " + MIN(index + step - 1, filteredParts:LENGTH - 1) + " (AM.MLP only)".
//         SET lineCount TO lineCount + 1.

//         FOR i IN RANGE(index, MIN(index + step, filteredParts:LENGTH)) {
//             PRINT "Part " + i + ": " + filteredParts[i]:NAME.
//             SET lineCount TO lineCount + 1.
//             PRINT "Modules: " + filteredParts[i]:ALLMODULES:JOIN(", ").
//             SET lineCount TO lineCount + 1.
//             IF filteredParts[i]:ALLMODULES:LENGTH > 0 {
//                 FOR moduleName IN filteredParts[i]:ALLMODULES {
//                     SET mymod TO filteredParts[i]:GETMODULE(moduleName).
//                     PRINT "  - " + moduleName + ": ".
//                     SET lineCount TO lineCount + 1.
//                     PRINT "    Events: " + mymod:ALLEVENTNAMES:JOIN(", ").
//                     SET lineCount TO lineCount + 1.
//                     PRINT "    Actions: " + mymod:ALLACTIONNAMES:JOIN(", ").
//                     SET lineCount TO lineCount + 1.
//                     IF lineCount >= maxLines {
//                         PRINT "Press 1 to continue, 0 to exit...".
//                         WAIT UNTIL TERMINAL:INPUT:HASCHAR.
//                         SET input TO TERMINAL:INPUT:GETCHAR().
//                         IF input = "0" RETURN.
//                         CLEARSCREEN.
//                         SET lineCount TO 0.
//                         PRINT "Showing parts " + index + " to " + MIN(index + step - 1, filteredParts:LENGTH - 1) + " (AM.MLP only)".
//                     }
//                 }
//             }
//             PRINT "---".
//             SET lineCount TO lineCount + 1.
//             IF lineCount >= maxLines {
//                 PRINT "Press 1 to continue, 0 to exit...".
//                 WAIT UNTIL TERMINAL:INPUT:HASCHAR.
//                 SET input TO TERMINAL:INPUT:GETCHAR().
//                 IF input = "0" RETURN.
//                 CLEARSCREEN.
//                 SET lineCount TO 0.
//                 PRINT "Showing parts " + index + " to " + MIN(index + step - 1, filteredParts:LENGTH - 1) + " (AM.MLP only)".
//             }
//         }

//         IF lineCount > 0 {
//             PRINT "Press 1 to continue, 0 to exit...".
//             WAIT UNTIL TERMINAL:INPUT:HASCHAR.
//             SET input TO TERMINAL:INPUT:GETCHAR().
//             IF input = "0" BREAK.
//         }
//         SET index TO index + step.
//     }
// }