---@diagnostic disable: undefined-global

require "MetadataSync"

return {
    LrTasks.startAsyncTask(function()
        MetadataSync.sendForCurrentSelection()
    end)
}
