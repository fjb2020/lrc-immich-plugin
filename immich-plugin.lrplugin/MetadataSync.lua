---@diagnostic disable: undefined-global, duplicate-set-field

require "ImmichAPI"
require "util"

MetadataSync = {}

-- ***********************************************************
-- Basic string normalizer used by metadata and tag helpers.
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
-- Normalize nil/empty parent IDs so root matching is consistent.
-- ***********************************************************
local function normalizeParentId(parentId)
    if parentId == nil or parentId == "" then
        return ""
    end
    return tostring(parentId)
end

-- ***********************************************************
-- Return stable local-id key for photo matching.
-- ***********************************************************
local function getPhotoLocalId(photo)
    local localId = photo and photo.localIdentifier
    if localId ~= nil and localId ~= "" then
        return tostring(localId)
    end
    return nil
end

-- ***********************************************************
-- Read publish settings from a service.
-- ***********************************************************
local function getPublishSettings(service)
    if not service or type(service.getPublishSettings) ~= "function" then
        return nil
    end
    local settings = service:getPublishSettings()
    local effectiveSettings = util.getEffectivePropertyTable(settings)
    return effectiveSettings
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

local function resolveServiceCredentials(serviceSettings, catalogSettings)
    local urlKeys = { "url", "URL", "immichUrl", "immichURL", "LR_url", "LR_URL" }
    local apiKeyKeys = { "apiKey", "apikey", "APIKey", "immichApiKey", "immichAPIKey", "LR_apiKey", "LR_apikey" }
    local ignoreKeywordTreeKeys = { "ignoreKeywordTree", "LR_ignoreKeywordTree" }

    local url = readCredentialField(serviceSettings, urlKeys)
    local apiKey = readCredentialField(serviceSettings, apiKeyKeys)
    local ignoreKeywordTree = readCredentialField(serviceSettings, ignoreKeywordTreeKeys)
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
    if util.nilOrEmpty(ignoreKeywordTree) then
        ignoreKeywordTree = readCredentialField(catalogSettings, ignoreKeywordTreeKeys)
        if not util.nilOrEmpty(ignoreKeywordTree) then
            source = "catalog service settings"
        end
    end
    if util.nilOrEmpty(ignoreKeywordTree) and type(prefs) == "table" and type(prefs.ignoreKeywordTree) == "string" and trimString(prefs.ignoreKeywordTree) then
        ignoreKeywordTree = trimString(prefs.ignoreKeywordTree)
        source = "global prefs fallback"
    end

    return url, apiKey, ignoreKeywordTree, source
end

-- ***********************************************************
-- Produce a compact debug description of a publish-settings object.
-- Read published collections containing this photo.
-- ***********************************************************
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

-- ***********************************************************
-- Read published photos from a publish collection.
-- ***********************************************************
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

-- ***********************************************************
-- Read all publish services from the active catalog for diagnostics.
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
-- Find a catalog publish service with the same localIdentifier.
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
-- Find the published-photo object for a selected photo in one collection.
-- ***********************************************************
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

-- ***********************************************************
-- Build a stable grouping key for one Immich service configuration.
-- ***********************************************************
local function buildServiceGroupKey(service, url, apiKey)
    local serviceId = service and service.localIdentifier and tostring(service.localIdentifier) or ""
    if serviceId ~= "" then
        return serviceId
    end
    return tostring(url) .. "|" .. tostring(apiKey)
end

-- ***********************************************************
-- Read description from caption metadata.
-- ***********************************************************
local function getPhotoDescription(photo)
    local description = trimString(photo:getFormattedMetadata("caption"))
    if description ~= nil then
        return description
    end

    -- Some catalogs expose the user-visible description under title/headline instead of caption.
    return trimString(photo:getFormattedMetadata("title")) or trimString(photo:getFormattedMetadata("headline"))
end

-- ***********************************************************
-- Read latitude/longitude from Lightroom metadata.
-- ***********************************************************
local function getPhotoCoordinates(photo)
    local latitude, longitude = nil, nil

    local gps = photo:getRawMetadata("gps")
    if gps then
        latitude = gps.latitude
        longitude = gps.longitude
    end

    return latitude, longitude
