
-- *************************************************
local function main()
    local share = LrView.share
    LrFunctionContext.callWithContext("ImmichExtraOptionsContext", function(context)
        log:info("ImmichExtraOptions")

        local allServices = util.getPublishServicesForPlugin(_PLUGIN.id)
        if #allServices == 0 then
            LrDialogs.message("No Piwigo publish services found.")
            return
        end

        local serviceItems = {}
        local serviceNames = {}
        for i, s in ipairs(allServices) do
            table.insert(serviceItems, {
                title = s:getName(),
                value = s,
            })
            table.insert(serviceNames, {
                title = s:getName(),
                value = i,
            })
        end

        local props = LrBinding.makePropertyTable(context)
        props.selectedService = 1

        local f = LrView.osFactory()
        local c = f:column {
            spacing = f:dialog_spacing(),

            UIHelpers.createPluginHeader(f, share, iconPath, pluginVersion),

            f:row {
                spacing = f:label_spacing(),

                f:static_text {
                    title = "Select publish service:",
                    alignment = 'right',
                    width = 150,
                },

                f:popup_menu {
                    value = LrView.bind { key = 'selectedService', bind_to_object = props },
                    items = serviceNames,
                    value_equal = valueEqual,
                    width = 300,
                },
            },

            f:spacer { height = 20 },
            f:row {
                f:static_text {
                    title = "Applies to selected photos/collection",
                    font = "<system/bold>",
                    alignment = 'left',
                    fill_horizontal = 1,
                },
            },

            f:spacer { height = 4 },

            f:spacer { height = 1 },
            f:row {
                f:push_button {
                    title = 'Set Piwigo Album Cover',
                    tooltip = "Sets selected image as Piwigo album cover",
                    width = share 'buttonwidth',
                    action = function()
                        LrTasks.startAsyncTask(function()
                            local serviceNo = props.selectedService
                            local service = serviceItems[serviceNo] and serviceItems[serviceNo].value or nil
                            if not service then
                                LrDialogs.message("Error", "Could not find publish service", "error")
                                return
                            end
                            setAlbumCoverFromSelection(service)
                        end)
                    end,
                },
                f:static_text {
                    title = "Sets selected image as Piwigo album cover for the selected service",
                    alignment = 'left',
                    width_in_chars = 58,
                },
            },

            f:spacer { height = 1 },
            f:row {
                f:push_button {
                    title = 'Send Metadata to Piwigo',
                    tooltip = "Sends metadata for selected photos to Piwigo",
                    width = share 'buttonwidth',
                    action = function()
                        LrTasks.startAsyncTask(function()
                            local serviceNo = props.selectedService
                            local service = serviceItems[serviceNo] and serviceItems[serviceNo].value or nil
                            if not service then
                                LrDialogs.message("Error", "Could not find publish service", "error")
                                return
                            end
                            sendMetadataForSelection(service)
                        end)
                    end,
                },
                f:static_text {
                    title = "Sends metadata for selected photos in the selected service",
                    alignment = 'left',
                    width_in_chars = 58,
                },
            },

            f:spacer { height = 1 },
            f:row {
                f:push_button {
                    title = 'Convert Collection to Collection Set',
                    tooltip = "Converts selected published collection to a collection set",
                    width = share 'buttonwidth',
                    action = function()
                        LrTasks.startAsyncTask(function()
                            local serviceNo = props.selectedService
                            local service = serviceItems[serviceNo] and serviceItems[serviceNo].value or nil
                            if not service then
                                LrDialogs.message("Error", "Could not find publish service", "error")
                                return
                            end
                            convertSelectionCollectionToSet(service)
                        end)
                    end,
                },
                f:static_text {
                    title = "Converts selected published collection to a collection set",
                    alignment = 'left',
                    width_in_chars = 58,
                },
            },
--[[
-- currently commented out as LrC SDK doesn't expose current display order of photos in a published collection
-- will be revisited
            f:spacer { height = 1 },
            f:row {
                f:push_button {
                    title = 'Sync Current Album Sort Now',
                    tooltip = "Sends the current Lightroom order for selected published collection to Piwigo",
                    action = function()
                        LrTasks.startAsyncTask(function()
                            local serviceNo = props.selectedService
                            local service = serviceItems[serviceNo] and serviceItems[serviceNo].value or nil
                            if not service then
                                LrDialogs.message("Error", "Could not find publish service", "error")
                                return
                            end
                            syncCurrentAlbumSortNow(service)
                        end)
                    end,
                },
                f:static_text {
                    title = "Syncs selected published collection's current order to Piwigo",
                    alignment = 'left',
                    width_in_chars = 58,
                },
            },
            ]]
        }

        LrDialogs.presentModalDialog {
            title = "Immich Publisher Extra Options",
            contents = c,
            actionVerb = "Close",
            cancelVerb = "< exclude >",
        }
    end)
end

-- *************************************************
-- Run main()
LrTasks.startAsyncTask(main)