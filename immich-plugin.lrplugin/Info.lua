return {

	LrSdkVersion = 3.0,
	LrSdkMinimumVersion = 3.0,

	LrToolkitIdentifier = 'lrc-immich-plugin',

	LrPluginName = "Immich",

	LrInitPlugin = "Init.lua",

	LrExportServiceProvider = {
		{
			title = "Immich Exporter",
			file = 'ExportServiceProvider.lua',
		},
		{
			title = "Immich Publisher",
			file = 'PublishServiceProvider.lua',
		},
	},

	LrMetadataProvider = 'MetadataProvider.lua',
	LrMetadataTagsetFactory = 'Tagset.lua',

	LrLibraryMenuItems = {
		{
			title = "Import from Immich",
			file = "ImportDialog.lua",
		},
		{
			title = "Immich import configuration",
			file = "ImportConfiguration.lua",
		},
		{
			title = "Export Keywords to Immich",
			file = "ExportKeywords.lua",
		},
		{
			title = "Send Metadata to Immich for Selected Images",
			file = "SendMetadataSelected.lua",
		},
		{
			title = "Import Metadata from Immich for Selected Images",
			file = "ImportMetadataSelected.lua",
		},
		{
			title = "Sync Album Contents for Selected Collection",
			file = "SyncAlbumSelected.lua",
		},
		{
			title = "Finalize Album Sync for Selected Collection",
			file = "FinalizeAlbumSync.lua",
		},
	},

	LrExportMenuItems = {
		{
			title = "Import from Immich",
			file = "ImportDialog.lua",
		},
		{
			title = "Immich import configuration",
			file = "ImportConfiguration.lua",
		},
	},

	LrPluginInfoProvider = 'PluginInfo.lua',

	LrPluginInfoURL = 'https://github.com/bmachek/lrc-immich-plugin/',

	VERSION = { major = 4, minor = 0, revision = 0, build = 29, },

}
