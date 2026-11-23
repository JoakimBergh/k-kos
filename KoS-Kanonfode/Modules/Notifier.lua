-- Notifier.lua
local ADDON_NAME = ...
local L = KillOnSight_L
local DB = KillOnSight_DB

local function RecordTrace(reason, fields)
  local trace = _G.KillOnSight_Trace
  if not trace or not trace.Record then return end
  pcall(trace.Record, trace, "notifier", reason, fields)
end

local Notifier = {}

local disabled = false
local function IsDisabled()
  local Core = _G.KillOnSight_Core
  return disabled or (Core and Core.IsKoSActive and not Core:IsKoSActive()) or false
end

function Notifier:SetDisabled(value)
  disabled = value and true or false
  if not disabled then return end
  for _, key in ipairs({"_stealthHoldTimer", "_stealthFadeTicker"}) do
    local timer = self[key]
    if timer and timer.Cancel then pcall(function() timer:Cancel() end) end
    self[key] = nil
  end
  local frames = {
    self.warningFrame, self._spyFrame, self._spyAlertGroup,
    self._stealthAlertWindow, self._targetAlertWindow, self._flashFrame,
  }
  for _, frame in ipairs(frames) do
    if frame and frame._timer and frame._timer.Cancel then pcall(function() frame._timer:Cancel() end); frame._timer = nil end
    if frame and frame._kosStealthAnim and frame._kosStealthAnim.Cancel then pcall(function() frame._kosStealthAnim:Cancel() end); frame._kosStealthAnim = nil end
    if frame and frame._kosTargetAnim and frame._kosTargetAnim.Cancel then pcall(function() frame._kosTargetAnim:Cancel() end); frame._kosTargetAnim = nil end
    if frame and frame._flashTicker then
      pcall(function() frame._flashTicker:SetScript("OnUpdate", nil); frame._flashTicker:Hide() end)
    end
    if frame and frame.SetScript then pcall(function() frame:SetScript("OnUpdate", nil) end) end
    if frame and frame.Hide then pcall(function() frame:Hide() end) end
  end
end


-- Local print helper (avoid relying on a global Print function)
local function _Print(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage("|cff00d0ff"..(KillOnSight_L and KillOnSight_L.ADDON_PREFIX or "K-KoS")..":|r "..tostring(msg))
  end
end


-- Optional town-level suppression: Booty Bay / Gadgetzan.
local function IsInGoblinTown()
  local sub = (GetSubZoneText and GetSubZoneText()) or ""
  local mini = (GetMinimapZoneText and GetMinimapZoneText()) or ""
  if sub == "" then sub = mini end
  if mini == "" then mini = sub end

  local bb = (L.SUBZONE_BOOTY_BAY or "Booty Bay")
  local gz = (L.SUBZONE_GADGETZAN or "Gadgetzan")

  return sub == bb or mini == bb or sub == gz or mini == gz
end

local function SuppressInGoblinTown()
  if not DB or not DB.GetSettings then return false end
  local prof = DB:GetSettings()
  return prof and prof.disableInGoblinTowns and IsInGoblinTown() or false
end

local function IsSecureTargetLocked()
  if not InCombatLockdown then return false end
  local ok, locked = pcall(InCombatLockdown)
  return not ok or locked == true
end

local function SaveSpyAlertPosition(frame)
  if not DB or not DB.GetSettings or not frame then return end
  local point, _, relPoint, x, y = frame:GetPoint(1)
  local prof = DB:GetSettings()
  prof.spyAlertPosition = prof.spyAlertPosition or {}
  prof.spyAlertPosition.point = point or "TOP"
  prof.spyAlertPosition.relPoint = relPoint or "TOP"
  prof.spyAlertPosition.x = tonumber(x) or 0
  prof.spyAlertPosition.y = tonumber(y) or -215
end

local function ApplySpyAlertPosition(frame)
  if not DB or not DB.GetSettings or not frame then return end
  local pos = DB:GetSettings().spyAlertPosition
  if type(pos) ~= "table" then return end

  local point = type(pos.point) == "string" and pos.point or "TOP"
  local relPoint = type(pos.relPoint) == "string" and pos.relPoint or "TOP"
  local x = tonumber(pos.x) or 0
  local y = tonumber(pos.y) or -215
  pcall(function()
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, relPoint, x, y)
  end)
