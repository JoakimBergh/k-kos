-- Database.lua
local ADDON_NAME = ...
local L = KillOnSight_L

KillOnSightDB = KillOnSightDB or {}


-- SavedVariables use the legacy KillOnSightDB key for compatibility.
-- Legacy profile structures are read only during the one-time migration to a single settings table.

local DB = {}

-- Normalize class input to classFile token (e.g. "ROGUE")
local _locToClassFile
local function _NormalizeClassForDB(classIn)
  if not classIn or classIn == "" then return nil end
  if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classIn] then
    return classIn
  end
  if not _locToClassFile then
    _locToClassFile = {}
    if LOCALIZED_CLASS_NAMES_MALE then
      for file, loc in pairs(LOCALIZED_CLASS_NAMES_MALE) do
        _locToClassFile[loc] = file
      end
    end
    if LOCALIZED_CLASS_NAMES_FEMALE then
      for file, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
        _locToClassFile[loc] = file
      end
    end
  end
  return _locToClassFile[classIn]
end





local function Now() return time() end

local function RealmKey()
  -- Account-wide shared DB across all realms/factions/characters.
  return "GLOBAL"
end

local function CharKey()
  local util = _G.KillOnSight_Util
  local name = (util and util:UnitPlayerName("player")) or ((_G.KillOnSight_Util and _G.KillOnSight_Util:UnitPlayerName("player")) or UnitName("player")) or "Unknown"
  if util and util:IsForeverNames() then return name end
  if name:find("-", 1, true) then return name end
  local realm = GetRealmName() or "UnknownRealm"
  return name .. "-" .. realm
end

local DEFAULTS = {
  settings = {
    enableSound = true,
    enableScreenFlash = true,
    throttleSeconds = 12,
    printToChat = true,
    minimap = { hide=false, minimapPos=220 },
    showNearbyFrame = true,
    nearbyFrameLocked = false,
	    spyAlertPosition = { point="TOP", relPoint="TOP", x=0, y=-215 },
	    -- nearbyFrame.bgAlpha controls the backdrop/border opacity. For simplicity (and
	    -- backward compatibility), we also keep nearbyAlpha in sync with bgAlpha so the
	    -- overall window opacity matches the background slider unless fading is enabled.
	    nearbyFrame = { point="CENTER", relPoint="CENTER", x=280, y=80, scale=0.80, bgAlpha=0.60 },
	    -- Legacy key (older versions used this for overall frame alpha). Kept for back-compat.
	    nearbyAlpha = 0.60,
    nearbyAutoHide = false,
    nearbyFade = false,

    -- Spy-style sound when a non-KoS enemy is first added to the nearby list.
    -- (Separate from KoS alerts and separate from stealth-detection sounds.)
    nearbySound = true,
    -- Alert scope only controls the extra Nearby sound. Detection and Nearby
    -- population always continue for every detected enemy player.
    -- "all" = sound for every newly seen enemy; "kos" = only KoS/Guild-KoS alerts.
    nearbyAlertMode = "all",
    -- Ordinary Nearby entries use this distance; high-confidence detections
    -- continue to use the existing 1.5x multiplier.
    nearbyMaxYards = 100,
    -- Nearby window is always ultra-minimal (no toggle)
    nearbyMinimal = true,
    nearbyRowIcons = true,
    -- Font used for player names in the Nearby list (dropdown in Options)
    nearbyNameFont = "Default",
    nearbyNameFontSize = 12,
    -- Max number of rows to show in Nearby before scrolling (Nearby pre-creates 20 rows)
    nearbyMaxVisibleRows = 20,
-- Stealth detection
stealthDetectEnabled = true,
stealthDetectChat = true,
stealthDetectSound = true,
stealthDetectCenterWarning = true,
stealthDetectAddToNearby = true,
    stealthWarningHoldSeconds = 6.0,
    stealthWarningFadeSeconds = 1.2,
    stealthNotifyCooldownSeconds = 8,

    -- Enemy stats pruning policy (enabled by default)
    statsPruneEnabled = true,
    statsPruneMaxDays = 180,
    statsPruneMaxEntries = 25000,
  },
  data = {
    revision = 0,          -- global revision
    statsRevision = 0,     -- enemy stats revision (for UI caching)
    players = {},          -- [lowerName] = entry
    guilds  = {},          -- [lowerGuild] = entry
    changes = {},          -- [seq] = { op="upsert"/"delete", kind="P"/"G", key, entry, rev }
    lastAttackers = {},    -- array of {name, guid, zone, at}

		-- Enemy encounter statistics (unbounded by default)
		-- statsPlayers[lowerName] = {
		--   name, classFile, guild,
		--   firstSeenAt, lastSeenAt,
		--   seenCount,
		--   wins, loses,
		-- }
		statsPlayers = {},
  }
}

-- Optional pruning policy for enemy stats (prevents long-term SavedVariables bloat)
-- Enabled by default to keep SavedVariables lean; can be disabled if you prefer Spy-like "remember everything" behavior.
--
-- User settings are stored once in realmDB.settings:
--   statsPruneEnabled   (bool)
--   statsPruneMaxDays   (number)  -- drop entries not seen in N days
--   statsPruneMaxEntries(number)  -- hard cap by dropping oldest lastSeenAt

