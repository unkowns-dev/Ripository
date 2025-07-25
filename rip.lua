local rip = {}

local json = loadstring(game:HttpGet("https://unkown.eu/packages/json.lua", true))()
local errorlib = loadstring(game:HttpGet("https://unkown.eu/packages/error.lua", true))()

local JSON_ERRORS = {
    ["name"] = errorlib.new("Invalid Rip.json data", "Name Missing", 1002),
    ["description"] = errorlib.new("Invalid Rip.json data", "Description Missing", 1003),
    ["entry"] = errorlib.new("Invalid Rip.json data", "Entry Missing", 1004)
}

local function ConvertYouarel(youarel)
    if youarel:sub(-1) == "/" then
        youarel = youarel:sub(1, -2)
    end
    local username, reponame = youarel:match("https://github.com/([^/]+)/([^/]+)")
    if not username or not reponame then
        error("Invalid GitHub URL format")
    end
    local rawBaseUrl = string.format("https://raw.githubusercontent.com/%s/%s/refs/heads/main/", username, reponame)
    return rawBaseUrl
end

local function checkJsonUwU(jsonTable, fieldName)
    if not jsonTable[fieldName] then
        local err = JSON_ERRORS[fieldName]
        if err then
            return errorlib.format(err)
        end
    end
end

local function gitgud(treeUrl)
    local function httpGet(url)
        return game:HttpGet(url)
    end

    local owner, repo, branch = treeUrl:match("github.com/([^/]+)/([^/]+)/tree/(.+)")
    assert(owner and repo and branch, "Invalid GitHub tree URL")

    local apiUrl = string.format("https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1", owner, repo, branch)
    local response = httpGet(apiUrl)
    local data = json.decode(response)

    local fileMap = {}
    for _, item in ipairs(data.tree) do
        if item.type == "blob" then
            local rawUrl = string.format("https://raw.githubusercontent.com/%s/%s/%s/%s", owner, repo, branch, item.path)
            fileMap[item.path] = { rawUrl }
        end
    end

    return fileMap
end


function rip.install(url)
    local RAW = ConvertYouarel(url)
    local RIPdotJson = game:HttpGet(RAW.."rip.json")
    local RIPdotJsonDecoded = json.decode(RIPdotJson)

    for key, _ in pairs(JSON_ERRORS) do
        local errinfo = checkJsonUwU(RIPdotJsonDecoded, key)
        if errinfo then
            error(errinfo)
        end
    end

    local name = RIPdotJsonDecoded.name or "unknown-package"
    print("Collecting " .. name)
    task.wait(0.05)

    print("  Downloading " .. name .. " (rip)")
    task.wait(0.05)

    if RIPdotJsonDecoded.dependencies then
        for _, dep in ipairs(RIPdotJsonDecoded.dependencies) do
            print("  Collecting " .. dep)
            task.wait(0.05)
            print("    Downloading " .. dep .. " (rip)")
            task.wait(0.05)
        end
    end

    local folder = "/rip/Packages/" .. name .. "/"

    if RIPdotJsonDecoded.name and not isfolder(folder) then 
        makefolder(folder)
        makefolder(folder .. "src")
    end

    writefile(folder .. "rip.json", RIPdotJson)

    print("Installing collected files:")
    local files = gitgud(url)
    for fname, raw in pairs(files) do
        local filePath = folder .. tostring(fname)
        writefile(filePath, game:HttpGet(raw[1]))
        print("  - " .. fname)
        task.wait(0.05)
    end

    print("Successfully installed " .. name)
end

local function readFile(path)
    if not isfile(path) then
        error("File not found: "..path)
    end
    return readfile(path)
end

getgenv()._rip_loaded = getgenv()._rip_loaded or {}

local function pathJoin(base, relative)
    if relative:sub(1,1) == "/" then
        relative = relative:sub(2)
    end
    if base:sub(-1) ~= "/" then
        base = base .. "/"
    end
    return base .. relative
end