end

local function SetAlertTargetMacro(frame, name)
  local button = frame and frame._targetButton
  if not button or IsSecureTargetLocked() then return false end

  local targetName
  if type(name) == "string" then
    targetName = name:gsub("|c%x%x%x%x%x%x%x%x", "")
      :gsub("|r", "")
      :gsub("|T.-|t", "")
      :gsub("[\r\n;]", "")
      :gsub("^%s+", "")
      :gsub("%s+$", "")
  end

  local macro = targetName and targetName ~= ""
    and ("/stopmacro [combat]\n/targetexact " .. targetName)
    or "/stopmacro"
  local ok = pcall(function()
    button:SetAttribute("type1", "macro")
    button:SetAttribute("macrotext1", macro)
    button:SetAttribute("macrotext", macro)
  end)
  return ok
end

local function ClassHex(classFile)
  if not classFile or not RAID_CLASS_COLORS or not RAID_CLASS_COLORS[classFile] then
    return nil
  end
  local c = RAID_CLASS_COLORS[classFile]
  local r = math.floor((c.r or 1) * 255 + 0.5)
  local g = math.floor((c.g or 1) * 255 + 0.5)
  local b = math.floor((c.b or 1) * 255 + 0.5)
  return string.format("|cff%02x%02x%02x", r, g, b)
end

local function ColorizeName(name, classFile)
  local hex = ClassHex(classFile)
  if not hex then return name end
  return hex .. name .. "|r"
end

function Notifier:GetStealthTiming()
  local prof = DB:GetSettings()
  local hold = tonumber(prof.stealthWarningHoldSeconds) or 6.0
  local fade = tonumber(prof.stealthWarningFadeSeconds) or 1.2
  if hold < 0 then hold = 0 end
  if fade < 0.1 then fade = 0.1 end
  return hold, fade
end

function Notifier:ApplyStealthSettings()
  local prof = DB:GetSettings()
  if prof.stealthDetectCenterWarning == false then
    if self.warningFrame then
      self.warningFrame:Hide()
    end
    if self._stealthHoldTimer and self._stealthHoldTimer.Cancel then
      self._stealthHoldTimer:Cancel()
    end
    if self._stealthFadeTicker and self._stealthFadeTicker.Cancel then
      self._stealthFadeTicker:Cancel()
    end
    self._stealthHoldTimer = nil
    self._stealthFadeTicker = nil
  end
end

local CENTER_WARNING_HOLD = 2.0   -- seconds fully visible
local CENTER_WARNING_FADE = 1.2   -- seconds smooth fade out
local CENTER_WARNING_YOFF = 180   -- vertical offset from center
-- Spy-style center warning frame (custom, reliable across client branches)
local function EnsureSpyWarningFrame()
  if Notifier._spyFrame then return Notifier._spyFrame end

  local parent = _G.UIParent or nil
  local f = CreateFrame("Frame", "KillOnSight_SpyWarningFrame", parent)
  f:SetFrameStrata("HIGH")
  f:SetSize(720, 84)
  if parent then
    f:SetPoint("CENTER", parent, "CENTER", 0, CENTER_WARNING_YOFF)
  else
    f:SetPoint("CENTER", 0, CENTER_WARNING_YOFF)
  end
  f:Hide()
  f:SetAlpha(1)

  -- Banner background
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.55)
  f.bg = bg

  -- Thin red top/bottom lines (Spy-ish)
  local top = f:CreateTexture(nil, "BORDER")
  top:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  top:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  top:SetHeight(2)
  top:SetColorTexture(1, 0.15, 0.15, 0.9)

  local bottom = f:CreateTexture(nil, "BORDER")
  bottom:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  bottom:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  bottom:SetHeight(2)
  bottom:SetColorTexture(1, 0.15, 0.15, 0.9)

  -- Text
  local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  fs:SetPoint("CENTER")
  fs:SetJustifyH("CENTER")
  fs:SetJustifyV("MIDDLE")
  fs:SetTextColor(1, 0.12, 0.12)
  fs:SetShadowColor(0, 0, 0, 1)
  fs:SetShadowOffset(2, -2)
  f.text = fs

  -- Internal fade state
  f._phase = "idle"
  f._t = 0
  f._timer = nil

  Notifier._spyFrame = f
  return f
