-- BalatroMulti: run several copies of the game side by side, all fed the same input.
--
-- Every instance loads this file (appended to main.lua by Lovely). It does nothing
-- unless the launcher set BALATRO_MULTI_ID / BALATRO_MULTI_N, so the game still
-- starts normally from Steam.
--
-- How it works:
--   * Instance 1 is the hub: a TCP server on localhost. The others connect to it.
--   * Whichever window receives a real mouse/keyboard event sends it to everyone,
--     with mouse positions expressed as a fraction of the window size.
--   * The game never sees the real mouse: love.mouse.getPosition and friends
--     return the shared virtual cursor instead.
--   * Each instance places its own borderless window in a grid cell, or covers the
--     whole display when it is the zoomed one.
(function()

local ID = tonumber(os.getenv("BALATRO_MULTI_ID") or "")
local N = tonumber(os.getenv("BALATRO_MULTI_N") or "")
if not ID or not N then return end
N = math.max(1, math.min(16, math.floor(N)))
ID = math.floor(ID)
if ID < 1 or ID > N then return end

local CFG = {
    port = tonumber(os.getenv("BALATRO_MULTI_PORT") or "") or 47816,
    display = tonumber(os.getenv("BALATRO_MULTI_DISPLAY") or "") or 1,
    fps = tonumber(os.getenv("BALATRO_MULTI_FPS") or "") or 60,
    -- Real Steam integration only in instance 1 (and not at all if set to 0).
    steam = os.getenv("BALATRO_MULTI_STEAM") ~= "0",
    label = os.getenv("BALATRO_MULTI_LABEL") ~= "0",
    keys = {
        zoom = "f1",  -- zoom into the instance under the mouse / back out to the grid
        prev = "f2",  -- zoom to the previous instance
        next = "f3",  -- zoom to the next instance
        quit = "f10", -- with Ctrl held: quit every instance
    },
}

local floor, ceil = math.floor, math.ceil

---------------------------------------------------------------------------
-- Save data: each instance gets its own save directory, seeded once from
-- the player's real save (minus any run in progress). The real save is
-- never written to.
---------------------------------------------------------------------------
do
    local fs = love.filesystem
    local base = fs.getIdentity()
    local mine = base .. "_multi_" .. ID
    fs.setIdentity(mine)
    if not fs.getInfo("settings.jkr") then
        fs.setIdentity(base)
        local files = {}
        local function grab(path)
            local data = fs.read(path)
            if data then files[#files + 1] = { path = path, data = data } end
        end
        if fs.getInfo("settings.jkr") then grab("settings.jkr") end
        for p = 1, 3 do
            local dir = tostring(p)
            local info = fs.getInfo(dir)
            if info and info.type == "directory" then
                for _, name in ipairs(fs.getDirectoryItems(dir)) do
                    if name:match("%.jkr$") and name ~= "save.jkr" then grab(dir .. "/" .. name) end
                end
            end
        end
        fs.setIdentity(mine)
        for _, f in ipairs(files) do
            local dir = f.path:match("^(.*)/[^/]+$")
            if dir then fs.createDirectory(dir) end
            fs.write(f.path, f.data)
        end
    end
end

---------------------------------------------------------------------------
-- Steam: only instance 1 talks to Steam. The others get a stand-in that
-- lets startup succeed, and G.STEAM is cleared once the game has loaded.
---------------------------------------------------------------------------
local use_steam = CFG.steam and ID == 1
if not use_steam then
    package.loaded["luasteam"] = nil
    package.preload["luasteam"] = function()
        return { init = function() return true end }
    end
end

---------------------------------------------------------------------------
-- Shared state
---------------------------------------------------------------------------
local V = {
    x = 0.5, y = 0.5, -- virtual cursor, as a fraction of the window
    buttons = {},     -- virtual mouse buttons held
    keys = {},        -- virtual keys held
    hover = 1,        -- instance the real mouse was last over
    zoom = 0,         -- zoomed instance, 0 = grid
}

local real = {
    getPosition = love.mouse.getPosition,
    kbIsDown = love.keyboard.isDown,
    setMode = love.window.setMode,
}

local function local_xy()
    local w, h = love.graphics.getDimensions()
    return floor(V.x * w + 0.5), floor(V.y * h + 0.5)
end

love.mouse.getPosition = local_xy
love.mouse.getX = function() return (local_xy()) end
love.mouse.getY = function() local _, y = local_xy(); return y end
love.mouse.isDown = function(...)
    for i = 1, select("#", ...) do
        if V.buttons[select(i, ...)] then return true end
    end
    return false
end
love.keyboard.isDown = function(...)
    for i = 1, select("#", ...) do
        if V.keys[select(i, ...)] then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Window placement
---------------------------------------------------------------------------
local ffi_ok, ffi = pcall(require, "ffi")
local sdl
if ffi_ok then
    pcall(ffi.cdef, "typedef struct SDL_Window SDL_Window;")
    pcall(ffi.cdef, "SDL_Window* SDL_GL_GetCurrentWindow(void);")
    pcall(ffi.cdef, "void SDL_SetWindowSize(SDL_Window*, int, int);")
    pcall(ffi.cdef, "void SDL_SetWindowAlwaysOnTop(SDL_Window*, int);")
    pcall(ffi.cdef, "void SDL_RaiseWindow(SDL_Window*);")
    local ok, lib = pcall(ffi.load, "SDL2")
    sdl = ok and lib or ffi.C
end

-- Calls an SDL function on this instance's window. Returns false if SDL is not reachable.
local function sdl_window_call(name, ...)
    if not sdl then return false end
    return (pcall(function(...)
        local win = sdl.SDL_GL_GetCurrentWindow()
        if win == nil then error("no window") end
        sdl[name](win, ...)
    end, ...))
end

local function display_index()
    local count = love.window.getDisplayCount()
    return math.max(1, math.min(count, CFG.display))
end

-- Cells keep the display's aspect ratio so a fractional mouse position lands on
-- the same spot whether an instance is in the grid or zoomed.
local function target_rect()
    local W, H = love.window.getDesktopDimensions(display_index())
    if V.zoom == ID then return 0, 0, W, H end
    local g = ceil(math.sqrt(N))
    local cw, ch = floor(W / g), floor(H / g)
    local rows = ceil(N / g)
    local row, col = floor((ID - 1) / g), (ID - 1) % g
    local in_row = (row == rows - 1) and (N - g * (rows - 1)) or g
    local x = floor((W - in_row * cw) / 2) + col * cw
    local y = floor((H - rows * ch) / 2) + row * ch
    return x, y, cw, ch
end

local window_ready = false
local function hard_set_mode(x, y, w, h)
    real.setMode(w, h, {
        fullscreen = false, borderless = true, resizable = false, vsync = 0,
        display = display_index(), x = x, y = y, highdpi = false,
        minwidth = 1, minheight = 1,
    })
end

local function apply_layout()
    local x, y, w, h = target_rect()
    if not window_ready then
        hard_set_mode(x, y, w, h)
        window_ready = true
    else
        local cw, ch = love.graphics.getDimensions()
        if cw ~= w or ch ~= h then
            -- Resizing through SDL is instant; setMode would rebuild the whole window.
            if not sdl_window_call("SDL_SetWindowSize", w, h) then hard_set_mode(x, y, w, h) end
        end
    end
    love.window.setPosition(x, y, display_index())
    local zoomed = V.zoom == ID
    sdl_window_call("SDL_SetWindowAlwaysOnTop", zoomed and 1 or 0)
    if zoomed then sdl_window_call("SDL_RaiseWindow") end
end

-- The game configures its own window at startup and from the settings menu.
-- Route all of that to the harness layout instead.
love.window.setMode = function() apply_layout(); return true end
love.window.updateMode = function() apply_layout(); return true end
love.window.setFullscreen = function() return true end

local function apply_audio()
    local audible = (V.zoom == 0 and ID == 1) or V.zoom == ID
    local want = audible and 1 or 0
    if love.audio and love.audio.getVolume() ~= want then love.audio.setVolume(want) end
end

local function apply_zoom(k)
    V.zoom = k
    apply_layout()
    apply_audio()
end

---------------------------------------------------------------------------
-- Network: line-based messages over localhost TCP, hub and spoke.
---------------------------------------------------------------------------
local socket = require("socket")
local is_hub = ID == 1
local server          -- hub: listening socket
local conns = {}      -- hub: connected instances
local link            -- spoke: connection to the hub
local retry_at = 0

local function new_conn(sock)
    sock:settimeout(0)
    sock:setoption("tcp-nodelay", true)
    return { sock = sock, inbuf = "", out = "" }
end

local function conn_flush(c)
    if c.out == "" then return end
    local sent, err, last = c.sock:send(c.out)
    if sent then
        c.out = ""
    elseif err == "timeout" then
        c.out = c.out:sub((last or 0) + 1)
    else
        c.dead = true
    end
end

local function conn_send(c, line)
    c.out = c.out .. line .. "\n"
    conn_flush(c)
end

local function conn_read(c, on_line)
    while true do
        local data, err, partial = c.sock:receive(4096)
        local chunk = data or partial
        if chunk and #chunk > 0 then c.inbuf = c.inbuf .. chunk end
        if not data then
            if err ~= "timeout" then c.dead = true end
            break
        end
    end
    local start = 1
    while true do
        local nl = c.inbuf:find("\n", start, true)
        if not nl then break end
        on_line(c.inbuf:sub(start, nl - 1), c)
        start = nl + 1
    end
    c.inbuf = c.inbuf:sub(start)
end

-- Send a message originating here to every other instance.
local function emit(line)
    if is_hub then
        for _, c in ipairs(conns) do conn_send(c, line) end
    elseif link then
        conn_send(link, line)
    end
end

---------------------------------------------------------------------------
-- Applying input to this instance's game
---------------------------------------------------------------------------
local injecting = false

-- Call the game's callback as if the event had arrived locally.
local function inject(name, ...)
    local f = love[name]
    if not f then return end
    injecting = true
    local ok, err = pcall(f, ...)
    injecting = false
    if not ok then error(err, 0) end
end

local A = {}
function A.move(x, y)
    local ox, oy = local_xy()
    V.x, V.y = x, y
    local nx, ny = local_xy()
    inject("mousemoved", nx, ny, nx - ox, ny - oy, false)
end
function A.press(x, y, b)
    V.x, V.y = x, y
    V.buttons[b] = true
    local nx, ny = local_xy()
    inject("mousepressed", nx, ny, b, false, 1)
end
function A.release(x, y, b)
    V.x, V.y = x, y
    V.buttons[b] = nil
    local nx, ny = local_xy()
    inject("mousereleased", nx, ny, b, false, 1)
end
function A.wheel(dx, dy) inject("wheelmoved", dx, dy) end
function A.key(k, sc, rep)
    V.keys[k] = true
    inject("keypressed", k, sc, rep)
end
function A.keyup(k, sc)
    V.keys[k] = nil
    inject("keyreleased", k, sc)
end
function A.text(t) inject("textinput", t) end

local function to_hex(s) return (s:gsub(".", function(c) return ("%02x"):format(c:byte()) end)) end
local function from_hex(s) return (s:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)) end

-- Handle a message from another instance.
local function handle(line)
    local f = {}
    for tok in line:gmatch("%S+") do f[#f + 1] = tok end
    local t = f[1]
    if t == "m" then
        V.hover = tonumber(f[2]) or V.hover
        A.move(tonumber(f[3]), tonumber(f[4]))
    elseif t == "p" then
        V.hover = tonumber(f[2]) or V.hover
        A.press(tonumber(f[3]), tonumber(f[4]), tonumber(f[5]))
    elseif t == "r" then
        A.release(tonumber(f[3]), tonumber(f[4]), tonumber(f[5]))
    elseif t == "w" then
        A.wheel(tonumber(f[2]), tonumber(f[3]))
    elseif t == "k" then
        A.key(f[2], f[3], f[4] == "1")
    elseif t == "u" then
        A.keyup(f[2], f[3])
    elseif t == "t" then
        A.text(from_hex(f[2] or ""))
    elseif t == "z" then
        apply_zoom(tonumber(f[2]) or 0)
    elseif t == "q" then
        love.event.quit()
    end
end

local function hub_on_line(line, from)
    for _, c in ipairs(conns) do
        if c ~= from then conn_send(c, line) end
    end
    handle(line)
end

local function net_poll()
    local now = love.timer.getTime()
    if is_hub then
        if not server and now >= retry_at then
            retry_at = now + 0.5
            local s = socket.bind("127.0.0.1", CFG.port)
            if s then s:settimeout(0); server = s end
        end
        if server then
            while true do
                local s = server:accept()
                if not s then break end
                local c = new_conn(s)
                conns[#conns + 1] = c
                -- Bring a newly connected instance up to date.
                conn_send(c, ("z %d"):format(V.zoom))
                conn_send(c, ("m %d %.5f %.5f"):format(V.hover, V.x, V.y))
            end
        end
        for _, c in ipairs(conns) do
            conn_flush(c)
            conn_read(c, hub_on_line)
        end
        for i = #conns, 1, -1 do
            if conns[i].dead then
                conns[i].sock:close()
                table.remove(conns, i)
            end
        end
    else
        if not link and now >= retry_at then
            retry_at = now + 0.5
            local s = socket.tcp()
            s:settimeout(0.05)
            if s:connect("127.0.0.1", CFG.port) then
                link = new_conn(s)
            else
                s:close()
            end
        end
        if link then
            conn_flush(link)
            conn_read(link, handle)
            if link.dead then
                link.sock:close()
                link = nil
            end
        end
    end
end

---------------------------------------------------------------------------
-- Capturing real input
---------------------------------------------------------------------------
local pending_move -- latest real mouse position this frame, sent once per frame

local function norm(x, y)
    local w, h = love.graphics.getDimensions()
    return x / math.max(1, w), y / math.max(1, h)
end

local function flush_move()
    if not pending_move then return end
    local x, y = pending_move[1], pending_move[2]
    pending_move = nil
    V.hover = ID
    emit(("m %d %.5f %.5f"):format(ID, x, y))
    A.move(x, y)
end

-- Replace a game callback: real events go to on_real, injected ones to the game.
local function capture(name, on_real)
    local orig = love[name]
    love[name] = function(...)
        if injecting then
            if orig then return orig(...) end
            return
        end
        return on_real(...)
    end
end

local function set_zoom_everywhere(k)
    emit(("z %d"):format(k))
    apply_zoom(k)
end

local function is_hotkey(key)
    local K = CFG.keys
    return key == K.zoom or key == K.prev or key == K.next or key == K.quit
end

local function hotkey(key, isrepeat)
    if isrepeat then return end
    local K = CFG.keys
    if key == K.zoom then
        set_zoom_everywhere(V.zoom ~= 0 and 0 or V.hover)
    elseif key == K.prev or key == K.next then
        local cur = V.zoom ~= 0 and V.zoom or V.hover
        local step = key == K.next and 1 or -1
        set_zoom_everywhere((cur - 1 + step) % N + 1)
    elseif key == K.quit then
        if real.kbIsDown("lctrl", "rctrl") then
            emit("q")
            love.event.quit()
        end
    end
end

capture("mousemoved", function(x, y)
    pending_move = { norm(x, y) }
end)
capture("mousepressed", function(x, y, button)
    pending_move = nil
    local nx, ny = norm(x, y)
    V.hover = ID
    emit(("p %d %.5f %.5f %d"):format(ID, nx, ny, button))
    A.press(nx, ny, button)
end)
capture("mousereleased", function(x, y, button)
    pending_move = nil
    local nx, ny = norm(x, y)
    emit(("r %d %.5f %.5f %d"):format(ID, nx, ny, button))
    A.release(nx, ny, button)
end)
capture("wheelmoved", function(dx, dy)
    emit(("w %s %s"):format(dx, dy))
    A.wheel(dx, dy)
end)
capture("keypressed", function(key, scancode, isrepeat)
    if is_hotkey(key) then return hotkey(key, isrepeat) end
    scancode = scancode or key
    emit(("k %s %s %d"):format(key, scancode, isrepeat and 1 or 0))
    A.key(key, scancode, isrepeat and true or false)
end)
capture("keyreleased", function(key, scancode)
    if is_hotkey(key) then return end
    scancode = scancode or key
    emit(("u %s %s"):format(key, scancode))
    A.keyup(key, scancode)
end)
capture("textinput", function(text)
    emit("t " .. to_hex(text))
    A.text(text)
end)

---------------------------------------------------------------------------
-- Different seed per instance: the game derives a new run's seed from the
-- cursor position, which is identical everywhere, so salt it per instance.
---------------------------------------------------------------------------
local function wrap_seed()
    local orig = rawget(_G, "generate_starting_seed")
    if type(orig) ~= "function" then return end
    generate_starting_seed = function(...)
        local randomseed = math.randomseed
        local salt = ID * 1009.31 + os.time() % 100000 + (love.timer.getTime() % 1)
        randomseed(salt * 1000)
        math.randomseed = function(s) return randomseed((tonumber(s) or 0) + salt) end
        local ok, seed = pcall(orig, ...)
        math.randomseed = randomseed
        if not ok then error(seed, 0) end
        return seed
    end
end

---------------------------------------------------------------------------
-- Frame hooks
---------------------------------------------------------------------------
local game_load, game_update, game_draw = love.load, love.update, love.draw
local last_w, last_h
local label_font

love.load = function(...)
    if game_load then game_load(...) end
    if not use_steam and G then G.STEAM = nil end
    wrap_seed()
    apply_layout()
    apply_audio()
end

love.update = function(dt)
    net_poll()
    flush_move()
    -- Window size changes made by the harness do not raise a resize event.
    local w, h = love.graphics.getDimensions()
    if w ~= last_w or h ~= last_h then
        last_w, last_h = w, h
        if love.resize then love.resize(w, h) end
    end
    if G then G.FPS_CAP = CFG.fps end
    apply_audio()
    if game_update then game_update(dt) end
end

love.draw = function()
    if game_draw then game_draw() end
    if not CFG.label then return end
    label_font = label_font or love.graphics.newFont(13)
    local text = "#" .. ID
    if is_hub and not server then text = text .. " (port busy)" end
    if not is_hub and not link then text = text .. " (no link)" end
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setCanvas()
    love.graphics.setShader()
    love.graphics.setScissor()
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 0, 0, label_font:getWidth(text) + 10, label_font:getHeight() + 4)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(text, label_font, 5, 2)
    love.graphics.pop()
end

end)()
