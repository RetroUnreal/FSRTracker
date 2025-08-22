-- FSRTracker - hardcoded spell-name triggers (Project Epoch / 3.3.5a)
-- Blue 5s sweep (FSR) -> wait for first real mana tick via UNIT_MANA -> 2s green pulses -> stop when full

local FSR_DURATION = 5
local TICK_INTERVAL = 2
local debugPrint = false

-- scale settings
local MIN_SCALE, MAX_SCALE = 0.5, 3.0
local barScale = 1.0  -- default; we'll override from SavedVariables on PLAYER_LOGIN

-- preview flag (so we can hide the bar again on lock if it was only shown for positioning)
local isPreview = false

-- ========= Safe debug print =========
local function sjoin(...)
  local out = {}
  for i = 1, select("#", ...) do out[i] = tostring(select(i, ...)) end
  return table.concat(out, " ")
end
local function dprint(...) if debugPrint then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffFSR|r "..sjoin(...)) end end

-- ========= TRIGGER SET =========
-- Lower-case spell names for O(1) lookups (case-insensitive).
local TRIGGERS = (function()
  local t = {}
  local function add(name) t[string.lower(name)] = true end

  -- Druid
  add("Frostbolt")
  add("Fireball")
  add("Arcane Explosion")
  add("Arcane Missiles")
  add("Fire Blast")
  add("Frost Nova")
  add("Barkskin")
  add("Cyclone")
  add("Entangling Roots")
  add("Faerie Fire")
  add("Force of Nature")
  add("Hibernate")
  add("Hurricane")
  add("Innervate")
  add("Insect Swarm")
  add("Moonfire")
  add("Moonkin Form")
  add("Soothe Animal")
  add("Starfire")
  add("Teleport: Moonglade")
  add("Thorns")
  add("Wrath")
  add("Aquatic Form")
  add("Cat Form")
  add("Bear Form")
  add("Dire Bear Form")
  add("Travel Form")
  add("Abolish Poison")
  add("Gift of the Wild")
  add("Healing Touch")
  add("Lifebloom")
  add("Mark of the Wild")
  add("Overgrowth")
  add("Rebirth")
  add("Regrowth")
  add("Rejuvenation")
  add("Remove Curse")
  add("Revive")
  add("Swiftmend")
  add("Tranquility")
  add("Tree of Life")

  -- Hunter
  add("Aspect of the Beast")
  add("Aspect of the Cheetah")
  add("Aspect of the Hawk")
  add("Aspect of the Monkey")
  add("Aspect of the Pack")
  add("Aspect of the Viper")
  add("Aspect of the Wild")
  add("Beast Lore")
  add("Bestial Wrath")
  add("Eagle Eye")
  add("Eyes of the Beast")
  add("Intimidation")
  add("Kill Command")
  add("Mend Pet")
  add("Revive Pet")
  add("Scare Beast")
  add("Tame Beast")
  add("Aimed Shot")
  add("Arcane Shot")
  add("Concussive Shot")
  add("Distracting Shot")
  add("Flare")
  add("Hunter's Mark")
  add("Multi-Shot")
  add("Scatter Shot")
  add("Scorpid Sting")
  add("Rapid Fire")
  add("Serpent Sting")
  add("Silencing Shot")
  add("Steady Shot")
  add("Tranquilizing Shot")
  add("Viper Sting")
  add("Volley")
  add("Counterattack")
  add("Disengage")
  add("Explosive Trap")
  add("Feign Death")
  add("Freezing Trap")
  add("Frost Trap")
  add("Immolation Trap")
  add("Misdirection")
  add("Mongoose Bite")
  add("Raptor Strike")
  add("Snake Trap")
  add("Wing Clip")
  add("Wyvern Sting")

  -- Mage (Arcane/Fire/Frost + utility)
  add("Amplify Magic")
  add("Arcane Barrage")
  add("Arcane Blast")
  add("Arcane Brilliance")
  add("Arcane Intellect")
  add("Blink")
  add("Conjure Food")
  add("Conjure Mana Agate")
  add("Conjure Mana Citrine")
  add("Conjure Mana Jade")
  add("Conjure Mana Ruby")
  add("Conjure Water")
  add("Conjure Weapon")
  add("Counterspell")
  add("Dampen Magic")
  add("Invisibility")
  add("Mage Armor")
  add("Mana Shield")
  add("Polymorph")
  add("Portal: Darnassus")
  add("Portal: Ironforge")
  add("Portal: Orgrimmar")
  add("Portal: Stonard")
  add("Portal: Stormwind")
  add("Portal: Theramore")
  add("Portal: Thunder Bluff")
  add("Portal: Undercity")
  add("Remove Lesser Curse")
  add("Ritual of Refreshment")
  add("Rune of Power")
  add("Slow")
  add("Slow Fall")
  add("Spellsteal")
  add("Teleport: Darnassus")
  add("Teleport: Ironforge")
  add("Teleport: Orgrimmar")
  add("Teleport: Stonard")
  add("Teleport: Stormwind")
  add("Teleport: Theramore")
  add("Teleport: Thunder Bluff")
  add("Teleport: Undercity")
  add("Blast Wave")
  add("Dragon's Breath")
  add("Fire Blast")
  add("Fire Ward")
  add("Fireball")
  add("Flamestrike")
  add("Molten Armor")
  add("Pyroblast")
  add("Scorch")
  add("Blizzard")
  add("Cone of Cold")
  add("Frost Armor")
  add("Frost Ward")
  add("Ice Armor")
  add("Ice Barrier")
  add("Ice Block")
  add("Ice Lance")
  add("Icy Veins")
  add("Summon Water Elemental")

  -- Paladin (Holy/Prot/Ret + racials)
  add("Blessing of Light")
  add("Blessing of Wisdom")
  add("Cleanse")
  add("Consecration")
  add("Divine Favor")
  add("Exorcism")
  add("Flash of Light")
  add("Greater Blessing of Light")
  add("Greater Blessing of Wisdom")
  add("Holy Light")
  add("Holy Shock")
  add("Holy Wrath")
  add("Purify")
  add("Redemption")
  add("Seal of Light")
  add("Seal of Righteousness")
  add("Seal of Wisdom")
  add("Turn Evil")
  add("Turn Undead")
  add("Avenger's Shield")
  add("Blessing of Kings")
  add("Blessing of Salvation")
  add("Blessing of Sanctuary")
  add("Divine Protection")
  add("Divine Shield")
  add("Greater Blessing of Kings")
  add("Greater Blessing of Salvation")
  add("Greater Blessing of Sanctuary")
  add("Hammer of Justice")
  add("Hand of Freedom")
  add("Hand of Protection")
  add("Hand of Sacrifice")
  add("Holy Shield")
  add("Righteous Defense")
  add("Righteous Fury")
  add("Seal of Justice")
  add("Avenging Wrath")
  add("Blessing of Might")
  add("Crusader Strike")
  add("Greater Blessing of Might")
  add("Hammer of Wrath")
  add("Judgement")
  add("Repentance")
  add("Seal of Command")
  add("Seal of Dedication")
  add("Seal of the Crusader")
  add("Seal of Penitence")
  add("Seal of the Mountain")
  add("Seal of Vengeance")

  -- Priest (Discipline/Holy/Shadow + racials)
  add("Dispel Magic")
  add("Divine Spirit")
  add("Fear Ward")
  add("Inner Fire")
  add("Levitate")
  add("Mana Burn")
  add("Mass Dispel")
  add("Pain Suppression")
  add("Power Infusion")
  add("Power Word: Barrier")
  add("Power Word: Fortitude")
  add("Power Word: Shield")
  add("Prayer of Fortitude")
  add("Prayer of Spirit")
  add("Shackle Undead")
  add("Abolish Disease")
  add("Binding Heal")
  add("Bless Water")
  add("Circle of Healing")
  add("Cure Disease")
  add("Flash Heal")
  add("Greater Heal")
  add("Heal")
  add("Holy Fire")
  add("Holy Nova")
  add("Lesser Heal")
  add("Lightwell")
  add("Prayer of Healing")
  add("Prayer of Mending")
  add("Renew")
  add("Resurrection")
  add("Smite")
  add("Fade")
  add("Mind Blast")
  add("Mind Control")
  add("Mind Flay")
  add("Mind Soothe")
  add("Mind Vision")
  add("Prayer of Shadow Protection")
  add("Psychic Scream")
  add("Shadow Protection")
  add("Shadow Word: Death")
  add("Shadow Word: Pain")
  add("Shadowfiend")
  add("Shadowform")
  add("Silence")
  add("Vampiric Embrace")
  add("Vampiric Touch")
  add("An'she's Protection")
  add("Bedside Manner")
  add("Chastise")
  add("Devouring Plague")
  add("Elune's Grace")
  add("Feedback")
  add("Hex of Weakness")
  add("Shadowguard")
  add("Touch of Weakness")

  -- Shaman
  add("Chain Lightning")
  add("Earth Shock")
  add("Earthbind Totem")
  add("Fire Elemental Totem")
  add("Fire Nova Totem")
  add("Flame Shock")
  add("Frost Shock")
  add("Lightning Bolt")
  add("Magma Totem")
  add("Molten Blast")
  add("Purge")
  add("Searing Totem")
  add("Soothe Elemental")
  add("Stoneclaw Totem")
  add("Totem of Wrath")
  add("Astral Recall")
  add("Bloodlust")
  add("Earth Elemental Totem")
  add("Far Sight")
  add("Fire Resistance Totem")
  add("Flametongue Totem")
  add("Flametongue Weapon")
  add("Frost Resistance Totem")
  add("Frostbrand Weapon")
  add("Ghost Wolf")
  add("Grace of Air Totem")
  add("Grounding Totem")
  add("Heroism")
  add("Lightning Shield")
  add("Nature Resistance Totem")
  add("Rockbiter Weapon")
  add("Sentry Totem")
  add("Stoneskin Totem")
  add("Stormstrike")
  add("Strength of Earth Totem")
  add("Water Breathing")
  add("Water Walking")
  add("Windfury Weapon")
  add("Windwall Totem")
  add("Windfury Totem")
  add("Wrath of Air Totem")
  add("Ancestral Spirit")
  add("Chain Heal")
  add("Cure Disease")
  add("Cure Poison")
  add("Disease Cleansing Totem")
  add("Earth Shield")
  add("Healing Stream Totem")
  add("Healing Wave")
  add("Lesser Healing Wave")
  add("Mana Spring Totem")
  add("Mana Tide Totem")
  add("Poison Cleansing Totem")
  add("Tranquil Air Totem")
  add("Tremor Totem")
  add("Reincarnation")

  -- Warlock (Aff/Demo/Destro + utility)
  add("Bane of Agony")
  add("Bane of Doom")
  add("Bane of Exhaustion")
  add("Bane of Tongues")
  add("Corruption")
  add("Curse of Recklessness")
  add("Curse of the Elements")
  add("Curse of Weakness")
  add("Death Coil")
  add("Drain Life")
  add("Drain Mana")
  add("Drain Soul")
  add("Fear")
  add("Howl of Terror")
  add("Seed of Corruption")
  add("Siphon Life")
  add("Unstable Affliction")
  add("Banish")
  add("Create Firestone")
  add("Create Healthstone")
  add("Create Soulstone")
  add("Create Spellstone")
  add("Demon Armor")
  add("Demon Skin")
  add("Demonic Empowerment")
  add("Detect Invisibility")
  add("Enslave Demon")
  add("Eye of Kilrogg")
  add("Fel Armor")
  add("Inferno")
  add("Ritual of Doom")
  add("Ritual of Souls")
  add("Ritual of Summoning")
  add("Shadow Ward")
  add("Soul Link")
  add("Soul Pact")
  add("Summon Felguard")
  add("Unending Breath")
  add("Summon Imp")
  add("Summon Voidwalker")
  add("Summon Succubus")
  add("Summon Felhunter")
  add("Summon Infernal")
  add("Summon Doomguard")
  add("Conflagrate")
  add("Hellfire")
  add("Immolate")
  add("Incinerate")
  add("Rain of Fire")
  add("Searing Pain")
  add("Shadow Bolt")
  add("Shadowburn")
  add("Shadowfury")
  add("Soul Fire")

  return t
end)()

