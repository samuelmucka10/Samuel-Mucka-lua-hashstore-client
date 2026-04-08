local script_path = arg[0]:match("^(.-)[^/\\]+$")
local client = dofile(script_path.."../client_hashstore.lua")

local files = {
    music = "big file.m4a",
    gif = "funni.gif",

    prefix = script_path.."../test_files/"
}
local local_hashes = {}

local list = {}
local function list_files()
    print("")
    list = assert(client.list_files())
    for i, hash, name in list:items() do
        print(i,hash,name)
    end
    print("")
end

local function progress(p)
    io.write(("\r %3.2f%% "):format(p*100))
    if p == 1 then
        io.write("Done! \n")
        return
    end
    io.flush()
end

local function upload_test_file(name)
    local hash = assert(client.upload_file(files.prefix..files[name],nil,progress)).hash
    print("received hash: "..hash)
    print(local_hashes[name] == hash and "Hashes match!" or "Hashes don't match!")
end

local function download_hash(hash)
    assert(client.download_file(hash,nil,nil,progress))
end

print("Calculating hashes for testing files")
for k, v in pairs(files) do
    if k ~= "prefix" then
        local hash = client.calc_hash(files.prefix..v)
        print(files.prefix..v.."\n",hash)
        local_hashes[k] = hash
        print()
    end 
end

print("Connecting...")
assert(client.init("0.0.0.0","9000"))
list_files()

print("Uploading smaller file...")
upload_test_file("gif")
print("Uploading larger file...")
upload_test_file("music")
list_files()

print("Downloading the two files and one random...")
math.randomseed(os.time())
local random_item = list[math.random(1,#list-2)]
print("Randomly picked file: "..random_item.name,"\n",random_item.hash)
download_hash(random_item.hash)
download_hash(local_hashes.gif)
download_hash(local_hashes.music)

print("Deleting new files...")
client.delete_hash(local_hashes.gif)
client.delete_hash(local_hashes.music)
list_files()
print(list.hashes[local_hashes.gif] and "Didn't delete the smaller file" or "Deleted the smaller file!")
print(list.hashes[local_hashes.music] and "Didn't delete the larger file" or "Deleted the larger file!")

client.close("0.0.0.0","9000")

print("Test is done!")