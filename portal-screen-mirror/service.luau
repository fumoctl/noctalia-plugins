--!nonstrict

local PANEL_ID = "fumoctl/portal-screen-mirror:controls"

local VALID_FPS = {
	auto = true,
	["30"] = true,
	["60"] = true,
	["120"] = true,
	["0"] = true,
}

local function normalizeFps(value)
	local s = tostring(value or "auto")
	return VALID_FPS[s] and s or "auto"
end

local function normalizeFit(value)
	if value == "cover" or value == "stretch" then
		return value
	end
	return "contain"
end

local function normalizeFilter(value)
	if value == "fast" then
		return "nearest"
	end
	return "linear"
end

local dataDir = noctalia.pluginDataDir()
local runFile = dataDir and (dataDir .. "/mirror.run") or nil
local liveFile = dataDir and (dataDir .. "/live.cfg") or nil
local errFile = dataDir and (dataDir .. "/mirror.err") or nil
local prefsFile = dataDir and (dataDir .. "/prefs.json") or nil

local function detectHomeDir()
	local d = dataDir or ""
	return string.match(d, "^(.-)/%.local/") or string.match(d, "^(/home/[^/]+)")
end

local function resolveBinarySync()
	if noctalia.commandExists("portal-screen-mirror") then
		return "portal-screen-mirror"
	end
	local home = detectHomeDir()
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
				return cand
			end
		end
	end
	return nil
end

local resolvedBin = resolveBinarySync()
local probingBinary = false
local pendingStart = nil

local sessionCounter = 0
local lastRequestSerial = -1
local lastFpsSerial = -1
local streamActive = false
local notifyOnStop = false
local pendingRestart = nil
local selectedFps = normalizeFps(noctalia.getConfig("max_fps"))

local status = {
	phase = "stopped",
	running = false,
	binary_available = resolvedBin ~= nil,
	destination = nil,
	mode = nil,
	message = "",
}

local function tr(key, values)
	return noctalia.tr(key, values)
end

local function shellQuote(value)
	return "'" .. string.gsub(tostring(value), "'", "'\\''") .. "'"
end

local function isInternalPanel(name)
	local n = name or ""
	return string.sub(n, 1, 4) == "eDP-" or string.sub(n, 1, 5) == "LVDS-" or string.sub(n, 1, 4) == "DSI-"
end

local function writeLiveConfig()
	if liveFile == nil then
		return
	end
	local fit = normalizeFit(noctalia.getConfig("fit"))
	local filter = normalizeFilter(noctalia.getConfig("scale_quality"))
	noctalia.writeFile(liveFile, fit .. " " .. filter .. " " .. selectedFps .. "\n")
end

local function syncFpsState(persistPrefs, configBase)
	writeLiveConfig()
	if persistPrefs and prefsFile ~= nil then
		local encoded = noctalia.json.encode({
			max_fps = selectedFps,
			config_base = configBase or normalizeFps(noctalia.getConfig("max_fps")),
		})
		if type(encoded) == "string" then
			noctalia.writeFile(prefsFile, encoded .. "\n")
		end
	end
	noctalia.state.set("mirror_prefs", {
		max_fps = selectedFps,
	})
end

local function loadInitialFps()
	local cfgFps = normalizeFps(noctalia.getConfig("max_fps"))
	selectedFps = cfgFps
	if prefsFile ~= nil then
		local raw = noctalia.readFile(prefsFile)
		if type(raw) == "string" and raw ~= "" then
			local parsed = noctalia.json.decode(raw)
			if type(parsed) == "table" then
				local savedBase = normalizeFps(parsed.config_base)
				local savedFps = normalizeFps(parsed.max_fps)
				if savedBase == cfgFps then
					selectedFps = savedFps
				else
					selectedFps = cfgFps
					syncFpsState(true, cfgFps)
					return
				end
			end
		end
	end
	syncFpsState(false, cfgFps)
end

local function publishStatus(phase, message)
	local syncBin = resolveBinarySync()
	if syncBin ~= nil then
		resolvedBin = syncBin
	end
	status.phase = phase
	status.running = phase == "running"
	status.binary_available = resolvedBin ~= nil
	status.message = message or ""
	noctalia.state.set("mirror_status", {
		phase = status.phase,
		running = status.running,
		binary_available = status.binary_available,
		destination = status.destination,
		mode = status.mode,
		message = status.message,
	})