-- Spells we explicitly ignore (case-insensitive)
local IGNORE = (function()
  local t = {}
  t[string.lower("Faerie Fire (Feral)")] = true
  return t
end)()

-- ========= UI (bar) =========
local bar = CreateFrame("StatusBar", "FSR_Bar", UIParent)
bar:SetSize(300, 16)
bar:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
bar:GetStatusBarTexture():SetHorizTile(false)
bar:SetMinMaxValues(0, FSR_DURATION)
bar:SetValue(0)
bar:SetStatusBarColor(0, 0.5, 1, 1)
bar:SetScale(barScale)  -- default; will be re-applied from SVs on PLAYER_LOGIN
bar:Hide()

-- background
local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
if bg.SetColorTexture then bg:SetColorTexture(0, 0, 0, 0.5) else bg:SetTexture(0, 0, 0, 0.5) end

-- spark
local spark = bar:CreateTexture(nil, "OVERLAY")
spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
spark:SetSize(16, 32)
spark:SetBlendMode("ADD")
spark:SetPoint("CENTER", bar, "LEFT", 0, 0)

-- drag support (off by default; use /fsr unlock)
bar:SetMovable(true)
bar:EnableMouse(false)
bar:RegisterForDrag("LeftButton")
bar:SetScript("OnDragStart", function(self) if self.isUnlocked then self:StartMoving() end end)
bar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

