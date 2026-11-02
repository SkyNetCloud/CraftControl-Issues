-- CraftControl
-- Redstone module
local version = 3

-- installer location
local installer = "https://craftcontrol.skynetcloud.ca/modules/installer.lua"
local time = 0
local token = '0'
-- this scanners name
local module_name = ''
-- owenrs username on website
local username = ''
local type = ''

local top = ''
local bottom = ''
local front = ''
local back = ''
local left = ''
local right = ''

local top_input = 0
local bottom_input = 0
local front_input = 0
local back_input = 0
local left_input = 0
local right_input = 0

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
	draw_text_term(15, 1, 'CraftControl Redstone Module', colors.gray, colors.lime)
	draw_text_term(10, 19, 'craftcontrol.skynetcloud.ca', colors.gray, colors.lime)
end

local status = 'connecting'
local lastSync = nil

-- clears one line, then writes on it, so redrawing never flickers
local function line(y, text, color)
	draw_line_term(1, y, 51, colors.black)
	if text and text ~= '' then draw_text_term(1, y, text, color or colors.white, colors.black) end
end

local function ago(seconds)
	seconds = math.floor(seconds)
	if seconds >= 60 then return math.floor(seconds / 60) .. 'm ' .. (seconds % 60) .. 's' end
	return seconds .. 's'
end

function terminal_screen()
	bars()
	draw_text_term(1, 2, 'Module: ', colors.lime, colors.black)
	draw_text_term(10, 2, module_name, colors.white, colors.black)
	draw_text_term(1, 3, 'Owner: ', colors.lime, colors.black)
	draw_text_term(8, 3, username, colors.white, colors.black)
	draw_text_term(1, 4 , string.rep("-", 51), colors.lime, colors.black)

	-- header
	line(6)
	draw_text_term(2, 6, 'SIDE', colors.lightGray, colors.black)
	draw_text_term(16, 6, 'OUTPUT', colors.lightGray, colors.black)
	draw_text_term(32, 6, 'INPUT', colors.lightGray, colors.black)

	local rows = {
		{'Top', top, top_input},
		{'Bottom', bottom, bottom_input},
		{'Front', front, front_input},
		{'Back', back, back_input},
		{'Left', left, left_input},
		{'Right', right, right_input},
	}
	for i, r in ipairs(rows) do
		local y = 6 + i
		line(y)
		draw_text_term(2, y, r[1], colors.white, colors.black)
		local on = r[2] == 'true'
		draw_text_term(14, y, on and '  ON  ' or ' OFF  ', on and colors.black or colors.lightGray, on and colors.lime or colors.gray)
		local high = r[3] == 1
		draw_text_term(30, y, high and ' HIGH ' or ' low  ', high and colors.black or colors.lightGray, high and colors.yellow or colors.gray)
		term.setBackgroundColor(colors.black)
	end

	if status == 'online' then
		line(15, 'Server: online' .. (lastSync and (', synced ' .. ago(os.clock() - lastSync) .. ' ago') or ''), colors.lime)
	else
		line(15, 'Server: ' .. status .. ' (outputs hold their last state)', colors.red)
	end
end

-- retrieves token from local text file
function load_config()
    sr = fs.open("config.txt", "r")
    token = sr.readLine()
	module_name = sr.readLine()
	username = sr.readLine()
	type = sr.readLine()
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


function string:split(delimiter)
    local result = { }
    local from  = 1
    local delim_from, delim_to = string.find( self, delimiter, from  )
    while delim_from do
        table.insert( result, string.sub( self, from , delim_from-1 ) )
        from  = delim_to + 1
        delim_from, delim_to = string.find( self, delimiter, from  )
    end
    table.insert( result, string.sub( self, from  ) )
    return result
end

function phone_home()
	getInputs()

    local response = http.post("https://craftcontrol.skynetcloud.ca/code/redstone.php",
        "token="..token.."&id="..os.getComputerID().."&top_input="..top_input.."&bottom_input="..bottom_input.."&front_input="..front_input.."&back_input="..back_input.."&left_input="..left_input.."&right_input="..right_input)
	if not response then
		status = 'offline'
		return
	end
	local return_string = response.readAll()
	response.close()
	status = 'online'
	lastSync = os.clock()
	
	result_array = string.split(return_string,",")
	current_version = tonumber(result_array[1])
	
	local function apply(side, idx)
		local on = tonumber(result_array[idx]) == 1
		rs.setOutput(side, on)
		return on and 'true' or 'false'
	end
	top = apply('top', 2)
	bottom = apply('bottom', 3)
	back = apply('back', 4)
	front = apply('front', 5)
	left = apply('left', 6)
	right = apply('right', 7)

	if current_version and current_version > version then
        run_installer()
	end
end

function getInputs()
	top_input = rs.getInput('top') and 1 or 0
	bottom_input = rs.getInput('bottom') and 1 or 0
	front_input = rs.getInput('front') and 1 or 0
	back_input = rs.getInput('back') and 1 or 0
	left_input = rs.getInput('left') and 1 or 0
	right_input = rs.getInput('right') and 1 or 0

end

------  End module specific code ---------


function start_loop()
	term.setBackgroundColor(colors.black)
	term.clear()
	phone_home()
	while true do
		terminal_screen()
		
		-- main active status with server
		sleep(2)
		phone_home()
	end
end

function start()
	term.clear()
	term.setCursorPos(1,1)
	
    if fs.exists("config.txt") then
        load_config()
        start_loop()
    else
        run_installer()
    end
end

start()