
local socket = require "socket"
local sha2 = require "sha2"

local forms = {
    list = "LIST\n",
    get = "GET %s\n",
    up = "UPLOAD %d %s\n",
    delete = "DELETE %s\n"
}

local function server_err(err)
    return ({
        closed = "Connection was closed",
        timeout = "Timeout; server was quiet for too long",
        ["broken pipe"] = "Connection was closed",
    })[err] or err
end

local client
local methods = {}

function methods.init(host,port)
    assert(not client,"Client already exists")
    port = tonumber(port)

    client = socket.tcp()

    client:settimeout(5)

    local success, err = client:connect(host,port)
    return success, err and ("Couldn't connect to server %s:%d\n%s"):format(host,port,err)
end

function methods.close()
    if client then
        client:close()
        client = nil
    end
end

function methods.created()
    return client and true -- true or nil
end

function methods.is_alive()
    if not client then return end
    local status, err = client:send("")
    return err ~= "closed",err
end

local list_meta = {
    __newindex = function()end,
    __index = {
        find = function(self,str)
            return self.hashes[str] or self.names[str]
        end,
        findAny = function(self,str)
            return self.hashes[str] or (self.names[str] or {})[1]
        end,
        items = function(self)
            local i = 0
            local n = self.count+0
            if n<1 then return function()end end
            return function()
                i = i + 1
                if i <= n then 
                    return i,self[i].hash,self[i].name 
                end
            end
        end
    }
}
local cached_list
function methods.list_files()
    assert(client,"Client not initiated!")

    client:send(forms.list) -- LIST
    local received,err = client:receive("*l")
    if not received then return nil,server_err(err) end
    
    -- there is only one respose we really care abt
    local count = tonumber(received:match("^200 OK (%d+)$") or "")
    if not count then return nil,"Unexpected response: "..received end

    local files = {names={},hashes={}}

    local skipped = 0

    for i = 1, count do
        local hash,name = client:receive("*l"):match("^([^%s]+).(.+)$")
        if hash and name then
            table.insert(files,{hash=hash,name=name})

            files.names[name] = files.names[name] or {}
            table.insert(files.names[name],hash)

            files.hashes[hash] = name
        else
            skipped = skipped+1
        end
    end

    files.count = count-skipped

    setmetatable(files,list_meta)

    cached_list = files

    return files
end

local callback_intervals = 100
local default_chunk_size = 4096