-- ========= State / Logic =========
local f = CreateFrame("Frame")
local lastCastTime, tracking = 0, false
local firstTickSeen, tickStart = false, 0
local lastMana = UnitMana("player") or 0

local function UpdateSpark()
  local _, maxv = bar:GetMinMaxValues()
  local width = bar:GetWidth()
  local percent = (maxv > 0) and (bar:GetValue() / maxv) or 0
  spark:SetPoint("CENTER", bar, "LEFT", width * percent, 0)
end

local function StopFSR(self)
  tracking = false
  bar:Hide()
  if self then self:SetScript("OnUpdate", nil) end
  firstTickSeen = false
end

local function StartFSR()
  lastCastTime = GetTime()
  tracking = true
  firstTickSeen = false
  tickStart = 0
  lastMana = UnitMana("player") or 0

  bar:SetMinMaxValues(0, FSR_DURATION)
  bar:SetValue(0)
  bar:SetStatusBarColor(0, 0.5, 1, 1) -- blue
  bar:Show()
  isPreview = false -- clear preview flag when real tracking begins

  f:SetScript("OnUpdate", function(self, elapsed)
    if not tracking then return end
    local now = GetTime()
    local dt = now - lastCastTime

    if dt <= FSR_DURATION then
      bar:SetMinMaxValues(0, FSR_DURATION)
      bar:SetValue(dt)
      bar:SetStatusBarColor(0, 0.5, 1, 1)
    else
      if firstTickSeen then
        local since = now - tickStart
        bar:SetMinMaxValues(0, TICK_INTERVAL)
        bar:SetValue(since % TICK_INTERVAL)
        bar:SetStatusBarColor(0, 1, 0, 0.6) -- green
      else
        bar:SetMinMaxValues(0, TICK_INTERVAL)
        bar:SetValue(0)
        bar:SetStatusBarColor(0, 1, 0, 0.6)
      end
    end

    UpdateSpark()
  end)