end

local flashFrame

local function EnsureFlashFrame()
  if flashFrame then return end
  flashFrame = CreateFrame("Frame", nil, UIParent)
  Notifier._flashFrame = flashFrame
  flashFrame:SetAllPoints(UIParent)
  flashFrame:Hide()
  flashFrame.tex = flashFrame:CreateTexture(nil, "BACKGROUND")
  flashFrame.tex:SetAllPoints()
  flashFrame.tex:SetColorTexture(1, 0, 0, 0.18)
end


local function EnsureSpyAlertGroup()
  if Notifier._spyAlertGroup then return Notifier._spyAlertGroup end

  local group = CreateFrame("Frame", "KillOnSight_SpyAlertGroup", UIParent)
  group:ClearAllPoints()
  group:SetPoint("TOP", UIParent, "TOP", 0, -215)
  group:SetClampedToScreen(true)
  group:SetSize(180, 90)
  group:SetMovable(true)
  group:EnableMouse(true)
  group:RegisterForDrag("LeftButton")
  group:SetScript("OnDragStart", function(self)
    if IsSecureTargetLocked() then return end
    self._alertGroupMoving = true
    self:StartMoving()
  end)
  group:SetScript("OnDragStop", function(self)
    if not self._alertGroupMoving then return end
    self:StopMovingOrSizing()
    self._alertGroupMoving = nil
    SaveSpyAlertPosition(self)
  end)
  group:Hide()

  Notifier._spyAlertGroup = group
  ApplySpyAlertPosition(group)
  return group
end

local function UpdateSpyAlertGroupSize()
  local group = Notifier._spyAlertGroup
  if not group then return end
  local stealth = Notifier._stealthAlertWindow
  local target = Notifier._targetAlertWindow
  local width = math.max(
    180,
    (stealth and stealth.GetWidth and stealth:GetWidth()) or 0,
    (target and target.GetWidth and target:GetWidth()) or 0
  )
  group:SetSize(width, 90)
end

local function UpdateSpyAlertGroupVisibility()
  local group = Notifier._spyAlertGroup
  if not group then return end
  local stealth = Notifier._stealthAlertWindow
  local target = Notifier._targetAlertWindow
  if (stealth and stealth:IsShown()) or (target and target:IsShown()) then
    group:Show()
  else
    group:Hide()
  end
end

local function StartMovingSpyAlertGroup()
  local group = Notifier._spyAlertGroup
  if not group or IsSecureTargetLocked() then return end
  group._alertGroupMoving = true
  group:StartMoving()
end

local function StopMovingSpyAlertGroup()
  local group = Notifier._spyAlertGroup
  if not group or not group._alertGroupMoving then return end
  group:StopMovingOrSizing()
  group._alertGroupMoving = nil
  SaveSpyAlertPosition(group)
end

