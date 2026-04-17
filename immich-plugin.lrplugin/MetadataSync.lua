---@diagnostic disable: undefined-global, duplicate-set-field

require "ImmichAPI"

MetadataSync = {}

-- Basic string normalizer used by metadata and tag helpers.
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

-- Normalize nil/empty parent IDs so root matching is consistent.
local function normalizeParentId(parentId)
    if parentId == nil or parentId == "" then
        return ""
    end
    return tostring(parentId)
end

-- Return stable local-id key for photo matching.
local function getPhotoLocalId(photo)
    local localId = photo and photo.localIdentifier
    if localId ~= nil and localId ~= "" then
        return tostring(localId)
    end
    return nil
end

-- Lightroom can wrap property tables as { ["< contents >"] = {...} }.
local function getEffectivePropertyTable(propertyTable)
    if type(propertyTable) == "table" and type(propertyTable["< contents >"]) == "table" then
        return propertyTable["< contents >"], propertyTable
    end
    return propertyTable, propertyTable
end

-- Read publish settings from a service.
local function getPublishSettings(service)
    if not service or type(service.getPublishSettings) ~= "function" then
        return nil
    end
    local settings = service:getPublishSettings()
    local effectiveSettings = getEffectivePropertyTable(settings)
    return effectiveSettings
end

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

local function readBooleanField(settings, keys)
    if type(settings) ~= "table" then
        return nil
    end
    for _, key in ipairs(keys or {}) do
        local value = settings[key]
        if type(value) == "boolean" then
            return value
        end
        if type(value) == "string" then
            local normalized = string.lower(value)
            if normalized == "true" then
                return true
            end
            if normalized == "false" then
                return false
            end
        end
    end
    return nil
end

local function resolveServiceCredentials(serviceSettings, catalogSettings)
    local urlKeys = { "url", "URL", "immichUrl", "immichURL", "LR_url", "LR_URL" }
    local apiKeyKeys = { "apiKey", "apikey", "APIKey", "immichApiKey", "immichAPIKey", "LR_apiKey", "LR_apikey" }
    local stripRootKeys = { "stripTagRootNode", "stripKeywordRootNode", "LR_stripTagRootNode" }

    local url = readCredentialField(serviceSettings, urlKeys)
    local apiKey = readCredentialField(serviceSettings, apiKeyKeys)
    local stripTagRootNode = readBooleanField(serviceSettings, stripRootKeys)
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
    if stripTagRootNode == nil then
        stripTagRootNode = readBooleanField(catalogSettings, stripRootKeys)
        if stripTagRootNode ~= nil then
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
    if stripTagRootNode == nil and type(prefs) == "table" and type(prefs.stripTagRootNode) == "boolean" then
        stripTagRootNode = prefs.stripTagRootNode
        source = "global prefs fallback"
    end

    return url, apiKey, stripTagRootNode, source
end

-- Produce a compact debug description of a publish-settings object.
-- Read published collections containing this photo.
local function getContainedPublishedCollections(photo)
    if not photo or type(photo.getContainedPublishedCollections) ~= "function" then
        return {}
    end
    local collections = photo:getContainedPublishedCollections()
    if type(collections) == "table" then
        return collections
    end
    return {}
end

-- Read published photos from a publish collection.
local function getPublishedPhotos(collection)
    if not collection or type(collection.getPublishedPhotos) ~= "function" then
        return {}
    end
    local photos = collection:getPublishedPhotos()
    if type(photos) == "table" then
        return photos
    end
    return {}
end

-- Read all publish services from the active catalog for diagnostics.
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

-- Find a catalog publish service with the same localIdentifier.
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

-- Find the published-photo object for a selected photo in one collection.
local function findPublishedPhotoInCollection(collection, selectedPhoto)
    local selectedId = getPhotoLocalId(selectedPhoto)
    for _, publishedPhoto in ipairs(getPublishedPhotos(collection)) do
        local p = publishedPhoto and publishedPhoto:getPhoto()
        if p == selectedPhoto then
            return publishedPhoto
        end
        if selectedId and getPhotoLocalId(p) == selectedId then
            return publishedPhoto
        end
    end
    return nil
end

-- Build a stable grouping key for one Immich service configuration.
local function buildServiceGroupKey(service, url, apiKey)
    local serviceId = service and service.localIdentifier and tostring(service.localIdentifier) or ""
    if serviceId ~= "" then
        return serviceId
    end
    return tostring(url) .. "|" .. tostring(apiKey)