end

-- ========= Event Handling =========
local function MaybeTriggerFSR(spellName)
  if not spellName or spellName == "" then return end
  local key = string.lower(spellName)
  if IGNORE[key] then
    dprint("Ignored:", spellName)
    return
  end
  if TRIGGERS[key] then
    dprint("Trigger:", spellName)
    StartFSR()
  else
    dprint("Not in list:", spellName)
  end
end

-- Spellcast events: start blue bar ASAP
f:RegisterEvent("UNIT_SPELLCAST_SENT")
f:RegisterEvent("UNIT_SPELLCAST_START")
f:SetScript("OnEvent", function(_, event, unit, arg2)
  if event == "UNIT_SPELLCAST_SENT" then
    if unit ~= "player" then return end
    MaybeTriggerFSR(arg2) -- args: unit, spell, rank, target
  elseif event == "UNIT_SPELLCAST_START" then
    if unit ~= "player" then return end
    local name = UnitCastingInfo("player")
    MaybeTriggerFSR(name)
  end
end)

-- Mana events (Wrath client): detect first tick + stop when full
local manaFrame = CreateFrame("Frame")
manaFrame:RegisterEvent("UNIT_MANA")
manaFrame:RegisterEvent("UNIT_MAXMANA")
manaFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
manaFrame:SetScript("OnEvent", function(self, event, unit)
  if event == "PLAYER_ENTERING_WORLD" then
    lastMana = UnitMana("player") or 0
    return
  end
  if unit ~= "player" then return end

  local current = UnitMana("player") or 0
  local max = UnitManaMax("player") or 0

  if tracking and max > 0 and current >= max then
    dprint("Mana full -> stop.")
    StopFSR(self)
  end

  if tracking and not firstTickSeen and (GetTime() - lastCastTime) > FSR_DURATION then
    if current > lastMana then
      firstTickSeen = true
      tickStart = GetTime()
      dprint("First mana tick via UNIT_MANA at", string.format("%.2f", tickStart - lastCastTime), "s")
    end
  end

  lastMana = current
end)

