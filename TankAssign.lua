-------------------------------------------------------------------------------
-- TankAssign.lua
-- Tank assignment addon for WoW 1.12.1 / Turtle WoW
-- Inspired by and structurally based on HealAssign by the same project
-------------------------------------------------------------------------------
local ADDON_NAME    = "TankAssign"
local ADDON_VERSION = "1.0.0"
local COMM_PREFIX   = "TankAssign"
-------------------------------------------------------------------------------
-- CONSTANTS
-------------------------------------------------------------------------------
local TYPE_BOSS   = "BOSS"    -- named boss/add from BossData
local TYPE_MARK   = "MARK"    -- raid marker index (1-8)
local TYPE_CUSTOM = "CUSTOM"  -- free-text custom target
local TYPE_NAME   = "NAME"    -- mob/boss name target
local BUILTIN_CUSTOM_TARGETS = {
    "Right side", "Left side",
    "North", "South", "East", "West",
}
-- CC spells: spell name → required class (uppercase fileName)
local CC_SPELLS = {
    { spell="Polymorph",       class="MAGE"    },
    { spell="Banish",          class="WARLOCK" },
    { spell="Shackle Undead",  class="PRIEST"  },
    { spell="Hibernate",       class="DRUID"   },
    { spell="Entangling Roots",class="DRUID"   },
}
-- Quick lookup: class → list of CC spells
local CC_BY_CLASS = {}
for _,entry in ipairs(CC_SPELLS) do
    if not CC_BY_CLASS[entry.class] then CC_BY_CLASS[entry.class] = {} end
    table.insert(CC_BY_CLASS[entry.class], entry.spell)
end
-- Raid marker indices → names and texture paths (WoW 1.12.1)
local MARK_ICONS = {
    [1] = { name="Star",     tex="Interface\\AddOns\\TankAssign\\textures\\mark_1_star"     },
    [2] = { name="Circle",   tex="Interface\\AddOns\\TankAssign\\textures\\mark_2_circle"   },
    [3] = { name="Diamond",  tex="Interface\\AddOns\\TankAssign\\textures\\mark_3_diamond"  },
    [4] = { name="Triangle", tex="Interface\\AddOns\\TankAssign\\textures\\mark_4_triangle" },
    [5] = { name="Moon",     tex="Interface\\AddOns\\TankAssign\\textures\\mark_5_moon"     },
    [6] = { name="Square",   tex="Interface\\AddOns\\TankAssign\\textures\\mark_6_square"   },
    [7] = { name="Cross",    tex="Interface\\AddOns\\TankAssign\\textures\\mark_7_cross"    },
    [8] = { name="Skull",    tex="Interface\\AddOns\\TankAssign\\textures\\mark_8_skull"    },
}
-- Returns display string and optional mark texture for any target type
local function ResolveTargetDisp(targetType, targetValue, markIndex)
    if targetType == TYPE_MARK then
        local mi = markIndex or tonumber(targetValue) or 0
        return (MARK_ICONS[mi] and MARK_ICONS[mi].name or ("Mark "..mi)),
               (MARK_ICONS[mi] and MARK_ICONS[mi].tex or nil)
    end
    return targetValue or "?", nil
end
-- Taunt spells per class (Turtle WoW 1.12.1)
-- aoe=true means AoE taunt (long CD, forces all nearby)
local TAUNT_SPELLS = {
    { name="Taunt",             cd=8,   class="WARRIOR", aoe=false, icon="Interface\\Icons\\Spell_Nature_Reincarnation"       },
    { name="Mocking Blow",      cd=120, class="WARRIOR", aoe=false, icon="Interface\\Icons\\Ability_Warrior_PunishingBlow"    },
    { name="Challenging Shout", cd=600, class="WARRIOR", aoe=true,  icon="Interface\\Icons\\Ability_BullRush"                 },
    { name="Growl",             cd=10,  class="DRUID",   aoe=false, icon="Interface\\Icons\\Ability_Physical_Taunt"           },
    { name="Challenging Roar",  cd=600, class="DRUID",   aoe=true,  icon="Interface\\Icons\\Ability_Druid_ChallangingRoar"    },
    { name="Hand of Reckoning", cd=10,  class="PALADIN", aoe=false, icon="Interface\\Icons\\Spell_Holy_Unyieldingfaith"       },
    { name="Earthshaker Slam",  cd=10,  class="SHAMAN",  aoe=false, icon="Interface\\Icons\\earthshaker_slam_11"              },
}
-- Combat log patterns for self-cast taunt detection (CHAT_MSG_SPELL_SELF_CASTOTHER)
-- Each entry: { pattern, spellName }
local TAUNT_SELF_PATTERNS = {
    { pat="^You perform Taunt on ",             spell="Taunt"             },
    { pat="^You perform Mocking Blow on ",      spell="Mocking Blow"      },
    { pat="^You perform Challenging Shout",     spell="Challenging Shout" },
    { pat="^You perform Growl on ",             spell="Growl"             },
    { pat="Challenging Roar",                   spell="Challenging Roar"  },
    { pat="^You perform Hand of Reckoning on ", spell="Hand of Reckoning" },
    { pat="^You perform Earthshaker Slam on ",  spell="Earthshaker Slam"  },
}
-- Class colors (same as HealAssign)
local CLASS_COLORS = {
    WARRIOR  = {0.78, 0.61, 0.43},
    PALADIN  = {0.96, 0.55, 0.73},
    HUNTER   = {0.67, 0.83, 0.45},
    ROGUE    = {1.00, 0.96, 0.41},
    PRIEST   = {1.00, 1.00, 1.00},
    SHAMAN   = {0.00, 0.44, 0.87},
    MAGE     = {0.25, 0.78, 0.92},
    WARLOCK  = {0.53, 0.53, 0.93},
    DRUID    = {1.00, 0.49, 0.04},
}
local function GetClassColor(class)
    local c = class and CLASS_COLORS[string.upper(class or "")]
    if c then return c[1], c[2], c[3] end
    return 0.8, 0.8, 0.8
end
-------------------------------------------------------------------------------
-- DATABASE INIT
-------------------------------------------------------------------------------
TankAssignDB = nil  -- saved variable
local function InitDB()
    if not TankAssignDB then TankAssignDB = {} end
    if not TankAssignDB.templates       then TankAssignDB.templates       = {} end
    if not TankAssignDB.activeTemplate  then TankAssignDB.activeTemplate  = nil end
    if not TankAssignDB.options         then TankAssignDB.options         = {} end
    if not TankAssignDB.options.fontSize       then TankAssignDB.options.fontSize       = 12   end
    if not TankAssignDB.options.windowAlpha    then TankAssignDB.options.windowAlpha    = 0.95 end
    if not TankAssignDB.options.showAssignFrame then TankAssignDB.options.showAssignFrame = false end
    if TankAssignDB.options.hideInBG == nil     then TankAssignDB.options.hideInBG = true end
    if not TankAssignDB.options.customTargets   then TankAssignDB.options.customTargets = {} end
    if not TankAssignDB.tauntCD         then TankAssignDB.tauntCD         = {} end
    if not TankAssignDB.presets         then TankAssignDB.presets         = {} end
    if not TankAssignDB.combatPanelPos  then TankAssignDB.combatPanelPos  = nil end
    if not TankAssignDB.minimapAngle    then TankAssignDB.minimapAngle    = 220 end
end
-------------------------------------------------------------------------------
-- BATTLEGROUND / VISIBILITY HELPERS  (copied from HealAssign pattern)
-------------------------------------------------------------------------------
local function TA_IsInBattleground()
    local zone = GetZoneText() or ""
    local bgZones = {
        ["Warsong Gulch"]    = true,
        ["Arathi Basin"]     = true,
        ["Alterac Valley"]   = true,
        ["Sunnyglade Valley"] = true,
    }
    return bgZones[zone] == true
end
local function TA_ShouldShow()
    if TA_IsInBattleground() then
        local hideInBG = TankAssignDB and TankAssignDB.options and TankAssignDB.options.hideInBG
        if hideInBG == nil then hideInBG = true end
        if hideInBG then return false end
    end
    return true
end
-------------------------------------------------------------------------------
-- TEMPLATE HELPERS
-------------------------------------------------------------------------------
local function NewTemplate(name)
    return {
        name    = name or "",
        roster  = {},   -- [playerName] = {class, tagMT, tagOT, tagOOT, tagV}
        tanks   = {},   -- [{name, targetType, targetValue, markIndex}]
        cc      = {},   -- [{name, spell, targetType, targetValue, markIndex}]
        fw      = {     -- Fearward queues: list of {tankName, queue={priestNames}}
            tanks = {},
        },
    }
end
local function DeepCopy(orig)
    local copy
    if type(orig) == "table" then
        copy = {}
        for k,v in pairs(orig) do copy[DeepCopy(k)] = DeepCopy(v) end
    else
        copy = orig
    end
    return copy
end
-------------------------------------------------------------------------------
-- TEMPLATE STATE
-------------------------------------------------------------------------------
currentTemplate = nil
local function GetActiveTemplate()
    if currentTemplate then
        if not currentTemplate.roster then currentTemplate.roster = {} end
        if not currentTemplate.tanks  then currentTemplate.tanks  = {} end
        if not currentTemplate.fw          then currentTemplate.fw = {tanks={}} end
        if not currentTemplate.fw.tanks    then currentTemplate.fw.tanks = {} end
        -- migrate old format {tankName, queue} → new {tanks=[]}
        if currentTemplate.fw.tankName ~= nil or currentTemplate.fw.queue ~= nil then
            local oldTank = currentTemplate.fw.tankName
            local oldQ    = currentTemplate.fw.queue or {}
            currentTemplate.fw = {tanks={}}
            if oldTank then
                table.insert(currentTemplate.fw.tanks, {tankName=oldTank, queue=oldQ})
            end
        end
    end
    return currentTemplate
end
-- Build tank list from roster (all tagged MT/OT/OOT)
local function GetTanksFromRoster(tmpl)
    if not tmpl or not tmpl.roster then return {} end
    local out = {}
    for pname, pdata in pairs(tmpl.roster) do
        if pdata.tagMT or pdata.tagOT or pdata.tagOOT then
            table.insert(out, {name=pname, class=pdata.class,
                tagMT=pdata.tagMT, tagOT=pdata.tagOT, tagOOT=pdata.tagOOT})
        end
    end
    table.sort(out, function(a,b) return a.name < b.name end)
    return out
end
-- Build priest list from roster (all PRIEST class regardless of tag)
local function GetPriestsFromRoster(tmpl)
    if not tmpl or not tmpl.roster then return {} end
    local out = {}
    for pname, pdata in pairs(tmpl.roster) do
        if pdata.class == "PRIEST" then
            table.insert(out, pname)
        end
    end
    table.sort(out)
    return out
end
-- Sync FW queues: remove priests no longer in roster, remove duplicate assignments
local function SyncFWQueueFromRoster(tmpl)
    if not tmpl or not tmpl.fw then return end
    local priests = {}
    for _,p in ipairs(GetPriestsFromRoster(tmpl)) do priests[p] = true end
    -- Track which priests are already assigned (to prevent duplicates)
    local assigned = {}
    for _,slot in ipairs(tmpl.fw.tanks or {}) do
        local newQ = {}
        for _,p in ipairs(slot.queue or {}) do
            if priests[p] and not assigned[p] then
                table.insert(newQ, p)
                assigned[p] = true
            end
        end
        slot.queue = newQ
    end
end
-------------------------------------------------------------------------------
-- RAID HELPERS
-------------------------------------------------------------------------------
local function GetRaidMembers()
    local members = {}
    local numRaid = GetNumRaidMembers()
    if numRaid and numRaid > 0 then
        for i=1,numRaid do
            local name,rank,subgroup,level,class,fileName,zone,online = GetRaidRosterInfo(i)
            if name then
                table.insert(members, {name=name, class=fileName or class, rank=rank, subgroup=subgroup, online=online})
            end
        end
    else
        local pname = UnitName("player")
        local _,pclass = UnitClass("player")
        if pname then table.insert(members, {name=pname, class=pclass, rank=2, subgroup=1, online=true}) end
        local numParty = GetNumPartyMembers()
        if numParty and numParty > 0 then
            for i=1,numParty do
                local mname = UnitName("party"..i)
                local _,mclass = UnitClass("party"..i)
                if mname then table.insert(members, {name=mname, class=mclass, rank=0, subgroup=1, online=true}) end
            end
        end
    end
    table.sort(members, function(a,b) return a.name < b.name end)
    return members
end
local function IsRaidLeader()
    local myName = UnitName("player")
    local numRaid = GetNumRaidMembers()
    if not numRaid or numRaid == 0 then return false end
    for i=1,numRaid do
        local name,rank = GetRaidRosterInfo(i)
        if name == myName and rank == 2 then return true end
    end
    return false
end
local function HasEditorRights()
    local numRaid = GetNumRaidMembers()
    if not numRaid or numRaid == 0 then return false end
    local myName = UnitName("player")
    for i=1,numRaid do
        local name,rank = GetRaidRosterInfo(i)
        if name == myName and rank >= 1 then return true end
    end
    return false
end
local function GetChannel()
    if GetNumRaidMembers() > 0  then return "RAID"  end
    if GetNumPartyMembers() > 0 then return "PARTY" end
    return nil
end
-------------------------------------------------------------------------------
-- TAUNT COOLDOWN TRACKING
-------------------------------------------------------------------------------
-- tauntCD[playerName][spellName] = GetTime() of last cast
local tauntCD = {}
local function TAUNT_GetCDInfo(playerName, spellName)
    local cd = 0
    for _,ts in ipairs(TAUNT_SPELLS) do
        if ts.name == spellName then cd = ts.cd break end
    end
    if cd == 0 then return 0, 0 end
    local t = tauntCD[playerName] and tauntCD[playerName][spellName]
    if not t then return 0, cd end
    local rem = cd - (GetTime() - t)
    if rem < 0 then rem = 0 end
    return rem, cd
end
local function TAUNT_RecordCast(playerName, spellName)
    if not tauntCD[playerName] then tauntCD[playerName] = {} end
    tauntCD[playerName][spellName] = GetTime()
end
-- Returns list of {spellName, remaining, cd, aoe} for a given player+class
local function TAUNT_GetForPlayer(playerName, class)
    local out = {}
    if not class then return out end
    local upperClass = string.upper(class)
    for _,ts in ipairs(TAUNT_SPELLS) do
        if string.upper(ts.class) == upperClass then
            local rem, cd = TAUNT_GetCDInfo(playerName, ts.name)
            table.insert(out, {name=ts.name, remaining=rem, cd=cd, aoe=ts.aoe, icon=ts.icon})
        end
    end
    return out
end
-------------------------------------------------------------------------------
-- FEARWARD COOLDOWN TRACKING
-------------------------------------------------------------------------------
local FW_CD_FULL  = 30   -- Fear Ward cooldown in seconds (vanilla 1.12: 30 sec)
local FW_ICON     = "Interface\\Icons\\Spell_Holy_Excorcism"
local fwCD        = {}   -- [priestName] = GetTime() of last cast
local FW_ALERT_SHOWN = {}
local function FW_GetCDRemaining(priestName)
    local t = fwCD[priestName]
    if not t then return 0 end
    local rem = FW_CD_FULL - (GetTime() - t)
    return rem > 0 and rem or 0
end
local function FW_RecordCast(priestName)
    fwCD[priestName] = GetTime()
    FW_ALERT_SHOWN[priestName] = nil
end
-- Broadcast FW cast to raid
local function FW_BroadcastCast(priestName)
    local chan = GetChannel()
    if chan then pcall(SendAddonMessage, COMM_PREFIX, "FW_CAST;"..priestName, chan) end
end
-------------------------------------------------------------------------------
-- SERIALIZATION
-------------------------------------------------------------------------------
local function SplitStr(str, sep)
    local result = {}
    local i, last, len = 1, 1, string.len(str)
    while i <= len do
        if string.sub(str,i,i) == sep then
            local part = string.sub(str,last,i-1)
            if part ~= "" then table.insert(result,part) end
            last = i+1
        end
        i = i+1
    end
    local part = string.sub(str,last)
    if part ~= "" then table.insert(result,part) end
    return result
end
local function Serialize(tmpl)
    -- roster: name:class:tags (MT/OT/OOT/V)
    local rosterParts = {}
    for pname,pdata in pairs(tmpl.roster or {}) do
        local safe = string.gsub(pname,"[|~;:,^=]","_")
        local tags = (pdata.tagMT  and "MT"  or "")
                  ..(pdata.tagOT  and "OT"  or "")
                  ..(pdata.tagOOT and "OOT" or "")
                  ..(pdata.tagV   and "V"   or "")
        table.insert(rosterParts, safe..":"..(pdata.class or "")..":"..tags)
    end
    -- tanks: name;targetType:targetValue:markIndex
    local tankParts = {}
    for _,t in ipairs(tmpl.tanks or {}) do
        local safeName = string.gsub(t.name or "","[|~;:,^=]","_")
        local safeVal  = string.gsub(t.targetValue or "","[|~;:,^=]","_")
        table.insert(tankParts, safeName..";"
            ..(t.targetType or "")..":" ..safeVal..":"
            ..tostring(t.markIndex or 0))
    end
    -- fw: tank1^p1^p2|tank2^p3^p4  (each slot separated by |, within slot ^ separates tank from priests)
    local fwSlots = {}
    for _,slot in ipairs((tmpl.fw and tmpl.fw.tanks) or {}) do
        local parts = {}
        table.insert(parts, string.gsub(slot.tankName or "","[|~;:,^=]","_"))
        for _,p in ipairs(slot.queue or {}) do
            table.insert(parts, string.gsub(p,"[|~;:,^=]","_"))
        end
        table.insert(fwSlots, table.concat(parts,"^"))
    end
    -- cc: name;spell:targetType:targetValue:markIndex
    local ccParts = {}
    for _,ce in ipairs(tmpl.cc or {}) do
        local safeName = (string.gsub(ce.name or "","[|~;:,^=]","_"))
        local safeSpell = (string.gsub(ce.spell or "","[|~;:,^=]","_"))
        local safeVal   = (string.gsub(ce.targetValue or "","[|~;:,^=]","_"))
        table.insert(ccParts, safeName..";"
            ..safeSpell..":"
            ..(ce.targetType or "")..":"
            ..safeVal..":"
            ..tostring(ce.markIndex or 0))
    end
    return "ta1~"
        ..string.gsub(tmpl.name or "","[|~;:,^=]","_").."~"
        ..table.concat(rosterParts,"|").."~"
        ..table.concat(tankParts,"|").."~"
        ..table.concat(fwSlots,"|").."~"
        ..table.concat(ccParts,"|")
end
local function Deserialize(str)
    if not str then return nil end
    local parts = SplitStr(str,"~")
    if not parts[1] or parts[1] ~= "ta1" then return nil end
    local tmpl = NewTemplate(parts[2] or "")
    -- roster
    if parts[3] and parts[3] ~= "" then
        for _,entry in ipairs(SplitStr(parts[3],"|")) do
            local ep = SplitStr(entry,":")
            if ep[1] and ep[1] ~= "" then
                local tags = ep[3] or ""
                tmpl.roster[ep[1]] = {
                    class  = ep[2] or "",
                    tagMT  = string.find(tags,"MT")  ~= nil or nil,
                    tagOT  = string.find(tags,"OT")  ~= nil or nil,
                    tagOOT = string.find(tags,"OOT") ~= nil or nil,
                    tagV   = string.find(tags,"V")   ~= nil or nil,
                }
            end
        end
    end
    -- tanks
    if parts[4] and parts[4] ~= "" then
        for _,entry in ipairs(SplitStr(parts[4],"|")) do
            local semi = string.find(entry,";")
            if semi then
                local tname = string.sub(entry,1,semi-1)
                local rest  = SplitStr(string.sub(entry,semi+1),":")
                table.insert(tmpl.tanks, {
                    name        = tname,
                    targetType  = rest[1] or "",
                    targetValue = rest[2] or "",
                    markIndex   = tonumber(rest[3]) or 0,
                })
            end
        end
    end
    -- fw
    if parts[5] and parts[5] ~= "" then
        tmpl.fw = {tanks={}}
        for _,slotStr in ipairs(SplitStr(parts[5],"|")) do
            if slotStr ~= "" then
                local fp = SplitStr(slotStr,"^")
                local tankN = fp[1] or ""
                if tankN ~= "" then
                    local queue = {}
                    for i=2,table.getn(fp) do
                        if fp[i] ~= "" then table.insert(queue, fp[i]) end
                    end
                    table.insert(tmpl.fw.tanks, {tankName=tankN, queue=queue})
                end
            end
        end
    end
    -- cc
    if parts[6] and parts[6] ~= "" then
        for _,entry in ipairs(SplitStr(parts[6],"|")) do
            local semi = string.find(entry,";")
            if semi then
                local cname = string.sub(entry,1,semi-1)
                local rest  = SplitStr(string.sub(entry,semi+1),":")
                -- rest: spell:targetType:targetValue:markIndex
                if cname ~= "" and rest[1] and rest[1] ~= "" then
                    table.insert(tmpl.cc, {
                        name        = cname,
                        spell       = rest[1] or "",
                        targetType  = rest[2] or "",
                        targetValue = rest[3] or "",
                        markIndex   = tonumber(rest[4]) or 0,
                    })
                end
            end
        end
    end
    return tmpl
end
-------------------------------------------------------------------------------
-- FRAME REFERENCES (forward declarations)
-------------------------------------------------------------------------------
local mainFrame        = nil
local rosterFrame      = nil
local assignFrame      = nil   -- personal window (tank / priest / viewer)
local fwFrame          = nil   -- Fearward queue manager window
local combatPanel      = nil   -- in-combat marker panel
local optionsFrame     = nil
local alertFrame       = nil
local fwAlertFrame     = nil
-- Forward function declarations (defined later)
local UpdateAssignFrame
local UpdateTankAssignFrame
local UpdatePriestAssignFrame
local RebuildMainGrid
local RebuildRosterRows
local CP_RefreshMarkIndicators
local GetTanksSorted
local ShowPatternDropdown
local FW_BroadcastAssignments
-- ESC stack
local openStack = {}
local function UpdateEscFrame()
    local toRemove = {
        ["TankAssignMainFrame"]    = true,
        ["TankAssignOptionsFrame"] = true,
        ["TankAssignRosterFrame"]  = true,
    }
    local i = 1
    while i <= table.getn(UISpecialFrames) do
        if toRemove[UISpecialFrames[i]] then
            table.remove(UISpecialFrames, i)
        else i = i+1 end
    end
    for j = table.getn(openStack), 1, -1 do
        local f = openStack[j]
        if f and f:IsShown() and f:GetName() then
            table.insert(UISpecialFrames, f:GetName())
            return
        end
        table.remove(openStack, j)
    end