local function EnsureSpyAlertWindow(kind)
  kind = kind == "stealth" and "stealth" or "targeting"
  local isStealth = kind == "stealth"
  local field = isStealth and "_stealthAlertWindow" or "_targetAlertWindow"
  if Notifier[field] then return Notifier[field] end

  local group = EnsureSpyAlertGroup()
  local frameName = isStealth and "KillOnSight_StealthAlertWindow" or "KillOnSight_TargetingAlertWindow"
  local f = CreateFrame("Frame", frameName, group, "BackdropTemplate")
  f:ClearAllPoints()
  if isStealth then
    f:SetPoint("TOPLEFT", group, "TOPLEFT", 0, 0)
  else
    f:SetPoint("TOPLEFT", group, "TOPLEFT", 0, -48)
  end
  f:SetSize(180, 42)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", StartMovingSpyAlertGroup)
  f:SetScript("OnDragStop", StopMovingSpyAlertGroup)
  f:Hide()

  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16,
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  f:SetBackdropColor(0, 0, 0, 0.90)

  f.Icon = CreateFrame("Frame", nil, f, "BackdropTemplate")
  f.Icon:ClearAllPoints()
  f.Icon:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -5)
  f.Icon:SetSize(32, 32)
  f.Icon:SetBackdrop({ bgFile = isStealth and "Interface\\Icons\\Ability_Stealth" or "Interface\\Icons\\Ability_Hunter_SniperShot" })
  f.Icon:SetBackdropColor(1, 1, 1, isStealth and 0.5 or 1)

  f.Title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.Title:SetPoint("TOPLEFT", f, "TOPLEFT", 42, -3)
  f.Title:SetHeight(12)
  f.Title:SetText(isStealth and L.STEALTH_DETECTED_TITLE or (L.TARGETING_YOU_TITLE or "Enemy targeting you!"))

  f.Name = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.Name:SetPoint("TOPLEFT", f, "TOPLEFT", 42, -15)
  f.Name:SetHeight(12)

  if not isStealth then
    -- Keep the secure click target anchored to its own frame, never to a text region.
    local targetButton = CreateFrame("Button", nil, f, "SecureActionButtonTemplate")
    targetButton:SetPoint("TOPLEFT", f, "TOPLEFT", 42, -15)
    targetButton:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 15)
    targetButton:EnableMouse(true)
    targetButton:RegisterForClicks("AnyDown", "AnyUp")
    targetButton:SetAttribute("type1", "macro")
    targetButton:SetAttribute("macrotext1", "/stopmacro")
    targetButton:SetAttribute("macrotext", "/stopmacro")
    targetButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    targetButton:SetScript("OnEnter", function(self)
      if not f._targetName or not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(f._targetName, 1, 0.82, 0)
      GameTooltip:AddLine(L.TARGETING_YOU_CLICK_HINT or "Click to target when out of combat.", 1, 1, 1, true)
      if IsSecureTargetLocked() then
        GameTooltip:AddLine(L.TARGETING_YOU_COMBAT_HINT or "Targeting is blocked during combat.", 1, 0.25, 0.25, true)
      end
      GameTooltip:Show()
    end)
    targetButton:SetScript("OnLeave", function()
      if GameTooltip then GameTooltip:Hide() end
    end)
    f._targetButton = targetButton
    f:HookScript("OnHide", function(self)
      self._targetName = nil
      self._targetGUID = nil
      SetAlertTargetMacro(self, nil)
    end)
  end

  local dismissButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  dismissButton:SetSize(18, 18)
  dismissButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  dismissButton:SetScript("OnClick", function()
    if Notifier.DismissSpyAlert then Notifier:DismissSpyAlert(kind) end
  end)
  f._dismissButton = dismissButton

  f.Location = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.Location:SetPoint("TOPLEFT", f, "TOPLEFT", 42, -26)
  f.Location:SetHeight(12)
  f.Location:SetText("")

  local borderR, borderG, borderB = isStealth and 0.6 or 1, isStealth and 0.2 or 0.15, isStealth and 1 or 0.15
  f:SetBackdropBorderColor(borderR, borderG, borderB, isStealth and 0.4 or 0.9)
  f.Title:SetTextColor(isStealth and 0.6 or 1, isStealth and 0.2 or 0.2, isStealth and 1 or 0.2, 1)
  f.Name:SetTextColor(1, 1, 1, 1)
  f.Location:SetTextColor(1, 0.82, 0, 1)

  Notifier[field] = f
  if not isStealth then Notifier._spyAlertWindow = f end
  UpdateSpyAlertGroupSize()
  return f
end


local function _FlashStopWindow(f)
  if not f then return end
  if f._flashTicker then
    f._flashTicker:SetScript("OnUpdate", nil)
    f._flashTicker:Hide()
    f._flashTicker = nil
  end
end

local function _FlashWindow(f)
  if not f then return end
  _FlashStopWindow(f)
  local flash = CreateFrame("Frame", nil, f)
  flash:SetAllPoints(f)
  flash:Hide()
  flash:SetAlpha(0.65)
  flash.elapsed = 0
  flash:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    local a = 0.65 * (1 - (self.elapsed / 0.55))
    if a <= 0 then
      self:SetScript("OnUpdate", nil)
      self:Hide()
    else
      self:SetAlpha(a)
    end
  end)
  f._flashTicker = flash
  flash:Show()
end

