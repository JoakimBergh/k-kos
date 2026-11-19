-- Version metadata compatibility for current WoW clients and older API surfaces.
local VERSION = "0.4.18"

local function GetInstalledVersion(addonName)
  if type(addonName) ~= "string" or addonName == "" then return VERSION end

  local metadataAPIs = {}
  if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
    metadataAPIs[#metadataAPIs + 1] = C_AddOns.GetAddOnMetadata
  end
  if type(GetAddOnMetadata) == "function" and GetAddOnMetadata ~= metadataAPIs[1] then
    metadataAPIs[#metadataAPIs + 1] = GetAddOnMetadata
  end

  for _, getMetadata in ipairs(metadataAPIs) do
    local ok, installedVersion = pcall(getMetadata, addonName, "Version")
    if ok and type(installedVersion) == "string" and installedVersion ~= "" then
      return installedVersion
    end
  end
  return VERSION
end

_G.KillOnSight_Version = {
  CURRENT = VERSION,
  GetInstalledVersion = GetInstalledVersion,
}
