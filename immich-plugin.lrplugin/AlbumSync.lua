---@diagnostic disable: undefined-global

require "ImmichAPI"
require "MetadataTask"
require "util"

AlbumSync = {}

-- ***********************************************************
-- Manifest file handling for album sync between phases.
local MANIFEST_FILENAME = "album_sync_manifest.json"
local LOCK_FILENAME = "album_sync.lock"

-- ***********************************************************
local function trimString(s)
    if type(s) ~= "string" then
        return nil
    end
    local t = s:match("^%s*(.-)%s*$")
    if t == "" then
        return nil
    end
    return t
end

-- ***********************************************************
local function readCredentialField(settings, keys)
    if type(settings) ~= "table" then
        return nil
    end
    for _, key in ipairs(keys or {}) do
        local value = settings[key]
        if type(value) == "string" then
            local trimmed = trimString(value)
            if trimmed then
                return trimmed
            end
        end
    end
    return nil
end

-- ***********************************************************
local function getPublishSettings(service)
    if not service or type(service.getPublishSettings) ~= "function" then
        return nil
    end
    local settings = service:getPublishSettings()
    return util.getEffectivePropertyTable(settings)
end

-- ***********************************************************
local function getCatalogPublishServices()
    local catalog = LrApplication.activeCatalog()
    if not catalog or type(catalog.getPublishServices) ~= "function" then
        return {}
    end
    local services = catalog:getPublishServices()
    if type(services) == "table" then
        return services
    end
    return {}
end

-- ***********************************************************
local function findCatalogServiceByLocalIdentifier(localIdentifier)
    if localIdentifier == nil or localIdentifier == "" then
        return nil
    end
    for _, service in ipairs(getCatalogPublishServices()) do
        if service and service.localIdentifier and tostring(service.localIdentifier) == tostring(localIdentifier) then
            return service
        end
    end
    return nil
end

-- ***********************************************************
local function findCatalogServiceForCollectionService(collectionService)
    if not collectionService then
        return nil
    end

    local localIdentifier = collectionService.localIdentifier
    local byLocalId = findCatalogServiceByLocalIdentifier(localIdentifier)
    if byLocalId then
        return byLocalId
    end

    -- Fallback: if there is exactly one Immich publish service in the catalog, use it.
    local immichServices = {}
    for _, service in ipairs(getCatalogPublishServices()) do
        if util.isImmichPublishService(service) then
            table.insert(immichServices, service)
        end
    end
    if #immichServices == 1 then
        return immichServices[1]
    end

    return nil
end

-- ***********************************************************
local function resolveServiceCredentials(serviceSettings, catalogSettings)
    local urlKeys = { "url", "URL", "immichUrl", "immichURL", "LR_url", "LR_URL" }
    local apiKeyKeys = { "apiKey", "apikey", "APIKey", "immichApiKey", "immichAPIKey", "LR_apiKey", "LR_apikey" }

    local url = readCredentialField(serviceSettings, urlKeys)
    local apiKey = readCredentialField(serviceSettings, apiKeyKeys)
    local source = "service settings"

    if util.nilOrEmpty(url) then
        url = readCredentialField(catalogSettings, urlKeys)
        if not util.nilOrEmpty(url) then
            source = "catalog service settings"
        end
    end
    if util.nilOrEmpty(apiKey) then
        apiKey = readCredentialField(catalogSettings, apiKeyKeys)
        if not util.nilOrEmpty(apiKey) then
            source = "catalog service settings"
        end
    end

    if util.nilOrEmpty(url) and type(prefs) == "table" and type(prefs.url) == "string" and trimString(prefs.url) then
        url = trimString(prefs.url)
        source = "global prefs fallback"
    end
    if util.nilOrEmpty(apiKey) and type(prefs) == "table" and type(prefs.apiKey) == "string" and trimString(prefs.apiKey) then
        apiKey = trimString(prefs.apiKey)
        source = "global prefs fallback"
    end

    return url, apiKey, source
