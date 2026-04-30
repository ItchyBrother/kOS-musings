// test_drain.ks
CLEARSCREEN.
PRINT "Testing FTE-1 Drain Valves".

// Get drain parts
LOCAL lvDrainPart1 IS SHIP:PARTSTAGGED("LVDrain1").
LOCAL lvDrainPart2 IS SHIP:PARTSTAGGED("LVDrain2").
IF lvDrainPart1:LENGTH = 0 OR lvDrainPart2:LENGTH = 0 {
    PRINT "Error: Missing LVDrain1 or LVDrain2".
    WAIT 5.
    REBOOT.
}
SET lvDrainPart1 TO lvDrainPart1[0].
SET lvDrainPart2 TO lvDrainPart2[0].

// Log modules
PRINT "LVDrain1 Modules:".
FOR mod IN lvDrainPart1:MODULES {
    PRINT "  " + mod.
    IF mod = "ModuleResourceDrain" {
        LOCAL drainMod IS lvDrainPart1:GETMODULE(mod).
        PRINT "    Events: " + drainMod:ALLEVENTNAMES.
        PRINT "    Actions: " + drainMod:ALLACTIONNAMES.
    }
}
PRINT "LVDrain2 Modules:".
FOR mod IN lvDrainPart2:MODULES {
    PRINT "  " + mod.
    IF mod = "ModuleResourceDrain" {
        LOCAL drainMod IS lvDrainPart2:GETMODULE(mod).
        PRINT "    Events: " + drainMod:ALLEVENTNAMES.
        PRINT "    Actions: " + drainMod:ALLACTIONNAMES.
    }
}

// Test draining
LOCAL drainLV1 IS 0.
LOCAL drainLV2 IS 0.
FOR mod IN lvDrainPart1:MODULES {
    IF mod = "ModuleResourceDrain" {
        SET drainLV1 TO lvDrainPart1:GETMODULE(mod).
    }
}
FOR mod IN lvDrainPart2:MODULES {
    IF mod = "ModuleResourceDrain" {
        SET drainLV2 TO lvDrainPart2:GETMODULE(mod).
    }
}
IF drainLV1 = 0 OR drainLV2 = 0 {
    PRINT "Error: ModuleResourceDrain not found".
    WAIT 5.
    REBOOT.
}

// Test actions/events
PRINT "Testing LVDrain1...".
FOR action IN LIST("Toggle Drain", "Start Drain", "Drain", "Toggle Draining") {
    IF drainLV1:ALLACTIONNAMES:CONTAINS(action) {
        PRINT "Trying action: " + action.
        drainLV1:DOACTION(action, TRUE).
        WAIT 5.
        PRINT "Resources - LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT).
    }
}
FOR event IN LIST("Start Draining", "Drain", "Toggle Draining") {
    IF drainLV1:ALLEVENTNAMES:CONTAINS(event) {
        PRINT "Trying event: " + event.
        drainLV1:DOEVENT(event).
        WAIT 5.
        PRINT "Resources - LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT).
    }
}
PRINT "Testing LVDrain2...".
FOR action IN LIST("Toggle Drain", "Start Drain", "Drain", "Toggle Draining") {
    IF drainLV2:ALLACTIONNAMES:CONTAINS(action) {
        PRINT "Trying action: " + action.
        drainLV2:DOACTION(action, TRUE).
        WAIT 5.
        PRINT "Resources - LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT).
    }
}
FOR event IN LIST("Start Draining", "Drain", "Toggle Draining") {
    IF drainLV2:ALLEVENTNAMES:CONTAINS(event) {
        PRINT "Trying event: " + event.
        drainLV2:DOEVENT(event).
        WAIT 5.
        PRINT "Resources - LF: " + ROUND(SHIP:LIQUIDFUEL) + " OX: " + ROUND(SHIP:OXIDIZER) + " Mono: " + ROUND(SHIP:MONOPROPELLANT).
    }
}
PRINT "Drain test complete. Check resource levels.".