local function CancelSpyAlertAnimation(f)
  for _, key in ipairs({"_kosStealthAnim", "_kosTargetAnim"}) do
    local timer = f and f[key]
    if timer and timer.Cancel then timer:Cancel() end
    if f then f[key] = nil end
  end
  if f and f.SetScript then f:SetScript("OnUpdate", nil) end
end

local function DismissSpyAlertFrame(f)
  if not f then return false end
  CancelSpyAlertAnimation(f)
  _FlashStopWindow(f)
  f:SetScript("OnUpdate", nil)
  f:SetAlpha(1)
  if f:IsShown() then f:Hide() end
  return true
end

function Notifier:DismissSpyAlert(kind)
  local changed = false
  if not kind or kind == "stealth" then
    changed = DismissSpyAlertFrame(self._stealthAlertWindow) or changed
  end
  if not kind or kind == "targeting" then
    changed = DismissSpyAlertFrame(self._targetAlertWindow) or changed
  end
  UpdateSpyAlertGroupVisibility()
  return changed
end

function Notifier:ClearTargetingAlert(guid)
  local f = self._targetAlertWindow
  if not f or f._alertKind ~= "targeting" then return false end
  if guid and f._targetGUID ~= guid then return false end
  return self:DismissSpyAlert("targeting")
end

function Notifier:ShowSpyStealthAlert(name, classFile)
  local f = EnsureSpyAlertWindow("stealth")
  CancelSpyAlertAnimation(f)
  f._alertKind = "stealth"

  -- Title (localized)
  if f.Title and f.Title.SetText then
    f.Title:SetText(L.STEALTH_DETECTED_TITLE)
    f.Title:SetTextColor(0.6, 0.2, 1.0, 1)
  end
  if f.Icon and f.Icon.SetBackdrop then
    f.Icon:SetBackdrop({ bgFile = "Interface\\Icons\\Ability_Stealth" })
    f.Icon:SetBackdropColor(1, 1, 1, 0.5)
  end
  if f.SetBackdropBorderColor then f:SetBackdropBorderColor(0.6, 0.2, 1.0, 0.4) end

  -- Apply class-colored name (Spy-style)
  local coloredName = ColorizeName(name, classFile)
  if f.Name and f.Name.SetText then
    f.Name:SetText(coloredName or (name or ""))
    -- Name position (no class icon)
    f.Name:SetPoint("TOPLEFT", f, "TOPLEFT", 42, -15)
  end

  -- Hide the optional location line for stealth (Spy behavior)
  if f.Location and f.Location.SetText then
    f.Location:SetText("")
  end

  -- Width = max(title, name) + 52 (Spy formula)
  local titleW = (f.Title and f.Title.GetStringWidth and f.Title:GetStringWidth()) or 0
  local nameW  = (f.Name and f.Name.GetStringWidth and f.Name:GetStringWidth()) or 0
  local w = math.max(titleW, nameW) + 52
  if w < 180 then w = 180 end -- keep readable minimum
  f:SetWidth(w)
  if f.Name and f.Name.SetWidth then f.Name:SetWidth(f:GetWidth() - 52) end
  if f.Location and f.Location.SetWidth then f.Location:SetWidth(f:GetWidth() - 52) end
  UpdateSpyAlertGroupSize()

  -- Show + animate (hold then fade)
  EnsureSpyAlertGroup():Show()
  f:Show()
  UpdateSpyAlertGroupVisibility()
  f:SetAlpha(1)

  local hold, fade = 6.0, 1.2
  if self.GetStealthTiming then
    local h, fd = self:GetStealthTiming()
    if h then hold = h end
    if fd then fade = fd end
  end

  -- Start flash pulse (small overlay)
  _FlashWindow(f)

  -- Hold, then fade out smoothly
  if C_Timer and C_Timer.After then
    f._kosStealthAnim = C_Timer.NewTimer(hold, function()
      if not f or not f.IsShown or not f:IsShown() then return end
      local t = 0
      f:SetScript("OnUpdate", function(self, elapsed)
        t = t + elapsed
        local p = t / fade
        if p >= 1 then
          self:SetScript("OnUpdate", nil)
          self:Hide()
          self:SetAlpha(1)
          UpdateSpyAlertGroupVisibility()
          return
        end
        self:SetAlpha(1 - p)
      end)
    end)
  else
    -- fallback: no timer API, just show
  end