end
local function PushWindow(f)
    for i = table.getn(openStack), 1, -1 do
        if openStack[i] == f then table.remove(openStack, i) end
    end
    table.insert(openStack, f)
    UpdateEscFrame()
end
local function HookFrameHide(f)
    local orig = f:GetScript("OnHide")
    f:SetScript("OnHide", function()
        if orig then orig() end
        UpdateEscFrame()
    end)
end
-------------------------------------------------------------------------------
-- TOOLTIP HELPER
-------------------------------------------------------------------------------
local function AddTooltip(frame, text)
    frame:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
-------------------------------------------------------------------------------
-- DROPDOWN
-------------------------------------------------------------------------------
local dropdownFrame        = nil
local activeDropdownAnchor = nil
local activeCCMarkIdx      = nil  -- track which mark has CC dropdown open
local TA_openDropdowns = {}
local function TA_CloseAllDropdowns()
    for _,f in ipairs(TA_openDropdowns) do
        if f and f:IsShown() then f:Hide() end
    end
    TA_openDropdowns     = {}
    activeDropdownAnchor = nil
    activeCCMarkIdx      = nil
end
local function CloseDropdown()
    TA_CloseAllDropdowns()
end
local function ShowDropdown(anchorFrame, items, onSelect, width)
    -- Toggle: same button same click closes
    if dropdownFrame and dropdownFrame:IsShown() and activeDropdownAnchor == anchorFrame then
        TA_CloseAllDropdowns()
        return
    end
    TA_CloseAllDropdowns()
    if not dropdownFrame then
        dropdownFrame = CreateFrame("Frame","TankAssignDropdownFrame",UIParent)
        dropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        dropdownFrame:EnableMouse(true)
        dropdownFrame:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true, tileSize=8, edgeSize=8,
            insets={left=2,right=2,top=2,bottom=2}
        })
        dropdownFrame:SetBackdropColor(0.06,0.06,0.10,0.97)
        dropdownFrame:SetBackdropBorderColor(0.4,0.4,0.6,0.9)
        dropdownFrame.buttons = {}
    end
    local f = dropdownFrame
    activeDropdownAnchor = anchorFrame
    dropdownFrame:SetFrameLevel(50)
    table.insert(TA_openDropdowns, f)
    for _,b in ipairs(f.buttons) do b:Hide() end
    local itemH = 22
    local pad   = 4
    local w     = width or 160
    local h     = table.getn(items)*itemH + pad*2
    if h < 24 then h = 24 end
    f:SetWidth(w)
    f:SetHeight(h)
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    for i,item in ipairs(items) do
        local btn = f.buttons[i]
        if not btn then
            btn = CreateFrame("Button",nil,f)
            btn:SetHeight(itemH)
            btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            btn:GetHighlightTexture():SetAlpha(0.4)
            local ic = btn:CreateTexture(nil,"OVERLAY")
            ic:SetWidth(14); ic:SetHeight(14)
            ic:SetPoint("LEFT",btn,"LEFT",4,0)
            btn.icon = ic
            local fs = btn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            fs:SetPoint("LEFT",btn,"LEFT",22,0)
            fs:SetPoint("RIGHT",btn,"RIGHT",-4,0)
            fs:SetJustifyH("LEFT")
            btn.label = fs
            btn.markIconTextures = {}
            f.buttons[i] = btn
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",f,"TOPLEFT",pad,-(pad+(i-1)*itemH))
        btn:SetWidth(w-pad*2)
        btn:Show()
        -- Hide previous mark icons
        for _,t in ipairs(btn.markIconTextures or {}) do t:Hide() end
        btn.markIconTextures = {}
        -- Right-side mark icons (assigned marks for this tank)
        local rightOffset = 4
        if item.markIcons then
            for _,tex in ipairs(item.markIcons) do
                local sz = 14
                local mic = btn:CreateTexture(nil,"OVERLAY")
                mic:SetWidth(sz); mic:SetHeight(sz)
                mic:SetPoint("RIGHT",btn,"RIGHT",-rightOffset,0)
                mic:SetTexture(tex)
                mic:Show()
                rightOffset = rightOffset + sz + 2
                table.insert(btn.markIconTextures, mic)
            end
        end
        btn.label:ClearAllPoints()
        btn.label:SetPoint("RIGHT",btn,"RIGHT",-(rightOffset),0)
        if item.icon then
            btn.icon:SetTexture(item.icon)
            btn.icon:SetWidth(16); btn.icon:SetHeight(16)
            btn.icon:Show()
            btn.label:SetPoint("LEFT",btn,"LEFT",24,0)
        else
            btn.icon:SetTexture(nil)
            btn.icon:Hide()
            btn.label:SetPoint("LEFT",btn,"LEFT",6,0)
        end
        if item.r then btn.label:SetTextColor(item.r,item.g,item.b)
        else btn.label:SetTextColor(1,1,1) end
        btn.label:SetText(item.text or "")
        local capturedItem = item
        btn:SetScript("OnClick",function()
            CloseDropdown()
            onSelect(capturedItem)
        end)
    end
    f:Show()
end
-- Two-level dropdown for CC assignment:
-- Level 1: list of CC spells (filtered to classes present in raid)
-- Level 2: list of players of the matching class
local subDropdownFrame = nil
local function CloseSubDropdown()
    if subDropdownFrame and subDropdownFrame:IsShown() then
        subDropdownFrame:Hide()
    end
