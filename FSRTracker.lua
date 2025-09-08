-- FSRTracker - Five-Second Rule tracker for Project Epoch (Wrath 3.3.5a)
-- Blue 5s sweep (FSR) -> wait for first real mana tick via UNIT_MANA -> 2s green pulses -> stop when full

----------------------------------
-- Constants & saved variables
----------------------------------
local ADDON_NAME = ... or "FSRTracker"

local FSR_DURATION   = 5
local TICK_INTERVAL  = 2
local MIN_SCALE      = 0.5
local MAX_SCALE      = 3.0

-- Base unscaled size of the bar (used for non-uniform stretch)
local BASE_W, BASE_H = 300, 16
local BASE_SPARK_W, BASE_SPARK_H = 16, 32

local debugPrint     = false
local barScale       = 1.0     -- uniform scale (SetScale)
local scaleX         = 1.0     -- width multiplier (SetSize)
local scaleY         = 1.0     -- height multiplier (SetSize)
local hideBG         = false   -- hide background & fill, spark only
local savedStrata    = "MEDIUM"
local savedLevel     = nil
local showCD         = false   -- COUNTDOWN TEXT TOGGLED OFF BY DEFAULT

-- Per-character SavedVariables
FSRTrackerDB = FSRTrackerDB or {}
if tonumber(FSRTrackerDB.scale)  then barScale = tonumber(FSRTrackerDB.scale)  end
if tonumber(FSRTrackerDB.scalex) then scaleX   = tonumber(FSRTrackerDB.scalex) end
if tonumber(FSRTrackerDB.scaley) then scaleY   = tonumber(FSRTrackerDB.scaley) end
if type(FSRTrackerDB.hideBG) == "boolean" then hideBG = FSRTrackerDB.hideBG end
if type(FSRTrackerDB.strata) == "string"  then savedStrata = FSRTrackerDB.strata end
if tonumber(FSRTrackerDB.level) then savedLevel = tonumber(FSRTrackerDB.level) end
if type(FSRTrackerDB.cd) == "boolean" then showCD = FSRTrackerDB.cd end

----------------------------------
-- Safe debug print
----------------------------------
local function sjoin(...)
  local out = {}
  for i = 1, select("#", ...) do out[i] = tostring(select(i, ...)) end
  return table.concat(out, " ")
end
local function dprint(...) if debugPrint then DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffFSR|r "..sjoin(...)) end end

----------------------------------
-- Helpers: always read real MANA (powerType 0)
----------------------------------
local hasUnitPower = type(UnitPower) == "function" and type(UnitPowerMax) == "function"
local function GetPlayerMana()
  if hasUnitPower then
    return (UnitPower("player", 0) or 0), (UnitPowerMax("player", 0) or 0)
  else
    return (UnitMana("player") or 0), (UnitManaMax("player") or 0)
  end
end

-- === Buff helpers (3.3.5-safe, locale-safe) ===
local function PlayerHasBuff(name)
  for i = 1, 40 do
    local n = UnitBuff("player", i)
    if not n then break end
    if n == name then return true end
  end
  return false
end

-- Localized buff names (fallback to English if spellId not found)
local BUFF_EVOCATION  = (GetSpellInfo(12051)) or "Evocation"
local BUFF_INNERVATE  = (GetSpellInfo(29166)) or "Innervate"
local BUFF_DIVINEPLEA = (GetSpellInfo(54428)) or "Divine Plea"

local function IsEvocating()  return PlayerHasBuff(BUFF_EVOCATION) end
local function IsInnervated()  return PlayerHasBuff(BUFF_INNERVATE) end

-- "Drinking" shows as a few names on 3.3.5; cover the common ones.
local function IsDrinking()
  for i = 1, 40 do
    local n = UnitBuff("player", i)
    if not n then break end
    if n == "Drink" or n == "Drinking" or n == "Food and Drink" then
      return true
    end
  end
  return false
end

----------------------------------------------------------------
-- 2-sec tick detector (3.3.5-safe)
----------------------------------------------------------------
local FSR = {
  gaining       = true,   -- allowed to gain (5s rule finished)
  resumeAt      = 0,      -- when 5s rule ends (GetTime())
  lastTickAt    = 0,      -- last ACCEPTED tick time
  baseline      = 0,      -- expected tick size (2s), adaptive
  failCount     = 0,
}

local function FSR_SeedBaseline()
  if type(GetManaRegen) == "function" then
    local notCastingPerSec = select(1, GetManaRegen())
    if notCastingPerSec and notCastingPerSec > 0 then
      FSR.baseline = notCastingPerSec * 2
    end
  end
  if FSR.baseline == 0 then FSR.baseline = 20 end -- harmless fallback
end
FSR_SeedBaseline()

local function FSR_EnterFiveSecondRule()
  FSR.gaining  = false
  FSR.resumeAt = GetTime() + 5
end

local function FSR_FiveSecondGate(now)
  if not FSR.gaining and now >= FSR.resumeAt then
    FSR.gaining, FSR.resumeAt = true, 0
  end
  return FSR.gaining
end

-- ----- special regen classifier (Wrath 3.3.5-safe, locale-safe) -----
local BUFF_MANATIDE      = (GetSpellInfo(16191)) or "Mana Tide"
local BUFF_REPLENISHMENT = (GetSpellInfo(57669)) or "Replenishment"