end

-- Read description from caption metadata.
local function getPhotoDescription(photo)
    local description = trimString(photo:getFormattedMetadata("caption"))
    if description ~= nil then
        return description
    end

    -- Some catalogs expose the user-visible description under title/headline instead of caption.
    return trimString(photo:getFormattedMetadata("title")) or trimString(photo:getFormattedMetadata("headline"))
end

-- Read latitude/longitude from Lightroom metadata.
local function getPhotoCoordinates(photo)
    local latitude, longitude = nil, nil

    local gps = photo:getRawMetadata("gps")
    if gps then
        latitude = gps.latitude
        longitude = gps.longitude
    end

    return latitude, longitude
end

-- Build full keyword path from root to current keyword.
local function keywordPathParts(keyword)
    local parts = {}
    local current = keyword
    local guard = 0
    while current and guard < 64 do
        guard = guard + 1
        local name = (type(current.getName) == "function") and current:getName() or nil
        if name and name ~= "" then
            table.insert(parts, 1, name)
        end
        if type(current.getParent) == "function" then
            current = current:getParent()
        else
            current = nil
        end
    end
    return parts
end

-- Return de-duplicated keyword paths assigned to photo.
local function getAssignedKeywordPaths(photo)
    local keywordObjs = photo:getRawMetadata("keywords")
    if type(keywordObjs) ~= "table" then
        return {}
    end

    local unique = {}
    local paths = {}
    for _, keyword in ipairs(keywordObjs) do
        if keyword then
            local parts = keywordPathParts(keyword)
            if #parts > 0 then
                local key = string.lower(table.concat(parts, "\t"))
                if not unique[key] then
                    unique[key] = true
                    table.insert(paths, parts)
                end
            end
        end
    end

    table.sort(paths, function(a, b)
        return table.concat(a, " > ") < table.concat(b, " > ")
    end)
    return paths
end

-- Build lookup for existing tags by name+parent context.
local function buildTagLookup(tags)
    local lookup = {}
    for _, tag in ipairs(tags or {}) do
        local name = trimString(tag and tag.name)
        if name then
            local key = string.lower(name) .. "|" .. normalizeParentId(tag and tag.parentId)
            if lookup[key] == nil then
                lookup[key] = tag
            end
        end
    end
    return lookup
end

-- Ensure one keyword path exists in Immich; return leaf tag id.
local function ensureTagPath(immich, tagLookup, pathParts)
    local parentId = ""
    local leafId = nil

    for _, name in ipairs(pathParts) do
        local n = trimString(name)
        if n and n ~= "" then
            local lookupKey = string.lower(n) .. "|" .. parentId
            local existing = tagLookup[lookupKey]
            if existing == nil then
                local created = immich:createTag(n, parentId ~= "" and parentId or nil)
                if not created or not created.id then
                    return nil
                end
                existing = created
                tagLookup[lookupKey] = created
            end
            leafId = tostring(existing.id)
            parentId = leafId
        end
    end

    return leafId
end

