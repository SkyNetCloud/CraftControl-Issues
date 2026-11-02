---------------------------------------------
--      Power module for CraftControl
--      by SkyNetCloud
--		craftcontrol.skynetcloud.ca
---------------------------------------------

-- variables

local bat={}
local version = 3

local installer = "https://craftcontrol.skynetcloud.ca/modules/installer.lua"
local token = '0'
local module_name = ''
local username = ''
local module_type = ''

-- write text to the terminal screen
function draw_text_term(x, y, text, text_color, bg_color)
    term.setTextColor(text_color)
    term.setBackgroundColor(bg_color)
    term.setCursorPos(x,y)
    write(text)
end

-- draw a line on the terminal screen
function draw_line_term(x, y, length, color)
    term.setBackgroundColor(color)
    term.setCursorPos(x,y)
    term.write(string.rep(" ", length))
end

function bars()
	draw_line_term(1, 1, 51, colors.lime)
	draw_line_term(1, 19, 51, colors.lime)
	draw_text_term(15, 1, 'CraftControl Energy Module', colors.gray, colors.lime)
	draw_text_term(10, 19, 'craftcontrol.skynetcloud.ca', colors.gray, colors.lime)
end

function terminal_screen()
	term.clear()
	bars()
	draw_text_term(1, 2, 'Module: ', colors.lime, colors.black)
	draw_text_term(10, 2, module_name, colors.white, colors.black)
	draw_text_term(1, 3, 'Owner: ', colors.lime, colors.black)
	draw_text_term(8, 3, username, colors.white, colors.black)
	draw_text_term(1, 4 , string.rep("-", 51), colors.lime, colors.black)
end

-- retrieves token from local text file
function load_config()
    sr = fs.open("config.txt", "r")
    token = sr.readLine()
    module_name = sr.readLine()
    username = sr.readLine()
    module_type = sr.readLine()
    sr.close()
end

-- called for new installations and when the scanner needs to be updated
function run_installer()
    if fs.exists("install") then
        fs.delete("install")
    end
    shell.run("wget", installer, "install")
    sleep(1)
    shell.run("install")
end


------  Start module specific code ---------

local function urlencode(str)
    return (string.gsub(tostring(str), "([^%w%-%._~])", function(c) return string.format("%%%02X", string.byte(c)) end))
end

function phone_home(bat_name, energy_type, percent)
    local ok, response = pcall(http.post, "https://craftcontrol.skynetcloud.ca/code/energy.php",
        "token="..token.."&id="..os.getComputerID().."&bat_name="..urlencode(bat_name)..
        "&energy_type="..urlencode(energy_type).."&percent="..urlencode(percent))
    if not ok or not response then
        return false, "could not reach server"
    end
    local return_string = response.readAll()
    response.close()

    if tonumber(return_string) == nil then
        return false, "server rejected data: "..tostring(return_string)
    end
    if tonumber(return_string) > version then
        run_installer()
    end
    return true
end

function round(num, idp)
    local mult = 10^(idp or 0)
    return math.floor(num * mult + 0.5) / mult
end

-- each reader returns stored, capacity, unit or nil. Tried in order.
local readers = {
    -- Mekanism energy cubes / generic CC:Tweaked energy peripherals
    {"J",  "getEnergy",          "getMaxEnergy"},
    {"FE", "getEnergy",          "getEnergyCapacity"},
    -- CoFH / Thermal / most RF blocks
    {"RF", "getEnergyStored",    "getMaxEnergyStored"},
    -- IndustrialCraft 2
    {"EU", "getEUStored",        "getEUCapacity"},
}

function readBattery(name)
    local p = peripheral.wrap(name)
    if not p then return nil end
    for _, r in ipairs(readers) do
        local unit, getStored, getMax = r[1], r[2], r[3]
        if type(p[getStored]) == "function" and type(p[getMax]) == "function" then
            local ok1, stored = pcall(p[getStored])
            local ok2, cap = pcall(p[getMax])
            if ok1 and ok2 and tonumber(stored) and tonumber(cap) and cap > 0 then
                return stored, cap, unit
            end
        end
    end
    return nil
end

-- 1234567 -> "1.23M"
local function short(n)
    local units = {"", "k", "M", "G", "T", "P"}
    local i = 1
    n = tonumber(n) or 0
    while math.abs(n) >= 1000 and i < #units do
        n = n / 1000
        i = i + 1
    end
    if i == 1 then return string.format("%d", math.floor(n)) end
    return string.format("%.2f%s", n, units[i])
end

local function duration(seconds)
    seconds = math.floor(seconds)
    local d, h, m, s = math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600), math.floor(seconds % 3600 / 60), seconds % 60
    if seconds >= 86400 then return string.format("%dd %dh", d, h) end
    if seconds >= 3600 then return string.format("%dh %dm", math.floor(seconds / 3600), m) end
    if seconds >= 60 then return string.format("%dm %ds", math.floor(seconds / 60), s) end
    return seconds .. "s"
end

local function levelColor(percent)
    if percent <= 15 then return colors.red end
    if percent <= 40 then return colors.orange end
    return colors.lime
end