local function FSR_SpecialRegenState()
  local s = { evocation=false, innervate=false, divinePlea=false, manaTide=false, replen=false, drink=false }
  for i = 1, 40 do
    local name = UnitBuff("player", i)
    if not name then break end
    if name == BUFF_EVOCATION then s.evocation = true
    elseif name == BUFF_INNERVATE then s.innervate = true
    elseif name == BUFF_DIVINEPLEA then s.divinePlea = true
    elseif name == BUFF_MANATIDE or name == "Mana Tide Totem" then s.manaTide = true
    elseif name == BUFF_REPLENISHMENT then s.replen = true
    elseif name == "Drink" or name == "Drinking" or name == "Food and Drink" then s.drink = true
    end
  end
  return s
end

local function FSR_SizeWindow()
  local base = math.max(4, FSR.baseline)
  local low, high = base * 0.65, base * 1.35   -- spirit-only tolerance
  if FSR.gaining then
    high = base * 2.2                          -- allow Spirit + mp5 after 5SR
  end
  return low, high
end

-- Returns (isRealTick, effectiveTickSize, shouldAdaptBaseline, reason, infoTbl)
local function FSR_IsRealTick(delta, now)
  local s        = FSR_SpecialRegenState()
  local inCombat = UnitAffectingCombat("player")

  -- Only Evocation can bypass the 5s gate
  local gateOpen = FSR_FiveSecondGate(now) or s.evocation
  if not gateOpen then
    return false, nil, nil, "gate-closed", {evoc=s.evocation}
  end

  -- Cadence check (accept merged 4s on lag)
  local dt    = (FSR.lastTickAt > 0) and (now - FSR.lastTickAt) or 2.0
  local near2 = (dt > 1.4 and dt < 2.6)
  local near4 = (dt >= 3.4 and dt < 4.6)
  if not (near2 or near4) then
    return false, nil, nil, "bad-cadence", {dt=dt}
  end

  -- During Evo/Innervate/Drink(OOC) we care about cadence only; skip size window
  local skipSize = s.evocation or s.innervate or (s.drink and not inCombat)

  local effective = near4 and (delta * 0.5) or delta
  if not skipSize then
    local low, high = FSR_SizeWindow()

    -- Forgive the first acceptance after gate
    if FSR.lastTickAt == 0 then
      low  = low  * 0.6
      high = high * 1.8
    end
    -- If we already rejected a few, widen more
    if (FSR.failCount or 0) >= 3 then
      low  = low  * 0.5
      high = high * 2.5
    end

    if effective < low or effective > high then
      return false, effective, false, "out-of-window", {
        eff=effective, low=low, high=high, base=FSR.baseline
      }
    end
  end

  -- Never adapt while big boosters are up (ignore Drink both in/out of combat)
  local adapt = not (s.evocation or s.innervate or s.drink)

  return true, effective, adapt, "ok", {
    dt=dt, skipSize=skipSize, evoc=s.evocation, inn=s.innervate, drink=s.drink
  }
end

local function FSR_OnManaGain(delta)
  local now = GetTime()
  local ok, effSz, adapt, reason, info = FSR_IsRealTick(delta, now)

  if not ok then
    FSR.failCount = (FSR.failCount or 0) + 1
    if debugPrint then
      local parts = {
        "Rejected first tick:",
        "reason="..tostring(reason),
        "Δ="..tostring(delta),
      }
      if info then
        if info.dt then table.insert(parts, string.format("dt=%.3f", info.dt)) end
        if info.eff then table.insert(parts, "eff="..tostring(info.eff)) end
        if info.low and info.high then
          table.insert(parts, string.format("win=[%.1f..%.1f]", info.low, info.high))
        end
        if info.base then table.insert(parts, "base="..tostring(math.floor(info.base+0.5))) end
        if info.skipSize ~= nil then table.insert(parts, "skipSize="..tostring(info.skipSize)) end
        if info.evoc then table.insert(parts, "Evo") end
        if info.inn then table.insert(parts, "Inn") end
        if info.drink then table.insert(parts, "Drink") end
      end
      dprint(table.concat(parts, " "))
    end
    return false
  end

  -- Accepted
  FSR.failCount = 0
  if adapt then
    local a = 0.30
    FSR.baseline = (FSR.baseline == 0) and effSz
                 or (FSR.baseline * (1 - a) + effSz * a)
  end
  FSR.lastTickAt = now

  if debugPrint then
    dprint(string.format(
      "Accepted first tick: eff=%d adapt=%s base→%d",
      effSz, tostring(adapt),
      math.floor((FSR.baseline or 0) + 0.5)
    ))
  end

  return true
end