end
local function ShowCCDropdown(anchorBtn, markIdx)
    -- Toggle: ПКМ на ту же метку закрывает дропдаун
    if subDropdownFrame and subDropdownFrame:IsShown()
        and subDropdownFrame._markIdx == markIdx then
        TA_CloseAllDropdowns()
        return
    end
    TA_CloseAllDropdowns()
    local tmpl = GetActiveTemplate()
    if not tmpl then return end
    if not tmpl.cc then tmpl.cc = {} end
    -- Build roster class lookup
    local classByName = {}
    for pname, pdata in pairs(tmpl.roster or {}) do
        classByName[pname] = pdata.class and string.upper(pdata.class) or nil
    end
    -- Already assigned CC for this mark: {[spell] = playerName}
    local alreadyCC = {}
    for _,entry in ipairs(tmpl.cc or {}) do
        if entry.targetType == TYPE_MARK and entry.markIndex == markIdx then
            alreadyCC[entry.spell] = entry.name
        end
    end
    -- Level 1 items: spells that have at least one matching player in raid
    local spellItems = {}
    for _,ccEntry in ipairs(CC_SPELLS) do
        local spell     = ccEntry.spell
        local reqClass  = ccEntry.class
        local players   = {}
        for pname, cls in pairs(classByName) do
            if cls == reqClass then
                table.insert(players, pname)
            end
        end
        table.sort(players)
        if table.getn(players) > 0 then
            table.insert(spellItems, {
                spell   = spell,
                players = players,
                assigned= alreadyCC[spell] or nil,
            })
        end
    end
    -- Always add Clear Mark at bottom
    table.insert(spellItems, {
        spell       = "Clear Mark",
        players     = {},
        isClearMark = true,
    })
    -- Close existing dropdowns
    CloseDropdown()
    CloseSubDropdown()
    -- Create level-1 frame if needed
    if not subDropdownFrame then
        subDropdownFrame = CreateFrame("Frame","TankAssignCCDropdown",UIParent)
        subDropdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        subDropdownFrame:SetFrameLevel(50)
        subDropdownFrame:EnableMouse(true)
        subDropdownFrame:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true, tileSize=8, edgeSize=8,
            insets={left=2,right=2,top=2,bottom=2}
        })
        subDropdownFrame:SetBackdropColor(0.06,0.06,0.10,0.97)
        subDropdownFrame:SetBackdropBorderColor(0.4,0.4,0.6,0.9)
        subDropdownFrame.buttons = {}
    end
    local f1       = subDropdownFrame
    local itemH    = 22
    local pad      = 4
    local w1       = 160
    f1:SetWidth(w1)
    f1:SetHeight(table.getn(spellItems)*itemH + pad*2)
    f1:ClearAllPoints()
    f1:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    -- Level-2 player frame (reused)
    local f2 = f1.subFrame
    if not f2 then
        f2 = CreateFrame("Frame", nil, UIParent)
        f2:SetFrameStrata("FULLSCREEN_DIALOG")
        f2:SetFrameLevel(52)
        f2:EnableMouse(true)
        f2:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true, tileSize=8, edgeSize=8,
            insets={left=2,right=2,top=2,bottom=2}
        })
        f2:SetBackdropColor(0.06,0.06,0.10,0.97)
        f2:SetBackdropBorderColor(0.4,0.4,0.6,0.9)
        f2.buttons = {}
        f2:Hide()
        f1.subFrame = f2
    end
    -- Hide old buttons
    for _,b in ipairs(f1.buttons) do b:Hide() end
    for _,b in ipairs(f2.buttons) do b:Hide() end
    local mobName = UnitExists("target") and UnitName("target") or nil
    for i, si in ipairs(spellItems) do
        local btn1 = f1.buttons[i]
        if not btn1 then
            btn1 = CreateFrame("Button", nil, f1)
            btn1:SetHeight(itemH)
            btn1:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            btn1:GetHighlightTexture():SetAlpha(0.4)
            local lbl = btn1:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            lbl:SetPoint("LEFT",btn1,"LEFT",6,0)
            lbl:SetPoint("RIGHT",btn1,"RIGHT",-18,0)
            lbl:SetJustifyH("LEFT")
            btn1.label = lbl
            local arrow = btn1:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            arrow:SetPoint("RIGHT",btn1,"RIGHT",-4,0)
            arrow:SetTextColor(0.7,0.7,0.7)
            arrow:SetText(">")
            f1.buttons[i] = btn1
        end
        btn1:ClearAllPoints()
        btn1:SetPoint("TOPLEFT",f1,"TOPLEFT",pad,-(pad+(i-1)*itemH))
        btn1:SetWidth(w1 - pad*2)
        btn1:Show()
        -- Color: red for Clear Mark, green if assigned, white if not
        local assigned = si.assigned
        if si.isClearMark then
            btn1.label:SetTextColor(1, 0.3, 0.3)
            btn1.label:SetText(si.spell)
        elseif assigned then
            btn1.label:SetTextColor(0.2,1,0.2)
            btn1.label:SetText("[X] "..si.spell)
        else
            btn1.label:SetTextColor(1,1,1)
            btn1.label:SetText(si.spell)
        end
        local capturedSI    = si
        local capturedMarkI = markIdx
        local capturedMob   = mobName
        -- Helper: show level-2 player list for this spell
        local function ShowLevel2()
            if capturedSI.isClearMark then return end
            local players = capturedSI.players
            if table.getn(players) == 0 then return end
            local w2  = 140
            f2:SetWidth(w2)
            f2:SetHeight(table.getn(players)*itemH + pad*2)
            f2:ClearAllPoints()
            f2:SetPoint("TOPLEFT", btn1, "TOPRIGHT", 2, 0)
            for _,b in ipairs(f2.buttons) do b:Hide() end
            -- Find currently assigned player for this spell+mark
            local assignedPlayer = nil
            local t4 = GetActiveTemplate()
            if t4 and t4.cc then
                for _,ex in ipairs(t4.cc) do
                    if ex.spell == capturedSI.spell
                        and ex.targetType == TYPE_MARK
                        and ex.markIndex  == capturedMarkI then
                        assignedPlayer = ex.name
                        break
                    end
                end
            end
            for j, pname in ipairs(players) do
                local btn2 = f2.buttons[j]
                if not btn2 then
                    btn2 = CreateFrame("Button",nil,f2)
                    btn2:SetHeight(itemH)
                    btn2:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                    btn2:GetHighlightTexture():SetAlpha(0.4)
                    local lbl2 = btn2:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                    lbl2:SetPoint("LEFT",btn2,"LEFT",6,0)
                    lbl2:SetPoint("RIGHT",btn2,"RIGHT",-4,0)
                    lbl2:SetJustifyH("LEFT")
                    btn2.label = lbl2
                    f2.buttons[j] = btn2
                end
                btn2:ClearAllPoints()
                btn2:SetPoint("TOPLEFT",f2,"TOPLEFT",pad,-(pad+(j-1)*itemH))
                btn2:SetWidth(w2-pad*2)
                btn2:Show()
                local cls = t4 and t4.roster and t4.roster[pname] and t4.roster[pname].class
                local cr,cg,cb = GetClassColor(cls)
                local isAssignedPlayer = (assignedPlayer == pname)
                if isAssignedPlayer then
                    btn2.label:SetTextColor(0.2, 1, 0.2)
                    btn2.label:SetText("[X] "..pname)
                else
                    btn2.label:SetTextColor(cr,cg,cb)
                    btn2.label:SetText(pname)
                end
                local capturedPlayer = pname
                local capturedSpell  = capturedSI.spell
                btn2:SetScript("OnClick", function()
                    local t5 = GetActiveTemplate()
                    if not t5 then return end
                    if not t5.cc then t5.cc = {} end
                    local filtered2 = {}
                    for _,ex in ipairs(t5.cc) do
                        if not (ex.spell == capturedSpell
                            and ex.targetType == TYPE_MARK
                            and ex.markIndex  == capturedMarkI) then
                            table.insert(filtered2, ex)
                        end
                    end
                    table.insert(filtered2, {
                        name        = capturedPlayer,
                        spell       = capturedSpell,
                        targetType  = TYPE_MARK,
                        targetValue = MARK_ICONS[capturedMarkI]
                                      and MARK_ICONS[capturedMarkI].name
                                      or ("Mark "..capturedMarkI),
                        markIndex   = capturedMarkI,
                    })
                    t5.cc = filtered2
                    TankAssign_SyncTemplate()
                    UpdateAssignFrame()
                    CP_RefreshMarkIndicators()
                    f2:Hide(); f1:Hide()
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cff00ccffTankAssign:|r "..capturedPlayer
                        .." assigned "..capturedSpell
                        .." on "..(MARK_ICONS[capturedMarkI]
                            and MARK_ICONS[capturedMarkI].name
                            or "Mark "..capturedMarkI))
                end)
            end
            f2:Show()
        end
        -- OnEnter: show level-2 for all spells, hide f2 only for Clear Mark
        btn1:SetScript("OnEnter", function()
            if capturedSI.isClearMark then
                f2:Hide()
            else
                ShowLevel2()
            end
        end)
        btn1:SetScript("OnClick", function()
            -- Clear Mark
            if capturedSI.isClearMark then
                if UnitExists("target") and HasEditorRights() then
                    if GetRaidTargetIndex("target") == capturedMarkI then
                        SetRaidTarget("target", 0)
                    end
                end
                local t3 = GetActiveTemplate()
                if t3 then
                    local ft = {}
                    for _,ex in ipairs(t3.tanks or {}) do
                        if not (ex.targetType == TYPE_MARK
                            and ex.markIndex == capturedMarkI) then
                            table.insert(ft, ex)
                        end
                    end
                    t3.tanks = ft
                    local fc = {}
                    for _,ex in ipairs(t3.cc or {}) do
                        if not (ex.targetType == TYPE_MARK
                            and ex.markIndex == capturedMarkI) then
                            table.insert(fc, ex)
                        end
                    end
                    t3.cc = fc
                    TankAssign_SyncTemplate()
                    UpdateAssignFrame()
                    CP_RefreshMarkIndicators()
                end
                f2:Hide(); f1:Hide()
                return
            end
            -- [X] remove assignment
            if capturedSI.assigned then
                local t3 = GetActiveTemplate()
                if not t3 then return end
                if not t3.cc then t3.cc = {} end
                local filtered = {}
                for _,ex in ipairs(t3.cc) do
                    if not (ex.spell == capturedSI.spell
                        and ex.targetType == TYPE_MARK
                        and ex.markIndex  == capturedMarkI) then
                        table.insert(filtered, ex)
                    end
                end
                t3.cc = filtered
                TankAssign_SyncTemplate()
                UpdateAssignFrame()
                CP_RefreshMarkIndicators()
                f2:Hide(); f1:Hide()
                return
            end
            -- Regular spell: also open level-2 on click (in case hover didn't work)
            ShowLevel2()
        end)
    end
    table.insert(TA_openDropdowns, f1)
    table.insert(TA_openDropdowns, f2)
    f1._markIdx = markIdx
    f1:Show()
end
-------------------------------------------------------------------------------
-- STATIC POPUPS
-------------------------------------------------------------------------------
local _nameEditRef = nil
local function InitStaticPopups()
    StaticPopupDialogs["TANKASSIGN_CONFIRM_DELETE"] = {
        text        = "Delete template '%s'?",
        button1     = "Delete",
        button2     = "Cancel",
        OnAccept    = function()
            local name = _nameEditRef and _nameEditRef:GetText() or ""
            if name ~= "" and TankAssignDB.templates[name] then
                TankAssignDB.templates[name] = nil
                if TankAssignDB.activeTemplate == name then
                    TankAssignDB.activeTemplate = nil
                    currentTemplate = NewTemplate("")
                end
                DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffTankAssign:|r Template '"..name.."' deleted.")
                if mainFrame and mainFrame:IsShown() then RebuildMainGrid() end
            end
        end,
        timeout     = 0,
        whileDead   = false,
        hideOnEscape= true,
    }
    StaticPopupDialogs["TANKASSIGN_UNSAVED"] = {
        text     = "Current template has unsaved changes. Continue?",
        button1  = "Yes",
        button2  = "Cancel",
        OnAccept = function()
            currentTemplate = NewTemplate("")
            if _nameEditRef then _nameEditRef:SetText("") end
            if mainFrame and mainFrame:IsShown() then RebuildMainGrid() end
            UpdateAssignFrame()
        end,
        timeout     = 0,
        whileDead   = false,
        hideOnEscape= true,
    }
end
-------------------------------------------------------------------------------
-- DEATH ALERT SYSTEM  (mirrors HealAssign — tanks instead of healers)
-------------------------------------------------------------------------------
local deadTanks = {}  -- [{name, targets, time}]
local function CreateAlertFrame()
    if alertFrame then return end
    alertFrame = CreateFrame("Frame","TankAssignAlertFrame",UIParent)
    alertFrame:SetWidth(600)
    alertFrame:SetHeight(44)
    alertFrame:SetPoint("TOP",UIParent,"TOP",0,-120)
    alertFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    alertFrame:Hide()
    alertFrame:SetBackdrop({
        bgFile  ="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=8,edgeSize=10,
        insets={left=4,right=4,top=4,bottom=4}
    })
    alertFrame:SetBackdropColor(0.3,0,0,0.92)
    alertFrame:SetBackdropBorderColor(1,0.1,0.1,1)
    local header = alertFrame:CreateFontString(nil,"OVERLAY","GameFontNormalHuge")
    header:SetFont("Fonts\\FRIZQT__.TTF",22,"OUTLINE")
    header:SetPoint("CENTER",alertFrame,"CENTER",0,0)
    header:SetTextColor(1,0.1,0.1)
    alertFrame.header = header
    alertFrame.elapsed  = 0
    alertFrame.duration = 5
    alertFrame:SetScript("OnUpdate",function()
        if not alertFrame.active then return end
        alertFrame.elapsed = alertFrame.elapsed + arg1
        local pct = alertFrame.elapsed / alertFrame.duration
        if pct >= 1 then
            alertFrame.active = false
            alertFrame:Hide()
        else
            local alpha = 1
            if pct > 0.6 then alpha = 1 - (pct-0.6)/0.4 end
            alertFrame:SetAlpha(alpha)
        end
    end)
end
local function RefreshAlertFrame()
    if not alertFrame then return end
    local now, alive = GetTime(), {}
    for _,d in ipairs(deadTanks) do
        if now - d.time < 15 then table.insert(alive,d) end
    end
    deadTanks = alive
    if table.getn(deadTanks) == 0 then alertFrame:Hide() end
end
local function TriggerTankDeath(tankName, assignment)
    local myName = UnitName("player")
    local tmpl   = GetActiveTemplate()
    -- Track in deadTanks
    local found = false
    for _,d in ipairs(deadTanks) do
        if d.name == tankName then
            d.time = GetTime()
            d.assignment = DeepCopy(assignment or {})
            found = true break
        end
    end
    if not found then
        table.insert(deadTanks, {name=tankName,
            assignment=DeepCopy(assignment or {}), time=GetTime()})
    end
    -- Only show alert to tanks and viewers
    local shouldShow = false
    if tmpl and tmpl.roster and tmpl.roster[myName] then
        local me = tmpl.roster[myName]
        if me.tagMT or me.tagOT or me.tagOOT or me.tagV then shouldShow = true end
    end
    if HasEditorRights and HasEditorRights() then shouldShow = true end
    if not shouldShow then return end
    PlaySoundFile("Interface\\AddOns\\TankAssign\\Sounds\\bucket.wav")
    if not alertFrame then CreateAlertFrame() end
    local asgn = assignment or {}
    local targetText = "No assignment"
    if asgn.targetValue and asgn.targetValue ~= "" then
        targetText = "Unattended: "..asgn.targetValue
    end
    alertFrame.header:SetText("TANK DEAD:  "..tankName.."   "..targetText)
    alertFrame.duration = 7
    alertFrame.elapsed  = 0
    alertFrame.active   = true
    alertFrame:SetAlpha(1)
    alertFrame:Show()
end
local function RemoveDeadTank(name)
    local newDead, changed = {}, false
    for _,d in ipairs(deadTanks) do
        if d.name == name then changed = true
        else table.insert(newDead, d) end
    end
    if changed then
        deadTanks = newDead
        RefreshAlertFrame()
        UpdateAssignFrame()
    end
end
local function CheckAllRezd()
    if table.getn(deadTanks) == 0 then return end
    local toRez = {}
    for _,d in ipairs(deadTanks) do
        for ri=1,GetNumRaidMembers() do
            local rname = UnitName("raid"..ri)
            if rname == d.name then
                if UnitHealth("raid"..ri) and UnitHealth("raid"..ri) > 0 then
                    table.insert(toRez, d.name)
                end
                break
            end
        end
        if UnitName("player") == d.name and UnitHealth("player") > 0 then
            table.insert(toRez, d.name)
        end
    end
    for _,name in ipairs(toRez) do RemoveDeadTank(name) end
end
-------------------------------------------------------------------------------
-- FEARWARD ALERT (BigWigs-style, green — for priest personal window)
-------------------------------------------------------------------------------
local function CreateFWAlertFrame()
    if fwAlertFrame then return end
    fwAlertFrame = CreateFrame("Frame","TankAssignFWAlert",UIParent)
    fwAlertFrame:SetWidth(560)
    fwAlertFrame:SetHeight(44)
    fwAlertFrame:SetPoint("TOP",UIParent,"TOP",0,-170)
    fwAlertFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    fwAlertFrame:Hide()
    fwAlertFrame:SetBackdrop({
        bgFile  ="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=8,edgeSize=10,
        insets={left=4,right=4,top=4,bottom=4}
    })
    fwAlertFrame:SetBackdropColor(0,0.2,0,0.92)
    fwAlertFrame:SetBackdropBorderColor(0.1,1,0.1,1)
    local txt = fwAlertFrame:CreateFontString(nil,"OVERLAY")
    txt:SetFont("Fonts\\FRIZQT__.TTF",22,"OUTLINE")
    txt:SetPoint("CENTER",fwAlertFrame,"CENTER",0,0)
    txt:SetTextColor(0.1,1,0.1)
    fwAlertFrame.txt = txt
    fwAlertFrame.elapsed = 0
    fwAlertFrame:SetScript("OnUpdate",function()
        fwAlertFrame.elapsed = fwAlertFrame.elapsed + arg1
        local pct = fwAlertFrame.elapsed / 7
        if pct >= 1 then
            fwAlertFrame:Hide()
            fwAlertFrame.elapsed = 0
        elseif pct > 0.6 then
            fwAlertFrame:SetAlpha(1-(pct-0.6)/0.4)
        else
            fwAlertFrame:SetAlpha(1)
        end
    end)
end
local function ShowFWAlert(tankName)
    if not fwAlertFrame then CreateFWAlertFrame() end
    fwAlertFrame.txt:SetText("FEAR WARD  →  "..tankName)
    fwAlertFrame.elapsed = 0
    fwAlertFrame:SetAlpha(1)
    fwAlertFrame:Show()
end
-------------------------------------------------------------------------------
-- PERSONAL ASSIGN FRAME  (tank window + priest window + viewer window)
-------------------------------------------------------------------------------
local function CreateAssignFrame()
    if assignFrame then return end
    assignFrame = CreateFrame("Frame","TankAssignAssignFrame",UIParent)
    assignFrame:SetWidth(220)
    assignFrame:SetHeight(100)
    assignFrame:SetPoint("CENTER",UIParent,"CENTER",400,0)
    assignFrame:SetMovable(true)
    assignFrame:EnableMouse(true)
    assignFrame:RegisterForDrag("LeftButton")
    assignFrame:SetScript("OnDragStart",function() this:StartMoving() end)
    assignFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    assignFrame:SetFrameStrata("MEDIUM")
    assignFrame:SetBackdrop({
        bgFile   ="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile ="Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true,tileSize=8,edgeSize=12,
        insets={left=4,right=4,top=4,bottom=4}
    })
    local _a = (TankAssignDB and TankAssignDB.options and TankAssignDB.options.windowAlpha) or 0.95
    assignFrame:SetBackdropColor(0.05,0.05,0.1,_a)
    assignFrame:SetBackdropBorderColor(0.3,0.6,1,0.8)
    assignFrame.content = {}
    assignFrame:Hide()
    local optBtn = CreateFrame("Button",nil,assignFrame,"UIPanelButtonTemplate")
    optBtn:SetWidth(24); optBtn:SetHeight(16)
    optBtn:SetPoint("TOPRIGHT",assignFrame,"TOPRIGHT",-4,-4)
    optBtn:SetText("O")
    optBtn:SetScript("OnClick",function()
        if optionsFrame and optionsFrame:IsShown() then optionsFrame:Hide()
        else TankAssign_OpenOptions() end
    end)
end
UpdateAssignFrame = function()
    if not assignFrame then return end
    for _,c in ipairs(assignFrame.content or {}) do c:Hide() end
    assignFrame.content = {}
    local inRaid      = GetNumRaidMembers() > 0
    local showOutside = TankAssignDB and TankAssignDB.options and TankAssignDB.options.showAssignFrame
    if not inRaid and not showOutside then assignFrame:Hide() return end
    if not TA_ShouldShow() then assignFrame:Hide() return end
    local myName   = UnitName("player")
    local tmpl     = GetActiveTemplate()
    local fontSize = (TankAssignDB.options and TankAssignDB.options.fontSize) or 12
    local myPdata  = tmpl and tmpl.roster and tmpl.roster[myName]
    local isTank   = myPdata and (myPdata.tagMT or myPdata.tagOT or myPdata.tagOOT)
    local isPriest = myPdata and myPdata.class == "PRIEST"
    local isViewer = myPdata and myPdata.tagV
    -- Check if this player has any CC assignments
    local myCCAssignments = {}
    if tmpl then
        for _,ce in ipairs(tmpl.cc or {}) do
            if ce.name == myName then
                table.insert(myCCAssignments, ce)
            end
        end
    end
    local isCC = table.getn(myCCAssignments) > 0
    if not isTank and not isPriest and not isViewer and not isCC then
        assignFrame:Hide() return
    end
    -- Layout helpers
    local PAD    = 6
    local rowH   = fontSize + 4
    local rowStep= fontSize + 5
    local titleH = fontSize + 8
    local yOff   = -(titleH + 2)
    local frameW
    if isViewer then
        frameW = math.max(200, math.min(380, fontSize * 18))
    else
        frameW = math.max(150, math.min(280, fontSize * 14))
    end
    assignFrame:SetWidth(frameW)
    local innerW = frameW - PAD*2
    local function AddContent(c) table.insert(assignFrame.content, c) end
    local function AddHeader(text, r,g,b, bgMul)
        bgMul = bgMul or 0.18
        local hdr = CreateFrame("Frame",nil,assignFrame)
        hdr:SetPoint("TOPLEFT",assignFrame,"TOPLEFT",PAD,yOff)
        hdr:SetWidth(innerW); hdr:SetHeight(rowH+2)
        hdr:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
            insets={left=0,right=0,top=0,bottom=0}})
        hdr:SetBackdropColor(r*bgMul,g*bgMul,b*bgMul,0.7)
        AddContent(hdr)
        local fs = hdr:CreateFontString(nil,"OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF",fontSize,"OUTLINE")
        fs:SetPoint("LEFT",hdr,"LEFT",0,0); fs:SetPoint("RIGHT",hdr,"RIGHT",0,0)
        fs:SetJustifyH("CENTER"); fs:SetTextColor(r,g,b); fs:SetText(text)
        yOff = yOff - (rowH+4)
    end
    local function AddBlock(text, r,g,b, extraText, er,eg,eb, markIcon)
        local blockH = rowStep + 6
        local block = CreateFrame("Frame",nil,assignFrame)
        block:SetPoint("TOPLEFT",assignFrame,"TOPLEFT",PAD,yOff)
        block:SetWidth(innerW); block:SetHeight(blockH)
        block:SetBackdrop({
            bgFile   ="Interface\\Buttons\\WHITE8X8",
            edgeFile ="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=8,edgeSize=8,
            insets={left=2,right=2,top=2,bottom=2}
        })
        block:SetBackdropColor(r*0.05,g*0.05,b*0.05,0.4)
        block:SetBackdropBorderColor(r*0.5,g*0.5,b*0.5,0.6)
        AddContent(block)
        local iconW = 0
        if markIcon then
            local sz = math.max(10, fontSize+2)
            local ic = block:CreateTexture(nil,"OVERLAY")
            ic:SetWidth(sz); ic:SetHeight(sz)
            ic:SetPoint("TOPLEFT",block,"TOPLEFT",4,-(blockH/2 - sz/2))
            ic:SetTexture(markIcon)
            iconW = sz + 6
        end
        local fs = block:CreateFontString(nil,"OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF",fontSize,"")
        fs:SetPoint("LEFT",block,"LEFT",6+iconW,0)
        fs:SetPoint("RIGHT",block,"RIGHT",-4,0)
        fs:SetHeight(blockH); fs:SetJustifyH("LEFT"); fs:SetJustifyV("MIDDLE")
        fs:SetTextColor(r,g,b); fs:SetText(text)
        if extraText then
            local fs2 = block:CreateFontString(nil,"OVERLAY")
            fs2:SetFont("Fonts\\FRIZQT__.TTF",math.max(8,fontSize-2),"")
            fs2:SetPoint("RIGHT",block,"RIGHT",-4,0)
            fs2:SetHeight(blockH); fs2:SetJustifyH("RIGHT"); fs2:SetJustifyV("MIDDLE")
            fs2:SetTextColor(er or 0.7,eg or 0.7,eb or 0.7)
            fs2:SetText(extraText)
        end
        yOff = yOff - blockH - 3
    end
    -- Taunt spell block: icon (with CD overlay) + spell name + CD text
    -- Copied from HealAssign innervate/rebirth block pattern
    local function AddTauntBlock(tankName, spellName, spellIcon, cdRem, tr,tg,tb)
        local ICON_SZ = math.max(18, math.min(32, math.floor(fontSize * 2.0)))
        local blockH  = ICON_SZ + 4
        local isReady = math.floor(cdRem) <= 0
        local block = CreateFrame("Frame",nil,assignFrame)
        block:SetPoint("TOPLEFT",assignFrame,"TOPLEFT",PAD,yOff)
        block:SetWidth(innerW); block:SetHeight(blockH)
        block:SetBackdrop({
            bgFile   ="Interface\\Buttons\\WHITE8X8",
            edgeFile ="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=8,edgeSize=8,
            insets={left=2,right=2,top=2,bottom=2}
        })
        block:SetBackdropColor(tr*0.05,tg*0.05,tb*0.05,0.4)
        block:SetBackdropBorderColor(tr*0.5,tg*0.5,tb*0.5,0.6)
        AddContent(block)
        -- Icon container (same as HealAssign)
        local iconCont = CreateFrame("Frame",nil,block)
        iconCont:SetWidth(ICON_SZ); iconCont:SetHeight(ICON_SZ)
        iconCont:SetPoint("LEFT",block,"LEFT",4,0)
        local iTex = iconCont:CreateTexture(nil,"BACKGROUND")
        iTex:SetAllPoints(iconCont)
        iTex:SetTexture(spellIcon or "Interface\\Icons\\Ability_Physical_Taunt")
        if isReady then
            iTex:SetVertexColor(1,1,1)
        else
            iTex:SetVertexColor(0.35,0.35,0.35)
        end
        -- CD text centered on icon
        local cdFSz = math.max(8, math.floor(fontSize * 0.85))
        local cdFS = iconCont:CreateFontString(nil,"OVERLAY")
        cdFS:SetFont("Fonts\\FRIZQT__.TTF",cdFSz,"OUTLINE")
        cdFS:SetPoint("CENTER",iconCont,"CENTER",0,0)
        cdFS:SetTextColor(1,1,0)
        if not isReady then
            if cdRem <= 90 then
                cdFS:SetText(math.ceil(cdRem).."s")
            else
                cdFS:SetText(math.ceil(cdRem/60).."m")
            end
        else
            cdFS:SetText("")
        end
        -- Spell name + tank name to the right of icon
        local nameFS = block:CreateFontString(nil,"OVERLAY")
        nameFS:SetFont("Fonts\\FRIZQT__.TTF",fontSize,"")
        nameFS:SetPoint("LEFT",block,"LEFT",ICON_SZ+10,0)
        nameFS:SetPoint("RIGHT",block,"RIGHT",-4,0)
        nameFS:SetHeight(blockH)
        nameFS:SetJustifyH("LEFT"); nameFS:SetJustifyV("MIDDLE")
        if isReady then
            nameFS:SetTextColor(tr,tg,tb)
        else
            nameFS:SetTextColor(tr*0.6,tg*0.6,tb*0.6)
        end
        if tankName and tankName ~= "" then
            nameFS:SetText(tankName..": "..spellName)
        else
            nameFS:SetText(spellName)
        end
        yOff = yOff - blockH - 3
    end
    -- Title
    local titleFS = assignFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    titleFS:SetPoint("TOP",assignFrame,"TOP",0,-3)
    titleFS:SetTextColor(1,0.82,0.0)
    titleFS:SetText(isViewer and "Tank Assignments" or "My Assignment")
    AddContent(titleFS)
    --------------------------------------------------------------------------
    -- VIEWER window (V tag): full assignment table
    --------------------------------------------------------------------------
    local colL = math.floor(innerW * 0.44)
    local colR = innerW - colL - 1
    local function RenderBlock(label, lr,lg,lb, names, getRGB, markIconTex)
        local showNames = names and table.getn(names) > 0
        if not showNames then names = {} end
        local numRows = showNames and table.getn(names) or 1
        local blockH  = rowStep * numRows + 2
        local block = CreateFrame("Frame",nil,assignFrame)
        block:SetPoint("TOPLEFT",assignFrame,"TOPLEFT",PAD,yOff)
        block:SetWidth(innerW); block:SetHeight(blockH)
        block:SetBackdrop({
            bgFile="Interface\\Buttons\\WHITE8X8",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=8,edgeSize=8,
            insets={left=2,right=2,top=2,bottom=2}
        })
        block:SetBackdropColor(lr*0.05,lg*0.05,lb*0.05,0.4)
        block:SetBackdropBorderColor(lr*0.5,lg*0.5,lb*0.5,0.6)
        AddContent(block)
        -- Mark icon in label column
        local iconW = 0
        if markIconTex then
            local sz = math.max(10, fontSize+2)
            local ic = block:CreateTexture(nil,"OVERLAY")
            ic:SetWidth(sz); ic:SetHeight(sz)
            ic:SetPoint("TOPLEFT",block,"TOPLEFT",4,-(rowStep/2 - sz/2)-2)
            ic:SetTexture(markIconTex)
            iconW = sz + 2
        end
        local fsL = block:CreateFontString(nil,"OVERLAY")
        fsL:SetFont("Fonts\\FRIZQT__.TTF",fontSize,"")
        fsL:SetPoint("TOPLEFT",block,"TOPLEFT",4+iconW,-2)
        local labelW = showNames and (colL-8-iconW) or (innerW-8-iconW)
        fsL:SetWidth(labelW); fsL:SetHeight(rowStep)
        fsL:SetJustifyH("LEFT"); fsL:SetJustifyV("MIDDLE")
        fsL:SetTextColor(lr,lg,lb); fsL:SetText(label)
        local vdiv = block:CreateTexture(nil,"ARTWORK")
        vdiv:SetWidth(1)
        vdiv:SetPoint("TOPLEFT",block,"TOPLEFT",colL,-2)
        vdiv:SetPoint("BOTTOMLEFT",block,"BOTTOMLEFT",colL,2)
        vdiv:SetTexture(lr*0.5,lg*0.5,lb*0.5,0.5)
        if not showNames then vdiv:Hide() end
        for hi,hname in ipairs(names) do
            local hr,hg,hb = 1,1,1
            if getRGB then hr,hg,hb = getRGB(hname) end
            local isDead = false
            for _,dd in ipairs(deadTanks) do
                if dd.name == hname then isDead=true break end
            end
            if isDead then hr,hg,hb = 1,0.15,0.15 end
            local fsH = block:CreateFontString(nil,"OVERLAY")
            fsH:SetFont("Fonts\\FRIZQT__.TTF",fontSize,"")
            fsH:SetPoint("TOPLEFT",block,"TOPLEFT",colL+4,-(2+(hi-1)*rowStep))
            fsH:SetWidth(colR-8); fsH:SetHeight(rowStep)
            fsH:SetJustifyH("LEFT"); fsH:SetJustifyV("MIDDLE")
            fsH:SetTextColor(hr,hg,hb)
            fsH:SetText(isDead and (hname.." [dead]") or hname)
            if hi < numRows then
                local hsep = block:CreateTexture(nil,"ARTWORK")
                hsep:SetHeight(1)
                hsep:SetPoint("TOPLEFT",block,"TOPLEFT",colL+2,-(2+hi*rowStep))
                hsep:SetPoint("TOPRIGHT",block,"TOPRIGHT",-2,-(2+hi*rowStep))
                hsep:SetTexture(0.3,0.3,0.3,0.3)
            end
        end
        yOff = yOff - blockH - 3
    end
    if isViewer and tmpl then
        AddHeader("Tank Assignments",1,0.8,0.2,0.22)
        -- Group by target
        local seen, targets, targetTanks = {},{},{}
        for _,t in ipairs(tmpl.tanks or {}) do
            local key = (t.targetType or "").."~"..(t.targetValue or "")
            if not seen[key] then
                seen[key] = true
                local disp, markTex = ResolveTargetDisp(t.targetType, t.targetValue, t.markIndex)
                table.insert(targets,{key=key, disp=disp, type=t.targetType, markTex=markTex})
                targetTanks[key] = {}
            end
            table.insert(targetTanks[key], t.name)
        end
        if table.getn(targets) == 0 then
            AddBlock("(no assignments)",0.5,0.5,0.5)
        else
            for _,tgt in ipairs(targets) do
                local tr,tg,tb = 0.78,0.61,0.43
                RenderBlock(tgt.disp, tr,tg,tb, targetTanks[tgt.key], function(n)
                    if tmpl.roster and tmpl.roster[n] then
                        return GetClassColor(tmpl.roster[n].class)
                    end
                    return 1,1,1
                end, tgt.markTex)
            end
        end
        -- FW section
        if tmpl.fw and table.getn(tmpl.fw.tanks or {}) > 0 then
            yOff = yOff - 2
            AddHeader("Fear Ward",0.6,0.8,1,0.15)
            for _,slot in ipairs(tmpl.fw.tanks) do
                if slot.tankName then
                    local fr,fg,fb = GetClassColor(
                        tmpl.roster and tmpl.roster[slot.tankName] and tmpl.roster[slot.tankName].class)
                    RenderBlock(slot.tankName, fr,fg,fb, slot.queue or {}, function(n)
                        if tmpl.roster and tmpl.roster[n] then
                            return GetClassColor(tmpl.roster[n].class)
                        end
                        return 1,1,1
                    end)
                end
            end
        end
        -- CC assignments section (viewer sees all CC)
        if tmpl.cc and table.getn(tmpl.cc) > 0 then
            yOff = yOff - 2
            AddHeader("CC Assignments", 0.6, 0.3, 0.9, 0.18)
            for _,ce in ipairs(tmpl.cc) do
                local cr,cg,cb = 1,1,1
                if tmpl.roster and tmpl.roster[ce.name] then
                    cr,cg,cb = GetClassColor(tmpl.roster[ce.name].class)
                end
                local disp = ce.targetValue or "?"
                local markTex = nil
                if ce.targetType == TYPE_MARK then
                    local mi = ce.markIndex or 0
                    disp    = MARK_ICONS[mi] and MARK_ICONS[mi].name or ("Mark "..mi)
                    markTex = MARK_ICONS[mi] and MARK_ICONS[mi].tex or nil
                end
                AddBlock(ce.name..": "..ce.spell, cr,cg,cb, nil, nil,nil,nil, markTex)
            end
        end
        -- AoE Taunts section (last)
        local allTanks = GetTanksSorted(tmpl)
        local hasAoeTaunt = false
        for _,t in ipairs(allTanks) do
            local tList = TAUNT_GetForPlayer(t.name, t.class)
            for _,ts in ipairs(tList) do
                if ts.aoe then hasAoeTaunt = true break end
            end
            if hasAoeTaunt then break end
        end
        if hasAoeTaunt then
            yOff = yOff - 2
            AddHeader("AoE Taunts", 0.9, 0.65, 0.2, 0.18)
            for _,t in ipairs(allTanks) do
                local tr2,tg2,tb2 = GetClassColor(t.class)
                local isDead = false
                for _,dd in ipairs(deadTanks) do
                    if dd.name == t.name then isDead = true break end
                end
                if isDead then tr2,tg2,tb2 = 1,0.15,0.15 end
                local tList = TAUNT_GetForPlayer(t.name, t.class)
                for _,ts in ipairs(tList) do
                    if ts.aoe then
                        AddTauntBlock(t.name, ts.name, ts.icon, ts.remaining, tr2,tg2,tb2)
                    end
                end
            end
        end
        local totalH = math.abs(yOff) + rowStep + 4
        if totalH < titleH + rowStep then totalH = titleH + rowStep end
        assignFrame:SetHeight(totalH)
        assignFrame:Show()
        return
    end
    --------------------------------------------------------------------------
    -- TANK window
    --------------------------------------------------------------------------
    if isTank and tmpl then
        -- Collect ALL assignments for this tank (multi-mark support)
        local myAssignments = {}
        for _,t in ipairs(tmpl.tanks or {}) do
            if t.name == myName then
                table.insert(myAssignments, t)
            end
        end
        yOff = yOff - 2
        local roleTag = myPdata.tagMT and "[MT]" or (myPdata.tagOT and "[OT]" or "[OOT]")
        AddHeader("My Target  "..roleTag, 0.78,0.61,0.43, 0.15)
        if table.getn(myAssignments) > 0 then
            for _,asgn in ipairs(myAssignments) do
                local disp, markTex = ResolveTargetDisp(asgn.targetType, asgn.targetValue, asgn.markIndex)
                RenderBlock(disp, 1,0.85,0.3, {}, nil, markTex)
            end
        else
            AddBlock("(not assigned)", 0.5,0.5,0.5)
        end
        -- Unattended targets (dead tanks' targets)
        local myDeadTargets = {}
        for _,d in ipairs(deadTanks) do
            if d.name ~= myName and d.assignment and d.assignment.targetValue then
                table.insert(myDeadTargets, {from=d.name, asgn=d.assignment})
            end
        end
        if table.getn(myDeadTargets) > 0 then
            yOff = yOff - 2
            AddHeader("Unattended!", 1,0.2,0.2, 0.25)
            for _,ud in ipairs(myDeadTargets) do
                local disp2, markTex2 = ResolveTargetDisp(ud.asgn.targetType, ud.asgn.targetValue, ud.asgn.markIndex)
                RenderBlock(disp2, 1,0.5,0.1, {ud.from.." [dead]"}, function()
                    return GetClassColor(tmpl.roster and tmpl.roster[ud.from] and tmpl.roster[ud.from].class)
                end, markTex2)
            end
        end
        -- FW queue (if I am one of the FW targets)
        for _,fwSlot in ipairs((tmpl.fw and tmpl.fw.tanks) or {}) do
            if fwSlot.tankName == myName then
                yOff = yOff - 2
                AddHeader("Fear Ward Queue", 0.6,0.8,1, 0.15)
                local queue = fwSlot.queue or {}
                if table.getn(queue) == 0 then
                    AddBlock("(no priests)", 0.5,0.5,0.5)
                else
                    for qi,pname in ipairs(queue) do
                        local cdRem = FW_GetCDRemaining(pname)
                        local pr,pg,pb = GetClassColor("PRIEST")
                        if tmpl.roster and tmpl.roster[pname] then
                            pr,pg,pb = GetClassColor(tmpl.roster[pname].class)
                        end
                        AddTauntBlock(qi..". "..pname, "Fear Ward", FW_ICON, cdRem, pr,pg,pb)
                    end
                end
            end
        end
        -- My CC assignments (if any)
        if isCC then
            yOff = yOff - 2
            AddHeader("My CC", 0.6,0.3,0.9, 0.15)
            for _,ce in ipairs(myCCAssignments) do
                local markTex2 = nil
                local disp2 = ce.targetValue or "?"
                if ce.targetType == TYPE_MARK then
                    local mi = ce.markIndex or 0
                    disp2    = MARK_ICONS[mi] and MARK_ICONS[mi].name or ("Mark "..mi)
                    markTex2 = MARK_ICONS[mi] and MARK_ICONS[mi].tex or nil
                end
                AddBlock(ce.spell, 0.9,0.7,1, nil, nil,nil,nil, markTex2)
            end
        end
        -- Taunt cooldowns (own)
        local myClass = myPdata and myPdata.class
        local tauntList = TAUNT_GetForPlayer(myName, myClass)
        if table.getn(tauntList) > 0 then
            yOff = yOff - 2
            AddHeader("Taunt Cooldowns", 0.9,0.7,0.3, 0.12)
            local tr0,tg0,tb0 = GetClassColor(myClass)
            for _,ts in ipairs(tauntList) do
                AddTauntBlock("", ts.name, ts.icon, ts.remaining, tr0,tg0,tb0)
            end
        end
        -- Other tanks' AoE taunt CDs only
        local otherTanks = GetTanksFromRoster(tmpl)
        local hasOthers = false
        for _,ot in ipairs(otherTanks) do
            if ot.name ~= myName then
                local otList = TAUNT_GetForPlayer(ot.name, ot.class)
                for _,ts in ipairs(otList) do
                    if ts.aoe and tauntCD[ot.name] and tauntCD[ot.name][ts.name] then
                        hasOthers = true break
                    end
                end
            end
        end
        if hasOthers then
            yOff = yOff - 2
            AddHeader("Other AoE Taunts", 0.7,0.7,0.9, 0.10)
            for _,ot in ipairs(otherTanks) do
                if ot.name ~= myName then
                    local tr2,tg2,tb2 = GetClassColor(ot.class)
                    local otList = TAUNT_GetForPlayer(ot.name, ot.class)
                    for _,ts in ipairs(otList) do
                        if ts.aoe and tauntCD[ot.name] and tauntCD[ot.name][ts.name] then
                            AddTauntBlock(ot.name, ts.name, ts.icon, ts.remaining, tr2,tg2,tb2)
                        end
                    end
                end
            end
        end
        local totalH = math.abs(yOff) + rowStep + 4
        if totalH < 80 then totalH = 80 end
        assignFrame:SetHeight(totalH)
        assignFrame:Show()
        return
    end
    --------------------------------------------------------------------------
    if isPriest and tmpl then
        -- Find my slot in the FW queues
        local mySlot   = nil
        local myPos    = nil
        for _,slot in ipairs((tmpl.fw and tmpl.fw.tanks) or {}) do
            for i,p in ipairs(slot.queue or {}) do
                if p == myName then mySlot = slot; myPos = i; break end
            end
            if mySlot then break end
        end
        local tankName = mySlot and mySlot.tankName
        local queue    = mySlot and mySlot.queue or {}
        local cdRem    = FW_GetCDRemaining(myName)
        -- Show window only if I am in a queue and there is a target tank
        if not tankName or not myPos then
            assignFrame:Hide() return
        end
        local frameW2 = math.max(150, math.min(260, fontSize*13))
        assignFrame:SetWidth(frameW2)
        local innerW2 = frameW2 - PAD*2
        local PAD2 = 5
        local ICON_SZ = math.floor(fontSize*2.5)
        if ICON_SZ < 20 then ICON_SZ = 20 end
        if ICON_SZ > 48 then ICON_SZ = 48 end
        local BTN_H = fontSize + 8
        -- Title: tank name
        local tr,tg,tb = 0.78,0.61,0.43
        if tmpl.roster and tmpl.roster[tankName] then
            tr,tg,tb = GetClassColor(tmpl.roster[tankName].class)
        end
        local tFS = assignFrame:CreateFontString(nil,"OVERLAY")
        tFS:SetFont("Fonts\\FRIZQT__.TTF",fontSize,"OUTLINE")
        tFS:SetTextColor(tr,tg,tb)
        tFS:SetPoint("TOP",assignFrame,"TOP",0,-4)
        tFS:SetWidth(frameW2-32)
        tFS:SetText(tankName)
        AddContent(tFS)
        local posFS = assignFrame:CreateFontString(nil,"OVERLAY")
        posFS:SetFont("Fonts\\FRIZQT__.TTF",fontSize,"")
        posFS:SetPoint("TOP",assignFrame,"TOP",0,-(4+fontSize+4))
        posFS:SetWidth(frameW2-12)
        posFS:SetJustifyH("CENTER")
        local qLen = table.getn(queue)
        posFS:SetTextColor(0.8,0.8,0.8)
        posFS:SetText("Queue: "..myPos.."/"..qLen)
        AddContent(posFS)
        -- FW icon with CD
        local iconY = -(4 + fontSize + 4 + fontSize + 6)
        local iFrame = CreateFrame("Frame",nil,assignFrame)
        iFrame:SetWidth(ICON_SZ); iFrame:SetHeight(ICON_SZ)
        iFrame:SetPoint("TOP",assignFrame,"TOP",0,iconY)
        local iTex = iFrame:CreateTexture(nil,"BACKGROUND")
        iTex:SetAllPoints(iFrame)
        iTex:SetTexture(FW_ICON)
        if cdRem > 0 then
            iTex:SetVertexColor(0.3,0.3,0.3)
            local iCDFS = iFrame:CreateFontString(nil,"OVERLAY")
            iCDFS:SetFont("Fonts\\FRIZQT__.TTF",math.max(8,math.floor(fontSize*0.85)),"OUTLINE")
            iCDFS:SetPoint("CENTER",iFrame,"CENTER",0,0)
            iCDFS:SetTextColor(1,1,0)
            local m = math.floor(cdRem/60)
            local s = math.floor(math.mod(cdRem,60))
            iCDFS:SetText(m>0 and string.format("%d:%02d",m,s) or tostring(math.floor(cdRem)))
        end
        AddContent(iFrame)
        -- Cast button
        local btnY = iconY - ICON_SZ - PAD2
        local btn = CreateFrame("Button",nil,assignFrame,"UIPanelButtonTemplate")
        btn:SetPoint("TOP",assignFrame,"TOP",0,btnY)
        local btnW = math.max(80, fontSize*6)
        btn:SetWidth(btnW); btn:SetHeight(BTN_H)
        btn:SetText("Fear Ward!")
        if cdRem > 0 then
            btn:SetTextColor(0.5,0.5,0.5)
            btn:EnableMouse(false); btn:SetAlpha(0.5)
        else
            btn:SetTextColor(0.1,1,0.1)
            btn:EnableMouse(true); btn:SetAlpha(1)
        end
        btn:SetScript("OnClick",function()
            local t2 = GetActiveTemplate()
            if not t2 then return end
            -- Find my tank
            local myTank = nil
            for _,slot in ipairs((t2.fw and t2.fw.tanks) or {}) do
                for _,p in ipairs(slot.queue or {}) do
                    if p == UnitName("player") then myTank = slot.tankName; break end
                end
                if myTank then break end
            end
            if not myTank then return end
            if UnitName("target") ~= myTank then
                TargetByName(myTank)
            else
                CastSpellByName("Fear Ward")
                FW_RecordCast(UnitName("player"))
                FW_BroadcastCast(UnitName("player"))
                UpdateAssignFrame()
            end
        end)
        AddContent(btn)
        -- Queue status below button
        local qY = btnY - BTN_H - PAD2
        for qi,pname in ipairs(queue) do
            local qFS = assignFrame:CreateFontString(nil,"OVERLAY")
            qFS:SetFont("Fonts\\FRIZQT__.TTF",math.max(8,fontSize-2),"")
            qFS:SetPoint("TOP",assignFrame,"TOP",0,qY)
            qFS:SetWidth(frameW2-12)
            qFS:SetJustifyH("CENTER")
            local qcr,qcg,qcb = GetClassColor("PRIEST")
            local qcd = FW_GetCDRemaining(pname)
            local qextra = ""
            if qcd > 0 then
                local m = math.floor(qcd/60)
                local s = math.floor(math.mod(qcd,60))
                qextra = " (".. (m>0 and string.format("%d:%02d",m,s) or (s.."s")) ..")"
                qcr,qcg,qcb = 0.7,0.5,0.5
            end
            local arrow = (qi == myPos) and "► " or (qi < myPos and "✓ " or "  ")
            qFS:SetTextColor(qcr,qcg,qcb)
            qFS:SetText(arrow..pname..qextra)
            AddContent(qFS)
            qY = qY - (fontSize+3)
        end
        -- My CC assignments (if any)
        if isCC then
            local ccY = qY - 4
            AddHeader("My CC", 0.6,0.3,0.9, 0.15)
            for _,ce in ipairs(myCCAssignments) do
                local markTexCC = nil
                if ce.targetType == TYPE_MARK then
                    local mi = ce.markIndex or 0
                    markTexCC = MARK_ICONS[mi] and MARK_ICONS[mi].tex or nil
                end
                AddBlock(ce.spell, 0.9,0.7,1, nil, nil,nil,nil, markTexCC)
            end
        end
        local totalH2 = math.abs(yOff) + rowStep + 4
        if totalH2 < 100 then totalH2 = 100 end
        assignFrame:SetHeight(totalH2)
        assignFrame:Show()
        return
    end
    --------------------------------------------------------------------------
    if isCC then
        local frameWCC = math.max(160, math.min(260, fontSize * 14))
        assignFrame:SetWidth(frameWCC)
        local innerWCC = frameWCC - PAD*2
        local titleCC = assignFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
        titleCC:SetPoint("TOP",assignFrame,"TOP",0,-3)
        titleCC:SetTextColor(0.6,0.3,0.9)
        titleCC:SetText("CC Assignment")
        AddContent(titleCC)
        yOff = yOff - 4
        AddHeader("My CC", 0.6,0.3,0.9, 0.15)
        for _,ce in ipairs(myCCAssignments) do
            local markTex = nil
            local disp    = ce.targetValue or "?"
            if ce.targetType == TYPE_MARK then
                local mi = ce.markIndex or 0
                disp    = MARK_ICONS[mi] and MARK_ICONS[mi].name or ("Mark "..mi)
                markTex = MARK_ICONS[mi] and MARK_ICONS[mi].tex or nil
            end
            AddBlock(ce.spell, 0.9,0.7,1, nil, nil,nil,nil, markTex)
        end
        local totalHCC = math.abs(yOff) + rowStep + 4
        if totalHCC < 80 then totalHCC = 80 end
        assignFrame:SetHeight(totalHCC)
        assignFrame:Show()
        return
    end
    assignFrame:Hide()
    -- Always refresh combat panel indicators after any assignment change
    CP_RefreshMarkIndicators()
end
-------------------------------------------------------------------------------
-- APPLY WINDOW ALPHA
-------------------------------------------------------------------------------
local function ApplyWindowAlpha(alpha)
    alpha = alpha or (TankAssignDB and TankAssignDB.options and TankAssignDB.options.windowAlpha) or 0.95
    if mainFrame   then mainFrame:SetBackdropColor(0.04,0.04,0.1,alpha) end
    if rosterFrame then rosterFrame:SetBackdropColor(0.04,0.04,0.1,alpha) end
    if optionsFrame then optionsFrame:SetBackdropColor(0.04,0.04,0.1,alpha) end
    if assignFrame  then assignFrame:SetBackdropColor(0.05,0.05,0.1,alpha) end
    if fwFrame      then fwFrame:SetBackdropColor(0.04,0.06,0.04,alpha) end
    if combatPanel  then combatPanel:SetBackdropColor(0.04,0.04,0.1,alpha) end
end
-------------------------------------------------------------------------------
-- RAID ROSTER FRAME
-------------------------------------------------------------------------------
local rosterRowWidgets = {}
RebuildRosterRows = function()
    if not rosterFrame then return end
    for _,r in ipairs(rosterRowWidgets) do r:Hide() end
    rosterRowWidgets = {}
    local tmpl = GetActiveTemplate()
    if not tmpl then return end
    local members = GetRaidMembers()
    local currentMembers = {}
    for _,m in ipairs(members) do currentMembers[m.name] = m end
    local toRemove = {}
    for pname,_ in pairs(tmpl.roster) do
        if not currentMembers[pname] then table.insert(toRemove, pname) end
    end
    for _,pname in ipairs(toRemove) do tmpl.roster[pname] = nil end
    for _,m in ipairs(members) do
        if not tmpl.roster[m.name] then
            tmpl.roster[m.name] = {class=m.class, subgroup=m.subgroup or 1}
        else
            tmpl.roster[m.name].class    = m.class
            tmpl.roster[m.name].subgroup = m.subgroup or tmpl.roster[m.name].subgroup or 1
        end
    end
    SyncFWQueueFromRoster(tmpl)
    local groups = {}
    for g=1,8 do groups[g] = {} end
    for pname,pdata in pairs(tmpl.roster) do
        local sg = pdata.subgroup or 1
        if sg < 1 then sg = 1 end
        if sg > 8 then sg = 8 end
        table.insert(groups[sg], {
            name=pname, class=pdata.class,
            tagMT=pdata.tagMT, tagOT=pdata.tagOT,
            tagOOT=pdata.tagOOT, tagV=pdata.tagV
        })
    end
    for g=1,8 do
        table.sort(groups[g], function(a,b) return a.name < b.name end)
    end
    -- Layout constants
    local SLOTS     = 5
    local cols      = 2
    local groupW    = 210
    local groupPadX = 12
    local playerH   = 18
    local headerH   = 20
    local groupPadY = 8
    local groupH    = headerH + SLOTS * playerH + 6  -- 116
    local topY      = -36  -- below title
    local btnArea   = 40   -- space for button row at bottom
    -- Resize mainFrame to fit all groups exactly
    local rows      = math.ceil(8 / cols)  -- 4
    local totalW    = 8 + cols * groupW + (cols-1) * groupPadX + 8
    local totalH    = math.abs(topY) + rows * groupH + (rows-1) * groupPadY + btnArea
    mainFrame:SetWidth(totalW)
    mainFrame:SetHeight(totalH)
    -- Draw on mainFrame directly (sc = mainFrame)
    local sc = mainFrame
    for gIdx=1,8 do
        local col  = math.mod(gIdx-1, cols)
        local grow = math.floor((gIdx-1) / cols)
        local gx   = 8 + col * (groupW + groupPadX)
        local gy   = topY - grow * (groupH + groupPadY)
        local gFrame = CreateFrame("Frame",nil,sc)
        gFrame:SetWidth(groupW)
        gFrame:SetHeight(groupH)
        gFrame:SetPoint("TOPLEFT",sc,"TOPLEFT",gx,gy)
        gFrame:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=8,edgeSize=8,
            insets={left=3,right=3,top=3,bottom=3}
        })
        gFrame:SetBackdropColor(0.07,0.07,0.14,0.95)
        gFrame:SetBackdropBorderColor(0.25,0.35,0.6,0.7)
        table.insert(rosterRowWidgets, gFrame)
        local gLabel = gFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        gLabel:SetPoint("TOPLEFT",gFrame,"TOPLEFT",5,-4)
        gLabel:SetTextColor(0.7,0.7,0.7)
        gLabel:SetText("Group "..gIdx)
        local py = -headerH
        for slot=1,SLOTS do
            local p = groups[gIdx][slot]
            local pRow = CreateFrame("Frame",nil,gFrame)
            pRow:SetHeight(playerH)
            pRow:SetPoint("TOPLEFT", gFrame,"TOPLEFT", 4, py)
            pRow:SetPoint("TOPRIGHT",gFrame,"TOPRIGHT",-4, py)
            table.insert(rosterRowWidgets, pRow)
            if p then
                local pr,pg,pb = GetClassColor(p.class)
                local capturedName = p.name
                local nameLabel = pRow:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                nameLabel:SetPoint("LEFT",pRow,"LEFT",4,0)
                nameLabel:SetWidth(76)
                nameLabel:SetJustifyH("LEFT")
                nameLabel:SetTextColor(pr,pg,pb)
                nameLabel:SetText(p.name)
                local mtBtn = CreateFrame("Button",nil,pRow,"UIPanelButtonTemplate")
                mtBtn:SetWidth(22); mtBtn:SetHeight(14); mtBtn:SetText("MT")
                mtBtn:SetPoint("LEFT",pRow,"LEFT",84,0)
                if p.tagMT then mtBtn:SetTextColor(1,0.4,0.4)
                else mtBtn:SetTextColor(0.35,0.35,0.35) end
                local otBtn = CreateFrame("Button",nil,pRow,"UIPanelButtonTemplate")
                otBtn:SetWidth(22); otBtn:SetHeight(14); otBtn:SetText("OT")
                otBtn:SetPoint("LEFT",mtBtn,"RIGHT",2,0)
                if p.tagOT then otBtn:SetTextColor(1,0.75,0.3)
                else otBtn:SetTextColor(0.35,0.35,0.35) end
                local ootBtn = CreateFrame("Button",nil,pRow,"UIPanelButtonTemplate")
                ootBtn:SetWidth(28); ootBtn:SetHeight(14); ootBtn:SetText("OOT")
                ootBtn:SetPoint("LEFT",otBtn,"RIGHT",2,0)
                if p.tagOOT then ootBtn:SetTextColor(0.6,0.9,0.6)
                else ootBtn:SetTextColor(0.35,0.35,0.35) end
                local vBtn = CreateFrame("Button",nil,pRow,"UIPanelButtonTemplate")
                vBtn:SetWidth(18); vBtn:SetHeight(14); vBtn:SetText("V")
                vBtn:SetPoint("LEFT",ootBtn,"RIGHT",2,0)
                if p.tagV then vBtn:SetTextColor(0.4,0.9,1)
                else vBtn:SetTextColor(0.35,0.35,0.35) end
                mtBtn:SetScript("OnClick",function()
                    local e = tmpl.roster[capturedName]
                    if e then e.tagMT = not e.tagMT
                        if e.tagMT then e.tagOT=nil; e.tagOOT=nil end
                        RebuildRosterRows(); UpdateAssignFrame() end
                end)
                otBtn:SetScript("OnClick",function()
                    local e = tmpl.roster[capturedName]
                    if e then e.tagOT = not e.tagOT
                        if e.tagOT then e.tagMT=nil; e.tagOOT=nil end
                        RebuildRosterRows(); UpdateAssignFrame() end
                end)
                ootBtn:SetScript("OnClick",function()
                    local e = tmpl.roster[capturedName]
                    if e then e.tagOOT = not e.tagOOT
                        if e.tagOOT then e.tagMT=nil; e.tagOT=nil end
                        RebuildRosterRows(); UpdateAssignFrame() end
                end)
                vBtn:SetScript("OnClick",function()
                    local e = tmpl.roster[capturedName]
                    if e then e.tagV = not e.tagV
                        RebuildRosterRows(); UpdateAssignFrame() end
                end)
            else
                local emptyLabel = pRow:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                emptyLabel:SetPoint("LEFT",pRow,"LEFT",4,0)
                emptyLabel:SetTextColor(0.25,0.25,0.25)
                emptyLabel:SetText("Empty")
            end
            py = py - playerH
        end
    end
