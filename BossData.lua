-- ============================================================
-- data/BossData.lua
-- Raid boss and add data for UBBRaidMaster
-- Server: Turtle WoW
-- Source: BigWigs addon modules (Turtle WoW build)
-- ============================================================
--
-- Format per entry:
--   name     : boss name (string)
--   adds     : list of add/wipemob names (table of strings)
--   wipemobs : adds that wipe the raid if not killed (subset of adds)
--   notes    : optional short note
--
-- "adds" contains all mobs that belong to this encounter
-- and are relevant for kill-order / tanking assignments.
-- Pure trash (pre-boss patrols) is listed in the raid's
-- trashMobs table, not per-boss.
-- ============================================================

UBBBossData = {}

-- ============================================================
-- RUINS OF AHN'QIRAJ (AQ20) — 20-man
-- ============================================================
UBBBossData["Ruins of Ahn'Qiraj"] = {
    {
        name     = "Kurinnaxx",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "General Rajaxx",
        adds     = {
            -- Wave 1
            "Qiraji Warrior", "Qiraji Needler", "Captain Qeez",
            -- Wave 2
            "Captain Tuubid",
            -- Wave 3
            "Captain Drenn",
            -- Wave 4
            "Captain Xurrem",
            -- Wave 5
            "Major Yeggeth",
            -- Wave 6
            "Major Pakkon",
            -- Wave 7
            "Colonel Zerran",
        },
        wipemobs = {},
        notes    = "8 waves before Rajaxx himself engages",
    },
    {
        name     = "Moam",
        adds     = { "Mana Fiend" },
        wipemobs = {},
    },
    {
        name     = "Buru the Gorger",
        adds     = { "Hive'Zara Egg" },
        wipemobs = {},
    },
    {
        name     = "Ayamiss the Hunter",
        adds     = { "Hive'Zara Larva" },
        wipemobs = {},
    },
    {
        name     = "Ossirian the Unscarred",
        adds     = {},
        wipemobs = {},
    },
}
UBBBossData["Ruins of Ahn'Qiraj"].trashMobs = {
    "Anubisath Guardian",
    "Flesh Hunter",
    "Hive'Zara Soldier",
}

-- ============================================================
-- TEMPLE OF AHN'QIRAJ (AQ40) — 40-man
-- ============================================================
UBBBossData["Temple of Ahn'Qiraj"] = {
    {
        name     = "The Prophet Skeram",
        adds     = {},
        wipemobs = {},
        notes    = "Splits into clones at 75%/50%/25% — clones are not tracked as adds",
    },
    {
        name     = "Battleguard Sartura",
        adds     = { "Sartura's Royal Guard" },
        wipemobs = { "Sartura's Royal Guard" },
    },
    {
        name     = "The Bug Family",
        adds     = { "Lord Kri", "Princess Yauj", "Vem" },
        wipemobs = { "Lord Kri", "Princess Yauj", "Vem" },
        notes    = "All three must die; kill order matters (Vem last)",
    },
    {
        name     = "Fankriss the Unyielding",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "Viscidus",
        adds     = { "Glob of Viscidus" },
        wipemobs = {},
        notes    = "Globs reform into Viscidus if not killed",
    },
    {
        name     = "Princess Huhuran",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "The Twin Emperors",
        adds     = { "Emperor Vek'lor", "Emperor Vek'nilash" },
        wipemobs = { "Emperor Vek'lor", "Emperor Vek'nilash" },
        notes    = "Both must die within 5 seconds of each other",
    },
    {
        name     = "Ouro",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "C'Thun",
        adds     = {
            "Eye of C'Thun",
            "Claw Tentacle",
            "Eye Tentacle",
            "Giant Claw Tentacle",
            "Giant Eye Tentacle",
            "Flesh Tentacle",
        },
        wipemobs = {},
        notes    = "Phase 1: Eye. Phase 2: Stomach — kill Flesh Tentacles to escape",
    },
}
UBBBossData["Temple of Ahn'Qiraj"].trashMobs = {
    "Qiraji Brainwasher",
    "Qiraji Champion",
    "Qiraji Mindslayer",
    "Anubisath Defender",
    "Anubisath Sentinel",
    "Anubisath Warder",
}