-- helper: center horizontally keeping current Y offset
local function CenterBarHorizontally()
  local _, _, _, _, yOfs = bar:GetPoint(1)
  if type(yOfs) ~= "number" then
    local _, centerY = bar:GetCenter()
    local screenH = UIParent:GetHeight() or 0
    yOfs = (centerY or (screenH/2)) - (screenH/2)
  end
  yOfs = math.floor((yOfs or -150) + 0.5)
  bar:ClearAllPoints()
  bar:SetPoint("CENTER", UIParent, "CENTER", 0, yOfs)
  bar:SetUserPlaced(true)
end

-- ========= Apply SavedVariables on login =========
local init = CreateFrame("Frame")
init:RegisterEvent("PLAYER_LOGIN")
init:SetScript("OnEvent", function()
  -- ensure SV table exists
  FSRTrackerDB = FSRTrackerDB or {}
  -- read, clamp, and apply saved scale
  local sv = tonumber(FSRTrackerDB.scale)
  if sv then
    if sv < MIN_SCALE then sv = MIN_SCALE end
    if sv > MAX_SCALE then sv = MAX_SCALE end
    barScale = sv
    bar:SetScale(barScale)
  end
end)

-- ========= Slash Commands =========
SLASH_FSR1 = "/fsr"
SlashCmdList["FSR"] = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")

  if msg == "test" then
    StartFSR()
    print("|cff66ccffFSR|r test started.")

  elseif msg == "debug" then
    debugPrint = not debugPrint
    print("|cff66ccffFSR|r debug:", tostring(debugPrint))

  elseif msg == "unlock" or msg == "move" then
    bar.isUnlocked = true
    bar:EnableMouse(true)
    bar:SetScale(barScale) -- make sure preview respects saved scale
    if not bar:IsShown() then
      isPreview = true
      bar:SetMinMaxValues(0, 5)
      bar:SetValue(5)
      bar:SetStatusBarColor(0, 0.5, 1, 0.4) -- translucent blue for preview
      bar:Show()
      UpdateSpark()
    end
    print("|cff66ccffFSR|r bar UNLOCKED. Drag to move. Use /fsr lock when done.")

  elseif msg == "lock" then
    bar.isUnlocked = false
    bar:EnableMouse(false)
    bar:SetUserPlaced(true)
    if isPreview and not tracking then
      bar:Hide()
    end
    isPreview = false
    print("|cff66ccffFSR|r bar LOCKED. Use /fsr unlock to move it again.")

  elseif msg == "reset" then
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    barScale = 1.0
    if barScale < MIN_SCALE then barScale = MIN_SCALE end
    if barScale > MAX_SCALE then barScale = MAX_SCALE end
    bar:SetScale(barScale)
    FSRTrackerDB.scale = barScale
    print(string.format("|cff66ccffFSR|r bar position reset and scale set to %.2f.", barScale))

  elseif msg == "center" then
    CenterBarHorizontally()
    print("|cff66ccffFSR|r bar centered horizontally (x = 0).")

  elseif msg and msg:match("^scale") then
    local val = tonumber(msg:match("^scale%s+([%d%.]+)"))
    if not val then
      print(string.format("|cff66ccffFSR|r usage: /fsr scale <%.1f–%.1f>", MIN_SCALE, MAX_SCALE))
      print(string.format("|cff66ccffFSR|r current scale: %.2f", barScale))
      return
    end
    if val < MIN_SCALE then val = MIN_SCALE end
    if val > MAX_SCALE then val = MAX_SCALE end
    barScale = val
    bar:SetScale(barScale)
    FSRTrackerDB.scale = barScale   -- persist per character
    print(string.format("|cff66ccffFSR|r bar scale set to %.2f (range %.1f–%.1f)", barScale, MIN_SCALE, MAX_SCALE))

  else
    print("|cff66ccffFSR|r commands: test, debug, unlock, lock, reset, center, scale <value>")
  end
end