end
local function CreateRosterFrame()
    if not mainFrame then return end
    if rosterFrame then
        RebuildRosterRows()
        return
    end
    rosterFrame = mainFrame  -- alias so RebuildRosterRows works
    mainFrame.scrollChild = mainFrame  -- draw directly on mainFrame
    RebuildRosterRows()
end
-------------------------------------------------------------------------------
-- FEARWARD QUEUE MANAGER FRAME
-------------------------------------------------------------------------------
local fwRows = {}
local function FW_RebuildRows()
    if not fwFrame then return end
    for _,r in ipairs(fwRows) do r:Hide() end
    fwRows = {}
    local tmpl = GetActiveTemplate()
    if not tmpl then return end
    SyncFWQueueFromRoster(tmpl)
    local rowH  = 24
    local pad   = 8
    local w     = 300
    local y     = -38  -- start below title
    -- Helper: build one priest row inside a tank block
    local function MakePriestRow(slotIdx, qi, pname)
        local slot = tmpl.fw.tanks[slotIdx]
        local ICON_SZ = 20
        local cell = CreateFrame("Frame", nil, fwFrame)
        cell:SetWidth(w - pad*2); cell:SetHeight(ICON_SZ + 4)
        cell:SetPoint("TOPLEFT", fwFrame, "TOPLEFT", pad, y)
        cell:SetBackdrop({
            bgFile  ="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=8,edgeSize=8,
            insets={left=2,right=2,top=2,bottom=2}
        })
        cell:SetBackdropColor(0.06,0.08,0.06,0.97)
        cell:SetBackdropBorderColor(0.2,0.5,0.2,0.7)
        table.insert(fwRows, cell)

        -- Position number
        local posFS = cell:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        posFS:SetPoint("LEFT",cell,"LEFT",4,0)
        posFS:SetWidth(14); posFS:SetJustifyH("CENTER")
        posFS:SetTextColor(0.6,0.6,0.6); posFS:SetText(qi..".")

        -- Fear Ward icon with CD overlay
        local cdRem   = FW_GetCDRemaining(pname)
        local isReady = cdRem <= 0
        local iconCont = CreateFrame("Frame",nil,cell)
        iconCont:SetWidth(ICON_SZ); iconCont:SetHeight(ICON_SZ)
        iconCont:SetPoint("LEFT",cell,"LEFT",20,0)
        local iTex = iconCont:CreateTexture(nil,"BACKGROUND")
        iTex:SetAllPoints(iconCont)
        iTex:SetTexture(FW_ICON)
        iTex:SetVertexColor(isReady and 1 or 0.35, isReady and 1 or 0.35, isReady and 1 or 0.35)
        if not isReady then
            local cdFS = iconCont:CreateFontString(nil,"OVERLAY")
            cdFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            cdFS:SetPoint("CENTER",iconCont,"CENTER",0,0)
            cdFS:SetTextColor(1,1,0)
            cdFS:SetText(cdRem <= 90 and (math.ceil(cdRem).."s") or (math.ceil(cdRem/60).."m"))
        end

        -- Priest name
        local pr,pg,pb = GetClassColor("PRIEST")
        if tmpl.roster and tmpl.roster[pname] then
            pr,pg,pb = GetClassColor(tmpl.roster[pname].class)
        end
        local nameFS = cell:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        nameFS:SetPoint("LEFT",cell,"LEFT",44,0)
        nameFS:SetPoint("RIGHT",cell,"RIGHT",-44,0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetTextColor(isReady and pr or pr*0.6, isReady and pg or pg*0.6, isReady and pb or pb*0.6)
        nameFS:SetText(pname)
        -- ↑ ↓ ✕
        local upBtn = CreateFrame("Button",nil,cell,"UIPanelButtonTemplate")
        upBtn:SetWidth(18); upBtn:SetHeight(14)
        upBtn:SetPoint("RIGHT",cell,"RIGHT",-42,0); upBtn:SetText("↑")
        local capturedSI,capturedQ = slotIdx, qi
        upBtn:SetScript("OnClick",function()
            local q = tmpl.fw.tanks[capturedSI] and tmpl.fw.tanks[capturedSI].queue
            if q and capturedQ > 1 then
                local tmp2=q[capturedQ-1]; q[capturedQ-1]=q[capturedQ]; q[capturedQ]=tmp2
                FW_RebuildRows(); UpdateAssignFrame(); FW_BroadcastAssignments()
            end
        end)
        local dnBtn = CreateFrame("Button",nil,cell,"UIPanelButtonTemplate")
        dnBtn:SetWidth(18); dnBtn:SetHeight(14)
        dnBtn:SetPoint("RIGHT",cell,"RIGHT",-22,0); dnBtn:SetText("↓")
        dnBtn:SetScript("OnClick",function()
            local q = tmpl.fw.tanks[capturedSI] and tmpl.fw.tanks[capturedSI].queue
            if q and capturedQ < table.getn(q) then
                local tmp2=q[capturedQ+1]; q[capturedQ+1]=q[capturedQ]; q[capturedQ]=tmp2
                FW_RebuildRows(); UpdateAssignFrame(); FW_BroadcastAssignments()
            end
        end)
        local rmBtn = CreateFrame("Button",nil,cell,"UIPanelButtonTemplate")
        rmBtn:SetWidth(18); rmBtn:SetHeight(14)
        rmBtn:SetPoint("RIGHT",cell,"RIGHT",-2,0); rmBtn:SetText("X")
        rmBtn:SetScript("OnClick",function()
            local q = tmpl.fw.tanks[capturedSI] and tmpl.fw.tanks[capturedSI].queue
            if q then
                table.remove(q, capturedQ)
                FW_RebuildRows(); UpdateAssignFrame(); FW_BroadcastAssignments()
            end
        end)
        table.insert(fwRows,upBtn); table.insert(fwRows,dnBtn); table.insert(fwRows,rmBtn)
        y = y - rowH - 2
    end
    -- Collect already-assigned priests (for "Add Priest" dropdown filtering)
    local function GetAssignedPriests()
        local assigned = {}
        for _,slot in ipairs(tmpl.fw.tanks or {}) do
            for _,p in ipairs(slot.queue or {}) do assigned[p] = true end
        end
        return assigned
    end
    -- Render each tank slot
    for si, slot in ipairs(tmpl.fw.tanks or {}) do
        local capturedSI = si
        -- Tank header row
        local hdr = CreateFrame("Frame", nil, fwFrame)
        hdr:SetWidth(w - pad*2); hdr:SetHeight(22)
        hdr:SetPoint("TOPLEFT", fwFrame, "TOPLEFT", pad, y)
        hdr:SetBackdrop({
            bgFile  ="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=8,edgeSize=8,
            insets={left=2,right=2,top=2,bottom=2}
        })
        hdr:SetBackdropColor(0.04,0.10,0.04,0.97)
        hdr:SetBackdropBorderColor(0.3,0.8,0.3,0.9)
        table.insert(fwRows, hdr)
        -- Tank name label
        local tr,tg,tb = 0.78,0.61,0.43
        if tmpl.roster and tmpl.roster[slot.tankName] then
            tr,tg,tb = GetClassColor(tmpl.roster[slot.tankName].class)
        end
        local tFS = hdr:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        tFS:SetPoint("LEFT",hdr,"LEFT",6,0)
        tFS:SetWidth(140); tFS:SetJustifyH("LEFT")
        tFS:SetTextColor(tr,tg,tb)
        tFS:SetText("[Tank] "..(slot.tankName or "?"))
        -- "Add Priest" button
        local addPBtn = CreateFrame("Button",nil,hdr,"UIPanelButtonTemplate")
        addPBtn:SetWidth(72); addPBtn:SetHeight(16)
        addPBtn:SetPoint("RIGHT",hdr,"RIGHT",-24,0)
        addPBtn:SetText("+ Priest")
        addPBtn:SetScript("OnClick",function()
            local assigned = GetAssignedPriests()
            local allPriests = GetPriestsFromRoster(tmpl)
            local items = {}
            for _,p in ipairs(allPriests) do
                if not assigned[p] then
                    local pr2,pg2,pb2 = GetClassColor("PRIEST")
                    if tmpl.roster and tmpl.roster[p] then
                        pr2,pg2,pb2 = GetClassColor(tmpl.roster[p].class)
                    end
                    table.insert(items,{text=p, r=pr2,g=pg2,b=pb2, pname=p})
                end
            end
            if table.getn(items) == 0 then
                table.insert(items,{text="(all priests assigned)",r=0.5,g=0.5,b=0.5})
            end
            ShowDropdown(addPBtn, items, function(item)
                if item.pname then
                    local sl = tmpl.fw.tanks[capturedSI]
                    if sl then
                        table.insert(sl.queue, item.pname)
                        FW_RebuildRows(); UpdateAssignFrame(); FW_BroadcastAssignments()
                    end
                end
            end, 160)
        end)
        table.insert(fwRows, addPBtn)
        -- Remove tank slot button
        local rmTBtn = CreateFrame("Button",nil,hdr,"UIPanelButtonTemplate")
        rmTBtn:SetWidth(18); rmTBtn:SetHeight(16)
        rmTBtn:SetPoint("RIGHT",hdr,"RIGHT",-2,0)
        rmTBtn:SetText("X")
        rmTBtn:SetScript("OnClick",function()
            table.remove(tmpl.fw.tanks, capturedSI)
            FW_RebuildRows(); UpdateAssignFrame(); FW_BroadcastAssignments()
        end)
        table.insert(fwRows, rmTBtn)
        y = y - 22 - 2
        -- Priest rows for this slot
        if table.getn(slot.queue or {}) == 0 then
            local noFS = fwFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            noFS:SetPoint("TOPLEFT",fwFrame,"TOPLEFT",pad+10,y)
            noFS:SetTextColor(0.5,0.5,0.5); noFS:SetText("  (no priests assigned)")
            table.insert(fwRows, noFS)
            y = y - 18
        else
            for qi,pname in ipairs(slot.queue) do
                MakePriestRow(si, qi, pname)
            end
        end
        y = y - 6  -- gap between tank blocks
    end
    -- "Add Tank" button at bottom
    local addTBtn = CreateFrame("Button",nil,fwFrame,"UIPanelButtonTemplate")
    addTBtn:SetWidth(90); addTBtn:SetHeight(20)
    addTBtn:SetPoint("TOPLEFT",fwFrame,"TOPLEFT",pad,y)
    addTBtn:SetText("+ Tank")
    addTBtn:SetScript("OnClick",function()
        local tanks = GetTanksFromRoster(tmpl)
        -- Filter out already-used tanks
        local usedTanks = {}
        for _,slot in ipairs(tmpl.fw.tanks or {}) do usedTanks[slot.tankName]=true end
        local items = {}
        for _,t in ipairs(tanks) do
            if not usedTanks[t.name] then
                local tr2,tg2,tb2 = GetClassColor(t.class)
                local roleTag = t.tagMT and "[MT]" or (t.tagOT and "[OT]" or "[OOT]")
                table.insert(items,{text=t.name.." "..roleTag, r=tr2,g=tg2,b=tb2, tname=t.name})
            end
        end
        if table.getn(items) == 0 then
            table.insert(items,{text="(no more tanks available)",r=0.5,g=0.5,b=0.5})
        end
        ShowDropdown(addTBtn, items, function(item)
            if item.tname then
                if not tmpl.fw then tmpl.fw = {tanks={}} end
                table.insert(tmpl.fw.tanks, {tankName=item.tname, queue={}})
                FW_RebuildRows(); UpdateAssignFrame(); FW_BroadcastAssignments()
            end
        end, 180)
    end)
    table.insert(fwRows, addTBtn)
    y = y - 26
    local totalH = math.abs(y) + 40
    if totalH < 80 then totalH = 80 end
    fwFrame:SetHeight(totalH)
    fwFrame:SetWidth(w)
end
-- Broadcast FW assignments to raid: FW_ASSIGN2;tank1^p1^p2|tank2^p3
FW_BroadcastAssignments = function()
    local tmpl = GetActiveTemplate()
    if not tmpl or not tmpl.fw then return end
    local chan = GetChannel()
    if not chan then return end
    local slots = {}
    for _,slot in ipairs(tmpl.fw.tanks or {}) do
        local parts = {slot.tankName or ""}
        for _,p in ipairs(slot.queue or {}) do table.insert(parts, p) end
        table.insert(slots, table.concat(parts,"^"))
    end
    pcall(SendAddonMessage, COMM_PREFIX, "FW_ASSIGN2;"..table.concat(slots,"|"), chan)
end
local function CreateFWFrame()
    if fwFrame then
        FW_RebuildRows()
        fwFrame:Raise(); fwFrame:Show()
        PushWindow(fwFrame)
        return
    end
    fwFrame = CreateFrame("Frame","TankAssignFWFrame",UIParent)
    fwFrame:SetWidth(300); fwFrame:SetHeight(200)
    fwFrame:SetPoint("TOPLEFT",mainFrame,"TOPRIGHT",10,0)
    fwFrame:SetMovable(true); fwFrame:EnableMouse(true)
    fwFrame:RegisterForDrag("LeftButton")
    fwFrame:SetScript("OnDragStart",function() this:StartMoving() end)
    fwFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    fwFrame:SetFrameStrata("DIALOG"); fwFrame:SetFrameLevel(10)
    fwFrame:SetBackdrop({
        bgFile  ="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true,tileSize=8,edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4}
    })
    local _a = (TankAssignDB and TankAssignDB.options and TankAssignDB.options.windowAlpha) or 0.95
    fwFrame:SetBackdropColor(0.04,0.06,0.04,_a)
    local title = fwFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOP",fwFrame,"TOP",0,-12)
    title:SetTextColor(0.4,1,0.6); title:SetText("Fear Ward Queue")
    local closeBtn = CreateFrame("Button",nil,fwFrame,"UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT",fwFrame,"TOPRIGHT",-4,-4)
    closeBtn:SetScript("OnClick",function() fwFrame:Hide() end)
    HookFrameHide(fwFrame)
    local syncBtn = CreateFrame("Button",nil,fwFrame,"UIPanelButtonTemplate")
    syncBtn:SetWidth(60); syncBtn:SetHeight(20)
    syncBtn:SetPoint("BOTTOMRIGHT",fwFrame,"BOTTOMRIGHT",-10,10)
    syncBtn:SetText("Sync")
    syncBtn:SetScript("OnClick",function() FW_BroadcastAssignments() end)
    AddTooltip(syncBtn,"Broadcast Fear Ward assignments to all raid members with TankAssign.")
    FW_RebuildRows()
    fwFrame:Raise(); fwFrame:Show()
    PushWindow(fwFrame)
end
-------------------------------------------------------------------------------
-- COMBAT PANEL  (marker assignment, in-fight)
-------------------------------------------------------------------------------
-- combatPanel state
local cpActiveMarkIdx  = nil   -- which mark icon is currently active
local cpMarkButtons    = {}    -- references to the 8 mark icon buttons
-- Returns tanks sorted MT first, then OT, then OOT
GetTanksSorted = function(tmpl)
    if not tmpl then return {} end
    local tanks = GetTanksFromRoster(tmpl)
    table.sort(tanks, function(a,b)
        local function rank(t)
            if t.tagMT  then return 1 end
            if t.tagOT  then return 2 end
            return 3  -- OOT
        end
        local ra, rb = rank(a), rank(b)
        if ra ~= rb then return ra < rb end
        return (a.name or "") < (b.name or "")
    end)
    return tanks
end
-- Find all tanks assigned to a given mark in the active template
local function CP_GetTanksForMark(markIdx)
    local tmpl = GetActiveTemplate()
    if not tmpl then return {} end
    local out = {}
    for _,t in ipairs(tmpl.tanks or {}) do
        if t.targetType == TYPE_MARK and t.markIndex == markIdx then
            table.insert(out, t.name)
        end
    end
    return out
end
-- Update indicator dots/names under each mark icon button
CP_RefreshMarkIndicators = function()
    if not combatPanel then return end
    for mi = 1, 8 do
        local btn = cpMarkButtons[mi]
        if btn and btn.indicator then
            local assigned = CP_GetTanksForMark(mi)
            if table.getn(assigned) > 0 then
                -- Show count badge: green=1 tank, yellow=2+
                local count = table.getn(assigned)
                btn.indicator:SetText(count)
                if count >= 2 then
                    btn.indicator:SetTextColor(1, 0.85, 0.1)
                else
                    btn.indicator:SetTextColor(0.3, 1, 0.3)
                end
                btn.indicator:Show()
                -- Highlight active mark border
                btn:SetBackdropBorderColor(0.3, 1, 0.3, 0.9)
            else
                btn.indicator:Hide()
                btn:SetBackdropBorderColor(0.3, 0.3, 0.5, 0.6)
            end
        end
    end
end
-- Show tank assignment dropdown anchored to the clicked mark button
local function CP_ShowTankDropdown(markIdx, anchorBtn)
    local tmpl = GetActiveTemplate()
    if not tmpl then return end
    local tanks = GetTanksSorted(tmpl)
    if table.getn(tanks) == 0 then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00ccffTankAssign:|r No tanks tagged. Use Raid Roster to tag MT/OT/OOT.")
        return
    end
    -- Currently assigned tanks for this mark
    local alreadyAssigned = {}
    for _,n in ipairs(CP_GetTanksForMark(markIdx)) do
        alreadyAssigned[n] = true
    end
    -- All marks assigned to each tank (for icons display)
    local tankMarks = {}  -- [tankName] = {markIndex, ...}
    for _,t in ipairs(tmpl.tanks or {}) do
        if t.targetType == TYPE_MARK and t.markIndex and t.markIndex > 0 then
            if not tankMarks[t.name] then tankMarks[t.name] = {} end
            table.insert(tankMarks[t.name], t.markIndex)
        end
    end
    -- Mob name from current target (for preset recording)
    local mobName = UnitExists("target") and UnitName("target") or nil
    local items = {}
    for _,t in ipairs(tanks) do
        local roleLabel = t.tagMT and "[MT]" or (t.tagOT and "[OT]" or "[OOT]")
        local tr,tg,tb = GetClassColor(t.class)
        local isAssigned = alreadyAssigned[t.name] and true or false
        local capturedTank = t
        local capturedMark = markIdx
        local capturedMob  = mobName
        -- Build mark icons list for this tank (all marks except current)
        local markIcons = {}
        for _,mi in ipairs(tankMarks[t.name] or {}) do
            if MARK_ICONS[mi] then
                table.insert(markIcons, MARK_ICONS[mi].tex)
            end
        end
        local displayText
        if isAssigned then
            displayText = "[X] "..t.name.." "..roleLabel
        else
            displayText = t.name.." "..roleLabel
        end
        table.insert(items, {
            text       = displayText,
            r          = isAssigned and 0.2 or tr,
            g          = isAssigned and 1.0 or tg,
            b          = isAssigned and 0.2 or tb,
            markIcons  = table.getn(markIcons) > 0 and markIcons or nil,
            isAssigned = isAssigned,
            tankData   = capturedTank,
            markIdx    = capturedMark,
            mobName    = capturedMob,
        })
    end
    -- Clear Mark at bottom
    table.insert(items, {
        text       = "Clear Mark",
        r=1, g=0.3, b=0.3,
        isClearMark = true,
        markIdx    = markIdx,
    })
    ShowDropdown(anchorBtn, items, function(item)
        if item.isSeparator then
            CP_ShowTankDropdown(markIdx, anchorBtn)
            return
        end
        if item.isClearMark then
            -- Remove mark from target if targeted
            if UnitExists("target") and HasEditorRights() then
                if GetRaidTargetIndex("target") == item.markIdx then
                    SetRaidTarget("target", 0)
                end
            end
            -- Clear all assignments for this mark
            local t3 = GetActiveTemplate()
            if t3 then
                local ft = {}
                for _,ex in ipairs(t3.tanks or {}) do
                    if not (ex.targetType == TYPE_MARK
                        and ex.markIndex == item.markIdx) then
                        table.insert(ft, ex)
                    end
                end
                t3.tanks = ft
                local fc = {}
                for _,ex in ipairs(t3.cc or {}) do
                    if not (ex.targetType == TYPE_MARK
                        and ex.markIndex == item.markIdx) then
                        table.insert(fc, ex)
                    end
                end
                t3.cc = fc
                TankAssign_SyncTemplate()
                UpdateAssignFrame()
                CP_RefreshMarkIndicators()
            end
            cpActiveMarkIdx = nil
            return
        end
        local t3 = GetActiveTemplate()
        if not t3 then return end
        if item.isAssigned then
            -- Toggle OFF: remove this tank from this mark
            local filtered = {}
            for _,ex in ipairs(t3.tanks or {}) do
                if not (ex.name == item.tankData.name
                    and ex.targetType == TYPE_MARK
                    and ex.markIndex  == item.markIdx) then
                    table.insert(filtered, ex)
                end
            end
            t3.tanks = filtered
        else
            -- Toggle ON: add this tank to this mark
            table.insert(t3.tanks, {
                name        = item.tankData.name,
                targetType  = TYPE_MARK,
                targetValue = MARK_ICONS[item.markIdx]
                              and MARK_ICONS[item.markIdx].name
                              or ("Mark "..item.markIdx),
                markIndex   = item.markIdx,
            })
        end
        TankAssign_SyncTemplate()
        UpdateAssignFrame()
        RebuildMainGrid()
        CP_RefreshMarkIndicators()
        cpActiveMarkIdx = nil
    end, 190)
    cpActiveMarkIdx = markIdx
end
local function CreateCombatPanel()
    if combatPanel then
        combatPanel:Show()
        return
    end
    -- Guard: only useful in a raid
    if GetNumRaidMembers() == 0 then
        if not HasEditorRights() then
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff00ccffTankAssign:|r Only Raid Leader or Assistant can open the editor.")
            return
        end
    end
    -- Panel width: 8 icons + preset button + padding
    local iconSz  = 28
    local iconGap = 4
    local numIcons = 8
    local targetBtnSz = 28  -- target icon button (same size as mark icons)
    local presetBtnW = 70
    local PAD = 8
    local panelW = PAD + numIcons*(iconSz+iconGap) + iconGap + targetBtnSz + PAD + presetBtnW + PAD
    combatPanel = CreateFrame("Frame","TankAssignCombatPanel",UIParent)
    combatPanel:SetWidth(panelW)
    combatPanel:SetHeight(48)
    combatPanel:SetMovable(true); combatPanel:EnableMouse(true)
    combatPanel:RegisterForDrag("LeftButton")
    combatPanel:SetScript("OnDragStart",function() this:StartMoving() end)
    combatPanel:SetScript("OnDragStop", function()
        this:StopMovingOrSizing()
        -- Save position (no argument to GetPoint in 1.12.1)
        local point, _, relPoint, x, y = this:GetPoint()
        if point then
            TankAssignDB.combatPanelPos = {
                point    = point,
                relPoint = relPoint or "CENTER",
                x        = math.floor(x or 0),
                y        = math.floor(y or 0),
            }
        end
    end)
    -- Restore saved position or default
    local pos = TankAssignDB and TankAssignDB.combatPanelPos
    if pos then
        combatPanel:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        combatPanel:SetPoint("CENTER", UIParent, "CENTER", 0, 200)
    end
    combatPanel:SetFrameStrata("HIGH")
    combatPanel:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true, tileSize=8, edgeSize=10,
        insets={left=3,right=3,top=3,bottom=3}
    })
    local _a = (TankAssignDB and TankAssignDB.options
                and TankAssignDB.options.windowAlpha) or 0.95
    combatPanel:SetBackdropColor(0.04, 0.04, 0.10, _a)
    combatPanel:SetBackdropBorderColor(0.4, 0.4, 0.8, 0.9)
    ---------------------------------------------------------------------------
    -- 8 mark icon buttons
    ---------------------------------------------------------------------------
    cpMarkButtons = {}
    for mi = 1, 8 do
        local capturedMI = mi
        -- Outer frame acts as a backdrop/border container
        local btnFrame = CreateFrame("Frame", nil, combatPanel)
        btnFrame:SetWidth(iconSz + 2)
        btnFrame:SetHeight(iconSz + 2)
        btnFrame:SetPoint("TOPLEFT", combatPanel, "TOPLEFT",
            PAD + (mi-1)*(iconSz+iconGap), -8)
        btnFrame:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=4, edgeSize=6,
            insets={left=1,right=1,top=1,bottom=1}
        })
        btnFrame:SetBackdropColor(0,0,0, 0.3)
        btnFrame:SetBackdropBorderColor(0.3, 0.3, 0.5, 0.6)
        -- Clickable button inside
        local btn = CreateFrame("Button", nil, btnFrame)
        btn:SetWidth(iconSz); btn:SetHeight(iconSz)
        btn:SetPoint("CENTER", btnFrame, "CENTER", 0, 0)
        -- CreateTexture instead of SetNormalTexture (1.12.1 compatibility)
        local iconTex = btn:CreateTexture(nil, "BACKGROUND")
        iconTex:SetAllPoints(btn)
        iconTex:SetTexture(MARK_ICONS[mi].tex)
        iconTex:SetAlpha(0.9)
        btn._iconTex = iconTex
        -- Highlight overlay
        btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
        btn:GetHighlightTexture():SetBlendMode("ADD")
        -- Small assignment-count badge (bottom-right of icon)
        local badge = btnFrame:CreateFontString(nil, "OVERLAY")
        badge:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        badge:SetPoint("BOTTOMRIGHT", btnFrame, "BOTTOMRIGHT", 2, -1)
        badge:SetJustifyH("RIGHT")
        badge:Hide()
        btn.indicator = badge
        btnFrame.indicator = badge
        btn:RegisterForClicks("LeftButtonUp","RightButtonUp")
        btn:SetScript("OnClick", function()
            if arg1 == "RightButton" then
                GameTooltip:Hide()
                -- Set mark on target if not already set
                if UnitExists("target") and HasEditorRights() then
                    if GetRaidTargetIndex("target") ~= capturedMI then
                        SetRaidTarget("target", capturedMI)
                    end
                end
                ShowCCDropdown(btn, capturedMI)
                return
            end
            -- LMB: set mark on target if not already set, then open tank dropdown
            if UnitExists("target") and HasEditorRights() then
                if GetRaidTargetIndex("target") ~= capturedMI then
                    SetRaidTarget("target", capturedMI)
                end
            end
            CP_ShowTankDropdown(capturedMI, btn)
        end)
        btn:SetScript("OnEnter", function()
            GameTooltip:SetOwner(this, "ANCHOR_TOP")
            GameTooltip:SetText(MARK_ICONS[capturedMI].name, 1, 1, 1, true)
            -- List tanks assigned to this mark
            local assigned = CP_GetTanksForMark(capturedMI)
            local tmplT = GetActiveTemplate()
            if table.getn(assigned) > 0 then
                GameTooltip:AddLine("Tanks:", 0.78,0.61,0.43)
                for _,tname in ipairs(assigned) do
                    local cr,cg,cb = 1,1,1
                    if tmplT and tmplT.roster and tmplT.roster[tname] then
                        cr,cg,cb = GetClassColor(tmplT.roster[tname].class)
                    end
                    GameTooltip:AddLine("  "..tname, cr,cg,cb)
                end
            else
                GameTooltip:AddLine("Tanks: (none)", 0.5,0.5,0.5)
            end
            -- List CC assigned to this mark
            if tmplT and tmplT.cc then
                local hasCc = false
                for _,ce in ipairs(tmplT.cc or {}) do
                    if ce.targetType == TYPE_MARK and ce.markIndex == capturedMI then
                        if not hasCc then
                            GameTooltip:AddLine("CC:", 0.6,0.3,0.9)
                            hasCc = true
                        end
                        local cr2,cg2,cb2 = 1,1,1
                        if tmplT.roster and tmplT.roster[ce.name] then
                            cr2,cg2,cb2 = GetClassColor(tmplT.roster[ce.name].class)
                        end
                        GameTooltip:AddLine("  "..ce.name.." ("..ce.spell..")", cr2,cg2,cb2)
                    end
                end
            end
            GameTooltip:AddLine("RMB: assign CC", 0.5,0.5,0.5)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cpMarkButtons[mi] = btn
        -- Store btnFrame reference for border color updates
        btn._frame = btnFrame
    end
    ---------------------------------------------------------------------------
    -- Target button (9th button — Boss/Adds + Custom targets)
    ---------------------------------------------------------------------------
    local targetBtnX = PAD + numIcons*(iconSz+iconGap) + iconGap
    local targetFrame = CreateFrame("Frame", nil, combatPanel)
    targetFrame:SetWidth(targetBtnSz); targetFrame:SetHeight(targetBtnSz)
    targetFrame:SetPoint("LEFT", combatPanel, "LEFT", targetBtnX, 0)
    local targetTex = targetFrame:CreateTexture(nil, "ARTWORK")
    targetTex:SetAllPoints(targetFrame)
    targetTex:SetTexture("Interface\\AddOns\\TankAssign\\textures\\TankAssign_target")
    local targetBtn = CreateFrame("Button", nil, combatPanel)
    targetBtn:SetAllPoints(targetFrame)
    targetBtn:RegisterForClicks("LeftButtonUp")
    targetBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Assign Target")
        GameTooltip:AddLine("Click: Boss/Adds or Custom target", 1,1,1)
        GameTooltip:Show()
    end)
    targetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    -- Three-level dropdown frames for target button
    local tgtDrop1 = nil   -- level 1: Boss/Adds | Custom
    local tgtDrop2 = nil   -- level 2: list of names
    local tgtDrop3 = nil   -- level 3: list of tanks
    local function CloseTgtDropdown()
        if tgtDrop1 then tgtDrop1:Hide() end
        if tgtDrop2 then tgtDrop2:Hide() end
        if tgtDrop3 then tgtDrop3:Hide() end
    end
    local function AssignTargetToTank(ttype, tvalue, anchorBtn)
        local tmpl2 = GetActiveTemplate()
        if not tmpl2 then return end
        local tanks2 = GetTanksSorted(tmpl2)
        if table.getn(tanks2) == 0 then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444TankAssign:|r No tanks tagged.")
            CloseTgtDropdown(); return
        end
        -- Build or reuse tgtDrop3
        if not tgtDrop3 then
            tgtDrop3 = CreateFrame("Frame","TankAssignTgtDrop3",UIParent)
            tgtDrop3:SetFrameStrata("FULLSCREEN_DIALOG")
            tgtDrop3:SetFrameLevel(54)
        tgtDrop3:EnableMouse(true)
            tgtDrop3:SetBackdrop({
                bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
                tile=true,tileSize=8,edgeSize=8,
                insets={left=2,right=2,top=2,bottom=2}
            })
            tgtDrop3:SetBackdropColor(0.06,0.06,0.10,0.97)
            tgtDrop3:SetBackdropBorderColor(0.4,0.4,0.6,0.9)
            tgtDrop3.buttons = {}
        end
        local itemH,pad,w = 22,4,180
        tgtDrop3:SetWidth(w)
        tgtDrop3:SetHeight(table.getn(tanks2)*itemH+pad*2)
        tgtDrop3:ClearAllPoints()
        tgtDrop3:SetPoint("TOPLEFT",anchorBtn,"TOPRIGHT",2,0)
        for _,b3 in ipairs(tgtDrop3.buttons) do b3:Hide() end
        for i,t in ipairs(tanks2) do
            local btn3 = tgtDrop3.buttons[i]
            if not btn3 then
                btn3 = CreateFrame("Button",nil,tgtDrop3)
                btn3:SetHeight(itemH)
                btn3:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                btn3:GetHighlightTexture():SetAlpha(0.4)
                local fs3 = btn3:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                fs3:SetPoint("LEFT",btn3,"LEFT",6,0); fs3:SetJustifyH("LEFT")
                btn3.label = fs3
                tgtDrop3.buttons[i] = btn3
            end
            btn3:ClearAllPoints()
            btn3:SetPoint("TOPLEFT",tgtDrop3,"TOPLEFT",pad,-(pad+(i-1)*itemH))
            btn3:SetWidth(w-pad*2); btn3:Show()
            local tr,tg,tb = GetClassColor(t.class)
            local roleTag = t.tagMT and "[MT]" or (t.tagOT and "[OT]" or "[OOT]")
            btn3.label:SetTextColor(tr,tg,tb)
            btn3.label:SetText(t.name.." "..roleTag)
            local capturedT = t
            local capturedType  = ttype
            local capturedValue = tvalue
            btn3:SetScript("OnClick",function()
                local tmpl3 = GetActiveTemplate()
                if not tmpl3 then CloseTgtDropdown(); return end
                -- Remove existing NAME/CUSTOM assignment for this tank
                local newTanks = {}
                for _,ex in ipairs(tmpl3.tanks or {}) do
                    if not (ex.name == capturedT.name
                        and (ex.targetType == TYPE_NAME or ex.targetType == TYPE_CUSTOM)) then
                        table.insert(newTanks, ex)
                    end
                end
                table.insert(newTanks, {
                    name        = capturedT.name,
                    targetType  = capturedType,
                    targetValue = capturedValue,
                    markIndex   = 0,
                })
                tmpl3.tanks = newTanks
                TankAssign_SyncTemplate()
                UpdateAssignFrame()
                RebuildMainGrid()
                CP_RefreshMarkIndicators()
                CloseTgtDropdown()
            end)
        end
        table.insert(TA_openDropdowns, tgtDrop3)
        tgtDrop3:Show()
    end
    local function ShowTgtDrop2Boss(anchorBtn)
        local zone = GetZoneText() or ""
        local bossData = UBBBossData and UBBBossData[zone] or {}
        if not tgtDrop2 then
            tgtDrop2 = CreateFrame("Frame","TankAssignTgtDrop2",UIParent)
            tgtDrop2:SetFrameStrata("FULLSCREEN_DIALOG")
            tgtDrop2:SetFrameLevel(52)
            tgtDrop2:EnableMouse(true)
            tgtDrop2:SetBackdrop({
                bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
                tile=true,tileSize=8,edgeSize=8,
                insets={left=2,right=2,top=2,bottom=2}
            })
            tgtDrop2:SetBackdropColor(0.06,0.06,0.10,0.97)
            tgtDrop2:SetBackdropBorderColor(0.4,0.4,0.6,0.9)
            tgtDrop2.buttons = {}
        end
        -- Build flat list: boss (orange), then its adds (grey)
        local names = {}
        if table.getn(bossData) == 0 then
            table.insert(names, {text="(no data for "..zone..")", r=0.5,g=0.5,b=0.5, noTarget=true})
        else
            for _,boss in ipairs(bossData) do
                table.insert(names, {text=boss.name, r=1,g=0.65,b=0.2,
                    targetType=TYPE_NAME, targetValue=boss.name})
                for _,add in ipairs(boss.adds or {}) do
                    table.insert(names, {text="  "..add, r=0.75,g=0.75,b=0.75,
                        targetType=TYPE_NAME, targetValue=add})
                end
            end
        end
        local itemH,pad,w = 20,4,200
        tgtDrop2:SetWidth(w)
        tgtDrop2:SetHeight(math.min(table.getn(names),14)*itemH+pad*2)
        tgtDrop2:ClearAllPoints()
        tgtDrop2:SetPoint("TOPLEFT",anchorBtn,"TOPRIGHT",2,0)
        for _,b2 in ipairs(tgtDrop2.buttons) do b2:Hide() end
        for i,entry in ipairs(names) do
            if i > 14 then break end
            local btn2 = tgtDrop2.buttons[i]
            if not btn2 then
                btn2 = CreateFrame("Button",nil,tgtDrop2)
                btn2:SetHeight(itemH)
                btn2:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                btn2:GetHighlightTexture():SetAlpha(0.4)
                local fs2 = btn2:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                fs2:SetPoint("LEFT",btn2,"LEFT",6,0); fs2:SetJustifyH("LEFT")
                btn2.label = fs2
                tgtDrop2.buttons[i] = btn2
            end
            btn2:ClearAllPoints()
            btn2:SetPoint("TOPLEFT",tgtDrop2,"TOPLEFT",pad,-(pad+(i-1)*itemH))
            btn2:SetWidth(w-pad*2); btn2:Show()
            btn2.label:SetTextColor(entry.r,entry.g,entry.b)
            btn2.label:SetText(entry.text)
            local capturedEntry = entry
            if entry.noTarget then
                btn2:SetScript("OnEnter", nil); btn2:SetScript("OnClick", nil)
            else
                btn2:SetScript("OnEnter",function()
                    if tgtDrop3 then tgtDrop3:Hide() end
                    AssignTargetToTank(capturedEntry.targetType, capturedEntry.targetValue, btn2)
                end)
                btn2:SetScript("OnClick",function() end)
            end
        end
        table.insert(TA_openDropdowns, tgtDrop2)
        tgtDrop2:Show()
    end
    local function ShowTgtDrop2Custom(anchorBtn)
        local allCustom = {}
        for _,ct in ipairs(BUILTIN_CUSTOM_TARGETS) do table.insert(allCustom, ct) end
        local userT = TankAssignDB.options and TankAssignDB.options.customTargets or {}
        for _,ct in ipairs(userT) do table.insert(allCustom, ct) end
        if not tgtDrop2 then
            tgtDrop2 = CreateFrame("Frame","TankAssignTgtDrop2",UIParent)
            tgtDrop2:SetFrameStrata("FULLSCREEN_DIALOG")
            tgtDrop2:SetFrameLevel(52)
            tgtDrop2:EnableMouse(true)
            tgtDrop2:SetBackdrop({
                bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
                tile=true,tileSize=8,edgeSize=8,
                insets={left=2,right=2,top=2,bottom=2}
            })
            tgtDrop2:SetBackdropColor(0.06,0.06,0.10,0.97)
            tgtDrop2:SetBackdropBorderColor(0.4,0.4,0.6,0.9)
            tgtDrop2.buttons = {}
        end
        local itemH,pad,w = 20,4,160
        tgtDrop2:SetWidth(w)
        tgtDrop2:SetHeight(table.getn(allCustom)*itemH+pad*2)
        tgtDrop2:ClearAllPoints()
        tgtDrop2:SetPoint("TOPLEFT",anchorBtn,"TOPRIGHT",2,0)
        for _,b2 in ipairs(tgtDrop2.buttons) do b2:Hide() end
        for i,ct in ipairs(allCustom) do
            local btn2 = tgtDrop2.buttons[i]
            if not btn2 then
                btn2 = CreateFrame("Button",nil,tgtDrop2)
                btn2:SetHeight(itemH)
                btn2:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                btn2:GetHighlightTexture():SetAlpha(0.4)
                local fs2 = btn2:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                fs2:SetPoint("LEFT",btn2,"LEFT",6,0); fs2:SetJustifyH("LEFT")
                btn2.label = fs2
                tgtDrop2.buttons[i] = btn2
            end
            btn2:ClearAllPoints()
            btn2:SetPoint("TOPLEFT",tgtDrop2,"TOPLEFT",pad,-(pad+(i-1)*itemH))
            btn2:SetWidth(w-pad*2); btn2:Show()
            btn2.label:SetTextColor(1,1,1)
            btn2.label:SetText(ct)
            local capturedCT = ct
            btn2:SetScript("OnEnter",function()
                if tgtDrop3 then tgtDrop3:Hide() end
                AssignTargetToTank(TYPE_CUSTOM, capturedCT, btn2)
            end)
            btn2:SetScript("OnClick",function() end)
        end
        table.insert(TA_openDropdowns, tgtDrop2)
        tgtDrop2:Show()
    end
    targetBtn:SetScript("OnClick", function()
        if tgtDrop1 and tgtDrop1:IsShown() then
            TA_CloseAllDropdowns(); return
        end
        TA_CloseAllDropdowns()
        if not tgtDrop1 then
            tgtDrop1 = CreateFrame("Frame","TankAssignTgtDrop1",UIParent)
            tgtDrop1:SetFrameStrata("FULLSCREEN_DIALOG")
        tgtDrop1:EnableMouse(true)
            tgtDrop1:SetBackdrop({
                bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
                tile=true,tileSize=8,edgeSize=8,
                insets={left=2,right=2,top=2,bottom=2}
            })
            tgtDrop1:SetBackdropColor(0.06,0.06,0.10,0.97)
            tgtDrop1:SetBackdropBorderColor(0.4,0.4,0.6,0.9)
            tgtDrop1.buttons = {}
        end
        local level1Items = {
            {text="Boss / Adds", r=1,g=0.8,b=0.3, isBoss=true, hasArrow=true},
            {text="Custom",      r=0.4,g=0.9,b=1,  isCustom=true, hasArrow=true},
        }
        local itemH,pad,w = 22,4,160
        tgtDrop1:SetWidth(w)
        tgtDrop1:SetHeight(table.getn(level1Items)*itemH+pad*2)
        tgtDrop1:ClearAllPoints()
        tgtDrop1:SetPoint("TOPLEFT",targetBtn,"BOTTOMLEFT",0,-2)
        for _,b1 in ipairs(tgtDrop1.buttons) do b1:Hide() end
        for i,item in ipairs(level1Items) do
            local btn1 = tgtDrop1.buttons[i]
            if not btn1 then
                btn1 = CreateFrame("Button",nil,tgtDrop1)
                btn1:SetHeight(itemH)
                btn1:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                btn1:GetHighlightTexture():SetAlpha(0.4)
                local fs1 = btn1:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                fs1:SetPoint("LEFT",btn1,"LEFT",6,0)
                fs1:SetPoint("RIGHT",btn1,"RIGHT",-18,0)
                fs1:SetJustifyH("LEFT")
                btn1.label = fs1
                local arrowFS = btn1:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                arrowFS:SetPoint("RIGHT",btn1,"RIGHT",-4,0)
                arrowFS:SetTextColor(0.6,0.6,0.6)
                arrowFS:SetText(">")
                tgtDrop1.buttons[i] = btn1
            end
            btn1:ClearAllPoints()
            btn1:SetPoint("TOPLEFT",tgtDrop1,"TOPLEFT",pad,-(pad+(i-1)*itemH))
            btn1:SetWidth(w-pad*2); btn1:Show()
            btn1.label:SetTextColor(item.r,item.g,item.b)
            btn1.label:SetText(item.text)
            local capturedItem = item
            local capturedBtn  = btn1
            btn1:SetScript("OnEnter",function()
                if tgtDrop2 then tgtDrop2:Hide() end
                if tgtDrop3 then tgtDrop3:Hide() end
                if capturedItem.isBoss        then ShowTgtDrop2Boss(capturedBtn)
                elseif capturedItem.isCustom  then ShowTgtDrop2Custom(capturedBtn) end
            end)
            btn1:SetScript("OnClick",function() end)
        end
        table.insert(TA_openDropdowns, tgtDrop1)
        if tgtDrop2 then table.insert(TA_openDropdowns, tgtDrop2) end
        if tgtDrop3 then table.insert(TA_openDropdowns, tgtDrop3) end
        tgtDrop1:Show()
    end)
    combatPanel._targetBtn = targetBtn
    ---------------------------------------------------------------------------
    -- Preset button (right side)
    ---------------------------------------------------------------------------
    local presetBtn = CreateFrame("Button", nil, combatPanel, "UIPanelButtonTemplate")
    presetBtn:SetWidth(presetBtnW)
    presetBtn:SetHeight(22)
    presetBtn:SetPoint("RIGHT", combatPanel, "RIGHT", -PAD, 0)
    presetBtn:SetText("Presets")
    presetBtn:SetScript("OnClick", function()
        ShowPatternDropdown(presetBtn)
    end)
    presetBtn:SetText("|cff888888Presets|r")
    presetBtn:GetFontString():SetTextColor(0.5,0.5,0.5)
    AddTooltip(presetBtn, "|cffff8800Work in progress.|r\nPreset system is not yet ready.")
    combatPanel._presetBtn = presetBtn
    combatPanel:Show()
    CP_RefreshMarkIndicators()