end

function Notifier:ShowSpyTargetAlert(name, classFile, guid)
  local f = EnsureSpyAlertWindow("targeting")
  CancelSpyAlertAnimation(f)
  f._alertKind = "targeting"
  f._targetName = name
  f._targetGUID = guid
  SetAlertTargetMacro(f, name)

  if f.Title and f.Title.SetText then
    f.Title:SetText(L.TARGETING_YOU_TITLE or "Enemy targeting you!")
    f.Title:SetTextColor(1, 0.2, 0.2, 1)
  end
  if f.Icon and f.Icon.SetBackdrop then
    f.Icon:SetBackdrop({ bgFile = "Interface\\Icons\\Ability_Hunter_SniperShot" })
    f.Icon:SetBackdropColor(1, 1, 1, 1)
  end
  if f.SetBackdropBorderColor then f:SetBackdropBorderColor(1, 0.15, 0.15, 0.9) end

  local coloredName = ColorizeName(name, classFile)
  if f.Name and f.Name.SetText then
    f.Name:SetText(coloredName or (name or ""))
    f.Name:SetPoint("TOPLEFT", f, "TOPLEFT", 42, -15)
  end
  if f.Location and f.Location.SetText then f.Location:SetText("") end

  local titleW = (f.Title and f.Title.GetStringWidth and f.Title:GetStringWidth()) or 0
  local nameW = (f.Name and f.Name.GetStringWidth and f.Name:GetStringWidth()) or 0
  local width = math.max(titleW, nameW) + 52
  if width < 180 then width = 180 end
  f:SetWidth(width)
  if f.Name and f.Name.SetWidth then f.Name:SetWidth(width - 52) end
  if f.Location and f.Location.SetWidth then f.Location:SetWidth(width - 52) end
  UpdateSpyAlertGroupSize()

  EnsureSpyAlertGroup():Show()
  f:Show()
  UpdateSpyAlertGroupVisibility()
  f:SetAlpha(1)
  _FlashWindow(f)

  local hold, fade = 4.0, 1.2
  if C_Timer and C_Timer.After then
    f._kosTargetAnim = C_Timer.NewTimer(hold, function()
      if not f or not f.IsShown or not f:IsShown() then return end
      local elapsed = 0
      f:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local progress = elapsed / fade
        if progress >= 1 then
          self:SetScript("OnUpdate", nil)
          self:Hide()
          self:SetAlpha(1)
          UpdateSpyAlertGroupVisibility()
          return
        end
        self:SetAlpha(1 - progress)
      end)
    end)
  end
  return true, "shown"
end

-- Pre-create the secure button during addon load, before a possible combat lockdown.
EnsureSpyAlertWindow("stealth")
EnsureSpyAlertWindow("targeting")

local targetButtonEventFrame = CreateFrame("Frame")
targetButtonEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
targetButtonEventFrame:SetScript("OnEvent", function()
  local f = Notifier._targetAlertWindow
  if not f or not f._targetButton then return end
  if f:IsShown() and f._alertKind == "targeting" then
    SetAlertTargetMacro(f, f._targetName)
  else
    SetAlertTargetMacro(f, nil)
  end
end)



-------------------------------------------------
-- Spy-style Stealth Alert Frame
-------------------------------------------------
function Notifier:Chat(msg)
  if IsDisabled() then return end
  if DB:GetSettings().printToChat then
    _Print(msg)
  end
end

-- Play a sound shipped with this addon. Use the runtime addon folder name
-- supplied by WoW instead of hard-coding it: the folder name can change,
-- and KoS-Kanonfode contains a non-ASCII character.
function Notifier:PlayBundledSound(fileName)
  if IsDisabled() then return false end
  if type(fileName) ~= "string" or fileName == "" then return false end

  local addonFolder = (type(ADDON_NAME) == "string" and ADDON_NAME ~= "")
    and ADDON_NAME or "KoS-Kanonfode"
  local path = "Interface\\AddOns\\" .. addonFolder .. "\\Sounds\\" .. fileName

  local played = false
  if PlaySoundFile then
    local ok, result = pcall(PlaySoundFile, path, "Master")
    played = ok and result and true or false
  end
  if played then return true end

  -- PlaySoundFile may return false without raising a Lua error (for example,
  -- when the file path cannot be resolved). Fall back to a built-in UI sound.
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
    pcall(PlaySound, SOUNDKIT.RAID_WARNING, "Master")
  end
  return false