----------------------------------
-- Trigger spell set (lowercased)
----------------------------------
local TRIGGERS = (function()
  local t = {}
  local function add(name) t[string.lower(name)] = true end

  -- Druid
  add("Barkskin"); add("Cyclone"); add("Entangling Roots"); add("Faerie Fire"); add("Force of Nature"); add("Hibernate")
  add("Hurricane"); add("Innervate"); add("Insect Swarm"); add("Moonfire"); add("Moonkin Form"); add("Soothe Animal")
  add("Starfire"); add("Teleport: Moonglade"); add("Thorns"); add("Wrath"); add("Aquatic Form"); add("Cat Form")
  add("Bear Form"); add("Dire Bear Form"); add("Travel Form"); add("Abolish Poison"); add("Gift of the Wild")
  add("Healing Touch"); add("Lifebloom"); add("Mark of the Wild"); add("Overgrowth"); add("Rebirth"); add("Regrowth")
  add("Rejuvenation"); add("Remove Curse"); add("Revive"); add("Swiftmend"); add("Tranquility"); add("Tree of Life")

  -- Hunter
  add("Aspect of the Beast"); add("Aspect of the Cheetah"); add("Aspect of the Hawk"); add("Aspect of the Monkey")
  add("Aspect of the Pack"); add("Aspect of the Viper"); add("Aspect of the Wild"); add("Beast Lore"); add("Bestial Wrath")
  add("Eagle Eye"); add("Eyes of the Beast"); add("Intimidation"); add("Kill Command"); add("Mend Pet"); add("Revive Pet")
  add("Scare Beast"); add("Tame Beast"); add("Aimed Shot"); add("Arcane Shot"); add("Concussive Shot"); add("Distracting Shot")
  add("Flare"); add("Hunter's Mark"); add("Multi-Shot"); add("Scatter Shot"); add("Scorpid Sting"); add("Rapid Fire")
  add("Serpent Sting"); add("Silencing Shot"); add("Steady Shot"); add("Tranquilizing Shot"); add("Viper Sting"); add("Volley")
  add("Counterattack"); add("Disengage"); add("Explosive Trap"); add("Feign Death"); add("Freezing Trap"); add("Frost Trap")
  add("Immolation Trap"); add("Misdirection"); add("Mongoose Bite"); add("Raptor Strike"); add("Snake Trap"); add("Wing Clip")
  add("Wyvern Sting")

  -- Mage
  add("Frostbolt"); add("Fireball"); add("Arcane Explosion"); add("Arcane Missiles"); add("Fire Blast"); add("Frost Nova")
  add("Amplify Magic"); add("Arcane Barrage"); add("Arcane Blast"); add("Arcane Brilliance"); add("Arcane Intellect"); add("Blink")
  add("Conjure Food"); add("Conjure Mana Agate"); add("Conjure Mana Citrine"); add("Conjure Mana Jade"); add("Conjure Mana Ruby")
  add("Conjure Water"); add("Conjure Weapon"); add("Counterspell"); add("Dampen Magic"); add("Invisibility"); add("Mage Armor")
  add("Mana Shield"); add("Polymorph"); add("Portal: Darnassus"); add("Portal: Ironforge"); add("Portal: Orgrimmar")
  add("Portal: Stonard"); add("Portal: Stormwind"); add("Portal: Theramore"); add("Portal: Thunder Bluff"); add("Portal: Undercity")
  add("Remove Lesser Curse"); add("Ritual of Refreshment"); add("Rune of Power"); add("Slow"); add("Slow Fall"); add("Spellsteal")
  add("Teleport: Darnassus"); add("Teleport: Ironforge"); add("Teleport: Orgrimmar"); add("Teleport: Stonard")
  add("Teleport: Stormwind"); add("Teleport: Theramore"); add("Teleport: Thunder Bluff"); add("Teleport: Undercity")
  add("Blast Wave"); add("Dragon's Breath"); add("Fire Blast"); add("Fire Ward"); add("Fireball"); add("Flamestrike")
  add("Molten Armor"); add("Pyroblast"); add("Scorch"); add("Blizzard"); add("Cone of Cold"); add("Frost Armor"); add("Frost Ward")
  add("Ice Armor"); add("Ice Barrier"); add("Ice Block"); add("Ice Lance"); add("Icy Veins"); add("Summon Water Elemental")

  -- Paladin
  add("Blessing of Light"); add("Blessing of Wisdom"); add("Cleanse"); add("Consecration"); add("Divine Favor"); add("Exorcism")
  add("Flash of Light"); add("Greater Blessing of Light"); add("Greater Blessing of Wisdom"); add("Holy Light"); add("Holy Shock")
  add("Holy Wrath"); add("Purify"); add("Redemption"); add("Seal of Light"); add("Seal of Righteousness"); add("Seal of Wisdom")
  add("Turn Evil"); add("Turn Undead"); add("Avenger's Shield"); add("Blessing of Kings"); add("Blessing of Salvation")
  add("Blessing of Sanctuary"); add("Divine Protection"); add("Divine Shield"); add("Greater Blessing of Kings")
  add("Greater Blessing of Salvation"); add("Greater Blessing of Sanctuary"); add("Hammer of Justice"); add("Hand of Freedom")
  add("Hand of Protection"); add("Hand of Sacrifice"); add("Holy Shield"); add("Righteous Defense"); add("Righteous Fury")
  add("Seal of Justice"); add("Avenging Wrath"); add("Blessing of Might"); add("Crusader Strike"); add("Greater Blessing of Might")
  add("Hammer of Wrath"); add("Judgement"); add("Repentance"); add("Seal of Command"); add("Seal of Dedication")
  add("Seal of the Crusader"); add("Seal of Penitence"); add("Seal of the Mountain"); add("Seal of Vengeance")

  -- Priest
  add("Dispel Magic"); add("Divine Spirit"); add("Fear Ward"); add("Inner Fire"); add("Levitate"); add("Mana Burn")
  add("Mass Dispel"); add("Pain Suppression"); add("Power Infusion"); add("Power Word: Barrier"); add("Power Word: Fortitude")
  add("Power Word: Shield"); add("Prayer of Fortitude"); add("Prayer of Spirit"); add("Shackle Undead"); add("Abolish Disease")
  add("Binding Heal"); add("Bless Water"); add("Circle of Healing"); add("Cure Disease"); add("Flash Heal"); add("Greater Heal")
  add("Heal"); add("Holy Fire"); add("Holy Nova"); add("Lesser Heal"); add("Lightwell"); add("Prayer of Healing")
  add("Prayer of Mending"); add("Renew"); add("Resurrection"); add("Smite"); add("Fade"); add("Mind Blast"); add("Mind Control")
  add("Mind Flay"); add("Mind Soothe"); add("Mind Vision"); add("Prayer of Shadow Protection"); add("Psychic Scream")
  add("Shadow Protection"); add("Shadow Word: Death"); add("Shadow Word: Pain"); add("Shadowfiend"); add("Shadowform")
  add("Silence"); add("Vampiric Embrace"); add("Vampiric Touch"); add("An'she's Protection"); add("Bedside Manner"); add("Chastise")
  add("Devouring Plague"); add("Elune's Grace"); add("Feedback"); add("Hex of Weakness"); add("Shadowguard"); add("Touch of Weakness")

  -- Shaman
  add("Chain Lightning"); add("Earth Shock"); add("Earthbind Totem"); add("Fire Elemental Totem"); add("Fire Nova Totem")
  add("Flame Shock"); add("Frost Shock"); add("Lightning Bolt"); add("Magma Totem"); add("Molten Blast"); add("Purge")
  add("Searing Totem"); add("Soothe Elemental"); add("Stoneclaw Totem"); add("Totem of Wrath"); add("Astral Recall"); add("Bloodlust")
  add("Earth Elemental Totem"); add("Far Sight"); add("Fire Resistance Totem"); add("Flametongue Totem"); add("Flametongue Weapon")
  add("Frost Resistance Totem"); add("Frostbrand Weapon"); add("Ghost Wolf"); add("Grace of Air Totem"); add("Grounding Totem")
  add("Heroism"); add("Lightning Shield"); add("Nature Resistance Totem"); add("Rockbiter Weapon"); add("Sentry Totem")
  add("Stoneskin Totem"); add("Stormstrike"); add("Strength of Earth Totem"); add("Water Breathing"); add("Water Walking")
  add("Windfury Weapon"); add("Windwall Totem"); add("Windfury Totem"); add("Wrath of Air Totem"); add("Ancestral Spirit")
  add("Chain Heal"); add("Cure Disease"); add("Cure Poison"); add("Disease Cleansing Totem"); add("Earth Shield")
  add("Healing Stream Totem"); add("Healing Wave"); add("Lesser Healing Wave"); add("Mana Spring Totem"); add("Mana Tide Totem")
  add("Poison Cleansing Totem"); add("Tranquil Air Totem"); add("Tremor Totem"); add("Reincarnation")

  -- Warlock
  add("Bane of Agony"); add("Bane of Doom"); add("Bane of Exhaustion"); add("Bane of Tongues"); add("Corruption")
  add("Curse of Recklessness"); add("Curse of the Elements"); add("Curse of Weakness"); add("Death Coil"); add("Drain Life")
  add("Drain Mana"); add("Drain Soul"); add("Fear"); add("Howl of Terror"); add("Seed of Corruption"); add("Siphon Life")
  add("Unstable Affliction"); add("Banish"); add("Create Firestone"); add("Create Healthstone"); add("Create Soulstone")
  add("Create Spellstone"); add("Demon Armor"); add("Demon Skin"); add("Demonic Empowerment"); add("Detect Invisibility")
  add("Enslave Demon"); add("Eye of Kilrogg"); add("Fel Armor"); add("Inferno"); add("Ritual of Doom"); add("Ritual of Souls")
  add("Ritual of Summoning"); add("Shadow Ward"); add("Soul Link"); add("Soul Pact"); add("Summon Felguard"); add("Unending Breath")
  add("Summon Imp"); add("Summon Voidwalker"); add("Summon Succubus"); add("Summon Felhunter"); add("Summon Infernal")
  add("Summon Doomguard"); add("Conflagrate"); add("Hellfire"); add("Immolate"); add("Incinerate"); add("Rain of Fire")
  add("Searing Pain"); add("Shadow Bolt"); add("Shadowburn"); add("Shadowfury"); add("Soul Fire")

  return t
end)()

