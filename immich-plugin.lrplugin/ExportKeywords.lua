---@diagnostic disable: undefined-global

require "ImmichAPI"

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- Collect all keywords in the catalog into a flat list, sorted alphabetically
-- by their full path (e.g. "Animals > Birds > Robin").
local function collectAllKeywords()
    local catalog = LrApplication.activeCatalog()
    local keywords = catalog:getKeywords()

    local items = {}

    local function walk(keyword, parentPath)
        local name = keyword:getName()
        local fullPath = parentPath ~= "" and (parentPath .. " > " .. name) or name
        table.insert(items, { title = fullPath, value = keyword, name = name, path = fullPath })
        for _, child in ipairs(keyword:getChildren()) do
            walk(child, fullPath)
        end
    end

    for _, kw in ipairs(keywords) do
        walk(kw, "")
    end

    table.sort(items, function(a, b) return a.path < b.path end)
    return items
end

-- Count how many keywords will be processed (root + descendants if recurse).
local function countKeywords(keyword, recurse)
    local count = 1
    if recurse then
        for _, child in ipairs(keyword:getChildren()) do
            count = count + countKeywords(child, true)
        end
    end
    return count
end

-- Compatibility wrapper: use ImmichAPI:deleteTag when available, otherwise
-- fall back to the underlying custom request method.
local function deleteTagCompat(immich, tagId)
    if util.nilOrEmpty(tagId) then
        return false
    end

    if type(immich.deleteTag) == "function" then
        return immich:deleteTag(tagId)
    end

    if immich.url and immich.apiBasePath and type(immich.createHeaders) == "function" then
        local response, headers = LrHttp.post(
            immich.url .. immich.apiBasePath .. '/tags/' .. tostring(tagId),
            '',
            immich:createHeaders(),
            'DELETE'
        )
        return headers and (headers.status == 204 or headers.status == 200)
    end

    log:warn('ExportKeywords: no tag deletion method available in ImmichAPI')
    return false
end

local function formatTagDetails(tag)
    if type(tag) ~= "table" then
        return tostring(tag)
    end

    return string.format(
        'id=%s, name=%s, value=%s, parentId=%s, createdAt=%s, updatedAt=%s',
        tostring(tag.id),
        tostring(tag.name),
        tostring(tag.value),
        tostring(tag.parentId),
        tostring(tag.createdAt),
        tostring(tag.updatedAt)
    )
end

local function normalizeParentId(parentId)
    if parentId == nil or parentId == "" then
        return nil
    end
    return tostring(parentId)
end

local function getTargetParentId(parentTagId, options)
    if options and options.ignoreHierarchy then
        return nil
    end
    return normalizeParentId(parentTagId)
end

-- Returns only same-name tags that belong to the target parent context.
local function filterTagsForTargetParent(existingList, targetParentId)
    local matches = {}
    for _, existing in ipairs(existingList or {}) do
        local existingParentId = normalizeParentId(existing and existing.parentId)
        if existingParentId == targetParentId then
            table.insert(matches, existing)
        end
    end
    return matches
end

-- After a successful delete, Immich may cascade-delete child tags. Since we only
-- load tags once at the start, prune that entire subtree from our in-memory map
-- so we don't attempt to delete already-removed children later in the run.
local function pruneDeletedSubtreeFromMap(existingByName, deletedRootId)
    if util.nilOrEmpty(deletedRootId) then
        return 0
    end

    local idsToDrop = { [tostring(deletedRootId)] = true }
    local changed = true

    while changed do
        changed = false
        for _, tagList in pairs(existingByName) do
            for _, tag in ipairs(tagList) do
                local tagId = tag and tag.id and tostring(tag.id) or nil
                local parentId = tag and tag.parentId and tostring(tag.parentId) or nil
                if tagId and parentId and idsToDrop[parentId] and not idsToDrop[tagId] then
                    idsToDrop[tagId] = true
                    changed = true
                end
            end
        end
    end

    local removedCount = 0
    for key, tagList in pairs(existingByName) do
        local kept = {}
        for _, tag in ipairs(tagList) do
            local tagId = tag and tag.id and tostring(tag.id) or nil
            if tagId and idsToDrop[tagId] then
                removedCount = removedCount + 1
            else
                table.insert(kept, tag)
            end
        end
        existingByName[key] = kept
    end

    return removedCount
end