end

function Notifier:Sound()
  if IsDisabled() then return end
  if not DB:GetSettings().enableSound then return end
  PlaySound(SOUNDKIT.RAID_WARNING, "Master")
end

function Notifier:NotifyTargetingYou(name, classFile, guid)
  if IsDisabled() then
    RecordTrace("target_alert_inactive", { active = false })
    return false, "inactive"
  end
  if SuppressInGoblinTown() then
    RecordTrace("target_alert_goblin_suppressed", { goblinFilter = true })
    return false, "goblin_town"
  end
  local prof = DB:GetSettings()
  if prof.targetingAlertEnabled == false then
    RecordTrace("target_alert_disabled")
    return false, "disabled"
  end
  local shown, status = self:ShowSpyTargetAlert(name, classFile, guid)
  if shown ~= true then
    status = status or "not_shown"
    RecordTrace("target_alert_not_shown", { alertStatus = status })
    return false, status
  end
  RecordTrace("target_alert_window_requested")
  if prof.enableSound ~= false then
    local played = self:PlayBundledSound("detected-nearby.mp3")
    RecordTrace("target_alert_sound_requested", { sound = played and true or false })
  end
  return true, "shown"
end

function Notifier:Flash()
  if IsDisabled() then return end
  if not DB:GetSettings().enableScreenFlash then return end
  EnsureFlashFrame()
  flashFrame:Show()
  flashFrame:SetAlpha(0.65)
  flashFrame.elapsed = 0
  flashFrame:SetScript("OnUpdate", function(self, dt)
    self.elapsed = self.elapsed + dt
    local a = 0.65 * (1 - (self.elapsed / 0.55))
    if a <= 0 then
      self:SetScript("OnUpdate", nil)
      self:Hide()
    else
      self:SetAlpha(a)
    end
  end)
end

function Notifier:NotifyPlayer(listType, name, reason)
  if IsDisabled() then return end
  if SuppressInGoblinTown() then return end
  -- Always update the Nearby list first.
  local nearby = _G.KillOnSight_Nearby
  if nearby and nearby.Seen then
    nearby:Seen(name, nil, nil, listType, nil)
  end

  -- Rollback-style behavior requested: KoS/Guild alerts fire ONLY once while the
  -- player remains in the Nearby list (no time-based throttling).
  local doChat, doStrong = true, true
  if nearby and nearby.ConsumeKoSGuildAnnouncement then
    doChat, doStrong = nearby:ConsumeKoSGuildAnnouncement(name, listType)
  end

  if not doChat and not doStrong then return end

  local suffix = reason and (" - "..reason) or ""
  if doChat then
    self:Chat(string.format(L.SEEN, listType, name, suffix))
  end
  if doStrong then
    self:Sound()
    self:Flash()
  end
end

function Notifier:NotifyGuild(listType, name, guild, reason)
  if IsDisabled() then return end
  if SuppressInGoblinTown() then return end
  -- Always update the Nearby list first.
  local nearby = _G.KillOnSight_Nearby
  if nearby and nearby.Seen then
    nearby:Seen(name, nil, guild, listType, nil)
  end

  -- Rollback-style behavior requested: KoS/Guild alerts fire ONLY once while the
  -- player remains in the Nearby list (no time-based throttling).
  local doChat, doStrong = true, true
  if nearby and nearby.ConsumeKoSGuildAnnouncement then
    doChat, doStrong = nearby:ConsumeKoSGuildAnnouncement(name, listType)
  end

  if not doChat and not doStrong then return end

  local suffix = reason and (" - "..reason) or ""
  if doChat then
    self:Chat(string.format(L.SEEN_GUILD, listType, name, guild, suffix))
  end
  if doStrong then
    self:Sound()
    self:Flash()
  end
end


