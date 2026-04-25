---@diagnostic disable: undefined-global

require "AlbumSync"

-- Build list of Immich published collections for user selection.
local function getImmichCollections()
    local catalog = LrApplication.activeCatalog()
    if not catalog then
        return {}
    end
    
    local collections = {}
    local services = catalog:getPublishServices()
    
    for _, service in ipairs(services or {}) do
        if util.isImmichPublishService(service) then
            local serviceCollections = service:getChildCollections()
            for _, pubCollection in ipairs(serviceCollections or {}) do
                table.insert(collections, {
                    title = pubCollection:getName(),
                    value = pubCollection
                })
            end
        end
    end
    
    return collections
end

return {
    LrTasks.startAsyncTask(function()
        local catalog = LrApplication.activeCatalog()
        if not catalog then
            LrDialogs.message("No catalog", "Cannot access the active Lightroom catalog.", "critical")
            return
        end
        
        -- Get list of Immich published collections.
        local collections = getImmichCollections()
        if #collections == 0 then
            LrDialogs.message("No collections", "No Immich published collections found. Create one first.", "warning")
            return
        end
        
        -- Prompt user to select a collection.
        local pubCollection = nil
        if #collections == 1 then
            pubCollection = collections[1].value
        else
            LrFunctionContext.callWithContext("selectCollection", function(context)
                local f = LrView.osFactory()
                local bind = LrView.bind
                local propertyTable = LrBinding.makePropertyTable(context)
                propertyTable.selectedCollection = collections[1].value
                
                local result = LrDialogs.presentModalDialog({
                    title = "Select Collection for Album Sync",
                    contents = f:column {
                        bind_to_object = propertyTable,
                        f:static_text {
                            title = "Choose Immich published collection to sync:",
                        },
                        f:popup_menu {
                            items = collections,
                            value = bind "selectedCollection",
                        },
                    },
                    actionVerb = "Select",
                    cancelVerb = "Cancel"
                })
                
                if result == "ok" then
                    pubCollection = propertyTable.selectedCollection
                end
            end)
        end
        
        if not pubCollection then
            return
        end
        
        -- Verify it's an Immich collection.
        local service = pubCollection:getService()
        if not service or not util.isImmichPublishService(service) then
            LrDialogs.message("Not an Immich collection", "The selected collection is not an Immich publish collection.", "warning")
            return
        end
        
        local collectionName = pubCollection:getName()
        
        -- Confirm with user.
        local confirmed = LrDialogs.promptForActionWithDoNotShow({
            actionPrefKey = "confirmAlbumSync",
            message = "Sync Album Contents",
            info = "Download missing assets from Immich album '" .. collectionName .. "' to the staging folder?\n\nYou will need to import these images into Lightroom manually, then run 'Finalize Album Sync'.",
            verbBtns = {
                { verb = "cancel", label = "Cancel" },
                { verb = "proceed", label = "Proceed" }
            }
        })
        
        if confirmed ~= "proceed" then
            return
        end
        
        -- Get staging folder from prefs.
        local stagingFolder = prefs.albumSyncStagingFolder
        if not stagingFolder or stagingFolder == "" then
            LrDialogs.message("Not configured", "Please configure the Album Sync Staging Folder in Immich import configuration.", "critical")
            return
        end
        
        -- Run download phase.
        local success, message = AlbumSync.downloadMissingAssets(pubCollection, stagingFolder)
        
        if success then
            LrDialogs.message("Album sync started", message, "info")
        else
            LrDialogs.message("Album sync failed", message, "critical")
        end
    end)
}
