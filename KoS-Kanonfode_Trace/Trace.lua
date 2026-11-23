-- Optional, local-only diagnostic trace for KoS-Kanonfode.
-- It starts automatically when this child add-on is enabled in WoW's AddOns list.
local Trace = {
  enabled = true,
  events = {},
}

KillOnSight_Trace = Trace

local COUNT_ONLY = {
  ["detector/target_scan_unit_missing"] = true,
  ["detector/target_scan_not_hostile_player"] = true,
  ["detector/target_scan_not_targeting_you"] = true,
  ["detector/target_scan_target_state_unknown"] = true,
  ["detector/target_scan_confirmed"] = true,
  ["detector/target_alert_repeat_suppressed"] = true,
  ["detector/target_alert_not_targeting"] = true,
  ["detector/target_alert_cooldown"] = true,
  ["detector/target_alert_suppressed"] = true,
  ["notifier/target_alert_goblin_suppressed"] = true,
  ["notifier/target_alert_not_shown"] = true,
  ["detector/unit_missing"] = true,
}
local MAX_EVENTS = 80
local REPORT_EVENTS = 16
local FIELD_ORDER = {
  "unit", "db", "notifier", "detector", "nearby", "core", "active",
  "player", "playerGuid", "hostile", "enemy", "attackable", "friendly",
  "direct", "forced", "within", "distanceKnown", "distanceSq", "rangeYards",
  "frameEnabled", "goblinFilter", "sound", "flash", "alertMode",
  "alertStatus",
}
local ALLOWED_FIELDS = {}
for _, key in ipairs(FIELD_ORDER) do ALLOWED_FIELDS[key] = true end

local function SafeNow()
  if type(GetTime) == "function" then
    local ok, value = pcall(GetTime)
    if ok and type(value) == "number" then return value end
  end
  return 0
end

local function ModuleStatus()
  local Core = _G.KillOnSight_Core
  local active
  if Core and Core.IsKoSActive then
    local ok, value = pcall(function() return Core:IsKoSActive() end)
    if ok and type(value) == "boolean" then active = value end
  end
  return {
    db = _G.KillOnSight_DB ~= nil,
    notifier = _G.KillOnSight_Notifier ~= nil,
    detector = _G.KillOnSight_Detector ~= nil,
    nearby = _G.KillOnSight_Nearby ~= nil,
    core = Core ~= nil,
    active = active,
  }
end

local function SafeCopyField(fields, key)
  local ok, value = pcall(function()
    if type(fields) ~= "table" or not ALLOWED_FIELDS[key] then return nil end
    local candidate = fields[key]
    local kind = type(candidate)
    if kind == "boolean" or kind == "number" then return candidate end
    if kind == "string" and #candidate <= 24 then return candidate end
    return nil
  end)
  if ok then return value end
  return nil
end

function Trace:Record(component, reason, fields)
  if not self.enabled then return end
  local countKey = tostring(component or "unknown") .. "/" .. tostring(reason or "unknown")
  if COUNT_ONLY[countKey] then
    local status = SafeCopyField(fields, "alertStatus")
    if type(status) == "string" then countKey = countKey .. ":" .. status end
    self.counts = self.counts or {}
    self.counts[countKey] = (self.counts[countKey] or 0) + 1
    return
  end
  local event = {
    at = math.max(0, SafeNow() - (self.startedAt or SafeNow())),
    component = tostring(component or "unknown"),
    reason = tostring(reason or "unknown"),
    fields = {},
  }
  for _, key in ipairs(FIELD_ORDER) do
    local value = SafeCopyField(fields, key)
    if value ~= nil then event.fields[key] = value end
  end
  self.events[#self.events + 1] = event
  if #self.events > MAX_EVENTS then table.remove(self.events, 1) end
end

function Trace:Enable()
  self.events = {}
  self.counts = {}
  self.startedAt = SafeNow()
  self.enabled = true
  self:Record("trace", "enabled")
  self:Record("startup", "module_state", ModuleStatus())
  return true
end

function Trace:Disable()
  self:Record("trace", "disabled")
  self.enabled = false
  return true
end

function Trace:Clear()
  self.events = {}
  self.counts = {}
  if self.enabled then self:Record("trace", "cleared") end
  return true
end

function Trace:Help()
  return table.concat({
    "K-KoS bug tracer (local, starts when its AddOns checkbox is enabled):",
    "Reproduce the issue, then /dump KillOnSight_Trace:Report()",
    "/dump KillOnSight_Trace:Disable()",
    "/dump KillOnSight_Trace:Clear()",
  }, "\n")
end

function Trace:Report()
  local version = _G.KillOnSight_Version and _G.KillOnSight_Version.CURRENT or "unknown"
  local modules = ModuleStatus()
  local lines = {
    "K-KoS trace v" .. tostring(version) .. " active=" .. tostring(self.enabled)
      .. " events=" .. tostring(#self.events),
    string.format("modules: DB=%s Notifier=%s Detector=%s Nearby=%s Core=%s active=%s",
      tostring(modules.db), tostring(modules.notifier), tostring(modules.detector),
      tostring(modules.nearby), tostring(modules.core), tostring(modules.active)),
  }
  local countParts = {}
  for key, n in pairs(self.counts or {}) do countParts[#countParts + 1] = key .. "=" .. n end
  table.sort(countParts)
  if #countParts > 0 then lines[#lines + 1] = "counted (not stored): " .. table.concat(countParts, " ") end
  local first = math.max(1, #self.events - REPORT_EVENTS + 1)
  for i = first, #self.events do
    local event = self.events[i]
    local parts = {}
    for _, key in ipairs(FIELD_ORDER) do
      local value = event.fields[key]
      if value ~= nil then parts[#parts + 1] = key .. "=" .. tostring(value) end
    end
    local line = string.format("+%.1fs %s/%s", event.at, event.component, event.reason)
    if #parts > 0 then line = line .. " " .. table.concat(parts, " ") end
    lines[#lines + 1] = line
  end
  return table.concat(lines, "\n")
end

Trace.startedAt = SafeNow()
Trace:Record("trace", "auto_started")
Trace:Record("startup", "module_state", ModuleStatus())