-- Export a keyword (and optionally all children) to Immich.
-- immich         : ImmichAPI instance
-- keyword        : LrKeyword object to export
-- parentTagId    : Immich tag id of the already-created parent, or nil for top-level
-- existingByName : map of lowercase tag name → Immich tag object (for dedup)
-- results        : accumulator table { created, skipped, failed }
-- recurse        : boolean – if false, only the root keyword is exported
-- progress       : LrProgressScope to update after each keyword
-- progressState  : table { completed = number, total = number }
-- options        : table { deleteExistingMatching = boolean, ignoreHierarchy = boolean }
-- createdTagIds  : set of tag IDs created in this run
local function exportKeywordTree(immich, keyword, parentTagId, existingByName, results, recurse, progress, progressState, options, createdTagIds)
    if progress:isCanceled() then return end

    local name = keyword:getName()
    local key  = string.lower(name)

    local tagId

    progress:setCaption(name)

    local allSameNameTags = existingByName[key] or {}
    local targetParentId = getTargetParentId(parentTagId, options)
    local matchingTagsForTargetParent = filterTagsForTargetParent(allSameNameTags, targetParentId)

    if options.deleteExistingMatching then
        local kept = {}
        for _, existing in ipairs(allSameNameTags) do
            local existingId = existing and existing.id and tostring(existing.id) or nil
            local existingParentId = normalizeParentId(existing and existing.parentId)

            -- Keep same-name tags outside the target parent context untouched.
            if existingParentId ~= targetParentId then
                table.insert(kept, existing)
            elseif existingId and createdTagIds[existingId] then
                table.insert(kept, existing)
            elseif existingId then
                if deleteTagCompat(immich, existingId) then
                    results.deleted = results.deleted + 1
                    local pruned = pruneDeletedSubtreeFromMap(existingByName, existingId)
                    if pruned > 1 then
                    end
                else
                    log:warn('ExportKeywords: delete failed for keyword "' .. name .. '": ' .. formatTagDetails(existing))
                    results.failedDeletes = results.failedDeletes + 1
                    table.insert(kept, existing)
                end
            end
        end
        existingByName[key] = kept
        matchingTagsForTargetParent = filterTagsForTargetParent(kept, targetParentId)
    end

    if (not options.deleteExistingMatching) and #matchingTagsForTargetParent > 0 then
        log:trace('ExportKeywords: skipping existing tag "' .. name .. '"')
        tagId = matchingTagsForTargetParent[1].id
        results.skipped = results.skipped + 1
    else
        local effectiveParentTagId = targetParentId
        local created = immich:createTag(name, effectiveParentTagId)
        if created and created.id then
            local createdId = tostring(created.id)
            tagId = createdId
            if existingByName[key] == nil then
                existingByName[key] = {}
            end
            table.insert(existingByName[key], created)
            createdTagIds[createdId] = true
            results.created = results.created + 1
        else
            log:warn('ExportKeywords: failed to create tag "' .. name .. '"')
            results.failed = results.failed + 1
            tagId = nil
        end
    end

    progressState.completed = progressState.completed + 1
    progress:setPortionComplete(progressState.completed, progressState.total)

    if recurse then
        for _, child in ipairs(keyword:getChildren()) do
            if progress:isCanceled() then return end
            local childParentId = options.ignoreHierarchy and nil or tagId
            exportKeywordTree(immich, child, childParentId, existingByName, results, true, progress, progressState, options, createdTagIds)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Entry point (called by Lightroom as a menu item)
-- ---------------------------------------------------------------------------

