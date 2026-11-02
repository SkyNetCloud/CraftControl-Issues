-- CraftControl
-- Reactor control module (Mekanism fission reactor or Big/Extreme Reactors)
-- Attach this computer to the Fission Reactor Logic Adapter, or to a Reactor Computer Port.
local version = 5

local installer = "https://craftcontrol.skynetcloud.ca/modules/installer.lua"
local token = '0'
local module_name = ''
local username = ''
local type = ''

------  Safety limits. The computer enforces these itself, even when the website is unreachable. ------
local LIMITS = {
    mekanism = {
        maxTemp = 1000,     -- Kelvin
        maxDamage = 10,     -- percent
        minCoolant = 15,    -- percent
        maxWaste = 90,      -- percent
    },
    -- Big/Bigger Reactors cannot explode from heat, so there is no automatic scram
    bigreactor = {},
}
local BR_ENERGY_CAPACITY = 10000000

local reactor = nil
local kind = nil
local latched = false        -- set after a safety scram; only cleared once the site shows "off"
local reason = ''            -- last safety scram reason, reported to the site
local desired_active = false
local desired_level = 0
local status = 'starting'
local reading = nil

function draw_text_term(x, y, text, text_color, bg_color)
    term.setTextColor(text_color)
    term.setBackgroundColor(bg_color)
    term.setCursorPos(x, y)
    write(text)
end

function draw_line_term(x, y, length, color)
    term.setBackgroundColor(color)
    term.setCursorPos(x, y)
    term.write(string.rep(" ", length))
end

function bars()
    draw_line_term(1, 1, 51, colors.lime)
    draw_line_term(1, 19, 51, colors.lime)
    draw_text_term(15, 1, 'CraftControl Reactor Control', colors.gray, colors.lime)
    draw_text_term(10, 19, 'craftcontrol.skynetcloud.ca', colors.gray, colors.lime)
end

-- clears one line, then writes on it, so redrawing every second never flickers
local function line(y, text, color)
    draw_line_term(1, y, 51, colors.black)
    if text and text ~= '' then draw_text_term(1, y, text, color or colors.white, colors.black) end
end

-- labelled bar: "Fuel     [#########-------]  97%"
-- goodHigh = true when a full bar is healthy (fuel, energy, coolant); false for waste and damage
local function stat_bar(y, label, percent, fillColor, goodHigh)
    percent = math.max(0, math.min(100, percent or 0))
    local w = term.getSize()
    local barLen = w - 8 - 6
    local filled = math.floor(barLen * percent / 100 + 0.5)
    local color = fillColor
    if goodHigh and percent <= 15 then color = colors.red end
    if not goodHigh and percent >= 75 then color = colors.red end
    if not goodHigh and percent >= 50 and percent < 75 then color = colors.orange end
    draw_text_term(1, y, string.format('%-8s', label), colors.white, colors.black)
    draw_line_term(9, y, filled, color)
    draw_line_term(9 + filled, y, barLen - filled, colors.gray)
    draw_text_term(9 + barLen + 1, y, string.format('%3.0f%%', percent), colors.white, colors.black)
    term.setBackgroundColor(colors.black)
end