end
-------------------------------------------------------------------------------
-- OPTIONS FRAME
-------------------------------------------------------------------------------
function TankAssign_OpenOptions()
    if optionsFrame then
        optionsFrame:Raise(); optionsFrame:Show()
        PushWindow(optionsFrame)
        return
    end
    optionsFrame = CreateFrame("Frame","TankAssignOptionsFrame",UIParent)
    optionsFrame:SetWidth(360); optionsFrame:SetHeight(560)
    optionsFrame:SetPoint("CENTER",UIParent,"CENTER")
    optionsFrame:SetMovable(true); optionsFrame:EnableMouse(true)
    optionsFrame:RegisterForDrag("LeftButton")
    optionsFrame:SetScript("OnDragStart",function() this:StartMoving() end)
    optionsFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    optionsFrame:SetFrameStrata("DIALOG"); optionsFrame:SetFrameLevel(20)
    optionsFrame:SetBackdrop({
        bgFile  ="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true,tileSize=8,edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4}
    })
    local _a = (TankAssignDB and TankAssignDB.options and TankAssignDB.options.windowAlpha) or 0.95
    optionsFrame:SetBackdropColor(0.04,0.04,0.1,_a)
    local title = optionsFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOP",optionsFrame,"TOP",0,-12)
    title:SetTextColor(0.4,0.8,1); title:SetText("TankAssign Options")
    local closeBtn = CreateFrame("Button",nil,optionsFrame,"UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT",optionsFrame,"TOPRIGHT",-4,-4)
    closeBtn:SetScript("OnClick",function() optionsFrame:Hide() end)
    HookFrameHide(optionsFrame)
    local y = -44
    -- Font size slider
    local secFont = optionsFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    secFont:SetPoint("TOPLEFT",optionsFrame,"TOPLEFT",14,y)
    secFont:SetTextColor(1,0.8,0.2); secFont:SetText("Assignments Font Size:")
    y = y-30
    local fontSlider = CreateFrame("Slider","TankAssignFontSlider",optionsFrame,"OptionsSliderTemplate")
    fontSlider:SetPoint("TOPLEFT",optionsFrame,"TOPLEFT",16,y)
    fontSlider:SetWidth(200); fontSlider:SetMinMaxValues(8,24); fontSlider:SetValueStep(1)
    fontSlider:SetValue(TankAssignDB.options.fontSize or 12)
    getglobal(fontSlider:GetName().."Text"):SetText("Size: "..(TankAssignDB.options.fontSize or 12))
    getglobal(fontSlider:GetName().."Low"):SetText("8")
    getglobal(fontSlider:GetName().."High"):SetText("24")
    fontSlider:SetScript("OnValueChanged",function()
        local val = math.floor(this:GetValue())
        TankAssignDB.options.fontSize = val
        getglobal(this:GetName().."Text"):SetText("Size: "..val)
        UpdateAssignFrame()
    end)
    y = y-44
    -- Window opacity slider
    local secAlpha = optionsFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    secAlpha:SetPoint("TOPLEFT",optionsFrame,"TOPLEFT",14,y)
    secAlpha:SetTextColor(1,0.8,0.2); secAlpha:SetText("Window Opacity:")
    y = y-30
    local alphaSlider = CreateFrame("Slider","TankAssignAlphaSlider",optionsFrame,"OptionsSliderTemplate")
    alphaSlider:SetPoint("TOPLEFT",optionsFrame,"TOPLEFT",16,y)
    alphaSlider:SetWidth(200); alphaSlider:SetMinMaxValues(0.3,1.0); alphaSlider:SetValueStep(0.05)
    local curA = (TankAssignDB.options and TankAssignDB.options.windowAlpha) or 0.95
    alphaSlider:SetValue(curA)
    getglobal(alphaSlider:GetName().."Text"):SetText(math.floor(curA*100).."%")
    getglobal(alphaSlider:GetName().."Low"):SetText("30%")
    getglobal(alphaSlider:GetName().."High"):SetText("100%")
    alphaSlider:SetScript("OnValueChanged",function()
        local val = math.floor(this:GetValue()*20+0.5)/20
        TankAssignDB.options.windowAlpha = val
        getglobal(this:GetName().."Text"):SetText(math.floor(val*100).."%")
        ApplyWindowAlpha(val)
    end)
    y = y-44
    -- Show assign frame outside raid
    local showCB = CreateFrame("CheckButton","TankAssignShowCB",optionsFrame,"UICheckButtonTemplate")
    showCB:SetWidth(20); showCB:SetHeight(20)
    showCB:SetPoint("TOPLEFT",optionsFrame,"TOPLEFT",14,y)
    showCB:SetChecked(TankAssignDB.options.showAssignFrame)
    showCB:SetScript("OnClick",function()
        TankAssignDB.options.showAssignFrame = this:GetChecked()
        local inRaid = GetNumRaidMembers() > 0
        if assignFrame then
            if inRaid or TankAssignDB.options.showAssignFrame then
                UpdateAssignFrame()
            else
                assignFrame:Hide()
            end
        end
    end)
    local showLabel = optionsFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    showLabel:SetPoint("LEFT",showCB,"RIGHT",4,0)
    showLabel:SetTextColor(0.9,0.9,0.9); showLabel:SetText("Show assignment frame outside raid")
    y = y-26
    -- Hide in Battleground checkbox
    local bgCB = CreateFrame("CheckButton","TankAssignBGCB",optionsFrame,"UICheckButtonTemplate")
    bgCB:SetWidth(20); bgCB:SetHeight(20)
    bgCB:SetPoint("TOPLEFT",optionsFrame,"TOPLEFT",14,y)
    bgCB:SetChecked(TankAssignDB.options.hideInBG ~= false)
    bgCB:SetScript("OnClick",function()
        TankAssignDB.options.hideInBG = this:GetChecked()
        UpdateAssignFrame()
    end)
    local bgLabel = optionsFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    bgLabel:SetPoint("LEFT",bgCB,"RIGHT",4,0)
    bgLabel:SetTextColor(0.9,0.9,0.9); bgLabel:SetText("Hide in Battlegrounds")
    y = y-30
    -- Custom Targets section
    local secCustom = optionsFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    secCustom:SetPoint("TOPLEFT",optionsFrame,"TOPLEFT",14,y)
    secCustom:SetTextColor(1,0.8,0.2); secCustom:SetText("Custom Assignment Targets:")
    y = y-18
    local customNote = optionsFrame:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    customNote:SetPoint("TOPLEFT",optionsFrame,"TOPLEFT",14,y)
    customNote:SetTextColor(0.55,0.55,0.55)
    customNote:SetText("Built-in: Right/Left side, N/S/E/W. Add your own below.")
    y = y-22
    local customEdit = CreateFrame("EditBox","TankAssignCustomEdit",optionsFrame,"InputBoxTemplate")
    customEdit:SetWidth(200); customEdit:SetHeight(20)
    customEdit:SetPoint("TOPLEFT",optionsFrame,"TOPLEFT",14,y)
    customEdit:SetAutoFocus(false); customEdit:SetMaxLetters(48)
    customEdit:SetText("")
    local addCustomBtn = CreateFrame("Button",nil,optionsFrame,"UIPanelButtonTemplate")
    addCustomBtn:SetWidth(60); addCustomBtn:SetHeight(20)
    addCustomBtn:SetPoint("LEFT",customEdit,"RIGHT",5,0)
    addCustomBtn:SetText("Add")
    y = y-28
    local clf = CreateFrame("Frame",nil,optionsFrame)
    clf:SetPoint("TOPLEFT",optionsFrame,"TOPLEFT",14,y)
    clf:SetWidth(320); clf:SetHeight(100)
    clf.rows = {}
    optionsFrame.clf = clf
    local function RefreshCustomList()
        for _,r in ipairs(clf.rows) do r:Hide() end
        clf.rows = {}
        local targets = TankAssignDB.options.customTargets or {}
        for i,ct in ipairs(targets) do
            local row = CreateFrame("Frame",nil,clf)
            row:SetHeight(18); row:SetWidth(320)
            row:SetPoint("TOPLEFT",clf,"TOPLEFT",0,-(i-1)*18)
            table.insert(clf.rows, row)
            local lbl = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            lbl:SetPoint("LEFT",row,"LEFT",2,0)
            lbl:SetTextColor(0.85,0.85,0.85); lbl:SetText(ct)
            local delBtn = CreateFrame("Button",nil,row,"UIPanelButtonTemplate")
            delBtn:SetWidth(22); delBtn:SetHeight(16)
            delBtn:SetPoint("RIGHT",row,"RIGHT",-2,0); delBtn:SetText("X")
            local capturedIdx = i
            delBtn:SetScript("OnClick",function()
                table.remove(TankAssignDB.options.customTargets, capturedIdx)
                RefreshCustomList()
            end)
        end
    end
    addCustomBtn:SetScript("OnClick",function()
        local txt = customEdit:GetText()
        if txt and txt ~= "" then
            if not TankAssignDB.options.customTargets then
                TankAssignDB.options.customTargets = {}
            end
            table.insert(TankAssignDB.options.customTargets, txt)
            customEdit:SetText("")
            RefreshCustomList()
        end
    end)
    RefreshCustomList()
    PushWindow(optionsFrame)