-- Resolve/create tag IDs for photo keywords.
-- options.stripTagRootNode (bool): if true, remove the first element of each keyword path.
local function resolveTagIdsForPhoto(immich, tagLookup, photo, options)
    local paths = getAssignedKeywordPaths(photo)
    if #paths == 0 then
        return {}
    end

    local stripRoot = options and options.stripTagRootNode
    log:trace('MetadataSync resolveTagIdsForPhoto: stripRoot=' .. tostring(stripRoot) .. ' pathCount=' .. tostring(#paths))
    local ids = {}
    local seen = {}
    for _, parts in ipairs(paths) do
        local effectiveParts = parts
        if stripRoot and #parts > 1 then
            effectiveParts = {}
            for i = 2, #parts do effectiveParts[#effectiveParts + 1] = parts[i] end
        end
        log:trace('MetadataSync: tag path original=' .. table.concat(parts, '>') .. ' effective=' .. table.concat(effectiveParts, '>'))
        local id = ensureTagPath(immich, tagLookup, effectiveParts)
        if id and not seen[id] then
            seen[id] = true
            table.insert(ids, id)
        end
    end
    return ids
end

-- Collect selected photo -> published asset pairs, grouped by Immich service.
local function collectPairsGroupedByService(selectedPhotos)
    local groups = {}
    local totalPairs = 0
    local notPublishedCount = 0
    local unconfiguredServiceCount = 0

    log:trace('MetadataSync: matching selected photos to published Immich assets: selected=' .. tostring(#(selectedPhotos or {})))

    for _, photo in ipairs(selectedPhotos or {}) do
        local matchedForPhoto = false
        local collections = getContainedPublishedCollections(photo)
        local photoId = getPhotoLocalId(photo)
        local fileName = photo and photo:getFormattedMetadata("fileName") or "(unknown file)"

        for _, collection in ipairs(collections) do
            local service = collection and collection:getService()
            local collectionName = (collection and type(collection.getName) == 'function') and tostring(collection:getName()) or '(unnamed collection)'

            if util.isImmichPublishService(service) then
                local settings = getPublishSettings(service)
                local catalogService = findCatalogServiceByLocalIdentifier(service and service.localIdentifier)
                local catalogSettings = getPublishSettings(catalogService)
                local url, apiKey, stripTagRootNode = resolveServiceCredentials(settings, catalogSettings)

                if util.nilOrEmpty(url) or util.nilOrEmpty(apiKey) then
                    log:warn('MetadataSync: missing URL/API key for Immich service; collection skipped: ' .. collectionName)
                    unconfiguredServiceCount = unconfiguredServiceCount + 1
                else
                    local publishedPhoto = findPublishedPhotoInCollection(collection, photo)
                    local assetId = publishedPhoto and publishedPhoto:getRemoteId() or nil

                    if not util.nilOrEmpty(assetId) then
                        local groupKey = buildServiceGroupKey(service, url, apiKey)
                        if groups[groupKey] == nil then
                            groups[groupKey] = {
                                url = url,
                                apiKey = apiKey,
                                stripTagRootNode = (stripTagRootNode == true),
                                photos = {},
                                seenAssetIds = {},
                            }
                        elseif groups[groupKey].stripTagRootNode == false and stripTagRootNode == true then
                            -- Prefer true if any contributing publish service enables stripping.
                            groups[groupKey].stripTagRootNode = true
                        end

                        local assetKey = tostring(assetId)
                        if not groups[groupKey].seenAssetIds[assetKey] then
                            groups[groupKey].seenAssetIds[assetKey] = true
                            table.insert(groups[groupKey].photos, {
                                photo = photo,
                                assetId = assetKey,
                            })
                            totalPairs = totalPairs + 1
                        end
                        matchedForPhoto = true
                    end
                end
            end
        end

        if not matchedForPhoto then
            notPublishedCount = notPublishedCount + 1
        end
    end

    log:trace('MetadataSync: matching complete totalPairs=' .. tostring(totalPairs)
        .. ' notPublishedCount=' .. tostring(notPublishedCount)
        .. ' unconfiguredServiceCount=' .. tostring(unconfiguredServiceCount))

    return groups, totalPairs, notPublishedCount, unconfiguredServiceCount
end

-- Reuse sync logic for publish flow where we already have photo->asset mapping.
function MetadataSync.syncExportedPrimaryMap(immich, exportedPrimaryByPhoto, progress, progressState, options)
    local photoPairs = {}
    local seen = {}
    for _, row in pairs(exportedPrimaryByPhoto or {}) do
        local photo = row and row.photo
        local assetId = row and row.assetId and tostring(row.assetId) or nil
        if photo and not util.nilOrEmpty(assetId) and not seen[assetId] then
            seen[assetId] = true
            table.insert(photoPairs, { photo = photo, assetId = assetId })
        end
    end
    return MetadataSync.syncPhotoAssetPairs(immich, photoPairs, progress, progressState, options)
end

-- Sync metadata for a list of photo/asset pairs against one Immich host.
-- options (optional table): { stripTagRootNode = bool }
function MetadataSync.syncPhotoAssetPairs(immich, pairs, progress, progressState, options)
    local results = {
        processed = 0,
        updated = 0,
        tagged = 0,
        failedUpdate = 0,
        failedTagging = 0,
    }

    local tagLookup = buildTagLookup(immich:getTags() or {})

    for _, pair in ipairs(pairs or {}) do
        if progress and progress:isCanceled() then
            break
        end

        local photo = pair.photo
        local assetId = pair.assetId
        local fileName = photo and photo:getFormattedMetadata("fileName") or tostring(assetId)

        if progress then
            progress:setCaption("Sending metadata: " .. tostring(fileName))
        end

        local description = getPhotoDescription(photo)
        local latitude, longitude = getPhotoCoordinates(photo)

        local body = {}
        if description ~= nil then body.description = description end
        if latitude ~= nil then body.latitude = latitude end
        if longitude ~= nil then body.longitude = longitude end

        if next(body) ~= nil then
            if immich:updateAsset(assetId, body) then
                results.updated = results.updated + 1
            else
                results.failedUpdate = results.failedUpdate + 1
            end
        end

        local tagIds = resolveTagIdsForPhoto(immich, tagLookup, photo, options)
        if #tagIds > 0 then
            if immich:bulkTagAssets({ assetId }, tagIds) then
                results.tagged = results.tagged + 1
            else
                results.failedTagging = results.failedTagging + 1
            end
        end

        results.processed = results.processed + 1
        if progress and progressState then
            progressState.completed = progressState.completed + 1
            progress:setPortionComplete(progressState.completed, progressState.total)
        end
    end

    return results
end

-- Library menu entry point: send metadata for selected photos to corresponding published Immich assets.
function MetadataSync.sendForCurrentSelection()
    local catalog = LrApplication.activeCatalog()
    if not catalog then
        LrDialogs.message("No catalog", "Cannot access the active Lightroom catalog.", "critical")
        return
    end

    local selectedPhotos = catalog:getTargetPhotos() or {}
    if #selectedPhotos == 0 then
        LrDialogs.message("No selected images", "Select one or more images in Library before running this command.", "warning")
        return
    end

    local groups, totalPairs, notPublishedCount, unconfiguredServiceCount = collectPairsGroupedByService(selectedPhotos)
    if totalPairs == 0 then
        local lines = {
            "No selected photos could be matched to published Immich assets.",
            "Selected photos: " .. tostring(#selectedPhotos),
            "Not matched to published Immich assets: " .. tostring(notPublishedCount),
        }
        if unconfiguredServiceCount > 0 then
            table.insert(lines, "Immich publish services with missing URL/API key encountered: " .. tostring(unconfiguredServiceCount))
        end
        LrDialogs.message("No published Immich assets", table.concat(lines, "\n"), "warning")
        return
    end

    local progress = LrProgressScope {
        title = "Sending metadata to Immich for selected images"
    }
    local progressState = { completed = 0, total = totalPairs }

    local summary = {
        processed = 0,
        updated = 0,
        tagged = 0,
        failedUpdate = 0,
        failedTagging = 0,
        failedConnections = 0,
    }

    for _, group in pairs(groups) do
        if progress:isCanceled() then
            break
        end

        local immich = ImmichAPI:new(group.url, group.apiKey)
        if not immich:checkConnectivity() then
            summary.failedConnections = summary.failedConnections + #group.photos
            for _ = 1, #group.photos do
                progressState.completed = progressState.completed + 1
                progress:setPortionComplete(progressState.completed, progressState.total)
            end
        else
            local options = { stripTagRootNode = group.stripTagRootNode == true }
            log:trace('MetadataSync standalone sync options stripTagRootNode=' .. tostring(options.stripTagRootNode))
            local result = MetadataSync.syncPhotoAssetPairs(immich, group.photos, progress, progressState, options)
            summary.processed = summary.processed + result.processed
            summary.updated = summary.updated + result.updated
            summary.tagged = summary.tagged + result.tagged
            summary.failedUpdate = summary.failedUpdate + result.failedUpdate
            summary.failedTagging = summary.failedTagging + result.failedTagging
        end
    end

    progress:done()

    local body = {
        "Selected images: " .. tostring(#selectedPhotos),
        "Published assets matched: " .. tostring(totalPairs),
        "Assets updated (description/GPS): " .. tostring(summary.updated),
        "Assets tagged: " .. tostring(summary.tagged),
        "Failed updates: " .. tostring(summary.failedUpdate),
        "Failed tag operations: " .. tostring(summary.failedTagging),
    }

    if summary.failedConnections > 0 then
        table.insert(body, "Skipped due to connection failures: " .. tostring(summary.failedConnections))
    end
    if unconfiguredServiceCount > 0 then
        table.insert(body, "Immich publish services missing URL/API key encountered: " .. tostring(unconfiguredServiceCount))
    end
    if progress:isCanceled() then
        table.insert(body, "Operation canceled by user.")
    end

    LrDialogs.message("Immich metadata sync complete", table.concat(body, "\n"), "info")
end