function terminal_screen()
    term.setBackgroundColor(colors.black)
    bars()
    draw_text_term(1, 2, 'Module: ', colors.lime, colors.black)
    draw_text_term(10, 2, module_name, colors.white, colors.black)
    draw_text_term(1, 3, 'Owner: ', colors.lime, colors.black)
    draw_text_term(8, 3, username, colors.white, colors.black)
    draw_text_term(1, 4, string.rep("-", 51), colors.lime, colors.black)

    local kindName = kind == 'mekanism' and 'Mekanism Fission' or (kind == 'bigreactor' and 'Bigger Reactors' or 'NOT FOUND')
    line(5, 'Reactor: ' .. kindName, kind and colors.white or colors.red)
    local online = status == 'online'
    draw_text_term(34, 5, 'Server: ', colors.white, colors.black)
    draw_text_term(42, 5, online and 'online' or 'offline', online and colors.lime or colors.red, colors.black)

    if not reading then
        for y = 6, 17 do line(y, '') end
        line(7, kind and 'Waiting for reactor data...' or 'No reactor found. Attach this computer to the', colors.lightGray)
        if not kind then line(8, 'reactor computer port / logic adapter.', colors.lightGray) end
    else
        -- State banner
        local stateColor = reading.active and colors.lime or colors.orange
        draw_line_term(1, 6, 51, stateColor)
        draw_text_term(2, 6, reading.active and 'ACTIVE' or 'OFF', colors.black, stateColor)
        local want = 'Wanted: ' .. (desired_active and 'ON' or 'OFF') .. ' at ' .. desired_level .. '%'
        draw_text_term(51 - #want, 6, want, colors.black, stateColor)
        term.setBackgroundColor(colors.black)

        local unit = kind == 'mekanism' and 'K' or 'C'
        local tempColor = colors.white
        if kind == 'mekanism' and LIMITS.mekanism.maxTemp then
            local frac = reading.temperature / LIMITS.mekanism.maxTemp
            tempColor = frac >= 0.9 and colors.red or (frac >= 0.7 and colors.orange or colors.white)
        end
        line(8, string.format('Temperature: %.0f %s', reading.temperature, unit), tempColor)

        stat_bar(10, 'Fuel', reading.fuel, colors.lime, true)
        stat_bar(11, 'Waste', reading.waste, colors.yellow, false)
        local row = 12
        if kind == 'mekanism' then
            stat_bar(row, 'Damage', reading.damage, colors.lime, false)
            row = row + 1
        else
            stat_bar(row, 'Energy', reading.energy, colors.lime, true)
            row = row + 1
        end
        if reading.coolant > 0 or kind == 'mekanism' then
            stat_bar(row, 'Coolant', reading.coolant, colors.cyan, true)
            row = row + 1
        end
        for y = row, 14 do line(y, '') end

        local outputLabel = kind == 'mekanism' and 'Burn rate: %.1f mB/t' or 'Output: %.0f FE/t'
        line(15, string.format(outputLabel, reading.burn), colors.white)
    end

    if latched or reason ~= '' then
        draw_line_term(1, 17, 51, colors.red)
        draw_text_term(2, 17, 'SAFETY SCRAM: ' .. reason, colors.white, colors.red)
        term.setBackgroundColor(colors.black)
    else
        line(17, '')
    end
end

function load_config()
    local sr = fs.open("config.txt", "r")
    token = sr.readLine()
    module_name = sr.readLine()
    username = sr.readLine()
    type = sr.readLine()
    sr.close()
end

function run_installer()
    if fs.exists("install") then fs.delete("install") end
    shell.run("wget", installer, "install")
    sleep(1)
    shell.run("install")
end

------  Start module specific code ---------

local function call(fn, ...)
    local ok, value = pcall(fn, ...)
    if ok then return value end
    return nil
end

-- Mekanism reports fractions (0-1); normalise to percent.
local function pct(v)
    v = tonumber(v) or 0
    if v <= 1 then v = v * 100 end
    return v
end

local function findReactor()
    reactor, kind = nil, nil
    for _, name in ipairs(peripheral.getNames()) do
        local t = peripheral.getType(name)
        if t == "fissionReactorLogicAdapter" then
            reactor, kind = peripheral.wrap(name), "mekanism"
            return
        elseif t == "BigReactors-Reactor" or t == "bigreactors-reactor" or t == "BiggerReactors_Reactor" then
            reactor, kind = peripheral.wrap(name), "bigreactor"
            return
        end
    end
end

local function readReactor()
    if not reactor then return nil end
    local r = {}
    if kind == "mekanism" then
        r.active = call(reactor.getStatus) == true
        r.temperature = tonumber(call(reactor.getTemperature)) or 0
        r.damage = pct(call(reactor.getDamagePercent))
        r.coolant = pct(call(reactor.getCoolantFilledPercentage))
        r.fuel = pct(call(reactor.getFuelFilledPercentage))
        r.waste = pct(call(reactor.getWasteFilledPercentage))
        r.burn = tonumber(call(reactor.getBurnRate)) or 0
        r.maxBurn = tonumber(call(reactor.getMaxBurnRate)) or 0
        r.energy = 0
    elseif reactor.fuelTank then
        -- Bigger Reactors (Revived): fuelTank(), battery() and coolantTank() return objects with methods
        r.active = call(reactor.active) == true
        r.temperature = math.max(tonumber(call(reactor.fuelTemperature)) or 0, tonumber(call(reactor.casingTemperature)) or 0)
        r.damage, r.coolant = 0, 0
        local tank = call(reactor.fuelTank)
        local cap = tank and tonumber(call(tank.capacity)) or 0
        r.fuel = cap > 0 and (tonumber(call(tank.fuel)) or 0) / cap * 100 or 0
        r.waste = cap > 0 and (tonumber(call(tank.waste)) or 0) / cap * 100 or 0
        local battery = call(reactor.battery)
        local bcap = battery and tonumber(call(battery.capacity)) or 0
        r.energy = bcap > 0 and (tonumber(call(battery.stored)) or 0) / bcap * 100 or 0
        r.burn = battery and tonumber(call(battery.producedLastTick)) or 0
        local coolant = call(reactor.coolantTank)
        local ccap = coolant and tonumber(call(coolant.capacity)) or 0
        r.coolant = ccap > 0 and (tonumber(call(coolant.coldFluidAmount)) or 0) / ccap * 100 or 0
    else
        r.active = call(reactor.getActive) == true
        r.temperature = tonumber(call(reactor.getFuelTemperature)) or 0
        r.damage, r.coolant = 0, 0
        local fuel, fuelMax = tonumber(call(reactor.getFuelAmount)) or 0, tonumber(call(reactor.getFuelAmountMax)) or 0
        r.fuel = fuelMax > 0 and fuel / fuelMax * 100 or 0
        local waste = tonumber(call(reactor.getWasteAmount)) or 0
        r.waste = fuelMax > 0 and waste / fuelMax * 100 or 0
        r.energy = (tonumber(call(reactor.getEnergyStored)) or 0) / BR_ENERGY_CAPACITY * 100
        r.burn = tonumber(call(reactor.getEnergyProducedLastTick)) or 0
    end
    return r
end

-- Returns a reason string when the reactor is outside its safe limits, otherwise nil.
local function unsafeReason(r)
    local l = LIMITS[kind]
    if kind == "mekanism" then
        if r.temperature > l.maxTemp then return 'temperature too high' end
        if r.damage > l.maxDamage then return 'reactor damage' end
        if r.active and r.coolant < l.minCoolant then return 'coolant low' end
        if r.waste > l.maxWaste then return 'waste full' end
    end
    return nil
end

local function scram()
    if kind == "mekanism" then
        call(reactor.scram)
    elseif kind == "bigreactor" then
        call(reactor.setActive, false)
        if reactor.fuelTank then call(reactor.setAllControlRodLevels, 100) end
    end
end

local function setLevel(level)
    if kind == "mekanism" then
        local max = tonumber(call(reactor.getMaxBurnRate)) or 0
        call(reactor.setBurnRate, max * level / 100)
    else
        -- Control rods: 100 is fully inserted (no output), so output is the inverse.
        call(reactor.setAllControlRodLevels, 100 - level)
    end
end

-- Runs every second: safety first, then bring the reactor to the wanted state.
local function control()
    if not reactor then findReactor() end
    if not reactor then return end

    reading = readReactor()
    local bad = unsafeReason(reading)
    if bad then
        if reading.active then scram() end
        latched = true
        reason = bad
        reading.active = false
        return
    end

    if latched or not desired_active then
        if reading.active then scram() end
        return
    end

    setLevel(desired_level)
    if not reading.active then
        if kind == "mekanism" then call(reactor.activate) else call(reactor.setActive, true) end
    end
end

local function splitLines(s)
    local out = {}
    for line in string.gmatch(s, "[^\r\n]+") do out[#out + 1] = line end
    return out
end

local function phone_home()
    local r = reading or { active = false, temperature = 0, damage = 0, coolant = 0, fuel = 0, waste = 0, burn = 0, energy = 0 }
    local body = "token=" .. textutils.urlEncode(token) .. "&id=" .. os.getComputerID() ..
        "&kind=" .. (kind or "") ..
        "&active=" .. (r.active and 1 or 0) ..
        "&reason=" .. textutils.urlEncode(latched and reason or "") ..
        "&temperature=" .. r.temperature .. "&damage=" .. r.damage .. "&coolant=" .. r.coolant ..
        "&fuel=" .. r.fuel .. "&waste=" .. r.waste .. "&burn=" .. r.burn .. "&energy=" .. r.energy

    local response = http.post("https://craftcontrol.skynetcloud.ca/code/reactor.php", body)
    if not response then
        status = 'offline (safety still active)'
        return
    end
    local text = response.readAll()
    response.close()
    status = 'online'

    local lines = splitLines(text)
    local current_version = tonumber(lines[1])
    if current_version and current_version > version then
        run_installer()
        return
    end

    desired_active = lines[2] == "1"
    desired_level = math.max(0, math.min(100, tonumber(lines[3]) or 0))
    -- The site shows "off" once it has seen the scram; only then may a new start be accepted.
    if not desired_active and latched then
        latched = false
        reason = ''
    end
end

------  End module specific code ---------

function start_loop()
    term.setBackgroundColor(colors.black)
    term.clear()
    findReactor()
    local tick = 0
    while true do
        pcall(control)
        if tick % 2 == 0 then pcall(phone_home) end
        terminal_screen()
        tick = tick + 1
        sleep(1)
    end
end

function start()
    term.clear()
    term.setCursorPos(1, 1)
    if fs.exists("config.txt") then
        load_config()
        start_loop()
    else
        run_installer()
    end
end

start()