end
-------------------------------------------------------------------------------
-- MAIN FRAME: TANK GRID (removed — assignments are shown in personal windows)
-------------------------------------------------------------------------------
-- Stub kept so existing call sites don't error
RebuildMainGrid = function() end
local function CreateMainFrame()
    if mainFrame then
        if mainFrame:IsShown() then
            mainFrame:Hide(); CloseDropdown()
        else
            mainFrame:Show(); mainFrame:Raise()
            RebuildRosterRows()
            PushWindow(mainFrame)
        end
        return
    end
    mainFrame = CreateFrame("Frame","TankAssignMainFrame",UIParent)
    mainFrame:SetWidth(460); mainFrame:SetHeight(520)
    mainFrame:SetPoint("CENTER",UIParent,"CENTER")
    mainFrame:SetMovable(true); mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart",function() this:StartMoving() end)
    mainFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
    mainFrame:SetFrameStrata("MEDIUM")
    mainFrame:SetBackdrop({
        bgFile  ="Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
        tile=true,tileSize=8,edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4}
    })
    local _a = (TankAssignDB and TankAssignDB.options and TankAssignDB.options.windowAlpha) or 0.95
    mainFrame:SetBackdropColor(0.04,0.04,0.1,_a)
    mainFrame:SetBackdropBorderColor(0.5,0.3,0.1,0.9)
    -- Title
    local title = mainFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOP",mainFrame,"TOP",0,-10)
    title:SetTextColor(1,0.6,0.2)
    title:SetText("TankAssign — Raid Roster")
    -- Close button
    local closeBtn = CreateFrame("Button",nil,mainFrame,"UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT",mainFrame,"TOPRIGHT",-2,-2)
    closeBtn:SetScript("OnClick",function() mainFrame:Hide() end)
    HookFrameHide(mainFrame)
    -- Single centered row of buttons at the bottom
    local btnH   = 22
    local btnY   = 8
    local bW     = {90, 80, 60, 80, 60}  -- Mark Panel, Fear Ward, Sync, Reset Tags, Options
    local bGap   = 4
    local totalBtnW = 0
    for _,w in ipairs(bW) do totalBtnW = totalBtnW + w + bGap end
    totalBtnW = totalBtnW - bGap  -- remove last gap
    -- Anchor first button so the row is centered
    local cpBtn = CreateFrame("Button",nil,mainFrame,"UIPanelButtonTemplate")
    cpBtn:SetWidth(bW[1]); cpBtn:SetHeight(btnH)
    cpBtn:SetPoint("BOTTOM",mainFrame,"BOTTOM", -math.floor(totalBtnW/2) + math.floor(bW[1]/2), btnY)
    cpBtn:SetText("Mark Panel")
    cpBtn:SetScript("OnClick",function()
        if combatPanel and combatPanel:IsShown() then combatPanel:Hide()
        else CreateCombatPanel() end
    end)
    AddTooltip(cpBtn, "Toggle combat marker panel.")
    local fwBtn = CreateFrame("Button",nil,mainFrame,"UIPanelButtonTemplate")
    fwBtn:SetWidth(bW[2]); fwBtn:SetHeight(btnH)
    fwBtn:SetPoint("LEFT",cpBtn,"RIGHT",bGap,0)
    fwBtn:SetText("Fear Ward")
    fwBtn:SetScript("OnClick",function()
        if fwFrame and fwFrame:IsShown() then fwFrame:Hide()
        else CreateFWFrame() end
    end)
    AddTooltip(fwBtn, "Manage Fear Ward queue.")
    local syncBtn = CreateFrame("Button",nil,mainFrame,"UIPanelButtonTemplate")
    syncBtn:SetWidth(bW[3]); syncBtn:SetHeight(btnH)
    syncBtn:SetPoint("LEFT",fwBtn,"RIGHT",bGap,0)
    syncBtn:SetText("Sync")
    syncBtn:SetScript("OnClick",function() TankAssign_SyncTemplate() end)
    AddTooltip(syncBtn, "Broadcast roster and assignments to raid.")
    local resetBtn = CreateFrame("Button",nil,mainFrame,"UIPanelButtonTemplate")
    resetBtn:SetWidth(bW[4]); resetBtn:SetHeight(btnH)
    resetBtn:SetPoint("LEFT",syncBtn,"RIGHT",bGap,0)
    resetBtn:SetText("Reset Tags")
    resetBtn:SetScript("OnClick",function()
        local t2 = GetActiveTemplate()
        if t2 and t2.roster then
            for _,pdata in pairs(t2.roster) do
                pdata.tagMT=nil; pdata.tagOT=nil; pdata.tagOOT=nil; pdata.tagV=nil
            end
            RebuildRosterRows(); UpdateAssignFrame()
        end
    end)
    AddTooltip(resetBtn, "Clear all MT/OT/OOT/V tags.")
    local optBtn = CreateFrame("Button",nil,mainFrame,"UIPanelButtonTemplate")
    optBtn:SetWidth(bW[5]); optBtn:SetHeight(btnH)
    optBtn:SetPoint("LEFT",resetBtn,"RIGHT",bGap,0)
    optBtn:SetText("Options")
    optBtn:SetScript("OnClick",function()
        if optionsFrame and optionsFrame:IsShown() then optionsFrame:Hide()
        else TankAssign_OpenOptions() end
    end)
    AddTooltip(optBtn, "Open options.")
    -- Build embedded roster scroll inside this frame
    CreateRosterFrame()
    InitStaticPopups()
    PushWindow(mainFrame)
