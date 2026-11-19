-- GUI.lua (Retail / Midnight only)
local ADDON_NAME = ...
local L = KillOnSight_L
local DB = KillOnSight_DB

local GUI = {}
local frame
local commStatusText

local function FormatTime(ts)
  if not ts or ts == 0 then return "-" end
  local d = date("%Y-%m-%d %H:%M", ts)
  return d
end

local function Print(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff00d0ff"..L.ADDON_PREFIX..":|r "..msg)
end

local function CanEditOfficialLists()
  local master = _G.KillOnSight_Master
  return master and master.CanEditOfficialLists and master:CanEditOfficialLists() == true
end


-------------------------------------------------
-- Class Icons
-------------------------------------------------
local CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"

local function _ApplyClassIcon(tex, classFile)
  if not tex then return end
  if not classFile or not CLASS_ICON_TCOORDS or not CLASS_ICON_TCOORDS[classFile] then
    tex:Hide()
    return
  end
  local c = CLASS_ICON_TCOORDS[classFile]
  tex:SetTexture(CLASS_ICON_TEXTURE)
  tex:SetTexCoord(c[1], c[2], c[3], c[4])
  tex:Show()
end

local function CreateBackdrop(f)
  if not f.SetBackdrop and BackdropTemplateMixin then
    Mixin(f, BackdropTemplateMixin)
  end
  if not f.SetBackdrop then return end
  f:SetBackdrop({
    bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
    tile=true, tileSize=32, edgeSize=32,
    insets={left=8,right=8,top=8,bottom=8}
  })
end

local function MakeButton(parent, text, w, h)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetText(text)
  b:SetSize(w or 100, h or 22)
  return b
end

local function MakeEditBox(parent, w)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w or 180, 20)
  e:SetAutoFocus(false)
  e:SetFontObject("ChatFontNormal")
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  return e
end

-------------------------------------------------
-- KoS Notes (reason) column + editor
-------------------------------------------------

local NOTE_ICON_TEX = "Interface\\Buttons\\UI-GuildButton-PublicNote-Up"

local NoteTooltip
local function EnsureNoteTooltip()
  if NoteTooltip then return NoteTooltip end

  local f = CreateFrame("Frame", "KillOnSight_NoteTooltip", UIParent, "BackdropTemplate")
  CreateBackdrop(f)
  f:SetFrameStrata("TOOLTIP")
  f:SetClampedToScreen(true)
  f:SetSize(280, 140)
  f:Hide()

  local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 10, -10)
  sf:SetPoint("BOTTOMRIGHT", -30, 10)

  local child = CreateFrame("Frame", nil, sf)
  child:SetSize(1, 1)
  sf:SetScrollChild(child)

  local text = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", 0, 0)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  text:SetWidth(276)
  text:SetText("")

  f._sf = sf
  f._text = text

  f:SetScript("OnMouseWheel", function(self, delta)
    local cur = self._sf:GetVerticalScroll() or 0
    local max = self._sf:GetVerticalScrollRange() or 0
    local next = cur - (delta * 20)
    if next < 0 then next = 0 end
    if next > max then next = max end
    self._sf:SetVerticalScroll(next)
  end)
  f:EnableMouse(true)
  f:EnableMouseWheel(true)

  NoteTooltip = f
  return f
end

local function ShowNoteTooltip(anchor, noteText)
  local f = EnsureNoteTooltip()
  local txt = (noteText and tostring(noteText) ~= "" and tostring(noteText)) or (L.UI_NOTE_EMPTY or "(No note)")

  f._text:SetText(txt)
  f._text:SetWidth(240)
  local h = f._text:GetStringHeight() or 0
  local maxH = 120
  local height = math.min(maxH, math.max(32, h + 6))
  f:SetSize(280, height + 20)

  f._sf:SetVerticalScroll(0)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", anchor, "BOTTOMRIGHT", 8, 0)
  f:Show()
end

local function HideNoteTooltip()
  if NoteTooltip then NoteTooltip:Hide() end
end

local NoteEditor
local function EnsureNoteEditor()
  if NoteEditor then return NoteEditor end

  local f = CreateFrame("Frame", "KillOnSight_NoteEditor", UIParent, "BackdropTemplate")
  CreateBackdrop(f)
  f:SetFrameStrata("DIALOG")
  f:SetSize(360, 220)
  f:SetPoint("CENTER")
  f:SetClampedToScreen(true)
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText(L.UI_NOTE_EDIT or "Edit Note")
  f._title = title

  local nameFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  nameFS:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  nameFS:SetText("-")
  f._nameFS = nameFS

  local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 14, -58)
  sf:SetPoint("BOTTOMRIGHT", -32, 44)

  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(true)
  eb:SetFontObject("ChatFontNormal")
  eb:SetWidth(280)
  eb:SetText("")
  eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() f:Hide() end)

  sf:SetScrollChild(eb)
  f._sf = sf
  f._eb = eb

  local btnSave = MakeButton(f, L.UI_NOTE_SAVE or "Save", 80, 22)
  btnSave:SetPoint("BOTTOMRIGHT", -14, 14)

  local btnClear = MakeButton(f, L.UI_NOTE_CLEAR or "Clear", 80, 22)
  btnClear:SetPoint("RIGHT", btnSave, "LEFT", -8, 0)

  local btnCancel = MakeButton(f, L.UI_NOTE_CANCEL or "Cancel", 80, 22)
  btnCancel:SetPoint("RIGHT", btnClear, "LEFT", -8, 0)

  btnCancel:SetScript("OnClick", function() f:Hide() end)

  f._btnSave = btnSave
  f._btnClear = btnClear
  f._btnCancel = btnCancel

  NoteEditor = f
  return f
end

local function OpenNoteEditor(playerName)
  local f = EnsureNoteEditor()
  local e = (playerName and DB and DB.LookupPlayer and DB:LookupPlayer(playerName)) or nil
  local cur = (e and e.reason) or ""

  f._playerName = playerName
  f._nameFS:SetText(playerName or "-")
  f._eb:SetText(cur or "")
  f._eb:HighlightText(0)
  f._sf:SetVerticalScroll(0)

  f._btnSave:SetScript("OnClick", function()
    local name = f._playerName
    if not name or name == "" then f:Hide() return end
    local text = f._eb:GetText() or ""
    if DB and DB.SetPlayerReason then
      DB:SetPlayerReason(name, text)
    elseif DB and DB.LookupPlayer then
      local ent = DB:LookupPlayer(name)
      if ent then ent.reason = text end
    end
    if KillOnSight_GUI and KillOnSight_GUI.RefreshAll then KillOnSight_GUI:RefreshAll() end
    f:Hide()
  end)

  f._btnClear:SetScript("OnClick", function()
    local name = f._playerName
    if name and name ~= "" and DB and DB.SetPlayerReason then
      DB:SetPlayerReason(name, nil)
    end
    if KillOnSight_GUI and KillOnSight_GUI.RefreshAll then KillOnSight_GUI:RefreshAll() end
    f:Hide()
  end)

  f:Show()
  f._eb:SetFocus()
end

local function MakeCheck(parent, label)
  local c = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
  c.Text:SetText(label)
  return c
end

local KillOnSight_SliderCounter = 0

local function MakeSlider(parent, label, minV, maxV, step)
  KillOnSight_SliderCounter = KillOnSight_SliderCounter + 1
  local name = ("KillOnSight_OptSlider%d"):format(KillOnSight_SliderCounter)
  local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
  s:SetMinMaxValues(minV, maxV)
  s:SetValueStep(step or 1)
  s:SetObeyStepOnDrag(true)
  s:SetWidth(160)
  _G[s:GetName().."Text"]:SetText(label)
  _G[s:GetName().."Low"]:SetText(tostring(minV))
  _G[s:GetName().."High"]:SetText(tostring(maxV))
  return s
end

local function CreateScrollList(parent, columns)
  -- columns: { {key="name", title="Name", width=160}, ... }
  local container = CreateFrame("Frame", nil, parent)
  container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
  container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)

  local header = CreateFrame("Frame", nil, container)
  header:SetPoint("TOPLEFT", 12, -10)
  header:SetPoint("TOPRIGHT", -32, -10)
  header:SetHeight(18)

  local x = 0
  for _,col in ipairs(columns) do
    local t = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    t:SetPoint("LEFT", x, 0)
    t:SetWidth(col.width)
    t:SetJustifyH("LEFT")
    t:SetText(col.title)
    col._hdr = t
    x = x + col.width
  end

  local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", 8, -30)
  scrollFrame:SetPoint("BOTTOMRIGHT", -28, 10)

  local content = CreateFrame("Frame", nil, scrollFrame)
  content:SetSize(scrollFrame:GetWidth(), 1)
  scrollFrame:SetScrollChild(content)
  scrollFrame:HookScript("OnSizeChanged", function(sf)
    content:SetWidth(sf:GetWidth())
  end)

  -- Virtualized list: only create enough rows for the visible viewport (plus a small buffer)
  -- and reuse them while scrolling. This keeps the Stats tab smooth even with very large datasets.
  local rows = {}
  local rowH = 18

  local function EnsureRows(n)
    for i=#rows+1, n do
      local r = CreateFrame("Button", nil, content)
      r:SetHeight(rowH)
      r:RegisterForClicks("LeftButtonUp")
      r:EnableMouse(true)
      r.bg = r:CreateTexture(nil, "BACKGROUND")
      r.bg:SetAllPoints()
      r.bg:SetColorTexture(1,1,1, i%2==0 and 0.03 or 0.0)
      r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
      local ht = r:GetHighlightTexture()
      ht:SetAllPoints(r)
      ht:SetBlendMode("ADD")

      r.cols = {}
      local xx = 0
      for _,col in ipairs(columns) do
        if col.key == "note" then
          -- Notes column is an icon-only clickable button.
          local b = CreateFrame("Button", nil, r)
          b:SetSize(16, 16)
          b:SetPoint("LEFT", xx + 4, 0)
          b:RegisterForClicks("LeftButtonUp")
          b:EnableMouse(true)

          local tex = b:CreateTexture(nil, "ARTWORK")
          tex:SetAllPoints()
          tex:SetTexture(NOTE_ICON_TEX)
          b._tex = tex

          b:SetScript("OnEnter", function(self)
            ShowNoteTooltip(self, self._noteText)
          end)
          b:SetScript("OnLeave", function()
            HideNoteTooltip()
          end)
          b:SetScript("OnClick", function(self)
            if self._playerName and self._playerName ~= "" then
              OpenNoteEditor(self._playerName)
            end
          end)

          r.noteBtn = b
          -- no fontstring for this column
        else
          local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
          fs:SetPoint("LEFT", xx, 0)
          fs:SetWidth(col.width)
          if col.key == "name" then
          r.classIcon = r:CreateTexture(nil, "ARTWORK")
          r.classIcon:SetSize(14, 14)
          r.classIcon:SetPoint("LEFT", xx + 2, 0)
          r.classIcon:Hide()
          fs:ClearAllPoints()
          fs:SetPoint("LEFT", xx + 18, 0)
          fs:SetWidth(col.width - 18)
          end
          fs:SetJustifyH("LEFT")
          fs:SetText("")
          r.cols[col.key] = fs
        end
        xx = xx + col.width
      end

      r:SetScript("OnClick", function(self)
        container.selectedKey = self._key
        if container._UpdateVisible then container:_UpdateVisible() end
        if container.onSelect then container.onSelect(self._key) end
      end)

      rows[i] = r
    end
  end

  local function VisibleRowCount()
    local h = scrollFrame:GetHeight() or 0
    -- +2 buffer rows prevents flicker when dragging the scrollbar
    return math.max(1, math.ceil(h / rowH) + 2)
  end

  container._UpdateVisible = function(self)
    local items = self.items or {}
    local total = #items
    content:SetHeight(total * rowH)

    local scroll = scrollFrame:GetVerticalScroll() or 0
    local first = math.floor(scroll / rowH) + 1

    for i,row in ipairs(rows) do
      local idx = first + i - 1
      local item = items[idx]
      if item then
        row._key = item._key
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((idx-1) * rowH))
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -((idx-1) * rowH))

        for _,col in ipairs(columns) do
          if col.key == "note" then
            if row.noteBtn then
              row.noteBtn._playerName = item._nameRaw
              row.noteBtn._noteText = item._reason
              local has = (item._reason and tostring(item._reason) ~= "")
              row.noteBtn._tex:SetAlpha(has and 1.0 or 0.3)
            end
          else
            local v = item[col.key]
            if row.cols[col.key] then
              row.cols[col.key]:SetText(v or "")
            end
            if col.key == "name" and row.classIcon then
              _ApplyClassIcon(row.classIcon, item._class)
            end
          end
        end

        -- selection + striping
        if self.selectedKey and self.selectedKey == row._key then
          row.bg:SetColorTexture(1,1,1, 0.12)
        else
          row.bg:SetColorTexture(1,1,1, (idx % 2 == 0) and 0.03 or 0.0)
        end

        row:Show()
      else
        row:Hide()
      end
    end
  end

  container.SetData = function(self, items)
    self.items = items or {}

    -- Ensure we have enough row frames for the current viewport.
    EnsureRows(VisibleRowCount())
    self:_UpdateVisible()
  end

  scrollFrame:SetScript("OnVerticalScroll", function(_, offset)
    if container._UpdateVisible then container:_UpdateVisible() end
  end)

  scrollFrame:HookScript("OnSizeChanged", function()
    -- Resize row pool if the viewport got larger.
    EnsureRows(VisibleRowCount())
    if container._UpdateVisible then container:_UpdateVisible() end
  end)

  return container