return {
    LrTasks.startAsyncTask(function()

        -- Validate configuration
        if util.nilOrEmpty(prefs.url) or util.nilOrEmpty(prefs.apiKey) then
            LrDialogs.message(
                "Immich not configured",
                "Please configure the Immich URL and API key in the plugin settings before exporting keywords.",
                "critical"
            )
            return
        end

        local immich = ImmichAPI:new(prefs.url, prefs.apiKey)
        if not immich:checkConnectivity() then
            LrDialogs.message(
                "Connection failed",
                "Cannot reach the Immich server. Check your URL and API key in the plugin settings.",
                "critical"
            )
            return
        end

        -- Build keyword list for the popup
        local keywordItems = collectAllKeywords()
        if #keywordItems == 0 then
            LrDialogs.message(
                "No keywords",
                "No keywords were found in the Lightroom catalog.",
                "warning"
            )
            return
        end

        -- Build popup items: each entry has title = full path, value = index into keywordItems
        local popupItems = {}
        for i, item in ipairs(keywordItems) do
            table.insert(popupItems, { title = item.title, value = i })
        end

        -- Dialog state and result
        local selectedIndex = 1
        local includeChildren = true
        local deleteExistingMatching = false
        local ignoreHierarchy = false

        local result = LrFunctionContext.callWithContext('ExportKeywordsDialog', function(context)
            local props = LrBinding.makePropertyTable(context)
            props.selectedIndex = selectedIndex
            props.includeChildren = true
            props.deleteExistingMatching = deleteExistingMatching
            props.ignoreHierarchy = ignoreHierarchy

            local f = LrView.osFactory()
            local contents = f:column {
                bind_to_object = props,
                spacing = f:control_spacing(),
                f:row {
                    spacing = f:label_spacing(),
                    f:static_text {
                        title = "Root keyword:",
                        alignment = 'right',
                        width = LrView.share 'label_width',
                    },
                    f:popup_menu {
                        items = popupItems,
                        value = LrView.bind('selectedIndex'),
                        width = 320,
                        tooltip = "Select the top-level keyword to export.",
                    },
                },
                f:row {
                    spacing = f:label_spacing(),
                    f:static_text {
                        title = "",
                        width = LrView.share 'label_width',
                    },
                    f:checkbox {
                        title = "Include child keywords",
                        value = LrView.bind('includeChildren'),
                    },
                },
                f:row {
                    spacing = f:label_spacing(),
                    f:static_text {
                        title = "",
                        width = LrView.share 'label_width',
                    },
                    f:checkbox {
                        title = "Delete existing matching Immich tags first",
                        value = LrView.bind('deleteExistingMatching'),
                    },
                },
                f:row {
                    spacing = f:label_spacing(),
                    f:static_text {
                        title = "",
                        width = LrView.share 'label_width',
                    },
                    f:checkbox {
                        title = "Ignore hierarchy (export all as root tags)",
                        value = LrView.bind('ignoreHierarchy'),
                    },
                },
                f:separator { fill_horizontal = 1 },
                f:static_text {
                    title = "Delete mode recreates matching names. Ignore hierarchy mode creates all selected keywords at Immich root level.",
                    font = "<system/small>",
                    text_color = LrColor(0.5, 0.5, 0.5),
                },
            }

            local dialogResult = LrDialogs.presentModalDialog {
                title      = "Export Keywords to Immich",
                contents   = contents,
                actionVerb = "Export",
            }

            selectedIndex    = props.selectedIndex
            includeChildren  = props.includeChildren
            deleteExistingMatching = props.deleteExistingMatching
            ignoreHierarchy = props.ignoreHierarchy
            return dialogResult
        end)

        if result ~= "ok" then
            return
        end

        if deleteExistingMatching then
            local confirmDelete = LrDialogs.confirm(
                "Delete existing matching Immich tags?",
                "This will delete existing Immich tags with matching names before recreating them in the selected hierarchy.\n\nThis action cannot be undone.",
                "Delete and Export",
                "Cancel"
            )
            if confirmDelete ~= "ok" then
                return
            end
        end

        local selectedItem = keywordItems[selectedIndex]
        if not selectedItem then
            return
        end

        -- Fetch existing Immich tags once for deduplication
        local existingByName = {}
        local existingTags = immich:getTags()
        if existingTags and type(existingTags) == "table" then
            for _, tag in ipairs(existingTags) do
                if tag.name then
                    local key = string.lower(tag.name)
                    if existingByName[key] == nil then
                        existingByName[key] = {}
                    end
                    table.insert(existingByName[key], tag)
                end
            end
        end

        -- Export
        local results = { created = 0, skipped = 0, failed = 0, deleted = 0, failedDeletes = 0 }
        local total = countKeywords(selectedItem.value, includeChildren)
        local progress = LrProgressScope {
            title      = "Exporting keywords to Immich",
            totalItems = total,
            functionContext = nil,
        }
        progress:setCancelable(true)
        local progressState = { completed = 0, total = total }
        local options = { deleteExistingMatching = deleteExistingMatching, ignoreHierarchy = ignoreHierarchy }
        local createdTagIds = {}

        exportKeywordTree(immich, selectedItem.value, nil, existingByName, results, includeChildren, progress, progressState, options, createdTagIds)

        progress:done()

        -- Summary
        if not progress:isCanceled() then
            local summary = string.format(
                "Export complete.\n\nCreated: %d\nAlready existed (skipped): %d\nDeleted existing: %d\nFailed deletes: %d\nFailed creates: %d",
                results.created, results.skipped, results.deleted, results.failedDeletes, results.failed
            )
            LrDialogs.message("Export Keywords to Immich", summary, (results.failed > 0 or results.failedDeletes > 0) and "warning" or "info")
        end
    end)
}