end

local startMirror

local function probeBinary(thenStart)
	local syncBin = resolveBinarySync()
	if syncBin ~= nil then
		resolvedBin = syncBin
		publishStatus(status.phase, status.message)
		if thenStart ~= nil then
			startMirror(thenStart.destination, thenStart.mode)
		end
		return
	end

	if streamActive or probingBinary then
		if thenStart ~= nil then
			pendingStart = thenStart
		end
		return
	end

	if thenStart ~= nil then
		pendingStart = thenStart
	end
	probingBinary = true

	local probeCmd = table.concat({
		[=[for cand in \]=],
		[=[  "$(command -v portal-screen-mirror 2>/dev/null)" \]=],
		[=[  "${CARGO_HOME:-$HOME/.cargo}/bin/portal-screen-mirror" \]=],
		[=[  "$HOME/.local/bin/portal-screen-mirror" \]=],
		[=[  "$HOME/bin/portal-screen-mirror" \]=],
		[=[  "/opt/portal-screen-mirror/portal-screen-mirror"; do]=],
		[=[  if [ -n "$cand" ] && [ -f "$cand" ] && [ -x "$cand" ]; then printf 'found:%s\n' "$cand"; exit 0; fi]=],
		[=[done]=],
		[=[DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"]=],
		[=[for dir in \]=],
		[=[  "$HOME/.AppImages" \]=],
		[=[  "$HOME/.Appimages" \]=],
		[=[  "$HOME/AppImages" \]=],
		[=[  "$HOME/Appimages" \]=],
		[=[  "$HOME/Applications" \]=],
		[=[  "$HOME/.local/bin" \]=],
		[=[  "$HOME/bin" \]=],
		[=[  "$DATA_HOME/AppImages" \]=],
		[=[  "$DATA_HOME/zap/v2" \]=],
		[=[  "$DATA_HOME/AM" \]=],
		[=[  "$HOME/Downloads" \]=],
		[=[  "/Applications" \]=],
		[=[  "/opt/AppImages"; do]=],
		[=[  [ -d "$dir" ] || continue]=],
		[=[  BEST=""]=],
		[=[  for f in "$dir"/* "$dir"/*/*; do]=],
		[=[    [ -f "$f" ] && [ -x "$f" ] || continue]=],
		[=[    base=$(basename "$f" | tr '[:upper:]' '[:lower:]')]=],
		[=[    case "$base" in]=],
		[=[      portal-screen-mirror|portal_screen_mirror|portal[-_]screen[-_]mirror*.appimage|portal*screen*mirror*.appimage)]=],
		[=[        if [ -z "$BEST" ] || [ "$f" -nt "$BEST" ]; then BEST="$f"; fi]=],
		[=[        ;;]=],
		[=[    esac]=],
		[=[  done]=],
		[=[  if [ -n "$BEST" ]; then printf 'found:%s\n' "$BEST"; exit 0; fi]=],
		[=[done]=],
		[=[printf 'missing\n']=],
	}, "\n")

	if not noctalia.runStream(probeCmd, function(line)
		line = noctalia.string.trim(line or "")
		if string.sub(line, 1, 6) == "found:" then
			resolvedBin = noctalia.string.trim(string.sub(line, 7))
			probingBinary = false
			publishStatus(status.phase, status.message)
			if pendingStart ~= nil then
				local req = pendingStart
				pendingStart = nil
				startMirror(req.destination, req.mode)
			end
		elseif line == "missing" then
			resolvedBin = nil
			probingBinary = false
			publishStatus(status.phase, status.message)
			if pendingStart ~= nil then
				pendingStart = nil
				noctalia.notifyError(tr("title"), tr("error.binary_missing"))
			end
		end
	end) then
		probingBinary = false
	end
end

local function findOutput(name)
	if type(name) ~= "string" or name == "" then
		return nil
	end
	for _, out in ipairs(noctalia.outputs() or {}) do
		if out.name == name then
			return out
		end
	end
	return nil
end

local function defaultDestination()
	local list = {}
	for _, out in ipairs(noctalia.outputs() or {}) do
		if type(out.name) == "string" and out.name ~= "" then
			table.insert(list, out)
		end
	end
	if #list < 2 then
		return nil
	end
	table.sort(list, function(a, b)
		local aInternal = isInternalPanel(a.name)
		local bInternal = isInternalPanel(b.name)
		if aInternal ~= bInternal then
			return not aInternal
		end
		local aFocused = a.focused == true
		local bFocused = b.focused == true
		if aFocused ~= bFocused then
			return not aFocused
		end
		return a.name < b.name
	end)
	return list[1].name
end

local function cleanupFiles()
	if runFile ~= nil then
		noctalia.removeFile(runFile)
	end
	if liveFile ~= nil then
		noctalia.removeFile(liveFile)
	end
	if errFile ~= nil then
		noctalia.removeFile(errFile)
	end
end

local function finishStopped(showOsd, customMsg)
	streamActive = false
	notifyOnStop = false
	cleanupFiles()

	status.destination = nil
	status.mode = nil
	publishStatus("stopped", customMsg or "")

	if showOsd then
		noctalia.osd.show("screen-share-off", customMsg or tr("osd.stopped"), { inactive = true })
	end

	if pendingRestart ~= nil then
		local req = pendingRestart
		pendingRestart = nil
		startMirror(req.destination, req.mode)
	end
end

local function finishFailed(errMsg)
	streamActive = false
	notifyOnStop = false
	pendingRestart = nil
	cleanupFiles()

	status.destination = nil
	status.mode = nil
	local msg = (type(errMsg) == "string" and errMsg ~= "") and errMsg or tr("error.stream_exited")
	publishStatus("error", msg)
	noctalia.notifyError(tr("title"), msg)
end

local function stopMirror(showOsd, customMsg)
	if not streamActive then
		finishStopped(showOsd, customMsg)
		return
	end
	notifyOnStop = showOsd == true
	publishStatus("stopping", tr("widget.stopping"))
	if runFile ~= nil then
		noctalia.removeFile(runFile)
	end
end

local function buildDaemonCmd(binPath, destName, mode)
	local fit = normalizeFit(noctalia.getConfig("fit"))
	local filter = normalizeFilter(noctalia.getConfig("scale_quality"))
	local showCursor = noctalia.getConfig("show_cursor") ~= false

	local launchParts = {
		'"$BIN"',
		shellQuote(mode),
		"--to",
		shellQuote(destName),
		"--fit",
		shellQuote(fit),
		"--filter",
		shellQuote(filter),
		"--max-fps",
		shellQuote(selectedFps),
	}
	if not showCursor then
		table.insert(launchParts, "--no-cursor")
	end
	local launchCmd = table.concat(launchParts, " ") .. ' >"$ERR" 2>&1 &'

	return table.concat({
		"BIN=" .. shellQuote(binPath),
		"RUN=" .. shellQuote(runFile),
		"CFG=" .. shellQuote(liveFile),
		"ERR=" .. shellQuote(errFile),
		"OWNER=$PPID",
		[=[if [ -n "${XDG_RUNTIME_DIR:-}" ]; then SOCK="$XDG_RUNTIME_DIR/portal-screen-mirror.sock"; else SOCK="/tmp/portal-screen-mirror-$(id -u).sock"; fi]=],
		[=[case "$BIN" in *.[Aa][Pp][Pp][Ii][Mm][Aa][Gg][Ee]) if [ ! -c /dev/fuse ] || [ ! -r /dev/fuse ]; then export APPIMAGE_EXTRACT_AND_RUN=1; fi ;; esac]=],
		': > "$ERR"',
		'if [ -S "$SOCK" ]; then "$BIN" stop >/dev/null 2>&1 || true; fi',
		launchCmd,
		"PID=$!",
		[=[trap '"$BIN" stop >/dev/null 2>&1 || true; kill -TERM "$PID" 2>/dev/null || true' HUP INT TERM EXIT]=],
		[=[printf 'selecting\n']=],
		"READY=0",
		[=[LAST_CFG=$(cat "$CFG" 2>/dev/null || true)]=],
		[=[while [ -f "$RUN" ] && kill -0 "$OWNER" 2>/dev/null && kill -0 "$PID" 2>/dev/null; do]=],
		[=[  if [ "$READY" -eq 0 ]; then]=],
		[=[    if [ -S "$SOCK" ] && "$BIN" status >/dev/null 2>&1; then READY=1; printf 'ready\n'; fi]=],
		[=[  else]=],
		[=[    CUR_CFG=$(cat "$CFG" 2>/dev/null || true)]=],
		[=[    if [ -n "$CUR_CFG" ] && [ "$CUR_CFG" != "$LAST_CFG" ]; then]=],
		[=[      LAST_CFG="$CUR_CFG"]=],
		[=[      set -- $CUR_CFG]=],
		[=[      if [ "$#" -ge 3 ]; then "$BIN" set --fit "$1" --filter "$2" --max-fps "$3" >/dev/null 2>&1 || true; fi]=],
		[=[    fi]=],
		[=[  fi]=],
		[=[  sleep 0.1]=],
		[=[done]=],
		[=[if [ ! -f "$RUN" ] || ! kill -0 "$OWNER" 2>/dev/null; then]=],
		[=[  "$BIN" stop >/dev/null 2>&1 || true]=],
		[=[  kill -TERM "$PID" 2>/dev/null || true]=],
		[=[  ATTEMPT=0]=],
		[=[  while kill -0 "$PID" 2>/dev/null && [ "$ATTEMPT" -lt 20 ]; do sleep 0.05; ATTEMPT=$((ATTEMPT + 1)); done]=],
		[=[  kill -KILL "$PID" 2>/dev/null || true]=],
		[=[  wait "$PID" 2>/dev/null || true]=],
		[=[  trap - HUP INT TERM EXIT]=],
		[=[  printf 'stopped\n']=],
		[=[else]=],
		[=[  wait "$PID"; CODE=$?]=],
		[=[  trap - HUP INT TERM EXIT]=],
		[=[  if [ "$READY" -eq 0 ] && [ "$CODE" -eq 0 ]; then]=],
		[=[    printf 'cancelled\n']=],
		[=[  elif [ "$CODE" -ne 0 ] && [ "$CODE" -ne 130 ] && [ "$CODE" -ne 143 ]; then]=],
		[=[    MSG=$(awk 'NF { line = $0 } END { sub(/^portal-screen-mirror: error: /, "", line); print line }' "$ERR" 2>/dev/null)]=],
		[=[    if [ -n "$MSG" ]; then printf 'error:%s\n' "$MSG"; else printf 'exited:%s\n' "$CODE"; fi]=],
		[=[  else]=],
		[=[    printf 'exited:%s\n' "$CODE"]=],
		[=[  fi]=],
		[=[fi]=],
	}, "\n")
