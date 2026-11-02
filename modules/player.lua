-- Base Scanner
-- Supports Advanced Peripherals (Player Detector + Inventory Manager)
-- and OpenPeripherals (Sensor).

-- ===== Config =====
local installer = "https://craftcontrol.skynetcloud.ca/modules/installer.lua"
local RANGE = 32 -- scan radius, centred on the Player Detector block
-- players ignored by the scanner
local allowedPlayerArray = {
    -- ["Topher"]=true, ["nunley21"]=true, ["Demethan"]=true, ["waerloga"]=true,
}

-- ===== State =====
local present = {}   -- [ign] = true while inside range
local lastInv = {}   -- [ign] = { [itemName] = totalCount } (card owner only)
local heart = 0
local time = 0
local token = '0'
local scanner = ''
local username = ''
local version = 3
local detector, manager, sensor

-- ===== Peripheral lookup =====
-- Advanced Peripherals: Player Detector (+ Inventory Manager). OpenPeripherals: Sensor.
local function findPeripherals()
    detector = peripheral.find("player_detector") or peripheral.find("playerDetector")
    manager  = peripheral.find("inventory_manager") or peripheral.find("inventoryManager")
    sensor   = peripheral.find("openperipheral_sensor") or peripheral.find("sensor")
    return detector ~= nil or sensor ~= nil
end