function methods.download_file(hash,new_name,dir,callback)
    assert(client,"Client not initiated!")
    assert(#tostring(hash)==64,"Invalid hash")
    assert(type(callback)=="function" or not callback,"Expected function or nil in the third argument, got "..type(callback))

    local callback = callback or function()end


    -- GET (hash)
    client:send(forms.get:format(hash))

    local received,err = client:receive("*l")
    if not received then return nil,server_err(err) end
    
    local status = received:match("^%d+")
    if status == "404" then return nil,"File not found (hash): "..hash end
    if status ~= "200" then return nil,"Unexpected response: "..received end

    -- getting file length and file name ("description")
    local length,name = received:match("^%d+ [^%s]+ (%d+) (.+)$")
    length = tonumber(length)

    -- setting destination
    dir = dir or "."
    local destination = ("%s/%s"):format(dir,new_name or "down_"..name:gsub("[^%w%.%-]", "_"))

    local file,err = io.open(destination,"wb")

    if err then
        -- a bit ugly
        -- but i did it to not add more if's than necessary
        file = {write=function()end,close=function()end}
        -- the received data needs to be dumped anyway
    end

    -- the main part
    -- i did it like this to not have too much data in memory at once
    local chunk_size = default_chunk_size
    local loop = math.floor(length/chunk_size)
    local last = length%chunk_size

    callback(0)
    
    for i = 1, loop do
        file:write((client:receive(chunk_size)) or "")
        if i%callback_intervals == 0 then callback(i/loop) end
    end

    if last > 0 then
        file:write((client:receive(last)) or "")
    end
    
    callback(1)

    file:close()

    return destination, err
end



function methods.upload_string(str,name)
    assert(client,"Client not initiated!")
    assert(name,"Expected string, got nil")

    local status, err = client:send(forms.up:format(#str,tostring(name))..str)
    if not status then return nil,server_err(err) end
    
    local response, err = client:receive("*l")

    if response then
        local status,message,hash = response:match("(%d+) ([%w_]+) ([%da-f]+)")
        if status~="200" and status~="409" then
            return nil,"Unexpected response:" ..response
        end
        return {msg=message,hash=hash}
    end
    
    return nil,err
end

function methods.upload_file(path,name,callback)
    assert(client,"Client not initiated!")
    assert(type(path)=="string","Expected string in the first argument, got "..type(path))
    assert(type(callback)=="function" or not callback,"Expected function or nil in the third argument, got "..type(callback))

    local callback = callback or function()end

    local file,err = io.open(path,"rb")
    if not file then return nil,"Failed openning "..err end
    name = name or path:match("[^/\\]+$")


    local length = file:seek("end")
    file:seek("set")

    local status,err = client:send(forms.up:format(length,tostring(name)))
    if not status then 
        file:close()
        return nil,err
    end

    local chunk_size = default_chunk_size
    local loop = math.ceil(length/chunk_size)

    callback(0)

    for i = 1, loop do
        status,err = client:send((file:read(chunk_size)) or "")
        if not status then 
            break
        end
        if i%callback_intervals == 0 then callback(i/loop) end
    end

    callback(1)

    file:close()

    if not status then return nil,server_err(err) end

    local response, err = client:receive("*l")

    if response then
        local status,message,hash = response:match("(%d+) ([%w_]+) ([%da-f]+)")
        if status~="200" and status~="409" then
            return nil,"Unexpected response: "..response
        end

        if cached_list then
            cached_list.hashes[hash] = name
            cached_list.names[name] = cached_list.names[name] or {}
            table.insert(cached_list.names[name],hash)
            table.insert(cached_list,{name=name,hash=hash})
        end

        return {msg=message,hash=hash}
    end

    return nil,err
end

function methods.delete_hash(hash)
    assert(client,"Client not initiated!")
    assert(#tostring(hash)==64,"Invalid hash")

    local status,err = client:send(forms.delete:format(hash))

    if status then 
        local response, err = client:receive("*l")
        if not response then return nil,server_err(err) end

        if response == "200 OK" then 
            if cached_list then                
                for i = #cached_list, 1, -1 do
                    if cached_list[i].hash == hash then
                        table.remove(cached_list,i)
                        break
                    end
                end
                for k, v in pairs(cached_list.names) do
                    for i = #v, 1, -1 do
                        if v[i] == hash then
                            table.remove(v,i)
                            break
                        end
                    end
                end
                cached_list.hashes[hash] = nil
            end

            return true 
        end

        local message = response:match("^%d+ (.+)$")
        if not message then return nil,"Unexpected response: "..response end

        return nil,"Server responded: "..message
    end

    return nil,err
end

function methods.upload_pipe(name)
    assert(client,"Client not initiated!")
    assert(name,"Expected string, got nil")
    
    local tmp_name = os.tmpname()
    local tmp_file,err = io.open(tmp_name,"wb")
    if not tmp_file then return nil,"Couln't open temporary file "..err end
    
    local chunk_size = default_chunk_size
    while true do
        local chunk = io.read(chunk_size)
        if not chunk then break end
        tmp_file:write(chunk)
    end

    tmp_file:close()
    local status,err = methods.upload_file(tmp_name,name)
    os.remove(tmp_name)

    return status,err
end

function methods.calc_hash(filename)
    local file,err = io.open(filename,"rb")
    if not file then return nil,"Couldn't open file "..err end
    
    local append = sha2.sha256()
    while true do
        local chunk = file:read(default_chunk_size)
        if not chunk then break end
        append(chunk)
    end

    file:close()

    return append()
end

function methods.hash_exists(hash)
    if not cached_list then
        local status,err = methods.list_files()
        if not status then return nil,err end
    end
    return cached_list:find(hash)
end

function methods.find_hash(name)
    if not cached_list then
        local status,err = methods.list_files()
        if not status then return nil,err end
    end
    local meta_no_errors_pls_thx = getmetatable(methods.list_files())
    return cached_list:find(name)
end

function methods.list_or_cache()
    if cached_list then
        return cached_list
    end
    return methods.list_files()
end

return methods
