-----------------FILES------------------------------
local BASE = "https://craftcontrol.skynetcloud.ca/modules/"
local module_files = {
	["1"] = "player.lua",
	["2"] = "energy.lua",
	["3"] = "fluid.lua",
	["4"] = "redstone.lua",
	["5"] = "rednet.lua",
	["6"] = "reactor.lua",
}
---------------------------------------------
term.clear()
local token = ''
local module_name = ''
local username = ''
local type = ''
local updating = false
local user = ''

-- downloads a file hosted on the CraftControl site
local function download(path, filename)
    local site = http.get(BASE..path)
    if not site then
        error("Unable to download "..path.." from craftcontrol.skynetcloud.ca")
    end
    local content = site.readAll()
    site.close()
    local file = fs.open(filename, "w")
    file.write(content)
    file.close()
end

function draw_text_term(x, y, text, text_color, bg_color)
    term.setTextColor(text_color)
    term.setBackgroundColor(bg_color)
    term.setCursorPos(x,y)
    write(text)
end

function draw_line_term(x, y, length, color)
    term.setBackgroundColor(color)
    term.setCursorPos(x,y)
    term.write(string.rep(" ", length))
end

function bars()
	draw_line_term(1, 1, 51, colors.lime)
	draw_line_term(1, 19, 51, colors.lime)
	draw_text_term(12, 1, 'CraftControl Module Installer', colors.gray, colors.lime)
	draw_text_term(13, 19, 'craftcontrol.skynetcloud.ca', colors.gray, colors.lime)
end

-- saves current token variable to local text file
function save_config()
    sw = fs.open("config.txt", "w")   
    sw.writeLine(token)
	sw.writeLine(module_name)
	sw.writeLine(username)
	sw.writeLine(type)
    sw.close()
end

function load_config()
    sr = fs.open("config.txt", "r")
    token = sr.readLine()
	module_name = sr.readLine()
	username = sr.readLine()
	type = sr.readLine()
    sr.close()
end

function launch_module()
    shell.run("CN_module")
end

function install_module()
	term.clear()
	bars()
	draw_text_term(1, 3, 'successfully linked', colors.lime, colors.black)
	sleep(0.5)
	draw_text_term(1, 4, 'installing...', colors.white, colors.black)
	sleep(0.5)
	
	draw_text_term(1, 5, 'removing old versions', colors.white, colors.black)
	if fs.exists("CN_module") then
	    fs.delete("CN_module")
	end
	sleep(0.5)
	
	draw_text_term(1, 6, 'downloading module', colors.white, colors.black)
	term.setCursorPos(1,7)
	term.setTextColor(colors.white)
    download(module_files[type], "CN_module")
	draw_text_term(1, 7, 'saved as CN_module', colors.white, colors.black)
    
    sleep(0.5)
  
    draw_text_term(1, 9, 'create startup file', colors.white, colors.black)
	term.setCursorPos(1,10)
	term.setTextColor(colors.white)
    if fs.exists("startup") then
        fs.delete("startup")
    end
    download("startup.lua", "startup")
	draw_text_term(1, 10, 'saved as startup', colors.white, colors.black)
    sleep(1)
  
    draw_text_term(1, 13, 'Setup Complete', colors.lime, colors.black)

    draw_text_term(1, 14, 'press enter to continue', colors.lightGray, colors.black)

    if updating then

    else
        input = read()
    end

    launch_module()
end

local function urlencode(str)
	return (string.gsub(str, "([^%w%-%._~])", function(c) return string.format("%%%02X", string.byte(c)) end))
end

-- Device-pairing login: the computer shows a short code, the player enters it on the website
-- while logged in. No username or password is ever typed (or sent) in-game.
function login()
	term.clear()
	bars()

	local response = http.post(
		"https://craftcontrol.skynetcloud.ca/code/pair_start.php",
		"id="..os.getComputerID().."&name="..urlencode(module_name).."&module_type="..type)
	local body = response and response.readAll() or ''
	local status, user_code, device_code = string.match(body, "^(%a+)\n(%w+)\n(%x+)$")

	if status ~= 'ok' then
		draw_text_term(1, 3, 'Could not reach craftcontrol.skynetcloud.ca', colors.red, colors.black)
		sleep(3)
		return login()
	end

	draw_text_term(1, 3, 'Link this module to your account:', colors.lime, colors.black)
	draw_text_term(1, 5, '1. Log in at craftcontrol.skynetcloud.ca', colors.white, colors.black)
	draw_text_term(1, 6, '2. Open "Link a module"', colors.white, colors.black)
	draw_text_term(1, 7, '3. Enter this code:', colors.white, colors.black)
	draw_text_term(4, 9, string.sub(user_code, 1, 4).."-"..string.sub(user_code, 5), colors.yellow, colors.black)
	draw_text_term(1, 12, 'Waiting for you... (code expires in 10 min)', colors.lightGray, colors.black)

	while true do
		sleep(3)
		local poll = http.post("https://craftcontrol.skynetcloud.ca/code/pair_poll.php", "device_code="..device_code)
		local reply = poll and poll.readAll() or ''
		local ok, new_token, owner = string.match(reply, "^(ok)\n(%x+)\n([%w_%-]+)$")
		if ok then
			token = new_token
			username = owner
			save_config()
			return install_module()
		elseif reply == 'expired' or reply == 'error' then
			draw_text_term(1, 14, 'Code expired. Restarting...', colors.red, colors.black)
			sleep(2)
			return login()
		end
	end
end
function name()
	term.clear()
	bars()
	
	draw_text_term(1, 3, 'Give this module a unique name:', colors.lime, colors.black)
	term.setCursorPos(2,4)
	term.setTextColor(colors.white)
	module_name = read()
	login()
end

function player_tracker()
	
	-- code to check that openperipheral sensor is present. give relavent error
	
	type = '1'
	name()
end

function choose_module(input) 
	if input == '1' then
		player_tracker()
	elseif input == '2' then
		type = '2'
		name()
	elseif input == '3' then
		type = '3'
		name()
	elseif input == '4' then
		type = '4'
		name()
	elseif input == '5' then
		type = '5'
		name()
	elseif input == '6' then
		type = '6'
		name()
	end
end

function install_select()
	term.clear()
	bars()
	draw_text_term(15, 3, 'Welcome to CraftControl!', colors.lime, colors.black)
	draw_text_term(1, 5, 'What module would you like to install?', colors.white, colors.black)
	
	draw_text_term(2, 7, '1. Player Tracking', colors.white, colors.black)
	draw_text_term(2, 8, '2. Energy Monitor', colors.white, colors.black)
	draw_text_term(2, 9, '3. Fluid Monitor', colors.white, colors.black)
	draw_text_term(2, 10, '4. Redstone Controls', colors.white, colors.black)
	draw_text_term(2, 11, '5. Rednet Gateway', colors.white, colors.black)
	draw_text_term(2, 12, '6. Reactor Control', colors.white, colors.black)
	draw_text_term(1, 14, 'Enter number:', colors.white, colors.black)
	term.setCursorPos(1,15)
	term.setTextColor(colors.white)
	input = read()
	
	choose_module(input)
end

function start()
    term.clear()
    if fs.exists("config.txt") then
        load_config()
        updating = true
        install_module()
    else
        install_select()
    end
end

start()