end

local function handleStreamLine(line)
	line = noctalia.string.trim(line or "")
	if line == "" then
		return
	end

	if line == "selecting" then
		publishStatus("starting", tr("panel.status_starting"))
	elseif line == "ready" then
		if status.destination == nil then
			stopMirror(false)
			return
		end
		publishStatus("running", tr("panel.status_running", { destination = status.destination }))
		noctalia.osd.show("screen-share", tr("osd.started", { destination = status.destination }))
	elseif line == "cancelled" then
		finishStopped(false)
	elseif line == "stopped" then
		finishStopped(notifyOnStop)
	elseif string.sub(line, 1, 6) == "error:" then
		finishFailed(noctalia.string.trim(string.sub(line, 7)))
	elseif string.sub(line, 1, 7) == "exited:" then
		local code = tonumber(string.sub(line, 8)) or 1
		if code == 0 or code == 130 or code == 143 or notifyOnStop then
			finishStopped(notifyOnStop)
		else
			finishFailed(tr("error.stream_exited"))
		end
	end
end

startMirror = function(destination, mode)
	mode = (mode == "region") and "region" or "portal"

	if runFile == nil or liveFile == nil or errFile == nil then
		finishFailed(tr("error.launch_failed"))
		return
	end

	local syncBin = resolveBinarySync()
	if syncBin ~= nil then
		resolvedBin = syncBin
	end
	if resolvedBin == nil then
		probeBinary({ destination = destination, mode = mode })
		return
	end

	if mode == "portal" and not noctalia.portalAvailable() then
		finishFailed(tr("error.portal_unavailable"))
		return
	end

	local destOut = findOutput(destination)
	if destOut == nil then
		finishFailed(tr("error.no_destination"))
		return
	end

	if streamActive then
		pendingRestart = { destination = destination, mode = mode }
		stopMirror(false)
		return
	end

	sessionCounter += 1
	local sessionId = tostring(noctalia.nowMs()) .. "-" .. tostring(sessionCounter)
	writeLiveConfig()
	local ok, err = noctalia.writeFile(runFile, sessionId .. "\n")
	if not ok then
		finishFailed(err or tr("error.launch_failed"))
		return
	end

	status.destination = destination
	status.mode = mode
	notifyOnStop = false
	streamActive = true
	publishStatus("starting", tr("panel.status_starting"))

	local cmd = buildDaemonCmd(resolvedBin, destOut.name, mode)
	if not noctalia.runStream(cmd, handleStreamLine) then
		streamActive = false
		cleanupFiles()
		finishFailed(tr("error.launch_failed"))
	end