end
-------------------------------------------------------------------------------
-- SYNC / COMMUNICATION
-------------------------------------------------------------------------------
local incomingChunks = {}
local CHUNK_SIZE     = 200
function TankAssign_SyncTemplate()
    local tmpl = GetActiveTemplate()
    if not tmpl then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444TankAssign:|r No active template to sync.")
        return
    end
    local channel = GetChannel()
    if not channel then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff4444TankAssign:|r Not in a group.")
        return
    end
    local data = Serialize(tmpl)
    data = string.gsub(data,"%%","{perc}")
    data = string.gsub(data,"\\","{bs}")
    data = string.gsub(data,"|","{pipe}")
    local chunks, len, i = {}, string.len(data), 1
    while i <= len do
        table.insert(chunks, string.sub(data,i,i+CHUNK_SIZE-1))
        i = i+CHUNK_SIZE
    end
    if table.getn(chunks) == 0 then table.insert(chunks,"") end
    local total = table.getn(chunks)
    for ci,chunk in ipairs(chunks) do
        pcall(SendAddonMessage, COMM_PREFIX, "S;"..ci..";"..total..";"..chunk, channel)
    end
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffTankAssign:|r Synced '"..tmpl.name.."' ("..total.." chunk(s)).")
end
local function HandleAddonMessage(prefix, msg, channel, sender)
    if prefix ~= COMM_PREFIX then return end
    local myName = UnitName("player")
    if sender == myName then return end
    -- FW cast broadcast: FW_CAST;priestName
    local _,_,fwCaster = string.find(msg,"^FW_CAST;(.+)$")
    if fwCaster then
        fwCD[fwCaster] = GetTime()
        UpdateAssignFrame()
        if fwFrame and fwFrame:IsShown() then FW_RebuildRows() end
        return
    end
    -- FW assignments new format: FW_ASSIGN2;tank1^p1^p2|tank2^p3
    local _,_,fwData2 = string.find(msg,"^FW_ASSIGN2;(.*)$")
    if fwData2 then
        local tmpl2 = GetActiveTemplate()
        if tmpl2 then
            tmpl2.fw = {tanks={}}
            for _,slotStr in ipairs(SplitStr(fwData2,"|")) do
                if slotStr ~= "" then
                    local fp = SplitStr(slotStr,"^")
                    local tankN = fp[1] or ""
                    if tankN ~= "" then
                        local queue2 = {}
                        for i=2,table.getn(fp) do
                            if fp[i] ~= "" then table.insert(queue2, fp[i]) end
                        end
                        table.insert(tmpl2.fw.tanks, {tankName=tankN, queue=queue2})
                    end
                end
            end
            UpdateAssignFrame()
            if fwFrame and fwFrame:IsShown() then FW_RebuildRows() end
        end
        return
    end
    -- legacy FW_ASSIGN (old clients): FW_ASSIGN;tankName;priest1|priest2
    local _,_,fwData = string.find(msg,"^FW_ASSIGN;(.*)$")
    if fwData then
        local tmpl2 = GetActiveTemplate()
        if tmpl2 then
            local parts2 = SplitStr(fwData,";")
            local tankN = parts2[1] or ""
            local queue2 = {}
            if parts2[2] and parts2[2] ~= "" then
                for _,p in ipairs(SplitStr(parts2[2],"|")) do
                    if p ~= "" then table.insert(queue2, p) end
                end
            end
            tmpl2.fw = {tanks={}}
            if tankN ~= "" then
                table.insert(tmpl2.fw.tanks, {tankName=tankN, queue=queue2})
            end
            UpdateAssignFrame()
            if fwFrame and fwFrame:IsShown() then FW_RebuildRows() end
        end
        return
    end
    -- Taunt CD broadcast: TAUNT_CD;playerName;spellName;castTime
    local _,_,tauntData = string.find(msg,"^TAUNT_CD;(.+)$")
    if tauntData then
        local parts3 = SplitStr(tauntData,";")
        local pname2 = parts3[1]
        local sname  = parts3[2]
        if pname2 and sname then
            if not tauntCD[pname2] then tauntCD[pname2] = {} end
            tauntCD[pname2][sname] = GetTime()  -- approximate
            UpdateAssignFrame()
        end
        return
    end
    -- Death signal: DEAD_TANK;tankName
    local _,_,deadName = string.find(msg,"^DEAD_TANK;(.+)$")
    if deadName then
        local tmpl3 = GetActiveTemplate()
        if tmpl3 then
            local asgn = nil
            for _,t in ipairs(tmpl3.tanks or {}) do
                if t.name == deadName then asgn = t break end
            end
            TriggerTankDeath(deadName, asgn)
            UpdateAssignFrame()
        end
        return
    end
    -- Chunk reassembly
    local _,_,cIdx,tChunks,d = string.find(msg,"^S;(%d+);(%d+);(.*)$")
    if not cIdx then return end
    local chunkIdx    = tonumber(cIdx)
    local totalChunks = tonumber(tChunks)
    if not incomingChunks[sender] or incomingChunks[sender].total ~= totalChunks then
        incomingChunks[sender] = {total=totalChunks, chunks={}}
    end
    incomingChunks[sender].chunks[chunkIdx] = d or ""
    local allReceived = true
    for ii=1,totalChunks do
        if not incomingChunks[sender].chunks[ii] then allReceived=false break end
    end
    if allReceived then
        local fullData = ""
        for ii=1,totalChunks do
            fullData = fullData..incomingChunks[sender].chunks[ii]
        end
        incomingChunks[sender] = nil
        fullData = string.gsub(fullData,"{perc}","%%")
        fullData = string.gsub(fullData,"{bs}","\\")
        fullData = string.gsub(fullData,"{pipe}","|")
        local tmpl4 = Deserialize(fullData)
        if tmpl4 then
            TankAssignDB.templates[tmpl4.name] = tmpl4
            TankAssignDB.activeTemplate = tmpl4.name
            currentTemplate = tmpl4
            DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffTankAssign:|r Received '"..tmpl4.name.."' from "..sender)
            if mainFrame and mainFrame:IsShown() then RebuildMainGrid() end
            UpdateAssignFrame()
        end
    end
end
-------------------------------------------------------------------------------
-- DEATH DETECTION
-------------------------------------------------------------------------------
local deathFrame = CreateFrame("Frame","TankAssignDeathFrame")
deathFrame:RegisterEvent("CHAT_MSG_COMBAT_HOSTILE_DEATH")
deathFrame:RegisterEvent("CHAT_MSG_COMBAT_FRIENDLY_DEATH")
deathFrame:SetScript("OnEvent",function()
    local msg = arg1
    if not msg then return end
    local deadName = nil
    if msg == "You die." then
        deadName = UnitName("player")
    else
        local _,_,cap = string.find(msg,"^(.+) dies%.$")
        if cap then deadName = cap end
    end
    if not deadName then return end
    local tmpl5 = GetActiveTemplate()
    if not tmpl5 then return end
    local numRaid  = GetNumRaidMembers()
    local numParty = GetNumPartyMembers()
    if (not numRaid or numRaid==0) and (not numParty or numParty==0) then return end
    -- Only process if deadName is a tagged tank
    local isTankDeath = false
    local asgn2 = nil
    if tmpl5.roster and tmpl5.roster[deadName] then
        local pd = tmpl5.roster[deadName]
        if pd.tagMT or pd.tagOT or pd.tagOOT then
            isTankDeath = true
            for _,t in ipairs(tmpl5.tanks or {}) do
                if t.name == deadName then asgn2 = t break end
            end
        end
    end
    if not isTankDeath then return end
    local chan = GetChannel()
    if chan then
        pcall(SendAddonMessage, COMM_PREFIX, "DEAD_TANK;"..deadName, chan)
    end
    TriggerTankDeath(deadName, asgn2)
    UpdateAssignFrame()
end)
-- Death ticker (expire old entries)
local alertTicker = CreateFrame("Frame","TankAssignTicker")
local alertTickerElapsed = 0
alertTicker:SetScript("OnUpdate",function()
    alertTickerElapsed = alertTickerElapsed + arg1
    if alertTickerElapsed >= 2 then
        alertTickerElapsed = 0
        if table.getn(deadTanks) > 0 then
            RefreshAlertFrame()
            UpdateAssignFrame()
        end
    end
end)
-- Resurrection detection
local rezFrame = CreateFrame("Frame","TankAssignRezFrame")
rezFrame:RegisterEvent("CHAT_MSG_SPELL_RESURRECT")
rezFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_CASTOTHER")
rezFrame:RegisterEvent("CHAT_MSG_SPELL_OTHER_CASTOTHER")
rezFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
rezFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
rezFrame:SetScript("OnEvent",function()
    if event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_ENTERING_WORLD" then
        local rezCheck = CreateFrame("Frame")
        local rezElapsed = 0
        rezCheck:SetScript("OnUpdate",function()
            rezElapsed = rezElapsed + arg1
            if rezElapsed >= 1.5 then
                rezCheck:SetScript("OnUpdate",nil); rezCheck:Hide()
                CheckAllRezd()
            end
        end)
        return
    end
    local msg2 = arg1
    if not msg2 then return end
    -- Resurrection
    local rezzed = nil
    if string.find(msg2,"^You have been resurrected")
    or string.find(msg2,"^You are resurrected") then
        rezzed = UnitName("player")
    else
        local _,_,cap2 = string.find(msg2,"^(.+) is resurrected")
        if not cap2 then _,_,cap2 = string.find(msg2,"^(.+) comes back to life") end
        if cap2 then rezzed = cap2 end
    end
    if rezzed then RemoveDeadTank(rezzed) return end
end)
-------------------------------------------------------------------------------
-- TAUNT SELF-CAST DETECTION + BROADCAST
-------------------------------------------------------------------------------
-- Taunt detection via function hooks (no external addon required)
-- Hook CastSpellByName and UseAction to detect taunt casts directly
local TA_tauntSpellSet = {}
for _,ts in ipairs(TAUNT_SPELLS) do
    TA_tauntSpellSet[ts.name] = true
end
local function TA_RecordTauntCast(spellName)
    if not TA_tauntSpellSet[spellName] then return end
    local myName = UnitName("player")
    TAUNT_RecordCast(myName, spellName)
    local chan2 = GetChannel()
    if chan2 then
        pcall(SendAddonMessage, COMM_PREFIX,
            "TAUNT_CD;"..myName..";"..spellName, chan2)
    end
    UpdateAssignFrame()
end
-- Hook CastSpellByName (macro /cast)
local TA_OldCSBN = CastSpellByName
CastSpellByName = function(spellName, onSelf)
    TA_OldCSBN(spellName, onSelf)
    if spellName then
        local baseName = string.gsub(spellName, "%s*%(.-%)", "")
        baseName = string.gsub(baseName, "^%s*(.-)%s*$", "%1")
        TA_RecordTauntCast(baseName)
    end
end
-- Hook CastSpell (action bar clicks in 1.12.1)
local TA_OldCS = CastSpell
CastSpell = function(spellId, bookType)
    TA_OldCS(spellId, bookType)
    if bookType == BOOKTYPE_SPELL then
        local spellName = GetSpellName(spellId, BOOKTYPE_SPELL)
        if spellName then
            TA_RecordTauntCast(spellName)
        end
    end
end
-- Hook UseAction — устанавливается после загрузки всех аддонов (в ADDON_LOADED)
-- чтобы быть последним в цепочке хуков (после SpellSystem и других)
local TA_ScanFrame = CreateFrame("GameTooltip", "TankAssignScanTooltip", UIParent, "GameTooltipTemplate")
TA_ScanFrame:SetOwner(UIParent, "ANCHOR_NONE")
local TA_OldUA = nil
local function TA_HookUseAction()
    TA_OldUA = UseAction
    UseAction = function(slot, checkCursor, onSelf)
        local spellName = nil
        pcall(function()
            TA_ScanFrame:ClearLines()
            TA_ScanFrame:SetAction(slot)
            spellName = TankAssignScanTooltipTextLeft1:GetText()
        end)
        TA_OldUA(slot, checkCursor, onSelf)
        if spellName then
            TA_RecordTauntCast(spellName)
        end
    end