local function DeepCopy(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = dst[k] or {}
      DeepCopy(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end


local function _MergeInto(dst, src)
  -- Merge src table into dst table (dst wins on conflicts)
  if type(dst) ~= "table" or type(src) ~= "table" then return end
  for k,v in pairs(src) do
    if dst[k] == nil then
      if type(v) == "table" then
        local t = {}
        _MergeInto(t, v)
        dst[k] = t
      else
        dst[k] = v
      end
    elseif type(dst[k]) == "table" and type(v) == "table" then
      _MergeInto(dst[k], v)
    end
  end
end

local function _MergeData(dstData, srcData)
  if type(dstData) ~= "table" or type(srcData) ~= "table" then return end

  dstData.players = dstData.players or {}
  if type(srcData.players) == "table" then
    for k, entry in pairs(srcData.players) do
      if dstData.players[k] == nil then
        dstData.players[k] = entry
      else
        local a = dstData.players[k]
        local b = entry
        local aSeen = tonumber(a.lastSeenAt or 0) or 0
        local bSeen = tonumber(b.lastSeenAt or 0) or 0
        if bSeen > aSeen then
          dstData.players[k] = b
        end
      end
    end
  end

  dstData.guilds = dstData.guilds or {}
  if type(srcData.guilds) == "table" then
    for k, entry in pairs(srcData.guilds) do
      if dstData.guilds[k] == nil then
        dstData.guilds[k] = entry
      end
    end
  end

  -- Merge statsPlayers if present
  dstData.statsPlayers = dstData.statsPlayers or {}
  if type(srcData.statsPlayers) == "table" then
    for k, entry in pairs(srcData.statsPlayers) do
      if dstData.statsPlayers[k] == nil then
        dstData.statsPlayers[k] = entry
      else
        local a = dstData.statsPlayers[k]
        local b = entry
        local aSeen = tonumber(a.lastSeenAt or 0) or 0
        local bSeen = tonumber(b.lastSeenAt or 0) or 0
        if bSeen > aSeen then
          dstData.statsPlayers[k] = b
        end
      end
    end
  end

  -- Keep highest revisions
  dstData.revision = math.max(tonumber(dstData.revision or 0) or 0, tonumber(srcData.revision or 0) or 0)
  dstData.statsRevision = math.max(tonumber(dstData.statsRevision or 0) or 0, tonumber(srcData.statsRevision or 0) or 0)
end

local function norm(s)
  if not s or s == "" then return nil end
  s = s:gsub("^%s+",""):gsub("%s+$","")
  if s == "" then return nil end
  return s
end

function DB:_BumpStatsRevision()
  local d = self:GetData()
  d.statsRevision = (tonumber(d.statsRevision or 0) or 0) + 1
end

function DB:GetStatsRevision()
  local d = self:GetData()
  return tonumber(d.statsRevision or 0) or 0
end

-- One-time, non-destructive migration for WoW Forever two-part identities.
-- Keep an in-SavedVariables snapshot for recovery; never guess missing surnames.
local NAME_SCHEMA_VERSION = 2
local function _NameIdentity(name)
  if type(name) ~= "string" then return nil end
  local util = _G.KillOnSight_Util
  if util and util.NormalizePlayerName then name = util:NormalizePlayerName(name) end
  if type(name) ~= "string" then return nil end
  name = name:gsub("%s*%-%s*", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
  if name == "" then return nil end
  return name:lower(), name
end
local function _LegacyFullName(oldKey, entry)
  -- Forever originally used the legacy realm field for the SURNAME.
  -- Only append it if the stored name is a single token. Never double-append.
  local full = type(entry.fullName) == "string" and entry.fullName or nil
  local name = type(entry.name) == "string" and entry.name or nil
  local surname = type(entry.realm) == "string" and entry.realm:match("^%s*(.-)%s*$") or nil
  if full and full ~= "" then return full end
  if name and name ~= "" then
    if name:find("[ %-]") then return name end
    if surname and surname ~= "" then return name .. " " .. surname end
  end
  -- Keys with two components are unambiguous even if entry.name is first-only.
  if type(oldKey) == "string" and oldKey:find("[ %-]") then return oldKey end
  return name or oldKey
end
local function _MergeMigratedEntry(dst, src, kind)
  if kind == "statsPlayers" then
    -- Historical duplicate counters can overlap; max avoids inventing events.
    for _, field in ipairs({"seenCount", "wins", "loses"}) do
      dst[field] = math.max(tonumber(dst[field]) or 0, tonumber(src[field]) or 0)
    end
    local first, oldFirst = tonumber(dst.firstSeenAt) or 0, tonumber(src.firstSeenAt) or 0
    if oldFirst > 0 and (first == 0 or oldFirst < first) then dst.firstSeenAt = oldFirst end
    if (tonumber(src.lastSeenAt) or 0) > (tonumber(dst.lastSeenAt) or 0) then dst.lastSeenAt = src.lastSeenAt end
  end
  -- Never discard notes or other distinct metadata when entries collide.
  for k, v in pairs(src) do
    if dst[k] == nil or dst[k] == "" then dst[k] = v end
  end
end
local function _MigrateNameData(realmDB)
  local util = _G.KillOnSight_Util
  if not (util and util.IsForeverNames and util:IsForeverNames()) then return end
  local data = realmDB.data
  if type(data) ~= "table" or (tonumber(data.nameSchemaVersion) or 0) >= NAME_SCHEMA_VERSION then return end
  -- Preserve the original backup from v1 and take a fresh v2 snapshot.
  if not realmDB.nameMigrationBackupV2 then
    local snapshot = {schema=NAME_SCHEMA_VERSION, createdAt=Now()}
    for _, kind in ipairs({"players", "statsPlayers"}) do
      snapshot[kind] = {}
      for key, entry in pairs(data[kind] or {}) do
        if type(entry) == "table" then
          local copy = {}; _MergeInto(copy, entry); snapshot[kind][key] = copy
        end
      end
    end
    realmDB.nameMigrationBackupV2 = snapshot
  end
  local changed = false
  for _, kind in ipairs({"players", "statsPlayers"}) do
    local entries = data[kind]
    if type(entries) == "table" then
      local keys = {}
      for key in pairs(entries) do keys[#keys+1] = key end
      table.sort(keys, function(x,y) return tostring(x) < tostring(y) end)
      for _, oldKey in ipairs(keys) do
        local entry = entries[oldKey]
        if type(entry) == "table" then
          local identity = _LegacyFullName(oldKey, entry)
          local key, full = _NameIdentity(identity)
          -- Never merge an unqualified first name with a full identity.
          if key and full:find(" ", 1, true) then
            if oldKey ~= key then
              local dst = entries[key]
              if dst and dst ~= entry then
                -- Only merge when both records independently resolve to the same full name.
                local otherKey = _NameIdentity(_LegacyFullName(key, dst))
                if otherKey == key then
                  _MergeMigratedEntry(dst, entry, kind)
                  entries[oldKey] = nil
                  entry = dst
                  changed = true
                end
              elseif not dst then
                entries[key] = entry
                entries[oldKey] = nil
                changed = true
              end
            end
            if entries[key] == entry then
              -- Stats uses name/realm as legacy components. Do not overwrite
              -- name with the complete identity while realm is still populated:
              -- older display paths would append the surname a second time.
              if kind == "statsPlayers" then
                local first, surname = full:match("^(%S+)%s+(.+)$")
                entry.name = first or full
                entry.realm = surname or entry.realm
              else
                entry.name = full
              end
              entry.fullName = full
            end
          end
        end
      end
    end
  end
  data.nameSchemaVersion = NAME_SCHEMA_VERSION
  if changed then
    data.revision = (tonumber(data.revision) or 0) + 1
    data.statsRevision = (tonumber(data.statsRevision) or 0) + 1
  end
end

function DB:Init()
  -- Use a single account-wide database shared across all realms/factions/characters.
  KillOnSightDB.global = KillOnSightDB.global or {}
  local realmDB = KillOnSightDB.global

  -- One-time migration: merge any older per-realm data into the account-wide database.
  -- Legacy profile tables are read only during this migration; they are not retained.
  if KillOnSightDB.realms and type(KillOnSightDB.realms) == "table" then
    for _, old in pairs(KillOnSightDB.realms) do
      if type(old) == "table" then
        if type(old.profiles) == "table" then
          realmDB.profiles = realmDB.profiles or {}
          _MergeInto(realmDB.profiles, old.profiles)
        end
        if type(old.profileNameByChar) == "table" then
          realmDB.profileNameByChar = realmDB.profileNameByChar or {}
          _MergeInto(realmDB.profileNameByChar, old.profileNameByChar)
        end
        if type(old.profile) == "table" then
          if type(realmDB.profile) ~= "table" then realmDB.profile = {} end
          _MergeInto(realmDB.profile, old.profile)
        end
        -- Merge main data tables (players/guilds/stats)
        if type(old.data) == "table" then
          realmDB.data = realmDB.data or {}
          _MergeInto(realmDB.data, DEFAULTS.data)
          _MergeData(realmDB.data, old.data)
        end
      end
    end
  end

  -- Migrate the current character's active legacy profile into one account-wide settings table.
  -- The current character assignment takes precedence, then Default, then the old single table.
  local ck = CharKey()
  if type(realmDB.settings) ~= "table" or next(realmDB.settings) == nil then
    local legacySettings
    local assigned = realmDB.profileNameByChar and realmDB.profileNameByChar[ck]
    if assigned and type(realmDB.profiles) == "table" then
      legacySettings = realmDB.profiles[assigned]
    end
    if type(legacySettings) ~= "table" and type(realmDB.profiles) == "table" then
      legacySettings = realmDB.profiles.Default
    end
    if type(legacySettings) ~= "table" then
      legacySettings = realmDB.profile
    end
    realmDB.settings = {}
    if type(legacySettings) == "table" then
      _MergeInto(realmDB.settings, legacySettings)
    end
  end

  -- Ensure defaults exist on the global DB and its single persistent settings table.
  DeepCopy(realmDB, DEFAULTS)

  self.realmKey = "GLOBAL"
  self.realmDB = realmDB
  self.settings = realmDB.settings
  realmDB.data = realmDB.data or {}
  realmDB.data.changes = type(realmDB.data.changes) == "table" and realmDB.data.changes or {}
  DeepCopy(self.settings, DEFAULTS.settings)
  self.settings.nearbyMinimal = true

  -- Remove the obsolete profile containers after successful migration.
  realmDB.profiles = nil
  realmDB.profileNameByChar = nil
  realmDB.profile = nil

  -- Clean legacy/dead keys and normalise settings from prior versions.
  local settings = self.settings
  settings.guildAlertCooldownSeconds = nil
  settings.kosAlertCooldownSeconds = nil
  settings.activityThrottleSeconds = nil
  settings.nearbyRowFade = nil
  if settings.nearbySound == nil then settings.nearbySound = true end
  if settings.nearbyAlertMode ~= "all" and settings.nearbyAlertMode ~= "kos" then
    settings.nearbyAlertMode = "all"
  end
  if type(settings.nearbyMaxYards) ~= "number" then settings.nearbyMaxYards = 100 end
  settings.nearbyMaxYards = math.floor((settings.nearbyMaxYards / 10) + 0.5) * 10
  if settings.nearbyMaxYards < 60 then settings.nearbyMaxYards = 60 end
  if settings.nearbyMaxYards > 200 then settings.nearbyMaxYards = 200 end
  if settings.nearbyNameFont == nil then settings.nearbyNameFont = "Default" end
  if settings.nearbyNameFontSize == nil then settings.nearbyNameFontSize = 12 end
  if settings.nearbyMaxVisibleRows == nil then settings.nearbyMaxVisibleRows = 20 end
  if type(settings.nearbyMaxVisibleRows) ~= "number" then settings.nearbyMaxVisibleRows = 20 end
  settings.nearbyMaxVisibleRows = math.floor(settings.nearbyMaxVisibleRows + 0.5)
  if settings.nearbyMaxVisibleRows < 1 then settings.nearbyMaxVisibleRows = 1 end
  if settings.nearbyMaxVisibleRows > 20 then settings.nearbyMaxVisibleRows = 20 end
  if settings.disableInGoblinTowns == nil then settings.disableInGoblinTowns = false end
  if settings.stealthNotifyCooldownSeconds == nil then settings.stealthNotifyCooldownSeconds = 8 end

  -- Honor is fully retired. Remove its list from the active database, legacy
  -- per-realm copies, and the old name-migration backup snapshot.
  if type(realmDB.data) == "table" then realmDB.data.honorPlayers = nil end
  if type(realmDB.nameMigrationBackupV2) == "table" then
    realmDB.nameMigrationBackupV2.honorPlayers = nil
  end
  if type(KillOnSightDB.realms) == "table" then
    for _, old in pairs(KillOnSightDB.realms) do
      if type(old) == "table" then
        if type(old.data) == "table" then old.data.honorPlayers = nil end
        if type(old.nameMigrationBackupV2) == "table" then
          old.nameMigrationBackupV2.honorPlayers = nil
        end
        -- Remove the obsolete per-realm profile/settings containers as well;
        -- all active options now live in realmDB.settings.
        old.profiles = nil
        old.profileNameByChar = nil
        old.profile = nil
        old.settings = nil
      end
    end
  end

  _MigrateNameData(realmDB)

  -- v0.3.0 synchronization baseline. Existing v0.2.x entries predate a
  -- complete revision journal, so the first sync from this schema must use a
  -- FULL snapshot when a peer is behind. Later official edits are delta-safe.
  local currentOfficialRevision = tonumber(realmDB.data.revision) or 0
  if tonumber(realmDB.data.syncSchemaVersion) ~= 2 then
    realmDB.data.changeFloor = math.max(currentOfficialRevision, 1)
    realmDB.data.syncSchemaVersion = 2
  elseif realmDB.data.changeFloor == nil then
    realmDB.data.changeFloor = math.max(currentOfficialRevision, 1)
  end

  -- Optional stats pruning (prevents long-term SV bloat)
  if self.PruneStatsPlayers then
    self:PruneStatsPlayers()
  end
end

function DB:_EnsureRealmDB()
  -- Defensive init: some modules may query DB before ADDON_LOADED finishes,
  -- or in rare edge-cases where realmDB wasn't set (e.g. savedvars not ready).
  if not self.realmDB then
    if type(self.Init) == "function" then
      -- Never throw here; if Init fails we still return a safe table.
      pcall(function() self:Init() end)
    end
  end

  -- Absolute fallback: keep the addon functional even if saved vars are missing.
  if not self.realmDB then
    KillOnSightDB = KillOnSightDB or {}
    KillOnSightDB.global = KillOnSightDB.global or {}
    self.realmDB = KillOnSightDB.global
    self.realmKey = self.realmKey or "GLOBAL"
  end

  self.realmDB.data = self.realmDB.data or {}
  return self.realmDB
end

function DB:GetSettings()
  -- A single account-wide options table; controls write directly to SavedVariables.
  local realmDB = self:_EnsureRealmDB()
  realmDB.settings = realmDB.settings or {}
  if self.settings ~= realmDB.settings then self.settings = realmDB.settings end
  DeepCopy(self.settings, DEFAULTS.settings)
  return self.settings
end

function DB:GetData()
  local realmDB = self:_EnsureRealmDB()
  return realmDB.data
end

local CloneOfficialEntry

-- Resolve a portable display-only class hint for a Player KoS entry. The hint
-- is sourced from the master's existing player entry or an exact full-name
-- stats record; local stats themselves are never transmitted.
local function ResolvePlayerClassHint(data, playerEntry)
  if type(playerEntry) ~= "table" then return nil end
  local function valid(value)
    local classFile = _NormalizeClassForDB(value) or value
    if type(classFile) == "string" and #classFile <= 32 and classFile:match("^[A-Z_]+$") then
      return classFile
    end
    return nil
  end

  local direct = valid(playerEntry.class)
  if direct then return direct end

  local name = playerEntry.name
  if type(name) ~= "string" or name == "" then return nil end
  local util = _G.KillOnSight_Util
  local key = (util and util.PlayerKey and util:PlayerKey(name)) or name:lower()
  local stats = data and data.statsPlayers
  if type(stats) ~= "table" then return nil end

  local function classFrom(record)
    if type(record) ~= "table" then return nil end
    return valid(record.classFile or record.class)
  end

  local exact = classFrom(stats[key])
  if exact then return exact end

  -- Some legacy records use a first-name key while keeping the full identity
  -- in fullName. Only accept an exact canonical full-name match.
  for _, record in pairs(stats) do
    if type(record) == "table" then
      local fullName = record.fullName
      if type(fullName) ~= "string" or fullName == "" then
        local first = record.name
        local last = record.realm
        if type(first) == "string" and first ~= "" and type(last) == "string" and last ~= "" then
          fullName = first .. " " .. last
        end
      end
      if type(fullName) == "string" and fullName ~= "" then
        local fullKey = (util and util.PlayerKey and util:PlayerKey(fullName)) or fullName:lower()
        if fullKey == key then
          local found = classFrom(record)
          if found then return found end
        end
      end
    end
  end
  return nil
end

-- Public official-list snapshot: intentionally excludes local sightings and
-- player encounter statistics so those remain specific to each member.
function DB:GetOfficialSnapshot()
  local data = self:GetData()
  local snapshot = { revision = tonumber(data.revision) or 0, players = {}, guilds = {} }
  for key, entry in pairs(data.players or {}) do
    local clean = CloneOfficialEntry(entry)
    -- Class is display metadata, not an authoritative KoS field. Include a
    -- best-effort hint in sync so members can render known class icons without
    -- overwriting their own local class observations.
    if clean then
      clean.classHint = ResolvePlayerClassHint(data, entry)
      snapshot.players[key] = clean
    end
  end
  for key, entry in pairs(data.guilds or {}) do
    local clean = CloneOfficialEntry(entry)
    if clean then snapshot.guilds[key] = clean end
  end
  return snapshot
end

-- Returns (changes, currentRevision) or (nil, currentRevision, reason).
-- A nil change set means the receiver must request a FULL snapshot.
function DB:GetOfficialChangesSince(revision)
  local data = self:GetData()
  local current = tonumber(data.revision) or 0
  local since = tonumber(revision)
  if not since or since < 0 or since > current then
    return nil, current, "invalid_revision"
  end
  local floor = tonumber(data.changeFloor) or 0
  if since < floor then
    return nil, current, "snapshot_required"
  end

  local changes = {}
  for rev = since + 1, current do
    local change = data.changes and data.changes[rev]
    if type(change) ~= "table" then
      return nil, current, "history_gap"
    end
    local copy = {}
    for key, value in pairs(change) do
      if type(value) ~= "table" then
        copy[key] = value
      elseif key == "entry" then
        copy.entry = CloneOfficialEntry(value)
      end
    end
    changes[#changes + 1] = copy
  end
  return changes, current
end

-- Persist insertion order to distinguish entries added within the same second.
local function NextListOrder(data)
  local maximum = tonumber(data.listAddOrder) or 0
  for _, list in ipairs({data.players, data.guilds}) do
    for _, entry in pairs(list or {}) do
      if type(entry) == "table" then
        maximum = math.max(maximum, tonumber(entry.addedOrder) or 0)
      end
    end
  end
  data.listAddOrder = maximum + 1
  return data.listAddOrder
end

local function MakePlayerEntry(name, listType, reason, addedBy, existing, class)
  return {
    name = name,
    class = class or (existing and existing.class) or nil,
    type = listType or L.KOS,
    reason = norm(reason),
    addedBy = addedBy or ((_G.KillOnSight_Util and _G.KillOnSight_Util:UnitPlayerName("player")) or UnitName("player")) or "Unknown",
    addedAt = existing and existing.addedAt or Now(),
    addedOrder = existing and existing.addedOrder or nil,
    modifiedAt = Now(),
    lastSeenAt = existing and existing.lastSeenAt or nil,
    lastSeenZone = existing and existing.lastSeenZone or nil,
  }
end

local function MakeGuildEntry(guild, listType, reason, addedBy, existing)
  return {
    guild = guild,
    type = listType or L.GUILD_KOS,
    reason = norm(reason),
    addedBy = addedBy or ((_G.KillOnSight_Util and _G.KillOnSight_Util:UnitPlayerName("player")) or UnitName("player")) or "Unknown",
    addedAt = existing and existing.addedAt or Now(),
    addedOrder = existing and existing.addedOrder or nil,
    modifiedAt = Now(),
    lastSeenAt = existing and existing.lastSeenAt or nil,
    lastSeenZone = existing and existing.lastSeenZone or nil,
  }
end

local function CanonicalPlayerKey(name)
  local util = _G.KillOnSight_Util
  return util and util:PlayerKey(name) or (type(name) == "string" and name:lower() or nil)
end


local function RequireMasterEdit(action)
  local master = _G.KillOnSight_Master
  if master and master.RequireEdit then
    return master:RequireEdit(action)
  end
  if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
    _G.DEFAULT_CHAT_FRAME:AddMessage("|cffff5555KoS-Kanonfode:|r Master permission module unavailable; official list changes are blocked.")
  end
  return false
end

CloneOfficialEntry = function(entry)
  if type(entry) ~= "table" then return nil end
  local copy = {}
  for key, value in pairs(entry) do
    -- Class is locally learned from observations; modifiedAt may change when
    -- that local class cache refreshes. Neither belongs to the official list.
    if type(value) ~= "table" and key ~= "lastSeenAt" and key ~= "lastSeenZone"
      and key ~= "class" and key ~= "modifiedAt" then
      copy[key] = value
    end
  end
  return copy
end

local function PreserveLocalEntryFields(incoming, existing)
  if type(incoming) ~= "table" then return incoming end
  local classHint = incoming.classHint
  incoming.classHint = nil
  if type(existing) == "table" then
    for _, field in ipairs({"lastSeenAt", "lastSeenZone", "modifiedAt"}) do
      if existing[field] ~= nil then incoming[field] = existing[field] end
    end
    -- Prefer a known class from the master; otherwise retain the member's
    -- locally learned class cache.
    if not classHint and existing.class ~= nil then incoming.class = existing.class end
  end
  if classHint and (type(classHint) == "string") and classHint:match("^[A-Z_]+$") then
    incoming.class = classHint
  end
  return incoming
end

local function ValidOfficialKey(key)
  return type(key) == "string" and key ~= "" and #key <= 160
end

local function ValidOfficialEntry(entry, kind)
  if type(entry) ~= "table" then return false end
  local label = kind == "P" and entry.name or entry.guild
  if type(label) ~= "string" or label == "" or #label > 160 then return false end
  if entry.type ~= nil and (type(entry.type) ~= "string" or #entry.type > 80) then return false end
  if entry.reason ~= nil and (type(entry.reason) ~= "string" or #entry.reason > 600) then return false end
  if entry.addedBy ~= nil and (type(entry.addedBy) ~= "string" or #entry.addedBy > 160) then return false end
  if entry.addedAt ~= nil and tonumber(entry.addedAt) == nil then return false end
  if entry.addedOrder ~= nil and tonumber(entry.addedOrder) == nil then return false end
  if entry.classHint ~= nil and (type(entry.classHint) ~= "string" or #entry.classHint > 32 or not entry.classHint:match("^[A-Z_]+$")) then return false end
  return true
end

local function InvalidateOfficialDigest()
  local comm = _G.KillOnSight_Comm
  if comm and comm.InvalidateDigest then
    pcall(function() comm:InvalidateDigest() end)
  end
end

local function RefreshAfterOfficialSync()
  local nearby = _G.KillOnSight_Nearby
  if nearby then
    if nearby.Refresh then pcall(function() nearby:Refresh() end) end
    if nearby.OnListChanged then
      pcall(function() nearby:OnListChanged("P", "") end)
      pcall(function() nearby:OnListChanged("G", "") end)
    end
  end
  local gui = _G.KillOnSight_GUI
  if gui and gui.RefreshAll then pcall(function() gui:RefreshAll() end) end
end

-- Apply an authoritative full snapshot received from the configured master.
-- Local observations and statistics are deliberately preserved per member.
function DB:ApplyOfficialSnapshot(snapshot, sourceIdentity)
  local master = _G.KillOnSight_Master
  if not master or not master.IsMasterIdentity or not master:IsMasterIdentity(sourceIdentity) then
    return false, "unauthorized_source"
  end
  if type(snapshot) ~= "table" or type(snapshot.players) ~= "table" or type(snapshot.guilds) ~= "table" then
    return false, "invalid_snapshot"
  end
  local revision = tonumber(snapshot.revision)
  if not revision or revision < 0 then return false, "invalid_revision" end

  local data = self:GetData()
  local newPlayers, newGuilds = {}, {}
  local playerCount, guildCount = 0, 0
  for key, entry in pairs(snapshot.players) do
    if not ValidOfficialKey(key) or not ValidOfficialEntry(entry, "P") then return false, "invalid_player_entry" end
    playerCount = playerCount + 1
    if playerCount > 10000 then return false, "too_many_players" end
    local copy = CloneOfficialEntry(entry)
    newPlayers[key] = PreserveLocalEntryFields(copy, data.players and data.players[key])
  end
  for key, entry in pairs(snapshot.guilds) do
    if not ValidOfficialKey(key) or not ValidOfficialEntry(entry, "G") then return false, "invalid_guild_entry" end
    guildCount = guildCount + 1
    if guildCount > 10000 then return false, "too_many_guilds" end
    local copy = CloneOfficialEntry(entry)
    newGuilds[key] = PreserveLocalEntryFields(copy, data.guilds and data.guilds[key])
  end

  data.players = newPlayers
  data.guilds = newGuilds
  data.revision = revision
  data.changes = {}
  data.changeFloor = revision
  data.syncSchemaVersion = 2
  data.syncLastMaster = tostring(sourceIdentity)
  data.syncLastRevision = revision
  InvalidateOfficialDigest()
  RefreshAfterOfficialSync()
  return true
end

-- Apply a contiguous official delta. Validate the complete delta before
-- mutating anything, so a bad final record cannot leave a partial update.
function DB:ApplyOfficialChanges(changes, targetRevision, sourceIdentity)
  local master = _G.KillOnSight_Master
  if not master or not master.IsMasterIdentity or not master:IsMasterIdentity(sourceIdentity) then
    return false, "unauthorized_source"
  end
  if type(changes) ~= "table" then return false, "invalid_changes" end
  local data = self:GetData()
  data.players = type(data.players) == "table" and data.players or {}
  data.guilds = type(data.guilds) == "table" and data.guilds or {}
  local current = tonumber(data.revision) or 0
  local target = tonumber(targetRevision)
  if not target or target < current then return false, "revision_regression" end
  if #changes == 0 then
    if target ~= current then return false, "empty_delta_gap" end
    return true
  end

  local validated = {}
  local expected = current + 1
  for _, change in ipairs(changes) do
    if type(change) ~= "table" or tonumber(change.rev) ~= expected then return false, "revision_gap" end
    if change.kind ~= "P" and change.kind ~= "G" then return false, "invalid_change_kind" end
    if not ValidOfficialKey(change.key) then return false, "invalid_change_key" end
    if change.op == "upsert" then
      if not ValidOfficialEntry(change.entry, change.kind) then return false, "invalid_change_entry" end
      if change.classHint ~= nil and (type(change.classHint) ~= "string" or #change.classHint > 32 or not change.classHint:match("^[A-Z_]+$")) then
        return false, "invalid_change_class_hint"
      end
    elseif change.op ~= "delete" then
      return false, "invalid_change_operation"
    end
    validated[#validated + 1] = {
      rev = expected, op = change.op, kind = change.kind, key = change.key,
      entry = CloneOfficialEntry(change.entry), changedAt = tonumber(change.changedAt),
      changedBy = type(change.changedBy) == "string" and change.changedBy or tostring(sourceIdentity),
      classHint = type(change.classHint) == "string" and change.classHint or nil,
    }
    expected = expected + 1
  end
  if expected - 1 ~= target then return false, "target_revision_mismatch" end

  data.changes = type(data.changes) == "table" and data.changes or {}
  for _, change in ipairs(validated) do
    local targetList = change.kind == "P" and data.players or data.guilds
    if change.op == "upsert" then
      local entry = CloneOfficialEntry(change.entry)
      if change.classHint then entry.classHint = change.classHint end
      targetList[change.key] = PreserveLocalEntryFields(entry, targetList[change.key])
    else
      targetList[change.key] = nil
    end
    data.changes[change.rev] = change
  end

  local revisions = {}
  for rev in pairs(data.changes) do
    local numeric = tonumber(rev)
    if numeric then revisions[#revisions + 1] = numeric end
  end
  table.sort(revisions)
  while #revisions > 1000 do
    local oldest = table.remove(revisions, 1)
    data.changes[oldest] = nil
    data.changeFloor = math.max(tonumber(data.changeFloor) or 0, oldest)
  end

  data.revision = target
  data.syncSchemaVersion = 2
  data.syncLastMaster = tostring(sourceIdentity)
  data.syncLastRevision = target
  InvalidateOfficialDigest()
  RefreshAfterOfficialSync()
  return true
end

local MAX_CHANGE_HISTORY = 1000
local function RecordOfficialChange(data, op, kind, key, entry)
  data.changes = type(data.changes) == "table" and data.changes or {}
  data.revision = (tonumber(data.revision) or 0) + 1
  local revision = data.revision
  local master = _G.KillOnSight_Master
  data.changes[revision] = {
    rev = revision,
    op = op,
    kind = kind,
    key = key,
    entry = CloneOfficialEntry(entry),
    classHint = (kind == "P" and ResolvePlayerClassHint(data, entry)) or nil,
    changedAt = Now(),
    changedBy = (master and master.GetPlayerIdentity and master:GetPlayerIdentity()) or UnitName("player") or "Unknown",
  }

  local revisions = {}
  for rev in pairs(data.changes) do
    local numeric = tonumber(rev)
    if numeric then revisions[#revisions + 1] = numeric end
  end
  table.sort(revisions)
  while #revisions > MAX_CHANGE_HISTORY do
    local oldest = table.remove(revisions, 1)
    data.changes[oldest] = nil
    data.changeFloor = math.max(tonumber(data.changeFloor) or 0, oldest)
  end

  -- A single official edit automatically enters the whisper sync queue.
  -- Applying an inbound sync never calls this function, so updates do not loop.
  local comm = _G.KillOnSight_Comm
  if master and master.IsMaster and master:IsMaster() and comm and comm.OnOfficialChange then
    pcall(function() comm:OnOfficialChange(revision) end)
  end
end

function DB:AddPlayer(name, listType, reason, addedBy, class)
  if not RequireMasterEdit("add or update Player KoS entries") then return false end
  name = norm(name); if not name then return false end
  local key = CanonicalPlayerKey(name)
  -- Retail/Midnight: some UI surfaces provide full names (Name-Realm) while Nearby normalizes
  -- to short names. Notify Nearby for both keys so tags update immediately either way.
  local shortKey
  if _G.Ambiguate then
    local s = Ambiguate(name, "short")
    if s and s ~= "" then
      shortKey = s:lower()
    end
  end
  local d = self:GetData()
  local existing = d.players[key]
  local entry = MakePlayerEntry(name, listType, reason, addedBy, existing, class)
  if not existing then entry.addedOrder = NextListOrder(d) end
  d.players[key] = entry
  RecordOfficialChange(d, "upsert", "P", key, entry)
  local N = _G.KillOnSight_Nearby
  if N and N.OnListChanged then
    pcall(function() N:OnListChanged("P", key) end)
    if shortKey and shortKey ~= key then pcall(function() N:OnListChanged("P", shortKey) end) end
  end
  return true
end

function DB:RemovePlayer(name)
  if not RequireMasterEdit("remove Player KoS entries") then return false end
  name = norm(name); if not name then return false end
  local key = CanonicalPlayerKey(name)
  local shortKey
  if _G.Ambiguate then
    local s = Ambiguate(name, "short")
    if s and s ~= "" then
      shortKey = s:lower()
    end
  end
  local d = self:GetData()
  local removedKey
  if d.players[key] then
    removedKey = key
  elseif shortKey and d.players[shortKey] then
    -- Allow removing a player even if this client stored/entered Name-Realm earlier.
    removedKey = shortKey
  end

  if removedKey then
    d.players[removedKey] = nil
    RecordOfficialChange(d, "delete", "P", removedKey, nil)
    local N = _G.KillOnSight_Nearby
    if N and N.OnListChanged then
      -- Notify both full and short keys so Nearby retags immediately regardless of how the entry was stored.
      pcall(function() N:OnListChanged("P", key) end)
      if shortKey and shortKey ~= key then pcall(function() N:OnListChanged("P", shortKey) end) end
    end
    return true
  end
  return false
end

function DB:AddGuild(guild, listType, reason, addedBy)
  if not RequireMasterEdit("add or update Guild KoS entries") then return false end
  guild = norm(guild); if not guild then return false end
  local key = guild:lower()
  local d = self:GetData()
  local existing = d.guilds[key]
  local entry = MakeGuildEntry(guild, listType, reason, addedBy, existing)
  if not existing then entry.addedOrder = NextListOrder(d) end
  d.guilds[key] = entry
  RecordOfficialChange(d, "upsert", "G", key, entry)
  local N = _G.KillOnSight_Nearby
  if N and N.OnListChanged then pcall(function() N:OnListChanged("G", key) end) end
  return true
end

function DB:RemoveGuild(guild)
  if not RequireMasterEdit("remove Guild KoS entries") then return false end
  guild = norm(guild); if not guild then return false end
  local key = guild:lower()
  local d = self:GetData()
  if d.guilds[key] then
    d.guilds[key] = nil
    RecordOfficialChange(d, "delete", "G", key, nil)
    local N = _G.KillOnSight_Nearby
    if N and N.OnListChanged then pcall(function() N:OnListChanged("G", key) end) end
    return true
  end
  return false
end

function DB:LookupPlayer(name)
  if not name then return nil end
  return self:GetData().players[CanonicalPlayerKey(name)]
end

function DB:LookupGuild(guild)
  if not guild or guild == "" then return nil end
  return self:GetData().guilds[guild:lower()]
end

function DB:SetPlayerClass(name, class)
  if not name or not class then return false end
  local key = CanonicalPlayerKey(name)
  local d = self:GetData()
  local e = d.players[key]
  if not e then return false end
  if e.class == class then return false end
  e.class = class
  e.modifiedAt = Now()
  local master = _G.KillOnSight_Master
  if master and master.IsMaster and master:IsMaster() then
    RecordOfficialChange(d, "upsert", "P", key, e)
  end
  return true
end

-- Update the optional note/reason attached to a KoS player.
-- This is metadata only and does not affect detection.
function DB:SetPlayerReason(name, reason)
  if not RequireMasterEdit("edit Player KoS notes") then return false end
  name = norm(name); if not name then return false end
  local key = CanonicalPlayerKey(name)
  local d = self:GetData()
  local e = d.players[key]
  if not e then return false end

  local r = norm(reason)
  if r == "" then r = nil end
  if e.reason == r then return false end

  e.reason = r
  e.modifiedAt = Now()
  RecordOfficialChange(d, "upsert", "P", key, e)
  return true
end
function DB:HasPlayer(name)
  return self:LookupPlayer(name) ~= nil
end

function DB:HasGuild(guild)
  return self:LookupGuild(guild) ~= nil
end
function DB:MarkSeenPlayer(name)
  local e = self:LookupPlayer(name)
  if e then
    e.lastSeenAt = Now()
    e.lastSeenZone = GetRealZoneText() or GetZoneText() or ""
  end
end

function DB:MarkSeenGuild(guild)
  local e = self:LookupGuild(guild)
  if e then
    e.lastSeenAt = Now()
    e.lastSeenZone = GetRealZoneText() or GetZoneText() or ""
  end
end

-- Enemy encounter stats (separate from KoS/Guild lists)
local function _ForeverStatsMode()
  if type(_G.RegionalUniqueNamesEnabled) ~= "function" then return false end
  local ok, enabled = pcall(_G.RegionalUniqueNamesEnabled)
  return ok and enabled == true
end

local function _StatsKey(name)
  if type(name) ~= "string" or name == "" then return nil end
  if _ForeverStatsMode() then
    -- In Forever the legacy realm separator represents a surname.
    return (name:gsub("%-", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")):lower()
  end
  return (name:match("^[^-]+") or name):lower()
end

local function _MergeStatsRecord(dst, src)
  if not dst or not src then return end
  for _, field in ipairs({"seenCount", "wins", "loses"}) do
    -- Legacy duplicates often count the same encounter twice: avoid inflation.
    dst[field] = math.max(tonumber(dst[field]) or 0, tonumber(src[field]) or 0)
  end
  local first = tonumber(src.firstSeenAt) or 0
  if first > 0 and (not dst.firstSeenAt or dst.firstSeenAt == 0 or first < dst.firstSeenAt) then dst.firstSeenAt = first end
  if (tonumber(src.lastSeenAt) or 0) > (tonumber(dst.lastSeenAt) or 0) then dst.lastSeenAt = src.lastSeenAt end
  for _, field in ipairs({"classFile", "guild", "faction", "realm", "fullName"}) do
    if (not dst[field] or dst[field] == "") and src[field] and src[field] ~= "" then dst[field] = src[field] end
  end
end

local function _ConsolidateForeverStats(data, fullKey)
  if not _ForeverStatsMode() then return end
  local stats = data.statsPlayers or {}
  -- Consolidate alternative separators and old first-name-only records.
  -- Never merge two distinct full names merely because they share a first name.
  local target = stats[fullKey]
  for oldKey, entry in pairs(stats) do
    if oldKey ~= fullKey and type(entry) == "table" then
      local canonical = _StatsKey(entry.fullName or ((entry.name or "") .. ((entry.realm and entry.realm ~= "") and (" " .. entry.realm) or "")))
      local keyCanonical = _StatsKey(oldKey)
      local exact = canonical == fullKey or keyCanonical == fullKey
      -- A first-name-only record is never proof of the same player.
      -- Merge only when both records explicitly resolve to the same full identity.
      if exact then
        if not target then target = entry; stats[fullKey] = target
        else _MergeStatsRecord(target, entry) end
        stats[oldKey] = nil
        data.statsRevision = (tonumber(data.statsRevision) or 0) + 1
      end
    end
  end
end

-- Repair historical Stats keys on demand, including records already saved before
-- a player is sighted again. Never combine two different surnames.
function DB:ConsolidateStatsDuplicates()
  if not _ForeverStatsMode() then return 0 end
  local data = self:GetData()
  local stats = data.statsPlayers or {}
  local function canonical(k, e)
    local name = type(e.fullName) == "string" and e.fullName or ""
    if name == "" then
      name = type(e.name) == "string" and e.name or ""
      if type(e.realm) == "string" and e.realm ~= "" then
        local base = name:match("^([^%s%-]+)") or name
        name = base .. " " .. e.realm
      end
    end
    local key = _StatsKey(name)
    if key and key:find(" ", 1, true) then return key end
    key = _StatsKey(k)
    if key and key:find(" ", 1, true) then return key end
    return nil
  end
  local changes = 0
  local keys = {}
  for k in pairs(stats) do keys[#keys+1] = k end
  for _, k in ipairs(keys) do
    local e = stats[k]
    if type(e) == "table" then
      local c = canonical(k, e)
      if c and c ~= k then
        if type(stats[c]) == "table" then _MergeStatsRecord(stats[c], e)
        else stats[c] = e end
        stats[k] = nil
        changes = changes + 1
      end
    end
  end
  if changes > 0 then
    data.statsRevision = (tonumber(data.statsRevision) or 0) + 1
  end
  return changes
end

-- Update / create an enemy stats record WITHOUT incrementing encounter count.
--
-- We treat "seenCount" as *encounters*, not raw detection events.
-- The encounter counter is incremented only when an encounter resolves
-- (win/loss/timeout) via StatsAddSeenEncounter().
-- Optional guid lets us backfill class for enemies where we don't yet have a unit.
function DB:NoteEnemySeen(name, classFile, guild, guid, factionGroup)
  local d = self:GetData()
  d.statsPlayers = d.statsPlayers or {}

  local key = _StatsKey(name)
  if not key then return end

  -- Safety: do not allow pets/totems/NPCs to create stats records.
  -- If we have a GUID, only accept real player GUIDs ("Player-####-########").
  if guid and guid ~= "" and not guid:match('^Player%-') then
    return
  end

  if _ForeverStatsMode() and key:find(" ", 1, true) then _ConsolidateForeverStats(d, key) end
  local now = Now()
  local e = d.statsPlayers[key]
  if not e then
    e = {
      name = _ForeverStatsMode() and key or (name:match("^[^-]+") or name),
      firstSeenAt = now,
      lastSeenAt = now,
      seenCount = 0, -- incremented by StatsAddSeenEncounter()
    }
    d.statsPlayers[key] = e
    self:_BumpStatsRevision()
  else
    if e.lastSeenAt ~= now then
      e.lastSeenAt = now
      self:_BumpStatsRevision()
    end
  end

  -- If we weren't given class, try GUID lookup (works on many clients when GUID is resolvable).
  if (not classFile or classFile == "") and guid and guid ~= "" and GetPlayerInfoByGUID then
    local _, cls = GetPlayerInfoByGUID(guid)
    classFile = cls
  end

  if classFile and classFile ~= "" then
    local cf = _NormalizeClassForDB(classFile) or classFile
    if e.classFile ~= cf then
      e.classFile = cf
      self:_BumpStatsRevision()
    end
  end
  if guild and guild ~= "" then
    if e.guild ~= guild then
      e.guild = guild
      self:_BumpStatsRevision()
    end
  end

  -- Track realm/fullName for cross-realm identification (do not depend on guild being known)
  if name and name ~= "" then
    local base = name:match("^[^-]+") or name
    local realm = name:match("^[^-]+%-(.+)$") or ""
    if _ForeverStatsMode() then
      base = key:match("^(%S+)") or key
      realm = key:match("^%S+ (.+)$") or ""
    end
    if e.name ~= base then e.name = base; self:_BumpStatsRevision() end
    if e.realm ~= realm then e.realm = realm; self:_BumpStatsRevision() end
    if e.fullName ~= name then e.fullName = name; self:_BumpStatsRevision() end
  end


if factionGroup and factionGroup ~= "" then
  if e.faction ~= factionGroup then
    e.faction = factionGroup
    self:_BumpStatsRevision()
  end
end
end

-- Increment "seenCount" once per encounter resolution (win/loss/timeout).
function DB:StatsAddSeenEncounter(name)
  local d = self:GetData(); d.statsPlayers = d.statsPlayers or {}
  local key = _StatsKey(name)
  if not key then return end
  if _ForeverStatsMode() and key:find(" ", 1, true) then _ConsolidateForeverStats(d, key) end
  local now = Now()
  local e = d.statsPlayers[key]
  if not e then
    e = { name = name:match("^[^-]+") or name, firstSeenAt = now, lastSeenAt = now, seenCount = 0 }
    d.statsPlayers[key] = e
    self:_BumpStatsRevision()
  end
  e.lastSeenAt = now
  e.seenCount = (tonumber(e.seenCount or 0) or 0) + 1
  self:_BumpStatsRevision()
end

function DB:StatsAddWin(name)
  local d = self:GetData(); d.statsPlayers = d.statsPlayers or {}
  local key = _StatsKey(name)
  if not key then return end
  local e = d.statsPlayers[key]
  if not e then
    e = { name = name:match("^[^-]+") or name, firstSeenAt = Now(), lastSeenAt = Now(), seenCount = 0 }
    d.statsPlayers[key] = e
    self:_BumpStatsRevision()
  end
  e.wins = (tonumber(e.wins or 0) or 0) + 1
  self:_BumpStatsRevision()
end

function DB:StatsAddLoss(name)
  local d = self:GetData(); d.statsPlayers = d.statsPlayers or {}
  local key = _StatsKey(name)
  if not key then return end
  local e = d.statsPlayers[key]
  if not e then
    e = { name = name:match("^[^-]+") or name, firstSeenAt = Now(), lastSeenAt = Now(), seenCount = 0 }
    d.statsPlayers[key] = e
    self:_BumpStatsRevision()
  end
  e.loses = (tonumber(e.loses or 0) or 0) + 1
  self:_BumpStatsRevision()
end
-- Return stats record for a player (or nil). Useful for pulling cached faction/class/guild.
function DB:StatsGetPlayer(name)
  local d = self:GetData(); d.statsPlayers = d.statsPlayers or {}
  local key = _StatsKey(name)
  if not key then return nil end
  return d.statsPlayers[key]
end

-- Returns true if an enemy stats record already exists for this name.
-- Useful when callers want to *enrich* existing records without creating new ones
-- (e.g. deferred guild resolution), so "Reset Stats" stays a true wipe.
function DB:HasStatsPlayer(name)
  local d = self:GetData(); d.statsPlayers = d.statsPlayers or {}
  local key = _StatsKey(name)
  if not key then return false end
  return d.statsPlayers[key] ~= nil
end

function DB:AddLastAttacker(name, guid, zone, guild, classFile)
  if not name or name == "" then return end
  local d = self:GetData()
  d.lastAttackers = d.lastAttackers or {}
  local keyName = CanonicalPlayerKey(name)
  local keyGUID = (guid and guid ~= "") and guid or nil


  -- Resolve/persist class immediately when possible (prevents "late recolor" after login)
  local class = _NormalizeClassForDB(classFile)
  if not class and keyGUID and GetPlayerInfoByGUID then
    local _, cls = GetPlayerInfoByGUID(keyGUID)
    class = _NormalizeClassForDB(cls)
  end
  -- remove existing entry (prefer GUID match when available)
  for j = #d.lastAttackers, 1, -1 do
    local e = d.lastAttackers[j]
    if e then
      if keyGUID and e.guid == keyGUID then
        table.remove(d.lastAttackers, j)
      elseif (not keyGUID) and e.name and CanonicalPlayerKey(e.name) == keyName then
        table.remove(d.lastAttackers, j)
      end
    end
  end

  table.insert(d.lastAttackers, 1, { name = name,
        class = class, guid = guid or "", zone = zone or "", guild = guild or "" })

  -- Keep enemy stats metadata in sync with what we already know for attackers.
  -- (Encounter counting is handled in Core.lua; this only refreshes metadata.)
  if self.NoteEnemySeen then
    self:NoteEnemySeen(name, class, guild, guid)
  end

  -- cap
	while #d.lastAttackers > 200 do
    table.remove(d.lastAttackers)
  end
end

function DB:UpdateLastAttackerGuild(name, guild)
  if (not guild) or guild == "" then return end
  local d = self:GetData()
  d.lastAttackers = d.lastAttackers or {}

  local keyName = (name and name ~= "") and CanonicalPlayerKey(name) or nil
  local keyGUID = (name and name:find("^Player%-")) and name or nil
  -- If caller passed a GUID in the first arg, match by GUID; otherwise match by name.
  for j = 1, #d.lastAttackers do
    local e = d.lastAttackers[j]
    if e then
      if keyGUID and e.guid == keyGUID then
        e.guild = guild
        if self.NoteEnemySeen then
          self:NoteEnemySeen(e.name or name, e.class, guild, e.guid)
        end
        return
      elseif (not keyGUID) and keyName and e.name and CanonicalPlayerKey(e.name) == keyName then
        e.guild = guild
        if self.NoteEnemySeen then
          self:NoteEnemySeen(e.name or name, e.class, guild, e.guid)
        end
        return
      end
    end
  end
end

function DB:UpdateLastAttackerGuildByGUID(guid, guild)
  if not guid or guid == "" then return end
  if not guild or guild == "" then return end
  local d = self:GetData()
  d.lastAttackers = d.lastAttackers or {}
  for i=1,#d.lastAttackers do
    local e = d.lastAttackers[i]
    if e and e.guid == guid then
      e.guild = guild
      if self.NoteEnemySeen then
        self:NoteEnemySeen(e.name, e.class, guild, e.guid)
      end
      return true
    end
  end
end

function DB:GetLastAttackers()
  local d = self:GetData()
  d.lastAttackers = d.lastAttackers or {}
  return d.lastAttackers
end

function DB:ClearLastAttackers()
  local d = self:GetData()
  d.lastAttackers = {}
end


function DB:ClearStatsPlayers()
  local d = self:GetData()
  d.statsPlayers = {}
  d.lastAttackers = {}
  self:_BumpStatsRevision()
end

function DB:PruneStatsPlayers()
  local p = self:GetSettings()
  if not p.statsPruneEnabled then return 0 end

  local maxDays = tonumber(p.statsPruneMaxDays or 0) or 0
  local maxEntries = tonumber(p.statsPruneMaxEntries or 0) or 0

  local d = self:GetData()
  d.statsPlayers = d.statsPlayers or {}
  local stats = d.statsPlayers
  local now = Now()
  local removed = 0

  -- 1) Drop entries older than maxDays (based on lastSeenAt)
  if maxDays and maxDays > 0 then
    local cutoff = now - (maxDays * 86400)
    for k,e in pairs(stats) do
      local last = tonumber(e and e.lastSeenAt or 0) or 0
      if last > 0 and last < cutoff then
        stats[k] = nil
        removed = removed + 1
      end
    end
  end

  -- 2) Hard cap by removing oldest lastSeenAt
  if maxEntries and maxEntries > 0 then
    local count = 0
    for _ in pairs(stats) do count = count + 1 end
    if count > maxEntries then
      local keys = {}
      for k,e in pairs(stats) do
        keys[#keys+1] = { k=k, last=tonumber(e and e.lastSeenAt or 0) or 0 }
      end
      table.sort(keys, function(a,b) return (a.last or 0) < (b.last or 0) end)
      local toDrop = count - maxEntries
      for i=1, toDrop do
        if keys[i] and keys[i].k then
          stats[keys[i].k] = nil
          removed = removed + 1
        end
      end
    end
  end

  if removed > 0 then
    self:_BumpStatsRevision()
  end
  return removed
end


KillOnSight_DB = DB
