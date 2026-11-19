-- Comm.lua
-- Automatic, silent master-to-member synchronization for WoW Forever.
-- All payload traffic uses WHISPER. We deliberately avoid GUILD addon messages
-- because the Forever client can scroll the guild chat window for each one.
local PREFIX = "KOSKANON"
local PROTOCOL = 4
local VERSION = _G.KillOnSight_Version and _G.KillOnSight_Version.CURRENT or "0.4.18"
local MASTER_NAME = "Calámir Dawnsinger"
local HELLO_INTERVAL = 60
local PEER_TTL = 600
local CHUNK_SIZE = 160
local MAX_TRANSFER_BYTES = 1024 * 1024
local MAX_TRANSFER_CHUNKS = 8192
local SEND_INTERVAL = 0.25
local ACK_RETRY_LIMIT = 2
local DIGEST_MISMATCH_LIMIT = 2
local DIGEST_MISMATCH_BACKOFF = 300
local HELLO_RESPONSE_TIMEOUT = 20
local CLASS_QUERY_COOLDOWN = 180
local CLASS_QUERY_TIMEOUT = 45
local CLASS_QUERY_REPLY_COOLDOWN = 60
local CLASS_QUERY_REPLY_WINDOW = 60
local CLASS_QUERY_REPLY_WINDOW_MAX = 30
local CLASS_QUERY_SWEEP_LIMIT = 5

local Comm = {
  prefix = PREFIX,
  protocol = PROTOCOL,
  version = VERSION,
  initialized = false,
  registered = false,
  registrationResult = nil,
  peers = {},
  incoming = {},
  completed = {},
  pendingTransfers = {},
  sendQueue = {},
  sendQueueHead = 1,
  nextTransferId = 0,
  lastHelloAt = 0,
  helloQueued = false,
  syncState = "Initializing",
  syncDetail = "",
  lastError = nil,
  digestCacheRevision = nil,
  digestCacheValue = nil,
  awaitingMasterSince = nil,
  pendingClassQueries = {},
  classQueryByKey = {},
  lastClassQueryAt = {},
  incomingClassQueryAt = {},
  incomingClassReplyWindowAt = 0,
  incomingClassReplyCount = 0,
  classSweepScheduled = false,
}

local frame
local pumpTicker
local heartbeatTicker
local broadcastScheduled = false

local SEND_RESULT = {
  [0] = "Success", [1] = "InvalidPrefix", [2] = "InvalidMessage",
  [3] = "AddonMessageThrottle", [4] = "InvalidChatType", [5] = "NotInGroup",
  [6] = "TargetRequired", [7] = "InvalidChannel", [8] = "ChannelThrottle",
  [9] = "GeneralError", [10] = "NotInGuild", [11] = "AddOnMessageLockdown",
  [12] = "TargetOffline",
}

local function Now()
  if type(_G.GetTime) == "function" then
    local ok, value = pcall(_G.GetTime)
    if ok and type(value) == "number" then return value end
  end
  if type(_G.time) == "function" then return _G.time() end
  return 0
end

local function After(delay, callback)
  if _G.C_Timer and type(_G.C_Timer.After) == "function" then
    _G.C_Timer.After(delay, callback)
  else
    callback()
  end
end

local function SetSyncState(state, detail)
  Comm.syncState = state or Comm.syncState
  Comm.syncDetail = detail or ""
  local gui = _G.KillOnSight_GUI
  if gui and gui.RefreshCommStatus then
    pcall(function() gui:RefreshCommStatus() end)
  end
end

local function GetChatInfo()
  return _G.C_ChatInfo
end

local function IsInInstanceNow()
  if type(_G.IsInInstance) ~= "function" then return false end
  local ok, inInstance = pcall(_G.IsInInstance)
  return ok and inInstance == true
end

local function IsChatMessagingLocked()
  local chatInfo = GetChatInfo()
  if not chatInfo or type(chatInfo.InChatMessagingLockdown) ~= "function" then return false end
  local ok, locked = pcall(chatInfo.InChatMessagingLockdown)
  return ok and locked == true
end

local function IsInGuildNow()
  if type(_G.IsInGuild) ~= "function" then return nil end
  local ok, value = pcall(_G.IsInGuild)
  if not ok then return nil end
  return value == true
end

local function GetMaster()
  return _G.KillOnSight_Master
end

local function IsMaster()
  local master = GetMaster()
  return master and master.IsMaster and master:IsMaster() == true
end

local function StripRealmSuffix(name)
  if type(name) ~= "string" then return name end
  -- Some roster/client surfaces append -Realm even on Forever's full
  -- First Last identities. Strip that suffix before PlayerKey converts
  -- Forever hyphens to spaces.
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

local function RequestGuildRoster()
  local fn = _G.GuildRoster
  if type(fn) ~= "function" and _G.C_GuildInfo then fn = _G.C_GuildInfo.GuildRoster end
  if type(fn) == "function" then pcall(fn) end
end

-- Returns found, online, rosterDisplayName, apiAvailable.
local function FindGuildMember(identity)
  local countFn, infoFn = _G.GetNumGuildMembers, _G.GetGuildRosterInfo
  if type(countFn) ~= "function" or type(infoFn) ~= "function" then
    return false, false, nil, false
  end
  local okCount, count = pcall(countFn)
  if not okCount or type(count) ~= "number" then return false, false, nil, false end

  for i = 1, count do
    -- GetGuildRosterInfo returns:
    -- name, rankName, rankIndex, level, class, zone, publicNote,
    -- officerNote, isOnline, status, ...
    -- pcall adds one leading success value, so isOnline is result[10].
    local result = { pcall(infoFn, i) }
    local name = result[2]
    local online = result[10]
    if result[1] and type(name) == "string" and name ~= "" and NamesMatch(name, identity) then
      return true, online == true, name, true
    end
  end
  return false, false, nil, true
end

local function NormalizeClassFile(value)
  local discovery = _G.KillOnSight_ClassDiscovery
  if not discovery or type(discovery.NormalizeClassFile) ~= "function" then return nil end
  local ok, classFile = pcall(function() return discovery:NormalizeClassFile(value) end)
  if ok then return classFile end
  return nil
