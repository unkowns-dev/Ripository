--[[ 
    Load your OutlineModule here (replace with actual loadstring or require)
    For example, if you have a URL or string, do:
    local OutlineModule = loadstring(game:HttpGet("YOUR_URL_HERE"))()
    
    For demo, I embed your OutlineModule directly below:
--]]

local OutlineModule = (function()
    local RunService = game:GetService("RunService")
    local Players = game:GetService("Players")
    local Camera = workspace.CurrentCamera

    local OutlineModule = {}

    local outlines = {}
    local labels = {}

    local function createScreenGui()
        local screenGui = Players.LocalPlayer:FindFirstChild("PlayerGui"):FindFirstChild("OutlineUI")
        if not screenGui then
            screenGui = Instance.new("ScreenGui")
            screenGui.Name = "OutlineUI"
            screenGui.ResetOnSpawn = false
            screenGui.IgnoreGuiInset = true
            screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
            screenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
        end
        return screenGui
    end

    local function getObjectCorners(obj)
        local cf, size
        if obj:IsA("Model") then
            cf, size = obj:GetBoundingBox()
        elseif obj:IsA("BasePart") then
            cf, size = obj.CFrame, obj.Size
        else
            return {}
        end

        local halfSize = size / 2
        local corners = {}

        for x = -1, 1, 2 do
            for y = -1, 1, 2 do
                for z = -1, 1, 2 do
                    local offset = Vector3.new(x * halfSize.X, y * halfSize.Y, z * halfSize.Z)
                    table.insert(corners, (cf * CFrame.new(offset)).Position)
                end
            end
        end

        return corners
    end

    RunService.RenderStepped:Connect(function()
        for _, item in ipairs(outlines) do
            local obj = item.object
            local frame = item.frame

            if obj and obj.Parent then
                local minX, minY = math.huge, math.huge
                local maxX, maxY = -math.huge, -math.huge
                local onScreen = false

                for _, corner in ipairs(getObjectCorners(obj)) do
                    local screenPoint, visible = Camera:WorldToViewportPoint(corner)
                    if visible then
                        onScreen = true
                        minX = math.min(minX, screenPoint.X)
                        minY = math.min(minY, screenPoint.Y)
                        maxX = math.max(maxX, screenPoint.X)
                        maxY = math.max(maxY, screenPoint.Y)
                    end
                end

                if onScreen then
                    frame.Visible = true
                    frame.Position = UDim2.fromOffset(minX, minY)
                    frame.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
                else
                    frame.Visible = false
                end
            else
                frame.Visible = false
            end
        end

        for _, labelData in ipairs(labels) do
            local obj = labelData.object
            local label = labelData.label
            local offset = labelData.offset

            if obj and obj.Parent then
                local worldPos
                if obj:IsA("Model") then
                    worldPos = select(1, obj:GetBoundingBox()).Position
                elseif obj:IsA("BasePart") then
                    worldPos = obj.Position
                end

                if worldPos then
                    local finalPos = worldPos + offset
                    local screenPos, visible = Camera:WorldToViewportPoint(finalPos)

                    label.Visible = visible
                    if visible then
                        label.Position = UDim2.fromOffset(screenPos.X, screenPos.Y)
                    end
                end
            else
                label.Visible = false
            end
        end
    end)

    function OutlineModule.OutlineObject(obj, uitable)
        local screenGui = createScreenGui()

        local outline = Instance.new("Frame")
        outline.Name = "OutlineFrame"
        outline.BorderSizePixel = 2
        outline.BackgroundTransparency = 1
        outline.AnchorPoint = Vector2.new(0, 0)
        outline.Size = UDim2.new(0, 0, 0, 0)
        outline.Position = UDim2.new(0, 0, 0, 0)
        outline.ZIndex = 1
        outline.Visible = false
        outline.Parent = screenGui

        for _, v in uitable:GetChildren() do
            v.Parent = outline
        end

        table.insert(outlines, {
            object = obj,
            frame = outline
        })

        return function()
            outline:Destroy()
            for i, v in ipairs(outlines) do
                if v.frame == outline then
                    table.remove(outlines, i)
                    break
                end
            end
        end
    end

    function OutlineModule.Clear(obj)
        for i = #outlines, 1, -1 do
            if outlines[i].object == obj then
                outlines[i].frame:Destroy()
                table.remove(outlines, i)
            end
        end

        for i = #labels, 1, -1 do
            if labels[i].object == obj then
                labels[i].label:Destroy()
                table.remove(labels, i)
            end
        end
    end

    function OutlineModule.IsOutlined(obj)
        for _, outlineData in ipairs(outlines) do
            if outlineData.object == obj then
                return true
            end
        end
        for _, labelData in ipairs(labels) do
            if labelData.object == obj then
                return true
            end
        end
        return false
    end

    return OutlineModule
end)()


--[[  
    Now the WorldGui proxy implementation — hooking Instance.new to fake it.
]]

do
    local oldInstanceNew = Instance.new
    local mt = getrawmetatable(game)
    local setreadonly = setreadonly or function() end
    local getnamecallmethod = getnamecallmethod or function() return "" end

    setreadonly(mt, false)

    local worldGuiProxies = {}

    local WorldGuiProxy = {}
    WorldGuiProxy.__index = WorldGuiProxy

    function WorldGuiProxy.new()
        local self = setmetatable({}, WorldGuiProxy)
        self._Parent = nil
        self.uitable = Instance.new("Folder")
        self.uitable.Name = "WorldGui_Container"
        return self
    end

    function WorldGuiProxy:__tostring()
        return "Instance (WorldGui)"
    end

    function WorldGuiProxy:Destroy()
        if self.cleanupFunc then
            self.cleanupFunc()
        end
        self.uitable:Destroy()
        worldGuiProxies[self] = nil
    end

    function WorldGuiProxy:__index(key)
        if key == "Parent" then
            return self._Parent
        elseif key == "Name" then
            return "WorldGui"
        elseif key == "Destroy" then
            return function() self:Destroy() end
        elseif key == "GetChildren" then
            return function()
                return self.uitable:GetChildren()
            end
        elseif key == "IsA" then
            return function(_, className)
                return className == "WorldGui"
            end
        else
            return rawget(WorldGuiProxy, key)
        end
    end

    function WorldGuiProxy:__newindex(key, value)
        if key == "Parent" then
            self._Parent = value
            self.uitable.Parent = value

            if self.cleanupFunc then
                self.cleanupFunc()
                self.cleanupFunc = nil
            end

            if value then
                self.cleanupFunc = OutlineModule.OutlineObject(value, self.uitable)
            end
        else
            rawset(self, key, value)
        end
    end

    local oldNamecall = mt.__namecall
    mt.__namecall = newcclosure(function(self, ...)
        local method = getnamecallmethod()
        local args = {...}
        if (method == "New" or method == "new") and args[1] == "WorldGui" then
            local proxy = WorldGuiProxy.new()
            worldGuiProxies[proxy] = true
            return proxy
        end
        return oldNamecall(self, ...)
    end)

    setreadonly(mt, true)

    local frameMt = getrawmetatable(Instance.new("Frame"))
    setreadonly(frameMt, false)
    local oldFrameNewIndex = frameMt.__newindex
    frameMt.__newindex = newcclosure(function(t, k, v)
        if k == "Parent" and type(v) == "table" and getmetatable(v) == WorldGuiProxy then
            rawset(t, "Parent", v.uitable)
        else
            oldFrameNewIndex(t, k, v)
        end
    end)
    setreadonly(frameMt, true)
end