-- ===== Backend abstraction =====
-- Returns a list of player names currently in range, or nil on failure.
local function listPlayers()
    if detector then
        local ok, players = pcall(detector.getPlayersInRange, RANGE)
        if ok and type(players) == "table" then return players end
        return nil
    end
    local ok, players = pcall(sensor.getPlayers)
    if not ok or type(players) ~= "table" then return nil end
    local names = {}
    for _, p in pairs(players) do
        if type(p) == "table" and p.name then
            names[#names + 1] = p.name
        elseif type(p) == "string" then
            names[#names + 1] = p
        end
    end
    return names
end

local function getPos(ign)
    if detector and detector.getPlayerPos then
        local ok, info = pcall(detector.getPlayerPos, ign)
        if ok and type(info) == "table" and info.x then
            return string.format(" at %d,%d,%d", info.x, info.y, info.z)
        end
    end
    return ""
end

-- Returns { [itemName] = totalCount } or nil when this player's inventory can't be read.
-- Inventory Manager: only the Memory Card owner. Sensor: any player in range.
local function getInventory(ign)
    if manager then
        local okOwner, owner = pcall(manager.getOwner)
        if okOwner and owner == ign then
            local okItems, items = pcall(manager.getItems)
            if okItems and type(items) == "table" then
                local totals = {}
                for _, it in pairs(items) do
                    totals[it.name] = (totals[it.name] or 0) + (it.count or 1)
                end
                return totals
            end
        end
    end
    if sensor then
        local okP, pdata = pcall(sensor.getPlayerByName, ign)
        if not okP or not pdata then return nil end
        local okA, data = pcall(pdata.all)
        local inv = okA and type(data) == "table" and data.player and data.player.inventory
        if type(inv) ~= "table" then return nil end
        local totals = {}
        for _, slot in pairs(inv) do
            if type(slot) == "table" then
                if type(slot.all) == "function" then
                    local okS, sd = pcall(slot.all)
                    slot = okS and sd or nil
                end
                if slot and slot.name then
                    totals[slot.name] = (totals[slot.name] or 0) + (slot.qty or slot.count or 1)
                end
            end
        end
        return totals
    end
    return nil
end

-- ===== Terminal helpers =====
local function draw_text_term(x, y, text, text_color, bg_color)
    term.setTextColor(text_color)
    term.setBackgroundColor(bg_color)
    term.setCursorPos(x, y)
    write(text)
end

local function draw_line_term(x, y, length, color)
    term.setBackgroundColor(color)
    term.setCursorPos(x, y)
    term.write(string.rep(" ", length))
end

local function bars()
    draw_line_term(1, 1, 51, colors.lime)
    draw_line_term(1, 19, 51, colors.lime)
    draw_text_term(20, 1, 'Base Scanner', colors.gray, colors.lime)
    draw_text_term(13, 19, 'craftcontrol.skynetcloud.ca', colors.gray, colors.lime)
end

local function scanner_screen()
    term.clear()
    bars()
    draw_text_term(1, 2, 'Scanner: ', colors.lime, colors.black)
    draw_text_term(10, 2, scanner, colors.white, colors.black)
    draw_text_term(1, 3, 'Owner: ', colors.lime, colors.black)
    draw_text_term(8, 3, username, colors.white, colors.black)
    draw_text_term(1, 4, string.rep("-", 51), colors.lime, colors.black)

    heart = heart + 1
    if heart > 15 then heart = 1 end
    draw_text_term(3, 10, 'Scanning ', colors.red, colors.black)
    draw_text_term(12, 10, string.rep(".", heart), colors.red, colors.black)
end

-- ===== Config / install / server =====
local function load_config()
    local sr = fs.open("config.txt", "r")
    token = sr.readLine()
    scanner = sr.readLine()
    username = sr.readLine()
    sr.close()
end

local function run_installer()
    if fs.exists("install") then fs.delete("install") end
    shell.run("wget", installer, "install")
    sleep(1)
    shell.run("install")
end

local function phone_home()
    local response = http.post("https://craftcontrol.skynetcloud.ca/code/ping.php",
        "token=" .. textutils.urlEncode(token) .. "&id=" .. os.getComputerID())
    if not response then return end
    local current_version = tonumber(response.readAll())
    response.close()
    if current_version and current_version > version then
        run_installer()
    end
end

-- event: 1 = entered, 2 = left, 3 = inventory change
local function post(ign, event, discription)
    local r = http.post("https://craftcontrol.skynetcloud.ca/code/log.php",
        "token=" .. textutils.urlEncode(token) ..
        "&ign=" .. textutils.urlEncode(ign) ..
        "&id=" .. os.getComputerID() ..
        "&event=" .. event ..
        "&discription=" .. textutils.urlEncode(discription))
    if r then r.close() end
end

-- ===== Inventory tracking =====
-- NOTE: with the Inventory Manager only the Memory Card owner's inventory is visible.
-- The OpenPeripherals Sensor can read every player in range.

local function diffInventory(old, new)
    local parts = {}
    for name, count in pairs(new) do
        local d = count - (old[name] or 0)
        if d > 0 then parts[#parts + 1] = "+" .. d .. " " .. name end
    end
    for name, count in pairs(old) do
        local d = (new[name] or 0) - count
        if d < 0 then parts[#parts + 1] = d .. " " .. name end
    end
    return parts
end

local function checkInventory(ign)
    local totals = getInventory(ign)
    if not totals then return end
    local old = lastInv[ign]
    if old then
        local changes = diffInventory(old, totals)
        if #changes > 0 then
            post(ign, 3, " inventory changed: " .. table.concat(changes, ", "))
        end
    end
    lastInv[ign] = totals
end

-- ===== Scan =====
local function record()
    local players = listPlayers()
    if not players then return end

    local seen = {}
    for _, ign in ipairs(players) do
        if not allowedPlayerArray[ign] then
            seen[ign] = true
            if not present[ign] then
                present[ign] = true
                post(ign, 1, " has entered sensor range" .. getPos(ign))
                lastInv[ign] = getInventory(ign)
            else
                checkInventory(ign)
            end
        end
    end

    -- anyone who was present but isn't now has left
    for ign in pairs(present) do
        if not seen[ign] then
            present[ign] = nil
            lastInv[ign] = nil
            post(ign, 2, " has left sensor range")
        end
    end
end

-- ===== Main =====
local function start_recording()
    while true do
        local ok, err = pcall(record)
        if not ok then
            term.setCursorPos(1, 18)
            term.setTextColor(colors.red)
            term.setBackgroundColor(colors.black)
            write(tostring(err):sub(1, 50))
        end

        scanner_screen()
        sleep(0.5)
        scanner_screen()
        sleep(0.5)

        time = time + 1
        if time > 30 then
            time = 0
            pcall(phone_home)
        end
    end
end

local function start()
    term.clear()
    term.setCursorPos(1, 1)
    if not findPeripherals() then
        error("No player detector or sensor found. Attach an Advanced Peripherals Player Detector or an OpenPeripherals Sensor.")
    end
    if fs.exists("config.txt") then
        load_config()
        start_recording()
    else
        run_installer()
    end
end

start()