function Notifier:CenterWarning(msg)
  if IsDisabled() then return end
  local hold, fade = self:GetStealthTiming()
  if self._stealthHoldTimer and self._stealthHoldTimer.Cancel then self._stealthHoldTimer:Cancel() end
  if self._stealthFadeTicker and self._stealthFadeTicker.Cancel then self._stealthFadeTicker:Cancel() end
  self._stealthHoldTimer = nil
  self._stealthFadeTicker = nil
  if not msg or msg == "" then return end

  local f = EnsureSpyWarningFrame()
  if f and f.text then
    f.text:SetText(msg)
    f:SetAlpha(1)
    f:Show()

    -- Cancel any existing timer
    if f._timer and f._timer.Cancel then
      f._timer:Cancel()
      f._timer = nil
    end

    -- Reset any running OnUpdate fade
    f:SetScript("OnUpdate", nil)
    f._phase = "hold"
    f._t = 0

    -- After hold time, begin fade-out smoothly
    if _G.C_Timer and _G.C_Timer.NewTimer then
      f._timer = _G.C_Timer.NewTimer(hold, function()
        if not f then return end
        f._phase = "fade"
        f._t = 0
        f:SetScript("OnUpdate", function(self, elapsed)
          self._t = (self._t or 0) + elapsed
          local p = self._t / fade
          if p >= 1 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            self:SetAlpha(1)
            self._phase = "idle"
            return
          end
          self:SetAlpha(1 - p)
        end)
      end)
    else
      -- Very old fallback: do both hold+fade inside OnUpdate
      f._phase = "hold"
      f._t = 0
      f:SetScript("OnUpdate", function(self, elapsed)
        self._t = (self._t or 0) + elapsed
        if self._phase == "hold" then
          if self._t >= hold then
            self._phase = "fade"
            self._t = 0
          end
          return
        end

        local p = self._t / fade
        if p >= 1 then
          self:SetScript("OnUpdate", nil)
          self:Hide()
          self:SetAlpha(1)
          self._phase = "idle"
          return
        end
        self:SetAlpha(1 - p)
      end)
    end

    return
  end

  -- Fallback: UIErrorsFrame (some UIs filter it)
  if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
    pcall(function() _G.UIErrorsFrame:AddMessage(msg, 1, 0.1, 0.1) end)
    return
  end

  -- Fallback: Raid warning (top-middle).
  if _G.RaidNotice_AddMessage and _G.RaidWarningFrame and _G.ChatTypeInfo then
    _G.RaidNotice_AddMessage(_G.RaidWarningFrame, msg, _G.ChatTypeInfo["RAID_WARNING"])
    return
  end
end
function Notifier:NotifyHidden(name, spellName, guid)
  if IsDisabled() then return end
  if SuppressInGoblinTown() then return end
  local prof = DB:GetSettings()

  -- Master stealth toggle (live)
  if prof.stealthDetectEnabled == false then
    return
  end

  local classFile
  if guid and GetPlayerInfoByGUID then
    local _, cls = GetPlayerInfoByGUID(guid)
    classFile = cls
  end

  local coloredName = ColorizeName(name, classFile)
  local label = spellName and (spellName .. ": ") or ""

  -- Chat output (Chat() respects printToChat)
  if prof.stealthDetectChat ~= false then
    self:Chat(string.format(L.SEEN_HIDDEN, label .. coloredName))
  end
  -- Spy-style stealth alert window
  if prof.stealthDetectCenterWarning ~= false then
    self:ShowSpyStealthAlert(name, classFile)
  end
  -- Stealth sound (independent of the main KoS/Guild sound toggle)
  if prof.stealthDetectSound ~= false then
    self:PlayBundledSound("detected-stealth.mp3")
  end

  self:Flash()

  -- Add to Nearby list (pass class so row can be colored/iconed)
  if prof.stealthDetectAddToNearby ~= false then
    if _G.KillOnSight_Nearby and _G.KillOnSight_Nearby.Seen then
      _G.KillOnSight_Nearby:Seen(name, classFile, nil, L.HIDDEN, nil)
    end
  end
end

function Notifier:NotifyActivity(listType, name, activity, reason)
  if IsDisabled() then return end
  if SuppressInGoblinTown() then return end
  local suffix = reason and (" - "..reason) or ""
  self:Chat(string.format(L.ACTIVITY, listType, name, activity, suffix))
  self:Sound()
end

KillOnSight_Notifier = Notifier