end

-- Newest additions first for the managed Player-KoS and Guild-KoS lists.
-- Legacy records without timestamps are placed after dated entries.
local function SortNewestEntries(arr)
  table.sort(arr, function(a, b)
    local av, bv = a.v or a, b.v or b
    local at, bt = tonumber(av.addedAt) or 0, tonumber(bv.addedAt) or 0
    if at ~= bt then return at > bt end
    local ao, bo = tonumber(av.addedOrder) or 0, tonumber(bv.addedOrder) or 0
    if ao ~= bo then return ao > bo end
    local ak, bk = tostring(a.k or a._key or ""), tostring(b.k or b._key or "")
    return ak < bk
  end)
end

local function SortPairs(tbl, keyFunc)
  local arr = {}
  for k,v in pairs(tbl or {}) do
    arr[#arr+1] = {k=k, v=v}
  end
  table.sort(arr, function(a,b) return keyFunc(a.v, a.k) < keyFunc(b.v, b.k) end)
  return arr
end


-------------------------------------------------
-- Class color helpers (GUI)
-- Nearby list already tracks class; we reuse that cache when available.
-------------------------------------------------
local function _ClassColorPrefix(classFile)
  if classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
    local c = RAID_CLASS_COLORS[classFile]
    return ("|cff%02x%02x%02x"):format(c.r*255, c.g*255, c.b*255)
  end
  return nil
end

local function _ColorizeName(name, classFile)
  if not name or name == "" then return "" end
  local p = _ClassColorPrefix(classFile)
  if p then
    return p .. name .. "|r"
  end
  return name
end

local _localizedToClassFile
local function _NormalizeClass(classIn)
  if not classIn or classIn == "" then return nil end
  if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classIn] then
    return classIn
  end
  if not _localizedToClassFile then
    _localizedToClassFile = {}
    if LOCALIZED_CLASS_NAMES_MALE then
      for file, loc in pairs(LOCALIZED_CLASS_NAMES_MALE) do
        _localizedToClassFile[loc] = file
      end
    end
    if LOCALIZED_CLASS_NAMES_FEMALE then
      for file, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE) do
        _localizedToClassFile[loc] = file
      end
    end
  end
  return _localizedToClassFile[classIn]
end

local function _GuessClassFor(name, guid)
  -- 1) Prefer Nearby cache (fast + reliable when recently seen)
  if name and KillOnSight_Nearby and KillOnSight_Nearby.entries then
    local util = _G.KillOnSight_Util
    local key = util and util:PlayerKey(name) or name:lower()
    local e = KillOnSight_Nearby.entries[key]
    if not e then
      for _, candidate in pairs(KillOnSight_Nearby.entries) do
        if type(candidate) == "table" and util and
           (util:SamePlayer(candidate.fullName, name) or util:SamePlayer(candidate.name, name)) then
          e = candidate
          break
        end
      end
    end
    if e and e.class then return _NormalizeClass(e.class) end
  end

  -- 2) Try GUID lookup (works when GUID is known/resolvable)
  if guid and guid ~= "" and GetPlayerInfoByGUID then
    local _, classFile = GetPlayerInfoByGUID(guid)
    classFile = _NormalizeClass(classFile)
    if classFile then return classFile end
  end

  return nil
end

-- WoW Forever stores surnames in the legacy Stats realm/fullName fields.
-- Resolve KoS entries for display only; never rewrite synced keys or saved data.
local function _ForeverDisplayName(name)
  if type(name) ~= "string" then return "" end
  -- Stats fullName uses First-Last, while Forever displays First Last.
  return (_G.KillOnSight_Util and _G.KillOnSight_Util:NormalizePlayerName(name:gsub("%-", " "))) or name
end

local function _StatsForKoS(data, name)
  if type(name) ~= "string" or name == "" then return nil end
  local stats = data and data.statsPlayers
  if type(stats) ~= "table" then return nil end
  local util = _G.KillOnSight_Util
  local lower = (util and util:PlayerKey(name)) or name:lower()
  local first = lower:match("^(%S+)")
  if not first then return nil end

  -- Since the Stats migration, records are keyed by full first + last name,
  -- not by the first name alone. Look up exact matches first.
  local record = stats[lower]
  if type(record) ~= "table" then
    local candidate, count = nil, 0
    for key, entry in pairs(stats) do
      if type(entry) == "table" then
        local full = entry.fullName or entry.name or key
        if type(full) == "string" and full ~= "" and
           type(entry.realm) == "string" and entry.realm ~= "" and
           not full:find("[%s%-]") then
          full = full .. " " .. entry.realm
        end
        local normalized = tostring(full):lower():gsub("%-", " "):gsub("%s+", " ")
        local keyNormalized = tostring(key):lower():gsub("%-", " "):gsub("%s+", " ")
        local exact = normalized == lower or keyNormalized == lower
        local firstOnly = lower == first and
          (normalized:match("^(%S+)") == first or keyNormalized:match("^(%S+)") == first)
        if exact then
          record = entry
          break
        elseif firstOnly then
          count = count + 1
          candidate = entry
        end
      end
    end
    -- Never assign another player's class when surnames are ambiguous.
    if not record and count == 1 then record = candidate end
  end
  if type(record) ~= "table" then return nil end
  local full = record.fullName or record.name or name
  if type(full) ~= "string" or full == "" then full = name end
  if type(record.realm) == "string" and record.realm ~= "" and not full:find("[%s%-]") then
    full = full .. " " .. record.realm
  end
  return record, _ForeverDisplayName(full)
end

local function BuildPlayers()
  local out = {}
  local data = DB:GetData()
  local sorted = SortPairs(data.players, function(v) return (v.name or ""):lower() end)
  SortNewestEntries(sorted)
  for _,it in ipairs(sorted) do
    local e = it.v
    local stats, statsName = _StatsForKoS(data, e.name)
    local classFile = _NormalizeClass(e.class)
      or (stats and _NormalizeClass(stats.classFile or stats.class))
      or _NormalizeClass(_GuessClassFor(e.name, nil))
    -- Expand legacy first-only entries to First Last using the Stats record.
    -- Keep the original KoS name/key for removal, syncing, and persistence.
    local displayName = e.name or ""
    if stats and statsName and statsName ~= "" then
      displayName = statsName
    end
    out[#out+1] = {
      _key = it.k,
      _nameRaw = e.name,
      _class = classFile,
      _reason = e.reason,
      name = _ColorizeName(displayName, classFile),
      type = e.type,
      note = "", -- icon-only column
      lastSeen = FormatTime(e.lastSeenAt),
      zone = e.lastSeenZone or "",
    }
  end
  return out
end

local function BuildGuilds()
  local out = {}
  local data = DB:GetData()
  local sorted = SortPairs(data.guilds, function(v) return (v.guild or ""):lower() end)
  SortNewestEntries(sorted)
  for _,it in ipairs(sorted) do
    local e = it.v
    out[#out+1] = {
      _key = it.k,
      guild = e.guild,
      type = e.type,
      -- reason hidden in UI

      lastSeen = FormatTime(e.lastSeenAt),
      zone = e.lastSeenZone or "",
    }
  end
  return out
end