end

local function GetKnownPlayerClass(name)
  local discovery = _G.KillOnSight_ClassDiscovery
  if not discovery or type(discovery.FindKnownPlayerClass) ~= "function" then return nil end
  local ok, classFile = pcall(function() return discovery:FindKnownPlayerClass(name) end)
  if ok then return classFile end
  return nil
end
local function RefreshClassViews()
  local gui = _G.KillOnSight_GUI
  if gui and gui.RefreshAll then pcall(function() gui:RefreshAll() end) end
end

local function ClearClassQuery(query)
  if not query then return end
  Comm.pendingClassQueries[query.id] = nil
  if Comm.classQueryByKey[query.key] == query.id then
    Comm.classQueryByKey[query.key] = nil
  end
end

local function ScheduleClassSweep(delay)
  if Comm.classSweepScheduled then return end
  Comm.classSweepScheduled = true
  After(delay or 3, function()
    Comm.classSweepScheduled = false
    if Comm.initialized and IsMaster() then Comm:QueryMissingPlayerClasses() end
  end)
end

local function GetOnlineGuildMembers()
  local countFn, infoFn = _G.GetNumGuildMembers, _G.GetGuildRosterInfo
  if type(countFn) ~= "function" or type(infoFn) ~= "function" then return {}, false end
  local okCount, count = pcall(countFn)
  if not okCount or type(count) ~= "number" then return {}, false end
  local members, seen = {}, {}
  for i = 1, count do
    -- GetGuildRosterInfo: isOnline is return 9; pcall prepends result[1].
    local result = { pcall(infoFn, i) }
    local name, online = result[2], result[10]
    if result[1] and type(name) == "string" and name ~= "" and online == true
        and not NamesMatch(name, MASTER_NAME) then
      local key = NameKey(name)
      if key and not seen[key] then
        seen[key] = true
        members[#members + 1] = name
      end
    end
  end
  return members, true
end

local function GetDatabaseInfo()
  local db = _G.KillOnSight_DB
  if not db or not db.GetData then return 0, 0, 0 end
  local ok, data = pcall(function() return db:GetData() end)
  if not ok or type(data) ~= "table" then return 0, 0, 0 end
  local players, guilds = 0, 0
  for _ in pairs(data.players or {}) do players = players + 1 end
  for _ in pairs(data.guilds or {}) do guilds = guilds + 1 end
  return tonumber(data.revision) or 0, players, guilds
end

local function RegisterPrefix()
  local chatInfo = GetChatInfo()
  local register = chatInfo and chatInfo.RegisterAddonMessagePrefix or _G.RegisterAddonMessagePrefix
  if type(register) ~= "function" then
    Comm.registered = false
    Comm.registrationResult = "API_MISSING"
    return false
  end
  local ok, result = pcall(register, PREFIX)
  Comm.registrationResult = ok and result or tostring(result)
  local isRegistered = false
  if chatInfo and type(chatInfo.IsAddonMessagePrefixRegistered) == "function" then
    local checkOK, check = pcall(chatInfo.IsAddonMessagePrefixRegistered, PREFIX)
    isRegistered = checkOK and check == true
  end
  Comm.registered = isRegistered or (ok and (result == true or result == 0))
  return Comm.registered
end

local function SendRaw(target, payload)
  if type(payload) ~= "string" or #payload == 0 or #payload > 255 then return false, "InvalidMessage" end
  if type(target) ~= "string" or target == "" then return false, "TargetRequired" end
  if not Comm.registered then return false, "PrefixNotRegistered" end
  if IsInInstanceNow() then return false, "IN_INSTANCE" end
  if IsChatMessagingLocked() then return false, "CHAT_LOCKED" end
  if IsInGuildNow() == false then return false, "NotInGuild" end

  local chatInfo = GetChatInfo()
  local send = chatInfo and chatInfo.SendAddonMessage or _G.SendAddonMessage
  if type(send) ~= "function" then return false, "API_MISSING" end
  -- The Forever/Mainline wrapper can expose the result enum as the final
  -- return value (and some compatibility layers place it after a nil result).
  -- Legacy SendAddonMessage may return no value at all; in that case the
  -- server-side ACK/timeout path is the authoritative delivery check.
  local ok, first, second, third = pcall(send, PREFIX, payload, "WHISPER", target)
  if not ok then return false, tostring(first) end
  local result = third
  if result == nil then result = second end
  if result == nil then result = first end
  if result == 0 or result == true then return true, result end
  if result == nil then return true, "NO_STATUS" end
  if type(result) == "number" then
    return false, SEND_RESULT[result] or ("Result_" .. tostring(result))
  end
  if result == false then return false, "SendFailed" end
  return false, "UnexpectedResult_" .. tostring(result)
end

local EnsurePump

local function QueueRaw(target, payload, onSent, onFail, transfer)
  Comm.sendQueue[#Comm.sendQueue + 1] = {
    target = target, payload = payload, onSent = onSent,
    onFail = onFail, transfer = transfer, attempts = 0, nextAt = 0,
  }
  if EnsurePump then EnsurePump() end
end

local function PopQueueHead()
  Comm.sendQueue[Comm.sendQueueHead] = false
  Comm.sendQueueHead = Comm.sendQueueHead + 1
  if Comm.sendQueueHead > #Comm.sendQueue then
    Comm.sendQueue = {}
    Comm.sendQueueHead = 1
  end
end

function Comm:PumpQueue()
  local item = self.sendQueue[self.sendQueueHead]
  if not item then
    if self.sendQueueHead > 1 then
      self.sendQueue = {}
      self.sendQueueHead = 1
    end
    if pumpTicker then
      if pumpTicker.Cancel then pumpTicker:Cancel() end
      pumpTicker = nil
    end
    return
  end
  if item.transfer and item.transfer.failed then PopQueueHead(); return end
  local now = Now()
  if item.nextAt and now < item.nextAt then return end
  local ok, result = SendRaw(item.target, item.payload)
  if ok then
    PopQueueHead()
    if item.onSent then pcall(item.onSent) end
    return
  end

  item.attempts = item.attempts + 1
  if result == "AddonMessageThrottle" or result == "CHAT_LOCKED" or result == "IN_INSTANCE" or result == "NO_RESULT" then
    item.nextAt = now + (result == "AddonMessageThrottle" and 1.0 or 0.75)
    return
  end

  if item.attempts < 3 and (result == "GeneralError" or result == "API_MISSING") then
    item.nextAt = now + 2.0
    return
  end
  PopQueueHead()
  if item.transfer then
    item.transfer.failed = true
    local key = NameKey(item.target)
    local peer = key and self.peers[key]
    if peer and peer.pending == item.transfer then peer.pending = nil end
  end
  self.lastError = tostring(result)
  SetSyncState("Connection unavailable", tostring(result))
  if item.onFail then pcall(item.onFail, result) end
end

EnsurePump = function()
  if pumpTicker then return end
  if _G.C_Timer and type(_G.C_Timer.NewTicker) == "function" then
    pumpTicker = _G.C_Timer.NewTicker(SEND_INTERVAL, function() Comm:PumpQueue() end)
  end
end

local function EscapeField(value)
  if value == nil then return "" end
  local text = tostring(value)
  -- Encode all non-simple bytes, including UTF-8 bytes, delimiters and controls.
  -- This keeps each wire record ASCII and safe to split into message chunks.
  return (text:gsub("([^%w%-%._ ])", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

local function UnescapeField(value)
  if value == nil or value == "" then return "" end
  return (value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function SplitFields(line)
  local fields, startAt = {}, 1
  while true do
    local at = line:find("~", startAt, true)
    if not at then
      fields[#fields + 1] = UnescapeField(line:sub(startAt))
      break
    end
    fields[#fields + 1] = UnescapeField(line:sub(startAt, at - 1))
    startAt = at + 1
  end
  return fields
end

local function EncodeEntryLine(kind, key, entry, includeClassHint)
  local label = kind == "P" and entry.name or entry.guild
  local classHint = entry.classHint
  if includeClassHint == false then classHint = nil end
  return table.concat({
    kind, EscapeField(key), EscapeField(label), EscapeField(entry.type),
    EscapeField(entry.reason), EscapeField(entry.addedBy),
    EscapeField(entry.addedAt), EscapeField(entry.addedOrder), EscapeField(classHint),
  }, "~")
end

local function SortedKeys(tbl)
  local keys = {}
  for key in pairs(tbl or {}) do keys[#keys + 1] = key end
  table.sort(keys)
  return keys
end

local function BuildSnapshotPayload(snapshot, includeClassHints)
  local lines = {}
  for _, key in ipairs(SortedKeys(snapshot.players)) do
    lines[#lines + 1] = EncodeEntryLine("P", key, snapshot.players[key], includeClassHints)
  end
  for _, key in ipairs(SortedKeys(snapshot.guilds)) do
    lines[#lines + 1] = EncodeEntryLine("G", key, snapshot.guilds[key], includeClassHints)
  end
  return table.concat(lines, "\n")
end

local function BuildDeltaPayload(changes)
  local lines = {}
  for _, change in ipairs(changes or {}) do
    local entry = change.entry
    local nameOrGuild = ""
    local entryType, reason, addedBy, addedAt, addedOrder = "", "", "", "", ""
    if type(entry) == "table" then
      nameOrGuild = change.kind == "P" and entry.name or entry.guild or ""
      entryType = entry.type or ""
      reason = entry.reason or ""
      addedBy = entry.addedBy or ""
      addedAt = entry.addedAt or ""
      addedOrder = entry.addedOrder or ""
    end
    lines[#lines + 1] = table.concat({
      "C", EscapeField(change.rev), EscapeField(change.op), EscapeField(change.kind),
      EscapeField(change.key), EscapeField(nameOrGuild), EscapeField(entryType),
      EscapeField(reason), EscapeField(addedBy), EscapeField(addedAt),
      EscapeField(addedOrder), EscapeField(change.changedAt), EscapeField(change.changedBy),
      EscapeField(change.classHint),
    }, "~")
  end
  return table.concat(lines, "\n")
end

local function Checksum(payload)
  local hash = 5381
  for i = 1, #payload do
    hash = (hash * 33 + string.byte(payload, i)) % 2147483647
  end
  return tostring(hash)
end

local function GetDatabaseDigest()
  local revision = select(1, GetDatabaseInfo())
  if Comm.digestCacheRevision == revision and Comm.digestCacheValue then
    return Comm.digestCacheValue
  end

  local db = _G.KillOnSight_DB
  if not db or not db.GetOfficialSnapshot then return Checksum("") end
  local ok, snapshot = pcall(function() return db:GetOfficialSnapshot() end)
  if not ok or type(snapshot) ~= "table" then return Checksum("") end

  -- The digest represents only authoritative Player/Guild list fields.
  -- classHint is display-only and may differ because each member keeps local
  -- class observations. It is still included in FULL/DELTA payloads.
  local digest = Checksum(BuildSnapshotPayload(snapshot, false))
  Comm.digestCacheRevision = revision
  Comm.digestCacheValue = digest
  return digest
end

function Comm:InvalidateDigest()
  self.digestCacheRevision = nil
  self.digestCacheValue = nil
end

local function PeerBackoffRemaining(peer, now)
  if not peer or not peer.digestBackoffUntil then return 0 end
  local remaining = peer.digestBackoffUntil - (now or Now())
  if remaining > 0 then return remaining end
  peer.digestBackoffUntil = nil
  peer.digestMismatchCount = 0
  peer.digestMismatchDetail = nil
  return 0
end

local function NextTransferId()
  Comm.nextTransferId = Comm.nextTransferId + 1
  local stamp = math.floor(Now() * 1000) % 100000000
  return string.format("%08d%02d", stamp, Comm.nextTransferId % 100)
end

local function ScheduleAckTimeout(target, transfer)
  -- Forever's per-prefix message throttle replenishes slowly. Leave ample
  -- time for queued whispers before retrying a whole transfer.
  local wait = math.max(30, (#transfer.packets * 1.1) + 20)
  After(wait, function()
    local key = NameKey(target)
    local peer = key and Comm.peers[key]
    if not peer or peer.pending ~= transfer or transfer.failed then return end
    if transfer.retries < ACK_RETRY_LIMIT then
      transfer.retries = transfer.retries + 1
      Comm:_QueueTransferPackets(target, transfer)
    else
      peer.pending = nil
      peer.needsSync = true
      SetSyncState("Waiting for member confirmation", target)
    end
  end)
end

function Comm:_QueueTransferPackets(target, transfer)
  if not transfer or transfer.failed then return end
  for index, packet in ipairs(transfer.packets) do
    local isLast = index == #transfer.packets
    QueueRaw(target, packet,
      isLast and function() ScheduleAckTimeout(target, transfer) end or nil,
      nil, transfer)
  end
end

function Comm:StartTransfer(target, transferType, revision, payload, peer)
  if type(payload) ~= "string" or #payload > MAX_TRANSFER_BYTES then
    self.lastError = "TRANSFER_TOO_LARGE"
    SetSyncState("Transfer too large", tostring(#(payload or "")) .. " bytes")
    return false
  end
  local id = NextTransferId()
  local checksum = Checksum(payload)
  local total = math.max(1, math.ceil(#payload / CHUNK_SIZE))
  if total > MAX_TRANSFER_CHUNKS then return false end
  local packets = {}
  for seq = 1, total do
    local startAt = (seq - 1) * CHUNK_SIZE + 1
    local chunk = payload:sub(startAt, startAt + CHUNK_SIZE - 1)
    local packet = string.format("%d|%s|%s|%d|%d|%d|%s|%s", PROTOCOL, transferType, id, revision, seq, total, checksum, chunk)
    if #packet > 255 then
      SetSyncState("Transfer packet too large", tostring(#packet) .. " bytes")
      return false
    end
    packets[#packets + 1] = packet
  end

  local transfer = {
    id = id, kind = transferType, revision = revision,
    checksum = checksum, packets = packets, retries = 0, failed = false,
  }
  peer.pending = transfer
  peer.needsSync = false
  self:_QueueTransferPackets(target, transfer)
  SetSyncState("Syncing", target .. " · " .. tostring(total) .. " packets")
  return true
end

local function MakeEntryFromFields(fields, index, kind, classHintIndex)
  local label = fields[index]
  if type(label) ~= "string" or label == "" then return nil end
  local entry = {
    type = fields[index + 1] ~= "" and fields[index + 1] or nil,
    reason = fields[index + 2] ~= "" and fields[index + 2] or nil,
    addedBy = fields[index + 3] ~= "" and fields[index + 3] or nil,
    addedAt = tonumber(fields[index + 4]),
    addedOrder = tonumber(fields[index + 5]),
  }
  if classHintIndex ~= false then
    local hintIndex = classHintIndex or (index + 6)
    entry.classHint = fields[hintIndex] ~= "" and fields[hintIndex] or nil
  end
  if kind == "P" then entry.name = label else entry.guild = label end
  return entry
end

local function ParseSnapshot(payload)
  local snapshot = { players = {}, guilds = {} }
  if payload == "" then return snapshot end
  for line in (payload .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then
      local fields = SplitFields(line)
      local kind, key = fields[1], fields[2]
      if (kind ~= "P" and kind ~= "G") or type(key) ~= "string" or key == "" then
        return nil, "bad_snapshot_record"
      end
      local entry = MakeEntryFromFields(fields, 3, kind)
      if not entry then return nil, "bad_snapshot_entry" end
      if kind == "P" then snapshot.players[key] = entry else snapshot.guilds[key] = entry end
    end
  end
  return snapshot
end

local function ParseChanges(payload)
  local changes = {}
  if payload == "" then return changes end
  for line in (payload .. "\n"):gmatch("(.-)\n") do
    if line ~= "" then
      local fields = SplitFields(line)
      if fields[1] ~= "C" then return nil, "bad_delta_record" end
      local change = {
        rev = tonumber(fields[2]), op = fields[3], kind = fields[4], key = fields[5],
        changedAt = tonumber(fields[12]), changedBy = fields[13] ~= "" and fields[13] or nil,
        classHint = fields[14] ~= "" and fields[14] or nil,
      }
      if not change.rev or not change.key or change.key == "" then return nil, "bad_delta_fields" end
      if change.op == "upsert" then
        if change.kind ~= "P" and change.kind ~= "G" then return nil, "bad_delta_kind" end
        -- Delta records place changedAt/changedBy before classHint; keep the
        -- hint on the change envelope rather than treating changedAt as an entry field.
        change.entry = MakeEntryFromFields(fields, 6, change.kind, false)
        if not change.entry then return nil, "bad_delta_entry" end
      elseif change.op ~= "delete" or (change.kind ~= "P" and change.kind ~= "G") then
        return nil, "bad_delta_operation"
      end
      changes[#changes + 1] = change
    end
  end
  table.sort(changes, function(a, b) return a.rev < b.rev end)
  return changes
end

function Comm:SendControl(target, payload)
  QueueRaw(target, payload)
end

function Comm:SendHello(force)
  if not self.registered then SetSyncState("Communication unavailable", "Prefix not registered"); return false end
  if IsMaster() then SetSyncState("Master ready", "Waiting for guild members"); return true end
  if IsInGuildNow() ~= true then SetSyncState("Not in guild", "Join the guild to synchronize"); return false end
  if IsInInstanceNow() then return false end
  local now = Now()
  if not force and self.lastHelloAt > 0 and (now - self.lastHelloAt) < HELLO_INTERVAL then return false end

  local found, online, rosterName, apiAvailable = FindGuildMember(MASTER_NAME)
  if not apiAvailable then
    RequestGuildRoster()
    SetSyncState("Waiting for guild roster", "Guild roster API unavailable")
    return false
  end
  if not found then
    RequestGuildRoster()
    SetSyncState("Waiting for master", MASTER_NAME .. " not found in guild roster")
    return false
  end
  if online == false then
    SetSyncState("Waiting for master", MASTER_NAME .. " is offline")
    return false
  end

  if self.helloQueued then return false end
  local revision, players, guilds = GetDatabaseInfo()
  local digest = GetDatabaseDigest()
  local payload = string.format("%d|HELLO|%s|%d|%d|%d|%s", PROTOCOL, VERSION, revision, players, guilds, digest)
  local target = rosterName or MASTER_NAME
  self.helloQueued = true
  QueueRaw(target, payload, function()
    Comm.helloQueued = false
    Comm.lastHelloAt = Now()
    local sentAt = Comm.lastHelloAt
    Comm.awaitingMasterSince = sentAt
    SetSyncState("Waiting for master", "Request sent to " .. target)
    if _G.C_Timer and type(_G.C_Timer.After) == "function" then
      After(HELLO_RESPONSE_TIMEOUT, function()
        if Comm.awaitingMasterSince == sentAt and not IsMaster()
            and Comm.syncState == "Waiting for master" then
          SetSyncState("No compatible master response",
            "Check master protocol v4 and addon-message permissions")
        end
      end)
    end
  end, function()
    Comm.helloQueued = false
  end)
  return true
end

local function SendAck(sender, transfer)
  local digest = GetDatabaseDigest()
  Comm:SendControl(sender, string.format("%d|ACK|%s|%d|%s", PROTOCOL, transfer.id, transfer.revision, digest))
end

local function SendNack(sender, id, revision, reason)
  Comm:SendControl(sender, string.format("%d|NACK|%s|%d|%s", PROTOCOL, id, revision, reason or "invalid"))
end

function Comm:SendLatestToPeer(peerName, peer)
  if not IsMaster() or not peerName or not peer then return false end
  if peer.protocolMismatch then return false end
  local remaining = PeerBackoffRemaining(peer, Now())
  if remaining > 0 then
    peer.needsSync = true
    return false
  end
  local current, playerCount, guildCount = GetDatabaseInfo()
  local currentDigest = GetDatabaseDigest()
  if peer.pending then peer.needsSync = true; return false end

  if peer.revision == current and peer.players == playerCount and peer.guilds == guildCount and peer.digest == currentDigest then
    QueueRaw(peer.target or peerName, string.format("%d|SAME|%d|%d|%d|%s", PROTOCOL, current, playerCount, guildCount, currentDigest))
    peer.lastSentRevision = current
    return true
  end

  local DB = _G.KillOnSight_DB
  if not DB or not DB.GetOfficialChangesSince or not DB.GetOfficialSnapshot then return false end
  if peer.revision <= current then
    local changes = DB:GetOfficialChangesSince(peer.revision)
    if changes ~= nil and #changes > 0 then
      local payload = BuildDeltaPayload(changes)
      return self:StartTransfer(peer.target or peerName, "D", current, payload, peer)
    elseif changes ~= nil and peer.revision == current then
      -- A count mismatch at the same revision means the local lists are incomplete.
    end
  end

  local snapshot = DB:GetOfficialSnapshot()
  return self:StartTransfer(peer.target or peerName, "F", current, BuildSnapshotPayload(snapshot), peer)
end

function Comm:OnOfficialChange(revision)
  if not IsMaster() then return end
  ScheduleClassSweep(1)
  if broadcastScheduled then return end
  broadcastScheduled = true
  After(0.8, function()
    broadcastScheduled = false
    if not IsMaster() then return end
    local now = Now()
    for key, peer in pairs(Comm.peers) do
      if now - (peer.lastHelloAt or 0) > PEER_TTL and not peer.pending then
        Comm.peers[key] = nil
      else
        local found, online, rosterName = FindGuildMember(peer.name or peer.target)
        if found and online ~= false then
          peer.target = rosterName or peer.target
          Comm:SendLatestToPeer(peer.target, peer)
        end
      end
    end
    SetSyncState("Master ready", "Revision " .. tostring(revision or select(1, GetDatabaseInfo())))
  end)
end

local function CountPeers()
  local count = 0
  for _ in pairs(Comm.peers) do count = count + 1 end
  return count
end

function Comm:GetStatusText()
  local revision, players, guilds = GetDatabaseInfo()
  if IsMaster() then
    local peers = CountPeers()
    local versionMismatch, digestPaused = {}, {}
    local now = Now()
    for _, peer in pairs(self.peers) do
      local label = tostring(peer.name or peer.target or "member")
      if peer.protocolMismatch then
        versionMismatch[#versionMismatch + 1] = label .. " (v" .. tostring(peer.protocol or "?") .. ")"
      elseif PeerBackoffRemaining(peer, now) > 0 then
        digestPaused[#digestPaused + 1] = label
      end
    end
    local status = "MASTER · " .. tostring(peers) .. " online peers · rev " .. tostring(revision)
    if #versionMismatch > 0 then
      status = status .. " · Protocol mismatch: " .. table.concat(versionMismatch, ", ")
    elseif #digestPaused > 0 then
      status = status .. " · Sync paused: " .. table.concat(digestPaused, ", ")
    end
    return status
  end
  if self.syncState == "Up to date" then return "Up to date · rev " .. tostring(revision) end
  local detail = type(self.syncDetail) == "string" and self.syncDetail ~= "" and (" · " .. self.syncDetail) or ""
  return tostring(self.syncState) .. detail .. " · rev " .. tostring(revision)
end

function Comm:HandleHello(sender, message)
  if not IsMaster() then return end
  local version, revision, players, guilds, digest = message:match("^%d+|HELLO|([^|]+)|(%d+)|(%d+)|(%d+)|(%d+)$")
  if not version then return end
  local found, _, rosterName, apiAvailable = FindGuildMember(sender)
  if not apiAvailable or not found then return end
  local key = NameKey(sender)
  if not key then return end
  local peer = self.peers[key] or {}
  peer.name = sender
  peer.target = rosterName or sender
  peer.version = version
  peer.protocol = PROTOCOL
  peer.protocolMismatch = nil
  peer.revision = tonumber(revision) or 0
  peer.players = tonumber(players) or 0
  peer.guilds = tonumber(guilds) or 0
  peer.digest = digest
  peer.lastHelloAt = Now()
  peer.pending = peer.pending
  self.peers[key] = peer
  self:SendLatestToPeer(peer.target, peer)
  SetSyncState("Master ready", "" .. CountPeers() .. " active member(s)")
end

function Comm:HandleAck(sender, message)
  if not IsMaster() then return end
  local id, revision, digest = message:match("^%d+|ACK|([^|]+)|(%d+)|(%d+)$")
  if not id then return end
  local found, _, rosterName, apiAvailable = FindGuildMember(sender)
  if not apiAvailable or not found then return end
  local key = NameKey(sender)
  local peer = key and self.peers[key]
  if not peer or not peer.pending or peer.pending.id ~= id then return end
  local acknowledged = tonumber(revision) or 0
  if acknowledged ~= peer.pending.revision then return end
  local _, pc, gc = GetDatabaseInfo()
  local masterDigest = GetDatabaseDigest()
  peer.pending = nil
  if digest ~= masterDigest then
    peer.digestMismatchCount = (tonumber(peer.digestMismatchCount) or 0) + 1
    peer.revision, peer.players, peer.guilds, peer.digest = -1, -1, -1, nil
    peer.needsSync = true
    if peer.digestMismatchCount >= DIGEST_MISMATCH_LIMIT then
      peer.digestBackoffUntil = Now() + DIGEST_MISMATCH_BACKOFF
      peer.digestMismatchDetail = "Repeated official digest mismatch"
      SetSyncState("Digest mismatch backoff",
        tostring(peer.name or sender) .. " · " .. tostring(peer.digestMismatchCount)
          .. " mismatches · retry in " .. tostring(DIGEST_MISMATCH_BACKOFF) .. "s")
      return
    end
    SetSyncState("Digest mismatch; retrying FULL",
      tostring(peer.name or sender) .. " · attempt " .. tostring(peer.digestMismatchCount)
        .. "/" .. tostring(DIGEST_MISMATCH_LIMIT))
    self:SendLatestToPeer(rosterName or peer.target or sender, peer)
    return
  end
  peer.digestMismatchCount = 0
  peer.digestBackoffUntil = nil
  peer.digestMismatchDetail = nil
  peer.revision = acknowledged
  peer.players, peer.guilds, peer.digest = pc, gc, digest
  peer.lastHelloAt = Now()
  peer.target = rosterName or peer.target
  if peer.needsSync or peer.revision < select(1, GetDatabaseInfo()) then
    peer.needsSync = false
    self:SendLatestToPeer(peer.target, peer)
  else
    SetSyncState("Master ready", "" .. CountPeers() .. " active member(s)")
  end
end

function Comm:HandleNack(sender, message)
  if not IsMaster() then return end
  local id, revision = message:match("^%d+|NACK|([^|]+)|(%d+)|[%w_%-]+$")
  if not id then return end
  local key = NameKey(sender)
  local peer = key and self.peers[key]
  if not peer or not peer.pending or peer.pending.id ~= id then return end
  peer.pending.failed = true
  peer.pending = nil
  peer.revision = -1
  peer.players = -1
  peer.guilds = -1
  self:SendLatestToPeer(peer.target or sender, peer)
end

function Comm:OnTransferChunk(sender, message)
  if IsMaster() then return end
  local master = GetMaster()
  if not master or not master.IsMasterIdentity or not master:IsMasterIdentity(sender) then return end
  local rosterFound, _, _, rosterApiAvailable = FindGuildMember(sender)
  if not rosterApiAvailable or not rosterFound then return end
  local kind, id, revision, seq, total, checksum, chunk = message:match("^%d+|([FD])|([^|]+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
  if not kind then return end
  revision, seq, total = tonumber(revision), tonumber(seq), tonumber(total)
  if not revision or not seq or not total or total < 1 or total > MAX_TRANSFER_CHUNKS or seq < 1 or seq > total then return end
  if #chunk > CHUNK_SIZE or #message > 255 then return end

  local completedAt = self.completed[id]
  if completedAt then
    SendAck(sender, { id = id, revision = revision })
    return
  end

  local transfer = self.incoming[id]
  if not transfer then
    transfer = { kind = kind, id = id, revision = revision, total = total, checksum = checksum,
      parts = {}, received = 0, bytes = 0, sender = sender, startedAt = Now(), lastChunkAt = Now() }
    self.incoming[id] = transfer
  elseif transfer.kind ~= kind or transfer.revision ~= revision or transfer.total ~= total
      or transfer.checksum ~= checksum or not NamesMatch(transfer.sender, sender) then
    self.incoming[id] = nil
    SendNack(sender, id, revision, "metadata")
    return
  end

  transfer.lastChunkAt = Now()
  if not transfer.parts[seq] then
    transfer.parts[seq] = chunk
    transfer.received = transfer.received + 1
    transfer.bytes = transfer.bytes + #chunk
  end
  if transfer.bytes > MAX_TRANSFER_BYTES then
    self.incoming[id] = nil
    SendNack(sender, id, revision, "too_large")
    return
  end
  if transfer.received < transfer.total then return end

  local payload = table.concat(transfer.parts)
  self.incoming[id] = nil
  if #payload ~= transfer.bytes or Checksum(payload) ~= transfer.checksum then
    SendNack(sender, id, revision, "checksum")
    return
  end

  local DB = _G.KillOnSight_DB
  local ok, reason
  if kind == "F" then
    local snapshot
    snapshot, reason = ParseSnapshot(payload)
    if snapshot then
      snapshot.revision = revision
      ok, reason = DB and DB.ApplyOfficialSnapshot and DB:ApplyOfficialSnapshot(snapshot, sender)
    end
  else
    local changes
    changes, reason = ParseChanges(payload)
    if changes then
      ok, reason = DB and DB.ApplyOfficialChanges and DB:ApplyOfficialChanges(changes, revision, sender)
    end
  end

  if ok then
    self.completed[id] = Now()
    self.awaitingMasterSince = nil
    SendAck(sender, { id = id, revision = revision })
    SetSyncState("Up to date", "Revision " .. tostring(revision))
  else
    SendNack(sender, id, revision, tostring(reason or "apply" ):gsub("[^%w_%-]", ""):sub(1, 24))
    SetSyncState("Sync failed", tostring(reason or "unknown"))
  end
  if DB and DB.GetData then
    local data = DB:GetData()
    data.syncLastMasterAt = Now()
  end
end

function Comm:HandleProtocolMismatch(sender, remoteProtocol, command, message)
  remoteProtocol = tonumber(remoteProtocol)
  if not remoteProtocol or remoteProtocol == PROTOCOL then return end

  if IsMaster() then
    -- A v3-or-older member can still send HELLO using the shared prefix. Record
    -- it for the Admin status line, but never send a v4 database transfer.
    if command ~= "HELLO" then return end
    local version, revision, players, guilds = message:match("^%d+|HELLO|([^|]+)|(%d+)|(%d+)|(%d+)|%d+$")
    if not version then return end
    local found, _, rosterName, apiAvailable = FindGuildMember(sender)
    if not apiAvailable or not found then return end
    local key = NameKey(sender)
    if not key then return end
    local peer = self.peers[key] or {}
    if peer.pending then peer.pending.failed = true end
    peer.pending = nil
    peer.name = sender
    peer.target = rosterName or sender
    peer.version = version
    peer.protocol = remoteProtocol
    peer.protocolMismatch = true
    peer.revision = tonumber(revision) or 0
    peer.players = tonumber(players) or 0
    peer.guilds = tonumber(guilds) or 0
    peer.lastHelloAt = Now()
    peer.needsSync = true
    self.peers[key] = peer
    SetSyncState("Protocol mismatch", sender .. " uses sync protocol v" .. tostring(remoteProtocol) .. "; v" .. tostring(PROTOCOL) .. " is required")
    return
  end

  local master = GetMaster()
  if master and master.IsMasterIdentity and master:IsMasterIdentity(sender) then
    self.awaitingMasterSince = nil
    SetSyncState("Protocol mismatch",
      "Master uses sync protocol v" .. tostring(remoteProtocol) .. "; update both clients to v" .. tostring(VERSION))
  end
end

function Comm:OnAddonMessage(prefix, message, distribution, sender)
  if prefix ~= PREFIX or type(message) ~= "string" or #message > 255 then return end
  if type(sender) ~= "string" or sender == "" or distribution ~= "WHISPER" then return end
  if IsInInstanceNow() then return end
  local protocol, command = message:match("^(%d+)|([A-Z_]+)|")
  protocol = tonumber(protocol)
  if not protocol or not command then return end
  if protocol ~= PROTOCOL then
    self:HandleProtocolMismatch(sender, protocol, command, message)
    return
  end

  local master = GetMaster()
  if not IsMaster() and master and master.IsMasterIdentity and master:IsMasterIdentity(sender)
      and (command == "SAME" or command == "F" or command == "D") then
    self.awaitingMasterSince = nil
  end

  if command == "HELLO" then
    self:HandleHello(sender, message)
  elseif command == "SAME" then
    local revision, players, guilds, digest = message:match("^%d+|SAME|(%d+)|(%d+)|(%d+)|(%d+)$")
    local master = GetMaster()
    local rosterFound, _, _, rosterApiAvailable = FindGuildMember(sender)
    if revision and not IsMaster() and master and master.IsMasterIdentity
        and master:IsMasterIdentity(sender) and rosterApiAvailable and rosterFound then
      local localRevision, localPlayers, localGuilds = GetDatabaseInfo()
      local localDigest = GetDatabaseDigest()
      if tonumber(revision) == localRevision and tonumber(players) == localPlayers and tonumber(guilds) == localGuilds and digest == localDigest then
        self.awaitingMasterSince = nil
        SetSyncState("Up to date", "Revision " .. tostring(revision))
      else
        SetSyncState("Waiting for master", "Local lists differ; requesting a full sync")
        self.lastHelloAt = 0
        self:SendHello(true)
      end
    end
  elseif command == "F" or command == "D" then
    self:OnTransferChunk(sender, message)
  elseif command == "ACK" then
    self:HandleAck(sender, message)
  elseif command == "NACK" then
    self:HandleNack(sender, message)
  elseif command == "CLASS_QUERY" then
    self:HandleClassQuery(sender, message)
  elseif command == "CLASS_REPLY" then
    self:HandleClassReply(sender, message)
  end
end

-- Master requests class observations only when a Player KoS entry lacks one.
-- Queries use private WHISPER messages and accept only exact-name replies.
function Comm:RequestPlayerClass(name)
  if not self.registered or not IsMaster() or IsInInstanceNow() or IsInGuildNow() ~= true then return false end
  if type(name) ~= "string" or name == "" or #name > 120 then return false end

  local DB = _G.KillOnSight_DB
  local entry = DB and DB.LookupPlayer and DB:LookupPlayer(name)
  if not entry or NormalizeClassFile(entry.class) then return false end

  local localClass = GetKnownPlayerClass(name)
  if localClass then
    if DB.SetPlayerClass and DB:SetPlayerClass(name, localClass) then RefreshClassViews() end
    return false
  end

  local key = NameKey(name)
  if not key or self.classQueryByKey[key] then return false end
  local now = Now()
  local lastQueryAt = self.lastClassQueryAt[key]
  if lastQueryAt and (now - lastQueryAt) < CLASS_QUERY_COOLDOWN then return false end

  local members, apiAvailable = GetOnlineGuildMembers()
  if not apiAvailable then
    RequestGuildRoster()
    return false
  end
  if #members == 0 then return false end

  local id = NextTransferId()
  local query = { id = id, key = key, name = name, startedAt = now, recipients = {} }
  self.pendingClassQueries[id] = query
  self.classQueryByKey[key] = id
  self.lastClassQueryAt[key] = now

  local payload = string.format("%d|CLASS_QUERY|%s|%s", PROTOCOL, id, EscapeField(name))
  local sent = 0
  for _, memberName in ipairs(members) do
    local memberKey = NameKey(memberName)
    if memberKey then
      query.recipients[memberKey] = true
      QueueRaw(memberName, payload)
      sent = sent + 1
    end
  end

  After(CLASS_QUERY_TIMEOUT, function()
    local current = Comm.pendingClassQueries[id]
    if current == query then ClearClassQuery(current) end
  end)
  return sent > 0
end

function Comm:QueryMissingPlayerClasses()
  if not IsMaster() then return 0 end
  local DB = _G.KillOnSight_DB
  local data = DB and DB.GetData and DB:GetData()
  if type(data) ~= "table" or type(data.players) ~= "table" then return 0 end
  local count = 0
  for _, entry in pairs(data.players) do
    if count >= CLASS_QUERY_SWEEP_LIMIT then break end
    if type(entry) == "table" and type(entry.name) == "string" and entry.name ~= ""
        and not NormalizeClassFile(entry.class) then
      if self:RequestPlayerClass(entry.name) then count = count + 1 end
    end
  end
  if count >= CLASS_QUERY_SWEEP_LIMIT then ScheduleClassSweep(3) end
  return count
end

function Comm:HandleClassQuery(sender, message)
  local master = GetMaster()
  if IsMaster() or not master or not master.IsMasterIdentity
      or not master:IsMasterIdentity(sender) then return end
  local found, _, _, apiAvailable = FindGuildMember(sender)
  if not apiAvailable or not found then return end

  local id, encodedName = message:match("^%d+|CLASS_QUERY|([^|]+)|([^|]+)$")
  if not id or not encodedName then return end
  local name = UnescapeField(encodedName)
  if type(name) ~= "string" or name == "" or #name > 120 or not NameKey(name) then return end

  local now = Now()
  local key = NameKey(name)
  local lastReplyAt = self.incomingClassQueryAt[key]
  if lastReplyAt and (now - lastReplyAt) < CLASS_QUERY_REPLY_COOLDOWN then return end
  if not self.incomingClassReplyWindowAt or self.incomingClassReplyWindowAt == 0
      or (now - self.incomingClassReplyWindowAt) >= CLASS_QUERY_REPLY_WINDOW then
    self.incomingClassReplyWindowAt = now
    self.incomingClassReplyCount = 0
  end
  if (self.incomingClassReplyCount or 0) >= CLASS_QUERY_REPLY_WINDOW_MAX then return end

  local classFile = GetKnownPlayerClass(name)
  if not classFile then return end
  self.incomingClassQueryAt[key] = now
  self.incomingClassReplyCount = (self.incomingClassReplyCount or 0) + 1
  self:SendControl(sender, string.format("%d|CLASS_REPLY|%s|%s|%s",
    PROTOCOL, id, EscapeField(name), classFile))
end

function Comm:HandleClassReply(sender, message)
  if not IsMaster() then return end
  local id, encodedName, classFile = message:match("^%d+|CLASS_REPLY|([^|]+)|([^|]+)|([A-Z_]+)$")
  if not id or not encodedName or not NormalizeClassFile(classFile) then return end
  local query = self.pendingClassQueries[id]
  if not query then return end

  local found, _, _, apiAvailable = FindGuildMember(sender)
  if not apiAvailable or not found then return end
  local senderKey = NameKey(sender)
  if not senderKey or not query.recipients or query.recipients[senderKey] ~= true then return end

  local name = UnescapeField(encodedName)
  if type(name) ~= "string" or not NamesMatch(name, query.name) then return end
  if NameKey(name) ~= query.key then return end

  local DB = _G.KillOnSight_DB
  local entry = DB and DB.LookupPlayer and DB:LookupPlayer(query.name)
  if not entry then ClearClassQuery(query); return end
  -- Do not overwrite an already-known class, and never create/replace list rows.
  if not NormalizeClassFile(entry.class) and DB.SetPlayerClass then
    if DB:SetPlayerClass(query.name, classFile) then RefreshClassViews() end
  end
  ClearClassQuery(query)
end

function Comm:TryHello(force)
  return self:SendHello(force)
end

local function ScheduleHello(delay)
  After(delay or 3, function()
    if Comm.initialized and not IsMaster() then Comm:SendHello(false) end
  end)
end

function Comm:Init()
  if self.initialized then return self.registered end
  if not frame then
    frame = _G.CreateFrame("Frame")
    frame:RegisterEvent("CHAT_MSG_ADDON")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("GUILD_ROSTER_UPDATE")
    frame:SetScript("OnEvent", function(_, event, ...)
      if event == "CHAT_MSG_ADDON" then
        Comm:OnAddonMessage(...)
      elseif event == "PLAYER_ENTERING_WORLD" then
        RequestGuildRoster()
        ScheduleHello(8)
      elseif event == "GUILD_ROSTER_UPDATE" then
        ScheduleHello(3)
        if IsMaster() then ScheduleClassSweep(4) end
      end
    end)
  end
  self.initialized = true
  local ok = RegisterPrefix()
  RequestGuildRoster()
  if IsMaster() then
    SetSyncState("Master ready", "Waiting for guild members")
    ScheduleClassSweep(10)
  else
    SetSyncState("Waiting for master", MASTER_NAME)
    ScheduleHello(8)
  end
  if _G.C_Timer and type(_G.C_Timer.NewTicker) == "function" and not heartbeatTicker then
    heartbeatTicker = _G.C_Timer.NewTicker(HELLO_INTERVAL, function()
      local now = Now()
      for id, transfer in pairs(Comm.incoming) do
        if now - (transfer.lastChunkAt or transfer.startedAt or now) > 240 then Comm.incoming[id] = nil end
      end
      for id, completedAt in pairs(Comm.completed) do
        if now - completedAt > 600 then Comm.completed[id] = nil end
      end
      if IsMaster() then
        for key, peer in pairs(Comm.peers) do
          if now - (peer.lastHelloAt or 0) > PEER_TTL and not peer.pending then Comm.peers[key] = nil end
        end
      else
        Comm:SendHello(false)
      end
    end)
  end
  return ok
end

-- Diagnostic slash commands were intentionally removed to avoid macro/chat taint.
-- Sync state is shown in the Options tab; normal synchronization is automatic.

_G.KillOnSight_Comm = Comm
