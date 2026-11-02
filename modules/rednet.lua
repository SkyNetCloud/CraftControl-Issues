-- CraftControl
-- Rednet gateway module
-- Relays redstone commands from the website to other computers over rednet.
-- Needs a wired or wireless modem attached to this computer.
local version = 1

local installer = "https://craftcontrol.skynetcloud.ca/modules/installer.lua"
local PROTOCOL = "craftcontrol"
local token = '0'
local module_name = ''
local username = ''
local type = ''

local targets = {}   -- list of { id, side, output, ok }
local acked = {}     -- ["id:side"] = true, reported to the server on the next poll
local status = 'starting'
local modem_name = nil

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
    draw_text_term(14, 1, 'CraftControl Rednet Gateway', colors.gray, colors.lime)
    draw_text_term(10, 19, 'craftcontrol.skynetcloud.ca', colors.gray, colors.lime)
end

function terminal_screen()
    term.clear()
    bars()
    draw_text_term(1, 2, 'Module: ', colors.lime, colors.black)
    draw_text_term(10, 2, module_name, colors.white, colors.black)
    draw_text_term(1, 3, 'Owner: ', colors.lime, colors.black)
    draw_text_term(8, 3, username, colors.white, colors.black)
    draw_text_term(1, 4, string.rep("-", 51), colors.lime, colors.black)
    draw_text_term(1, 5, 'Modem: ' .. (modem_name or 'NOT FOUND'), modem_name and colors.white or colors.red, colors.black)
    draw_text_term(1, 6, 'Server: ' .. status, colors.white, colors.black)

    local row = 8
    for _, t in ipairs(targets) do
        if row > 17 then break end
        local line = string.format('#%d %-6s %s', t.id, t.side, t.output == 1 and 'ON ' or 'OFF')
        draw_text_term(2, row, line .. (t.ok and '  ok' or '  no reply'), t.ok and colors.lime or colors.orange, colors.black)
        row = row + 1
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

local function openModem()
    modem_name = nil
    for _, name in ipairs(peripheral.getNames()) do
        if peripheral.getType(name) == "modem" then
            if not rednet.isOpen(name) then rednet.open(name) end
            modem_name = name
            return true
        end
    end
    return false
end

local function splitLines(s)
    local out = {}
    for line in string.gmatch(s, "[^\r\n]+") do out[#out + 1] = line end
    return out
end

local function phone_home()
    local seen = {}
    for key in pairs(acked) do seen[#seen + 1] = key end
    acked = {}

    local response = http.post("https://craftcontrol.skynetcloud.ca/code/rednet.php",
        "token=" .. textutils.urlEncode(token) .. "&id=" .. os.getComputerID() ..
        "&seen=" .. textutils.urlEncode(table.concat(seen, ",")))
    if not response then
        status = 'offline'
        return
    end
    local body = response.readAll()
    response.close()
    status = 'online'

    local lines = splitLines(body)
    local current_version = tonumber(lines[1])
    if current_version and current_version > version then
        run_installer()
        return
    end

    targets = {}
    for i = 2, #lines do
        local id, side, output = string.match(lines[i], "^(%d+),(%a+),([01])$")
        if id then
            targets[#targets + 1] = { id = tonumber(id), side = side, output = tonumber(output), ok = false }
        end
    end
end

-- Sends every target its desired state, then collects acknowledgements for a short time.
local function relay()
    if not modem_name and not openModem() then return end

    for _, t in ipairs(targets) do
        rednet.send(t.id, { cn = "set", side = t.side, on = t.output == 1 }, PROTOCOL)
    end

    local pending = #targets
    local deadline = os.clock() + 1.5
    while pending > 0 and os.clock() < deadline do
        local sender, msg = rednet.receive(PROTOCOL, math.max(0.1, deadline - os.clock()))
        if sender and _G.type(msg) == "table" and msg.cn == "ack" then
            for _, t in ipairs(targets) do
                if t.id == sender and t.side == msg.side and not t.ok then
                    t.ok = true
                    pending = pending - 1
                    acked[sender .. ":" .. msg.side] = true
                end
            end
        end
    end
end

------  End module specific code ---------

function start_loop()
    openModem()
    pcall(phone_home)
    while true do
        pcall(relay)
        terminal_screen()
        sleep(1)
        pcall(phone_home)
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