-- Explicit ignores
local IGNORE = (function()
  local t = {}
  t[string.lower("Faerie Fire (Feral)")] = true
  return t
end)()

----------------------------------
-- UI: bar & visuals
----------------------------------
local bar = CreateFrame("StatusBar", "FSR_Bar", UIParent)
bar:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
bar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
bar:GetStatusBarTexture():SetHorizTile(false)
bar:SetMinMaxValues(0, FSR_DURATION)
bar:SetValue(0)
bar:SetFrameStrata(savedStrata or "MEDIUM")
if savedLevel then bar:SetFrameLevel(savedLevel) end
bar:Hide()

-- background (classic-safe)
local bg = bar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints()
if bg.SetColorTexture then bg:SetColorTexture(0, 0, 0, 0.5) else bg:SetTexture(0, 0, 0, 0.5) end

-- spark
local spark = bar:CreateTexture(nil, "OVERLAY")
spark:SetTexture("Interface\\CastingBar\\UI-CastingBar-Spark")
spark:SetBlendMode("ADD")

-- countdown text (hidden by default)
local cdText = bar:CreateFontString(nil, "OVERLAY")
cdText:ClearAllPoints()
cdText:SetPoint("CENTER", bar, "CENTER", 0, 0)  -- << inside the bar
cdText:SetDrawLayer("OVERLAY", 1)               -- above the spark
cdText:SetJustifyH("CENTER"); cdText:SetJustifyV("MIDDLE")
cdText:SetTextColor(1, 1, 1, 0.95)
cdText:SetShadowColor(0, 0, 0, 0.9)
cdText:SetShadowOffset(1, -1)
cdText:Hide()