end

noctalia.state.watch("mirror_fps_request", function(req)
	if type(req) ~= "table" then
		return
	end
	if type(req.serial) == "number" then
		if req.serial == lastFpsSerial then
			return
		end
		lastFpsSerial = req.serial
	end
	local nextFps = normalizeFps(req.max_fps)
	if nextFps ~= selectedFps then
		selectedFps = nextFps
		syncFpsState(true, normalizeFps(noctalia.getConfig("max_fps")))
	end
end)

noctalia.state.watch("mirror_request", function(req)
	if type(req) ~= "table" then
		return
	end
	if type(req.serial) == "number" then
		if req.serial == lastRequestSerial then
			return
		end
		lastRequestSerial = req.serial
	end

	if req.max_fps ~= nil then
		local nextFps = normalizeFps(req.max_fps)
		if nextFps ~= selectedFps then
			selectedFps = nextFps
			syncFpsState(true, normalizeFps(noctalia.getConfig("max_fps")))
		end
	end

	if req.action == "start" then
		startMirror(req.destination, req.mode)
	elseif req.action == "stop" then
		pendingRestart = nil
		stopMirror(true)
	elseif req.action == "probe_binary" then
		probeBinary(nil)
	elseif req.action == "open_repo" then
		if not streamActive and not probingBinary then
			noctalia.runStream(
				"xdg-open 'https://github.com/fumoctl/portal-screen-mirror' >/dev/null 2>&1 || true",
				function(_) end
			)
		end
	end
end)