-- ============================================================
-- BLACKWING LAIR (BWL) — 40-man
-- ============================================================
UBBBossData["Blackwing Lair"] = {
    {
        name     = "Razorgore the Untamed",
        adds     = { "Grethok the Controller", "Blackwing Guardsman" },
        wipemobs = { "Grethok the Controller" },
        notes    = "Phase 1: kill adds; 3 Guardsman deaths trigger phase change",
    },
    {
        name     = "Vaelastrasz the Corrupt",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "Broodlord Lashlayer",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "Firemaw",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "Ebonroc",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "Flamegor",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "Chromaggus",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "Nefarian",
        adds     = {
            "Red Drakonid",
            "Blue Drakonid",
            "Green Drakonid",
            "Black Drakonid",
            "Bronze Drakonid",
            "Bone Construct",
        },
        wipemobs = {},
        notes    = "Phase 1: 44 Drakonids in waves. Phase 3 (20% HP): Bone Constructs",
    },
}
UBBBossData["Blackwing Lair"].trashMobs = {
    "Death Talon Wyrmguard",
}

-- ============================================================
-- MOLTEN CORE (MC) — 40-man  [Turtle WoW: +3 custom bosses]
-- ============================================================
UBBBossData["Molten Core"] = {
    {
        name     = "Lucifron",
        adds     = { "Flamewaker Protector", "Flamewaker Protector" },
        wipemobs = {},
        notes    = "2x Flamewaker Protector; kill before boss",
    },
    {
        name     = "Magmadar",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "Gehennas",
        adds     = { "Flamewaker", "Flamewaker" },
        wipemobs = {},
    },
    {
        name     = "Garr",
        adds     = { "Firesworn" },
        wipemobs = {},
        notes    = "8x Firesworn banished/killed before Garr",
    },
    {
        name     = "Baron Geddon",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "Shazzrah",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "Sulfuron Harbinger",
        adds     = { "Flamewaker Priest" },
        wipemobs = {},
        notes    = "4x Flamewaker Priest; healer adds — kill first",
    },
    {
        name     = "Golemagg the Incinerator",
        adds     = { "Core Rager" },
        wipemobs = {},
        notes    = "2x Core Rager; do NOT kill unless Golemagg <10% HP",
    },
    {
        name     = "Majordomo Executus",
        adds     = { "Flamewaker Elite", "Flamewaker Healer" },
        wipemobs = {},
        notes    = "4x Elite + 4x Healer; kill all adds, boss surrenders",
    },
    {
        name     = "Ragnaros",
        adds     = { "Son of Flame" },
        wipemobs = { "Son of Flame" },
        notes    = "10x Son of Flame during submerge phase; must be killed before Ragnaros resurfaces",
    },
    -- Turtle WoW custom bosses
    {
        name     = "Incindis",
        adds     = {},
        wipemobs = {},
        notes    = "Custom Turtle WoW boss",
    },
    {
        name     = "Sorcerer-Thane Thaurissan",
        adds     = {},
        wipemobs = {},
        notes    = "Custom Turtle WoW boss",
    },
    {
        name     = "Twin Golems",
        adds     = { "Smoldaris", "Basalthar" },
        wipemobs = { "Smoldaris", "Basalthar" },
        notes    = "Custom Turtle WoW boss; both golems are the encounter",
    },
}
UBBBossData["Molten Core"].trashMobs = {
    "Core Hound",
    "Ancient Core Hound",
    "Flame Imp",
    "Lava Surger",
}