end

-- ***********************************************************
local function isVideoAsset(asset)
    if type(asset) ~= "table" then
        return false
    end

    local fileName = tostring(asset.originalFileName or "")
    local extension = string.match(string.lower(fileName), "%.([^.]+)$")
    if not extension then
        return false
    end

    local videoExtensions = {
        mp4 = true,
        mov = true,
        m4v = true,
        avi = true,
        mkv = true,
        webm = true,
        wmv = true,
        mpg = true,
        mpeg = true,
        mts = true,
        m2ts = true,
        ts = true,
        ['3gp'] = true,
        ['3g2'] = true,
    }

    return videoExtensions[extension] == true
end

-- ***********************************************************
-- Build manifest path in staging folder.
local function getManifestPath(stagingFolder)
    if not stagingFolder or stagingFolder == "" then
        return nil
    end
    return LrPathUtils.child(stagingFolder, MANIFEST_FILENAME)
end

-- ***********************************************************
-- Build lock file path in staging folder.
local function getLockFilePath(stagingFolder)
    if not stagingFolder or stagingFolder == "" then
        return nil
    end
    return LrPathUtils.child(stagingFolder, LOCK_FILENAME)
end

-- ***********************************************************
-- Check if staging folder exists and is empty; return error message if not.
function AlbumSync.validateStagingFolder(stagingFolder)
    if not stagingFolder or stagingFolder == "" then
        return "Album Sync Staging Folder is not configured."
    end
    
    if not LrFileUtils.exists(stagingFolder) then
        return "Album Sync Staging Folder does not exist: " .. stagingFolder
    end
    
    -- Check if directory is empty.
    if not LrFileUtils.isEmptyDirectory(stagingFolder) then
        return "Album Sync Staging Folder is not empty. Please move or delete existing files first: " .. stagingFolder
    end
    
    return nil
end

-- ***********************************************************
-- Create lock file to prevent concurrent runs.
local function acquireLock(stagingFolder)
    local lockPath = getLockFilePath(stagingFolder)
    if not lockPath then
        return false
    end
    
    if LrFileUtils.exists(lockPath) then
        return false
    end
    
    local ok, err = LrTasks.pcall(function()
        local file = io.open(lockPath, "w")
        if file then
            file:write(tostring(os.time()))
            file:close()
            return true
        end
        return false
    end)
    
    return ok
end

-- ***********************************************************
-- Release lock file.
local function releaseLock(stagingFolder)
    local lockPath = getLockFilePath(stagingFolder)
    if lockPath and LrFileUtils.exists(lockPath) then
        LrFileUtils.delete(lockPath)
    end
end

-- ***********************************************************
-- Create manifest as JSON for phase A completion.
local function writeManifest(stagingFolder, albumId, collectionLocalId, entries)
    local manifestPath = getManifestPath(stagingFolder)
    if not manifestPath then
        return false
    end
    
    local manifest = {
        version = 1,
        albumId = albumId,
        collectionLocalId = collectionLocalId,
        timestamp = os.time(),
        pluginBuild = 27,
        entries = entries or {}
    }
    
    local ok, err = LrTasks.pcall(function()
        local json = JSON:encode(manifest)
        local file = io.open(manifestPath, "w")
        if file then
            file:write(json)
            file:close()
            return true
        end
        return false
    end)
    
    return ok
end

-- ***********************************************************
-- Read manifest from staging folder for phase B.
function AlbumSync.readManifest(stagingFolder)
    local manifestPath = getManifestPath(stagingFolder)
    if not manifestPath or not LrFileUtils.exists(manifestPath) then
        return nil
    end
    
    local manifest = nil
    local ok, err = LrTasks.pcall(function()
        local file = io.open(manifestPath, "r")
        if file then
            local content = file:read("*a")
            file:close()
            manifest = JSON:decode(content)
        end
    end)
    
    return ok and manifest or nil
end

