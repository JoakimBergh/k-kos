-- ClassDiscovery.lua
-- Read-only class lookup for the communication layer. This module never
-- initializes, migrates, or writes the official SavedVariables database.

local Discovery = {}

local VALID_CLASS_FILES = {
  WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true,
  PRIEST = true, SHAMAN = true, MAGE = true, WARLOCK = true,
  DRUID = true,
}

local function StripRealmSuffix(name)
  if type(name) ~= "string" then return name end
  local left = name:match("^(.-)%-[^%-]+$")
  if left and left:find("%s") then return left end
  return name
end

local function NameKey(name)
  if type(name) ~= "string" or name == "" then return nil end
  name = StripRealmSuffix(name)
  local util = _G.KillOnSight_Util
  if util and util.PlayerKey then
    local ok, key = pcall(function() return util:PlayerKey(name) end)
    if ok and type(key) == "string" and key ~= "" then return key end
  end
  return name:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
end

local function NamesMatch(a, b)
  local ka, kb = NameKey(a), NameKey(b)
  if not ka or not kb then return false end
  return ka == kb or StripRealmSuffix(ka) == StripRealmSuffix(kb)
end

function Discovery:NormalizeClassFile(value)
  if type(value) ~= "string" or value == "" then return nil end
  local upper = value:upper()
  if VALID_CLASS_FILES[upper] then return upper end
  if _G.LOCALIZED_CLASS_NAMES_MALE then
    for file, localized in pairs(_G.LOCALIZED_CLASS_NAMES_MALE) do
      if localized == value and VALID_CLASS_FILES[file] then return file end
    end
  end
  if _G.LOCALIZED_CLASS_NAMES_FEMALE then
    for file, localized in pairs(_G.LOCALIZED_CLASS_NAMES_FEMALE) do
      if localized == value and VALID_CLASS_FILES[file] then return file end
    end
  end
  return nil
end

-- Read only existing class observations. This lookup does not call database
-- initialization, create rows, change list tables, or persist class updates.
function Discovery:FindKnownPlayerClass(name)
  if type(name) ~= "string" or name == "" then return nil end
  local db = _G.KillOnSight_DB
  -- Read the already-initialized DB object directly. Calling GetData or
  -- LookupPlayer here could invoke defensive database initialization.
  local realmDB = db and db.realmDB
  local data = type(realmDB) == "table" and realmDB.data or nil
  if type(data) ~= "table" then return nil end

  local players = data.players
  local key = NameKey(name)
  local player = type(players) == "table" and key and (players[key] or players[name:lower()]) or nil
  if type(player) == "table" then
    local classFile = self:NormalizeClassFile(player.class)
    if classFile then return classFile end
  end

  local stats = data.statsPlayers
  if key and type(stats) == "table" then
    local record = stats[key]
    if type(record) == "table" then
      local fullName = record.fullName
      if type(fullName) ~= "string" or fullName == "" then
        local first, surname = record.name, record.realm
        if type(first) == "string" and first ~= "" and type(surname) == "string" and surname ~= "" then
          fullName = first .. " " .. surname
        end
      end
      if not fullName or fullName == "" or NamesMatch(fullName, name) then
        local classFile = self:NormalizeClassFile(record.classFile or record.class)
        if classFile then return classFile end
      end
    end

    -- Legacy record keys are accepted only with an exact full identity match.
    for _, candidate in pairs(stats) do
      if type(candidate) == "table" then
        local fullName = candidate.fullName
        if type(fullName) ~= "string" or fullName == "" then
          local first, surname = candidate.name, candidate.realm
          if type(first) == "string" and first ~= "" and type(surname) == "string" and surname ~= "" then
            fullName = first .. " " .. surname
          end
        end
        if type(fullName) == "string" and fullName ~= "" and NamesMatch(fullName, name) then
          local classFile = self:NormalizeClassFile(candidate.classFile or candidate.class)
          if classFile then return classFile end
        end
      end
    end
  end

  local nearby = _G.KillOnSight_Nearby
  local entries = nearby and nearby.entries
  if type(entries) == "table" then
    for _, candidate in pairs(entries) do
      if type(candidate) == "table" then
        local candidateName = candidate.fullName or candidate.name
        if type(candidateName) == "string" and NamesMatch(candidateName, name) then
          local classFile = self:NormalizeClassFile(candidate.classFile or candidate.class)
          if not classFile and type(candidate.guid) == "string" and candidate.guid ~= ""
              and type(_G.GetPlayerInfoByGUID) == "function" then
            local guidOK, localizedClass, englishClass = pcall(_G.GetPlayerInfoByGUID, candidate.guid)
            if guidOK then
              classFile = self:NormalizeClassFile(englishClass) or self:NormalizeClassFile(localizedClass)
            end
          end
          if classFile then return classFile end
        end
      end
    end
  end
  return nil
end

_G.KillOnSight_ClassDiscovery = Discovery