-- ============================================================
-- ZUL'GURUB (ZG) — 20-man
-- ============================================================
UBBBossData["Zul'Gurub"] = {
    {
        name     = "High Priest Venoxis",
        adds     = { "Razzashi Cobra" },
        wipemobs = {},
        notes    = "4x Razzashi Cobra; Phase 1 Troll → Phase 2 Snake (at Enrage/engage yell)",
    },
    {
        name     = "High Priestess Jeklik",
        adds     = {},
        wipemobs = {},
        notes    = "Phase 1 Bat (HP >50%) → Phase 2 Troll (HP <50%)",
    },
    {
        name     = "High Priestess Mar'li",
        adds     = { "Spawn of Mar'li" },
        wipemobs = {},
        notes    = "Alternating Troll/Spider phases (35s each); 4 Spider adds per cycle",
    },
    {
        name     = "Bloodlord Mandokir",
        adds     = { "Ohgan" },
        wipemobs = { "Ohgan" },
        notes    = "Ohgan must be kept alive; his death enrages Mandokir. Mandokir levels up on kills.",
    },
    {
        name     = "Gahz'ranka",
        adds     = {},
        wipemobs = {},
        notes    = "Optional boss; summoned via Mudskunk Lure",
    },
    {
        name     = "High Priest Thekal",
        adds     = { "Zealot Zath", "Zealot Lor'Khan" },
        wipemobs = { "Zealot Zath", "Zealot Lor'Khan" },
        notes    = "Phase 1: all 3 must die within ~1s of each other (they res); Phase 2: Tiger form",
    },
    {
        name     = "High Priestess Arlokk",
        adds     = {},
        wipemobs = {},
        notes    = "Vanish/Mark/Panther phase cycle; +35% damage in Panther form",
    },
    {
        name     = "Hakkar the Soulflayer",
        adds     = { "Son of Hakkar" },
        wipemobs = {},
        notes    = "Sons die for Poisonous Blood stacks (Blood Siphon mechanic). Aspects active if priests not killed.",
    },
    -- Edge of Madness (one of four random each reset)
    {
        name     = "Gri'lek",
        adds     = {},
        wipemobs = {},
        notes    = "Edge of Madness boss; Avatar ability — run away",
    },
    {
        name     = "Hazza'rah",
        adds     = { "Nightmare Illusion" },
        wipemobs = {},
        notes    = "Edge of Madness boss; 3x Nightmare Illusions — kill fast",
    },
    {
        name     = "Renataki",
        adds     = {},
        wipemobs = {},
        notes    = "Edge of Madness boss; Vanish/Ambush cycle",
    },
    {
        name     = "Wushoolay",
        adds     = {},
        wipemobs = {},
        notes    = "Edge of Madness boss; interrupt Chain Lightning",
    },
}
UBBBossData["Zul'Gurub"].trashMobs = {
    "Gurubashi Bat Rider",
    "Gurubashi Berserker",
    "Mad Servant",
}