-- ***********************************************************
-- Delete manifest and lock files after finalize.
local function cleanupManifest(stagingFolder)
    local manifestPath = getManifestPath(stagingFolder)
    local lockPath = getLockFilePath(stagingFolder)
    
    if manifestPath and LrFileUtils.exists(manifestPath) then
        LrFileUtils.delete(manifestPath)
    end
    
    releaseLock(stagingFolder)
end

-- ***********************************************************
-- Phase A: Download missing assets and create manifest.
-- Returns: success (bool), message (string).
function AlbumSync.downloadMissingAssets(selectedPublishedCollection, stagingFolder)
    local catalog = LrApplication.activeCatalog()
    if not catalog then
        return false, "Cannot access active Lightroom catalog."
    end
    
    -- Validate staging folder.
    local validationError = AlbumSync.validateStagingFolder(stagingFolder)
    if validationError then
        return false, validationError
    end
    
    -- Try to acquire lock.
    if not acquireLock(stagingFolder) then
        return false, "Album sync is already in progress in this staging folder."
    end
    
    -- Get selected collection details.
    local collectionName = selectedPublishedCollection:getName()
    local albumId = selectedPublishedCollection:getRemoteId()
    
    if not albumId or albumId == "" then
        releaseLock(stagingFolder)
        return false, "Published collection does not have a remote album ID. Please publish it to Immich first."
    end
    
    -- Get service settings.
    local service = selectedPublishedCollection:getService()
    if not service then
        releaseLock(stagingFolder)
        return false, "Cannot access publish service for this collection."
    end
    
    local settings = getPublishSettings(service)
    local catalogService = findCatalogServiceForCollectionService(service)
    local catalogSettings = getPublishSettings(catalogService)
    log:trace("Collection service localIdentifier: " .. tostring(service.localIdentifier))

    local url, apiKey, source = resolveServiceCredentials(settings, catalogSettings)
    if util.nilOrEmpty(url) or util.nilOrEmpty(apiKey) then
        releaseLock(stagingFolder)
        return false, "Immich service is not configured. Please configure URL and API key."
    end

    log:trace("Using credentials from " .. tostring(source) .. ": URL=" .. tostring(url) .. ", apiKey=" .. util.cutApiKey(apiKey))
    -- Initialize Immich API.
    local immich = ImmichAPI:new(url, apiKey)
    if not immich:checkConnectivity() then
        releaseLock(stagingFolder)
        return false, "Cannot connect to Immich server. Check URL and API key."
    end
    
    -- Verify album still exists.
    if not immich:checkIfAlbumExists(albumId) then
        releaseLock(stagingFolder)
        return false, "Album does not exist on Immich server. It may have been deleted."
    end
    
    -- Get all assets in Immich album.
    local immichAssets = immich:getAlbumAssets(albumId)
    if not immichAssets or #immichAssets == 0 then
        releaseLock(stagingFolder)
        return false, "Album contains no assets or could not be read."
    end
    
    -- Build set of already-published asset IDs in this collection.
    local publishedPhotos = selectedPublishedCollection:getPublishedPhotos()
    local publishedAssetIds = {}
    for _, publishedPhoto in ipairs(publishedPhotos or {}) do
        local remoteId = publishedPhoto:getRemoteId()
        if remoteId and remoteId ~= "" then
            publishedAssetIds[tostring(remoteId)] = true
        end
    end
    
    log:info("AlbumSync: Found " .. tostring(#immichAssets) .. " assets in Immich album, " .. tostring(#publishedPhotos) .. " already published in Lightroom collection.")
   log:info("AlbumSync: Published asset IDs: " .. util.serialiseVar(publishedAssetIds))
    -- Find missing non-video assets.
    local missingAssets = {}
    local skippedVideoCount = 0
    for _, asset in ipairs(immichAssets) do
        log:info("AlbumSync: Checking asset " .. tostring(asset.id) .. " (" .. tostring(asset.originalFileName) .. ")")  
        if isVideoAsset(asset) then
            skippedVideoCount = skippedVideoCount + 1
        elseif not publishedAssetIds[tostring(asset.id)] then
            table.insert(missingAssets, asset)
        end
    end
    
    if #missingAssets == 0 then
        releaseLock(stagingFolder)
        return true, "All assets in the album are already in this Lightroom collection. No download needed."
    end
    
    -- Download missing assets.
    local progress = LrProgressScope {
        title = "Sync Album: Downloading missing assets",
        caption = "Starting..."
    }
    
    local manifestEntries = {}
    local downloadedCount = 0
    local failedCount = 0
    
    for i, asset in ipairs(missingAssets) do
        if progress:isCanceled() then
            break
        end
        
        local fileName = asset.originalFileName or asset.id
        progress:setCaption("Downloading " .. fileName .. " (" .. tostring(i) .. " of " .. tostring(#missingAssets) .. ")")
        
        local assetData = immich:downloadAsset(asset.id)
        if assetData then
            local filePath = LrPathUtils.child(stagingFolder, fileName)
            
            local ok, writeErr = LrTasks.pcall(function()
                local file = io.open(filePath, "wb")
                if file then
                    file:write(assetData)
                    file:close()
                    return true
                end
                return false
            end)
            
            if ok then
                downloadedCount = downloadedCount + 1
                table.insert(manifestEntries, {
                    filename = fileName,
                    path = filePath,
                    assetId = asset.id,
                    assetUrl = immich:getAssetUrl(asset.id)
                })
            else
                failedCount = failedCount + 1
                log:warn("AlbumSync: Failed to write downloaded asset " .. asset.id .. " to " .. filePath)
            end
        else
            failedCount = failedCount + 1
            log:warn("AlbumSync: Failed to download asset " .. asset.id)
        end
        
        progress:setPortionComplete(i, #missingAssets)
    end
    
    progress:done()
    
    if downloadedCount == 0 then
        releaseLock(stagingFolder)
        return false, "Failed to download any assets. Check logs and connection."
    end
    
    -- Write manifest.
    if not writeManifest(stagingFolder, albumId, albumId, manifestEntries) then
        releaseLock(stagingFolder)
        return false, "Failed to write sync manifest. Cleanup and retry."
    end

    -- Open Lightroom import dialog at the staging folder so user can import immediately.
    local importUiOpened = false
    local importOk, importErr = LrTasks.pcall(function()
        catalog:triggerImportUI(stagingFolder)
        importUiOpened = true
    end)
    if not importOk then
        log:warn("AlbumSync: Failed to open import dialog for staging folder " .. tostring(stagingFolder) .. ": " .. tostring(importErr))
    end
    
    local message = "Downloaded " .. tostring(downloadedCount) .. " missing asset(s)"
    if failedCount > 0 then
        message = message .. "; " .. tostring(failedCount) .. " download(s) failed (check logs)"
    end
    if skippedVideoCount > 0 then
        message = message .. "; " .. tostring(skippedVideoCount) .. " video asset(s) skipped"
    end
    if importUiOpened then
        message = message .. ".\n\nImport dialog opened at the staging folder. Import these images using the 'Add' option, then run 'Finalize Album Sync for Selected Collection'."
    else
        message = message .. ".\n\nNext: Import these images into Lightroom using the 'Add' option, then run 'Finalize Album Sync for Selected Collection'."
    end
    
    return true, message
end

-- ***********************************************************
-- Phase B: Finalize after user manually imports photos.
-- Returns: success (bool), message (string).
function AlbumSync.finalizeImportedPhotos(selectedPublishedCollection, stagingFolder)
    local catalog = LrApplication.activeCatalog()
    if not catalog then
        return false, "Cannot access active Lightroom catalog."
    end
    
    -- Read manifest.
    local manifest = AlbumSync.readManifest(stagingFolder)
    if not manifest then
        return false, "No sync manifest found in staging folder. Run 'Sync Album Contents' first."
    end
    
    if manifest.albumId ~= selectedPublishedCollection:getRemoteId() then
        return false, "Staging folder manifest does not match selected collection. Please select the correct collection."
    end
    
    local albumId = manifest.albumId
    local entries = manifest.entries or {}
    
    if #entries == 0 then
        cleanupManifest(stagingFolder)
        return true, "No assets to finalize in manifest."
    end
    
    -- Get service settings.
    local service = selectedPublishedCollection:getService()
    local settings = getPublishSettings(service)
    local catalogService = findCatalogServiceForCollectionService(service)
    local catalogSettings = getPublishSettings(catalogService)
    local url, apiKey = resolveServiceCredentials(settings, catalogSettings)
    if util.nilOrEmpty(url) or util.nilOrEmpty(apiKey) then
        return false, "Cannot read publish service settings."
    end

    local immich = ImmichAPI:new(url, apiKey)
    
    -- Finalize each entry.
    local results = {
        linked = 0,
        skipped = 0,
        notFound = 0,
        failed = 0
    }
    
    local progress = LrProgressScope {
        title = "Sync Album: Finalizing imported photos",
        caption = "Starting..."
    }
    
    for i, entry in ipairs(entries) do
        if progress:isCanceled() then
            break
        end
        
        progress:setCaption("Finalizing " .. entry.filename .. " (" .. tostring(i) .. " of " .. tostring(#entries) .. ")")
        
        -- Find imported photo by path.
        local photo = nil
        local ok, findErr = LrTasks.pcall(function()
            photo = catalog:findPhotoByPath(entry.path)
        end)
        
        if not ok or not photo then
            results.notFound = results.notFound + 1
            log:warn("AlbumSync: Could not find imported photo at path " .. entry.path)
        else
            -- Check if already linked in collection.
            local publishedPhotos = selectedPublishedCollection:getPublishedPhotos()
            local alreadyLinked = false
            for _, pubPhoto in ipairs(publishedPhotos) do
                if pubPhoto:getRemoteId() == entry.assetId then
                    alreadyLinked = true
                    break
                end
            end
            
            if alreadyLinked then
                results.skipped = results.skipped + 1
                log:trace("AlbumSync: Photo already linked in collection: " .. entry.assetId)
            else
                -- Add to published collection and set metadata.
                local linkSuccess = false
                
                local writeOk, writeErr = LrTasks.pcall(function()
                    catalog:withWriteAccessDo("Finalize Album Sync", function()
                        -- Add to published collection.
                        selectedPublishedCollection:addPhotoByRemoteId(photo, entry.assetId, entry.assetUrl, true)
                        linkSuccess = true
                    end, { timeout = 30 })
                end)
                
                if writeOk and linkSuccess then
                    local metaOk = MetadataTask.setImmichAssetId(photo, entry.assetId)
                    if not metaOk then
                        log:warn("AlbumSync: Linked photo but failed to set metadata for asset " .. tostring(entry.assetId))
                    end
                    results.linked = results.linked + 1
                    log:trace("AlbumSync: Successfully linked photo " .. entry.assetId)
                else
                    results.failed = results.failed + 1
                    log:warn("AlbumSync: Failed to finalize photo " .. entry.assetId .. ": " .. tostring(writeErr))
                end
            end
        end
        
        progress:setPortionComplete(i, #entries)
    end
    
    progress:done()
    
    -- Cleanup manifest.
    cleanupManifest(stagingFolder)
    
    local message = "Finalize complete:\n"
        .. "Linked: " .. tostring(results.linked) .. "\n"
        .. "Skipped (already linked): " .. tostring(results.skipped) .. "\n"
        .. "Not found (file not imported): " .. tostring(results.notFound) .. "\n"
        .. "Failed: " .. tostring(results.failed)
    
    return (results.linked + results.skipped > 0), message
end

-- ***********************************************************
return AlbumSync
