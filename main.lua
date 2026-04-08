local config_name = "hashstore_client_config"
local unpack = unpack or table.unpack

local function get_config()
	local file,err = io.open(config_name,"r")
	if not file then return nil,err,true end

	local line = file:read("*l")
	if not line then return nil, "Config file is likely empty" end

	local ip = line:match("localhost") and "127.0.0.1"
	local port = line:match(":[^%d]-(%d+)")

	if not port then return nil, "Did you enter the port?" end

	if not ip then
		local t = {line:match("(%d+)[^%d]+(%d+)[^%d]+(%d+)[^%d]+(%d+)")}
		local invalid = #t~=4
		for _,v in ipairs(t) do
			v = tonumber(v)
			invalid = invalid or v<0 or v>255
		end
		ip = (not invalid) and table.concat(t,".")
	end

	if not ip then return nil,"Invalid/weird IP format" end

	return {
		ip = ip.."",
		port = port..""
	}
end

local function write_config(cfg)
	local file,err = io.open(config_name,"w")
	if not file then return nil,err end
	local status,err = file:write(("%s:%s"):format(cfg.ip,cfg.port))
	file:close()
	return status,err
end

local cfg
do
	local _,no_file;
	cfg,_,no_file = get_config()
	cfg = cfg or {
		ip = "0.0.0.0",
		port = "9000"
	}
	if no_file then
		write_config(cfg)
	end
end


local client = require "client_hashstore"