-- ============================================================
-- NAXXRAMAS — 40-man
-- ============================================================
UBBBossData["Naxxramas"] = {
    -- Spider Wing
    {
        name     = "Anub'Rekhan",
        adds     = { "Crypt Guard" },
        wipemobs = {},
        notes    = "Crypt Guard enrages on adds death; Locust Swarm: move away",
    },
    {
        name     = "Grand Widow Faerlina",
        adds     = { "Naxxramas Worshipper" },
        wipemobs = {},
        notes    = "4x Worshippers; MC a Worshipper to remove Enrage (Widow's Embrace)",
    },
    {
        name     = "Maexxna",
        adds     = { "Maexxna Spiderling" },
        wipemobs = {},
        notes    = "Spiderlings every 30s; Web Spray every 40s; kill spiderlings before they reach healers",
    },
    -- Plague Wing
    {
        name     = "Noth the Plaguebringer",
        adds     = {
            "Plagued Warrior",
            "Plagued Champion",
            "Plagued Guardian",
            "Plagued Construct",
        },
        wipemobs = {},
        notes    = "Floor/Balcony phases; adds spawn during balcony (waves) and on floor",
    },
    {
        name     = "Heigan the Unclean",
        adds     = {},
        wipemobs = {},
        notes    = "Dance phase every 90s; stay on safe platform sector",
    },
    {
        name     = "Loatheb",
        adds     = { "Spore" },
        wipemobs = {},
        notes    = "Spore spawns every 13s — stand in it for Fungal Bloom (allows healing); Inevitable Doom escalates",
    },
    -- Military Wing
    {
        name     = "Instructor Razuvious",
        adds     = { "Deathknight Understudy" },
        wipemobs = {},
        notes    = "Priests MC Understudies to tank; 4x Understudy available",
    },
    {
        name     = "Gothik the Harvester",
        adds     = {
            "Unrelenting Trainee",
            "Unrelenting Deathknight",
            "Unrelenting Rider",
            "Spectral Trainee",
            "Spectral Deathknight",
            "Spectral Rider",
        },
        wipemobs = {},
        notes    = "Split raid on two sides; living side kills adds before they go spectral; Gothik enters room after ~274s",
    },
    {
        name     = "The Four Horsemen",
        adds     = {
            "Thane Korth'azz",
            "Highlord Mograine",
            "Sir Zeliek",
            "Lady Blaumeux",
        },
        wipemobs = {
            "Thane Korth'azz",
            "Highlord Mograine",
            "Sir Zeliek",
            "Lady Blaumeux",
        },
        notes    = "All 4 are the encounter; rotate tanks every 3 marks; all 4 must die within ~15s of each other",
    },
    -- Construct Wing
    {
        name     = "Patchwerk",
        adds     = {},
        wipemobs = {},
        notes    = "Enrage at 5% HP or ~7 minutes; pure tank & spank",
    },
    {
        name     = "Grobbulus",
        adds     = {},
        wipemobs = {},
        notes    = "Mutating Injection: walk boss to wall before debuff expires",
    },
    {
        name     = "Gluth",
        adds     = { "Zombie Chow" },
        wipemobs = {},
        notes    = "Zombie Chow heal Gluth; kite/kill before Decimate; Decimate every 105s",
    },
    {
        name     = "Thaddius",
        adds     = { "Feugen", "Stalagg" },
        wipemobs = { "Feugen", "Stalagg" },
        notes    = "Phase 1: kill Feugen + Stalagg (they res if not simultaneous); Phase 2: Polarity Shift — match charge",
    },
    -- Frostwyrm Lair
    {
        name     = "Sapphiron",
        adds     = {},
        wipemobs = {},
        notes    = "Ice Bolt: hide behind Ice Block; Blizzard: move away",
    },
    {
        name     = "Kel'Thuzad",
        adds     = {
            "Unstoppable Abomination",
            "Soul Weaver",
            "Guardian of Icecrown",
        },
        wipemobs = {},
        notes    = "Phase 1 (320s): kill 14 Abominations + 14 Soul Weavers. Phase 2: boss active. Phase 3 (<40% HP): 5 Guardians — shackle up to 3",
    },
}
UBBBossData["Naxxramas"].trashMobs = {
    "Carrion Spinner",
    "Venom Stalker",
    "Necro Stalker",
    "Patchwork Golem",
    "Deathknight Captain",
    "Deathknight Cavalier",
    "Death Lord",
    "Stoneskin Gargoyle",
    "Plagued Gargoyle",
    "Living Monstrosity",
}

-- ============================================================
-- EMERALD SANCTUM — custom Turtle WoW raid
-- ============================================================
UBBBossData["Emerald Sanctum"] = {
    {
        name     = "Solnius",
        adds     = {},
        wipemobs = {},
        notes    = "Sleep phase (45s): adds spawn in waves. Hard Mode: Erennius joins the fight",
    },
    {
        name     = "Erennius",
        adds     = {},
        wipemobs = {},
        notes    = "Solo boss; also appears as Hard Mode add for Solnius",
    },
}
UBBBossData["Emerald Sanctum"].trashMobs = {
    "Sanctum Dragonkin",
    "Sanctum Dreamer",
    "Sanctum Suppressor",
    "Sanctum Wyrm",
    "Sanctum Wyrmkin",
}