-- own font so we can resize with height without double-scaling on SetScale()
local cdFont = CreateFont("FSR_CD_Font")

-- track current fill color and apply hideBG safely
local curR, curG, curB, curA = 0, 0.5, 1, 1
local function ApplyHideBG()
  bg:SetAlpha(hideBG and 0 or 0.5)
  bar:SetStatusBarColor(curR, curG, curB, hideBG and 0 or curA)
end
local function SetBarColor(r,g,b,a)
  curR, curG, curB, curA = r, g, b, a or 1
  bar:SetStatusBarColor(r, g, b, hideBG and 0 or curA)
end
SetBarColor(0, 0.5, 1, 1)

-- Dimension updates (uniform + non-uniform)
local function RefreshDimensions()
  -- uniform scale first
  bar:SetScale(barScale)
  -- then non-uniform stretch via SetSize
  local w = BASE_W * scaleX
  local h = BASE_H * scaleY
  bar:SetSize(w, h)

  -- spark size: keep slim, scale height with bar
  local sparkH = math.max(h * 2, 8)
  spark:SetSize(BASE_SPARK_W, sparkH)
  spark:ClearAllPoints()
  spark:SetPoint("CENTER", bar, "LEFT", 0, 0)

  -- countdown font: scale with the bar height (no double-scaling via SetScale())
  local px = math.max(12, math.floor(h * 0.9))
  cdFont:SetFont(STANDARD_TEXT_FONT, px, "OUTLINE")
  cdText:SetFontObject(cdFont)
end


-- drag support
bar:SetMovable(true)
bar:EnableMouse(false)
bar:RegisterForDrag("LeftButton")
bar:SetScript("OnDragStart", function(self) if self.isUnlocked then self:StartMoving() end end)
bar:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)

-- initialize size once
RefreshDimensions()

----------------------------------
-- State / logic
----------------------------------
local f = CreateFrame("Frame")
local lastCastTime, tracking = 0, false
local firstTickSeen, tickStart = false, 0
local lastMana = (GetPlayerMana())

local function UpdateSpark()
  local _, maxv = bar:GetMinMaxValues()
  local width   = bar:GetWidth()
  local percent = (maxv > 0) and (bar:GetValue() / maxv) or 0
  spark:SetPoint("CENTER", bar, "LEFT", width * percent, 0)
end

local function UpdateCountdown(now)
  if not showCD then return end
  if not bar:IsShown() then cdText:Hide(); return end

  local dt = now - lastCastTime
  local remaining

  if tracking and dt <= FSR_DURATION then
    remaining = math.max(0, FSR_DURATION - dt)
  elseif tracking and firstTickSeen then
    local since = now - tickStart
    remaining = TICK_INTERVAL - (since % TICK_INTERVAL)
  else
    remaining = nil
  end

  if remaining then
    cdText:SetText(string.format("%.1f", remaining))
    cdText:Show()
  else
    cdText:Hide()
  end
end

local function StopFSR()
  tracking      = false
  firstTickSeen = false
  bar:Hide()
  cdText:Hide()
  FSR.lastTickAt = 0
  f:SetScript("OnUpdate", nil)
end

local function StartFSR()
  lastCastTime  = GetTime()
  tracking      = true
  firstTickSeen = false
  tickStart     = 0
  lastMana      = (GetPlayerMana())

  -- RESET the last accepted tick so the next run can accept the first post-5s gain
  FSR.lastTickAt = 0
  FSR.failCount = 0


  -- begin the 5-second rule gate (we only call StartFSR on SUCCEEDED casts)
  FSR_EnterFiveSecondRule()

  bar:SetMinMaxValues(0, FSR_DURATION)
  bar:SetValue(0)
  SetBarColor(0, 0.5, 1, 1) -- blue
  bar:Show()
  if showCD then cdText:Show() end

  f:SetScript("OnUpdate", function(self, elapsed)
    if not tracking then return end
    local now = GetTime()
    local dt  = now - lastCastTime

    if dt <= FSR_DURATION then
      bar:SetMinMaxValues(0, FSR_DURATION)
      bar:SetValue(dt)
      SetBarColor(0, 0.5, 1, 1)
    else
      if firstTickSeen then
        local since = now - tickStart
        bar:SetMinMaxValues(0, TICK_INTERVAL)
        bar:SetValue(since % TICK_INTERVAL)
        SetBarColor(0, 1, 0, 0.6)
      else
        bar:SetMinMaxValues(0, TICK_INTERVAL)
        bar:SetValue(0)
        SetBarColor(0, 1, 0, 0.6)
      end
    end

    UpdateSpark()
    UpdateCountdown(now)
  end)
end

----------------------------------
-- Events: spell (with debug prints) + mana
----------------------------------
local function MaybeTriggerFSR(spellName)
  if not spellName or spellName == "" then return end
  local key = string.lower(spellName)
  if IGNORE[key] then dprint("Ignored:", spellName) return end
  if TRIGGERS[key] then
    dprint("Trigger:", spellName)
    StartFSR()
  else
    dprint("Not in list:", spellName)
  end
end