-- clears one line, then writes text on it so a redraw never flickers
local function line(y, text, color)
    local w = term.getSize()
    draw_line_term(1, y, w, colors.black)
    if text and text ~= "" then draw_text_term(1, y, text, color or colors.white, colors.black) end
end

function drawBar(percent)
    local w = term.getSize()
    local barLen = w - 2
    local filled = math.floor(barLen * percent / 100 + 0.5)
    local fillColor = levelColor(percent)
    local label = string.format("%.1f%%", percent)
    local labelStart = math.floor((barLen - #label) / 2) + 1

    for row = 7, 9 do
        draw_line_term(2, row, filled, fillColor)
        draw_line_term(2 + filled, row, barLen - filled, colors.gray)
    end
    -- percent label centred on the middle row, drawn over whichever colour is under it
    for i = 1, #label do
        local x = labelStart + i - 1
        term.setCursorPos(1 + x, 8)
        term.setBackgroundColor(x <= filled and fillColor or colors.gray)
        term.setTextColor(colors.black)
        term.write(label:sub(i, i))
    end
    term.setBackgroundColor(colors.black)
end

local lastStored, lastTime, rate = nil, nil, nil
local lastSync, syncError = nil, nil
local SYNC_EVERY = 30
local REFRESH = 5

-- energy change per second, smoothed so one noisy reading doesn't swing the display
local function updateRate(stored)
    local now = os.clock()
    if lastStored and now > lastTime then
        local instant = (stored - lastStored) / (now - lastTime)
        rate = rate and (rate * 0.6 + instant * 0.4) or instant
    end
    lastStored, lastTime = stored, now
end

-- "left" -> "Left side"; "mekanism:basic_energy_cube_3" -> "Basic Energy Cube #3"
local function prettyName(name)
    local sides = {left = "Left", right = "Right", top = "Top", bottom = "Bottom", front = "Front", back = "Back"}
    if sides[name] then return sides[name] .. " side" end
    local n = name:gsub("^[^:]*:", "")
    local num = n:match("[_%s](%d+)$")
    if num then n = n:gsub("[_%s]%d+$", "") end
    n = n:gsub("(%l)(%u)", "%1 %2"):gsub("[_%-]+", " ")
    n = n:gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end)
    return num and (n .. " #" .. num) or n
end

function drawDetails(name, stored, cap, unit, percent)
    line(6, "")
    draw_text_term(2, 6, prettyName(name), colors.white, colors.black)
    local w = term.getSize()
    draw_text_term(w - #unit - 1, 6, " " .. unit .. " ", colors.black, colors.lightGray)
    term.setBackgroundColor(colors.black)
    drawBar(percent)

    line(11, "Stored:   " .. short(stored) .. " / " .. short(cap) .. " " .. unit, colors.white)

    if rate and math.abs(rate) >= 0.5 then
        local charging = rate > 0
        line(12, string.format("%s %s%s/s", charging and "Charging:" or "Draining:", short(math.abs(rate)), " " .. unit),
            charging and colors.lime or colors.orange)
        local remaining = charging and (cap - stored) or stored
        line(13, (charging and "Full in:  " or "Empty in: ") .. duration(remaining / math.abs(rate)), colors.lightGray)
    else
        line(12, "Steady (no change)", colors.lightGray)
        line(13, "")
    end

    if syncError then
        line(15, "Server: " .. syncError, colors.red)
    elseif lastSync then
        line(15, "Server: online, synced " .. duration(os.clock() - lastSync) .. " ago", colors.lime)
    else
        line(15, "Server: connecting...", colors.lightGray)
    end
end

function start_loop()
    terminal_screen()
    local tick = 0
    while true do
        local found = false
        for _, name in ipairs(peripheral.getNames()) do
            local stored, cap, unit = readBattery(name)
            if stored then
                found = true
                local percent = round(stored / cap * 100, 1)
                if percent > 100 then percent = 100 end
                updateRate(stored)
                if tick % math.floor(SYNC_EVERY / REFRESH) == 0 then
                    local ok, err = phone_home(name, unit, percent)
                    if ok then
                        lastSync, syncError = os.clock(), nil
                    else
                        syncError = err
                    end
                end
                drawDetails(name, stored, cap, unit, percent)
                break
            end
        end
        if not found then
            terminal_screen()
            draw_text_term(1, 6, "No power storage found.", colors.red, colors.black)
            draw_text_term(1, 7, "Place the computer next to an energy", colors.white, colors.black)
            draw_text_term(1, 8, "cube / battery (or attach a wired modem).", colors.white, colors.black)
            local names = peripheral.getNames()
            draw_text_term(1, 10, "Peripherals seen: "..(#names > 0 and table.concat(names, ", ") or "none"), colors.lightGray, colors.black)
            lastStored, rate = nil, nil
        end
        term.setBackgroundColor(colors.black)
        tick = tick + 1
        sleep(REFRESH)
    end
end

function start()
    term.clear()
    term.setCursorPos(1,1)

    if fs.exists("config.txt") then
        load_config()
        local ok, err = pcall(start_loop)
        if not ok then
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.red)
            print("Module crashed: "..tostring(err))
            term.setTextColor(colors.white)
        end
    else
        run_installer()
    end
end

start()