end

-- ***********************************************************
local function toNumber(value)
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" then
        return tonumber(trimString(value))
    end
    return nil
end

-- ***********************************************************
-- Read description from Immich asset payload.
-- ***********************************************************
local function getAssetDescription(assetInfo)
    if type(assetInfo) ~= "table" then
        return nil
    end
    local exifInfo = assetInfo.exifInfo or {}
    return trimString(assetInfo.description) or trimString(exifInfo.description) or nil
end

-- ***********************************************************
-- Read latitude/longitude from Immich asset payload.
-- ***********************************************************
local function getAssetCoordinates(assetInfo)
    if type(assetInfo) ~= "table" then
        return nil, nil
    end

    local latitude = toNumber(assetInfo.latitude)
    local longitude = toNumber(assetInfo.longitude)

    if latitude == nil or longitude == nil then
        local exifInfo = assetInfo.exifInfo
        if type(exifInfo) == "table" then
            latitude = latitude or toNumber(exifInfo.latitude)
            longitude = longitude or toNumber(exifInfo.longitude)
        end
    end

    if latitude == nil or longitude == nil then
        return nil, nil
    end

    return latitude, longitude
end

-- ***********************************************************
local function extractLeafNameFromTag(tag)
    local name = trimString(tag and tag.name)
    if name then
        return name
    end

    local fullValue = trimString(tag and tag.value)
    if not fullValue then
        return nil
    end

    -- Immich may expose full paths in different separators; keep only the leaf.
    local leaf = fullValue
    leaf = leaf:gsub("^.* > ", "")
    leaf = leaf:gsub("^.*|", "")
    leaf = leaf:gsub("^.*/", "")
    leaf = leaf:gsub("^.*\\", "")
    return trimString(leaf)
end

-- ***********************************************************
local function getAssetLeafTagNames(assetInfo)
    local leafNames = {}
    local seen = {}

    if type(assetInfo) ~= "table" or type(assetInfo.tags) ~= "table" then
        return leafNames
    end

    for _, tag in ipairs(assetInfo.tags) do
        local leaf = extractLeafNameFromTag(tag)
        if leaf then
            local key = string.lower(leaf)
            if not seen[key] then
                seen[key] = true
                table.insert(leafNames, leaf)
            end
        end
    end

    table.sort(leafNames, function(a, b)
        return string.lower(a) < string.lower(b)
    end)
    return leafNames
end

-- ***********************************************************
-- Build full keyword path from root to current keyword.
-- ***********************************************************
local function keywordPathParts(keyword)
    local parts = {}
    local current = keyword
    local guard = 0
    while current and guard < 64 do
        guard = guard + 1
        table.insert(parts, 1, current)
        if type(current.getParent) == "function" then
            current = current:getParent()
        else
            current = nil
        end
    end
    return parts
end

-- ***********************************************************
local function getKeywordIncludeOnExport(keyword)
    if not keyword or type(keyword.getAttributes) ~= "function" then
        return true
    end

    local attrs = keyword:getAttributes()
    if type(attrs) ~= "table" then
        return true
    end

    if type(attrs.includeOnExport) == "boolean" then
        return attrs.includeOnExport
    end
    return true
end

-- ***********************************************************
local function parseIgnoreKeywordTree(ignoreKeywordTree)
    local lookup = {}
    if type(ignoreKeywordTree) ~= "string" then
        return lookup
    end

    for token in string.gmatch(ignoreKeywordTree, "([^,]+)") do
        local name = trimString(token)
        if name then
            lookup[string.lower(name)] = true
        end
    end

    return lookup
end

-- ***********************************************************
local function applyKeywordExportRules(pathParts, ignoredRoots)
    local filtered = {}
    for _, part in ipairs(pathParts or {}) do
        local includePart = (part.includeOnExport ~= false)
        if ignoredRoots[string.lower(part.name or "")] then
            return {}
        end

        if includePart and part.name then
            table.insert(filtered, part.name)
        end
    end
    return filtered
