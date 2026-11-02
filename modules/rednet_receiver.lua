-- CraftControl Rednet receiver
-- Run this on any computer that a Rednet gateway should control.
-- It sets redstone outputs when told to by the gateway, and ignores everyone else.
-- Needs a wired or wireless modem. Install with:
--   wget https://craftcontrol.skynetcloud.ca/modules/rednet_receiver.lua startup

local PROTOCOL = "craftcontrol"
local CONFIG = ".cn_gateway"
local SIDES = { top = true, bottom = true, front = true, back = true, left = true, right = true }

local gateway
if fs.exists(CONFIG) then
    local f = fs.open(CONFIG, "r")
    gateway = tonumber(f.readLine())
    f.close()
end
if not gateway then
    term.clear()
    term.setCursorPos(1, 1)
    print("CraftControl Rednet receiver")
    print("Computer ID of the gateway (run 'id' on it):")
    gateway = tonumber(read())
    if not gateway then error("That is not a computer id") end
    local f = fs.open(CONFIG, "w")
    f.writeLine(tostring(gateway))
    f.close()
end

local opened = false
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
        rednet.open(name)
        opened = true
    end
end
if not opened then error("No modem found. Attach a modem to this computer.") end

term.clear()
term.setCursorPos(1, 1)
print("Receiver ready. Computer " .. os.getComputerID() .. ", gateway " .. gateway)

while true do
    local sender, msg = rednet.receive(PROTOCOL)
    if sender == gateway and type(msg) == "table" and msg.cn == "set" and SIDES[msg.side] then
        redstone.setOutput(msg.side, msg.on == true)
        rednet.send(sender, { cn = "ack", side = msg.side }, PROTOCOL)
    end
end