local function loadModule(pkgName, filePath)
    local cache = getgenv()._rip_loaded
    cache[pkgName] = cache[pkgName] or {}

    if cache[pkgName][filePath] then
        return cache[pkgName][filePath]
    end

    local root = "/rip/Packages/" .. pkgName .. "/"
    local fullPath = pathJoin(root, filePath)

    if not isfile(fullPath) then
        error("Module file not found: "..fullPath)
    end

    local code = readFile(fullPath)

    local function packageLoadstring(fileName)
        local function loadAllModulesInCurrentDir()
            local dir = filePath:match("(.*/)")
            dir = dir or ""

            local modules = {}
            local basePath = "/rip/Packages/" .. pkgName .. "/" .. dir

            local files = listfiles(basePath)

            for _, f in ipairs(files) do
                local relativePath = f:sub(#basePath + 1)  

                if f:match("%.lua$") and not f:lower():match("init.lua") then
                    local modName = relativePath:match("([^/]+)%.lua$")
                    modules[modName] = loadModule(pkgName, dir .. relativePath)
                end
            end
            return modules
        end

        local newPath
        if fileName == "*" then
            return function()
                return loadAllModulesInCurrentDir()
            end
        elseif fileName:sub(1,1) == "/" then
            newPath = fileName:sub(2)
        else
            local dir = filePath:match("(.*/)")
            dir = dir or ""
            newPath = dir .. fileName
        end

        return function()
            return loadModule(pkgName, newPath)
        end
    end



    local env = setmetatable({
        loadstring = packageLoadstring,
    }, { __index = getgenv() })

    local fn, err = loadstring(code, filePath)
    if not fn then error(err) end
    setfenv(fn, env)

    local result = fn()
    cache[pkgName][filePath] = result or true
    return result
end

function rip.include(pkgName)
    if getgenv()._rip_loaded[pkgName] and getgenv()._rip_loaded[pkgName].__entry_loaded then
        local mod = getgenv()._rip_loaded[pkgName].__entry_loaded
        getgenv()[pkgName] = mod 
        return mod
    end

    local root = "/rip/Packages/" .. pkgName .. "/"
    local ripJsonPath = root .. "rip.json"

    if not isfile(ripJsonPath) then
        error("rip.json missing for package: "..pkgName)
    end

    local ripJsonRaw = readFile(ripJsonPath)
    local ripJson = json.decode(ripJsonRaw)

    if not ripJson or not ripJson.entry then
        error("Entry missing in rip.json for package: "..pkgName)
    end

    local entryModule = loadModule(pkgName, ripJson.entry)

    getgenv()._rip_loaded[pkgName].__entry_loaded = entryModule

    getgenv()[pkgName] = entryModule

    return entryModule
end


function rip.update(pkgName)
    -- too lazy rn
end

function rip.ListPackages()
    local folder = "/rip/Packages/"
    if isfolder(folder) then
        print("INSTALLED RIP PACKAGES[")
        for _, file in listfiles(folder) do
            print(string.gsub(file,folder,""))
        end
        print("]")
    end
end

function rip.uninstall(pkgName)
    local folder = "/rip/Packages/"
    if isfolder(folder .. pkgName) then
        local decoded = json.decode(readFile(folder .. pkgName .. "/rip.json"))
        local version = decoded.version or "unknown"
        print("Found existing installation: " .. pkgName .. " " .. version)
        task.wait(.05)
        print("Uninstalling " .. pkgName .. "-" .. version .. ":")
        task.wait(.05)

        print("  Removing:")
        task.wait(.05)

        for _, v in ipairs(decoded.files) do
            print("    " .. folder .. pkgName.. v)
             task.wait(.05)

        end
        task.wait(.05)

        print("Successfully uninstalled " .. pkgName .. "-" .. version)
        delfolder(folder..pkgName)
    else
        print("Package '" .. pkgName .. "' is not installed.")
    end
end


function rip.show(pkgName)
    local folder = "/rip/Packages/"
    if isfolder(folder..pkgName) then
        local decoded = json.decode(readFile(folder..pkgName.."/rip.json"))
        print("Name: "..decoded.name)
        print("Version: "..decoded.version)
        print("Description: "..decoded.description)

    end
end

getgenv().install = rip.install
getgenv().uninstall = rip.uninstall

getgenv().include = rip.include

getgenv().ListPackages = rip.ListPackages
getgenv().show = rip.show

return rip
