    LOCAL baseParts IS SHIP:PARTSNAMED("AM.MLP.TitanIILaunchStand").
    IF baseParts:LENGTH > 0 {
        SET basePart TO baseParts[0].
        LOCAL genCount IS 0.
        FOR moduleName IN basePart:ALLMODULES {
            IF moduleName = "ModuleGenerator" {
                SET genCount TO genCount + 1.
                SET genModule TO basePart:GETMODULE(moduleName).
                IF genModule:ALLACTIONNAMES:CONTAINS("activate generator") {
                    genModule:DOACTION("activate generator", TRUE).
                    PRINT "Activated generator " + genCount + " on " + basePart:NAME AT (0, 1 + genCount).
                } ELSE IF genModule:ALLEVENTNAMES:CONTAINS("activate generator") {
                    genModule:DOEVENT("activate generator").
                    PRINT "Activated generator " + genCount + " (event) on " + basePart:NAME AT (0, 1 + genCount).
                } ELSE {
                    PRINT "Generator " + genCount + " already active on " + basePart:NAME AT (0, 1 + genCount).
                }
            }
        }
    }