end

-- ***********************************************************
-- Return de-duplicated keyword paths assigned to photo.
-- ***********************************************************
local function getAssignedKeywordPaths(photo, ignoredRoots)
    local keywordObjs = photo:getRawMetadata("keywords")
    if type(keywordObjs) ~= "table" then
        return {}
    end

    local unique = {}
    local paths = {}
    for _, keyword in ipairs(keywordObjs) do
        if keyword then
            local pathKeywords = keywordPathParts(keyword)
            local parts = {}
            for _, partKeyword in ipairs(pathKeywords) do
                local partName = trimString(partKeyword:getName())
                if partName then
                    table.insert(parts, {
                        name = partName,
                        includeOnExport = getKeywordIncludeOnExport(partKeyword),
                    })
                end
            end

            local effectiveParts = applyKeywordExportRules(parts, ignoredRoots)
            if #effectiveParts > 0 then
                local key = string.lower(table.concat(effectiveParts, "\t"))
                if not unique[key] then
                    unique[key] = true
                    table.insert(paths, effectiveParts)
                end
            end
        end
    end

    table.sort(paths, function(a, b)
        return table.concat(a, " > ") < table.concat(b, " > ")
    end)
    return paths
end


-- ***********************************************************
-- Build lookup for existing tags by name+parent context.
-- ***********************************************************
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

-- ***********************************************************
-- Ensure one keyword path exists in Immich; return leaf tag id.
-- ***********************************************************
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

local function resolveTagIdsForPhotoWithIgnoredRoots(immich, tagLookup, photo, ignoredRoots)
    local paths = getAssignedKeywordPaths(photo, ignoredRoots)
    if #paths == 0 then
        return {}
    end

    local ids = {}
    local seen = {}
    for _, parts in ipairs(paths) do
        local effectiveParts = parts
        log:trace('MetadataSync: tag path original=' ..
            table.concat(parts, '>') .. ' effective=' .. table.concat(effectiveParts, '>'))
        local id = ensureTagPath(immich, tagLookup, effectiveParts)
        if id and not seen[id] then
            seen[id] = true
            table.insert(ids, id)
        end
    end
    return ids
end

-- ***********************************************************
local function getKeywordNameSafe(keyword)
    if not keyword or type(keyword.getName) ~= "function" then
        return nil
    end
    local value = keyword:getName()
    return trimString(value)
end

-- ***********************************************************
local function getKeywordChildrenSafe(keyword)
    if not keyword or type(keyword.getChildren) ~= "function" then
        return {}
    end
    local children = keyword:getChildren()
    if type(children) ~= "table" then
        return {}
    end
    return children
end

-- ***********************************************************
local function appendKeywordToLeafIndex(leafIndex, keyword, explicitName)
    if type(leafIndex) ~= "table" or not keyword then
        return
    end

    local name = trimString(explicitName) or getKeywordNameSafe(keyword)
    if not name then
        return
    end

    local key = string.lower(name)
    if leafIndex[key] == nil then
        leafIndex[key] = {}
    end
    table.insert(leafIndex[key], keyword)
end

-- ***********************************************************
local function indexKeywordTreeByLeaf(leafIndex, keyword)
    if not keyword then
        return
    end

    appendKeywordToLeafIndex(leafIndex, keyword)

    for _, child in ipairs(getKeywordChildrenSafe(keyword)) do
        indexKeywordTreeByLeaf(leafIndex, child)
    end
end

-- ***********************************************************
local function buildKeywordLeafIndex(catalog)
    local index = {}
    local roots = (catalog and type(catalog.getKeywords) == "function") and catalog:getKeywords() or {}
    for _, keyword in ipairs(roots or {}) do
        indexKeywordTreeByLeaf(index, keyword)
    end
    return index
end

