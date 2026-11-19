--!nonstrict

local PANEL_ID = "fumoctl/portal-screen-mirror:controls"

local status = noctalia.state.get("mirror_status") or {
	phase = "stopped",
	running = false,
}
local requestSerial = 0

local function tr(key, values)
	return noctalia.tr(key, values)
end

local function isBinaryAvailable()
	if status.binary_available == true or noctalia.commandExists("portal-screen-mirror") then
		return true
	end
	local dataDir = noctalia.pluginDataDir() or ""
	local home = string.match(dataDir, "^(.-)/%.local/") or string.match(dataDir, "^(/home/[^/]+)")
	if type(home) == "string" and home ~= "" then
		local exactCandidates = {
			home .. "/.cargo/bin/portal-screen-mirror",
			home .. "/.local/bin/portal-screen-mirror",
			home .. "/bin/portal-screen-mirror",
			"/opt/portal-screen-mirror/portal-screen-mirror",
		}
		local appDirs = { "/AppImages", "/.AppImages", "/.Appimages", "/Appimages", "/Applications" }
		local appNames = {
			"portal_screen_mirror.appimage",
			"portal-screen-mirror.appimage",
			"portal-screen-mirror-x86_64.AppImage",
			"portal-screen-mirror-aarch64.AppImage",
		}
		for _, dir in ipairs(appDirs) do
			for _, fname in ipairs(appNames) do
				table.insert(exactCandidates, home .. dir .. "/" .. fname)
			end
		end
		for _, cand in ipairs(exactCandidates) do
			if noctalia.commandExists(cand) then
				return true
			end
		end
	end
	return false
end

local function modeLabel(mode)
	if mode == "region" then
		return tr("mode.region")
	end
	return tr("mode.portal")
end

local function render()
	local phase = status.phase or "stopped"
	barWidget.setText("")

	if phase == "running" then
		barWidget.setGlyph("screen-share")
		barWidget.setGlyphColor("primary")
		barWidget.setTooltip({
			{ key = tr("widget.running_status"), value = tr("widget.running_value") },
			{ key = tr("widget.destination"), value = status.destination or "?" },
			{ key = tr("widget.mode"), value = modeLabel(status.mode) },
			{ key = tr("widget.right_click_key"), value = tr("widget.right_click_value") },
		})
	elseif phase == "starting" then
		barWidget.setGlyph("loader-2")
		barWidget.setGlyphColor("on_surface_variant")
		barWidget.setTooltip(tr("widget.starting"))
	elseif phase == "stopping" then
		barWidget.setGlyph("loader-2")
		barWidget.setGlyphColor("on_surface_variant")
		barWidget.setTooltip(tr("widget.stopping"))
	elseif phase == "error" then
		barWidget.setGlyph("screen-share-off")
		barWidget.setGlyphColor("error")
		local msg = status.message
		barWidget.setTooltip(type(msg) == "string" and msg ~= "" and msg or tr("widget.error"))
	else
		barWidget.setGlyph("screen-share")
		barWidget.setGlyphColor("on_surface")
		if not isBinaryAvailable() then
			barWidget.setTooltip(tr("error.binary_missing"))
		else
			barWidget.setTooltip(tr("widget.ready"))
		end
	end
end

noctalia.state.watch("mirror_status", function(value)
	if type(value) == "table" then
		status = value
		render()
	end
end)

function update()
	local current = noctalia.state.get("mirror_status")
	if type(current) == "table" then
		status = current
	end
	render()
end

function onClick()
	noctalia.togglePanel(PANEL_ID)
end

function onRightClick()
	local phase = status.phase or "stopped"
	if phase == "running" or phase == "starting" then
		requestSerial += 1
		noctalia.state.set("mirror_request", {
			action = "stop",
			serial = requestSerial,
		})
		return
	end
	noctalia.togglePanel(PANEL_ID)
end

noctalia.setUpdateInterval(1000)
render()