-- Debug every spell event when /fsr debug is on
local function DebugSpellEvent(event, unit, a2, a3, a4, a5)
  if not debugPrint or unit ~= "player" then return end
  local name
  if event == "UNIT_SPELLCAST_SENT" then
    name = a2
  elseif event == "UNIT_SPELLCAST_START" then
    name = UnitCastingInfo(unit)
  elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
    name = UnitChannelInfo(unit)
  else
    name = a2 or UnitCastingInfo(unit) or UnitChannelInfo(unit)
  end
  name = name or "?"
  local tag = ""
  local key = string.lower(name)
  if IGNORE[key] then
    tag = " [IGNORED]"
  elseif TRIGGERS[key] then
    tag = " [TRIGGER]"
  end
  DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff66ccffFSR|r %s: %s%s", event, name, tag))
end

-- start blue sweep ASAP; also register extra events for better debug visibility
f:RegisterEvent("UNIT_SPELLCAST_SENT")
f:RegisterEvent("UNIT_SPELLCAST_START")
f:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
f:RegisterEvent("UNIT_SPELLCAST_STOP")
f:RegisterEvent("UNIT_SPELLCAST_FAILED")
f:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
f:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")

f:SetScript("OnEvent", function(_, event, unit, arg2, arg3, arg4, arg5)
  if unit ~= "player" then return end
  DebugSpellEvent(event, unit, arg2, arg3, arg4, arg5)

  -- Start the 5s sweep ONLY when a spell actually succeeds.
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    MaybeTriggerFSR(arg2)  -- arg2 = spell name
  end

  -- If you find a server/core where channeled spells don't fire SUCCEEDED,
  -- you can optionally treat channel end as "success" too:
  -- if event == "UNIT_SPELLCAST_CHANNEL_STOP" then
  --   MaybeTriggerFSR(arg2)
  -- end
end)

-- mana tick & full detection (read true mana, not current power)
local manaFrame = CreateFrame("Frame")
manaFrame:RegisterEvent("UNIT_MANA")
manaFrame:RegisterEvent("UNIT_MAXMANA")
manaFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
manaFrame:RegisterEvent("PLAYER_LEVEL_UP")
manaFrame:SetScript("OnEvent", function(self, event, unit)
  if event == "PLAYER_ENTERING_WORLD" then
    lastMana = (GetPlayerMana())
    FSR_SeedBaseline()
    return
  end

  if event == "PLAYER_LEVEL_UP" then
    local newLevel = tonumber(unit) or UnitLevel("player")
    -- Clear adaptive state so the next accepted tick re-syncs cleanly
    FSR.baseline   = 0
    FSR.failCount  = 0
    FSR.lastTickAt = 0
    FSR_SeedBaseline()
    dprint(string.format("Level up to %d -> baseline reseeded to ~%d.", newLevel or -1, math.floor((FSR.baseline or 0) + 0.5)))
    return
  end

  if unit ~= "player" then return end

  local current, max = GetPlayerMana()
  local now   = GetTime()
  local delta = current - lastMana

  -- Stop when full.
  if tracking and max > 0 and current >= max then
    dprint("Mana full -> stop.")
    StopFSR()
    lastMana = current
    return
  end

  -- Only consider +mana while waiting for the first tick.
  if tracking and not firstTickSeen and delta > 0 then
    -- HARD GATE: do not even query the classifier until the 5s gate is open,
    -- except Evocation (we want pulses during the channel).
    local gateOpen = (now - lastCastTime) >= FSR_DURATION or IsEvocating()
    if not gateOpen then
      if debugPrint then
        local left = math.max(0, FSR_DURATION - (now - lastCastTime))
        dprint(string.format("5s gate active (%.2fs left), ignoring +%d mana.", left, delta))
      end
      -- Do NOT touch failCount here.
    else
      if FSR_OnManaGain(delta) then
        firstTickSeen = true
        tickStart     = now
        dprint(string.format("First clean mana tick at + %.2f s (Δ=%d)", now - lastCastTime, delta))
      else
        dprint("Ignored non-2s mana source while waiting for first tick.")
      end
    end
  end

  lastMana = current
end)

-- Pause pulses when Evo/Innervate end in combat; resync on next accepted tick.
local auraWatcher = CreateFrame("Frame")
auraWatcher:RegisterEvent("UNIT_AURA")
local hadEvo, hadInn = false, false

auraWatcher:SetScript("OnEvent", function(_, _, u)
  if u ~= "player" or not tracking then return end
  local s = FSR_SpecialRegenState()
  -- if either aura just fell off, pause pulses and wait for a fresh real tick
  if (hadEvo and not s.evocation) or (hadInn and not s.innervate) then
    if UnitAffectingCombat("player") then
      firstTickSeen = false
      FSR.lastTickAt = 0
      bar:SetMinMaxValues(0, TICK_INTERVAL)
      bar:SetValue(0)
      SetBarColor(0, 1, 0, 0.6)
      dprint("Special regen ended -> pausing pulses to resync on next real tick.")
    end
  end
  hadEvo, hadInn = s.evocation, s.innervate
end)

