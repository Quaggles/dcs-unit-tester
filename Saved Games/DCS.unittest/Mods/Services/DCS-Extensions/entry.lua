declare_plugin("dcs_extensions", {
	installed = true,
	dirName = current_mod_path,
	developerName = _("MisterOutofTime"),
	developerLink = _(""),
	displayName = _("DCS dcs_extensions"),
	version = "0.0.1",
	state = "installed",
	info = _("DCS-dcs_extensions"),
	binaries = {"dcs_extensions.dll"},
    load_immediate = true,
	--Skins = {
	--	{ name = "dcs_extensions", dir = "Theme" },
	--},
	--Options = {
--		{ name = "dcs_extensions", nameId = "dcs_extensions", dir = "Options", allow_in_simulation = true; },
--	},
})

plugin_done()