-- ***********************************************************
local function findDirectChildKeyword(parentKeyword, childName)
    local wanted = trimString(childName)
    if not wanted then
        return nil
    end

    local children = {}
    if parentKeyword and type(parentKeyword.getChildren) == "function" then
        children = parentKeyword:getChildren() or {}
    else
        local catalog = LrApplication.activeCatalog()
        children = (catalog and type(catalog.getKeywords) == "function") and (catalog:getKeywords() or {}) or {}
    end

    local wantedLower = string.lower(wanted)
    for _, child in ipairs(children) do
        local childNameValue = getKeywordNameSafe(child)
        if childNameValue and string.lower(childNameValue) == wantedLower then
            return child
        end
    end

    return nil
end

-- ***********************************************************
local function createKeywordSafe(catalog, keywordName, parentKeyword)
    if not catalog or type(catalog.createKeyword) ~= "function" then
        return nil
    end

    local name = trimString(keywordName)
    if not name then
        return nil
    end

    local attempts = {
        function() return catalog:createKeyword(name, {}, false, parentKeyword, true) end,
        function() return catalog:createKeyword(name, nil, false, parentKeyword, true) end,
        function() return catalog:createKeyword(name, {}, false, parentKeyword) end,
        function() return catalog:createKeyword(name, nil, false, parentKeyword) end,
    }

    for _, attempt in ipairs(attempts) do
        local ok, created = LrTasks.pcall(attempt)
        if ok and created then
            return created
        end
    end

    return nil
end

-- ***********************************************************
local function ensureLrKeywordPath(catalog, leafIndex, pathParts)
    local currentParent = nil

    for _, rawName in ipairs(pathParts or {}) do
        local name = trimString(rawName)
        if name and name ~= "" then
            local keyword = findDirectChildKeyword(currentParent, name)
            if not keyword then
                keyword = createKeywordSafe(catalog, name, currentParent)
                if not keyword then
                    return nil
                end
                appendKeywordToLeafIndex(leafIndex, keyword, name)
            end
            currentParent = keyword
        end
    end

    return currentParent
end

-- ***********************************************************
local function buildAssignedKeywordSet(photo)
    local assigned = {}
    local keywords = photo and photo:getRawMetadata("keywords") or nil
    if type(keywords) ~= "table" then
        return assigned
    end
    for _, keyword in ipairs(keywords) do
        assigned[tostring(keyword)] = true
    end
    return assigned
end

-- ***********************************************************
local function addKeywordToPhoto(photo, keyword, assignedKeywordSet)
    if not photo or not keyword then
        return false
    end
    local keywordKey = keyword:getName() or ""
    if assignedKeywordSet and assignedKeywordSet[keywordKey] then
        return false
    end

    local added = false

    photo:addKeyword(keyword)
    added = true


    if added and assignedKeywordSet then
        assignedKeywordSet[keywordKey] = true
    end
    return added
end

