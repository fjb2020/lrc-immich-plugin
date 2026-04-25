MetadataTask = {}

local keyAssetId = 'immichAssetId'


-- Set or clear stored Immich asset ID for a photo. Pass nil or "" to clear (e.g. when asset was deleted in Immich).
-- ***********************************************************
function MetadataTask.setImmichAssetId(photo, assetId)
    if not photo then
        log:warn("setImmichAssetId: photo is nil")
        return false
    end

    local catalog = LrApplication.activeCatalog()
    if not catalog then
        log:error("setImmichAssetId: no active catalog")
        return false
    end

    local valueToSet = (assetId ~= nil and assetId ~= "") and tostring(assetId) or ""

    catalog:withWriteAccessDo("Set Immich asset ID", function()
        photo:setPropertyForPlugin(_PLUGIN, keyAssetId, valueToSet)
    end, { timeout = 30 })
    return true
end

-- ***********************************************************
function MetadataTask.getImmichAssetId(photo)
    if not photo then
        return nil
    end
    
    local assetId = photo:getPropertyForPlugin(_PLUGIN, keyAssetId)
    if assetId and assetId ~= "" then
        log:trace("getImmichAssetId: Found assetId " .. assetId .. " for photo " .. tostring(photo.localIdentifier))
    end
    return assetId
end