local function BuildLastAttackers(limit)
  limit = limit or 200
  local items = {}
  local list = DB:GetLastAttackers()
  for i=1, math.min(#list, limit) do
    local e = list[i]
    local rawName = e.name or ""
    local key = rawName:lower()
    local classFile = _NormalizeClass(e.class) or _GuessClassFor(rawName, e.guid)

    local util = _G.KillOnSight_Util
    local isKoS = (rawName ~= "" and DB.HasPlayer and DB:HasPlayer(rawName))
    local isGuild = (e.guild and e.guild ~= "" and DB.HasGuild and DB:HasGuild(e.guild))
    local tag = ""
    if util and util.AppendTags then
      tag = util:AppendTags("", isKoS, isGuild)
    else
      if isKoS then tag = " |cffff0000[KoS]|r" end
      if isGuild then tag = " |cffffd000[Guild]|r" end
    end

    items[#items+1] = {
      _key = key,
      _class = classFile,
      name = _ColorizeName(rawName, classFile) .. tag,
      guild = e.guild or "",
      zone = e.zone or "",
    }
  end
  return items
end

local function BuildLastSeen(limit)
  limit = limit or 200
  local items = {}
  local data = DB:GetData()
  for k,e in pairs(data.players) do
    if e.lastSeenAt then
      items[#items+1] = { kind="P", _key=k, name=e.name, type=e.type, lastSeenAt=e.lastSeenAt, zone=e.lastSeenZone or "", reason=e.reason or "" }
    end
  end
  for k,e in pairs(data.guilds) do
    if e.lastSeenAt then
      items[#items+1] = { kind="G", _key=k, name=e.guild, type=e.type, lastSeenAt=e.lastSeenAt, zone=e.lastSeenZone or "", reason=e.reason or "" }
    end
  end
  table.sort(items, function(a,b) return (a.lastSeenAt or 0) > (b.lastSeenAt or 0) end)
  local out = {}
  for i=1, math.min(#items, limit) do
    local it = items[i]
    out[#out+1] = {
      _key = it.kind..":"..it._key,
      name = it.name,
      type = it.type,
      lastSeen = FormatTime(it.lastSeenAt),
      zone = it.zone,
      -- reason hidden in UI

    }
  end
  return out
end



local function BuildStats(opts)
  if DB.ConsolidateStatsDuplicates then DB:ConsolidateStatsDuplicates() end
  opts = opts or {}
  local q = (opts.query or ""):lower()
  local sortKey = opts.sortKey or "lastSeen"

  local util = _G.KillOnSight_Util
  local out = {}
  local data = DB:GetData()
  local stats = data.statsPlayers or {}
  local kosPlayers = (data and data.players) or {}
  local hasGuild = (DB and DB.HasGuild) and function(g) return DB:HasGuild(g) end or function() return false end

  -- Cache sorted keys per sortKey so we don't re-sort on every keystroke.
  -- Sorting can be the main hitch with 10k+ enemies.
  GUI._statsSortCache = GUI._statsSortCache or { by = {} }
  local rev = (DB.GetStatsRevision and DB:GetStatsRevision()) or (tonumber(data.statsRevision or 0) or 0)
  local cache = GUI._statsSortCache.by[sortKey]

  local function SortCompare(aKey, bKey)
    local a = stats[aKey] or {}
    local b = stats[bKey] or {}
    if sortKey == "name" then
      local av = (a.name or aKey or ""):lower()
      local bv = (b.name or bKey or ""):lower()
      if av == bv then return (aKey or "") < (bKey or "") end
      return av < bv
    elseif sortKey == "seen" then
      local av = tonumber(a.seenCount or 0) or 0
      local bv = tonumber(b.seenCount or 0) or 0
      if av == bv then return (aKey or "") < (bKey or "") end
      return av > bv
    elseif sortKey == "wins" then
      local av = tonumber(a.wins or 0) or 0
      local bv = tonumber(b.wins or 0) or 0
      if av == bv then return (aKey or "") < (bKey or "") end
      return av > bv
    elseif sortKey == "loses" then
      local av = tonumber(a.loses or 0) or 0
      local bv = tonumber(b.loses or 0) or 0
      if av == bv then return (aKey or "") < (bKey or "") end
      return av > bv
    else
      local av = tonumber(a.lastSeenAt or 0) or 0
      local bv = tonumber(b.lastSeenAt or 0) or 0
      if av == bv then return (aKey or "") < (bKey or "") end
      return av > bv
    end
  end

  if (not cache) or cache.rev ~= rev then
    local keys = {}
    for k in pairs(stats) do keys[#keys+1] = k end
    table.sort(keys, SortCompare)
    cache = { rev = rev, keys = keys }
    GUI._statsSortCache.by[sortKey] = cache
  end

  for _,k in ipairs(cache.keys or {}) do
    local e = stats[k]
    if e then
      local name = (e.name) or k
      local displayName = name
      local util = _G.KillOnSight_Util
      if util and util.IsForeverNames and util:IsForeverNames() then
        -- Forever's legacy realm is the surname, but migrated name may
        -- already contain it. Prefer the canonical two-part database key.
        displayName = tostring(k):gsub("%s*%-%s*", " ")
        if not displayName:find(" ", 1, true) then
          local full = e.fullName or name
          full = tostring(full):gsub("%s*%-%s*", " ")
          if not full:find(" ", 1, true) and e.realm and e.realm ~= "" then
            full = full .. " " .. e.realm
          end
          displayName = full
        end
      elseif e.realm and e.realm ~= "" then
        displayName = name .. "-" .. e.realm
      elseif e.fullName and e.fullName:find("-", 1, true) then
        displayName = e.fullName
      end
      local guild = (e.guild) or ""

      local ok = true
      if q and q ~= "" then
        local nl = (name or ""):lower()
        local gl = (guild or ""):lower()
        ok = (nl:find(q, 1, true) ~= nil) or (gl:find(q, 1, true) ~= nil)
      end

      if ok then
        local classFile = _NormalizeClass(e.classFile) or _GuessClassFor(name, nil)
        local isKos = (kosPlayers and kosPlayers[k]) ~= nil
        local isGuild = (guild ~= "") and hasGuild(guild)
        local nameText = _ColorizeName(displayName or name, classFile)
        if util and util.AppendTags then
          nameText = util:AppendTags(nameText, isKos, isGuild)
        else
          if isKos then nameText = nameText .. " |cffff0000[KoS]|r" end
          if isGuild then nameText = nameText .. " |cffffd000[Guild]|r" end
        end

        local seenN = tonumber(e.seenCount or 0) or 0
        -- Some records exist from sightings/metadata refresh before an encounter resolves.
        -- Avoid confusing "0" in the list: if we've seen them at least once, show 1+.
        if seenN == 0 and (tonumber(e.firstSeenAt or 0) or 0) > 0 then
          seenN = 1
        end

        out[#out+1] = {
          _key = k,
          _class = classFile,
          name = nameText,
          guild = guild,
          seen = tostring(seenN),
          lastSeen = FormatTime(e.lastSeenAt or 0),
          wins = tostring(e.wins or 0),
          loses = tostring(e.loses or 0),
        }
      end
    end
  end

  return out
end

local function CreateDropdown(parent, values)
  local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  dd.values = values or {}
  dd.selected = dd.values[1]
  dd.onChanged = nil -- optional callback(v)

  UIDropDownMenu_SetWidth(dd, 90)
  UIDropDownMenu_Initialize(dd, function(self, level)
    local info = UIDropDownMenu_CreateInfo()
    for _,v in ipairs(dd.values) do
      local value = v -- Lua 5.1 closure safety
      info.text = value
      info.func = function()
        dd.selected = value
        UIDropDownMenu_SetText(dd, value)
        if type(dd.onChanged) == "function" then
          dd.onChanged(value)
        end
      end
      info.checked = (dd.selected == value)
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  UIDropDownMenu_SetText(dd, dd.selected or "")
  return dd
end

local MANUAL_CLASS_FILES = {
  "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
  "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local function _ClassDisplayName(classFile)
  return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile])
    or (LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[classFile])
    or classFile
end

local function CreateClassDropdown(parent)
  local dd = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  dd.values = {}
  for _, classFile in ipairs(MANUAL_CLASS_FILES) do
    dd.values[#dd.values + 1] = { value = classFile, text = _ClassDisplayName(classFile) }
  end
  dd.selected = nil
  dd.onChanged = nil
  UIDropDownMenu_SetWidth(dd, 100)
  UIDropDownMenu_Initialize(dd, function(self, level)
    local info = UIDropDownMenu_CreateInfo()
    for _, option in ipairs(dd.values) do
      local choice = option -- Lua 5.1 closure safety
      info.text = choice.text
      info.value = choice.value
      info.func = function()
        dd.selected = choice.value
        UIDropDownMenu_SetText(dd, choice.text)
        if type(dd.onChanged) == "function" then dd.onChanged(choice.value) end
      end
      info.checked = (dd.selected == choice.value)
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  function dd:SetPlayerClass(classFile)
    local normalized = _NormalizeClass(classFile)
    self.selected = normalized
    for _, option in ipairs(self.values) do
      if option.value == normalized then
        UIDropDownMenu_SetText(self, option.text)
        return
      end
    end
    UIDropDownMenu_SetText(self, L.UI_CLASS_UNKNOWN or "Unknown")
  end

  function dd:SetNoPlayer()
    self.selected = nil
    UIDropDownMenu_SetText(self, L.UI_SELECT_PLAYER or "Select player")
  end

  dd:SetNoPlayer()
  return dd
end

local function MakeTab(parent, idx, text)
  local tab = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  tab:SetID(idx)
  tab:SetText(text)
  tab:SetHeight(22)
  tab:SetWidth(math.max(90, (tab:GetFontString() and (tab:GetFontString():GetStringWidth() + 26) or 90)))

  tab.SetSelected = function(self, selected)
    if selected then
      self:Disable()
      local fs = self:GetFontString()
      if fs then fs:SetTextColor(1, 0.82, 0) end -- highlight-ish
      self:SetAlpha(1)
    else
      self:Enable()
      local fs = self:GetFontString()
      if fs then fs:SetTextColor(1, 1, 1) end
      self:SetAlpha(0.9)
    end
  end

  tab:SetScript("OnClick", function(self)
    if parent and parent.tabs then
      for _,t in ipairs(parent.tabs) do
        if t and t.SetSelected then t:SetSelected(t == self) end
      end
    end
    if parent and parent.ShowTab then
      parent:ShowTab(self:GetID())
    end
  end)

  return tab
end

function GUI:Create()

-- Forward references for enabling/disabling the Add button safely
local addBtn
local nameBox

local function UpdateAddState()
  if not addBtn or not nameBox then return end
  if not addBtn.IsEnabled or not addBtn.Disable then return end
  if not CanEditOfficialLists() then
    addBtn:Disable()
    addBtn:SetAlpha(0.35)
    return
  end
  local txt = (nameBox.GetText and nameBox:GetText() or "") or ""
  txt = txt:gsub("^%s+", ""):gsub("%s+$", "")
  local exists = false
  if txt ~= "" then
    exists = ((DB.HasPlayer and DB:HasPlayer(txt)) or (DB.LookupPlayer and DB:LookupPlayer(txt) ~= nil) or false)
  elseif (not (nameBox.HasFocus and nameBox:HasFocus())) and UnitExists("target") and UnitIsPlayer("target") then
    local tName = _G.KillOnSight_Util:UnitPlayerName("target")
    if tName and tName ~= "" then
      exists = ((DB.HasPlayer and DB:HasPlayer(tName)) or (DB.LookupPlayer and DB:LookupPlayer(tName) ~= nil) or false)
    end
  end
  if exists then
    addBtn:Disable()
    addBtn:SetAlpha(0.35)
  else
    addBtn:Enable()
    addBtn:SetAlpha(1)
  end
end

  if frame then return end

  frame = CreateFrame("Frame", "KillOnSight_MainFrame", UIParent, "BackdropTemplate")
  frame:SetSize(640, 440)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  if type(UISpecialFrames) == "table" then
    local frameName = "KillOnSight_MainFrame"
    local registered = false
    for _, specialFrame in ipairs(UISpecialFrames) do
      if specialFrame == frameName then registered = true; break end
    end
    if not registered then UISpecialFrames[#UISpecialFrames + 1] = frameName end
  end
  frame:Hide()
  CreateBackdrop(frame)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  frame.title:SetTextColor(1, 0.82, 0)
  frame.title:SetPoint("TOP", 0, -14)
  frame.title:SetText(L.UI_TITLE)

  -- KoS logo (top-left)
  frame.logo = frame:CreateTexture(nil, "ARTWORK")
  frame.logo:SetSize(64, 64)
  frame.logo:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -12)
  frame.logo:SetTexture("Interface\\AddOns\\KoS-Kanonfode\\logo.tga")
  frame.logo:SetAlpha(0.95)


  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -5, -5)
  -- tabs
  frame.tabs = {}
  frame.tabPanels = {}

  local DEFAULT_W, DEFAULT_H = 640, 440
  local STATS_W, STATS_H = 980, 520
  local OPTIONS_W, OPTIONS_H = math.floor((DEFAULT_W * 1.10) + 0.5), DEFAULT_H

  function frame:LayoutTabs()
    local xPad = 12
    local yRow1 = 7      -- row 1 just under frame
    local yRow2 = -17    -- row 2 below row 1 (if needed)
    local gap = 2
    local row = 1
    local cur = nil

    for _,t in ipairs(self.tabs or {}) do
      -- Skip hidden tabs (e.g., Attackers on Retail)
      if t and t.IsShown and (not t:IsShown()) then
        -- no-op
      else
        t:ClearAllPoints()
	        if not cur then
	          t:SetPoint("TOPLEFT", self, "BOTTOMLEFT", xPad, yRow1)
          cur = t
        else
	          t:SetPoint("LEFT", cur, "RIGHT", gap, 0)

        local right = (t:GetRight() or 0)
        local frameRight = (self:GetRight() or 0)

        if frameRight > 0 and right > 0 and right > (frameRight - 10) and row == 1 then
          t:ClearAllPoints()
	          t:SetPoint("TOPLEFT", self, "BOTTOMLEFT", xPad, yRow2)
          row = 2
        end

          cur = t
        end
      end
    end
  end

  frame.ShowTab = function(self, id)
    -- Retail: Attackers tab is intentionally hidden/disabled.
    if id == 3 then
      id = 4
    end
    -- Resize for certain tabs so they have room to breathe.
    if id == 4 then
      if not self._wasSize then
        self._wasSize = { self:GetWidth(), self:GetHeight() }
      end
      self:SetSize(STATS_W, STATS_H)
    elseif id == 5 then
      if not self._wasSize then
        self._wasSize = { self:GetWidth(), self:GetHeight() }
      end
      self:SetSize(OPTIONS_W, OPTIONS_H)
    else
      -- restore to default (or previous saved size)
      if self._wasSize then
        self:SetSize(self._wasSize[1] or DEFAULT_W, self._wasSize[2] or DEFAULT_H)
      else
        self:SetSize(DEFAULT_W, DEFAULT_H)
      end
    end

    -- Use dedicated localized titles for certain tabs (so the main addon title isn't reused everywhere).
    if self.title then
      if id == 4 and L and L.UI_STATS_TITLE then
        self.title:SetText(L.UI_STATS_TITLE)
      elseif id == 3 and L and L.UI_ATTACKERS_TITLE then
        self.title:SetText(L.UI_ATTACKERS_TITLE)
      elseif id == 5 and L and L.UI_OPTIONS_TITLE then
        self.title:SetText(L.UI_OPTIONS_TITLE)
      elseif L and L.UI_TITLE then
        self.title:SetText(L.UI_TITLE)
      end
    end

    -- Hide logo on Options tab only
    if self.logo and self.logo.SetShown then
      self.logo:SetShown(id ~= 5)
    elseif self.logo then
      if id == 5 then self.logo:Hide() else self.logo:Show() end
    end

  if self.LayoutTabs then self:LayoutTabs() end

    for i=1,#self.tabPanels do
      local p = self.tabPanels[i]
      if p then p:Hide() end
    end
    if self.tabPanels[id] then
      self.tabPanels[id]:Show()
    end
    self._activeTab = id
    if self._refreshActivePanel and self:IsShown() then
      self._refreshActivePanel()
    end
  end

  local t1 = MakeTab(frame, 1, L.UI_TAB_PLAYERS)
  local t2 = MakeTab(frame, 2, L.UI_TAB_GUILDS)
  local t3 = MakeTab(frame, 3, L.UI_TAB_ATTACKERS)
  local t4 = MakeTab(frame, 4, (L.UI_TAB_STATS or "Stats"))
  local t5 = MakeTab(frame, 5, L.UI_OPTIONS)

  if t3 then
    t3:Hide()
  end

  -- Tab layout: place tabs BELOW the frame (so they don't overlap the window content)
  local tabs = {t1, t2, t3, t4, t5}
  frame.tabs = tabs
  frame:LayoutTabs()

local pPlayers = CreateFrame("Frame", nil, frame)
  pPlayers:SetAllPoints(frame)
  pPlayers:SetPoint("TOPLEFT", 12, -42)
  pPlayers:SetPoint("BOTTOMRIGHT", -12, 12)
  frame.tabPanels[1] = pPlayers
  local remBtn = MakeButton(pPlayers, L.UI_REMOVE, 80, 22)
  remBtn:SetPoint("TOPRIGHT", pPlayers, "TOPRIGHT", -10, -10)
  local playerEditor = CanEditOfficialLists()
  if not playerEditor then
    -- Members get a clean browse-only list: no disabled search/add/remove bar
    -- and no edit box that can visually overlap the read-only message.
    remBtn:Hide()
    local readOnly = pPlayers:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    readOnly:SetPoint("TOPLEFT", pPlayers, "TOPLEFT", 12, -16)
    readOnly:SetText("OFFICIAL PLAYER KoS LIST  ·  Managed by Calámir Dawnsinger")
    readOnly:SetTextColor(1, 0.82, 0.35)
  end

  addBtn = MakeButton(pPlayers, L.UI_ADD, 80, 22)
  addBtn:SetPoint("RIGHT", remBtn, "LEFT", -6, 0)

  local nameLabel = pPlayers:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  nameLabel:SetTextColor(1, 0.82, 0)
  nameLabel:SetText(L.UI_NAME)
  nameLabel:SetPoint("TOPLEFT", pPlayers, "TOPLEFT", 90, -14)

  nameBox = MakeEditBox(pPlayers, 120)
  nameBox:SetPoint("TOPLEFT", pPlayers, "TOPLEFT", 135, -10)
  nameBox:SetWidth(120) -- fixed width so it does not overlap the logo
  nameBox:SetText("")
  if not playerEditor then
    addBtn:Hide()
    nameLabel:Hide()
    nameBox:Hide()
  end

  local classLabel = pPlayers:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  classLabel:SetTextColor(1, 0.82, 0)
  classLabel:SetText(L.UI_CLASS or "Class")
  classLabel:SetPoint("TOPLEFT", pPlayers, "TOPLEFT", 90, -44)

  local classDropdown = CreateClassDropdown(pPlayers)
  classDropdown:SetPoint("TOPLEFT", pPlayers, "TOPLEFT", 126, -35)
  if not playerEditor then
    classLabel:Hide()
    classDropdown:Hide()
  end

  local setClassBtn = MakeButton(pPlayers, L.UI_SET_CLASS or "Set class", 82, 22)
  setClassBtn:SetPoint("LEFT", classDropdown, "RIGHT", -6, 4)
  if not playerEditor then setClassBtn:Hide() end

  local function UpdateManualClassState()
    local key = pPlayers._selected or (pPlayers._list and pPlayers._list.selectedKey)
    local entry = key and DB:GetData().players[key]
    if entry then
      classDropdown:SetPlayerClass(entry.class or _GuessClassFor(entry.name, nil))
      if playerEditor then setClassBtn:Enable(); setClassBtn:SetAlpha(1) end
    else
      classDropdown:SetNoPlayer()
      if playerEditor then setClassBtn:Disable(); setClassBtn:SetAlpha(0.35) end
    end
  end

  -- Keep the Add button state in sync with manual input and target changes.
  -- Without these hooks, adding one player while that player remains targeted
  -- can leave Add disabled even after the user types a different player name.
  nameBox:HookScript("OnTextChanged", function()
    local key = pPlayers._selected or (pPlayers._list and pPlayers._list.selectedKey)
    local entry = key and DB:GetData().players[key]
    if entry and (nameBox:GetText() or "") ~= (entry.name or "") then
      pPlayers._selected = nil
      if pPlayers._list then
        pPlayers._list.selectedKey = nil
        if pPlayers._list._UpdateVisible then pPlayers._list:_UpdateVisible() end
      end
    end
    UpdateAddState()
    UpdateManualClassState()
  end)
  nameBox:HookScript("OnEditFocusGained", function()
    UpdateAddState()
  end)
  nameBox:HookScript("OnEditFocusLost", function()
    UpdateAddState()
  end)

  local targetState = CreateFrame("Frame", nil, pPlayers)
  targetState:RegisterEvent("PLAYER_TARGET_CHANGED")
  targetState:SetScript("OnEvent", function()
    UpdateAddState()
  end)
  -- Initialise the button based on current input/target.
  UpdateAddState()
  -- no reason box in UI

  local list = CreateScrollList(pPlayers, {
    {key="name", title=L.UI_NAME, width=170},
    {key="type", title=L.UI_TYPE, width=70},
    {key="lastSeen", title=L.UI_LAST_SEEN, width=130},
    {key="zone", title=L.UI_ZONE, width=150},
    -- Notes column placed after Zone (far right)
    {key="note", title=(L.UI_NOTES or "Notes"), width=60},
  })
  list:SetPoint("TOPLEFT", 0, -70)
  list:SetPoint("BOTTOMRIGHT", 0, 0)

  pPlayers._list = list
  pPlayers._selected = nil
  list.onSelect = function(k)
    pPlayers._selected = k
    if playerEditor then
      local e = DB:GetData().players[k]
      if e and e.name then nameBox:SetText(e.name) end
    end
    UpdateManualClassState()
  end
  UpdateManualClassState()

  setClassBtn:SetScript("OnClick", function()
    local key = pPlayers._selected or (pPlayers._list and pPlayers._list.selectedKey)
    local entry = key and DB:GetData().players[key]
    if not entry then UpdateManualClassState(); return end
    if classDropdown.selected then
      if DB.SetPlayerClass then DB:SetPlayerClass(entry.name, classDropdown.selected) end
    end
    GUI:RefreshAll()
    UpdateManualClassState()
  end)

  addBtn:SetScript("OnClick", function()
    local name = (nameBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local classFile
  local targetName = (UnitExists("target") and UnitIsPlayer("target")) and (_G.KillOnSight_Util:UnitPlayerName("target")) or nil
  local targetClass = (targetName and select(2, UnitClass("target"))) or nil

  -- If we are targeting the same player we're adding (or name is blank), prefer the target's class.
  if targetName and targetClass then
    if name == "" then
      classFile = targetClass
    else
      local n1 = name:lower()
      local n2 = targetName:lower()
      if n1 == n2 then
        classFile = targetClass
      end
    end
  end

  -- Otherwise, fall back to any cached/guessed class
  if not classFile then
    classFile = _GuessClassFor(name ~= "" and name or (targetName or ""), nil)
  end
    if name == "" then
      -- If nothing typed, add current target (player only)
      if UnitExists("target") and UnitIsPlayer("target") then
        local tName = _G.KillOnSight_Util:UnitPlayerName("target")
        if tName and tName ~= "" then
          name = tName
          nameBox:SetText(name)
        end
      end
    end
    if name == "" then return end
    if ((DB.HasPlayer and DB:HasPlayer(name)) or (DB.LookupPlayer and DB:LookupPlayer(name) ~= nil) or false) then UpdateAddState(); return end
    DB:AddPlayer(name, L.KOS, nil, ((_G.KillOnSight_Util and _G.KillOnSight_Util:UnitPlayerName("player")) or UnitName("player")), classFile)
    nameBox:SetText("")
    GUI:RefreshAll()
    UpdateAddState()
  end)

  remBtn:SetScript("OnClick", function()
    local key = pPlayers._selected or (pPlayers._list and pPlayers._list.selectedKey)
    local typed = nameBox:GetText()
    if key then
      local entry = DB:GetData().players[key]
      if entry then DB:RemovePlayer(entry.name) end
    elseif typed and typed ~= "" then
      DB:RemovePlayer(typed)
    end
    pPlayers._selected = nil
    if pPlayers._list then pPlayers._list.selectedKey = nil end
    nameBox:SetText("")
    GUI:RefreshAll()
    UpdateAddState()
  end)

  -- guilds panel
  local pGuilds = CreateFrame("Frame", nil, frame)
  pGuilds:SetAllPoints(frame)
  pGuilds:SetPoint("TOPLEFT", 12, -42)
  pGuilds:SetPoint("BOTTOMRIGHT", -12, 12)
  pGuilds:Hide()
  frame.tabPanels[2] = pGuilds
  local gRemBtn = MakeButton(pGuilds, L.UI_REMOVE, 80, 22)
  gRemBtn:SetPoint("TOPRIGHT", pGuilds, "TOPRIGHT", -10, -10)

  local gAddBtn = MakeButton(pGuilds, L.UI_ADD, 80, 22)
  gAddBtn:SetPoint("RIGHT", gRemBtn, "LEFT", -6, 0)
  local guildEditor = CanEditOfficialLists()
  if not guildEditor then
    gAddBtn:Hide()
    gRemBtn:Hide()
    local readOnly = pGuilds:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    readOnly:SetPoint("TOPLEFT", pGuilds, "TOPLEFT", 12, -16)
    readOnly:SetText("OFFICIAL GUILD KoS LIST  ·  Managed by Calámir Dawnsinger")
    readOnly:SetTextColor(1, 0.82, 0.35)
  end

  local guildLabel = pGuilds:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  guildLabel:SetTextColor(1, 0.82, 0)
  guildLabel:SetText(L.UI_GUILD)
  guildLabel:SetPoint("TOPLEFT", pGuilds, "TOPLEFT", 90, -14)

  local guildBox = MakeEditBox(pGuilds, 150)
  guildBox:SetPoint("TOPLEFT", pGuilds, "TOPLEFT", 145, -10)
  guildBox:SetWidth(150) -- fixed width so it does not overlap the logo
  if not guildEditor then
    guildLabel:Hide()
    guildBox:Hide()
  end
  -- no reason box in UI

  local gList = CreateScrollList(pGuilds, {
    {key="guild", title=L.UI_GUILD, width=220},
    {key="type", title=L.UI_TYPE, width=90},
        {key="lastSeen", title=L.UI_LAST_SEEN, width=130},
    {key="zone", title=L.UI_ZONE, width=150},
  })
  gList:SetPoint("TOPLEFT", 0, -42)
  gList:SetPoint("BOTTOMRIGHT", 0, 0)
  pGuilds._list = gList
  pGuilds._selected = nil
  gList.onSelect = function(k)
    pGuilds._selected = k
    if guildEditor then
      local e = DB:GetData().guilds[k]
      if e and e.guild then guildBox:SetText(e.guild) end
    end
  end

  gAddBtn:SetScript("OnClick", function()
    DB:AddGuild(guildBox:GetText(), L.GUILD_KOS, nil, ((_G.KillOnSight_Util and _G.KillOnSight_Util:UnitPlayerName("player")) or UnitName("player")))
    guildBox:SetText("")
    GUI:RefreshAll()
  end)

  gRemBtn:SetScript("OnClick", function()
    local key = pGuilds._selected or (pGuilds._list and pGuilds._list.selectedKey)
    local typed = guildBox:GetText()
    if key then
      local entry = DB:GetData().guilds[key]
      if entry then DB:RemoveGuild(entry.guild) end
    elseif typed and typed ~= "" then
      DB:RemoveGuild(typed)
    end
    pGuilds._selected = nil
    if pGuilds._list then pGuilds._list.selectedKey = nil end
    guildBox:SetText("")
    GUI:RefreshAll()
  end)

  -- last seen panel
  local pSeen = CreateFrame("Frame", nil, frame)
  pSeen:SetAllPoints(frame)
  pSeen:SetPoint("TOPLEFT", 12, -42)
  pSeen:SetPoint("BOTTOMRIGHT", -12, 12)
  pSeen:Hide()
    local seenList = CreateScrollList(pSeen, {
    {key="name", title=L.UI_NAME, width=220},
    {key="type", title=L.UI_TYPE, width=90},
    {key="lastSeen", title=L.UI_LAST_SEEN, width=150},
    {key="zone", title=L.UI_ZONE, width=160},
      })
  seenList:SetPoint("TOPLEFT", 0, -10)
  seenList:SetPoint("BOTTOMRIGHT", 0, 0)
  pSeen._list = seenList

  -- last attackers panel
  local pAtk = CreateFrame("Frame", nil, frame)
  pAtk:SetAllPoints(frame)
  pAtk:SetPoint("TOPLEFT", 12, -42)
  pAtk:SetPoint("BOTTOMRIGHT", -12, 12)
  pAtk:Hide()
  frame.tabPanels[3] = pAtk
  local atkList = CreateScrollList(pAtk, {
    {key="name", title=L.UI_NAME, width=260},
    {key="guild", title=L.UI_GUILD, width=170},
    {key="zone", title=L.UI_ZONE, width=220},
  })
  -- Top action bar (keeps buttons accessible even when the list is long)
  local atkBar = CreateFrame("Frame", nil, pAtk)
  atkBar:SetPoint("TOPLEFT", 0, 0)
  atkBar:SetPoint("TOPRIGHT", 0, 0)
  atkBar:SetHeight(28)

  -- List sits below the bar
  atkList:SetPoint("TOPLEFT", 0, -34)
  atkList:SetPoint("BOTTOMRIGHT", 0, 0)
  pAtk._list = atkList

  local btnClearAtk = MakeButton(atkBar, L.UI_CLEAR, 80, 22)
  btnClearAtk:SetPoint("TOPRIGHT", -10, -3)
  btnClearAtk:SetScript("OnClick", function()
    DB:ClearLastAttackers()
    GUI:RefreshAll()
  end)

  local btnAddAtk = MakeButton(atkBar, L.UI_ADD_KOS, 90, 22)
  btnAddAtk:SetPoint("RIGHT", btnClearAtk, "LEFT", -6, 0)

  local btnAddGuildAtk = MakeButton(atkBar, (L.UI_ADD_GUILD or "Add Guild"), 90, 22)
  btnAddGuildAtk:SetPoint("RIGHT", btnAddAtk, "LEFT", -6, 0)

  local function SetBtnEnabled(b, enabled)
    if not b then return end
    if enabled then
      if b.Enable then b:Enable() end
      if b.SetEnabled then b:SetEnabled(true) end
      b:SetAlpha(1.0)
    else
      if b.Disable then b:Disable() end
      if b.SetEnabled then b:SetEnabled(false) end
      b:SetAlpha(0.45)
    end
  end

  local function GetSelectedAttacker()
    local key = atkList.selectedKey
    if not key or key == "" then return nil end
    local list = DB:GetLastAttackers()
    for _,e in ipairs(list) do
      if e.name and e.name:lower() == key then
        return e
      end
    end
    return nil
  end

  local function UpdateAtkButtons()
    local e = GetSelectedAttacker()
    if not CanEditOfficialLists() then
      SetBtnEnabled(btnAddAtk, false)
      SetBtnEnabled(btnAddGuildAtk, false)
      return
    end
    if not e or not e.name or e.name == "" then
      SetBtnEnabled(btnAddAtk, false)
      SetBtnEnabled(btnAddGuildAtk, false)
      return
    end

    -- Add KoS button
    local canAddKoS = true
    if DB.HasPlayer and DB:HasPlayer(e.name) then
      canAddKoS = false
    end
    SetBtnEnabled(btnAddAtk, canAddKoS)

    -- Add Guild button
    local canAddGuild = true
    if not e.guild or e.guild == "" then
      canAddGuild = false
    elseif DB.HasGuild and DB:HasGuild(e.guild) then
      canAddGuild = false
    end
    SetBtnEnabled(btnAddGuildAtk, canAddGuild)
  end
  btnAddAtk:SetScript("OnClick", function()
    local e = GetSelectedAttacker()
    if not e or not e.name or e.name == "" then return end
    if DB:HasPlayer(e.name) then
      UpdateAtkButtons()
      return
    end
    DB:AddPlayer(e.name, L.KOS, nil, ((_G.KillOnSight_Util and _G.KillOnSight_Util:UnitPlayerName("player")) or UnitName("player")), _NormalizeClass(e.class) or _GuessClassFor(e.name, e.guid))
    GUI:RefreshAll()
    UpdateAtkButtons()
  end)

  btnAddGuildAtk:SetScript("OnClick", function()
    local e = GetSelectedAttacker()
    local guild = e and e.guild
    if not guild or guild == "" then
      UpdateAtkButtons()
      return
    end
    if DB:HasGuild(guild) then
      UpdateAtkButtons()
      return
    end
    DB:AddGuild(guild, L.GUILD_KOS, nil, ((_G.KillOnSight_Util and _G.KillOnSight_Util:UnitPlayerName("player")) or UnitName("player")))
    GUI:RefreshAll()
    UpdateAtkButtons()
  end)

  atkList.onSelect = function()
    UpdateAtkButtons()
  end

  -- Expose update so RefreshAll can keep buttons in sync
  pAtk._UpdateButtons = UpdateAtkButtons
  UpdateAtkButtons()

  -- stats panel
  local pStats = CreateFrame("Frame", nil, frame)
  pStats:SetAllPoints(frame)
  pStats:SetPoint("TOPLEFT", 12, -42)
  pStats:SetPoint("BOTTOMRIGHT", -12, 12)
  pStats:Hide()
  frame.tabPanels[4] = pStats

  -- confirm popup (created once)
  if not StaticPopupDialogs["KOS_RESET_STATS"] then
    StaticPopupDialogs["KOS_RESET_STATS"] = {
      text = (L.UI_STATS_RESET_CONFIRM or "Reset enemy statistics?"),
      button1 = YES,
      button2 = NO,
      OnAccept = function()
        if DB and DB.ClearStatsPlayers then DB:ClearStatsPlayers() end
        if DB and DB.ClearLastAttackers then DB:ClearLastAttackers() end
        local Stats = _G.KillOnSight_MidnightStats
        if Stats and Stats.OnResetStats then
          pcall(Stats.OnResetStats, Stats)
        end
        if GUI and GUI.RefreshAll then GUI:RefreshAll() end
      end,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      preferredIndex = 3,
    }
  end

  local sBar = CreateFrame("Frame", nil, pStats)
  sBar:SetPoint("TOPLEFT", 0, 0)
  sBar:SetPoint("TOPRIGHT", 0, 0)
  sBar:SetHeight(28)

  local sSearch = MakeEditBox(sBar, 180)
  sSearch:SetPoint("TOPRIGHT", -10, -4)
  sSearch:SetText("")

  local sortDD = CreateDropdown(sBar, { (L.UI_STATS_SORT_LASTSEEN or "Last Seen"), (L.UI_STATS_SORT_NAME or "Name"), (L.UI_STATS_SORT_SEEN or "Seen"), (L.UI_STATS_SORT_WINS or "Wins"), (L.UI_STATS_SORT_LOSES or "Losses") })
  sortDD:SetPoint("RIGHT", sSearch, "LEFT", -12, -2)

  local btnReset = MakeButton(sBar, (L.UI_STATS_RESET or "Reset"), 70, 22)
  btnReset:SetPoint("RIGHT", sortDD, "LEFT", -8, 0)
  btnReset:SetScript("OnClick", function()
    StaticPopup_Show("KOS_RESET_STATS")
  end)

  local sList = CreateScrollList(pStats, {
    {key="name", title=L.UI_NAME, width=220},
    {key="guild", title=L.UI_GUILD, width=170},
    {key="seen", title=(L.UI_STATS_SEEN or "Seen"), width=60},
    {key="lastSeen", title=L.UI_LAST_SEEN, width=150},
    {key="wins", title=(L.UI_STATS_WINS or "W"), width=40},
    {key="loses", title=(L.UI_STATS_LOSES or "L"), width=40},
  })
  sList:SetPoint("TOPLEFT", 0, -34)
  sList:SetPoint("BOTTOMLEFT", 0, 0)
  sList:SetPoint("RIGHT", pStats, "RIGHT", -220, 0)
  pStats._list = sList

  local dPane = CreateFrame("Frame", nil, pStats, "BackdropTemplate")
  dPane:SetPoint("TOPRIGHT", -8, -34)
  dPane:SetPoint("BOTTOMRIGHT", -8, 8)
  dPane:SetWidth(210)
  CreateBackdrop(dPane)

  local dName = dPane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  dName:SetPoint("TOPLEFT", 12, -12)
  dName:SetText("-")

  local dInfo = {}
  local function AddInfoLine(i, label)
    local fs = dPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 12, -12 - (i*16))
    fs:SetJustifyH("LEFT")
    fs:SetText(label .. ": -")
    dInfo[i] = fs
    return fs
  end

  local lClass = AddInfoLine(1, (L.UI_CLASS or "Class"))
  local lGuild = AddInfoLine(2, L.UI_GUILD)
  local lFaction = AddInfoLine(3, (L.UI_FACTION or "Faction"))
  
  local lFirst = AddInfoLine(4, (L.UI_STATS_FIRSTSEEN or "First seen"))
  local lLast  = AddInfoLine(5, L.UI_LAST_SEEN)
  local lSeen  = AddInfoLine(6, (L.UI_STATS_SEEN or "Seen"))
  local lW     = AddInfoLine(7, (L.UI_STATS_WINS or "Wins"))
  local lL     = AddInfoLine(8, (L.UI_STATS_LOSES or "Losses"))

  local btnAdd = MakeButton(dPane, (L.UI_ADD_KOS or "Add KoS"), 170, 22)
  btnAdd:SetPoint("BOTTOM", dPane, "BOTTOM", 0, 44)

  local btnRem = MakeButton(dPane, (L.UI_REMOVE_KOS or "Remove KoS"), 170, 22)
  btnRem:SetPoint("BOTTOM", dPane, "BOTTOM", 0, 18)

  local btnGuildKos = MakeButton(dPane, (L.UI_ADD_GUILD_KOS), 170, 22)
  btnGuildKos:SetPoint("BOTTOM", dPane, "BOTTOM", 0, 70)

  -- Forward-declared so the Add/Remove buttons can force a list refresh.
  local RefreshStatsList

  local function RefreshDetail(keyLower)
    local data = DB:GetData()
    local e = (data.statsPlayers or {})[keyLower]
    if not e then
      dName:SetText("-")
      lClass:SetText((L.UI_CLASS or "Class") .. ": -")
      lGuild:SetText(L.UI_GUILD .. ": -")
      if lFaction then lFaction:SetText((L.UI_FACTION or "Faction") .. ": -") end
      lFirst:SetText((L.UI_STATS_FIRSTSEEN or "First seen") .. ": -")
      lLast:SetText(L.UI_LAST_SEEN .. ": -")
      lSeen:SetText((L.UI_STATS_SEEN or "Seen") .. ": -")
      lW:SetText((L.UI_STATS_WINS or "Wins") .. ": -")
      lL:SetText((L.UI_STATS_LOSES or "Losses") .. ": -")
      btnAdd:Disable()
      btnRem:Disable()
      btnGuildKos:Disable()
      return
    end

    local name = e.name or keyLower
    local classFile = _NormalizeClass(e.classFile) or _GuessClassFor(name, nil)
    dName:SetText(_ColorizeName(name, classFile))
    local classLabel = "-"
    if classFile and classFile ~= "" then
      classLabel = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile])
        or (LOCALIZED_CLASS_NAMES_FEMALE and LOCALIZED_CLASS_NAMES_FEMALE[classFile])
        or classFile
    end
    lClass:SetText((L.UI_CLASS or "Class") .. ": " .. classLabel)
    lGuild:SetText(L.UI_GUILD .. ": " .. ((e.guild and e.guild ~= "") and e.guild or "-"))

local factionLabel = "-"
    local fg = e.faction
    if fg and fg ~= "" then
      local aName = _G.FACTION_ALLIANCE or "Alliance"
      local hName = _G.FACTION_HORDE or "Horde"
      if fg == "Alliance" then
        factionLabel = "|cff3f7fff" .. aName .. "|r"
      elseif fg == "Horde" then
        factionLabel = "|cffff3333" .. hName .. "|r"
      else
        factionLabel = fg
      end
    end
    if lFaction then
      lFaction:SetText((L.UI_FACTION or "Faction") .. ": " .. factionLabel)
    end
    lFirst:SetText((L.UI_STATS_FIRSTSEEN or "First seen") .. ": " .. FormatTime(e.firstSeenAt))
    lLast:SetText(L.UI_LAST_SEEN .. ": " .. FormatTime(e.lastSeenAt))
    local seenN = tonumber(e.seenCount or 0) or 0
    if seenN == 0 and (tonumber(e.firstSeenAt or 0) or 0) > 0 then
      seenN = 1
    end
    lSeen:SetText((L.UI_STATS_SEEN or "Seen") .. ": " .. tostring(seenN))
    lW:SetText((L.UI_STATS_WINS or "Wins") .. ": " .. tostring(e.wins or 0))
    lL:SetText((L.UI_STATS_LOSES or "Losses") .. ": " .. tostring(e.loses or 0))

    local has = (DB.HasPlayer and DB:HasPlayer(name))
    if not CanEditOfficialLists() then
      if btnAdd.Disable then btnAdd:Disable() end
      if btnRem.Disable then btnRem:Disable() end
    elseif has then
      if btnAdd.Disable then btnAdd:Disable() end
      if btnRem.Enable then btnRem:Enable() end
    else
      if btnAdd.Enable then btnAdd:Enable() end
      if btnRem.Disable then btnRem:Disable() end
    end

    local guildName = (type(e.guild) == "string" and e.guild:match("^%s*(.-)%s*$")) or ""
    if CanEditOfficialLists() and guildName ~= "" and DB.HasGuild and not DB:HasGuild(guildName) then
      btnGuildKos:Enable()
    else
      btnGuildKos:Disable()
    end

    btnGuildKos:SetScript("OnClick", function()
      if guildName == "" or not DB.AddGuild or (DB.HasGuild and DB:HasGuild(guildName)) then return end
      DB:AddGuild(guildName, L.GUILD_KOS, nil, ((_G.KillOnSight_Util and _G.KillOnSight_Util:UnitPlayerName("player")) or UnitName("player")))
      if GUI and GUI.RefreshAll then GUI:RefreshAll() end
      if RefreshStatsList then RefreshStatsList() end
      RefreshDetail(keyLower)
    end)

    btnAdd:SetScript("OnClick", function()
      if name and name ~= "" and DB.AddPlayer and not DB:HasPlayer(name) then
        DB:AddPlayer(name, L.KOS, nil, ((_G.KillOnSight_Util and _G.KillOnSight_Util:UnitPlayerName("player")) or UnitName("player")), classFile)
        if GUI and GUI.RefreshAll then GUI:RefreshAll() end
        if RefreshStatsList then RefreshStatsList() end
        RefreshDetail(keyLower)
      end
    end)

    btnRem:SetScript("OnClick", function()
      if name and name ~= "" and DB.RemovePlayer and DB:HasPlayer(name) then
        DB:RemovePlayer(name)
        if GUI and GUI.RefreshAll then GUI:RefreshAll() end
        if RefreshStatsList then RefreshStatsList() end
        RefreshDetail(keyLower)
      end
    end)
  end

  sList.onSelect = function(k)
    pStats._selected = k
    RefreshDetail(k)
  end

  local function SortKeyFromDD()
    local t = sortDD.selected or "Last Seen"
    if t == (L.UI_STATS_SORT_NAME or "Name") then return "name" end
    if t == (L.UI_STATS_SORT_SEEN or "Seen") then return "seen" end
    if t == (L.UI_STATS_SORT_WINS or "Wins") then return "wins" end
    if t == (L.UI_STATS_SORT_LOSES or "Losses") then return "loses" end
    return "lastSeen"
  end

  RefreshStatsList = function()
    pStats._list:SetData(BuildStats({
      query = sSearch:GetText() or "",
      kosOnly = false,
      pvpOnly = false,
      sortKey = SortKeyFromDD(),
    }))
    if pStats._selected then RefreshDetail(pStats._selected) end
  end

  -- Debounce search so we don't rebuild/filter on every keystroke.
  -- (Sorting is cached above, but filtering + rebuilding rows can still be expensive for large datasets.)
  pStats._searchSeq = 0
  sSearch:SetScript("OnTextChanged", function()
    pStats._searchSeq = (pStats._searchSeq or 0) + 1
    local seq = pStats._searchSeq
    if C_Timer and C_Timer.After then
      C_Timer.After(0.15, function()
        if pStats and pStats:IsShown() and pStats._searchSeq == seq then
          RefreshStatsList()
        end
      end)
    else
      RefreshStatsList()
    end
  end)

  sortDD.onChanged = function() RefreshStatsList() end

  pStats._Refresh = RefreshStatsList

  -- options panel
  local pOpt = CreateFrame("Frame", nil, frame)
  pOpt:SetAllPoints(frame)
  pOpt:SetPoint("TOPLEFT", 12, -42)
  pOpt:SetPoint("BOTTOMRIGHT", -12, 12)
  pOpt:Hide()
  frame.tabPanels[5] = pOpt

  -- Make the Options tab scrollable so additional settings never overlap or run off-screen.
  -- NOTE: parent MUST be the Options panel (pOpt). If the parent is nil or a wrong variable,
  -- widgets will appear at the screen's top-left (UIParent).
  local optScroll = CreateFrame("ScrollFrame", nil, pOpt, "UIPanelScrollFrameTemplate")
  frame._optScroll = optScroll
  optScroll:SetPoint("TOPLEFT", pOpt, "TOPLEFT", 0, 0)
  optScroll:SetPoint("BOTTOMRIGHT", pOpt, "BOTTOMRIGHT", -28, 0) -- leave room for the scrollbar

  local opt = CreateFrame("Frame", nil, optScroll)
  optScroll.Child = opt
  opt._kosWidgets = {}
  local function _W(k,v) opt._kosWidgets[k]=v end
  -- Size dynamically based on the actual options content so the scrollbar never overshoots into blank space.
  -- (We still set a sane initial size; it will be recalculated on show/resize.)
  opt:SetSize(optScroll:GetWidth() or 700, optScroll:GetHeight() or 1)
  optScroll:SetScrollChild(opt)

  local function _UpdateOptionsScrollSizing()
    if not optScroll or not opt then return end
    -- Ensure the scroll child is as wide as the visible viewport (minus a tiny gutter).
    local vw = (optScroll:GetWidth() or 0)
    if vw > 0 and opt.SetWidth then
      opt:SetWidth(vw)
    end

    -- Measure the lowest bottom across children/regions and fit the scroll child to it.
    local top = opt:GetTop() or optScroll:GetTop()
    local minBottom = nil

    for _,child in ipairs({ opt:GetChildren() }) do
      local b = child and child.GetBottom and child:GetBottom() or nil
      if b and (not minBottom or b < minBottom) then
        minBottom = b
      end
    end

    for _,region in ipairs({ opt:GetRegions() }) do
      local b = region and region.GetBottom and region:GetBottom() or nil
      if b and (not minBottom or b < minBottom) then
        minBottom = b
      end
    end

    if top and minBottom then
      local pad = 40
      local h = math.max(1, (top - minBottom) + pad)
      local viewH = optScroll:GetHeight() or 0
      if viewH > 0 and h < viewH then h = viewH end
      opt:SetHeight(h)

      -- Clamp scroll offset so you can never scroll past the last option into blank space.
      local maxScroll = math.max(0, h - (viewH or 0))
      local cur = optScroll:GetVerticalScroll() or 0
      if cur > maxScroll then
        optScroll:SetVerticalScroll(maxScroll)
      end

      local sb = optScroll.ScrollBar
      if sb and sb.SetShown then
        sb:SetShown(h > (viewH + 1))
      end
    end
  end

  optScroll:HookScript("OnShow", function()
    if C_Timer and C_Timer.After then
      C_Timer.After(0, _UpdateOptionsScrollSizing)
    else
      _UpdateOptionsScrollSizing()
    end
  end)
  optScroll:HookScript("OnSizeChanged", function()
    if C_Timer and C_Timer.After then
      C_Timer.After(0, _UpdateOptionsScrollSizing)
    else
      _UpdateOptionsScrollSizing()
    end
  end)

  -- Every Options control writes directly to one persistent account-wide settings table.
  local function CurrentSettings()
    local _DB = GetDB and GetDB() or DB
    if _DB and _DB.GetSettings then
      return _DB:GetSettings()
    end
    return {}
  end

  local settings = CurrentSettings()

  -- Alerts (KoS / Guild)
  local tAlerts = opt:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  tAlerts:SetPoint("TOPLEFT", opt, "TOPLEFT", 20, -20)
  tAlerts:SetText(L.UI_ALERTS or "KoS / Guild")

  local tVersion = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  tVersion:SetPoint("TOPRIGHT", opt, "TOPRIGHT", -30, -25)
  tVersion:SetJustifyH("RIGHT")
  local versionInfo = _G.KillOnSight_Version
  local version = versionInfo and type(versionInfo.GetInstalledVersion) == "function"
    and versionInfo.GetInstalledVersion(ADDON_NAME)
  if not version or version == "" then
    version = versionInfo and versionInfo.CURRENT or "0.4.18"
  end
  tVersion:SetText((L.UI_VERSION or "Version") .. ": v" .. tostring(version))

  local cSound = MakeCheck(opt, L.UI_SOUND)
  _W("cSound", cSound)
  cSound:SetPoint("TOPLEFT", tAlerts, "BOTTOMLEFT", 0, -10)
  cSound:SetChecked(settings.enableSound)

  local cFlash = MakeCheck(opt, L.UI_FLASH)
  _W("cFlash", cFlash)
  cFlash:SetPoint("TOPLEFT", cSound, "BOTTOMLEFT", 0, -8)
  cFlash:SetChecked(settings.enableScreenFlash)

  local cTargetingAlert = MakeCheck(opt, L.UI_TARGETING_ALERT or "Alert when an enemy targets you")
  _W("cTargetingAlert", cTargetingAlert)
  cTargetingAlert:SetPoint("TOPLEFT", cFlash, "BOTTOMLEFT", 0, -8)
  cTargetingAlert:SetChecked(settings.targetingAlertEnabled ~= false)
  cTargetingAlert:SetScript("OnClick", function(self)
    CurrentSettings().targetingAlertEnabled = self:GetChecked()
  end)


  -- Nearby
  local tNearby = opt:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  tNearby:SetPoint("TOPLEFT", cTargetingAlert, "BOTTOMLEFT", 0, -18)
  tNearby:SetText(L.UI_NEARBY_HEADING or "Nearby")

  -- Nearby window options
  local cNearby = MakeCheck(opt, L.UI_NEARBY_FRAME)
  _W("cNearby", cNearby)
  cNearby:SetPoint("TOPLEFT", tNearby, "BOTTOMLEFT", 0, -10)
  cNearby:SetChecked(settings.showNearbyFrame ~= false)
  cNearby:SetScript("OnClick", function(self)
    local settings = CurrentSettings()
    settings.showNearbyFrame = self:GetChecked()
    if KillOnSight_Nearby and KillOnSight_Nearby.SetShown then
      KillOnSight_Nearby:SetShown((CurrentSettings().showNearbyFrame ~= false))
    end
  end)

-- Separate toggle for the Spy-style "detected nearby" sound.
local cNearbySound = MakeCheck(opt, L.UI_NEARBY_SOUND)
_W("cNearbySound", cNearbySound)
cNearbySound:SetPoint("TOPLEFT", cNearby, "BOTTOMLEFT", 0, -6)
cNearbySound:SetChecked(settings.nearbySound ~= false)
cNearbySound:SetScript("OnClick", function(self)
  local settings = CurrentSettings()
  settings.nearbySound = self:GetChecked()
end)

-- Alert scope affects only the extra arrival sound for non-KoS enemies.
-- Every enemy is still detected, recorded and shown in Nearby in both modes.
local alertModeAllLabel = L.UI_ALERT_MODE_ALL or "All Enemies"
local alertModeKosLabel = L.UI_ALERT_MODE_KOS or "KoS List Only"
local alertModeLabel = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
alertModeLabel:SetPoint("TOPLEFT", cNearbySound, "BOTTOMLEFT", 16, -12)
alertModeLabel:SetText(L.UI_NEARBY_ALERT_MODE or "Nearby alert scope")

local ddNearbyAlertMode = CreateDropdown(opt, { alertModeAllLabel, alertModeKosLabel })
_W("ddNearbyAlertMode", ddNearbyAlertMode)
UIDropDownMenu_SetWidth(ddNearbyAlertMode, 145)
ddNearbyAlertMode:SetPoint("TOPLEFT", alertModeLabel, "BOTTOMLEFT", -16, -2)
local function GetNearbyAlertModeLabel(mode)
  return mode == "kos" and alertModeKosLabel or alertModeAllLabel
end
settings.nearbyAlertMode = (settings.nearbyAlertMode == "kos") and "kos" or "all"
ddNearbyAlertMode.selected = GetNearbyAlertModeLabel(settings.nearbyAlertMode)
UIDropDownMenu_SetText(ddNearbyAlertMode, ddNearbyAlertMode.selected)
ddNearbyAlertMode.onChanged = function(selectedLabel)
  local settings = CurrentSettings()
  settings.nearbyAlertMode = (selectedLabel == alertModeKosLabel) and "kos" or "all"
end

-- Nearby distance controls the maximum distance for ordinary Nearby entries
-- and their arrival sound. High-confidence detections retain the existing 1.5x range.
local nearbyRangeLabel = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
_W("nearbyRangeLabel", nearbyRangeLabel)
nearbyRangeLabel:SetPoint("TOPLEFT", ddNearbyAlertMode, "BOTTOMLEFT", 16, -12)
nearbyRangeLabel:SetText(L.UI_NEARBY_RANGE or "Nearby list/alert range (yards)")

local nearbyRangeValue = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
_W("nearbyRangeValue", nearbyRangeValue)
nearbyRangeValue:SetPoint("LEFT", nearbyRangeLabel, "RIGHT", 8, 0)

local sNearbyRange = CreateFrame("Slider", "KillOnSightNearbyRangeSlider", opt, "OptionsSliderTemplate")
_W("sNearbyRange", sNearbyRange)
sNearbyRange:SetWidth(240)
sNearbyRange:SetPoint("TOPLEFT", nearbyRangeLabel, "BOTTOMLEFT", 0, -6)
sNearbyRange:SetMinMaxValues(60, 200)
sNearbyRange:SetValueStep(10)
sNearbyRange:SetObeyStepOnDrag(true)
_G[sNearbyRange:GetName().."Low"]:SetText("60")
_G[sNearbyRange:GetName().."High"]:SetText("200")
_G[sNearbyRange:GetName().."Text"]:SetText("")

do
  local settings = CurrentSettings()
  if type(settings.nearbyMaxYards) ~= "number" then settings.nearbyMaxYards = 100 end
  settings.nearbyMaxYards = math.floor((settings.nearbyMaxYards / 10) + 0.5) * 10
  if settings.nearbyMaxYards < 60 then settings.nearbyMaxYards = 60 end
  if settings.nearbyMaxYards > 200 then settings.nearbyMaxYards = 200 end
  sNearbyRange:SetValue(settings.nearbyMaxYards)
  nearbyRangeValue:SetText(tostring(settings.nearbyMaxYards) .. " yd")
end

sNearbyRange:SetScript("OnValueChanged", function(self, val)
  if opt._kosSync then return end
  val = math.floor((val / 10) + 0.5) * 10
  if val < 60 then val = 60 end
  if val > 200 then val = 200 end
  local settings = CurrentSettings()
  settings.nearbyMaxYards = val
  nearbyRangeValue:SetText(tostring(val) .. " yd")
  _G[self:GetName().."Text"]:SetText("")
end)

local cNearbyLock = MakeCheck(opt, L.UI_NEARBY_LOCK)
cNearbyLock:SetPoint("TOPLEFT", sNearbyRange, "BOTTOMLEFT", 16, -12)
cNearbyLock:SetChecked(settings.nearbyFrameLocked == true)
cNearbyLock:SetScript("OnClick", function(self)
  local settings = CurrentSettings()
  settings.nearbyFrameLocked = self:GetChecked()
  if KillOnSight_Nearby and KillOnSight_Nearby.ApplyLocked then
    KillOnSight_Nearby:ApplyLocked()
  end
end)


local cAutoHide = MakeCheck(opt, L.UI_NEARBY_AUTOHIDE)
cAutoHide:SetPoint("TOPLEFT", cNearbyLock, "BOTTOMLEFT", 0, -10)
cAutoHide:SetChecked(settings.nearbyAutoHide ~= false)
cAutoHide:SetScript("OnClick", function(self)
  local settings = CurrentSettings()
  settings.nearbyAutoHide = self:GetChecked()
  if KillOnSight_Nearby and KillOnSight_Nearby.Refresh then
    KillOnSight_Nearby:Refresh()
  end
end)

local anchorBelowAutoHide = cAutoHide
local anchorOffset = -10


-- Nearby window scale
local scaleLabel = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
scaleLabel:SetPoint("TOPLEFT", anchorBelowAutoHide, "BOTTOMLEFT", 0, anchorOffset)
scaleLabel:SetText(L.UI_NEARBY_SCALE)

local scaleValue = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
scaleValue:SetPoint("LEFT", scaleLabel, "RIGHT", 8, 0)

local sNearbyScale = CreateFrame("Slider", "KillOnSightNearbyScaleSlider", opt, "OptionsSliderTemplate")
  _W("sNearbyScale", sNearbyScale)
  _W("scaleValue", scaleValue)

sNearbyScale:SetWidth(240)
sNearbyScale:SetPoint("TOPLEFT", scaleLabel, "BOTTOMLEFT", 0, -6)
sNearbyScale:SetMinMaxValues(0.60, 1.60)
sNearbyScale:SetValueStep(0.05)
sNearbyScale:SetObeyStepOnDrag(true)
_G[sNearbyScale:GetName().."Low"]:SetText("0.6")
_G[sNearbyScale:GetName().."High"]:SetText("1.6")
_G[sNearbyScale:GetName().."Text"]:SetText("")

do
  local settings = CurrentSettings()
  settings.nearbyFrame = settings.nearbyFrame or {}
  if type(settings.nearbyFrame.scale) ~= "number" then settings.nearbyFrame.scale = 1.0 end
  sNearbyScale:SetValue(settings.nearbyFrame.scale)
  scaleValue:SetText(string.format("(%.2f)", settings.nearbyFrame.scale))
end

sNearbyScale:SetScript("OnValueChanged", function(self, val)
  if opt._kosSync then return end
  val = math.floor((val * 100) + 0.5) / 100
  local settings = CurrentSettings()
  settings.nearbyFrame = settings.nearbyFrame or {}
  settings.nearbyFrame.scale = val

  if KillOnSight_Nearby and KillOnSight_Nearby.ApplyPosition then
    KillOnSight_Nearby:ApplyPosition()
  elseif KillOnSight_Nearby and KillOnSight_Nearby.frame and KillOnSight_Nearby.frame.SetScale then
    KillOnSight_Nearby.frame:SetScale(val)
  end

  scaleValue:SetText(string.format("(%.2f)", val))
end)

-- Nearby background
local bgLabel = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
bgLabel:SetPoint("TOPLEFT", sNearbyScale, "BOTTOMLEFT", 0, -18)
bgLabel:SetText(L.UI_NEARBY_BACKGROUND)

local bgValue = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
bgValue:SetPoint("LEFT", bgLabel, "RIGHT", 8, 0)

local sNearbyBG = CreateFrame("Slider", "KillOnSightNearbyBGAlphaSlider", opt, "OptionsSliderTemplate")
  _W("sNearbyBG", sNearbyBG)
  _W("bgValue", bgValue)

sNearbyBG:SetWidth(240)
sNearbyBG:SetPoint("TOPLEFT", bgLabel, "BOTTOMLEFT", 0, -6)
sNearbyBG:SetMinMaxValues(0.00, 1.00)
sNearbyBG:SetValueStep(0.05)
sNearbyBG:SetObeyStepOnDrag(true)
_G[sNearbyBG:GetName().."Low"]:SetText("0")
_G[sNearbyBG:GetName().."High"]:SetText("100")
_G[sNearbyBG:GetName().."Text"]:SetText("")

do
  local settings = CurrentSettings()
  settings.nearbyFrame = settings.nearbyFrame or {}
  if type(settings.nearbyFrame.bgAlpha) ~= "number" then
    if type(settings.nearbyAlpha) == "number" then
      settings.nearbyFrame.bgAlpha = settings.nearbyAlpha
    else
      settings.nearbyFrame.bgAlpha = 0.80
    end
  end
  sNearbyBG:SetValue(settings.nearbyFrame.bgAlpha)
  bgValue:SetText(string.format("(%d%%)", math.floor((settings.nearbyFrame.bgAlpha*100)+0.5)))
end

sNearbyBG:SetScript("OnValueChanged", function(self, val)
  if opt._kosSync then return end
  val = math.floor((val * 100) + 0.5) / 100
  local settings = CurrentSettings()
  settings.nearbyFrame = settings.nearbyFrame or {}
  settings.nearbyFrame.bgAlpha = val
	  -- Keep legacy key in sync for older code paths, but do NOT use frame alpha for this.
	  settings.nearbyAlpha = val

	  if KillOnSight_Nearby then
	    if KillOnSight_Nearby.ApplyBackdrop then KillOnSight_Nearby:ApplyBackdrop() end
	    -- Minimal mode owns the backdrop in that state.
	    if KillOnSight_Nearby.ApplyMinimalMode then KillOnSight_Nearby:ApplyMinimalMode() end
	  end

  bgValue:SetText(string.format("(%d%%)", math.floor((val*100)+0.5)))
end)



-- Nearby name font
local fontLabel = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
fontLabel:SetPoint("TOPLEFT", sNearbyBG, "BOTTOMLEFT", 0, -18)
fontLabel:SetText(L.UI_NEARBY_NAME_FONT or "Nearby name font")

local fontChoices
if KillOnSight_Nearby and KillOnSight_Nearby.GetNameFontChoices then
  fontChoices = KillOnSight_Nearby:GetNameFontChoices()
end
if type(fontChoices) ~= "table" or #fontChoices == 0 then
  fontChoices = { "Default", "Morpheus", "Skurri" }
end
local ddNearbyFont = CreateDropdown(opt, fontChoices)
  _W("ddNearbyFont", ddNearbyFont)

UIDropDownMenu_SetWidth(ddNearbyFont, 140)
ddNearbyFont:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -16, -2)

-- Initialize from settings
local _pFont = CurrentSettings()
_pFont.nearbyNameFont = _pFont.nearbyNameFont or "Default"
-- If the saved font is no longer offered (filtered out), fall back to Default.
do
  local ok = false
  for _, v in ipairs(fontChoices) do
    if v == _pFont.nearbyNameFont then ok = true break end
  end
  if not ok then _pFont.nearbyNameFont = "Default" end
end
ddNearbyFont.selected = _pFont.nearbyNameFont
UIDropDownMenu_SetText(ddNearbyFont, ddNearbyFont.selected)
ddNearbyFont.onChanged = function(v)
  local settings = CurrentSettings()
  settings.nearbyNameFont = v or "Default"
  if KillOnSight_Nearby and KillOnSight_Nearby.ApplyNameFont then
    KillOnSight_Nearby:ApplyNameFont()
  end
end

hooksecurefunc("UIDropDownMenu_SetText", function(dd, txt)
  if dd ~= ddNearbyFont then return end
  local settings = CurrentSettings()
  settings.nearbyNameFont = ddNearbyFont.selected or "Default"
  if KillOnSight_Nearby and KillOnSight_Nearby.ApplyNameFont then
    KillOnSight_Nearby:ApplyNameFont()
  end
end)


-- Nearby name font size
local sizeLabel = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
sizeLabel:SetPoint("TOPLEFT", ddNearbyFont, "BOTTOMLEFT", 16, -14)
sizeLabel:SetText(L.UI_NEARBY_NAME_SIZE or "Nearby name size")

local sizeValue = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
sizeValue:SetPoint("LEFT", sizeLabel, "RIGHT", 8, 0)

local sNearbyNameSize = CreateFrame("Slider", "KillOnSightNearbyNameSizeSlider", opt, "OptionsSliderTemplate")
  _W("sNearbyNameSize", sNearbyNameSize)
  _W("sizeValue", sizeValue)

sNearbyNameSize:SetPoint("TOPLEFT", sizeLabel, "BOTTOMLEFT", 0, -6)
sNearbyNameSize:SetMinMaxValues(8, 20)
sNearbyNameSize:SetValueStep(1)
sNearbyNameSize:SetObeyStepOnDrag(true)
_G[sNearbyNameSize:GetName().."Low"]:SetText("8")
_G[sNearbyNameSize:GetName().."High"]:SetText("20")

do
  local settings = CurrentSettings()
  if type(settings.nearbyNameFontSize) ~= "number" then settings.nearbyNameFontSize = 12 end
  sNearbyNameSize:SetValue(settings.nearbyNameFontSize)
  sizeValue:SetText(tostring(settings.nearbyNameFontSize))
end
_G[sNearbyNameSize:GetName().."Text"]:SetText("")

sNearbyNameSize:SetScript("OnValueChanged", function(self, val)
  if opt._kosSync then return end
  val = math.floor(val + 0.5)
  local settings = CurrentSettings()
  settings.nearbyNameFontSize = val
  sizeValue:SetText(tostring(val))
  _G[self:GetName().."Text"]:SetText("")
  if KillOnSight_Nearby and KillOnSight_Nearby.ApplyNameFont then
    KillOnSight_Nearby:ApplyNameFont()
  end
end)


-- Nearby max visible rows (before scrolling)
local maxRowsLabel = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
maxRowsLabel:SetPoint("TOPLEFT", sNearbyNameSize, "BOTTOMLEFT", 0, -18)
maxRowsLabel:SetText(L.UI_NEARBY_MAX_ROWS or "Nearby max rows")

local maxRowsValue = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
maxRowsValue:SetPoint("LEFT", maxRowsLabel, "RIGHT", 8, 0)

local sNearbyMaxRows = CreateFrame("Slider", "KillOnSightNearbyMaxRowsSlider", opt, "OptionsSliderTemplate")
  _W("sNearbyMaxRows", sNearbyMaxRows)
  _W("maxRowsValue", maxRowsValue)

sNearbyMaxRows:SetPoint("TOPLEFT", maxRowsLabel, "BOTTOMLEFT", 0, -6)
sNearbyMaxRows:SetMinMaxValues(5, 20)
sNearbyMaxRows:SetValueStep(1)
sNearbyMaxRows:SetObeyStepOnDrag(true)
_G[sNearbyMaxRows:GetName().."Low"]:SetText("5")
_G[sNearbyMaxRows:GetName().."High"]:SetText("20")
_G[sNearbyMaxRows:GetName().."Text"]:SetText("")

do
  local settings = CurrentSettings()
  if type(settings.nearbyMaxVisibleRows) ~= "number" then settings.nearbyMaxVisibleRows = 20 end
  settings.nearbyMaxVisibleRows = math.floor(settings.nearbyMaxVisibleRows + 0.5)
  if settings.nearbyMaxVisibleRows < 5 then settings.nearbyMaxVisibleRows = 5 end
  if settings.nearbyMaxVisibleRows > 20 then settings.nearbyMaxVisibleRows = 20 end
  sNearbyMaxRows:SetValue(settings.nearbyMaxVisibleRows)
  maxRowsValue:SetText(tostring(settings.nearbyMaxVisibleRows))
end

sNearbyMaxRows:SetScript("OnValueChanged", function(self, val)
  if opt._kosSync then return end
  val = math.floor(val + 0.5)
  if val < 5 then val = 5 end
  if val > 20 then val = 20 end
  local settings = CurrentSettings()
  settings.nearbyMaxVisibleRows = val
  maxRowsValue:SetText(tostring(val))
  _G[self:GetName().."Text"]:SetText("")
  if KillOnSight_Nearby and KillOnSight_Nearby.AutoFitHeight then
    KillOnSight_Nearby:AutoFitHeight(KillOnSight_Nearby._lastCount or 1)
    if KillOnSight_Nearby.Refresh then KillOnSight_Nearby:Refresh() end
  end
end)

-- Automatic Guild Sync status; no visible chat announcements are used.
local syncStatusHeading = opt:CreateFontString(nil, "OVERLAY", "GameFontNormal")
syncStatusHeading:SetPoint("TOPLEFT", sNearbyMaxRows, "BOTTOMLEFT", 0, -28)
syncStatusHeading:SetText("Guild Sync")
commStatusText = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
commStatusText:SetPoint("TOPLEFT", syncStatusHeading, "BOTTOMLEFT", 0, -6)
commStatusText:SetWidth(560)
commStatusText:SetJustifyH("LEFT")
commStatusText:SetText("Waiting for communication status...")

-- Nearby window is always ultra-minimal (no toggle)
CurrentSettings().nearbyMinimal = true
if KillOnSight_Nearby and KillOnSight_Nearby.ApplyMinimalMode then
  KillOnSight_Nearby:ApplyMinimalMode()
end

  cSound:SetScript("OnClick", function(self)
    local settings = CurrentSettings()
    settings.enableSound = self:GetChecked()
  end)
  cFlash:SetScript("OnClick", function(self)
    local settings = CurrentSettings()
    settings.enableScreenFlash = self:GetChecked()
  end)
  -- initialize tab visuals
  if frame.tabs then
    for i,t in ipairs(frame.tabs) do
      if t and t.SetSelected then t:SetSelected(i == 1) end
    end
  end

  frame._refreshActivePanel = function()
    if not frame:IsShown() then return end
    local id = frame._activeTab or 1
    if id == 1 and pPlayers._list then
      pPlayers._list:SetData(BuildPlayers())
    elseif id == 2 and pGuilds._list then
      pGuilds._list:SetData(BuildGuilds())
    elseif id == 3 and pAtk._list then
      pAtk._list:SetData(BuildLastAttackers())
      if pAtk._UpdateButtons then pAtk:_UpdateButtons() end
    elseif id == 4 and pStats._Refresh then
      pStats._Refresh()
    elseif id == 5 and GUI.RefreshCommStatus then
      GUI:RefreshCommStatus()
    end
  end

  frame:ShowTab(1)

  -- store references for refresh
  frame._playersPanel = pPlayers
  frame._guildsPanel = pGuilds
  frame._seenPanel = pSeen
  frame._attackersPanel = pAtk
  frame._statsPanel = pStats
end




function GUI:RefreshCommStatus()
  if not commStatusText then return end
  local comm = _G.KillOnSight_Comm
  local status = comm and comm.GetStatusText and comm:GetStatusText() or "Communication unavailable"
  commStatusText:SetText("Guild Sync: " .. tostring(status))
end

function GUI:RefreshAll()
  if not frame or not frame:IsShown() then return end
  if frame._refreshActivePanel then frame._refreshActivePanel() end
end

function GUI:Show()
  self:Create()
  frame:Show()
  self:RefreshAll()
  self:RefreshCommStatus()
end

function GUI:Hide()
  if frame then frame:Hide() end
end

function GUI:Toggle()
  self:Create()
  if frame:IsShown() then self:Hide() else self:Show() end
end

KillOnSight_GUI = GUI