----------------------------------
-- SavedVars restore + login message
----------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self, event, arg1)
  if event == "ADDON_LOADED" and (arg1 == ADDON_NAME or arg1 == "FSRTracker") then
    FSRTrackerDB = FSRTrackerDB or {}

    if tonumber(FSRTrackerDB.scale)  then barScale = tonumber(FSRTrackerDB.scale)  else barScale = 1.0 end
    if tonumber(FSRTrackerDB.scalex) then scaleX   = tonumber(FSRTrackerDB.scalex) else scaleX   = 1.0 end
    if tonumber(FSRTrackerDB.scaley) then scaleY   = tonumber(FSRTrackerDB.scaley) else scaleY   = 1.0 end
    if type(FSRTrackerDB.hideBG) == "boolean" then hideBG = FSRTrackerDB.hideBG else hideBG = false end
    if type(FSRTrackerDB.strata) == "string" then savedStrata = FSRTrackerDB.strata else savedStrata = "MEDIUM" end
    if tonumber(FSRTrackerDB.level) then savedLevel = tonumber(FSRTrackerDB.level) else savedLevel = nil end
    if type(FSRTrackerDB.cd) == "boolean" then showCD = FSRTrackerDB.cd else showCD = false end

    RefreshDimensions()
    bar:SetFrameStrata(savedStrata or "MEDIUM")
    if savedLevel then bar:SetFrameLevel(savedLevel) end
    ApplyHideBG()
    if not showCD then cdText:Hide() end

  elseif event == "PLAYER_LOGIN" then
    local ver = GetAddOnMetadata(ADDON_NAME or "FSRTracker", "Version") or GetAddOnMetadata("FSRTracker", "Version") or ""
    local verText = (ver ~= "" and (" v" .. ver) or "")
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffFSRTracker|r"..verText.." loaded — by |cffa335eeRetroUnreal|r aka |cffa335eeBhop|r. Type |cff66ccff/fsr|r for commands. Let me know of any issues.")
    self:UnregisterEvent("PLAYER_LOGIN")
    self:UnregisterEvent("ADDON_LOADED")
  end
end)

----------------------------------
-- Slash commands
----------------------------------
local function norm_strata(s)
  if not s or s == "" then return nil end
  s = string.upper(s)
  if s == "BG" or s == "BACKGROUND" then return "BACKGROUND" end
  if s == "LOW" then return "LOW" end
  if s == "MED" or s == "MEDIUM" then return "MEDIUM" end
  if s == "HIGH" then return "HIGH" end
  if s == "DIALOG" then return "DIALOG" end
  if s == "FS" or s == "FULLSCREEN" then return "FULLSCREEN" end
  if s == "FSD" or s == "FULLSCREEN_DIALOG" then return "FULLSCREEN_DIALOG" end
  if s == "TOP" or s == "TOOLTIP" then return "TOOLTIP" end
  return nil
end

local function clamp_level(n)
  n = tonumber(n)
  if not n then return nil end
  if n < 0 then n = 0 end
  if n > 20000 then n = 20000 end  -- plenty high
  return math.floor(n + 0.5)