--[[
{
	--flag = {
		args = number,
		group = 1
	},
	aliases = {
		-f = --flag
	},
	default = --flag
}
]]
local function find_flags(flags,arg)
	if not flags then return end
	local found = {}
	local i = 0
	local did_groups = {}
	while true do
		i = i+1
		local token = arg[i]
		if not token then break end -- loop end

		-- either normal or alias flag
		local name = (flags[token] and token.."") or (flags.aliases or {})[token]
		local flag = flags[name]

		-- if neither, try inserting arguments to the default flag
		if not (flag or did_groups.default) then
			flag = flags[flags.default]
			name = flags.default..""
			did_groups.default = true
			i=i-1
			if did_groups[flag.group or "nil"] then
				return nil,"Too many arguments"
			end
		end
		
		-- if flag doesnt exist or is duplicate, throw error
		if not flag then return nil,"Unexpected argument: "..token end
		if did_groups[flag.group or "nil"] then return nil,"Duplicate group of flags: "..token end

		-- success!
		name = name:gsub("^%-+",""):gsub("%-","_")
		found[name] = {flag_name=name..""}

		
		if flag.group then
			did_groups[flag.group] = true
		end
		
		local is_table = type(flag.args) == "table"
		local l = (is_table and #flag.args) or flag.args

		if not flag.args then
			i=i+1 
			found[name] = arg[i]
			l = 0
		end

		if flag.args == 0 then
			found[name] = true
			l = 0
		end

		for j = 1, l do
			i=i+1
			local v = arg[i]
			if not v then break end
				
			if is_table then 
				found[name][flag.args[j]] = v
			else
				found[name][j] = v
			end
		end

		did_groups["nil"] = false
	end
	return found
end

local function resolve_hash(input)
	local hash = input.hash
	if input.name then
		local hashes = client.find_hash(input.name)
		if not hashes then 
			print("Couldn't find: "..input.name)
			return
		end
		local loop = #hashes>1 and not hashes[tonumber(input.number) or 0]
		local i = 1
		if loop then
			print("Found multiple files: ")
			for i, v in ipairs(hashes) do
				print(i,v)
			end
		end
		while loop do
			if not i then
				print("Wrong input, please try again.")
			end
			io.write("Type number of your file: ")
			local answer = tonumber(io.read())
			i = hashes[answer or 0] and answer
			loop = not i
		end
		hash = hashes[i]
	elseif input.index then
		local i = tonumber(input.index)
		if input.index~="last" and not i then
			print("Expected number")
			return
		end
		local list = client.list_or_cache()
		if not list then 
			print("Something went wrong!\n"..err)
			return
		end
		i = i or #list
		local item = list[i]
		if not item then 
			print("Index out of range")
			return
		end
		hash = item.hash..""
	end
	if #hash~=64 then
		print("Invalid hash")
		return
	end
	return hash
end

local function progress_func(p)
	local l = 20
	local char = "="
	local percent = ("%3.2f%%"):format(p*100)
	local bar = char:rep(math.floor(l*p+.5))
	local progress = (" [%-_s]%8s\r"):gsub("_",l..""):format(bar,percent) -- always fixed size
	io.write(progress)
	io.flush()
end

local command_flags = {
	upload = {
		["--file"] = {
			args = {"path","name"},
			group = 1,
		},
		["--string"] = {
			args = {"str","name"},
			group = 1,
		},
		["--file-auto"] = {
			args = {"path"},
			group = 1,
		},
		["--pipe"] = {
			args = {"name"},
			group = 1,
		},
		["--check"] = {
			args = 0
		},

		aliases = {
			["-f"] = "--file",
			["-s"] = "--string",
			["--short"] = "--string",
			["-F"] = "--file-auto",
			["-fa"] = "--file-auto",
			["-a"] = "--file-auto",
			["-p"] = "--pipe",
			["-c"] = "--check",
		},
		default = "--file"
	},
	delete = {
		["--name"] = {
			group = 1
		},
		["--hash"] = {
			group = 1
		},
		["--index"] = {
			group = 1
		},
		["--number"] = {
			group = 3
		},
		aliases = {
			["-n"] = "--name",
			["-h"] = "--hash",
			["-i"] = "--index",
			["--prefer"] = "--number",
			["-N"] = "--number",
		},
		default = "--hash"
	},
	get = {
		["--name"] = {
			group = 1
		},
		["--hash"] = {
			group = 1
		},
		["--index"] = {
			group = 1
		},
		["--dir"] = {
			group = 2
		},
		["--number"] = {
			group = 3
		},
		["--new-name"] = {
			group = 4
		},
		aliases = {
			["-n"] = "--name",
			["-h"] = "--hash",
			["-i"] = "--index",
			["-D"] = "--dir",
			["-dir"] = "--dir",
			["--directory"] = "--dir",
			["-d"] = "--new-name",
			["--destination"] = "--new-name",
			["--prefer"] = "--number",
			["-N"] = "--number",
		},
		default = "--hash"
	},
	list = {
		["--match"] = {
			args = 1,
			group = 1
		},
		default = "--match",
		aliases = {
			["-m"] = "--match",
			["-r"] = "--match",
			["--search"] = "--match",
			["-s"] = "--match",
		}
	},
	["set-server"] = {
		["--address"] = {
			args = 2,
			group = 1
		},
		default = "--address"
	},
	["get-file-hash"] = {
		["--file"] = {
			group = 1
		},
		default = "--file"
	}
}

local requires_connection = {
	upload = true,
	list = true,
	get = true,
	delete = true,
	repl = true
}

local aliases = {
	help = {"nil","h","-h","--h","-help","--help",""},
	upload = {"up"},
	get = {"download","down"},
	delete = {"del","remove"},
	["say-server"] = {"ip","server"}
}

local exec
local commands = {
	help = function()
		io.write((([[HASHSTORE client CLI
			----------
			help
			repl (for a repl-like interface)
			set-server <ip> <port> (writes into local config)
			get-file-hash <file path>
			
			list [match] (lists files stored on the server; "match" accepts lua patterns/regex)
			delete [--hash/-h] <hash>
			delete <--index/-i> <number>
			delete <--name/-n> <name>
			get [--hash/-h] <hash> [<--destination/-d> <detination file path>] [<--directory/-D> <directory path>] 
			get <--index/-i> <number> [<--destination/-d> <detination file path>] [<--directory/-D> <directory path>] 
			get <--name/-n> <name> [<--number/-N> <number>] [<--destination/-d> <detination file path>] [<--directory/-D> <directory path>] 
				(will find by name. if there are multiple files with the same name,
				 it will either ask which one you prefer or use the number in the argument)
			upload [--check/-c] [--file/-f] <path> <name> (--check will check if the file is already on the server)
			upload [--check/-c] <--file-auto/-F> <path> (will automatically set name/description to the filename)
			upload <--string/--short/-s> <string> <name> (useful for testing and sending short strings)
			upload <--pipe/-p> <name> (useful for piping data into the command)
		]]):gsub("\\]","]"):gsub("\n%s%s%s","\n")))
	end,
	upload = function(input)
		local t = input.file or input.file_auto or input.string or input.pipe

		if not t then
			print("Missing arguments!")
			return
		end
		if not (t.name or input.file_auto) then
			print("Missing a name the file should be uploaded with!")
			return
		end
		if (input.file or input.file_auto) and not t.path then
			print("Missing a file path!")
			return
		end

		print("Starting...")

		local status,err

		if input.file or input.file_auto then
			if input.check then
				local hash,err = client.calc_hash(t.path)
				if not hash then return print(err) end
				if client.hash_exists(hash) then
					print("File with the same hash is already uploaded:\n"..hash)
					return
				end
			end
			status,err = client.upload_file(t.path,t.name,progress_func)
		elseif input.string then
			status,err = client.upload_string(t.string,t.name)
		elseif input.pipe then
			status,err = client.upload_pipe(t.name)
		end

		if status then
			print("\nDone!\nreceived hash: "..status.hash)
		else
			print("Something went wrong!\n"..err)
		end
	end,
	get = function(input)
		local hash = resolve_hash(input)
		if not hash then return end
		local destination,err = client.download_file(hash,input.new_name,input.dir,progress_func)
		if destination then
			print("\nDone!\nSaved as: "..destination)
		else
			print("Something went wrong!\n"..err)
		end
	end,
	list = function(input)
		local list,err = client.list_files()
		if not list then return print(err) end
		for i, a, b in list:items() do
			local line = ("%d %s %s"):format(i,a,b)
			if input.match then
				if line:match(input.match) then
					print(line)
				end
			else
				print(line)
			end
		end
	end,
	delete = function(input)
		local hash = resolve_hash(input)
		if not hash then return end
		local status,err = client.delete_hash(hash)
		if status then
			print("Done!")
		else
			print("Something went wrong!\n"..err)
		end
	end,
	repl = function()
		while true do
			io.write("> ")
			local line = io.read()

			local t = {}
			do
				local hold = ""

				local function add()
					if #hold>0 then
						table.insert(t,hold.."")
						hold = ""
					end
				end

				local string_mode = nil
				local i = 0
				while i<#line do
					i = i+1
					local c = line:sub(i,i)
					if c == " " and not string_mode then
						add()
					elseif c == string_mode then
						string_mode = nil
					elseif c == "\\" then
						i=i+1
						c = line:sub(i,i) or ""
						if string_mode and c~=string_mode then
							hold = hold.."\\"
						end
						hold = hold..c
					elseif c == "\"" or  c == "\'" then
						string_mode = c..""
					else
						hold = hold..c
					end
				end
				add()	
			end
			
			if t[1] == "repl" then
				t[1] = "INVALID"
			elseif t[1] == "disconnect" then
				client.close()
			elseif t[1] == "connect" then
				if client.is_alive() then
					client.close()
				end
				local status,err = client.init(cfg.ip,cfg.port)
				if status then 
					print(("Connected to %s:%s succesfully!"):format(cfg.ip,cfg.port)) 
				else
					print(err)
				end
			elseif t[1] == "exit" then
				client.close()
				os.exit()
			elseif t[1] then
				local name = t[1]..""
				local status,err = pcall(exec,t,true)
				if aliases[name]=="help" then 
					print("\nREPL-specific commands:\nexit, disconnect, connect")
				end
				if not status then print("Error: "..err) end
			end
		end
	end,
	["set-server"] = function(input)
		if #input.address ~= 2 then
			print("Invalid number of commands")
			return 
		end
		if not cfg.ip:match("^%d+%.%d+%.%d+%.%d+$") then
			print("Inavlid address format")
			return
		end
		if not tonumber(cfg.port) then
			print("Inavlid port")
			return
		end

		cfg.ip,cfg.port = unpack(input.address)
		
		if cfg.ip == "localhost" then
			cfg.ip = "127.0.0.1"
		end

		write_config(cfg)
	end,
	["say-server"] = function(input)
		print(("%s:%s"):format(cfg.ip,cfg.port))
	end,
	["get-file-hash"] = function(input)
		local hash,err = client.calc_hash(input.file)
		print(hash or err)
	end
}

do
	local n = {}
	for orig in pairs(commands) do
		for i, alias in ipairs(aliases[orig] or {}) do
			n[alias] = orig..""
		end
		n[orig] = orig..""
	end
	aliases = n
end

exec = function(arg,no_reconnect) -- made it a function to quickly create repl
	local name = aliases[(arg[1] or "nil")..""]
	if not commands[name] then
		print("Command doesn't exist")
		return
	end
	table.remove(arg,1)
	local flags,err = find_flags(command_flags[name],arg)
	if err and not flags then
		print("Invalid command\n"..err)
		return
	end
	if no_reconnect or not requires_connection[name] then
		commands[name](flags)
		return
	end
	local status,err = client.init(cfg.ip,cfg.port)
	if status then
		commands[name](flags)
	else
		print(err)
	end
	client.close()
end

exec(arg)