-- ============================================================
-- LOWER KARAZHAN HALLS — custom Turtle WoW raid (10-man)
-- ============================================================
UBBBossData["Lower Karazhan Halls"] = {
    {
        name     = "Grizikil",
        adds     = { "Grellkin" },
        wipemobs = {},
        notes    = "Grellkin spawn on engage",
    },
    {
        name     = "Moroes",
        adds     = {},
        wipemobs = {},
        notes    = "2 phases; no adds",
    },
    {
        name     = "Brood Queen Araxxna",
        adds     = { "Skitterweb Egg" },
        wipemobs = {},
        notes    = "2 eggs per yell; eggs hatch after 20s",
    },
    {
        name     = "Clawlord Howlfang",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "Lord Blackwald II",
        adds     = { "Shadowbane Ragefang" },
        wipemobs = {},
        notes    = "First Ragefang ~30s after engage, then ~every 60s",
    },
}
UBBBossData["Lower Karazhan Halls"].trashMobs = {
    "Phantom Servant",
    "Dark Rider Champion",
}

-- ============================================================
-- UPPER KARAZHAN HALLS — custom Turtle WoW raid (40-man)
-- ============================================================
UBBBossData["Upper Karazhan Halls"] = {
    {
        name     = "Echo of Medivh",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "Kruul",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "Mephistroth",
        adds     = { "Shard of Hellfury" },
        wipemobs = {},
        notes    = "Shards spawn during Shards of Hellfury cast",
    },
    {
        name     = "Rupturan the Broken",
        adds     = { "Dirt Mound", "Living Stone" },
        wipemobs = {},
    },
    {
        name     = "Sanv Tas'dal",
        adds     = { "NetherWalker" },
        wipemobs = {},
        notes    = "NetherWalkers spawn during Phase Shifted",
    },
    {
        name     = "Anomalus",
        adds     = {},
        wipemobs = {},
    },
    {
        name     = "King",
        adds     = { "Knight", "Bishop", "Rook" },
        wipemobs = {},
        notes    = "Chess Event",
    },
    {
        name     = "Ley-Watcher Incantagos",
        adds     = { "Manascale Ley-Seeker", "Manascale Whelp" },
        wipemobs = {},
    },
    {
        name     = "Keeper Gnarlmoon",
        adds     = { "Blood Raven", "Red Owl", "Blue Owl" },
        wipemobs = {},
        notes    = "12x Blood Ravens in waves; Red Owl at 66% HP, Blue Owl at 33% HP",
    },
}
UBBBossData["Upper Karazhan Halls"].trashMobs = {
    "Manascale Drake",
    "Unstable Arcane Elemental",
    "Disrupted Arcane Elemental",
    "Arcane Anomaly",
    "Crumbling Protector",
    "Lingering Magus",
    "Lingering Astrologist",
    "Phantom Servant",
    "Dark Rider Champion",
}

-- ============================================================
-- HELPER: Get all boss names for a raid (for dropdowns)
-- ============================================================
function UBBBossData_GetBossNames(raidName)
    local data = UBBBossData[raidName]
    if not data then return {} end
    local names = {}
    for _, entry in ipairs(data) do
        table.insert(names, entry.name)
    end
    return names
end

-- ============================================================
-- HELPER: Get adds for a specific boss
-- ============================================================
function UBBBossData_GetAdds(raidName, bossName)
    local data = UBBBossData[raidName]
    if not data then return {} end
    for _, entry in ipairs(data) do
        if entry.name == bossName then
            return entry.adds or {}
        end
    end
    return {}
end

-- ============================================================
-- HELPER: Get wipemobs for a specific boss
-- ============================================================
function UBBBossData_GetWipemobs(raidName, bossName)
    local data = UBBBossData[raidName]
    if not data then return {} end
    for _, entry in ipairs(data) do
        if entry.name == bossName then
            return entry.wipemobs or {}
        end
    end
    return {}
end

-- ============================================================
-- HELPER: Get sorted list of all raid names
-- ============================================================
function UBBBossData_GetRaidNames()
    local names = {}
    for raidName, _ in pairs(UBBBossData) do
        table.insert(names, raidName)
    end
    table.sort(names)
    return names
end