end

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
    bar:SetMinMaxValues(0, FSR_DURATION)
    bar:SetValue(0)
    SetBarColor(0, 0.5, 1, 0.9)
    bar:Show()
    if showCD then cdText:SetText("5.0"); cdText:Show() end
    print("|cff66ccffFSR|r bar UNLOCKED. Drag to move. Use /fsr lock when done.")

  elseif msg == "lock" then
    bar.isUnlocked = false
    bar:EnableMouse(false)
    if not tracking then bar:Hide(); cdText:Hide() end
    print("|cff66ccffFSR|r bar LOCKED. Use /fsr unlock to move it again.")

  elseif msg == "reset" then
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, -150)
    barScale, scaleX, scaleY = 1.0, 1.0, 1.0
    FSRTrackerDB.scale  = barScale
    FSRTrackerDB.scalex = scaleX
    FSRTrackerDB.scaley = scaleY
    RefreshDimensions()

    -- NEW: ensure background is turned back on
    hideBG = false
    FSRTrackerDB.hideBG = false
    ApplyHideBG()

    print("|cff66ccffFSR|r bar reset to default position and scale 1.0 (scalex=1.0, scaley=1.0).")

  elseif msg == "center" then
    local _, _, _, _, y = bar:GetPoint()
    y = y or -150
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "CENTER", 0, y)
    print("|cff66ccffFSR|r bar centered horizontally (y offset "..tostring(y)..").")

  elseif msg == "front" then
    bar:SetFrameStrata("TOOLTIP")
    bar:SetFrameLevel(100)
    FSRTrackerDB.strata = "TOOLTIP"
    FSRTrackerDB.level  = 100
    print("|cff66ccffFSR|r bar brought to front (strata=TOOLTIP, level=100).")

  elseif msg:match("^strata") then
    local arg = msg:match("^strata%s+(%S+)")
    if not arg then
      print("|cff66ccffFSR|r current strata: "..(bar:GetFrameStrata() or "?"))
      print("|cff66ccffFSR|r usage: /fsr strata BACKGROUND|LOW|MEDIUM|HIGH|DIALOG|FULLSCREEN|FULLSCREEN_DIALOG|TOOLTIP")
    else
      local s = norm_strata(arg)
      if not s then
        print("|cff66ccffFSR|r unknown strata '"..arg.."'.")
      else
        bar:SetFrameStrata(s)
        FSRTrackerDB.strata = s
        print("|cff66ccffFSR|r strata set to "..s..".")
      end
    end

  elseif msg:match("^level") then
    local arg = msg:match("^level%s+(%S+)")
    if not arg then
      print("|cff66ccffFSR|r current level: "..tostring(bar:GetFrameLevel()))
      print("|cff66ccffFSR|r usage: /fsr level <0–20000>")
    else
      local lvl = clamp_level(arg)
      if not lvl then
        print("|cff66ccffFSR|r usage: /fsr level <0–20000>")
      else
        bar:SetFrameLevel(lvl)
        FSRTrackerDB.level = lvl
        print("|cff66ccffFSR|r frame level set to "..lvl..".")
      end
    end

  elseif msg:match("^scale%s") or msg == "scale" then
    local val = tonumber(msg:match("^scale%s+([%d%.]+)"))
    if not val then
      print(string.format("|cff66ccffFSR|r usage: /fsr scale <%.1f–%.1f>", MIN_SCALE, MAX_SCALE))
      print(string.format("|cff66ccffFSR|r current scale: %.2f", barScale))
      return
    end
    if val < MIN_SCALE then val = MIN_SCALE end
    if val > MAX_SCALE then val = MAX_SCALE end
    barScale = val
    FSRTrackerDB.scale = barScale
    RefreshDimensions()
    print(string.format("|cff66ccffFSR|r scale set to %.2f (range %.1f–%.1f).", barScale, MIN_SCALE, MAX_SCALE))

  elseif msg:match("^scalex%s") or msg == "scalex" then
    local val = tonumber(msg:match("^scalex%s+([%d%.]+)"))
    if not val then
      print(string.format("|cff66ccffFSR|r usage: /fsr scalex <%.1f–%.1f> (current %.2f)", MIN_SCALE, MAX_SCALE, scaleX))
      return
    end
    if val < MIN_SCALE then val = MIN_SCALE end
    if val > MAX_SCALE then val = MAX_SCALE end
    scaleX = val
    FSRTrackerDB.scalex = scaleX
    RefreshDimensions()
    print(string.format("|cff66ccffFSR|r scalex set to %.2f (width stretch).", scaleX))

  elseif msg:match("^scaley%s") or msg == "scaley" then
    local val = tonumber(msg:match("^scaley%s+([%d%.]+)"))
    if not val then
      print(string.format("|cff66ccffFSR|r usage: /fsr scaley <%.1f–%.1f> (current %.2f)", MIN_SCALE, MAX_SCALE, scaleY))
      return
    end
    if val < MIN_SCALE then val = MIN_SCALE end
    if val > MAX_SCALE then val = MAX_SCALE end
    scaleY = val
    FSRTrackerDB.scaley = scaleY
    RefreshDimensions()
    print(string.format("|cff66ccffFSR|r scaley set to %.2f (height stretch).", scaleY))

  elseif msg:match("^bg") then
    local arg = msg:match("^bg%s+(%S+)")
    if arg == "on" then hideBG = true
    elseif arg == "off" then hideBG = false
    else hideBG = not hideBG end
    FSRTrackerDB.hideBG = hideBG
    ApplyHideBG()
    print("|cff66ccffFSR|r background "..(hideBG and "hidden (spark only)." or "shown."))

  elseif msg:match("^cd") then
    local arg = msg:match("^cd%s+(%S+)")
    if arg == "on" then showCD = true
    elseif arg == "off" then showCD = false
    else showCD = not showCD end
    FSRTrackerDB.cd = showCD
    if showCD and (bar:IsShown() or bar.isUnlocked) then cdText:Show() else cdText:Hide() end
    print("|cff66ccffFSR|r countdown "..(showCD and "enabled." or "disabled."))

  elseif msg == "seed" then
    local old = FSR.baseline or 0
    -- Clear adaptive state so the next accepted tick re-syncs cleanly
    FSR.failCount  = 0
    FSR.lastTickAt = 0
    -- (Do not touch firstTickSeen: we can seed while running)
    FSR.baseline   = 0
    FSR_SeedBaseline()
    print(string.format("|cff66ccffFSR|r baseline reseeded to ~%d (was %d). Tip: use while not casting/drinking.",
         math.floor((FSR.baseline or 0) + 0.5)))


  else
    print("|cff66ccffFSR|r commands:")
    print("  |cff66ccff/fsr unlock|r — unlock & show preview (drag to move)")
    print("  |cff66ccff/fsr lock|r — lock & hide (when idle)")
    print("  |cff66ccff/fsr center|r — center horizontally")
    print("  |cff66ccff/fsr reset|r — reset position and ALL scales")
    print("  |cff66ccff/fsr front|r — bring the bar above other UI (TOOLTIP/100)")
    print("  |cff66ccff/fsr strata <name>|r — BACKGROUND|LOW|MEDIUM|HIGH|DIALOG|FULLSCREEN|FULLSCREEN_DIALOG|TOOLTIP")
    print("  |cff66ccff/fsr level <0–20000>|r — set frame level within the strata")
    print("  |cff66ccff/fsr scale <"..MIN_SCALE.."–"..MAX_SCALE..">|r — uniform scale")
    print("  |cff66ccff/fsr scalex <"..MIN_SCALE.."–"..MAX_SCALE..">|r — width stretch")
    print("  |cff66ccff/fsr scaley <"..MIN_SCALE.."–"..MAX_SCALE..">|r — height stretch")
    print("  |cff66ccff/fsr bg [on|off]|r — toggle spark-only mode")
    print("  |cff66ccff/fsr cd [on|off]|r — toggle numeric countdown on bar")
    print("  |cff66ccff/fsr test|r — show a test sweep")
    print("  |cff66ccff/fsr debug|r — toggle debug prints (also prints spell events)")
    print("  |cff66ccff/fsr seed|r — reseed baseline from current regen (use while not casting/drinking)")
  end
end