-- ***********************************************************
-- Collect selected photo -> published asset pairs, grouped by Immich service.
-- ***********************************************************
local function collectPairsGroupedByService(selectedPhotos)
    local groups = {}
    local totalPairs = 0
    local notPublishedCount = 0
    local unconfiguredServiceCount = 0

    log:trace('MetadataSync: matching selected photos to published Immich assets: selected=' ..
        tostring(#(selectedPhotos or {})))

    for _, photo in ipairs(selectedPhotos or {}) do
        local matchedForPhoto = false
        local collections = getContainedPublishedCollections(photo)
        local photoId = getPhotoLocalId(photo)
        local fileName = photo and photo:getFormattedMetadata("fileName") or "(unknown file)"

        for _, collection in ipairs(collections) do
            local service = collection and collection:getService()
            local collectionName = (collection and type(collection.getName) == 'function') and
                tostring(collection:getName()) or '(unnamed collection)'

            if util.isImmichPublishService(service) then
                local settings = getPublishSettings(service)
                local catalogService = findCatalogServiceByLocalIdentifier(service and service.localIdentifier)
                local catalogSettings = getPublishSettings(catalogService)
                local url, apiKey, ignoreKeywordTree = resolveServiceCredentials(settings, catalogSettings)

                if util.nilOrEmpty(url) or util.nilOrEmpty(apiKey) then
                    log:warn('MetadataSync: missing URL/API key for Immich service; collection skipped: ' ..
                        collectionName)
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
                                ignoreKeywordTree = ignoreKeywordTree,
                                photos = {},
                                seenAssetIds = {},
                            }
                        elseif util.nilOrEmpty(groups[groupKey].ignoreKeywordTree) and
                            not util.nilOrEmpty(ignoreKeywordTree) then
                            groups[groupKey].ignoreKeywordTree = ignoreKeywordTree
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

-- ***********************************************************
-- Reuse sync logic for publish flow where we already have photo->asset mapping.
-- ***********************************************************
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

-- ***********************************************************
-- Sync metadata for a list of photo/asset pairs against one Immich host.
-- ***********************************************************
function MetadataSync.syncPhotoAssetPairs(immich, pairs, progress, progressState, options)
    local results = {
        processed = 0,
        updated = 0,
        tagged = 0,
        failedUpdate = 0,
        failedTagging = 0,
    }

    local ignoredRoots = parseIgnoreKeywordTree(options and options.ignoreKeywordTree)

    local tagLookup = buildTagLookup(immich:getTags() or {})

    for _, pair in ipairs(pairs or {}) do
        if progress and progress:isCanceled() then
            break
        end

        local photo = pair.photo     -- LrC photo object
        local assetId = pair.assetId -- Immich asset ID as string
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

        local tagIds = resolveTagIdsForPhotoWithIgnoredRoots(immich, tagLookup, photo, ignoredRoots)
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

-- ***********************************************************
-- Pull metadata from Immich back into Lightroom for one Immich host.
-- ***********************************************************
function MetadataSync.pullPhotoAssetPairs(immich, pairs, progress, progressState)
    local catalog = LrApplication.activeCatalog()
    local results = {
        processed = 0,
        updatedCaption = 0,
        updatedGps = 0,
        keywordsAdded = 0,
        missingKeywordsCreated = 0,
        duplicateKeywordsRouted = 0,
        failedAssetReads = 0,
        failedWrites = 0,
    }

    if not catalog then
        results.failedWrites = #(pairs or {})
        return results
    end

    -- Build index of existing keywords by leaf name for efficient lookup during sync.
    local leafIndex = buildKeywordLeafIndex(catalog)

    for _, pair in ipairs(pairs or {}) do
        -- for each photo/asset pair, pull metadata from Immich and apply to Lightroom photo; create keywords as needed
        if progress and progress:isCanceled() then
            break
        end

        local photo = pair.photo
        local assetId = pair.assetId
        local fileName = photo and photo:getFormattedMetadata("fileName") or tostring(assetId)
        if progress then
            progress:setCaption("Pulling metadata: " .. tostring(fileName))
        end

        local assetInfo = immich:getAssetInfo(assetId)
        if type(assetInfo) ~= "table" then
            results.failedAssetReads = results.failedAssetReads + 1
            results.processed = results.processed + 1
            if progress and progressState then
                progressState.completed = progressState.completed + 1
                progress:setPortionComplete(progressState.completed, progressState.total)
            end
        else

            local description = getAssetDescription(assetInfo)
            local latitude, longitude = getAssetCoordinates(assetInfo)
            local leafTagNames = getAssetLeafTagNames(assetInfo)

            local ok, err = LrTasks.pcall(function()
                catalog:withWriteAccessDo("Pull metadata from Immich", function()
                    if description ~= nil then
                        photo:setRawMetadata("title", description)
                        results.updatedCaption = results.updatedCaption + 1
                    end

                    if latitude ~= nil and longitude ~= nil then
                        photo:setRawMetadata("gps", { latitude = latitude, longitude = longitude })
                        results.updatedGps = results.updatedGps + 1
                    end

                    local assignedKeywordSet = buildAssignedKeywordSet(photo)
                    for _, leafName in ipairs(leafTagNames) do
                        local key = string.lower(leafName)
                        local matches = leafIndex[key] or {}
                        local targetKeyword = nil
                        local addKwToPhotoFlag = false
                        log:trace('MetadataSync pull processing tag for assetId=' ..
                            tostring(assetId) ..
                            ': leafName=' .. tostring(leafName) .. ' matchCount=' .. tostring(#matches))
                        if #matches == 1 then
                            -- only add keywords to photo if there's exactly one match in the catalog to avoid accidental mis-tagging; route to Missing/Duplicates if no or multiple matches    
                            targetKeyword = matches[1]
                            addKwToPhotoFlag = true
                        elseif #matches == 0 then
                            targetKeyword = ensureLrKeywordPath(catalog, leafIndex,
                                { "~Metadata", "ImmichKwSync", "Missing", leafName })
                            if targetKeyword then
                                results.missingKeywordsCreated = results.missingKeywordsCreated + 1
                            end
                        else
                            targetKeyword = ensureLrKeywordPath(catalog, leafIndex,
                                { "~Metadata", "ImmichKwSync", "Duplicates", leafName })
                            if targetKeyword then
                                results.duplicateKeywordsRouted = results.duplicateKeywordsRouted + 1
                            end
                        end
                        
                        if addKwToPhotoFlag then
                            if addKeywordToPhoto(photo, targetKeyword, assignedKeywordSet) then
                                results.keywordsAdded = results.keywordsAdded + 1
                            end
                        end
                    end
                end, { timeout = 30 })
            end)

            if not ok then
                log:warn('MetadataSync pull write failed for assetId=' .. tostring(assetId) .. ': ' .. tostring(err))
                results.failedWrites = results.failedWrites + 1
            end

            results.processed = results.processed + 1
            if progress and progressState then
                progressState.completed = progressState.completed + 1
                progress:setPortionComplete(progressState.completed, progressState.total)
            end
        end
    end

    return results
end

-- ***********************************************************
-- Library menu entry point: push/pull metadata for selected photos to corresponding published Immich assets.
-- ***********************************************************
function MetadataSync.syncForCurrentSelection(syncDirection)
    local catalog = LrApplication.activeCatalog()
    if not catalog then
        LrDialogs.message("No catalog", "Cannot access the active Lightroom catalog.", "critical")
        return
    end

    local selectedPhotos = catalog:getTargetPhotos() or {}
    if #selectedPhotos == 0 then
        LrDialogs.message("No selected images", "Select one or more images in Library before running this command.",
            "warning")
        return
    end

    if syncDirection ~= "pull" and syncDirection ~= "push" then
        LrDialogs.message("Unsupported sync direction",
            "The specified sync direction is not supported. Please use 'pull' or 'push'.", "info")
        return
    end

    local groups, totalPairs, notPublishedCount, unconfiguredServiceCount = collectPairsGroupedByService(selectedPhotos)
    -- build table of lrPhoto <-> Immich asset ID pairs, grouped by Immich service config (URL+API key)
    --
    if totalPairs == 0 then
        local lines = {
            "No selected photos could be matched to published Immich assets.",
            "Selected photos: " .. tostring(#selectedPhotos),
            "Not matched to published Immich assets: " .. tostring(notPublishedCount),
        }
        if unconfiguredServiceCount > 0 then
            table.insert(lines,
                "Immich publish services with missing URL/API key encountered: " .. tostring(unconfiguredServiceCount))
        end
        LrDialogs.message("No published Immich assets", table.concat(lines, "\n"), "warning")
        return
    end

    local operation = (syncDirection == "pull") and "Pulling" or "Sending"

    local progress = LrProgressScope {
        title = "Sync Metadata: " .. operation .. " metadata for selected images to Immich"
    }
    local progressState = { completed = 0, total = totalPairs }

    local pushSummary = {
        processed = 0,
        updated = 0,
        tagged = 0,
        failedUpdate = 0,
        failedTagging = 0,
        failedConnections = 0,
    }
    local pullSummary = {
        processed = 0,
        updatedCaption = 0,
        updatedGps = 0,
        keywordsAdded = 0,
        missingKeywordsCreated = 0,
        duplicateKeywordsRouted = 0,
        failedAssetReads = 0,
        failedWrites = 0,
        failedConnections = 0,
    }

    for _, group in pairs(groups) do
        -- each group corresponds to one Immich service (unique URL+API key) and contains all photo/asset pairs matching that service
        if progress:isCanceled() then
            break
        end

        local immich = ImmichAPI:new(group.url, group.apiKey)
        if not immich:checkConnectivity() then
            pushSummary.failedConnections = pushSummary.failedConnections + #group.photos
            pullSummary.failedConnections = pullSummary.failedConnections + #group.photos
            for _ = 1, #group.photos do
                progressState.completed = progressState.completed + 1
                progress:setPortionComplete(progressState.completed, progressState.total)
            end
        else
            if syncDirection == "pull" then
                local result = MetadataSync.pullPhotoAssetPairs(immich, group.photos, progress, progressState)
                pullSummary.processed = pullSummary.processed + result.processed
                pullSummary.updatedCaption = pullSummary.updatedCaption + result.updatedCaption
                pullSummary.updatedGps = pullSummary.updatedGps + result.updatedGps
                pullSummary.keywordsAdded = pullSummary.keywordsAdded + result.keywordsAdded
                pullSummary.missingKeywordsCreated = pullSummary.missingKeywordsCreated + result.missingKeywordsCreated
                pullSummary.duplicateKeywordsRouted = pullSummary.duplicateKeywordsRouted +
                    result.duplicateKeywordsRouted
                pullSummary.failedAssetReads = pullSummary.failedAssetReads + result.failedAssetReads
                pullSummary.failedWrites = pullSummary.failedWrites + result.failedWrites
            else
                local options = {
                    ignoreKeywordTree = group.ignoreKeywordTree,
                }
                local result = MetadataSync.syncPhotoAssetPairs(immich, group.photos, progress, progressState, options)
                pushSummary.processed = pushSummary.processed + result.processed
                pushSummary.updated = pushSummary.updated + result.updated
                pushSummary.tagged = pushSummary.tagged + result.tagged
                pushSummary.failedUpdate = pushSummary.failedUpdate + result.failedUpdate
                pushSummary.failedTagging = pushSummary.failedTagging + result.failedTagging
            end
        end
    end

    progress:done()
    local body
    if syncDirection == "pull" then
        body = {
            "Selected images: " .. tostring(#selectedPhotos),
            "Published assets matched: " .. tostring(totalPairs),
            "Assets processed: " .. tostring(pullSummary.processed),
            "Captions updated from Immich: " .. tostring(pullSummary.updatedCaption),
            "GPS updated from Immich: " .. tostring(pullSummary.updatedGps),
            "Keywords added: " .. tostring(pullSummary.keywordsAdded),
            "Missing keywords created under ~Metadata|ImmichKwSync|Missing: " ..
            tostring(pullSummary.missingKeywordsCreated),
            "Duplicate leaf tags routed to ~Metadata|ImmichKwSync|Duplicates: " ..
            tostring(pullSummary.duplicateKeywordsRouted),
            "Failed asset reads: " .. tostring(pullSummary.failedAssetReads),
            "Failed Lightroom writes: " .. tostring(pullSummary.failedWrites),
        }
    else
        body = {
            "Selected images: " .. tostring(#selectedPhotos),
            "Published assets matched: " .. tostring(totalPairs),
            "Assets updated (description/GPS): " .. tostring(pushSummary.updated),
            "Assets tagged: " .. tostring(pushSummary.tagged),
            "Failed updates: " .. tostring(pushSummary.failedUpdate),
            "Failed tag operations: " .. tostring(pushSummary.failedTagging),
        }
    end
    if pullSummary.failedConnections > 0 then
        table.insert(body, "Skipped due to connection failures: " .. tostring(pullSummary.failedConnections))
    end
    if unconfiguredServiceCount > 0 then
        table.insert(body,
            "Immich publish services missing URL/API key encountered: " .. tostring(unconfiguredServiceCount))
    end
    if progress:isCanceled() then
        table.insert(body, "Operation canceled by user.")
    end

    LrDialogs.message("Immich metadata sync complete", table.concat(body, "\n"), "info")
end