end
-- Fallback: chat message patterns
local tauntSelfFrame = CreateFrame("Frame","TankAssignTauntSelf")
tauntSelfFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
tauntSelfFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_BUFF")
tauntSelfFrame:RegisterEvent("CHAT_MSG_SPELL_PERIODIC_SELF_BUFFS")
tauntSelfFrame:RegisterEvent("SPELLCAST_STOP")
-- Track last spell cast via SPELLCAST_START for SPELLCAST_STOP matching
local TA_lastSpellCast = nil
local tauntStartFrame = CreateFrame("Frame","TankAssignTauntStart")
tauntStartFrame:RegisterEvent("SPELLCAST_START")
tauntStartFrame:SetScript("OnEvent",function()
    TA_lastSpellCast = arg1
end)
tauntSelfFrame:SetScript("OnEvent",function()
    local msg3 = arg1 or ""
    if event == "SPELLCAST_STOP" then
        if TA_lastSpellCast then
            TA_RecordTauntCast(TA_lastSpellCast)
            TA_lastSpellCast = nil
        end
        return
    end
    local myName = UnitName("player")
    for _,pat in ipairs(TAUNT_SELF_PATTERNS) do
        if string.find(msg3, pat.pat) then
            TAUNT_RecordCast(myName, pat.spell)
            local chan2 = GetChannel()
            if chan2 then
                pcall(SendAddonMessage, COMM_PREFIX,
                    "TAUNT_CD;"..myName..";"..pat.spell, chan2)
            end
            UpdateAssignFrame()
            break
        end
    end
end)
-------------------------------------------------------------------------------
-- TAUNT CD TICKER
-- Refreshes assign/viewer frames every 1 second while taunt CDs are active
-------------------------------------------------------------------------------
local tauntTickerElapsed = 0
local tauntTicker = CreateFrame("Frame","TankAssignTauntTicker")
tauntTicker:SetScript("OnUpdate",function()
    tauntTickerElapsed = tauntTickerElapsed + arg1
    if tauntTickerElapsed >= 1 then
        tauntTickerElapsed = 0
        -- Only refresh if there are active taunt CDs
        local hasActive = false
        for pname,spells in pairs(tauntCD) do
            for sname,castTime in pairs(spells) do
                local cd = 0
                for _,ts in ipairs(TAUNT_SPELLS) do
                    if ts.name == sname then cd = ts.cd break end
                end
                if cd > 0 and (GetTime() - castTime) < cd then
                    hasActive = true
                    break
                end
            end
            if hasActive then break end
        end
        if hasActive then
            UpdateAssignFrame()
        end
    end
end)
-------------------------------------------------------------------------------
-- FW SELF-CAST DETECTION
-- Priest detects their own Fear Ward cast via combat log
-- "You cast Fear Ward on X." → CHAT_MSG_SPELL_SELF_CASTOTHER
-- Note: CD is recorded immediately on button click (like HA druid),
-- but we also detect via combat log as a fallback (when cast outside addon)
-------------------------------------------------------------------------------
local fwSelfFrame = CreateFrame("Frame","TankAssignFWSelf")
fwSelfFrame:RegisterEvent("CHAT_MSG_SPELL_SELF_CASTOTHER")
fwSelfFrame:SetScript("OnEvent",function()
    local msg4 = arg1 or ""
    if string.find(msg4,"^You cast Fear Ward on ") then
        local myName = UnitName("player")
        FW_RecordCast(myName)
        FW_BroadcastCast(myName)
        UpdateAssignFrame()
        if fwFrame and fwFrame:IsShown() then FW_RebuildRows() end
    end
end)
-- FW ticker: update priest frame every second (CD countdown + alert logic)
local fwTicker = CreateFrame("Frame","TankAssignFWTicker")
local fwTickerElapsed = 0
fwTicker:SetScript("OnUpdate",function()
    fwTickerElapsed = fwTickerElapsed + arg1
    if fwTickerElapsed < 1 then return end
    fwTickerElapsed = 0
    local myName = UnitName("player")
    local tmpl7  = GetActiveTemplate()
    if not tmpl7 or not tmpl7.fw then return end
    local myPd7 = tmpl7.roster and tmpl7.roster[myName]
    if not myPd7 or myPd7.class ~= "PRIEST" then return end
    if assignFrame and assignFrame:IsShown() then UpdateAssignFrame() end
    if fwFrame    and fwFrame:IsShown()    then FW_RebuildRows() end
    -- Find which tank slot I belong to
    local mySlot = nil
    local myPos7 = nil
    for _,slot in ipairs(tmpl7.fw.tanks or {}) do
        for i,p in ipairs(slot.queue or {}) do
            if p == myName then mySlot = slot; myPos7 = i; break end
        end
        if mySlot then break end
    end
    if not mySlot or not mySlot.tankName then return end
    -- Alert: my CD ready and all priests before me in this queue are on CD
    local cdRem7 = FW_GetCDRemaining(myName)
    if cdRem7 > 0 then
        FW_ALERT_SHOWN[myName] = nil
        return
    end
    local iAmNext = true
    if myPos7 > 1 then
        for ii = 1, myPos7-1 do
            local prev = mySlot.queue[ii]
            if prev and FW_GetCDRemaining(prev) <= 0 then
                iAmNext = false; break
            end
        end
    end
    if iAmNext and not FW_ALERT_SHOWN[myName] then
        FW_ALERT_SHOWN[myName] = true
        ShowFWAlert(mySlot.tankName)
    end
end)
-- Taunt CD ticker: update tank personal frame every second
local tauntTicker = CreateFrame("Frame","TankAssignTauntTicker")
local tauntTickerElapsed = 0
tauntTicker:SetScript("OnUpdate",function()
    tauntTickerElapsed = tauntTickerElapsed + arg1
    if tauntTickerElapsed < 1 then return end
    tauntTickerElapsed = 0
    if assignFrame and assignFrame:IsShown() then
        UpdateAssignFrame()
    end
end)
-------------------------------------------------------------------------------
-- RAID TARGET CHANGE TRACKER
-- When a mark moves to a new mob, clear assignments for that mark index
-- so tanks are not shown as assigned to a mob they're not tanking.
-------------------------------------------------------------------------------
local markTracker = CreateFrame("Frame", "TankAssignMarkTracker")
markTracker:RegisterEvent("PLAYER_TARGET_CHANGED")
-- Snapshot of last known mark→mobName mapping
local lastMarkNames = {}  -- [markIndex] = mobName or nil
local function RefreshMarkTracking()
    if not currentTemplate then return end
    local changed = false
    for mi = 1, 8 do
        local unit = "mark"..mi
        local mobName = UnitExists(unit) and UnitName(unit) or nil
        local prev = lastMarkNames[mi]
        if prev ~= mobName then
            -- Mark moved to a different mob (or was cleared)
            if prev ~= nil and mobName ~= prev then
                -- Remove all tank assignments for this mark index
                local filtered = {}
                for _,t in ipairs(currentTemplate.tanks or {}) do
                    if not (t.targetType == TYPE_MARK and t.markIndex == mi) then
                        table.insert(filtered, t)
                    end
                end
                if table.getn(filtered) ~= table.getn(currentTemplate.tanks or {}) then
                    currentTemplate.tanks = filtered
                    changed = true
                end
            end
            lastMarkNames[mi] = mobName
        end
    end
    if changed then
        UpdateAssignFrame()
        RebuildMainGrid()
        CP_RefreshMarkIndicators()
    end
end
markTracker:SetScript("OnEvent", function()
    if event == "PLAYER_TARGET_CHANGED" then
        RefreshMarkTracking()
    end
end)
-------------------------------------------------------------------------------
-- MINIMAP BUTTON
-- Button defined in TankAssign.xml (TankAssignMinimapBtn), same as HealAssign
-------------------------------------------------------------------------------
local function UpdateMinimapPos(a)
    local x = math.cos(math.rad(a)) * 80
    local y = math.sin(math.rad(a)) * 80
    TankAssignMinimapBtn:ClearAllPoints()
    TankAssignMinimapBtn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 52 - x, y - 52)
end
local function CreateMinimapButton()
    if not TankAssignMinimapBtn then return end
    UpdateMinimapPos(TankAssignDB.minimapAngle or 220)
    TankAssignMinimapBtn:Show()
    TankAssignMinimapBtn:SetScript("OnClick", function()
        if arg1 == "RightButton" then
            if optionsFrame and optionsFrame:IsShown() then
                optionsFrame:Hide()
            else
                TankAssign_OpenOptions()
            end
        else
            if not HasEditorRights() then
                DEFAULT_CHAT_FRAME:AddMessage(
                    "|cff00ccffTankAssign:|r Only Raid Leader or Assistant can open the editor.")
                return
            end
            CreateMainFrame()
        end
    end)
    TankAssignMinimapBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(this, "ANCHOR_LEFT")
        GameTooltip:SetText("TankAssign v"..ADDON_VERSION)
        GameTooltip:AddLine("Left click: open main window (RL/Assist)", 1, 1, 1)
        GameTooltip:AddLine("Right click: options", 1, 1, 1)
        GameTooltip:AddLine("Drag: reposition", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    TankAssignMinimapBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    TankAssignMinimapBtn:SetScript("OnDragStart", function()
        this:LockHighlight()
        this:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local s = UIParent:GetEffectiveScale()
            cx, cy = cx/s, cy/s
            local a = math.deg(math.atan2(cy - my, cx - mx))
            TankAssignDB.minimapAngle = a
            UpdateMinimapPos(a)
        end)
    end)
    TankAssignMinimapBtn:SetScript("OnDragStop", function()
        this:UnlockHighlight()
        this:SetScript("OnUpdate", nil)
    end)
end
-------------------------------------------------------------------------------
-- PATTERN SYSTEM
-- Presets stored in TankAssignDB.presets[zone][name] = {{markIndex, mobName}, ...}
-- Two-level dropdown: Save / Load -> list of presets for current zone
-------------------------------------------------------------------------------
local patternDropFrame  = nil  -- level-1 dropdown (Save / Load)
local patternListFrame  = nil  -- level-2 dropdown (preset names)
ShowPatternDropdown = function(anchorBtn)
    -- Toggle: if already open, close
    if patternDropFrame and patternDropFrame:IsShown() then
        TA_CloseAllDropdowns()
        return
    end
    TA_CloseAllDropdowns()
    local zone = GetZoneText() or "Unknown"
    if not patternDropFrame then
        patternDropFrame = CreateFrame("Frame", "TankAssignPatternDrop", UIParent)
        patternDropFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        patternDropFrame:SetFrameLevel(50)
        patternDropFrame:EnableMouse(true)
        patternDropFrame:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true, tileSize=8, edgeSize=8,
            insets={left=2,right=2,top=2,bottom=2}
        })
        patternDropFrame:SetBackdropColor(0.06,0.06,0.10,0.97)
        patternDropFrame:SetBackdropBorderColor(0.4,0.4,0.6,0.9)
    end
    if not patternListFrame then
        patternListFrame = CreateFrame("Frame", "TankAssignPatternList", UIParent)
        patternListFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        patternListFrame:SetFrameLevel(52)
        patternListFrame:EnableMouse(true)
        patternListFrame:SetBackdrop({
            bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true, tileSize=8, edgeSize=8,
            insets={left=2,right=2,top=2,bottom=2}
        })
        patternListFrame:SetBackdropColor(0.06,0.06,0.10,0.97)
        patternListFrame:SetBackdropBorderColor(0.4,0.4,0.6,0.9)
        patternListFrame.buttons = {}
        patternListFrame:Hide()
    end
    local itemH = 22
    local pad   = 4
    local w1    = 120
    -- Level 1: Save / Load
    local items = {
        { text = "Save Pattern", isSave = true },
        { text = "Load", isLoad = true, hasArrow = true },
    }
    patternDropFrame:SetWidth(w1)
    patternDropFrame:SetHeight(table.getn(items)*itemH + pad*2)
    patternDropFrame:ClearAllPoints()
    patternDropFrame:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    if not patternDropFrame.buttons then patternDropFrame.buttons = {} end
    for _,b in ipairs(patternDropFrame.buttons) do b:Hide() end
    for i,item in ipairs(items) do
        local btn = patternDropFrame.buttons[i]
        if not btn then
            btn = CreateFrame("Button", nil, patternDropFrame)
            btn:SetHeight(itemH)
            btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            btn:GetHighlightTexture():SetAlpha(0.4)
            local fs = btn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            fs:SetPoint("LEFT",btn,"LEFT",6,0)
            fs:SetPoint("RIGHT",btn,"RIGHT",-18,0)
            fs:SetJustifyH("LEFT")
            btn.label = fs
            local arrowFS = btn:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
            arrowFS:SetPoint("RIGHT",btn,"RIGHT",-4,0)
            arrowFS:SetTextColor(0.6,0.6,0.6)
            btn.arrowLabel = arrowFS
            patternDropFrame.buttons[i] = btn
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT",patternDropFrame,"TOPLEFT",pad,-(pad+(i-1)*itemH))
        btn:SetWidth(w1-pad*2)
        btn:Show()
        btn.label:SetTextColor(1,1,1)
        btn.label:SetText(item.text)
        if btn.arrowLabel then
            btn.arrowLabel:SetText(item.hasArrow and ">" or "")
        end
        local capturedItem = item
        local capturedZone = zone
        if item.isSave then
            btn:SetScript("OnEnter", function() patternListFrame:Hide() end)
            btn:SetScript("OnClick", function()
                -- Save current marks on all visible units
                local snapshot = {}
                -- Scan all raid members
                for ri = 1, GetNumRaidMembers() do
                    local unit = "raid"..ri
                    local idx  = GetRaidTargetIndex(unit)
                    if idx and idx > 0 then
                        local mname = UnitName(unit)
                        if mname then
                            local dup = false
                            for _,s in ipairs(snapshot) do
                                if s.markIndex == idx then dup = true break end
                            end
                            if not dup then
                                table.insert(snapshot, {markIndex=idx, mobName=mname})
                            end
                        end
                    end
                end
                -- Also check target
                if UnitExists("target") then
                    local idx = GetRaidTargetIndex("target")
                    if idx and idx > 0 then
                        local mname = UnitName("target")
                        if mname then
                            local dup = false
                            for _,s in ipairs(snapshot) do
                                if s.markIndex == idx then dup = true break end
                            end
                            if not dup then
                                table.insert(snapshot, {markIndex=idx, mobName=mname})
                            end
                        end
                    end
                end
                if table.getn(snapshot) == 0 then
                    DEFAULT_CHAT_FRAME:AddMessage(
                        "|cffff4444TankAssign:|r No marked units found. Mark mobs first.")
                    TA_CloseAllDropdowns()
                    return
                end
                -- Ask for name via static popup
                TA_CloseAllDropdowns()
                StaticPopupDialogs["TANKASSIGN_SAVE_PATTERN"] = {
                    text         = "Save pattern for |cffffd700"..capturedZone.."|r\nEnter name:",
                    button1      = "Save",
                    button2      = "Cancel",
                    hasEditBox   = 1,
                    maxLetters   = 40,
                    timeout      = 0,
                    whileDead    = false,
                    hideOnEscape = true,
                    OnAccept = function()
                        local name = getglobal(this:GetParent():GetName().."EditBox"):GetText()
                        if not name or name == "" then return end
                        if not TankAssignDB.presets then TankAssignDB.presets = {} end
                        if not TankAssignDB.presets[capturedZone] then
                            TankAssignDB.presets[capturedZone] = {}
                        end
                        TankAssignDB.presets[capturedZone][name] = snapshot
                        DEFAULT_CHAT_FRAME:AddMessage(
                            "|cff00ccffTankAssign:|r Pattern '|cffffffff"..name..
                            "|r' saved for "..capturedZone.." ("..table.getn(snapshot).." marks).")
                    end,
                }
                StaticPopup_Show("TANKASSIGN_SAVE_PATTERN")
            end)
        elseif item.isLoad then
            btn:SetScript("OnEnter", function()
                -- Build list of presets for current zone
                local zonePresets = TankAssignDB.presets and TankAssignDB.presets[capturedZone] or {}
                local names = {}
                for n,_ in pairs(zonePresets) do table.insert(names, n) end
                table.sort(names)
                if table.getn(names) == 0 then
                    patternListFrame:Hide()
                    return
                end
                local maxVisible = 10
                local w2 = 160
                local visCount = math.min(table.getn(names), maxVisible)
                patternListFrame:SetWidth(w2)
                patternListFrame:SetHeight(visCount*itemH + pad*2)
                patternListFrame:ClearAllPoints()
                patternListFrame:SetPoint("TOPLEFT", btn, "TOPRIGHT", 2, 0)
                for _,b2 in ipairs(patternListFrame.buttons) do b2:Hide() end
                for j,pname in ipairs(names) do
                    if j > maxVisible then break end
                    local btn2 = patternListFrame.buttons[j]
                    if not btn2 then
                        btn2 = CreateFrame("Button", nil, patternListFrame)
                        btn2:SetHeight(itemH)
                        btn2:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
                        btn2:GetHighlightTexture():SetAlpha(0.4)
                        local fs2 = btn2:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
                        fs2:SetPoint("LEFT",btn2,"LEFT",6,0)
                        fs2:SetPoint("RIGHT",btn2,"RIGHT",-4,0)
                        fs2:SetJustifyH("LEFT")
                        btn2.label = fs2
                        patternListFrame.buttons[j] = btn2
                    end
                    btn2:ClearAllPoints()
                    btn2:SetPoint("TOPLEFT",patternListFrame,"TOPLEFT",pad,-(pad+(j-1)*itemH))
                    btn2:SetWidth(w2-pad*2)
                    btn2:Show()
                    btn2.label:SetTextColor(1,0.85,0.3)
                    btn2.label:SetText(pname)
                    local capturedPreset = zonePresets[pname]
                    local capturedName   = pname
                    btn2:SetScript("OnClick", function()
                        -- Apply pattern: target each mob by name and set mark
                        local applied = 0
                        for _,entry in ipairs(capturedPreset or {}) do
                            if entry.mobName and entry.markIndex then
                                TargetByName(entry.mobName, false)
                                if UnitExists("target") then
                                    SetRaidTarget("target", entry.markIndex)
                                    applied = applied + 1
                                    ClearTarget()
                                end
                            end
                        end
                        DEFAULT_CHAT_FRAME:AddMessage(
                            "|cff00ccffTankAssign:|r Pattern '|cffffffff"..capturedName..
                            "|r' applied ("..applied.." marks set).")
                        TA_CloseAllDropdowns()
                    end)
                end
                patternListFrame:Show()
            end)
            btn:SetScript("OnClick", function() end)
        end
    end
    table.insert(TA_openDropdowns, patternDropFrame)
    table.insert(TA_openDropdowns, patternListFrame)
    patternDropFrame:Show()
end
-------------------------------------------------------------------------------
-- MAIN EVENT HANDLER
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame","TankAssignEventFrame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("RAID_ROSTER_UPDATE")
eventFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent",function()
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            InitDB()
            if TankAssignDB.activeTemplate
            and TankAssignDB.templates[TankAssignDB.activeTemplate] then
                currentTemplate = TankAssignDB.templates[TankAssignDB.activeTemplate]
                if not currentTemplate.roster then currentTemplate.roster = {} end
                if not currentTemplate.tanks  then currentTemplate.tanks  = {} end
                if not currentTemplate.fw     then
                    currentTemplate.fw = {tankName=nil, queue={}}
                end
            end
            if not currentTemplate then currentTemplate = NewTemplate("") end
            CreateAssignFrame()
            CreateAlertFrame()
            CreateFWAlertFrame()
            if GetNumRaidMembers() > 0 then UpdateAssignFrame() end
            DEFAULT_CHAT_FRAME:AddMessage(
                "|cff00ccffTankAssign|r v"..ADDON_VERSION.." loaded.  |cffffffff/ta|r  or  |cffffffff/tankassign|r")
            TA_HookUseAction()
            CreateMinimapButton()
        end
    elseif event == "CHAT_MSG_ADDON" then
        HandleAddonMessage(arg1,arg2,arg3,arg4)
    elseif event == "PLAYER_ENTERING_WORLD" then
        UpdateAssignFrame()
    elseif event == "RAID_ROSTER_UPDATE" or event == "PARTY_MEMBERS_CHANGED" then
        local inRaid = GetNumRaidMembers() > 0
        if assignFrame then
            if inRaid then
                UpdateAssignFrame()
            else
                local showOut = TankAssignDB and TankAssignDB.options
                    and TankAssignDB.options.showAssignFrame
                if showOut then UpdateAssignFrame()
                else assignFrame:Hide() end
            end
        end
        if inRaid then
            if mainFrame and mainFrame:IsShown() then RebuildRosterRows() end
            -- Auto-show personal assign window for tagged tanks
            local myName2  = UnitName("player")
            local tmpl2    = GetActiveTemplate()
            local myPdata2 = tmpl2 and tmpl2.roster and tmpl2.roster[myName2]
            local isTank2  = myPdata2 and (myPdata2.tagMT or myPdata2.tagOT or myPdata2.tagOOT)
            if isTank2 then UpdateAssignFrame() end
        else
            if currentTemplate then
                currentTemplate.roster = {}
                currentTemplate.tanks  = {}
                currentTemplate.cc     = {}
                currentTemplate.fw     = {tankName=nil, queue={}}
            end
        end
    end
end)
-------------------------------------------------------------------------------
-- SLASH COMMANDS
-------------------------------------------------------------------------------
SLASH_TANKASSIGN1 = "/tankassign"
SLASH_TANKASSIGN2 = "/ta"
SlashCmdList["TANKASSIGN"] = function(msg)
    msg = string.lower(msg or "")
    if msg == "sync" then
        TankAssign_SyncTemplate()
    elseif msg == "options" or msg == "opt" then
        if optionsFrame and optionsFrame:IsShown() then optionsFrame:Hide()
        else TankAssign_OpenOptions() end
    elseif msg == "assign" then
        if assignFrame then
            if assignFrame:IsShown() then assignFrame:Hide()
            else UpdateAssignFrame() end
        end
    elseif msg == "panel" then
        if combatPanel and combatPanel:IsShown() then combatPanel:Hide()
        else CreateCombatPanel() end
    elseif msg == "fw" then
        if HasEditorRights() then
            if fwFrame and fwFrame:IsShown() then fwFrame:Hide()
            else CreateFWFrame() end
        else
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444TankAssign:|r Only Raid Leader or Assistant can manage Fear Ward queue.")
        end
    elseif msg == "icons" then
        -- Debug: print actual icon paths for all taunt spells from spellbook
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffTankAssign:|r Taunt spell icons:")
        for i = 1, GetNumSpells and GetNumSpells() or 300 do
            local sName = GetSpellName(i, BOOKTYPE_SPELL)
            if not sName then break end
            for _,ts in ipairs(TAUNT_SPELLS) do
                if sName == ts.name then
                    local tex = GetSpellTexture(i, BOOKTYPE_SPELL) or "nil"
                    DEFAULT_CHAT_FRAME:AddMessage("  "..ts.name..": "..tex)
                end
            end
        end
    elseif msg == "help" then
        DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffTankAssign|r v"..ADDON_VERSION.."  commands:")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/ta|r           - Toggle main window (RL/Assist only)")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/ta sync|r      - Broadcast template to group")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/ta assign|r    - Toggle personal assignment frame")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/ta panel|r     - Toggle combat marker panel")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/ta fw|r        - Toggle Fear Ward queue manager")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/ta options|r   - Open options")
        DEFAULT_CHAT_FRAME:AddMessage("  |cffffffff/ta help|r      - This help")
    else
        -- Default: toggle main frame (RL/Assist only)
        if not HasEditorRights() then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4444TankAssign:|r Only Raid Leader or Assistant can open the editor.")
            return
        end
        CreateMainFrame()
    end
end