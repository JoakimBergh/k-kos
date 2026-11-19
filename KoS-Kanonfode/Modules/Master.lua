-- Master.lua
-- Local master identity and permissions for official Player/Guild KoS lists.
-- This is an addon-level permission boundary, not cryptographic protection
-- against a user modifying their own local addon files.
local Master = {}

Master.NAME = "Calámir Dawnsinger"

local function NormalizeIdentity(value)
  if type(value) ~= "string" then return nil end
  value = value:gsub("^%s+", ""):gsub("%s+$", "")
  value = value:gsub("%s+", " ")
  if value == "" then return nil end
  return value:lower()
end

local MASTER_KEY = NormalizeIdentity(Master.NAME)

local function AddCandidate(out, value)
  local key = NormalizeIdentity(value)
  if not key then return end
  for _, existing in ipairs(out) do
    if existing == key then return end
  end
  out[#out + 1] = key
end

local function StripRealmSuffix(key)
  if not key then return nil end
  -- On clients that append a realm to a full character name, remove only a
  -- final -Realm suffix when the left side already contains the full name.
  local left = key:match("^(.-)%-[^%-]+$")
  if left and left:find("%s") then
    left = left:gsub("%s+$", "")
    return left
  end
  return key
end

function Master:GetIdentityCandidates()
  local out = {}
  local util = _G.KillOnSight_Util
  if util and util.UnitPlayerName then
    local ok, value = pcall(function() return util:UnitPlayerName("player") end)
    if ok then AddCandidate(out, value) end
  end

  if type(_G.GetUnitName) == "function" then
    local ok, value = pcall(_G.GetUnitName, "player", true)
    if ok then AddCandidate(out, value) end
  end

  if type(_G.UnitFullName) == "function" then
    local ok, first, second = pcall(_G.UnitFullName, "player")
    if ok and type(first) == "string" and first ~= "" then
      if type(second) == "string" and second ~= "" then
        AddCandidate(out, first .. " " .. second)
      else
        AddCandidate(out, first)
      end
    end
  end

  if type(_G.UnitName) == "function" then
    local ok, first, second = pcall(_G.UnitName, "player")
    if ok and type(first) == "string" and first ~= "" then
      if type(second) == "string" and second ~= "" then
        AddCandidate(out, first .. " " .. second)
      else
        AddCandidate(out, first)
      end
    end
  end
  return out
end

function Master:GetPlayerIdentity()
  local util = _G.KillOnSight_Util
  if util and util.UnitPlayerName then
    local ok, value = pcall(function() return util:UnitPlayerName("player") end)
    if ok and type(value) == "string" and value ~= "" then return value end
  end
  if type(_G.GetUnitName) == "function" then
    local ok, value = pcall(_G.GetUnitName, "player", true)
    if ok and type(value) == "string" and value ~= "" then return value end
  end
  if type(_G.UnitFullName) == "function" then
    local ok, first, second = pcall(_G.UnitFullName, "player")
    if ok and type(first) == "string" and first ~= "" then
      if type(second) == "string" and second ~= "" then return first .. " " .. second end
      return first
    end
  end
  if type(_G.UnitName) == "function" then
    local ok, first, second = pcall(_G.UnitName, "player")
    if ok and type(first) == "string" and first ~= "" then
      if type(second) == "string" and second ~= "" then return first .. " " .. second end
      return first
    end
  end
  return "Unknown"
end

function Master:IsMasterIdentity(identity)
  local key = NormalizeIdentity(identity)
  if not key then return false end
  if key == MASTER_KEY then return true end
  return StripRealmSuffix(key) == MASTER_KEY
end

function Master:IsMaster()
  for _, candidate in ipairs(self:GetIdentityCandidates()) do
    if candidate == MASTER_KEY or StripRealmSuffix(candidate) == MASTER_KEY then
      return true
    end
  end
  return false
end

function Master:CanEditOfficialLists()
  return self:IsMaster()
end

function Master:RequireEdit(action)
  if self:CanEditOfficialLists() then return true end
  local label = action or "edit the official KoS lists"
  local message = "Read-only: only " .. self.NAME .. " can " .. label .. "."
  if _G.DEFAULT_CHAT_FRAME and _G.DEFAULT_CHAT_FRAME.AddMessage then
    _G.DEFAULT_CHAT_FRAME:AddMessage("|cffff5555K-KoS:|r " .. message)
  elseif _G.print then
    _G.print("K-KoS: " .. message)
  end
  return false
end

_G.KillOnSight_Master = Master
