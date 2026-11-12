-- Stand-in for Balatro, used to exercise the harness under plain LÖVE.
-- It copies the parts of Balatro's main.lua the harness depends on: the custom
-- love.run loop, the startup window/Steam sequence, polling love.mouse.getPosition,
-- and the seed generator. Every game-level input callback is logged to a file so
-- the logs of all instances can be compared.
--
-- Environment:
--   BM_MOD   absolute path to multi.lua
--   BM_LOG   directory for log_<id>.txt
--   BM_TEST  if set, instance 1 plays a scripted input sequence and all quit

local ID = tonumber(os.getenv("BALATRO_MULTI_ID") or "0")
local log_file = os.getenv("BM_LOG") and io.open(os.getenv("BM_LOG") .. "/log_" .. ID .. ".txt", "w")
local function log(...)
    if not log_file then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
    log_file:write(table.concat(parts, " "), "\n")
    log_file:flush()
end

G = { FPS_CAP = 500, CONTROLLER = { cursor_position = { x = 0, y = 0 } }, clicks = {}, typed = "" }

function random_string(length, seed)
    if seed then math.randomseed(seed) end
    local ret = ""
    for _ = 1, length do
        ret = ret .. string.char(math.random(string.byte("A"), string.byte("Z")))
    end
    return ret
end

function generate_starting_seed()
    return random_string(8, G.CONTROLLER.cursor_position.x * 0.33411983 + G.CONTROLLER.cursor_position.y * 0.874146)
end

function love.run()
    if love.load then love.load(love.arg.parseGameArguments(arg), arg) end
    if love.timer then love.timer.step() end
    local dt = 0
    return function()
        local run_time = love.timer.getTime()
        if love.event and G and G.CONTROLLER then
            love.event.pump()
            local _n, _a, _b, _c, _d, _e, touched
            for name, a, b, c, d, e, f in love.event.poll() do
                if name == "quit" then
                    if not love.quit or not love.quit() then return a or 0 end
                end
                if name == "touchpressed" then
                    touched = true
                elseif name == "mousepressed" then
                    _n, _a, _b, _c, _d, _e = name, a, b, c, d, e
                else
                    love.handlers[name](a, b, c, d, e, f)
                end
            end
            if _n then love.handlers["mousepressed"](_a, _b, _c, _d, _e, touched) end
        end
        if love.timer then dt = love.timer.step() end
        if love.update then love.update(dt) end
        if love.graphics and love.graphics.isActive() then
            if love.draw then love.draw() end
            love.graphics.present()
        end
        run_time = math.min(love.timer.getTime() - run_time, 0.1)
        G.FPS_CAP = G.FPS_CAP or 500
        if run_time < 1. / G.FPS_CAP then love.timer.sleep(1. / G.FPS_CAP - run_time) end
    end
end

function love.load()
    -- Like Balatro: go borderless fullscreen, then require Steam and quit if it fails.
    love.window.updateMode(1280, 720, { fullscreen = true, fullscreentype = "desktop", vsync = 1, resizable = true })
    local st = require "luasteam"
    st.send_control = {}
    if not (st.init and st:init()) then love.event.quit() end
    G.STEAM = st
    love.mouse.setVisible(false)
    log("identity", love.filesystem.getIdentity())
    log("seeded settings", love.filesystem.read("settings.jkr") or "none")
    log("seeded profile", love.filesystem.read("1/profile.jkr") or "none")
    log("seeded run", love.filesystem.read("1/save.jkr") or "none")
end

function love.resize(w, h) log("resize", w, h) end
function love.mousemoved(x, y) log("mousemoved", x / love.graphics.getWidth(), y / love.graphics.getHeight()) end
function love.mousepressed(x, y, button)
    log("mousepressed", ("%.3f %.3f"):format(x / love.graphics.getWidth(), y / love.graphics.getHeight()), button)
    G.clicks[#G.clicks + 1] = { x / love.graphics.getWidth(), y / love.graphics.getHeight() }
end
function love.mousereleased(x, y, button)
    log("mousereleased", ("%.3f %.3f"):format(x / love.graphics.getWidth(), y / love.graphics.getHeight()), button)
end
function love.keypressed(key)
    log("keypressed", key)
    G.typed = G.typed .. key .. " "
end
function love.keyreleased(key) log("keyreleased", key) end

local t, step = 0, 1
local script
if os.getenv("BM_TEST") then
    -- "Real" events are delivered the way LÖVE delivers them: through the love.* callbacks.
    script = {
        { 2.0, function() if ID == 1 then love.mousemoved(300, 200, 0, 0, false) end end },
        { 2.3, function() if ID == 1 then love.mousepressed(300, 200, 1, false, 1) end end },
        { 2.4, function() if ID == 1 then love.mousereleased(300, 200, 1, false, 1) end end },
        { 2.6, function() if ID == 1 then love.keypressed("a", "a", false); love.keyreleased("a", "a") end end },
        { 3.0, function()
            log("state", "grid", love.graphics.getDimensions())
            log("position", love.window.getPosition())
            log("mouse", love.mouse.getPosition())
            log("steam", tostring(G.STEAM))
            log("seed", generate_starting_seed())
        end },
        -- Input from a different instance, then zoom into it (it is now the hovered one).
        { 3.2, function() if ID == 2 then love.mousepressed(50, 60, 2, false, 1); love.mousereleased(50, 60, 2, false, 1) end end },
        { 3.4, function() if ID == 1 then love.keypressed("f1", "f1", false); love.keyreleased("f1", "f1") end end },
        { 4.4, function()
            log("state", "zoom2", love.graphics.getDimensions())
            log("position", love.window.getPosition())
            log("volume", love.audio.getVolume())
        end },
        { 4.5, function() if ID == 2 then love.mousepressed(960, 540, 1, false, 1); love.mousereleased(960, 540, 1, false, 1) end end },
        { 4.6, function() if ID == 1 then love.keypressed("f3", "f3", false) end end },
        { 5.6, function() log("state", "zoom3", love.graphics.getDimensions()) end },
        { 5.7, function() if ID == 1 then love.keypressed("f1", "f1", false) end end },
        { 6.7, function() log("state", "grid2", love.graphics.getDimensions()) end },
        { 7.0, function() love.event.quit() end },
    }
end

function love.update(dt)
    t = t + dt
    G.CONTROLLER.cursor_position.x, G.CONTROLLER.cursor_position.y = love.mouse.getPosition()
    while script and script[step] and t >= script[step][1] do
        script[step][2]()
        step = step + 1
    end
end

function love.draw()
    local w, h = love.graphics.getDimensions()
    love.graphics.clear(0.1 + 0.05 * (ID % 4), 0.25, 0.2 + 0.04 * ID)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(("instance %d  %dx%d  fps %d"):format(ID, w, h, love.timer.getFPS()), 10, 30)
    love.graphics.print("typed: " .. G.typed, 10, 50)
    for _, c in ipairs(G.clicks) do love.graphics.circle("line", c[1] * w, c[2] * h, 8) end
    love.graphics.setColor(1, 0.8, 0.2)
    love.graphics.circle("fill", G.CONTROLLER.cursor_position.x, G.CONTROLLER.cursor_position.y, 5)
end

-- Lovely appends the mod to main.lua; do the same here.
if os.getenv("BM_MOD") then assert(loadfile(os.getenv("BM_MOD")))() end
-- BM_TWICE simulates two installed copies of the mod.
if os.getenv("BM_MOD") and os.getenv("BM_TWICE") then assert(loadfile(os.getenv("BM_MOD")))() end