function onOutputsChanged()
	if (status.phase == "running" or status.phase == "starting") and findOutput(status.destination) == nil then
		pendingRestart = nil
		stopMirror(true, tr("error.disconnected"))
	end
end

function onConfigChanged()
	local cfgFps = normalizeFps(noctalia.getConfig("max_fps"))
	selectedFps = cfgFps
	syncFpsState(true, cfgFps)
end

function onIpc(event, payload)
	local arg = noctalia.string.trim(payload or "")
	if event == "toggle" then
		if status.phase == "running" or status.phase == "starting" then
			pendingRestart = nil
			stopMirror(true)
		else
			noctalia.togglePanel(PANEL_ID)
		end
	elseif event == "stop" then
		pendingRestart = nil
		stopMirror(true)
	elseif event == "portal" or event == "region" then
		if status.phase == "running" or status.phase == "starting" then
			pendingRestart = nil
			stopMirror(true)
			return
		end
		local dest = arg ~= "" and arg or defaultDestination()
		if dest == nil then
			noctalia.notifyError(tr("title"), tr("error.no_destination"))
			return
		end
		startMirror(dest, event)
	end
end

function onExit(_signal, _reason)
	pendingRestart = nil
	cleanupFiles()
end

cleanupFiles()
loadInitialFps()
publishStatus("stopped", "")
if resolvedBin == nil then
	probeBinary(nil)
end
