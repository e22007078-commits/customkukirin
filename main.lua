--[[
	CUSTOM KUKIRIN v3.1 — by zyru   (Default + Beta)
	Один LocalScript / executor-скрипт. Меню: RightShift или LeftAlt.  F = вилли, G = авто-вилли (beta).
	Самокаты: Kukirin G4 / G2 / G3 Pro / G2 Ultra / G2 Master.
]]
local Players, UIS, RS = game:GetService("Players"), game:GetService("UserInputService"), game:GetService("RunService")
local TweenService, HttpService = game:GetService("TweenService"), game:GetService("HttpService")
local Lighting, Workspace = game:GetService("Lighting"), game:GetService("Workspace")
local GuiService = game:GetService("GuiService")
local player = Players.LocalPlayer
local RGB, HSV = Color3.fromRGB, Color3.fromHSV

if shared.GIGAHUB and type(shared.GIGAHUB.destroy) == "function" then pcall(shared.GIGAHUB.destroy) end
local Hub = {conns = {}, cleanups = {}, updaters = {}, lang = "en", version = "3.0"}
shared.GIGAHUB = Hub
function Hub.onClean(f) table.insert(Hub.cleanups, f) end
function Hub.destroy()
	for _, c in ipairs(Hub.conns) do pcall(function() c:Disconnect() end) end
	for _, f in ipairs(Hub.cleanups) do pcall(f) end
	Hub.conns, Hub.cleanups, Hub.updaters = {}, {}, {}
	shared.GIGAHUB = nil
end

local CFG = {
	SCOOTERS   = {"Kukirin G4", "Kukirin G2", "Kukirin G3 Pro", "Kukirin G2 Ultra", "KuKirin G2 Master"},
	BETA_USERS = {"prixyel185", "merstach"},  -- ники с доступом к BETA (добавляй через запятую)
	BETA_USER_IDS = {},                   -- или UserId
	MENU_KEYS  = {Enum.KeyCode.RightShift, Enum.KeyCode.LeftAlt},
	WHEELIE_KEY = Enum.KeyCode.F, AUTO_WHEELIE_KEY = Enum.KeyCode.G,
	FORWARD_LOCAL = Vector3.new(0, 0, -1), UP_LOCAL = Vector3.new(0, 1, 0),
	FOLDER = "CustomKukirin",
	HELMET_ID = 115694279406990, GOGGLES_ID = 126144287183782,
}
Hub.CFG = CFG

---------------------------------------------------------------- utils
local U = {}
Hub.U = U
function U.new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end
function U.corner(i, r) return U.new("UICorner", {CornerRadius = UDim.new(0, r or 8)}, i) end
function U.tween(i, t, props, style, dir)
	local tw = TweenService:Create(i, TweenInfo.new(t, style or Enum.EasingStyle.Quart, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end
function U.connect(sig, fn)
	local c = sig:Connect(fn)
	table.insert(Hub.conns, c)
	return c
end
function U.norm(s) return (tostring(s):lower():gsub("[^%w]", "")) end
function U.hex(c) return string.format("#%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)) end
function U.fromHex(s)
	local r, g, b = tostring(s):match("^#?(%x%x)(%x%x)(%x%x)$")
	if r then return RGB(tonumber(r, 16), tonumber(g, 16), tonumber(b, 16)) end
end
function U.c2t(c) return {math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)} end
function U.t2c(t) return RGB(t[1], t[2], t[3]) end
function U.isFx(o) return o.Name:sub(1, 5) == "GIGA_" or o:FindFirstAncestor("GIGA_FX") ~= nil end
function U.chainName(p, model)
	local t, n = {}, p
	while n and n ~= model do table.insert(t, n.Name:lower()) n = n.Parent end
	return table.concat(t, "/")
end
function U.centroid(list)
	local c = Vector3.zero
	for _, p in ipairs(list) do c = c + p.Position end
	return #list > 0 and c / #list or c
end
function U.guiParent()
	local ok, h = pcall(function() return gethui() end)
	if ok and h then return h end
	local ok2, cg = pcall(function()
		local t = Instance.new("ScreenGui"); t.Parent = game:GetService("CoreGui"); t:Destroy()
		return game:GetService("CoreGui")
	end)
	if ok2 and cg then return cg end
	return player:WaitForChild("PlayerGui")
end
function Hub.addUpdater(fn) table.insert(Hub.updaters, fn) end
local warned = {}
U.connect(RS.RenderStepped, function(dt)
	for i, fn in ipairs(Hub.updaters) do
		local ok, err = pcall(fn, dt)
		if not ok and not warned[i] then warned[i] = true warn("[GIGAHUB] updater error: " .. tostring(err)) end
	end
end)

---------------------------------------------------------------- storage + images
local Store = {mem = {}}
Hub.Store = Store
Store.fs = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
local function ensureFolder()
	pcall(function() if makefolder and not (isfolder and isfolder(CFG.FOLDER)) then makefolder(CFG.FOLDER) end end)
end
function Store.save(name, data)
	local ok, json = pcall(function() return HttpService:JSONEncode(data) end)
	if not ok then return end
	Store.mem[name] = json
	if Store.fs then ensureFolder() pcall(writefile, CFG.FOLDER .. "/" .. name .. ".json", json) end
end
function Store.load(name, default)
	local json = Store.mem[name]
	if not json and Store.fs then
		pcall(function() local p = CFG.FOLDER .. "/" .. name .. ".json" if isfile(p) then json = readfile(p) end end)
	end
	if json then
		local ok, d = pcall(function() return HttpService:JSONDecode(json) end)
		if ok and d ~= nil then return d end
	end
	return default
end

local Img = {cache = {}}
Hub.Img = Img
local function hashStr(s) local h = 5381 for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end return tostring(h) end
function Img.canDownload() return Store.fs and (type(getcustomasset) == "function" or type(getsynasset) == "function") end
-- возвращает asset-строку или nil, ошибку.  Только PNG / JPG.  Вызывать из task.spawn (yield)
function Img.get(url)
	url = tostring(url or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if url == "" then return nil, "empty" end
	if url:match("^%d+$") then return "rbxassetid://" .. url end
	if url:match("^rbxassetid://") or url:match("^rbxasset://") then return url end
	if Img.cache[url] then return Img.cache[url] end
	if not Img.canDownload() then return nil, "URL images need an executor with writefile + getcustomasset" end
	local data
	pcall(function() data = game:HttpGet(url) end)
	if not data then
		pcall(function()
			local req = request or http_request or (syn and syn.request)
			local res = req({Url = url, Method = "GET"})
			data = res and res.Body
		end)
	end
	if not data or #data < 16 then return nil, "download failed" end
	local kind
	if data:sub(1, 4) == "\137PNG" then kind = "png" elseif data:sub(1, 3) == "\255\216\255" then kind = "jpg" end
	if not kind then return nil, "only PNG / JPG are supported" end
	ensureFolder()
	local path = CFG.FOLDER .. "/img_" .. hashStr(url) .. "." .. kind
	local ok = pcall(writefile, path, data)
	if not ok then return nil, "writefile failed" end
	local ok2, asset = pcall(function() return (getcustomasset or getsynasset)(path) end)
	if not ok2 or not asset then return nil, "getcustomasset failed" end
	Img.cache[url] = asset
	return asset
end

---------------------------------------------------------------- scooter registry / rig
local CATS = {
	{k = "wheelie",    en = "Wheelie Bar",  ru = "Вилли-бар",    kw = {"wheelie", "bugel"}},
	{k = "grips",      en = "Grips",        ru = "Грипсы",       kw = {"grip"}},
	{k = "brakes",     en = "Brakes",       ru = "Тормоза",      kw = {"brake", "disc", "caliper", "rotor"}},
	{k = "lights",     en = "Lights",       ru = "Фары",         kw = {"light", "lamp"}},
	{k = "battery",    en = "Battery",      ru = "Аккумулятор",  kw = {"battery", "batt"}},
	{k = "motor",      en = "Motor",        ru = "Мотор",        kw = {"motor", "engine", "hub"}},
	{k = "wheels",     en = "Wheels",       ru = "Колёса",       kw = {"wheel", "tire", "tyre", "rim"}},
	{k = "suspension", en = "Suspension",   ru = "Подвеска",     kw = {"suspension", "fork", "shock", "spring"}},
	{k = "stem",       en = "Stem",         ru = "Стойка",       kw = {"stem", "column", "steer", "neck"}},
	{k = "handlebar",  en = "Handlebar",    ru = "Руль",         kw = {"handlebar", "handle", "bars"}},
	{k = "frame",      en = "Frame / Deck", ru = "Рама / дека",  kw = {"frame", "deck", "body", "chassis"}},
	{k = "other",      en = "Other",        ru = "Прочее",       kw = {}},
}
Hub.CATS = CATS
local CATIDX = {}
for i, c in ipairs(CATS) do CATIDX[c.k] = i end

local Reg = {rigs = setmetatable({}, {__mode = "k"}), names = {}, current = nil, override = nil, listeners = {}}
Hub.Reg = Reg
for _, n in ipairs(CFG.SCOOTERS) do Reg.names[U.norm(n)] = true end
local function isScooter(o) return (o:IsA("Model") or o:IsA("BasePart")) and Reg.names[U.norm(o.Name)] == true end

local function classify(part, model)
	local node = part
	while node and node ~= model do
		local ln = node.Name:lower()
		for _, c in ipairs(CATS) do
			for _, kw in ipairs(c.kw) do if ln:find(kw, 1, true) then return c.k end end
		end
		node = node.Parent
	end
	return "other"
end

local function wheelInfo(list)
	local big, bm = nil, 0
	for _, p in ipairs(list) do
		local m = math.max(p.Size.X, p.Size.Y, p.Size.Z)
		if m > bm then big, bm = p, m end
	end
	if not big then return nil end
	return {center = big.Position, r = bm / 2, w = math.min(big.Size.X, big.Size.Y, big.Size.Z), part = big}
end
Reg.wheelInfo = wheelInfo

local function splitWheels(wheels, ref, root)
	if #wheels == 0 then return {}, {} end
	local a, endA, d1 = wheels[1], wheels[1], -1
	for _, p in ipairs(wheels) do local d = (p.Position - a.Position).Magnitude if d > d1 then endA, d1 = p, d end end
	local endB, d2 = endA, -1
	for _, p in ipairs(wheels) do local d = (p.Position - endA.Position).Magnitude if d > d2 then endB, d2 = p, d end end
	if d2 < 0.8 then return wheels, {} end
	local A, B = {}, {}
	for _, p in ipairs(wheels) do
		if (p.Position - endA.Position).Magnitude <= (p.Position - endB.Position).Magnitude then table.insert(A, p) else table.insert(B, p) end
	end
	local cA, cB = U.centroid(A), U.centroid(B)
	local aFront
	if ref then aFront = (cA - ref).Magnitude < (cB - ref).Magnitude
	else local f = root.CFrame:VectorToWorldSpace(CFG.FORWARD_LOCAL) aFront = cA:Dot(f) > cB:Dot(f) end
	if aFront then return A, B end
	return B, A
end

function Reg.rig(model)
	if not model or not model.Parent then return nil end
	local r = Reg.rigs[model]
	if r and not r.dirty then return r end
	r = r or {model = model, orig = setmetatable({}, {__mode = "k"})}
	r.dirty = false
	r.parts, r.byCat, r.cat, r.u, r.slots, r.slotMap, r.accent = {}, {}, {}, {}, {}, {}, {}
	r.hidden = r.hidden or {}
	for _, c in ipairs(CATS) do r.byCat[c.k] = {} end
	local list = model:GetDescendants()
	if model:IsA("BasePart") then table.insert(list, model) end
	local biggest, bv = nil, 0
	for _, o in ipairs(list) do
		if o:IsA("BasePart") and not U.isFx(o) then
			table.insert(r.parts, o)
			local k = classify(o, model)
			r.cat[o] = k
			table.insert(r.byCat[k], o)
			if not r.orig[o] then
				local e = {Color = o.Color, Material = o.Material, Transparency = o.Transparency}
				if o:IsA("UnionOperation") then e.UsePartColor = o.UsePartColor end
				r.orig[o] = e
			end
			local _, sat, val = r.orig[o].Color:ToHSV()
			if sat > 0.45 and val > 0.35 and k ~= "wheels" then r.accent[o] = true end -- «краска» = цветные акценты
			local v = o.Size.X * o.Size.Y * o.Size.Z
			if v > bv and k ~= "wheelie" then biggest, bv = o, v end
			if o.Transparency < 0.98 and o.Size.Magnitude > 0.06 then
				local s = r.slotMap[o.Name]
				if not s then s = {name = o.Name, parts = {}, cat = k} r.slotMap[o.Name] = s table.insert(r.slots, s) end
				table.insert(s.parts, o)
			end
		end
	end
	table.sort(r.slots, function(a, b)
		if CATIDX[a.cat] ~= CATIDX[b.cat] then return CATIDX[a.cat] < CATIDX[b.cat] end
		return a.name < b.name
	end)
	r.root = (model:IsA("Model") and model.PrimaryPart) or biggest
	-- перед / зад
	local wheels = {}
	for _, p in ipairs(r.byCat.wheels) do table.insert(wheels, p) end
	local f, b = {}, {}
	for _, p in ipairs(wheels) do
		local cn = U.chainName(p, model)
		if cn:find("front", 1, true) then table.insert(f, p) elseif cn:find("back", 1, true) or cn:find("rear", 1, true) then table.insert(b, p) end
	end
	if r.root and (#f == 0 or #b == 0) then
		local hb = {}
		for _, k in ipairs({"handlebar", "grips", "stem"}) do for _, p in ipairs(r.byCat[k]) do table.insert(hb, p) end end
		f, b = splitWheels(wheels, #hb > 0 and U.centroid(hb) or nil, r.root)
	end
	r.front, r.rear = f, b
	r.fwdLocal = CFG.FORWARD_LOCAL
	if r.root and #f > 0 and #b > 0 then
		local up = r.root.CFrame:VectorToWorldSpace(CFG.UP_LOCAL)
		local d = U.centroid(f) - U.centroid(b)
		d = d - up * d:Dot(up)
		if d.Magnitude > 0.5 then r.fwdLocal = r.root.CFrame:VectorToObjectSpace(d.Unit) end
	end
	-- проекция вдоль самоката 0..1 (для радужного градиента)
	if r.root then
		local mn, mx = math.huge, -math.huge
		local tmp = {}
		for _, p in ipairs(r.parts) do
			local v = r.root.CFrame:PointToObjectSpace(p.Position):Dot(r.fwdLocal)
			tmp[p] = v
			mn, mx = math.min(mn, v), math.max(mx, v)
		end
		for p, v in pairs(tmp) do r.u[p] = (mx > mn) and (v - mn) / (mx - mn) or 0 end
	end
	if not r.conn then
		r.conn = model.DescendantAdded:Connect(function(d) if not U.isFx(d) then r.dirty = true end end)
	end
	Reg.rigs[model] = r
	return r
end

function Reg.list()
	local t = {}
	for _, c in ipairs(Workspace:GetChildren()) do if isScooter(c) then table.insert(t, c) end end
	return t
end
local lastDeep = -100
function Reg.find()
	if Reg.override and Reg.override.Parent then return Reg.override end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local seat = hum and hum.SeatPart
	local a = seat
	while a and a ~= Workspace do if isScooter(a) then return a end a = a.Parent end
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local best, bd = nil, math.huge
	for _, s in ipairs(Reg.list()) do
		local pos = s:IsA("Model") and s:GetPivot().Position or s.Position
		local d = hrp and (pos - hrp.Position).Magnitude or 0
		if d < bd then best, bd = s, d end
	end
	if best then return best end
	if os.clock() - lastDeep > 3 then
		lastDeep = os.clock()
		for _, n in ipairs(CFG.SCOOTERS) do
			local d = Workspace:FindFirstChild(n, true)
			if d and isScooter(d) then return d end
		end
	end
	return Reg.current and Reg.current.Parent and Reg.current or nil
end
function Reg.currentRig() return Reg.rig(Reg.current) end
function Reg.forward(r) return r.root.CFrame:VectorToWorldSpace(r.fwdLocal) end
function Reg.axes(r)
	local cf = r.root.CFrame
	local up = cf:VectorToWorldSpace(CFG.UP_LOCAL).Unit
	local fwd = cf:VectorToWorldSpace(r.fwdLocal)
	fwd = fwd - up * fwd:Dot(up)
	if fwd.Magnitude < 0.05 then fwd = cf.LookVector - up * cf.LookVector:Dot(up) end
	fwd = fwd.Unit
	local side = fwd:Cross(up).Unit
	return fwd, side:Cross(fwd).Unit, side
end
function U.fxFolder(model)
	local f = model:FindFirstChild("GIGA_FX")
	if not f then f = U.new("Folder", {Name = "GIGA_FX"}, model) end
	return f
end
function U.localBounds(r)
	local root = r.root
	local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, p in ipairs(r.parts) do
		if p.Transparency < 0.98 then
			local rel, h = root.CFrame:ToObjectSpace(p.CFrame), p.Size / 2
			for _, sx in ipairs({-1, 1}) do for _, sy in ipairs({-1, 1}) do for _, sz in ipairs({-1, 1}) do
				local c = rel * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz)
				mn = Vector3.new(math.min(mn.X, c.X), math.min(mn.Y, c.Y), math.min(mn.Z, c.Z))
				mx = Vector3.new(math.max(mx.X, c.X), math.max(mx.Y, c.Y), math.max(mx.Z, c.Z))
			end end end
		end
	end
	return mn, mx
end

-- следим за активным самокатом
task.spawn(function()
	while shared.GIGAHUB == Hub do
		local s = Reg.find()
		if s ~= Reg.current then
			Reg.current = s
			for _, fn in ipairs(Reg.listeners) do task.spawn(fn, s) end
		end
		task.wait(0.5)
	end
end)
function Reg.onChange(fn) table.insert(Reg.listeners, fn) end

---------------------------------------------------------------- current look
Hub.look = {
	cat = {}, slot = {}, rainbow = {},
	hide = {},
	glow  = {on = false, c = RGB(0, 90, 255), bright = 4, range = 10, spread = 100, react = false, strip = false, halo = 0.6},
	trail = {on = false, c = RGB(255, 255, 255)},
	smoke = {c = nil, own = false},
	wheelGlow = {on = false, c = RGB(0, 255, 255)},
}

---------------------------------------------------------------- paint / textures
local Paint, Tex = {}, {}
Hub.Paint, Hub.Tex = Paint, Tex
local FACES = {"Top", "Front", "Back", "Left", "Right", "Bottom"}
Hub.FACES = FACES

local function stripTex(r, p)
	local o = r.orig[p]
	if not o or o.stripped then return end
	o.stripped = true
	for _, ch in ipairs(p:GetChildren()) do
		if ch:IsA("SurfaceAppearance") then
			o.sa = o.sa or {}
			table.insert(o.sa, ch)
			ch.Parent = nil
		elseif ch:IsA("SpecialMesh") then
			o.sm = o.sm or {}
			table.insert(o.sm, {ch, ch.TextureId, ch.VertexColor})
			pcall(function() ch.TextureId = "" ch.VertexColor = Vector3.one end)
		end
	end
	if p:IsA("MeshPart") and p.TextureID ~= "" then
		o.tex = p.TextureID
		pcall(function() p.TextureID = "" end)
	end
end
local function restoreTex(r, p)
	local o = r.orig[p]
	if not o or not o.stripped then return end
	o.stripped = false
	if o.sa then for _, sa in ipairs(o.sa) do sa.Parent = p end o.sa = nil end
	if o.sm then for _, e in ipairs(o.sm) do pcall(function() e[1].TextureId = e[2] e[1].VertexColor = e[3] end) end o.sm = nil end
	if o.tex then local t = o.tex pcall(function() p.TextureID = t end) o.tex = nil end
end
local function paintPart(r, p, c)
	if p:IsA("UnionOperation") then p.UsePartColor = true end
	stripTex(r, p)
	if p.Color ~= c then p.Color = c end
end
-- радуга касается только выбранных категорий и «краски» (цветные акценты), а не всего самоката
local function isRb(k, r, p)
	local rb = Hub.look.rainbow
	return rb[k] == true or (rb.paint == true and r.accent[p] == true)
end

function Paint.refresh()
	local r = Reg.currentRig()
	if not r then return end
	local look = Hub.look
	for _, p in ipairs(r.parts) do
		if p.Parent then
			local k = r.cat[p]
			local slot, cat = look.slot[p.Name], look.cat[k]
			if (slot and slot.h) or look.hide[k] then
				if p.Transparency < 1 then p.Transparency = 1 end
				r.hidden[p] = true
			elseif r.hidden[p] then
				r.hidden[p] = nil
				p.Transparency = r.orig[p].Transparency
			end
			local c = (slot and slot.c) or (cat and cat.c)
			local m = (slot and slot.m) or (cat and cat.m)
			if c and not isRb(k, r, p) then paintPart(r, p, c) end
			if m and p.Material ~= m then p.Material = m end
			if slot and slot.tex then Tex.apply(r, p, slot.tex) end
		end
	end
end
function Paint.restoreAll(r)
	r = r or Reg.currentRig()
	if not r then return end
	for _, p in ipairs(r.parts) do
		local o = r.orig[p]
		if o and p.Parent then
			restoreTex(r, p)
			p.Color, p.Material, p.Transparency = o.Color, o.Material, o.Transparency
			if o.UsePartColor ~= nil and p:IsA("UnionOperation") then p.UsePartColor = o.UsePartColor end
			Tex.clear(p)
		end
	end
	r.hidden = {}
end
function Paint.reset()
	Paint.restoreAll()
	Hub.look.cat, Hub.look.slot, Hub.look.rainbow, Hub.look.hide = {}, {}, {}, {}
end
function Paint.setCat(k, c, m) Hub.look.cat[k] = c and {c = c, m = m} or nil Paint.refresh() end
function Paint.restoreCat(k)
	local r = Reg.currentRig()
	Hub.look.cat[k] = nil
	if not r then return end
	for _, p in ipairs(r.byCat[k] or {}) do
		local o = r.orig[p]
		if o and p.Parent then restoreTex(r, p) p.Color, p.Material = o.Color, o.Material end
	end
end
function Paint.setHideCat(k, v)
	Hub.look.hide[k] = v or nil
	Paint.refresh()
end

-- ТЕКСТУРЫ по URL (PNG/JPG). mode: "Image" (SurfaceGui, работает на любой детали) | "Decal" | "UV" | "Anim" (спрайт-лист)
function Tex.clear(p)
	for _, n in ipairs({"GIGA_Tex", "GIGA_Img", "GIGA_Anim"}) do
		local d = p:FindFirstChild(n)
		if d then d:Destroy() end
	end
end
local function surfaceImage(p, spec, name)
	local face = spec.face or "Top"
	local key = spec.asset .. "|" .. face .. "|" .. (spec.mode or "")
	local sg = p:FindFirstChild(name)
	if sg and sg:GetAttribute("k") == key then return end
	if sg then sg:Destroy() end
	sg = U.new("SurfaceGui", {Name = name, Face = Enum.NormalId[face], LightInfluence = 0, AlwaysOnTop = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		SizingMode = Enum.SurfaceGuiSizingMode.FixedSize, CanvasSize = Vector2.new(512, 512), Brightness = 1}, p)
	sg:SetAttribute("k", key)
	local box = U.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ClipsDescendants = true}, sg)
	if spec.mode == "Anim" then
		local cols, rows, fps = spec.cols or 4, spec.rows or 4, spec.fps or 12
		local img = U.new("ImageLabel", {Size = UDim2.fromScale(cols, rows), BackgroundTransparency = 1, Image = spec.asset, ScaleType = Enum.ScaleType.Stretch}, box)
		task.spawn(function()
			local i = 0
			while sg.Parent and shared.GIGAHUB == Hub do
				img.Position = UDim2.fromScale(-(i % cols), -math.floor(i / cols))
				i = (i + 1) % (cols * rows)
				task.wait(1 / math.max(fps, 1))
			end
		end)
	else
		U.new("ImageLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = spec.asset, ScaleType = Enum.ScaleType.Stretch}, box)
	end
end
function Tex.apply(r, p, spec)
	if not spec or not spec.asset then return end
	local mode = spec.mode or "Image"
	if mode == "UV" and p:IsA("MeshPart") then
		stripTex(r, p)
		if p.TextureID ~= spec.asset then pcall(function() p.TextureID = spec.asset end) end
	elseif mode == "Anim" then surfaceImage(p, spec, "GIGA_Anim")
	elseif mode == "Decal" then
		local d = p:FindFirstChild("GIGA_Tex")
		local face = Enum.NormalId[spec.face or "Top"]
		if d and d.Texture == spec.asset and d.Face == face then return end
		if d then d:Destroy() end
		U.new("Decal", {Name = "GIGA_Tex", Texture = spec.asset, Face = face}, p)
	else surfaceImage(p, spec, "GIGA_Img") end
end
function Tex.setSlot(name, spec, cb)
	local slot = Hub.look.slot[name] or {}
	Hub.look.slot[name] = slot
	if not spec then
		slot.tex = nil
		local r = Reg.currentRig()
		if r and r.slotMap[name] then for _, p in ipairs(r.slotMap[name].parts) do Tex.clear(p) end end
		Paint.refresh()
		return
	end
	task.spawn(function()
		local asset, err = Img.get(spec.url)
		if not asset then if cb then cb(false, err) end return end
		spec.asset = asset
		slot.tex = spec
		Paint.refresh()
		if cb then cb(true) end
	end)
end

-- радужная краска (только выбранное)
Hub.addUpdater(function()
	local rb = Hub.look.rainbow
	if not next(rb) then return end
	local r = Reg.currentRig()
	if not r then return end
	local t = os.clock() * 0.22
	for _, p in ipairs(r.parts) do
		if isRb(r.cat[p], r, p) then
			if p:IsA("UnionOperation") then p.UsePartColor = true end
			stripTex(r, p)
			p.Color = HSV((t + (r.u[p] or 0) * 0.6) % 1, 0.95, 0.95)
		end
	end
end)
task.spawn(function()
	while shared.GIGAHUB == Hub do
		task.wait(1)
		local look = Hub.look
		if next(look.cat) or next(look.slot) or next(look.hide) then pcall(Paint.refresh) end
	end
end)

---------------------------------------------------------------- effects
local Fx = {}
Hub.Fx = Fx
local function rbOn(k) return Hub.look.rainbow[k] == true end
local function hue(off) return HSV((os.clock() * 0.3 + (off or 0)) % 1, 1, 1) end
local function speedOf(r) return r.root and r.root.AssemblyLinearVelocity.Magnitude or 0 end
local function newHolder(r, name, size, cf, transparency)
	local h = U.new("Part", {Name = name, Size = size, CFrame = cf, Transparency = transparency, Material = Enum.Material.Neon, CanCollide = false, CanQuery = false,
		CanTouch = false, CastShadow = false, Massless = true, Anchored = false}, U.fxFolder(r.model))
	U.new("WeldConstraint", {Part0 = r.root, Part1 = h}, h)
	return h
end

-- Underglow: невидимый блок (по желанию — неоновая полоса) + свет ТОЛЬКО вниз, приварен к самокату (без лагов)
local G = {}
Fx.glow = G
function G.destroy() if G.holder then G.holder:Destroy() end G.holder, G.surf, G.point = nil, nil, nil end
function G.build()
	G.destroy()
	local look = Hub.look
	if not look.glow.on then return false end
	local r = Reg.currentRig()
	if not r or not r.root then return false end
	local mn, mx = U.localBounds(r)
	local size, center = mx - mn, (mn + mx) / 2
	local fwd, up, side = Reg.axes(r)
	local pos = (r.root.CFrame * CFrame.new(center.X, mn.Y + math.max(size.Y * 0.06, 0.12), center.Z)).Position
	-- ориентация по миру самоката (Bottom всегда смотрит вниз, даже если у корня «кривые» оси)
	local cf = CFrame.fromMatrix(pos, side, up)
	local w, l = math.min(size.X, size.Z) * 0.5, math.max(size.X, size.Z) * 0.55
	local h = newHolder(r, "GIGA_GlowHolder", Vector3.new(math.max(w, 0.4), 0.06, math.max(l, 0.4)), cf, look.glow.strip and 0 or 1)
	h.Color = look.glow.c
	G.surf = U.new("SurfaceLight", {Face = Enum.NormalId.Bottom, Angle = look.glow.spread, Color = look.glow.c, Brightness = look.glow.bright, Range = look.glow.range, Shadows = false}, h)
	G.point = U.new("PointLight", {Color = look.glow.c, Brightness = look.glow.bright * look.glow.halo, Range = math.max(look.glow.range * 0.55, 3), Shadows = false}, h)
	G.holder = h
	return true
end
function G.setColor(c) if G.holder then G.holder.Color = c G.surf.Color = c G.point.Color = c end end
function G.setLight(b, rng, spread)
	if G.surf then
		G.surf.Brightness, G.surf.Range = b, rng
		if spread then G.surf.Angle = spread end
		G.point.Brightness, G.point.Range = b * Hub.look.glow.halo, math.max(rng * 0.55, 3)
	end
end
function G.setStrip(v) Hub.look.glow.strip = v if G.holder then G.holder.Transparency = v and 0 or 1 end end

-- Trail (лента света по земле)
local T = {}
Fx.trail = T
function T.destroy() for _, o in pairs(T.objs or {}) do o:Destroy() end T.objs = nil T.obj = nil end
function T.build()
	T.destroy()
	if not Hub.look.trail.on then return end
	local r = Reg.currentRig()
	if not r or not r.root then return end
	local info = wheelInfo(r.rear)
	local lp, rad, width
	if info then
		lp = r.root.CFrame:PointToObjectSpace(info.center)
		rad, width = info.r, math.clamp(info.w * 2.5, 0.8, 3)
	else
		lp, rad, width = -r.fwdLocal * (math.max(r.root.Size.X, r.root.Size.Z) / 2), 0.3, 1
	end
	local side = r.fwdLocal:Cross(Vector3.yAxis)
	if side.Magnitude < 0.1 then side = Vector3.xAxis end
	side = side.Unit
	local ground = lp + Vector3.new(0, -rad + 0.06, 0)
	local a0 = U.new("Attachment", {Name = "GIGA_TA0", Position = ground - side * width / 2}, r.root)
	local a1 = U.new("Attachment", {Name = "GIGA_TA1", Position = ground + side * width / 2}, r.root)
	local t = U.new("Trail", {Name = "GIGA_Trail", Attachment0 = a0, Attachment1 = a1, Color = ColorSequence.new(Hub.look.trail.c),
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1)}),
		LightEmission = 1, Lifetime = 1.2, MinLength = 0.05, FaceCamera = false}, r.root)
	T.objs, T.obj = {a0, a1, t}, t
end

-- Smoke: свой дым + перекраска игрового (список эмиттеров кэшируется — никаких GetDescendants каждый кадр)
local S = {list = {}, scanned = -100}
Fx.smoke = S
local smokeOrig = setmetatable({}, {__mode = "k"})
function S.destroy() if S.att then S.att:Destroy() end S.att, S.em = nil, nil end
local function rainbowSeq(o)
	local kp = {}
	for i = 0, 6 do kp[#kp + 1] = ColorSequenceKeypoint.new(i / 6, HSV((o + i / 7) % 1, 0.85, 1)) end
	return ColorSequence.new(kp)
end
function S.scan(force)
	if not force and os.clock() - S.scanned < 4 then return end
	S.scanned = os.clock()
	local list = {}
	local r = Reg.currentRig()
	if r then for _, d in ipairs(r.model:GetDescendants()) do if d:IsA("ParticleEmitter") and not U.isFx(d) then list[#list + 1] = d end end end
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("ParticleEmitter") and not U.isFx(d) then
			local n = d.Name:lower()
			if n:find("smoke") or n:find("skid") or n:find("burnout") or n:find("drift") then list[#list + 1] = d end
		end
	end
	S.list = list
end
function S.build()
	S.destroy()
	local look = Hub.look
	if not look.smoke.own then return end
	local r = Reg.currentRig()
	if not r or not r.root then return end
	local info = wheelInfo(r.rear)
	local pos = info and r.root.CFrame:PointToObjectSpace(info.center) + Vector3.new(0, -info.r * 0.6, 0) or Vector3.new(0, -1, 1)
	local att = U.new("Attachment", {Name = "GIGA_SmokeAtt", CFrame = CFrame.lookAt(pos, pos - r.fwdLocal)}, r.root)
	S.em = U.new("ParticleEmitter", {Name = "GIGA_Smoke", Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(look.smoke.c or RGB(230, 230, 230)),
		Rate = 40, Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(22, 22),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60), LightEmission = 0.3,
		Size = NumberSequence.new({NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 4.5)}),
		Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1)}),
		EmissionDirection = Enum.NormalId.Front, Enabled = false}, att)
	S.att = att
end
function S.recolorGame(c)
	S.scan(true)
	for _, d in ipairs(S.list) do
		if d.Parent then
			if not smokeOrig[d] then smokeOrig[d] = d.Color end
			d.Color = ColorSequence.new(c)
		end
	end
end
function S.restoreGame() for d, c in pairs(smokeOrig) do if d.Parent then d.Color = c end end end

-- Wheel glow: неоновые кольца, приварены к колёсам
local WG = {rings = {}}
Fx.wheelGlow = WG
function WG.destroy() for _, p in ipairs(WG.rings) do p:Destroy() end WG.rings = {} end
function WG.build()
	WG.destroy()
	if not Hub.look.wheelGlow.on then return end
	local r = Reg.currentRig()
	if not r or not r.root then return end
	local _, _, side = Reg.axes(r)
	local fwd = Reg.axes(r)
	for _, grp in ipairs({r.front, r.rear}) do
		local info = wheelInfo(grp)
		if info then
			for _, sg in ipairs({-1, 1}) do
				local ring = U.new("Part", {Name = "GIGA_WheelRing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, info.r * 1.45, info.r * 1.45), Material = Enum.Material.Neon,
					Color = Hub.look.wheelGlow.c, CFrame = CFrame.fromMatrix(info.center + side * (sg * (info.w / 2 + 0.02)), side, fwd), CanCollide = false, CanQuery = false,
					CanTouch = false, CastShadow = false, Massless = true}, U.fxFolder(r.model))
				U.new("WeldConstraint", {Part0 = info.part, Part1 = ring}, ring)
				WG.rings[#WG.rings + 1] = ring
			end
		end
	end
end

-- Lights (радуга для игровых ламп), кэш
local L = {list = {}, scanned = -100}
local lightsOrig = setmetatable({}, {__mode = "k"})
function Fx.restoreLights() for d, c in pairs(lightsOrig) do if d.Parent then d.Color = c end end end

local acc = {a = 0, b = 0}
Hub.addUpdater(function(dt)
	local look = Hub.look
	local r = Reg.currentRig()
	if not r or not r.root then return end
	if G.holder then
		if rbOn("glow") then G.setColor(hue()) end
		if look.glow.react then
			local k = 1 + math.clamp(speedOf(r) / 25, 0, 2.5)
			G.setLight(look.glow.bright * k, look.glow.range * (0.8 + k * 0.2))
		end
	end
	if T.obj and rbOn("trail") then T.obj.Color = ColorSequence.new(hue(), hue(-0.15)) end
	if S.em then
		local W = Hub.Wheelie
		S.em.Enabled = (W and (W.on or W.auto)) or speedOf(r) > 12
		if not rbOn("smoke") then S.em.Color = ColorSequence.new(look.smoke.c or RGB(230, 230, 230)) end
	end
	acc.a = acc.a + dt
	if acc.a >= 0.1 then -- тяжёлое — 10 раз в секунду
		acc.a = 0
		if rbOn("smoke") then
			local seq = rainbowSeq(os.clock() * 0.3)
			if S.em then S.em.Color = seq end
			S.scan()
			for _, d in ipairs(S.list) do if d.Parent then smokeOrig[d] = smokeOrig[d] or d.Color d.Color = seq end end
		end
		if rbOn("lights") then
			if os.clock() - L.scanned > 3 then
				L.scanned = os.clock()
				L.list = {}
				for _, d in ipairs(r.model:GetDescendants()) do if d:IsA("Light") and not U.isFx(d) then L.list[#L.list + 1] = d end end
			end
			local c = hue(0.5)
			for _, d in ipairs(L.list) do if d.Parent then lightsOrig[d] = lightsOrig[d] or d.Color d.Color = c end end
		end
		if #WG.rings > 0 then
			for i, ring in ipairs(WG.rings) do
				if ring.Parent then ring.Color = rbOn("wheelglow") and hue(i * 0.12) or look.wheelGlow.c end
			end
		end
	end
end)

function Fx.rebuildAll()
	G.build() T.build() S.build() WG.build()
	if Hub.Garland then Hub.Garland.build() end
	local sm = Hub.look.smoke
	if sm.c then S.recolorGame(sm.c) end
end
Reg.onChange(function()
	task.wait(0.3) Paint.refresh() Fx.rebuildAll()
	if Hub.Fork and Hub.Fork.cfg.on then Hub.Fork.build() end
	if Hub.Pend and Hub.Pend.cfg.on then Hub.Pend.build() end
end)
Hub.onClean(function() G.destroy() T.destroy() S.destroy() WG.destroy() S.restoreGame() Fx.restoreLights() local r = Reg.currentRig() if r then Paint.restoreAll(r) end end)

---------------------------------------------------------------- wheelie (F) + auto wheelie (G, beta)
local W = {on = false, auto = false, angle = 55, power = 7, ramp = 70, nudgeAmp = 1.0, nudgeFreq = 0.5, target = 0, invert = false, pivot = true, level = true, brake = 1.2}
Hub.Wheelie = W
W.listeners = {}
local function wfire() for _, f in ipairs(W.listeners) do pcall(f) end end
function W.set(v) W.on = v wfire() end
function W.setAuto(v) W.auto = v wfire() end
local RP = RaycastParams.new()
RP.FilterType = Enum.RaycastFilterType.Exclude
-- физика на Stepped. Скорость центра масс НЕ накапливается (она задаётся заново каждый шаг от точки опоры),
-- поэтому самокат не улетает вверх, а стоит на заднем колесе и удерживает угол
U.connect(RS.Stepped, function(_, dt)
	if not dt or dt <= 0 then return end
	local active = W.on or W.auto
	W.target = W.target + math.clamp((active and W.angle or 0) - W.target, -W.ramp * dt, W.ramp * dt)
	if not active and W.target < 0.05 then W.target = 0 return end
	local r = Reg.currentRig()
	if not r or not r.root or r.root.Anchored then return end
	local root = r.root
	local fwd = Reg.forward(r).Unit
	if W.invert then fwd = -fwd end
	local right = fwd:Cross(Vector3.yAxis)
	if right.Magnitude < 0.1 then return end
	right = right.Unit
	local pitch = math.deg(math.asin(math.clamp(fwd.Y, -1, 1)))
	local av = root.AssemblyAngularVelocity
	local rate = av:Dot(right)
	local want = math.clamp(math.rad(W.target - pitch) * W.power, -4, 4)
	local newAV = av + right * ((rate + (want - rate) * math.clamp(dt * 20, 0, 1)) - rate)
	if W.level then -- без крена
		local rr = newAV:Dot(fwd)
		local goal = -right:Dot(root.CFrame:VectorToWorldSpace(CFG.UP_LOCAL)) * 6
		newAV = newAV + fwd * ((rr + (goal - rr) * math.clamp(dt * 10, 0, 1)) - rr)
	end
	root.AssemblyAngularVelocity = newAV
	local lv = root.AssemblyLinearVelocity
	local hv = Vector3.new(lv.X, 0, lv.Z)
	if W.auto then -- стоим на месте + лёгкое покачивание вперёд-назад
		local flat = Vector3.new(fwd.X, 0, fwd.Z)
		if flat.Magnitude > 0.05 then hv = flat.Unit * (math.sin(os.clock() * W.nudgeFreq * math.pi * 2) * W.nudgeAmp) end
	elseif W.brake > 0 then -- обычное вилли (F): плавно тормозим
		hv = hv * math.clamp(1 - W.brake * dt, 0, 1)
	end
	local info = W.pivot and wheelInfo(r.rear)
	local grounded = false
	if info then
		RP.FilterDescendantsInstances = {r.model, player.Character}
		grounded = Workspace:Raycast(info.center, Vector3.new(0, -(info.r + 1.2), 0), RP) ~= nil
	end
	if info and grounded then
		local pivot = info.center - Vector3.new(0, info.r, 0) -- точка касания заднего колеса
		lv = hv + newAV:Cross(root.AssemblyCenterOfMass - pivot)
	else
		lv = Vector3.new(hv.X, lv.Y, hv.Z)
	end
	if lv.Y > 10 then lv = Vector3.new(lv.X, 10, lv.Z) end
	root.AssemblyLinearVelocity = lv
end)

---------------------------------------------------------------- spring fork (из GIGA FORK) — на все самокаты
local F = {cfg = {on = false, side = 0, length = 2.3, thick = 0.10, turns = 8, segs = 10, rake = -1}, built = nil}
Hub.Fork = F
local FC = {fork = RGB(22, 22, 24), metal = RGB(190, 194, 200), sa = RGB(245, 245, 245), sb = RGB(25, 25, 28)}
function F.remove() if F.built and F.built.folder then F.built.folder:Destroy() end F.built = nil end
function F.build()
	F.remove()
	local r = Reg.currentRig()
	if not r or not r.root then return false end
	local fi, ri = wheelInfo(r.front), wheelInfo(r.rear)
	if not fi then return false end
	local cfg = F.cfg
	local rad, A = fi.r, fi.center
	local w = math.clamp(fi.w, rad * 0.15, rad * 1.2)
	local fwd, up, side = Reg.axes(r)
	local ref
	local hb = {}
	for _, k in ipairs({"handlebar", "grips"}) do for _, p in ipairs(r.byCat[k]) do table.insert(hb, p) end end
	if #hb > 0 then ref = U.centroid(hb) end
	local rake = cfg.rake >= 0 and cfg.rake or 12
	if cfg.rake < 0 and ref then
		local v = ref - A
		local a, b = v:Dot(up), v:Dot(fwd)
		if a > 0.5 then rake = math.clamp(math.deg(math.atan2(-b, a)), 0, 30) end
	end
	local rk = math.rad(rake)
	local u = (up * math.cos(rk) - fwd * math.sin(rk)).Unit
	local n = u:Cross(side).Unit
	local rf, L = math.max(rad * cfg.thick, 0.04), rad * cfg.length
	local h1, h2, halfW = L * 0.26, L * 0.80, w / 2
	local capT = math.max(rad * 0.07, 0.05)
	local off = cfg.side * (halfW + rf * 1.8)
	local Alat = A + side * off
	local function P(t) return Alat + u * t end
	local anchor, bd
	for _, k in ipairs({"stem", "handlebar", "suspension", "grips"}) do
		for _, p in ipairs(r.byCat[k]) do
			local d = (p.Position - A).Magnitude
			if not bd or d < bd then anchor, bd = p, d end
		end
	end
	anchor = anchor or r.root
	local folder = U.fxFolder(r.model)
	local sub = U.new("Folder", {Name = "GIGA_FORK"}, folder)
	local function add(a, b, dia, color, ov, name)
		local d = b - a
		local len = d.Magnitude
		if len < 1e-4 then return end
		local dir = d / len
		local rf2 = (math.abs(dir:Dot(side)) < 0.9) and side or up
		local perp = (rf2 - dir * rf2:Dot(dir)).Unit
		local p = U.new("Part", {Name = name or "ForkPart", Shape = Enum.PartType.Cylinder, Size = Vector3.new(len + (ov or 0), math.max(dia, 0.05), math.max(dia, 0.05)),
			CFrame = CFrame.fromMatrix((a + b) / 2, dir, perp), Color = color, Material = Enum.Material.Metal, Anchored = false, CanCollide = false,
			CanQuery = false, CanTouch = false, Massless = true, CastShadow = false}, sub)
		U.new("WeldConstraint", {Part0 = anchor, Part1 = p}, p)
	end
	add(A + side * (math.min(-halfW, off - rf * 1.2) - capT * 1.2), A + side * (math.max(halfW, off + rf * 1.2) + capT * 1.2), rf, FC.metal, 0, "Axle")
	for _, sg in ipairs({-1, 1}) do
		local c = A + side * (sg * (halfW + capT * 0.5))
		add(c - side * capT * 0.5, c + side * capT * 0.5, rad * 0.30, FC.metal, 0, "Cap")
	end
	add(P(-rf * 0.8), P(h1), rf * 2.5, FC.fork, 0, "Lower")
	add(P(h1), P(h2), rf * 1.7, FC.fork, 0, "Core")
	local hA, hB, Rh, tw = h1 + rf * 0.5, h2 - rf * 0.5, rf * 1.55, rf * 0.8
	local total, prev = cfg.turns * cfg.segs, nil
	for i = 0, total do
		local t = i / total
		local ang = t * cfg.turns * 2 * math.pi
		local pt = P(hA + (hB - hA) * t) + (side * math.cos(ang) + n * math.sin(ang)) * Rh
		if prev then add(prev, pt, tw, (math.floor((i - 1) / cfg.segs) % 2 == 0) and FC.sa or FC.sb, tw * 0.7, "Spring") end
		prev = pt
	end
	add(P(h1), P(h1 + rf * 0.55), Rh * 2.5, FC.metal, 0, "SeatLow")
	add(P(h2 - rf * 0.55), P(h2), Rh * 2.5, FC.metal, 0, "SeatHigh")
	add(P(h2), P(L), rf * 2.0, FC.metal, 0, "Upper")
	add(P(L - rf * 1.4), P(L + rf * 0.4), rf * 3.4, FC.fork, 0, "Clamp")
	F.built = {folder = sub, anchor = anchor, model = r.model}
	return true
end
function F.set(on)
	F.cfg.on = on
	if on then F.build() else F.remove() end
end
task.spawn(function()
	while shared.GIGAHUB == Hub do
		task.wait(0.7)
		if F.cfg.on and Reg.current then
			local b = F.built
			if not b or not b.folder.Parent or b.model ~= Reg.current or not b.anchor:IsDescendantOf(Reg.current) then pcall(F.build) end
		end
	end
end)
Hub.onClean(F.remove)

---------------------------------------------------------------- custom helmet (переписан)
local H = {on = false, cache = {}, cfg = {hy = 0, hz = 0, hs = 1, gy = 0, gz = 0, gs = 1, mask = true, goggles = true, hideHair = true}}
Hub.Helmet = H
local function loadAcc(id)
	if H.cache[id] ~= nil then return H.cache[id] or nil end
	local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
	local acc
	if ok and objs then
		for _, o in ipairs(objs) do
			acc = o:IsA("Accessory") and o or o:FindFirstChildWhichIsA("Accessory", true)
			if acc then break end
		end
	end
	H.cache[id] = acc or false
	return acc
end
local function procAcc(name, color, ball)
	local acc = Instance.new("Accessory")
	local h = U.new("Part", {Name = "Handle", Size = ball and Vector3.new(1.45, 1.45, 1.45) or Vector3.new(1.3, 0.4, 0.3), Shape = ball and Enum.PartType.Ball or Enum.PartType.Block,
		Color = color, Material = Enum.Material.SmoothPlastic, CanCollide = false, Massless = true}, acc)
	U.new("Attachment", {Name = ball and "HatAttachment" or "FaceFrontAttachment", CFrame = ball and CFrame.new(0, 0.55, 0) or CFrame.new(0, 0, 0.5)}, h)
	return acc
end
function H.detach(char)
	char = char or player.Character
	if not char then return end
	for _, o in ipairs(char:GetDescendants()) do
		if o:GetAttribute("GIGAH") then o:Destroy() end
		if o:IsA("BasePart") and o:GetAttribute("GIGAHairHidden") then o.Transparency = o:GetAttribute("GIGAHairHidden") o:SetAttribute("GIGAHairHidden", nil) end
	end
end
local function place(acc, hum, dy, dz, scale)
	local handle = acc:FindFirstChild("Handle")
	if not handle then return end
	for _, d in ipairs(acc:GetDescendants()) do
		if d:IsA("BasePart") then d.CanCollide, d.Massless, d.Anchored = false, true, false end
	end
	acc:SetAttribute("GIGAH", true)
	hum:AddAccessory(acc)
	task.spawn(function()
		local weld = handle:WaitForChild("AccessoryWeld", 2)
		if weld and weld:IsA("Weld") then
			weld.C0 = weld.C0 * CFrame.new(0, dy, dz)
			if scale ~= 1 then handle.Size = handle.Size * scale end
		end
	end)
end
function H.attach(char)
	char = char or player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local head = char and char:FindFirstChild("Head")
	if not hum or not head then return end
	H.detach(char)
	local c = H.cfg
	if c.hideHair then
		for _, a in ipairs(char:GetChildren()) do
			if a:IsA("Accessory") then
				local hd = a:FindFirstChild("Handle")
				if hd and hd.Transparency < 1 then hd:SetAttribute("GIGAHairHidden", hd.Transparency) hd.Transparency = 1 end
			end
		end
	end
	task.spawn(function()
		local hs = loadAcc(CFG.HELMET_ID)
		local helm = hs and hs:Clone() or procAcc("Helmet", RGB(20, 20, 24), true)
		helm.Name = "GIGA_Helmet"
		place(helm, hum, c.hy, c.hz, c.hs)
		if c.goggles then
			local gsrc = loadAcc(CFG.GOGGLES_ID)
			local g = gsrc and gsrc:Clone() or procAcc("Goggles", RGB(40, 110, 200), false)
			g.Name = "GIGA_Goggles"
			place(g, hum, c.gy, c.gz, c.gs)
		end
	end)
	if c.mask then
		local m = U.new("Part", {Name = "GIGA_Mask", Shape = Enum.PartType.Ball, Size = Vector3.new(head.Size.X * 1.18, head.Size.Y * 0.95, head.Size.Z * 1.18),
			Color = RGB(8, 8, 8), Material = Enum.Material.SmoothPlastic, CanCollide = false, Massless = true, CastShadow = false,
			CFrame = head.CFrame * CFrame.new(0, -head.Size.Y * 0.15, 0)}, head)
		m:SetAttribute("GIGAH", true)
		U.new("WeldConstraint", {Part0 = head, Part1 = m}, m)
	end
end
function H.set(on)
	H.on = on
	if on then H.attach() else H.detach() end
end
U.connect(player.CharacterAdded, function(char)
	if H.on then task.wait(1.5) if H.on then H.attach(char) end end
end)
task.spawn(function()
	while shared.GIGAHUB == Hub do
		task.wait(3)
		local char = player.Character
		if H.on and char and char:FindFirstChild("Head") and not char:FindFirstChild("GIGA_Helmet") then pcall(H.attach, char) end
	end
end)
Hub.onClean(function() H.detach() end)

---------------------------------------------------------------- misc: sky, stretch, fov, cinematic, speedo, photo
local M = {stretchV = 0.75, fov = 70}
Hub.Misc = M
local savedSky
function M.darkSky(on)
	if on then
		if not savedSky then savedSky = {Lighting.ClockTime, Lighting.Brightness, Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.FogColor, Lighting.FogEnd, Lighting.FogStart} end
		M.skyOn = true
		Lighting.ClockTime, Lighting.Brightness = 0, 1.5
		Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.FogColor = RGB(40, 40, 50), RGB(50, 50, 70), RGB(30, 30, 45)
		Lighting.FogEnd, Lighting.FogStart = 700, 150
	else
		M.skyOn = false
		if savedSky then
			Lighting.ClockTime, Lighting.Brightness, Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.FogColor, Lighting.FogEnd, Lighting.FogStart = table.unpack(savedSky)
			savedSky = nil
		end
	end
end
Hub.addUpdater(function() if M.skyOn and Lighting.ClockTime > 1 and Lighting.ClockTime < 23 then Lighting.ClockTime = 0 end end)
function M.stretch(on)
	pcall(function() RS:UnbindFromRenderStep("GIGA_Stretch") end)
	M.stretchOn = on
	if on then
		RS:BindToRenderStep("GIGA_Stretch", Enum.RenderPriority.Camera.Value + 1, function()
			local cam = Workspace.CurrentCamera
			if cam then cam.CFrame = cam.CFrame * CFrame.new(0, 0, 0, 1, 0, 0, 0, M.stretchV, 0, 0, 0, 1) end
		end)
	end
end
function M.setFov(v) M.fov = v M.fovOn = true local cam = Workspace.CurrentCamera if cam then cam.FieldOfView = v end end
Hub.addUpdater(function() if M.fovOn then local cam = Workspace.CurrentCamera if cam and math.abs(cam.FieldOfView - M.fov) > 0.1 then cam.FieldOfView = M.fov end end end)
function M.cinematic(on)
	local bloom = Lighting:FindFirstChild("GIGA_Bloom")
	local cc = Lighting:FindFirstChild("GIGA_CC")
	if on then
		bloom = bloom or U.new("BloomEffect", {Name = "GIGA_Bloom", Intensity = 0.7, Size = 28, Threshold = 1.1}, Lighting)
		cc = cc or U.new("ColorCorrectionEffect", {Name = "GIGA_CC", Contrast = 0.12, Saturation = 0.25, TintColor = RGB(255, 245, 255)}, Lighting)
	else
		if bloom then bloom:Destroy() end
		if cc then cc:Destroy() end
	end
end
Hub.onClean(function() M.stretch(false) M.cinematic(false) M.darkSky(false) end)

---------------------------------------------------------------- Custom details: маятниковая подвеска (как на фото) + гирлянда
local P = {cfg = {on = false, side = 1, turns = 7, thick = 1, hideStock = false, len = 1.4, mode = "full", cable = true}, built = nil}
Hub.Pend = P
local PC = {arm = RGB(24, 24, 27), metal = RGB(185, 190, 198), sa = RGB(245, 245, 245), sb = RGB(22, 22, 25), wire = RGB(14, 14, 16)}
function P.remove() if P.built and P.built.folder then P.built.folder:Destroy() end P.built = nil end
function P.build()
	P.remove()
	local r = Reg.currentRig()
	if not r or not r.root then return false end
	local fi = wheelInfo(r.front)
	if not fi then return false end
	local cfg = P.cfg
	local rad, A = fi.r, fi.center
	local halfW = math.clamp(fi.w, rad * 0.15, rad * 1.2) / 2
	local fwd, up, side = Reg.axes(r)
	local rf = math.max(rad * 0.085, 0.05) * cfg.thick
	local off = side * (cfg.side * (halfW + rf * 2.4))
	local anchor, bd
	for _, k in ipairs({"stem", "handlebar", "suspension", "grips"}) do
		for _, p in ipairs(r.byCat[k]) do
			local d = (p.Position - A).Magnitude
			if not bd or d < bd then anchor, bd = p, d end
		end
	end
	anchor = anchor or r.root
	local sub = U.new("Folder", {Name = "GIGA_PEND"}, U.fxFolder(r.model))
	local function add(a, b, dia, color, name, ov)
		local d = b - a
		local len = d.Magnitude
		if len < 1e-4 then return end
		local dir = d / len
		local ref = (math.abs(dir:Dot(side)) < 0.9) and side or up
		local p = U.new("Part", {Name = name, Shape = Enum.PartType.Cylinder, Size = Vector3.new(len + (ov or 0), math.max(dia, 0.04), math.max(dia, 0.04)),
			CFrame = CFrame.fromMatrix((a + b) / 2, dir, (ref - dir * ref:Dot(dir)).Unit), Color = color, Material = Enum.Material.Metal, CanCollide = false,
			CanQuery = false, CanTouch = false, Massless = true, CastShadow = false}, sub)
		U.new("WeldConstraint", {Part0 = anchor, Part1 = p}, p)
	end
	local function bez3(p0, p1, p2, p3, t)
		local u = 1 - t
		return u ^ 3 * p0 + 3 * u * u * t * p1 + 3 * u * t * t * p2 + t ^ 3 * p3
	end
	local L = cfg.len
	local S0 = A + up * (rad * 2.1) - fwd * (rad * 0.2) + off                                   -- низ рулевой стойки
	local T0 = A + fwd * (rad * 0.9 * L) + up * (rad * (1.0 + 0.25 * L)) + off                  -- верхнее крепление амортизатора
	local C0 = S0 + fwd * (rad * 1.5 * L) + up * (rad * 0.05)
	local H0 = A + off                                                                          -- ступица
	if cfg.mode == "full" then
		local prev
		for i = 0, 12 do
			local t = i / 12
			local pt = (1 - t) ^ 2 * S0 + 2 * (1 - t) * t * C0 + t ^ 2 * T0
			if prev then add(prev, pt, rf * (3.0 - 1.1 * t), PC.arm, "Arm", rf * 1.2) end
			prev = pt
		end
		add(S0 - up * rf, S0 + up * rf * 2.5, rf * 3.6, PC.arm, "ArmJoint")
	else
		add(T0 + up * rf * 4, T0, rf * 2.8, PC.arm, "Mount") -- «маятник в колесе»: только амортизатор у колеса
	end
	-- амортизатор
	local dir = (H0 - T0).Unit
	local len = (H0 - T0).Magnitude
	add(T0 - dir * rf, T0 + dir * len * 0.2, rf * 3.4, PC.arm, "ShockTop")
	local n = side:Cross(dir)
	n = n.Magnitude > 0.05 and n.Unit or up
	local m = dir:Cross(n).Unit
	local a0, b0 = T0 + dir * len * 0.2, T0 + dir * len * 0.82
	local total, prevp = cfg.turns * 10, nil
	for i = 0, total do
		local t = i / total
		local ang = t * cfg.turns * 2 * math.pi
		local pt = a0 + (b0 - a0) * t + (n * math.cos(ang) + m * math.sin(ang)) * (rf * 1.7)
		if prevp then add(prevp, pt, rf * 0.85, (math.floor((i - 1) / 10) % 2 == 0) and PC.sa or PC.sb, "Coil", rf * 0.6) end
		prevp = pt
	end
	add(a0, b0, rf * 1.5, PC.arm, "ShockCore")
	add(b0, H0 - dir * rf, rf * 2.0, PC.metal, "ShockRod")
	add(H0 - side * (cfg.side * rf * 1.6), H0 + side * (cfg.side * rf * 1.6), rf * 2.6, PC.metal, "HubCap")
	-- провод: из ЦЕНТРА руля вниз вдоль стойки и в колесо (ступицу)
	if cfg.cable then
		local hb = {}
		for _, k in ipairs({"handlebar", "grips"}) do for _, p in ipairs(r.byCat[k]) do if p.Transparency < 0.98 then hb[#hb + 1] = p end end end
		if #hb > 0 then
			local c = U.centroid(hb)
			c = c - side * (c - A):Dot(side) -- строго по центру руля (на оси самоката)
			local drop = (c - A):Dot(up)
			local p1 = c - up * drop * 0.35 + fwd * rad * 0.1
			local p2 = A + up * rad * 2.5 + off * 0.45 - fwd * rad * 0.05
			local p3 = H0 + side * (cfg.side * rf * 0.4)
			local pv
			for i = 0, 18 do
				local pt = bez3(c, p1, p2, p3, i / 18)
				if pv then add(pv, pt, rf * 0.5, PC.wire, "Cable", rf * 0.3) end
				pv = pt
			end
		end
	end
	P.built = {folder = sub, anchor = anchor, model = r.model}
	if cfg.hideStock then Hub.Paint.setHideCat("suspension", true) end
	return true
end
function P.set(on)
	P.cfg.on = on
	if on then P.build() else P.remove() end
end
function P.hideStock(v)
	P.cfg.hideStock = v
	Hub.Paint.setHideCat("suspension", v)
end
task.spawn(function()
	while shared.GIGAHUB == Hub do
		task.wait(0.7)
		if P.cfg.on and Reg.current then
			local b = P.built
			if not b or not b.folder.Parent or b.model ~= Reg.current or not b.anchor:IsDescendantOf(Reg.current) then pcall(P.build) end
		end
	end
end)
Hub.onClean(P.remove)

-- Гирлянда вдоль деки снизу слева и справа, всегда включена, свой цвет
local Ga = {cfg = {on = false, c = RGB(255, 170, 60), count = 20, size = 1, mode = "Solid", bright = 1.5}, leds = {}, parts = {}}
Hub.Garland = Ga
function Ga.destroy() for _, p in ipairs(Ga.parts) do p:Destroy() end Ga.parts, Ga.leds = {}, {} end
function Ga.build()
	Ga.destroy()
	if not Ga.cfg.on then return end
	local r = Reg.currentRig()
	if not r or not r.root then return end
	local cfg = Ga.cfg
	local fl, ul = r.fwdLocal.Unit, CFG.UP_LOCAL.Unit
	local sl = fl:Cross(ul).Unit
	local list = {}
	for _, p in ipairs(r.byCat.frame) do if p.Transparency < 0.98 then list[#list + 1] = p end end
	if #list == 0 then list = r.parts end
	local fMin, fMax, uMin, sMin, sMax = math.huge, -math.huge, math.huge, math.huge, -math.huge
	for _, p in ipairs(list) do
		local rel, h = r.root.CFrame:ToObjectSpace(p.CFrame), p.Size / 2
		for _, x in ipairs({-1, 1}) do for _, y in ipairs({-1, 1}) do for _, z in ipairs({-1, 1}) do
			local c = rel * Vector3.new(h.X * x, h.Y * y, h.Z * z)
			local f, u, s = c:Dot(fl), c:Dot(ul), c:Dot(sl)
			fMin, fMax, uMin, sMin, sMax = math.min(fMin, f), math.max(fMax, f), math.min(uMin, u), math.min(sMin, s), math.max(sMax, s)
		end end end
	end
	local width = math.min(sMax - sMin, 4)
	local mid = (sMin + sMax) / 2
	local ledSize = math.max(width * 0.11, 0.08) * cfg.size
	local fw, uw = r.root.CFrame:VectorToWorldSpace(fl), r.root.CFrame:VectorToWorldSpace(ul)
	local folder = U.fxFolder(r.model)
	for _, sg in ipairs({-1, 1}) do
		local sc = mid + sg * width / 2 * 0.92
		local wireLen = (fMax - fMin) * 0.96
		local center = fl * ((fMin + fMax) / 2) + ul * (uMin - ledSize * 0.3) + sl * sc
		local wire = U.new("Part", {Name = "GIGA_GarlandWire", Shape = Enum.PartType.Cylinder, Size = Vector3.new(wireLen, ledSize * 0.22, ledSize * 0.22), Color = RGB(15, 15, 15),
			Material = Enum.Material.SmoothPlastic, CFrame = CFrame.fromMatrix((r.root.CFrame * CFrame.new(center)).Position, fw, uw), CanCollide = false, CanQuery = false, CanTouch = false,
			CastShadow = false, Massless = true}, folder)
		U.new("WeldConstraint", {Part0 = r.root, Part1 = wire}, wire)
		Ga.parts[#Ga.parts + 1] = wire
		for i = 1, cfg.count do
			local t = (i - 1) / math.max(cfg.count - 1, 1)
			local f = fMin + (fMax - fMin) * (0.04 + 0.92 * t)
			local lp = fl * f + ul * (uMin - ledSize * 0.3 - ledSize * 0.35 * math.sin(math.pi * t)) + sl * sc
			local led = U.new("Part", {Name = "GIGA_Led", Shape = Enum.PartType.Ball, Size = Vector3.one * ledSize, Material = Enum.Material.Neon, Color = cfg.c,
				CFrame = r.root.CFrame * CFrame.new(lp), CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false, Massless = true}, folder)
			U.new("WeldConstraint", {Part0 = r.root, Part1 = led}, led)
			local light = (i % 4 == 1) and U.new("PointLight", {Color = cfg.c, Brightness = cfg.bright, Range = ledSize * 22, Shadows = false}, led) or nil
			Ga.parts[#Ga.parts + 1] = led
			Ga.leds[#Ga.leds + 1] = {p = led, l = light, i = i, n = cfg.count}
		end
	end
end
function Ga.setColor(c)
	Ga.cfg.c = c
	if Ga.cfg.mode == "Solid" then for _, e in ipairs(Ga.leds) do e.p.Color = c if e.l then e.l.Color = c end end end
end
function Ga.setBright(b) Ga.cfg.bright = b for _, e in ipairs(Ga.leds) do if e.l then e.l.Brightness = b end end end
function Ga.set(on) Ga.cfg.on = on if on then Ga.build() else Ga.destroy() end end
local gAcc = 0
Hub.addUpdater(function(dt)
	if #Ga.leds == 0 or Ga.cfg.mode == "Solid" then return end
	gAcc = gAcc + dt
	if gAcc < 0.033 then return end
	gAcc = 0
	local t, mode, base = os.clock(), Ga.cfg.mode, Ga.cfg.c
	for _, e in ipairs(Ga.leds) do
		local c
		if mode == "Rainbow" then c = HSV((t * 0.25 + e.i / e.n) % 1, 1, 1)
		elseif mode == "Chase" then c = base:Lerp(Color3.new(0, 0, 0), 1 - (math.sin(t * 4 - e.i * 0.55) * 0.5 + 0.5) ^ 2)
		else c = base:Lerp(Color3.new(0, 0, 0), 1 - (math.sin(t * 2.7 + e.i * 7.3) * 0.5 + 0.5)) end
		e.p.Color = c
		if e.l then e.l.Color = c end
	end
end)
Hub.onClean(Ga.destroy)

---------------------------------------------------------------- Realistic shader (день / ночь)
local Sh = {on = false, name = nil, saved = nil, intensity = 1, lock = nil, reflect = nil}
Hub.Shader = Sh
local SH_PROPS = {"Brightness", "ExposureCompensation", "ClockTime", "Ambient", "OutdoorAmbient", "ColorShift_Top", "ColorShift_Bottom", "EnvironmentDiffuseScale", "EnvironmentSpecularScale", "GlobalShadows", "FogColor", "FogEnd", "FogStart"}
local W3 = RGB(255, 255, 255)
Sh.presets = {
	{n = "Realistic Day", day = true, p = {Brightness = 2.4, ExposureCompensation = 0.15, Ambient = RGB(70, 75, 85), OutdoorAmbient = RGB(120, 130, 145), ColorShift_Top = RGB(255, 244, 224)},
		bloom = {0.35, 24, 1.6}, cc = {0, 0.1, 0.18, RGB(255, 250, 245)}, rays = 0.06, atm = {0.28, 0, RGB(190, 210, 235), RGB(210, 225, 245), 0.2, 0.8}},
	{n = "Golden Hour", day = true, clock = 17.4, p = {Brightness = 2.8, Ambient = RGB(90, 70, 60), OutdoorAmbient = RGB(150, 110, 90), ColorShift_Top = RGB(255, 200, 140)},
		bloom = {0.5, 28, 1.3}, cc = {0.02, 0.15, 0.3, RGB(255, 225, 190)}, rays = 0.15, atm = {0.33, 0, RGB(255, 190, 140), RGB(255, 160, 110), 0.6, 1.2}},
	{n = "Crisp Vivid", day = true, p = {Brightness = 2.2, ExposureCompensation = 0.1, Ambient = RGB(80, 85, 95), OutdoorAmbient = RGB(130, 140, 155)},
		bloom = {0.3, 22, 1.8}, cc = {0.03, 0.22, 0.42, W3}, rays = 0.05, atm = {0.15, 0, RGB(180, 205, 240), RGB(200, 220, 245), 0.1, 0.4}},
	{n = "Cinematic", day = true, p = {Brightness = 2.0, ExposureCompensation = 0, Ambient = RGB(60, 65, 75), OutdoorAmbient = RGB(105, 115, 130), ColorShift_Top = RGB(255, 235, 210)},
		bloom = {0.45, 30, 1.2}, cc = {0.05, 0.22, -0.05, RGB(235, 245, 255)}, dof = {0.25, 28, 35}, atm = {0.35, 0, RGB(170, 195, 225), RGB(200, 210, 230), 0.3, 1.0}},
	{n = "Overcast Calm", day = true, p = {Brightness = 1.6, Ambient = RGB(95, 100, 110), OutdoorAmbient = RGB(125, 130, 140)},
		bloom = {0.2, 20, 1.8}, cc = {-0.02, 0, -0.15, RGB(220, 230, 240)}, atm = {0.45, 0, RGB(170, 180, 195), RGB(190, 195, 205), 0, 1.6}},
	{n = "Realistic Night", clock = 0, lock = true, p = {Brightness = 0.9, Ambient = RGB(30, 36, 60), OutdoorAmbient = RGB(45, 55, 90), ColorShift_Top = RGB(150, 170, 255), EnvironmentSpecularScale = 0.6},
		bloom = {0.9, 30, 0.9}, cc = {0, 0.18, 0.05, RGB(200, 215, 255)}, atm = {0.32, 0, RGB(25, 35, 70), RGB(30, 40, 80), 0, 1.2}},
	{n = "Neon Night", clock = 0, lock = true, p = {Brightness = 0.8, Ambient = RGB(40, 20, 70), OutdoorAmbient = RGB(60, 30, 100), ColorShift_Top = RGB(200, 120, 255)},
		bloom = {1.4, 36, 0.7}, cc = {0.1, 0.3, 0.35, RGB(230, 200, 255)}, atm = {0.3, 0, RGB(40, 15, 70), RGB(60, 20, 90), 0, 1}},
	{n = "Moonlight", clock = 1, lock = true, p = {Brightness = 1.1, Ambient = RGB(40, 50, 75), OutdoorAmbient = RGB(70, 85, 120), ColorShift_Top = RGB(190, 210, 255)},
		bloom = {0.7, 26, 1.0}, cc = {0.02, 0.15, -0.05, RGB(205, 225, 255)}, rays = 0.03, atm = {0.25, 0, RGB(40, 55, 95), RGB(60, 80, 120), 0.3, 0.9}},
	{n = "Foggy Night", clock = 0, lock = true, p = {Brightness = 0.8, Ambient = RGB(35, 40, 55), OutdoorAmbient = RGB(55, 62, 80), FogColor = RGB(30, 34, 48), FogEnd = 420, FogStart = 20},
		bloom = {0.8, 30, 0.9}, cc = {0, 0.1, -0.1, RGB(200, 210, 235)}, atm = {0.6, 0, RGB(45, 52, 70), RGB(55, 62, 85), 0, 2.5}},
	{n = "Cyberpunk", clock = 0, lock = true, p = {Brightness = 0.9, Ambient = RGB(50, 20, 60), OutdoorAmbient = RGB(30, 60, 90), ColorShift_Top = RGB(255, 90, 200), ColorShift_Bottom = RGB(60, 200, 255)},
		bloom = {1.6, 38, 0.6}, cc = {0.12, 0.35, 0.5, RGB(255, 215, 245)}, atm = {0.28, 0, RGB(30, 20, 60), RGB(70, 30, 110), 0, 1.2}},
}
function Sh.clearFx()
	for _, n in ipairs({"GIGA_SH_Bloom", "GIGA_SH_CC", "GIGA_SH_Rays", "GIGA_SH_DoF", "GIGA_SH_Atm"}) do
		local o = Lighting:FindFirstChild(n)
		if o then o:Destroy() end
	end
	if Sh.atmSaved and Sh.atmSaved.o.Parent then
		for k, v in pairs(Sh.atmSaved.v) do pcall(function() Sh.atmSaved.o[k] = v end) end
	end
	Sh.atmSaved = nil
end
function Sh.restore()
	Sh.on, Sh.lock = false, nil
	Sh.clearFx()
	if Sh.saved then for k, v in pairs(Sh.saved) do pcall(function() Lighting[k] = v end) end Sh.saved = nil end
end
function Sh.apply(name)
	local pr
	for _, p in ipairs(Sh.presets) do if p.n == name then pr = p end end
	if not pr then return end
	if not Sh.saved then
		Sh.saved = {}
		for _, k in ipairs(SH_PROPS) do pcall(function() Sh.saved[k] = Lighting[k] end) end
	end
	Sh.clearFx()
	Sh.on, Sh.name = true, name
	local k = Sh.intensity
	for prop, v in pairs(pr.p or {}) do pcall(function() Lighting[prop] = v end) end
	if Sh.reflect then pcall(function() Lighting.EnvironmentSpecularScale = Sh.reflect end) end
	if pr.clock then Lighting.ClockTime = pr.clock end
	Sh.lock = pr.lock and (pr.clock or 0) or nil
	if pr.bloom then U.new("BloomEffect", {Name = "GIGA_SH_Bloom", Intensity = pr.bloom[1] * k, Size = pr.bloom[2], Threshold = pr.bloom[3]}, Lighting) end
	if pr.cc then U.new("ColorCorrectionEffect", {Name = "GIGA_SH_CC", Brightness = pr.cc[1], Contrast = pr.cc[2] * k, Saturation = pr.cc[3] * k, TintColor = pr.cc[4]}, Lighting) end
	if pr.rays then U.new("SunRaysEffect", {Name = "GIGA_SH_Rays", Intensity = pr.rays * k, Spread = 0.8}, Lighting) end
	if pr.dof then U.new("DepthOfFieldEffect", {Name = "GIGA_SH_DoF", FarIntensity = pr.dof[1] * k, FocusDistance = pr.dof[2], InFocusRadius = pr.dof[3], NearIntensity = 0}, Lighting) end
	if pr.atm then
		local a = Lighting:FindFirstChildOfClass("Atmosphere")
		if a then
			Sh.atmSaved = {o = a, v = {Density = a.Density, Offset = a.Offset, Color = a.Color, Decay = a.Decay, Glare = a.Glare, Haze = a.Haze}}
		else a = U.new("Atmosphere", {Name = "GIGA_SH_Atm"}, Lighting) end
		a.Density, a.Offset, a.Color, a.Decay, a.Glare, a.Haze = pr.atm[1] * k, pr.atm[2], pr.atm[3], pr.atm[4], pr.atm[5], pr.atm[6]
	end
end
function Sh.toggleFx(kind, on)
	local map = {bloom = "GIGA_SH_Bloom", rays = "GIGA_SH_Rays", dof = "GIGA_SH_DoF", cc = "GIGA_SH_CC"}
	local o = Lighting:FindFirstChild(map[kind])
	if o then o.Enabled = on end
end
Hub.addUpdater(function() if Sh.lock and math.abs(Lighting.ClockTime - Sh.lock) > 0.05 then Lighting.ClockTime = Sh.lock end end)
Hub.onClean(Sh.restore)


---------------------------------------------------------------- Avatar (Skins): стать другим игроком / свой аватар (только у тебя на экране)
local Av = {saved = Store.load("avatars", {}), custom = {acc = {}}}
Hub.Avatar = Av
local function myHum() local c = player.Character return c and c:FindFirstChildOfClass("Humanoid"), c end
function Av.thumb(id, full) return string.format("rbxthumb://type=%s&id=%d&w=%d&h=%d", full and "Avatar" or "AvatarHeadShot", id, full and 420 or 150, full and 420 or 150) end
function Av.idOf(text)
	text = tostring(text or ""):gsub("%s+", "")
	if text == "" then return nil end
	if tonumber(text) then return tonumber(text) end
	local ok, id = pcall(function() return Players:GetUserIdFromNameAsync(text) end)
	return ok and id or nil
end
local function clearLook(char)
	for _, o in ipairs(char:GetChildren()) do
		if (o:IsA("Accessory") or o:IsA("Shirt") or o:IsA("Pants") or o:IsA("ShirtGraphic") or o:IsA("CharacterMesh")) and not o:GetAttribute("GIGAH") then o:Destroy() end
	end
end
-- ok, сообщение
function Av.become(userId)
	local hum, char = myHum()
	if not hum then return false, "no character" end
	local okd, desc = pcall(function() return Players:GetHumanoidDescriptionFromUserId(userId) end)
	if okd and desc then
		local oka = pcall(function() hum:ApplyDescription(desc) end)
		if oka then Av.current, Av.custom = userId, {acc = {}} return true end
	end
	local ok, app = pcall(function() return Players:GetCharacterAppearanceAsync(userId) end)
	if not ok or not app then return false, "can't load avatar" end
	clearLook(char)
	local bc = app:FindFirstChildOfClass("BodyColors")
	if bc then
		local old = char:FindFirstChildOfClass("BodyColors")
		if old then old:Destroy() end
		bc:Clone().Parent = char
	end
	for _, o in ipairs(app:GetChildren()) do
		if o:IsA("Accessory") then hum:AddAccessory(o:Clone())
		elseif o:IsA("Shirt") or o:IsA("Pants") or o:IsA("ShirtGraphic") then o:Clone().Parent = char end
	end
	Av.current, Av.custom = userId, {acc = {}}
	return true
end
function Av.restore() return Av.become(player.UserId) end
function Av.setSkin(c)
	local _, char = myHum()
	if not char then return end
	local bc = char:FindFirstChildOfClass("BodyColors") or U.new("BodyColors", {}, char)
	bc.HeadColor3, bc.TorsoColor3, bc.LeftArmColor3, bc.RightArmColor3, bc.LeftLegColor3, bc.RightLegColor3 = c, c, c, c, c, c
	for _, p in ipairs(char:GetChildren()) do if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then p.Color = c end end
	Av.custom.skin = U.c2t(c)
end
function Av.setClothes(kind, id)
	local _, char = myHum()
	id = tonumber(id)
	if not char or not id then return false end
	local o = char:FindFirstChildOfClass(kind) or U.new(kind, {}, char)
	o[kind .. "Template"] = "rbxassetid://" .. id
	Av.custom[kind == "Shirt" and "shirt" or "pants"] = id
	return true
end
function Av.addAccessory(id, cb)
	id = tonumber(id)
	local hum = myHum()
	if not hum or not id then if cb then cb(false) end return end
	task.spawn(function()
		local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. id) end)
		local acc
		if ok and objs then for _, o in ipairs(objs) do acc = o:IsA("Accessory") and o or o:FindFirstChildWhichIsA("Accessory", true) if acc then break end end end
		if not acc then if cb then cb(false) end return end
		acc = acc:Clone()
		acc:SetAttribute("GIGAAv", true)
		hum:AddAccessory(acc)
		table.insert(Av.custom.acc, id)
		if cb then cb(true) end
	end)
end
function Av.clearAdded()
	local _, char = myHum()
	if char then for _, o in ipairs(char:GetChildren()) do if o:GetAttribute("GIGAAv") then o:Destroy() end end end
	Av.custom.acc = {}
end
function Av.hideStock(v)
	local _, char = myHum()
	if not char then return end
	for _, a in ipairs(char:GetChildren()) do
		if a:IsA("Accessory") and not a:GetAttribute("GIGAAv") and not a:GetAttribute("GIGAH") then
			local h = a:FindFirstChild("Handle")
			if h then
				if v and h.Transparency < 1 then h:SetAttribute("AvHid", h.Transparency) h.Transparency = 1
				elseif not v and h:GetAttribute("AvHid") then h.Transparency = h:GetAttribute("AvHid") h:SetAttribute("AvHid", nil) end
			end
		end
	end
end
function Av.applySaved(a)
	if a.kind == "user" then return Av.become(a.id) end
	if a.skin then Av.setSkin(U.t2c(a.skin)) end
	if a.shirt then Av.setClothes("Shirt", a.shirt) end
	if a.pants then Av.setClothes("Pants", a.pants) end
	Av.clearAdded()
	for _, id in ipairs(a.acc or {}) do Av.addAccessory(id) end
	return true
end
function Av.save(name)
	local e
	if Av.current and Av.current ~= player.UserId and not Av.custom.skin and not Av.custom.shirt and not Av.custom.pants and #Av.custom.acc == 0 then
		e = {name = name, kind = "user", id = Av.current}
	else
		e = {name = name, kind = "custom", skin = Av.custom.skin, shirt = Av.custom.shirt, pants = Av.custom.pants, acc = Av.custom.acc}
	end
	for i, a in ipairs(Av.saved) do if a.name == name then Av.saved[i] = e Store.save("avatars", Av.saved) return end end
	table.insert(Av.saved, e)
	Store.save("avatars", Av.saved)
end
function Av.delete(name)
	for i, a in ipairs(Av.saved) do if a.name == name then table.remove(Av.saved, i) break end end
	Store.save("avatars", Av.saved)
end

---------------------------------------------------------------- Custom GUI: редактор раскладки (чёрный фон + двигаемые/масштабируемые рамки)
local Lay = {data = Store.load("layout", {}), orig = {}}
Hub.Layout = Lay
Lay.targets = {
	{id = "Cash",    gui = "CashUI",         child = "Frame", en = "Cash UI",         ru = "Деньги (CashUI)"},
	{id = "Shop",    gui = "ShopUI",         en = "Shop",            ru = "Магазин (ShopUI)"},
	{id = "Quest",   gui = "QuestMenu",      en = "Quest Menu",      ru = "Квесты (QuestMenu)"},
	{id = "Vehicle", gui = "VehicleSpawner", en = "Vehicle Spawner", ru = "Спавн транспорта"},
}
-- В StarterGui лежат только шаблоны; живые копии — в PlayerGui. Работаем с PlayerGui.
function Lay.resolve(t)
	local pg = player:FindFirstChild("PlayerGui")
	local g = pg and pg:FindFirstChild(t.gui)
	if not g then return nil, nil end
	if g:IsA("GuiObject") then return g, g end
	local f = (t.child and g:FindFirstChild(t.child)) or g:FindFirstChild("Frame") or g:FindFirstChildWhichIsA("GuiObject")
	return f, g
end
function Lay.apply(t)
	local f = Lay.resolve(t)
	if not f then return false end
	local o = Lay.orig[t.id]
	if not o or o.f ~= f then o = {f = f, pos = f.Position, anchor = f.AnchorPoint} Lay.orig[t.id] = o end
	local d = Lay.data[t.id]
	local sc = f:FindFirstChild("GIGA_Scale")
	if not d then
		f.Position, f.AnchorPoint = o.pos, o.anchor
		if sc then sc.Scale = 1 end
		return true
	end
	local vp = Workspace.CurrentCamera.ViewportSize
	local par, pa = f.Parent, Vector2.zero
	if par and par:IsA("GuiObject") then pa = par.AbsolutePosition
	elseif par and par:IsA("ScreenGui") and not par.IgnoreGuiInset then pa = GuiService:GetGuiInset() end
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(d.fx * vp.X - pa.X, d.fy * vp.Y - pa.Y)
	sc = sc or U.new("UIScale", {Name = "GIGA_Scale"}, f)
	sc.Scale = d.s or 1
	return true
end
function Lay.applyAll() for _, t in ipairs(Lay.targets) do pcall(Lay.apply, t) end end
function Lay.resetAll()
	Lay.data = {}
	Lay.applyAll()
	Store.save("layout", Lay.data)
end
-- плавное уменьшение игрового UI, пока открыто меню
function Lay.shrink(on, factor)
	for _, t in ipairs(Lay.targets) do
		local f = Lay.resolve(t)
		if f then
			local s = f:FindFirstChild("GIGA_Shrink") or U.new("UIScale", {Name = "GIGA_Shrink"}, f)
			U.tween(s, 0.35, {Scale = on and (factor or 0.8) or 1}, Enum.EasingStyle.Quart)
		end
	end
end

function Lay.openEditor()
	if Lay.ed then return end
	local UI = Hub.UI
	local wasOpen = Hub.menu and Hub.menu.open
	if wasOpen then Hub.menu.hide() end
	Lay.shrink(false)
	local gui = U.new("ScreenGui", {Name = "GIGA_LAYOUT", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1001, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, U.guiParent())
	Lay.ed = gui
	local bg = U.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Active = true}, gui)
	U.tween(bg, 0.3, {BackgroundTransparency = 0.1})
	U.new("TextLabel", {Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 18), BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 22,
		Text = (Hub.lang == "ru") and "РЕДАКТОР ИНТЕРФЕЙСА — тяни рамки, тяни угол для размера" or "LAYOUT EDITOR — drag boxes, drag the corner to resize"}, bg)
	-- показать скрытые окна, чтобы измерить размеры
	local peeked = {}
	for _, t in ipairs(Lay.targets) do
		local f, g = Lay.resolve(t)
		if f then
			local p = {g = g, f = f, en = g:IsA("ScreenGui") and g.Enabled, vis = f.Visible}
			if g:IsA("ScreenGui") then g.Enabled = true end
			f.Visible = true
			peeked[t.id] = p
		end
	end
	task.wait(0.15)
	local vp = Workspace.CurrentCamera.ViewportSize
	local state = {}
	local boxes = {}
	local k = 0
	for _, t in ipairs(Lay.targets) do
		local p = peeked[t.id]
		local f = p and p.f
		local d = Lay.data[t.id]
		local s = d and d.s or 1
		local w, h, cx, cy
		if f and f.AbsoluteSize.X > 4 then
			local sc = f:FindFirstChild("GIGA_Scale")
			local cur = sc and sc.Scale or 1
			w, h = f.AbsoluteSize.X / cur, f.AbsoluteSize.Y / cur
			cx, cy = f.AbsolutePosition.X + f.AbsoluteSize.X / 2, f.AbsolutePosition.Y + f.AbsoluteSize.Y / 2
		else
			w, h, cx, cy = 260, 160, vp.X * (0.25 + 0.15 * k), vp.Y * 0.5
		end
		k = k + 1
		if d then cx, cy = d.fx * vp.X, d.fy * vp.Y end
		state[t.id] = {cx = cx, cy = cy, s = s, w = w, h = h, found = f ~= nil}
		local st = state[t.id]
		local box = U.new("Frame", {BackgroundColor3 = RGB(30, 33, 48), BackgroundTransparency = 0.15, BorderSizePixel = 0, Active = true}, bg)
		U.corner(box, 10)
		local strk = U.new("UIStroke", {Thickness = 2, Color = st.found and RGB(130, 150, 255) or RGB(255, 120, 120)}, box)
		local lab = U.new("TextLabel", {Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 8), BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 15,
			TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top}, box)
		local handle = U.new("Frame", {Size = UDim2.fromOffset(22, 22), AnchorPoint = Vector2.one, Position = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(130, 150, 255), BorderSizePixel = 0, ZIndex = 3, Active = true}, box)
		U.corner(handle, 6)
		local function refresh()
			box.Size = UDim2.fromOffset(st.w * st.s, st.h * st.s)
			box.Position = UDim2.fromOffset(st.cx - st.w * st.s / 2, st.cy - st.h * st.s / 2)
			lab.Text = ((Hub.lang == "ru") and t.ru or t.en) .. string.format("\n%d%%%s", st.s * 100, st.found and "" or "  (не найдено)")
		end
		refresh()
		boxes[t.id] = box
		box.InputBegan:Connect(function(i)
			if UI.isPress(i) then
				local m0, c0x, c0y = UIS:GetMouseLocation(), st.cx, st.cy
				UI.beginDrag(function(m)
					st.cx = math.clamp(c0x + (m.X - m0.X), 0, vp.X)
					st.cy = math.clamp(c0y + (m.Y - m0.Y), 0, vp.Y)
					refresh()
				end)
			end
		end)
		handle.InputBegan:Connect(function(i)
			if UI.isPress(i) then
				local m0, s0 = UIS:GetMouseLocation(), st.s
				UI.beginDrag(function(m)
					st.s = math.clamp(s0 + ((m.X - m0.X) / st.w + (m.Y - m0.Y) / st.h) / 2, 0.3, 2.5)
					refresh()
				end)
			end
		end)
	end
	local function close()
		for id, p in pairs(peeked) do
			if p.g:IsA("ScreenGui") and p.en == false then p.g.Enabled = false end
			if p.vis == false then p.f.Visible = false end
		end
		U.tween(bg, 0.25, {BackgroundTransparency = 1})
		task.delay(0.28, function() gui:Destroy() Lay.ed = nil end)
		if wasOpen and Hub.menu then Hub.menu.show() end
	end
	local function btn(text, x, color, cb)
		local b = U.new("TextButton", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, x, 1, -30), Size = UDim2.fromOffset(170, 44), BackgroundColor3 = color, Text = text, TextColor3 = Color3.new(1, 1, 1),
			Font = Enum.Font.GothamBold, TextSize = 14, AutoButtonColor = true, ZIndex = 5}, bg)
		U.corner(b, 12)
		b.MouseButton1Click:Connect(cb)
	end
	local ru = Hub.lang == "ru"
	btn(ru and "СОХРАНИТЬ" or "SAVE", -185, RGB(70, 120, 255), function()
		for _, t in ipairs(Lay.targets) do
			local st = state[t.id]
			if st and st.found then Lay.data[t.id] = {fx = st.cx / vp.X, fy = st.cy / vp.Y, s = st.s} end
		end
		Store.save("layout", Lay.data)
		close()
		Lay.applyAll()
	end)
	btn(ru and "СБРОСИТЬ ВСЁ" or "RESET ALL", 0, RGB(190, 90, 60), function() close() Lay.resetAll() end)
	btn(ru and "ОТМЕНА" or "CANCEL", 185, RGB(60, 64, 82), close)
end
task.delay(2, function() Lay.applyAll() end)
Hub.onClean(function() if Lay.ed then Lay.ed:Destroy() end end)

---------------------------------------------------------------- skins
local Sk = {user = Store.load("skins", {}), builtin = {}, classic = {}}
Hub.Skins = Sk
local function T3(r, g, b) return {r, g, b} end
local function mk(name, main, acc, glow, trail, opts)
	opts = opts or {}
	local m = opts.mat
	local cat = {
		frame = {c = main, m = m}, battery = {c = main}, motor = {c = main}, other = {c = main},
		wheels = {c = opts.wheel or T3(18, 18, 20)},
		handlebar = {c = acc, m = m}, stem = {c = acc, m = m}, suspension = {c = acc, m = m}, grips = {c = opts.grips or T3(15, 15, 15)},
		wheelie = {c = acc}, brakes = {c = acc},
	}
	return {name = name, cat = cat, slot = {}, glow = glow and {on = true, c = glow} or {on = false}, trail = trail and {on = true, c = trail} or {on = false},
		smoke = {}, wheelGlow = opts.wg and {on = true, c = opts.wg} or {on = false}, rainbow = opts.rainbow or {}}
end
Sk.builtin = {
	{name = "Rainbow Kugoo", rainbow = {all = true}, cat = {}, slot = {}, glow = {on = true, c = T3(255, 0, 0)}, trail = {on = true, c = T3(255, 255, 255)},
		smoke = {own = true}, wheelGlow = {on = true, c = T3(0, 255, 255)}, tag = "RAINBOW"},
	mk("Aurora", T3(10, 38, 44), T3(120, 255, 210), T3(60, 255, 190), T3(120, 200, 255), {wg = T3(60, 255, 190)}),
	mk("Cyber Neon", T3(12, 12, 18), T3(0, 255, 255), T3(0, 255, 255), T3(255, 0, 200), {wg = T3(255, 0, 200)}),
	mk("Blood Moon", T3(22, 0, 4), T3(255, 10, 40), T3(255, 0, 30), T3(255, 80, 0)),
	mk("Gold Luxury", T3(14, 14, 14), T3(255, 196, 58), T3(255, 170, 40), T3(255, 215, 90), {mat = Enum.Material.Metal.Name}),
	mk("Ghost", T3(235, 245, 255), T3(150, 200, 255), T3(150, 210, 255), T3(220, 240, 255)),
	mk("Toxic", T3(14, 20, 14), T3(57, 255, 20), T3(57, 255, 20), T3(57, 255, 20), {wg = T3(57, 255, 20)}),
	mk("Vaporwave", T3(28, 10, 60), T3(255, 70, 190), T3(255, 70, 190), T3(0, 240, 255), {wg = T3(0, 240, 255)}),
	mk("Sunset", T3(24, 8, 28), T3(255, 115, 0), T3(255, 95, 0), T3(255, 210, 0)),
	mk("Galaxy", T3(8, 4, 36), T3(140, 80, 255), T3(130, 0, 255), T3(0, 200, 255), {wg = T3(140, 80, 255)}),
	mk("Stealth", T3(10, 10, 10), T3(40, 40, 44), nil, nil),
	mk("Midnight", T3(10, 12, 30), T3(90, 120, 255), T3(90, 120, 255), T3(160, 180, 255)),
	mk("Snow", T3(240, 244, 250), T3(120, 170, 230), T3(160, 200, 255), T3(230, 240, 255)),
	mk("Candy", T3(255, 150, 200), T3(120, 230, 255), T3(255, 120, 190), T3(120, 230, 255)),
	mk("Lava", T3(20, 8, 6), T3(255, 90, 20), T3(255, 70, 0), T3(255, 170, 40), {wg = T3(255, 90, 20)}),
	mk("Ocean", T3(6, 30, 50), T3(0, 200, 230), T3(0, 190, 255), T3(120, 240, 255)),
	mk("Forest", T3(12, 28, 16), T3(90, 220, 110), T3(70, 255, 120), T3(150, 255, 170)),
	mk("Sakura", T3(250, 225, 235), T3(255, 120, 170), T3(255, 140, 190), T3(255, 200, 225)),
	mk("Carbon Orange", T3(20, 20, 22), T3(255, 120, 0), T3(255, 120, 0), T3(255, 190, 90)),
	mk("Titanium", T3(120, 125, 135), T3(220, 225, 235), nil, nil, {mat = Enum.Material.Metal.Name}),
	mk("Cyber Yellow", T3(14, 14, 14), T3(255, 230, 0), T3(255, 230, 0), T3(255, 255, 140)),
	mk("Racing", T3(240, 240, 245), T3(220, 20, 30), T3(255, 30, 40), T3(255, 120, 120)),
	mk("Lime Rush", T3(16, 16, 18), T3(170, 255, 0), T3(170, 255, 0), T3(210, 255, 120), {wg = T3(170, 255, 0)}),
	mk("Violet Haze", T3(30, 12, 50), T3(200, 120, 255), T3(190, 100, 255), T3(230, 180, 255)),
	mk("Mint", T3(230, 250, 242), T3(60, 210, 170), T3(80, 230, 190), T3(180, 255, 230)),
	mk("Copper", T3(28, 18, 14), T3(210, 120, 70), T3(255, 150, 80), T3(255, 200, 150), {mat = Enum.Material.Metal.Name}),
	mk("Royal Blue", T3(10, 20, 60), T3(240, 200, 60), T3(60, 110, 255), T3(240, 200, 60)),
	mk("Black & White", T3(14, 14, 16), T3(245, 245, 248), nil, nil),
	mk("White & Black", T3(245, 245, 248), T3(14, 14, 16), nil, nil),
}
local function solid(name, main, wheel, acc)
	local s = mk(name, main, acc or main, nil, nil, {wheel = wheel})
	return s
end
Sk.classic = {
	{id = "default", en = "Default", ru = "По умолчанию"},
	{id = "white", en = "Full White", ru = "Полностью белый", skin = solid("Full White", T3(255, 255, 255), T3(0, 0, 0))},
	{id = "black", en = "Full Black", ru = "Полностью чёрный", skin = solid("Full Black", T3(0, 0, 0), T3(0, 0, 0))},
	{id = "bpink", en = "Black + Pink", ru = "Чёрный + розовый", skin = solid("Black + Pink", T3(0, 0, 0), T3(0, 0, 0), T3(255, 20, 147))},
	{id = "red", en = "Full Red", ru = "Полностью красный", skin = solid("Full Red", T3(150, 25, 25), T3(0, 0, 0))},
	{id = "blue", en = "Full Blue", ru = "Полностью синий", skin = solid("Full Blue", T3(137, 207, 240), T3(0, 0, 0))},
	{id = "borange", en = "Black + Orange", ru = "Чёрный + оранжевый", skin = solid("Black + Orange", T3(0, 0, 0), T3(0, 0, 0), T3(255, 120, 0))},
	{id = "bred", en = "Black + Red", ru = "Чёрный + красный", skin = solid("Black + Red", T3(0, 0, 0), T3(0, 0, 0), T3(220, 20, 30))},
	{id = "bgold", en = "Black + Gold", ru = "Чёрный + золото", skin = solid("Black + Gold", T3(0, 0, 0), T3(0, 0, 0), T3(255, 196, 58))},
	{id = "wblue", en = "White + Blue", ru = "Белый + синий", skin = solid("White + Blue", T3(255, 255, 255), T3(0, 0, 0), T3(0, 110, 255))},
	{id = "pink", en = "Full Pink", ru = "Полностью розовый", skin = solid("Full Pink", T3(255, 120, 190), T3(0, 0, 0))},
	{id = "purple", en = "Full Purple", ru = "Полностью фиолетовый", skin = solid("Full Purple", T3(140, 60, 255), T3(0, 0, 0))},
	{id = "green", en = "Full Green", ru = "Полностью зелёный", skin = solid("Full Green", T3(40, 190, 90), T3(0, 0, 0))},
}
-- Random: красивые сочетания (чёрный/белый + акцент)
function Sk.random()
	local rnd = math.random
	local H = rnd()
	local function hv(h, sat, val) return U.c2t(HSV(h % 1, sat, val)) end
	local black, white, dark, light = T3(14, 14, 16), T3(245, 245, 248), T3(42, 44, 50), T3(205, 208, 215)
	local style = rnd(1, 5)
	local base, acc, acc2
	if style == 1 then base, acc, acc2 = black, white, light
	elseif style == 2 then base, acc, acc2 = white, black, dark
	elseif style == 3 then base, acc, acc2 = black, hv(H, 0.9, 1), white
	elseif style == 4 then base, acc, acc2 = white, hv(H, 0.85, 1), black
	else base, acc, acc2 = dark, hv(H, 0.85, 1), hv(H + 0.5, 0.8, 1) end
	local glow = rnd() < 0.7 and acc or nil
	local skin = mk("Random " .. rnd(100, 999), base, acc, glow, rnd() < 0.5 and acc or nil, {wg = (rnd() < 0.3) and acc or nil})
	skin.cat.suspension = {c = acc2}
	skin.cat.grips = {c = (style == 2 or style == 4) and black or white}
	skin.cat.wheelie = {c = acc2}
	return skin
end

function Sk.capture(name)
	local look = Hub.look
	local s = {name = name, cat = {}, slot = {}, rainbow = {}, smoke = {}}
	for k, v in pairs(look.cat) do s.cat[k] = {c = U.c2t(v.c), m = v.m and v.m.Name or nil} end
	for k, v in pairs(look.slot) do
		local e = {c = v.c and U.c2t(v.c) or nil, m = v.m and v.m.Name or nil, h = v.h or nil}
		if v.tex then e.tex = {url = v.tex.url, face = v.tex.face, mode = v.tex.mode, cols = v.tex.cols, rows = v.tex.rows, fps = v.tex.fps} end
		s.slot[k] = e
	end
	for k, v in pairs(look.rainbow) do s.rainbow[k] = v end
	s.hide = {}
	for k, v in pairs(look.hide) do s.hide[k] = v end
	s.glow = {on = look.glow.on, c = U.c2t(look.glow.c)}
	s.trail = {on = look.trail.on, c = U.c2t(look.trail.c)}
	s.wheelGlow = {on = look.wheelGlow.on, c = U.c2t(look.wheelGlow.c)}
	s.smoke = {own = look.smoke.own, c = look.smoke.c and U.c2t(look.smoke.c) or nil}
	return s
end
local function mat(n) if not n then return nil end local ok, m = pcall(function() return Enum.Material[n] end) return ok and m or nil end
function Sk.apply(s)
	local look = Hub.look
	Paint.reset()
	look.cat, look.slot, look.rainbow, look.hide = {}, {}, {}, {}
	for k, v in pairs(s.hide or {}) do look.hide[k] = v end
	for k, v in pairs(s.cat or {}) do look.cat[k] = {c = U.t2c(v.c), m = mat(v.m)} end
	local texJobs = {}
	for k, v in pairs(s.slot or {}) do
		look.slot[k] = {c = v.c and U.t2c(v.c) or nil, m = mat(v.m), h = v.h}
		if v.tex then table.insert(texJobs, {k, v.tex}) end
	end
	for k, v in pairs(s.rainbow or {}) do look.rainbow[k] = v end
	if look.rainbow.all then -- Rainbow Kugoo: радуга ТОЛЬКО на красках-акцентах, руле, грипсах, вилли-баре и эффектах (не на всём самокате)
		look.rainbow = {paint = true, handlebar = true, grips = true, wheelie = true, glow = true, trail = true, smoke = true, wheelglow = true, lights = true}
	end
	local g = s.glow or {on = false}
	look.glow.on = g.on and true or false
	if g.c then look.glow.c = U.t2c(g.c) end
	local t = s.trail or {on = false}
	look.trail.on = t.on and true or false
	if t.c then look.trail.c = U.t2c(t.c) end
	local w = s.wheelGlow or {on = false}
	look.wheelGlow.on = w.on and true or false
	if w.c then look.wheelGlow.c = U.t2c(w.c) end
	local sm = s.smoke or {}
	look.smoke.own, look.smoke.c = sm.own and true or false, sm.c and U.t2c(sm.c) or nil
	if not look.rainbow.smoke then S.restoreGame() end
	if not look.rainbow.lights then Fx.restoreLights() end
	Paint.refresh()
	Fx.rebuildAll()
	for _, j in ipairs(texJobs) do Tex.setSlot(j[1], j[2]) end
	if Hub.syncUI then Hub.syncUI() end
end
function Sk.saveUser(skin)
	for i, s in ipairs(Sk.user) do if s.name == skin.name then Sk.user[i] = skin Store.save("skins", Sk.user) return end end
	table.insert(Sk.user, skin)
	Store.save("skins", Sk.user)
end
function Sk.delete(name)
	for i, s in ipairs(Sk.user) do if s.name == name then table.remove(Sk.user, i) break end end
	Store.save("skins", Sk.user)
end
function Sk.swatches(s)
	local out = {}
	local c = s.cat or {}
	local function add(t) if t then table.insert(out, U.t2c(t)) end end
	if s.rainbow and s.rainbow.all then return {RGB(255, 0, 0), RGB(255, 200, 0), RGB(0, 255, 90), RGB(0, 160, 255), RGB(190, 0, 255)} end
	add(c.frame and c.frame.c) add(c.wheels and c.wheels.c) add(c.handlebar and c.handlebar.c)
	if s.glow and s.glow.on then add(s.glow.c) end
	if s.trail and s.trail.on then add(s.trail.c) end
	if #out == 0 then for _, v in pairs(s.slot or {}) do if v.c then add(v.c) end if #out >= 4 then break end end end
	return out
end
function Sk.applyClassic(c)
	if c.id == "default" then
		Paint.reset() Hub.look.glow.on, Hub.look.trail.on = false, false
		Hub.look.smoke.own, Hub.look.wheelGlow.on = false, false
		S.restoreGame() Fx.restoreLights() Fx.rebuildAll()
		if Hub.syncUI then Hub.syncUI() end
	else
		Sk.apply(c.skin)
	end
end


-- Cloud Key: пресет <-> текстовый ключ (делись ключом с друзьями)
local B64C = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64R = {}
for i = 1, 64 do B64R[B64C:sub(i, i)] = i - 1 end
local function b64e(data)
	local out = {}
	for i = 1, #data, 3 do
		local a, b, c = data:byte(i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1, c2, c3, c4 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
		out[#out + 1] = B64C:sub(c1 + 1, c1 + 1) .. B64C:sub(c2 + 1, c2 + 1) .. (b and B64C:sub(c3 + 1, c3 + 1) or "=") .. (c and B64C:sub(c4 + 1, c4 + 1) or "=")
	end
	return table.concat(out)
end
local function b64d(s)
	s = s:gsub("[^%w%+/=]", "")
	local out = {}
	for i = 1, #s, 4 do
		local a, b, c, d = s:sub(i, i), s:sub(i + 1, i + 1), s:sub(i + 2, i + 2), s:sub(i + 3, i + 3)
		local n = (B64R[a] or 0) * 262144 + (B64R[b] or 0) * 4096 + (B64R[c] or 0) * 64 + (B64R[d] or 0)
		out[#out + 1] = string.char(math.floor(n / 65536) % 256)
		if c ~= "=" and c ~= "" then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
		if d ~= "=" and d ~= "" then out[#out + 1] = string.char(n % 256) end
	end
	return table.concat(out)
end
function Sk.toKey(skin)
	local ok, json = pcall(function() return HttpService:JSONEncode(skin) end)
	return ok and ("CK1:" .. b64e(json)) or nil
end
function Sk.fromKey(key)
	key = tostring(key or ""):gsub("%s+", "")
	if key:sub(1, 4) ~= "CK1:" then return nil end
	local ok, t = pcall(function() return HttpService:JSONDecode(b64d(key:sub(5))) end)
	if ok and type(t) == "table" and (t.cat or t.slot) then return t end
	return nil
end

---------------------------------------------------------------- UI kit
local UI = {reg = {}, tr = {}, acc = {c1 = RGB(255, 255, 255), c2 = RGB(255, 255, 255), txt = RGB(0, 0, 0)}, counters = setmetatable({}, {__mode = "k"})}
Hub.UI = UI
UI.themes = {
	Dark = {bg = RGB(15, 16, 21), side = RGB(11, 12, 16), el = RGB(25, 27, 35), elh = RGB(38, 41, 52), stroke = RGB(50, 54, 68), text = RGB(240, 242, 248), sub = RGB(125, 130, 148)},
	Light = {bg = RGB(245, 246, 251), side = RGB(232, 234, 241), el = RGB(255, 255, 255), elh = RGB(226, 229, 238), stroke = RGB(205, 208, 220), text = RGB(20, 22, 28), sub = RGB(110, 114, 126)},
}
UI.themeName = "Dark"
local TH = UI.themes.Dark
local function themeVal(key)
	if key == "acc" then return UI.acc.c1 elseif key == "acc2" then return UI.acc.c2 elseif key == "accText" then return UI.acc.txt end
	return TH[key]
end
function UI.r(inst, prop, key)
	table.insert(UI.reg, {inst, prop, key})
	inst[prop] = themeVal(key)
	return inst
end
function UI.retheme()
	TH = UI.themes[UI.themeName]
	local alive = {}
	for _, e in ipairs(UI.reg) do
		if e[1].Parent or e[1] == UI.gui then e[1][e[2]] = themeVal(e[3]) table.insert(alive, e) end
	end
	UI.reg = alive
end
function UI.setAccent(c1, c2)
	UI.acc.c1, UI.acc.c2 = c1, c2 or c1
	UI.acc.txt = (c1.R * 0.299 + c1.G * 0.587 + c1.B * 0.114) > 0.6 and RGB(0, 0, 0) or RGB(255, 255, 255)
	UI.retheme()
end
function UI.setTheme(name) UI.themeName = name UI.retheme() end
function UI.tx(inst, en, ru)
	inst.Text = (Hub.lang == "ru" and ru) or en
	table.insert(UI.tr, {inst, en, ru or en})
	return inst
end
function UI.setLang(l)
	Hub.lang = l
	local alive = {}
	for _, e in ipairs(UI.tr) do if e[1].Parent then e[1].Text = (l == "ru" and e[3]) or e[2] table.insert(alive, e) end end
	UI.tr = alive
end
function UI.order(parent) UI.counters[parent] = (UI.counters[parent] or 0) + 1 return UI.counters[parent] end

function UI.init()
	if UI.gui then UI.gui:Destroy() end
	UI.gui = U.new("ScreenGui", {Name = "GIGAHUB", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 999, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, U.guiParent())
	UI.layer = UI.gui
	Hub.onClean(function() if UI.gui then UI.gui:Destroy() end end)
	U.connect(UIS.InputChanged, function(i)
		if UI.dragFn and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then UI.dragFn(UIS:GetMouseLocation()) end
	end)
	U.connect(UIS.InputEnded, function(i)
		if UI.dragFn and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch) then UI.dragFn = nil end
	end)
end
function UI.beginDrag(fn) UI.dragFn = fn fn(UIS:GetMouseLocation()) end
local function isPress(i) return i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch end
UI.isPress = isPress

function UI.makeDraggable(frame, handle)
	handle.InputBegan:Connect(function(i)
		if isPress(i) then
			local m0, p0 = UIS:GetMouseLocation(), frame.Position
			UI.dragFn = function(m) frame.Position = UDim2.new(p0.X.Scale, p0.X.Offset + (m.X - m0.X), p0.Y.Scale, p0.Y.Offset + (m.Y - m0.Y)) end
		end
	end)
end

function UI.toast(msg, kind)
	if not UI.gui then return end
	local t = U.new("TextLabel", {AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 20), Size = UDim2.fromOffset(0, 34), AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = RGB(18, 19, 25), Text = "   " .. msg .. "   ", TextColor3 = kind == "bad" and RGB(255, 120, 120) or RGB(235, 240, 255), Font = Enum.Font.GothamMedium, TextSize = 13, ZIndex = 200}, UI.gui)
	U.corner(t, 10)
	U.new("UIStroke", {Color = kind == "bad" and RGB(255, 90, 90) or UI.acc.c1, Thickness = 1.2, Transparency = 0.3}, t)
	U.tween(t, 0.35, {Position = UDim2.new(0.5, 0, 1, -40)}, Enum.EasingStyle.Back)
	task.delay(2.6, function()
		U.tween(t, 0.3, {Position = UDim2.new(0.5, 0, 1, 30), TextTransparency = 1, BackgroundTransparency = 1})
		task.delay(0.35, function() t:Destroy() end)
	end)
end

---- базовые элементы
function UI.row(parent, h)
	local r = U.new("Frame", {Size = UDim2.new(1, 0, 0, h or 42), BorderSizePixel = 0, LayoutOrder = UI.order(parent)}, parent)
	UI.r(r, "BackgroundColor3", "el")
	U.corner(r, 10)
	local s = U.new("UIStroke", {Thickness = 1, Transparency = 0.55}, r)
	UI.r(s, "Color", "stroke")
	return r
end
function UI.label(parent, en, ru, props)
	local l = U.new("TextLabel", {BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -90, 1, 0), Position = UDim2.fromOffset(16, 0)}, parent)
	for k, v in pairs(props or {}) do l[k] = v end
	UI.r(l, "TextColor3", (props and props.sub) and "sub" or "text")
	UI.tx(l, en, ru)
	return l
end
function UI.section(parent, en, ru)
	local l = U.new("TextLabel", {Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = UI.order(parent)}, parent)
	UI.r(l, "TextColor3", "sub")
	UI.tx(l, en, ru)
	return l
end
function UI.divider(parent)
	local d = U.new("Frame", {Size = UDim2.new(1, 0, 0, 1), BorderSizePixel = 0, BackgroundTransparency = 0.5, LayoutOrder = UI.order(parent)}, parent)
	UI.r(d, "BackgroundColor3", "stroke")
	return d
end
function UI.button(parent, en, ru, cb, h)
	local b = U.new("TextButton", {Size = UDim2.new(1, 0, 0, h or 42), BorderSizePixel = 0, AutoButtonColor = false, Font = Enum.Font.GothamMedium, TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = UI.order(parent)}, parent)
	UI.r(b, "BackgroundColor3", "el")
	UI.r(b, "TextColor3", "text")
	UI.tx(b, en, ru)
	U.corner(b, 10)
	U.new("UIPadding", {PaddingLeft = UDim.new(0, 16)}, b)
	local st = U.new("UIStroke", {Thickness = 1, Transparency = 0.55}, b)
	UI.r(st, "Color", "stroke")
	local line = U.new("Frame", {Size = UDim2.fromOffset(3, 0), Position = UDim2.new(0, -16, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BorderSizePixel = 0}, b)
	UI.r(line, "BackgroundColor3", "acc")
	U.corner(line, 2)
	b.MouseEnter:Connect(function()
		U.tween(b, 0.15, {BackgroundColor3 = TH.elh})
		U.tween(st, 0.15, {Transparency = 0.1})
		U.tween(line, 0.2, {Size = UDim2.fromOffset(3, 20)})
	end)
	b.MouseLeave:Connect(function()
		U.tween(b, 0.15, {BackgroundColor3 = TH.el})
		U.tween(st, 0.15, {Transparency = 0.55})
		U.tween(line, 0.2, {Size = UDim2.fromOffset(3, 0)})
	end)
	b.MouseButton1Down:Connect(function() U.tween(b, 0.06, {Size = UDim2.new(0.98, 0, 0, (h or 42) - 2)}) end)
	b.MouseButton1Up:Connect(function() U.tween(b, 0.18, {Size = UDim2.new(1, 0, 0, h or 42)}, Enum.EasingStyle.Back) end)
	if cb then b.MouseButton1Click:Connect(cb) end
	return b
end
function UI.switch(parent, initial, cb)
	local state = initial and true or false
	local tr = U.new("TextButton", {Size = UDim2.fromOffset(42, 22), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Text = "", AutoButtonColor = false, BorderSizePixel = 0}, parent)
	U.corner(tr, 11)
	local kn = U.new("Frame", {Size = UDim2.fromOffset(16, 16), BorderSizePixel = 0}, tr)
	U.corner(kn, 8)
	local function render(anim)
		local col = state and UI.acc.c1 or TH.elh
		local kcol = state and UI.acc.txt or TH.text
		local pos = state and UDim2.new(1, -19, 0.5, -8) or UDim2.new(0, 3, 0.5, -8)
		if anim then
			U.tween(tr, 0.22, {BackgroundColor3 = col})
			U.tween(kn, 0.22, {Position = pos, BackgroundColor3 = kcol}, Enum.EasingStyle.Back)
		else tr.BackgroundColor3, kn.Position, kn.BackgroundColor3 = col, pos, kcol end
	end
	render(false)
	UI.switches = UI.switches or {}
	table.insert(UI.switches, {tr = tr, render = render})
	tr.MouseButton1Click:Connect(function() state = not state render(true) if cb then cb(state) end end)
	return {set = function(v) state = v and true or false render(true) end, get = function() return state end}
end
local oldRetheme = UI.retheme
function UI.retheme()
	oldRetheme()
	local alive = {}
	for _, s in ipairs(UI.switches or {}) do if s.tr.Parent then s.render(false) table.insert(alive, s) end end
	UI.switches = alive
	if Hub.menu and Hub.menu.cur then Hub.menu.select(Hub.menu.cur, true) end
end
function UI.toggle(parent, en, ru, default, cb)
	local r = UI.row(parent)
	UI.label(r, en, ru)
	return UI.switch(r, default, cb), r
end
function UI.slider(parent, en, ru, min, max, default, step, fmt, cb)
	local r = UI.row(parent, 54)
	UI.label(r, en, ru, {Size = UDim2.new(1, -90, 0, 28), Position = UDim2.fromOffset(16, 2)})
	local val = U.new("TextLabel", {Size = UDim2.fromOffset(70, 28), Position = UDim2.new(1, -86, 0, 2), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right}, r)
	UI.r(val, "TextColor3", "sub")
	local bar = U.new("TextButton", {Size = UDim2.new(1, -32, 0, 6), Position = UDim2.new(0, 16, 1, -18), Text = "", AutoButtonColor = false, BorderSizePixel = 0}, r)
	UI.r(bar, "BackgroundColor3", "elh")
	U.corner(bar, 3)
	local fill = U.new("Frame", {Size = UDim2.fromScale(0, 1), BorderSizePixel = 0}, bar)
	UI.r(fill, "BackgroundColor3", "acc")
	U.corner(fill, 3)
	local knob = U.new("Frame", {Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), BorderSizePixel = 0, ZIndex = 2}, bar)
	UI.r(knob, "BackgroundColor3", "text")
	U.corner(knob, 7)
	local function vis(v)
		local a = math.clamp((v - min) / (max - min), 0, 1)
		fill.Size, knob.Position = UDim2.fromScale(a, 1), UDim2.fromScale(a, 0.5)
		val.Text = string.format(fmt or "%.0f", v)
	end
	vis(default)
	bar.InputBegan:Connect(function(i)
		if isPress(i) then
			UI.beginDrag(function(m)
				local a = math.clamp((m.X - bar.AbsolutePosition.X) / math.max(bar.AbsoluteSize.X, 1), 0, 1)
				local v = min + a * (max - min)
				if step and step > 0 then v = math.floor(v / step + 0.5) * step end
				v = math.clamp(v, min, max)
				vis(v)
				cb(v)
			end)
		end
	end)
	return {set = vis}, r
end
function UI.cycle(parent, en, ru, options, default, cb)
	local r = UI.row(parent)
	UI.label(r, en, ru, {Size = UDim2.new(1, -170, 1, 0)})
	local idx = 1
	for i, o in ipairs(options) do if o.v == default then idx = i end end
	local b = U.new("TextButton", {Size = UDim2.fromOffset(130, 26), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), AutoButtonColor = false, Font = Enum.Font.GothamBold, TextSize = 12, BorderSizePixel = 0}, r)
	UI.r(b, "BackgroundColor3", "elh")
	UI.r(b, "TextColor3", "text")
	U.corner(b, 8)
	local function render() local o = options[idx] b.Text = (Hub.lang == "ru" and o.ru) or o.en or tostring(o.v) end
	render()
	b.MouseButton1Click:Connect(function() idx = idx % #options + 1 render() cb(options[idx].v) end)
	return {set = function(v) for i, o in ipairs(options) do if o.v == v then idx = i end end render() end}, r
end
function UI.input(parent, en, ru, placeholder, cb, default)
	local r = UI.row(parent)
	UI.label(r, en, ru, {Size = UDim2.new(0, 110, 1, 0)})
	local tb = U.new("TextBox", {Size = UDim2.new(1, -140, 0, 28), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Text = default or "", PlaceholderText = placeholder or "",
		ClearTextOnFocus = false, Font = Enum.Font.Gotham, TextSize = 12, BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left}, r)
	UI.r(tb, "BackgroundColor3", "elh")
	UI.r(tb, "TextColor3", "text")
	U.corner(tb, 8)
	U.new("UIPadding", {PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10)}, tb)
	tb.FocusLost:Connect(function(enter) cb(tb.Text, enter) end)
	return tb, r
end

---- цветовой пикер (HSV квадрат + hue + HEX + палитра + недавние)
Hub.recent = {}
local PALETTE = {RGB(255, 255, 255), RGB(200, 200, 205), RGB(140, 140, 150), RGB(80, 80, 88), RGB(35, 35, 40), RGB(0, 0, 0),
	RGB(255, 0, 0), RGB(255, 100, 0), RGB(255, 200, 0), RGB(255, 255, 0), RGB(150, 255, 0), RGB(0, 255, 60),
	RGB(0, 255, 200), RGB(0, 200, 255), RGB(0, 110, 255), RGB(70, 60, 255), RGB(170, 0, 255), RGB(255, 0, 220),
	RGB(255, 20, 147), RGB(150, 25, 25), RGB(137, 207, 240), RGB(90, 50, 20), RGB(255, 215, 0), RGB(0, 90, 60)}
function UI.pickColor(initial, cb, title)
	if UI.picker then UI.picker:Destroy() UI.picker = nil end
	local h, s, v = initial:ToHSV()
	local pk = U.new("Frame", {Size = UDim2.fromOffset(300, 392), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 40, 0.5, 0), BorderSizePixel = 0, ZIndex = 100, Active = true}, UI.gui)
	UI.r(pk, "BackgroundColor3", "bg")
	U.corner(pk, 14)
	local ps = U.new("UIStroke", {Thickness = 1.5}, pk)
	UI.r(ps, "Color", "acc")
	UI.picker = pk
	local head = U.new("Frame", {Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Active = true}, pk)
	UI.makeDraggable(pk, head)
	local tl = U.new("TextLabel", {Size = UDim2.new(1, -60, 1, 0), Position = UDim2.fromOffset(16, 0), BackgroundTransparency = 1, Text = title or "Color", Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left}, head)
	UI.r(tl, "TextColor3", "text")
	local x = U.new("TextButton", {Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, -36, 0, 5), BackgroundColor3 = RGB(190, 45, 45), Text = "×", TextColor3 = RGB(255, 255, 255), Font = Enum.Font.GothamBold, TextSize = 16, AutoButtonColor = true}, head)
	U.corner(x, 8)
	x.MouseButton1Click:Connect(function() pk:Destroy() UI.picker = nil end)

	local sv = U.new("TextButton", {Size = UDim2.new(1, -32, 0, 150), Position = UDim2.fromOffset(16, 44), Text = "", AutoButtonColor = false, BorderSizePixel = 0, ClipsDescendants = true}, pk)
	U.corner(sv, 8)
	local wf = U.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(255, 255, 255), BorderSizePixel = 0}, sv)
	U.new("UIGradient", {Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1)})}, wf)
	local bf = U.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(0, 0, 0), BorderSizePixel = 0}, sv)
	U.new("UIGradient", {Rotation = 90, Transparency = NumberSequence.new({NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0)})}, bf)
	local cur = U.new("Frame", {Size = UDim2.fromOffset(14, 14), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 3}, sv)
	U.corner(cur, 7)
	U.new("UIStroke", {Color = RGB(255, 255, 255), Thickness = 2}, cur)

	local hb = U.new("TextButton", {Size = UDim2.new(1, -32, 0, 14), Position = UDim2.fromOffset(16, 204), Text = "", AutoButtonColor = false, BorderSizePixel = 0}, pk)
	U.corner(hb, 7)
	local kp = {}
	for i = 0, 6 do kp[#kp + 1] = ColorSequenceKeypoint.new(i / 6, HSV(i / 6, 1, 1)) end
	U.new("UIGradient", {Color = ColorSequence.new(kp)}, hb)
	local hk = U.new("Frame", {Size = UDim2.fromOffset(6, 20), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5), BackgroundColor3 = RGB(255, 255, 255), BorderSizePixel = 0, ZIndex = 3}, hb)
	U.corner(hk, 3)
	U.new("UIStroke", {Color = RGB(0, 0, 0), Thickness = 1, Transparency = 0.5}, hk)

	local prev = U.new("Frame", {Size = UDim2.fromOffset(46, 28), Position = UDim2.fromOffset(16, 230), BorderSizePixel = 0}, pk)
	U.corner(prev, 8)
	local hex = U.new("TextBox", {Size = UDim2.fromOffset(100, 28), Position = UDim2.fromOffset(70, 230), Font = Enum.Font.GothamBold, TextSize = 13, ClearTextOnFocus = false, BorderSizePixel = 0}, pk)
	UI.r(hex, "BackgroundColor3", "el")
	UI.r(hex, "TextColor3", "text")
	U.corner(hex, 8)
	local rgbl = U.new("TextLabel", {Size = UDim2.fromOffset(100, 28), Position = UDim2.fromOffset(184, 230), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right}, pk)
	UI.r(rgbl, "TextColor3", "sub")

	local function render(skipHex)
		local c = HSV(h, s, v)
		wf.Parent.BackgroundColor3 = HSV(h, 1, 1)
		cur.Position = UDim2.fromScale(s, 1 - v)
		hk.Position = UDim2.fromScale(h, 0.5)
		prev.BackgroundColor3 = c
		if not skipHex then hex.Text = U.hex(c) end
		local t = U.c2t(c)
		rgbl.Text = string.format("R %d  G %d  B %d", t[1], t[2], t[3])
		return c
	end
	local function commit(c) cb(c) end
	local function pushRecent(c)
		local hx = U.hex(c)
		for i, e in ipairs(Hub.recent) do if U.hex(e) == hx then table.remove(Hub.recent, i) break end end
		table.insert(Hub.recent, 1, c)
		while #Hub.recent > 12 do table.remove(Hub.recent) end
	end
	render()
	sv.InputBegan:Connect(function(i)
		if isPress(i) then
			UI.beginDrag(function(m)
				s = math.clamp((m.X - sv.AbsolutePosition.X) / sv.AbsoluteSize.X, 0, 1)
				v = 1 - math.clamp((m.Y - sv.AbsolutePosition.Y) / sv.AbsoluteSize.Y, 0, 1)
				commit(render())
			end)
		end
	end)
	hb.InputBegan:Connect(function(i)
		if isPress(i) then
			UI.beginDrag(function(m)
				h = math.clamp((m.X - hb.AbsolutePosition.X) / hb.AbsoluteSize.X, 0, 0.999)
				commit(render())
			end)
		end
	end)
	hex.FocusLost:Connect(function()
		local c = U.fromHex(hex.Text)
		if c then h, s, v = c:ToHSV() commit(render()) pushRecent(c) else render() end
	end)
	local function swatches(list, y, label)
		local lb = U.new("TextLabel", {Size = UDim2.new(1, -32, 0, 14), Position = UDim2.fromOffset(16, y), BackgroundTransparency = 1, Text = label, Font = Enum.Font.GothamBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left}, pk)
		UI.r(lb, "TextColor3", "sub")
		for i, c in ipairs(list) do
			local col, row = (i - 1) % 12, math.floor((i - 1) / 12)
			local b = U.new("TextButton", {Size = UDim2.fromOffset(18, 18), Position = UDim2.fromOffset(16 + col * 22, y + 16 + row * 22), BackgroundColor3 = c, Text = "", AutoButtonColor = false, BorderSizePixel = 0}, pk)
			U.corner(b, 5)
			U.new("UIStroke", {Color = RGB(128, 128, 128), Transparency = 0.7}, b)
			b.MouseButton1Click:Connect(function() h, s, v = c:ToHSV() commit(render()) pushRecent(c) end)
		end
	end
	swatches(PALETTE, 266, "PALETTE")
	if #Hub.recent > 0 then swatches(Hub.recent, 330, "RECENT") end
	pk.Destroying:Connect(function() pushRecent(HSV(h, s, v)) end)
end
function UI.colorRow(parent, en, ru, get, cb)
	local r = UI.row(parent)
	UI.label(r, en, ru, {Size = UDim2.new(1, -100, 1, 0)})
	local sw = U.new("TextButton", {Size = UDim2.fromOffset(52, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Text = "", AutoButtonColor = false, BackgroundColor3 = get(), BorderSizePixel = 0}, r)
	U.corner(sw, 8)
	local st = U.new("UIStroke", {Thickness = 1.5, Transparency = 0.5}, sw)
	UI.r(st, "Color", "text")
	sw.MouseButton1Click:Connect(function()
		UI.pickColor(sw.BackgroundColor3, function(c) sw.BackgroundColor3 = c cb(c) end, (Hub.lang == "ru" and ru) or en)
	end)
	return {set = function(c) sw.BackgroundColor3 = c end}, r
end

---------------------------------------------------------------- window
function UI.window(o)
	local root = U.new("CanvasGroup", {Name = o.name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(o.w, o.h),
		BorderSizePixel = 0, GroupTransparency = 1, Visible = false}, UI.gui)
	UI.r(root, "BackgroundColor3", "bg")
	U.corner(root, 16)
	local scale = U.new("UIScale", {Scale = 1.14}, root)
	local stroke = U.new("UIStroke", {Thickness = o.beta and 2 or 1.2, Transparency = o.beta and 0 or 0.3}, root)
	local win = {root = root, tabs = {}, pages = {}, open = false}
	if o.beta then
		local g = U.new("UIGradient", {}, stroke)
		Hub.addUpdater(function() if root.Parent then g.Rotation = (os.clock() * 50) % 360 g.Color = ColorSequence.new({ColorSequenceKeypoint.new(0, UI.acc.c1), ColorSequenceKeypoint.new(0.5, UI.acc.c2), ColorSequenceKeypoint.new(1, UI.acc.c1)}) end end)
	else UI.r(stroke, "Color", "stroke") end

	local bar = U.new("Frame", {Size = UDim2.new(1, 0, 0, 64), BackgroundTransparency = 1, Active = true}, root)
	UI.makeDraggable(root, bar)
	local dot = U.new("Frame", {Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(24, 27), BorderSizePixel = 0}, bar)
	UI.r(dot, "BackgroundColor3", "acc")
	U.corner(dot, 5)
	Hub.addUpdater(function() if dot.Parent then dot.BackgroundTransparency = 0.5 + 0.5 * math.sin(os.clock() * 2.2) * 0.65 end end)
	local t1 = U.new("TextLabel", {Size = UDim2.fromOffset(200, 22), Position = UDim2.fromOffset(46, 15), BackgroundTransparency = 1, Text = o.title, Font = Enum.Font.GothamBlack, TextSize = 18, TextXAlignment = Enum.TextXAlignment.Left}, bar)
	UI.r(t1, "TextColor3", "text")
	local t2 = U.new("TextLabel", {Size = UDim2.fromOffset(200, 16), Position = UDim2.fromOffset(46, 37), BackgroundTransparency = 1, Text = o.sub, Font = Enum.Font.Gotham, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left}, bar)
	UI.r(t2, "TextColor3", "sub")
	local x = U.new("TextButton", {Size = UDim2.fromOffset(32, 32), Position = UDim2.new(1, -46, 0, 16), BackgroundTransparency = 1, Text = "×", Font = Enum.Font.GothamBold, TextSize = 22, AutoButtonColor = false}, bar)
	UI.r(x, "TextColor3", "text")
	UI.r(x, "BackgroundColor3", "elh")
	U.corner(x, 8)
	x.MouseEnter:Connect(function() U.tween(x, 0.15, {BackgroundTransparency = 0}) end)
	x.MouseLeave:Connect(function() U.tween(x, 0.15, {BackgroundTransparency = 1}) end)
	x.MouseButton1Click:Connect(function() win.hide() end)
	win.bar = bar
	local hl = U.new("Frame", {Size = UDim2.new(1, -32, 0, 1), Position = UDim2.fromOffset(16, 64), BorderSizePixel = 0, BackgroundTransparency = 0.4}, root)
	UI.r(hl, "BackgroundColor3", "stroke")

	local side = U.new("Frame", {Size = UDim2.new(0, 168, 1, -65), Position = UDim2.fromOffset(0, 65), BackgroundTransparency = 1}, root)
	local sl = U.new("ScrollingFrame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 0, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y}, side)
	U.new("UIListLayout", {Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder}, sl)
	U.new("UIPadding", {PaddingTop = UDim.new(0, 14), PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14)}, sl)
	local vl = U.new("Frame", {Size = UDim2.new(0, 1, 1, -90), Position = UDim2.fromOffset(168, 78), BorderSizePixel = 0, BackgroundTransparency = 0.5}, root)
	UI.r(vl, "BackgroundColor3", "stroke")
	local host = U.new("Frame", {Size = UDim2.new(1, -169, 1, -65), Position = UDim2.fromOffset(169, 65), BackgroundTransparency = 1, ClipsDescendants = true}, root)

	function win.addTab(id, en, ru, glyph)
		local b = U.new("TextButton", {Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = #win.tabs + 1}, sl)
		UI.r(b, "BackgroundColor3", "elh")
		U.corner(b, 9)
		local gl = U.new("TextLabel", {Size = UDim2.fromOffset(26, 38), Position = UDim2.fromOffset(8, 0), BackgroundTransparency = 1, Text = glyph or "•", Font = Enum.Font.GothamBold, TextSize = 15}, b)
		local hasGlyph = glyph ~= nil and glyph ~= ""
		gl.Visible = hasGlyph
		local lb = U.new("TextLabel", {Size = UDim2.new(1, -24, 1, 0), Position = UDim2.fromOffset(hasGlyph and 36 or 14, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left}, b)
		UI.tx(lb, en, ru)
		local ind = U.new("Frame", {Size = UDim2.fromOffset(3, 0), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), BorderSizePixel = 0}, b)
		UI.r(ind, "BackgroundColor3", "acc")
		U.corner(ind, 2)
		local page = U.new("ScrollingFrame", {Name = id, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageTransparency = 0.5,
			CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false}, host)
		UI.r(page, "ScrollBarImageColor3", "acc")
		U.new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, page)
		U.new("UIPadding", {PaddingTop = UDim.new(0, 16), PaddingLeft = UDim.new(0, 18), PaddingRight = UDim.new(0, 18), PaddingBottom = UDim.new(0, 18)}, page)
		local tab = {id = id, btn = b, page = page, ind = ind, gl = gl, lb = lb}
		table.insert(win.tabs, tab)
		win.pages[id] = page
		b.MouseEnter:Connect(function() if win.cur ~= id then U.tween(b, 0.15, {BackgroundTransparency = 0.6}) end end)
		b.MouseLeave:Connect(function() if win.cur ~= id then U.tween(b, 0.15, {BackgroundTransparency = 1}) end end)
		b.MouseButton1Click:Connect(function() win.select(id) end)
		return page
	end
	function win.select(id, quiet)
		win.cur = id
		for _, t in ipairs(win.tabs) do
			local on = t.id == id
			t.page.Visible = on
			t.lb.TextColor3 = on and TH.text or TH.sub
			t.gl.TextColor3 = on and UI.acc.c1 or TH.sub
			U.tween(t.btn, 0.2, {BackgroundTransparency = on and 0.35 or 1})
			U.tween(t.ind, 0.25, {Size = UDim2.fromOffset(3, on and 20 or 0)})
			if on and not quiet then
				t.page.Position = UDim2.fromOffset(0, 14)
				U.tween(t.page, 0.3, {Position = UDim2.fromOffset(0, 0)})
			end
		end
	end
	if o.noSide then side.Visible, vl.Visible, host.Visible = false, false, false end
	function win.show()
		if win.open then return end
		win.open = true
		root.Visible = true
		scale.Scale, root.GroupTransparency = 1.14, 1
		U.tween(scale, 0.4, {Scale = 1}, Enum.EasingStyle.Quart)
		U.tween(root, 0.3, {GroupTransparency = 0})
		if Hub.settings.shrinkGame then Lay.shrink(true, 0.8) end
	end
	function win.hide()
		if not win.open then return end
		win.open = false
		U.tween(scale, 0.22, {Scale = 0.9}, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
		U.tween(root, 0.22, {GroupTransparency = 1})
		Lay.shrink(false)
		task.delay(0.24, function() if not win.open then root.Visible = false end end)
		if win.onHide then win.onHide() end
	end
	function win.destroy() root:Destroy() end
	return win
end

---------------------------------------------------------------- menus
Hub.settings = Store.load("settings", {shrinkGame = true, lang = "en", last = "default", accent = nil})
Hub.syncers = {}
function Hub.syncUI() for _, f in ipairs(Hub.syncers) do pcall(f) end end
local function sync(f) table.insert(Hub.syncers, f) end
local function saveSettings() Store.save("settings", Hub.settings) end
function Hub.isBeta()
	local n = player.Name:lower()
	for _, u in ipairs(CFG.BETA_USERS) do if u:lower() == n then return true end end
	for _, id in ipairs(CFG.BETA_USER_IDS) do if id == player.UserId then return true end end
	return false
end
local function opt(v, en, ru) return {v = v, en = en, ru = ru or en} end

local Pages = {}
Hub.Pages = Pages

function Pages.presets(page)
	UI.section(page, "READY PRESETS", "ГОТОВЫЕ ПРЕСЕТЫ")
	for _, c in ipairs(Sk.classic) do UI.button(page, c.en, c.ru, function() Sk.applyClassic(c) UI.toast(c.en) end) end
	UI.divider(page)
	UI.section(page, "RAINBOW / RANDOM", "РАДУГА / СЛУЧАЙНО")
	UI.button(page, "Rainbow Kugoo (full)", "Rainbow Kugoo (полный)", function() Sk.apply(Sk.builtin[1]) UI.toast("Rainbow Kugoo") end)
	UI.button(page, "Random (beautiful mix)", "Random (красивый микс)", function() local sk = Sk.random() Sk.apply(sk) UI.toast(sk.name) end)
	UI.divider(page)
	UI.section(page, "SKINS CATALOG", "КАТАЛОГ СКИНОВ")
	for i, sk in ipairs(Sk.builtin) do
		if i > 1 then UI.button(page, sk.name, sk.name, function() Sk.apply(sk) UI.toast(sk.name) end, 38) end
	end
	UI.divider(page)
	UI.section(page, "CREATE", "СОЗДАНИЕ")
	UI.button(page, "Create preset (3D editor)", "Создать пресет (3D-редактор)", function() Hub.Creator.open() end)
	local mine = U.new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = UI.order(page)}, page)
	U.new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, mine)
	function Hub.refreshPresets()
		for _, c in ipairs(mine:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
		UI.counters[mine] = 0
		if #Sk.user > 0 then UI.section(mine, "MY PRESETS", "МОИ ПРЕСЕТЫ") end
		for _, s in ipairs(Sk.user) do UI.button(mine, s.name, s.name, function() Sk.apply(s) UI.toast(s.name) end) end
	end
	Hub.refreshPresets()
	UI.divider(page)
	UI.section(page, "CLOUD KEY (share your look as a key)", "CLOUD KEY (поделись видом как ключом)")
	local keyBox = UI.input(page, "Your key", "Твой ключ", "press Export", function() end)
	UI.button(page, "Export current look to key", "Экспорт текущего вида в ключ", function()
		local key = Sk.toKey(Sk.capture("Shared look"))
		if not key then UI.toast("export failed", "bad") return end
		keyBox.Text = key
		if type(setclipboard) == "function" then pcall(setclipboard, key) UI.toast("Key copied to clipboard") else UI.toast("Key is in the box — copy it") end
	end, 38)
	local inBox = UI.input(page, "Paste key", "Вставь ключ", "CK1:...", function() end)
	UI.button(page, "Import key", "Импорт ключа", function()
		local sk = Sk.fromKey(inBox.Text)
		if not sk then UI.toast("Invalid key", "bad") return end
		sk.name = (sk.name or "Shared") .. " (key)"
		Sk.apply(sk) Sk.saveUser(sk) Hub.refreshPresets()
		UI.toast("Imported: " .. sk.name)
	end, 38)
end

local function partsSection(page)
	local holder = U.new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = UI.order(page)}, page)
	U.new("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, holder)
	local colors = {}
	local function rebuild()
		for _, c in ipairs(holder:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
		UI.counters[holder] = 0
		UI.section(holder, "SCOOTER PARTS (only parts found on your scooter)", "ЧАСТИ САМОКАТА (только найденные на твоём)")
		local r = Reg.currentRig()
		if not r then UI.label(UI.row(holder), "No scooter found nearby", "Самокат не найден рядом", {sub = true}) return end
		local any = false
		for _, cat in ipairs(CATS) do
			local list = r.byCat[cat.k]
			local vis = false
			for _, p in ipairs(list) do if p.Transparency < 0.98 then vis = true break end end
			if vis then
				any = true
				colors[cat.k] = colors[cat.k] or (Hub.look.cat[cat.k] and Hub.look.cat[cat.k].c) or RGB(255, 255, 255)
				local row = UI.row(holder)
				UI.label(row, cat.en .. "  (" .. #list .. ")", cat.ru .. "  (" .. #list .. ")", {Size = UDim2.new(1, -170, 1, 0)})
				local sw = U.new("TextButton", {Size = UDim2.fromOffset(36, 24), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -66, 0.5, 0), Text = "", AutoButtonColor = false, BackgroundColor3 = colors[cat.k], BorderSizePixel = 0}, row)
				U.corner(sw, 8)
				local sws = U.new("UIStroke", {Thickness = 1.5, Transparency = 0.5}, sw)
				UI.r(sws, "Color", "text")
				local on = Hub.look.cat[cat.k] ~= nil
				local sc = UI.switch(row, on, function(v)
					if v then Paint.setCat(cat.k, colors[cat.k]) else Paint.restoreCat(cat.k) end
				end)
				sw.MouseButton1Click:Connect(function()
					UI.pickColor(colors[cat.k], function(c)
						colors[cat.k] = c sw.BackgroundColor3 = c
						Paint.setCat(cat.k, c)
						sc.set(true)
					end, (Hub.lang == "ru" and cat.ru or cat.en))
				end)
			end
		end
		if not any then UI.label(UI.row(holder), "No paintable parts", "Нет красящихся частей", {sub = true}) end
	end
	rebuild()
	Reg.onChange(function() task.wait(0.4) pcall(rebuild) end)
end

function Pages.custom(page)
	UI.section(page, "GAME MODIFICATION", "МОДИФИКАЦИЯ ИГРЫ")
	UI.toggle(page, "Stretched resolution", "Растянутое разрешение", false, function(v) M.stretch(v) end)
	UI.slider(page, "Stretch amount", "Сила растяжения", 0.5, 1, M.stretchV, 0.01, "%.2f", function(v) M.stretchV = v end)
	UI.toggle(page, "Dark sky", "Тёмное небо", false, function(v) M.darkSky(v) end)
	UI.divider(page)
	UI.section(page, "WHEELIE", "ВИЛЛИ")
	local wt = UI.toggle(page, "Wheelie assist [F]", "Помощник вилли [F]", false, function(v) W.set(v) end)
	W.listeners[#W.listeners + 1] = function() wt.set(W.on) end
	UI.slider(page, "Wheelie angle", "Угол вилли", 15, 75, W.angle, 1, "%.0f°", function(v) W.angle = v end)
	UI.divider(page)
	UI.section(page, "VEHICLE MODIFICATION", "МОДИФИКАЦИЯ ТРАНСПОРТА")
	local look = Hub.look
	local tt = UI.toggle(page, "Trail", "След", look.trail.on, function(v) look.trail.on = v Fx.trail.build() end)
	sync(function() tt.set(look.trail.on) end)
	UI.toggle(page, "Rainbow trail", "Радужный след", false, function(v) look.rainbow.trail = v or nil if not v then Fx.trail.build() end end)
	local tc = UI.colorRow(page, "Trail color", "Цвет следа", function() return look.trail.c end, function(c) look.trail.c = c look.rainbow.trail = nil if Fx.trail.obj then Fx.trail.obj.Color = ColorSequence.new(c) end end)
	sync(function() tc.set(look.trail.c) end)
	UI.toggle(page, "Own smoke effect", "Свой дым", look.smoke.own, function(v) look.smoke.own = v Fx.smoke.build() end)
	UI.colorRow(page, "Smoke color", "Цвет дыма", function() return look.smoke.c or RGB(255, 255, 255) end, function(c) look.smoke.c = c look.rainbow.smoke = nil Fx.smoke.recolorGame(c) end)
	UI.divider(page)
	UI.section(page, "CUSTOM HELMET", "КАСТОМНЫЙ ШЛЕМ")
	local hc = Hub.Helmet.cfg
	UI.toggle(page, "Replace helmet", "Заменить шлем", Hub.Helmet.on, function(v) Hub.Helmet.set(v) end)
	local function reh() if Hub.Helmet.on then Hub.Helmet.attach() end end
	UI.toggle(page, "Mask (balaclava)", "Маска", hc.mask, function(v) hc.mask = v reh() end)
	UI.toggle(page, "Goggles", "Очки", hc.goggles, function(v) hc.goggles = v reh() end)
	UI.toggle(page, "Hide hair / hats", "Скрыть волосы / шапки", hc.hideHair, function(v) hc.hideHair = v reh() end)
	UI.slider(page, "Helmet height", "Высота шлема", -1, 1, hc.hy, 0.05, "%.2f", function(v) hc.hy = v end)
	UI.slider(page, "Helmet forward", "Шлем вперёд/назад", -1, 1, hc.hz, 0.05, "%.2f", function(v) hc.hz = v end)
	UI.slider(page, "Goggles height", "Высота очков", -1, 1, hc.gy, 0.05, "%.2f", function(v) hc.gy = v end)
	UI.slider(page, "Goggles forward", "Очки вперёд/назад", -1, 1, hc.gz, 0.05, "%.2f", function(v) hc.gz = v end)
	UI.button(page, "Apply helmet offsets", "Применить смещения шлема", reh, 38)
	UI.divider(page)
	partsSection(page)
	UI.divider(page)
	UI.section(page, "CUSTOM GUI", "CUSTOM GUI")
	UI.label(UI.row(page), "Move and resize game windows (Cash, Shop, Quests, Spawner) on a black canvas.", "Двигай и меняй размер окон игры (деньги, магазин, квесты, спавнер) на чёрном фоне.", {sub = true, TextSize = 12, Size = UDim2.new(1, -20, 1, 0)})
	UI.button(page, "Open layout editor", "Открыть редактор интерфейса", function() Lay.openEditor() end)
	UI.button(page, "Reset all GUI positions", "Сбросить все позиции UI", function() Lay.resetAll() end, 38)
end

function Pages.glow(page)
	local look = Hub.look
	UI.section(page, "UNDERGLOW (light only, no visible block)", "ПОДСВЕТКА (только свет, без видимого блока)")
	local gt = UI.toggle(page, "Enable underglow", "Включить подсветку", look.glow.on, function(v)
		look.glow.on = v
		local ok = Fx.glow.build()
		if v and not ok then UI.toast("Scooter not found - stand next to a Kukirin", "bad") end
	end)
	sync(function() gt.set(look.glow.on) end)
	UI.toggle(page, "Rainbow mode", "Радужный режим", look.rainbow.glow == true, function(v) look.rainbow.glow = v or nil if not v then Fx.glow.setColor(look.glow.c) end end)
	local gc = UI.colorRow(page, "Glow color", "Цвет подсветки", function() return look.glow.c end, function(c) look.glow.c = c look.rainbow.glow = nil Fx.glow.setColor(c) end)
	sync(function() gc.set(look.glow.c) end)
	UI.slider(page, "Brightness", "Яркость", 0.5, 12, look.glow.bright, 0.5, "%.1f", function(v) look.glow.bright = v Fx.glow.setLight(v, look.glow.range) end)
	UI.slider(page, "Range", "Дальность", 3, 30, look.glow.range, 1, "%.0f", function(v) look.glow.range = v Fx.glow.setLight(look.glow.bright, v) end)
	UI.slider(page, "Spread (lower = only the ground)", "Угол (меньше = только земля)", 40, 180, look.glow.spread, 5, "%.0f°", function(v) look.glow.spread = v Fx.glow.setLight(look.glow.bright, look.glow.range, v) end)
	UI.slider(page, "Halo (point light)", "Ореол (точечный свет)", 0, 1.5, look.glow.halo, 0.05, "%.2f", function(v) look.glow.halo = v Fx.glow.setLight(look.glow.bright, look.glow.range) end)
	UI.toggle(page, "Show neon strip", "Показать неоновую полосу", look.glow.strip, function(v) Fx.glow.setStrip(v) end)
	UI.toggle(page, "React to speed", "Реакция на скорость", look.glow.react, function(v) look.glow.react = v if not v then Fx.glow.setLight(look.glow.bright, look.glow.range) end end)
	UI.divider(page)
	UI.section(page, "WHEEL GLOW", "СВЕТ КОЛЁС")
	local wt = UI.toggle(page, "Neon wheel rings", "Неоновые кольца колёс", look.wheelGlow.on, function(v) look.wheelGlow.on = v Fx.wheelGlow.build() end)
	sync(function() wt.set(look.wheelGlow.on) end)
	UI.toggle(page, "Rainbow wheel rings", "Радужные кольца", look.rainbow.wheelglow == true, function(v) look.rainbow.wheelglow = v or nil end)
	UI.colorRow(page, "Ring color", "Цвет колец", function() return look.wheelGlow.c end, function(c) look.wheelGlow.c = c look.rainbow.wheelglow = nil end)
end

function Pages.settings(page, win)
	UI.section(page, "THEME", "ТЕМА")
	UI.toggle(page, "Light theme", "Светлая тема", UI.themeName == "Light", function(v) UI.setTheme(v and "Light" or "Dark") end)
	UI.colorRow(page, "Accent color", "Цвет акцента", function() return UI.acc.c1 end, function(c) UI.setAccent(c, Hub.kind == "beta" and UI.acc.c2 or c) Hub.settings.accent = U.c2t(c) saveSettings() end)
	UI.divider(page)
	UI.section(page, "INTERFACE", "ИНТЕРФЕЙС")
	UI.toggle(page, "Shrink game UI while menu is open", "Уменьшать игровой UI при открытии меню", Hub.settings.shrinkGame, function(v) Hub.settings.shrinkGame = v saveSettings() end)
	UI.toggle(page, "Mobile button", "Мобильная кнопка", true, function(v) if Hub.mobileBtn then Hub.mobileBtn.Visible = v end end)
	UI.cycle(page, "Language", "Язык", {opt("en", "English", "English"), opt("ru", "Русский", "Русский")}, Hub.lang, function(v) UI.setLang(v) Hub.settings.lang = v saveSettings() end)
	UI.button(page, "Open GUI layout editor", "Открыть редактор интерфейса", function() Lay.openEditor() end, 38)
	UI.divider(page)
	UI.section(page, "KEYS", "КЛАВИШИ")
	UI.label(UI.row(page), "Menu: RightShift / LeftAlt   |   Wheelie: F   |   Auto wheelie: G", "Меню: RightShift / LeftAlt   |   Вилли: F   |   Авто-вилли: G", {sub = true, TextSize = 12, Size = UDim2.new(1, -20, 1, 0)})
	UI.divider(page)
	UI.section(page, "DATA", "ДАННЫЕ")
	UI.label(UI.row(page), Store.fs and "Saving to disk: ON (workspace/CustomKukirin)" or "Saving to disk: OFF (memory only — executor has no writefile)",
		Store.fs and "Сохранение на диск: ВКЛ (workspace/CustomKukirin)" or "Сохранение на диск: ВЫКЛ (только память — нет writefile)", {sub = true, TextSize = 12, Size = UDim2.new(1, -20, 1, 0)})
	UI.button(page, "Unload Custom Kukirin", "Выгрузить Custom Kukirin", function() Hub.destroy() end, 38)
end

local deb = {}
local function debounce(key, fn)
	local tok = {}
	deb[key] = tok
	task.delay(0.4, function() if deb[key] == tok then pcall(fn) end end)
end

function Pages.details(page)
	local P, F, Ga = Hub.Pend, Hub.Fork, Hub.Garland
	UI.section(page, "PENDULUM SUSPENSION (like the photo)", "МАЯТНИКОВАЯ ПОДВЕСКА (как на фото)")
	local pt = UI.toggle(page, "Pendulum arm + shock", "Маятник + амортизатор", P.cfg.on, function(v) P.set(v) end)
	sync(function() pt.set(P.cfg.on) end)
	UI.cycle(page, "Side", "Сторона", {opt(1, "Right", "Справа"), opt(-1, "Left", "Слева")}, P.cfg.side, function(v) P.cfg.side = v if P.cfg.on then P.build() end end)
	UI.slider(page, "Spring coils", "Витки пружины", 3, 12, P.cfg.turns, 1, "%.0f", function(v) P.cfg.turns = v debounce("pend", function() if P.cfg.on then P.build() end end) end)
	UI.slider(page, "Thickness", "Толщина", 0.6, 1.8, P.cfg.thick, 0.05, "%.2f", function(v) P.cfg.thick = v debounce("pend", function() if P.cfg.on then P.build() end end) end)
	UI.cycle(page, "Mode", "Режим", {opt("full", "Full (arm + shock)", "Полный (рычаг + амортизатор)"), opt("wheel", "Wheel only (no top)", "Только в колесе (без верха)")}, P.cfg.mode, function(v) P.cfg.mode = v if P.cfg.on then P.build() end end)
	UI.slider(page, "Arm length", "Длина маятника", 0.8, 2.2, P.cfg.len, 0.05, "%.2f", function(v) P.cfg.len = v debounce("pend", function() if P.cfg.on then P.build() end end) end)
	UI.toggle(page, "Cable (handlebar center to wheel)", "Провод (из центра руля в колесо)", P.cfg.cable, function(v) P.cfg.cable = v if P.cfg.on then P.build() end end)
	UI.toggle(page, "Hide stock fork / suspension", "Скрыть стоковую вилку / подвеску", P.cfg.hideStock, function(v) P.hideStock(v) end)
	UI.divider(page)
	UI.section(page, "TELESCOPIC SPRING FORK (all scooters)", "ТЕЛЕСКОПИЧЕСКАЯ ПРУЖИННАЯ ВИЛКА (все самокаты)")
	local ft = UI.toggle(page, "Spring fork", "Пружинная вилка", F.cfg.on, function(v) F.set(v) end)
	sync(function() ft.set(F.cfg.on) end)
	UI.cycle(page, "Fork position", "Позиция вилки", {opt(0, "Center", "По центру"), opt(1, "Side +", "Сбоку +"), opt(-1, "Side -", "Сбоку -")}, F.cfg.side, function(v) F.cfg.side = v if F.cfg.on then F.build() end end)
	UI.slider(page, "Fork length", "Длина вилки", 1.4, 3.2, F.cfg.length, 0.1, "%.1f", function(v) F.cfg.length = v debounce("fork", function() if F.cfg.on then F.build() end end) end)
	UI.slider(page, "Spring turns", "Витки пружины", 3, 14, F.cfg.turns, 1, "%.0f", function(v) F.cfg.turns = v debounce("fork", function() if F.cfg.on then F.build() end end) end)
	UI.divider(page)
	UI.section(page, "GARLAND (under the deck, always on)", "ГИРЛЯНДА (под декой, всегда включена)")
	local gt = UI.toggle(page, "Garland", "Гирлянда", Ga.cfg.on, function(v) Ga.set(v) end)
	sync(function() gt.set(Ga.cfg.on) end)
	UI.colorRow(page, "Garland color", "Цвет гирлянды", function() return Ga.cfg.c end, function(c) Ga.setColor(c) end)
	UI.cycle(page, "Mode", "Режим", {opt("Solid", "Solid", "Одноцветная"), opt("Rainbow", "Rainbow", "Радуга"), opt("Chase", "Chase", "Бегущая"), opt("Twinkle", "Twinkle", "Мерцание")}, Ga.cfg.mode, function(v) Ga.cfg.mode = v if v == "Solid" then Ga.setColor(Ga.cfg.c) end end)
	UI.slider(page, "LED count (per side)", "Кол-во огоньков (с каждой стороны)", 6, 40, Ga.cfg.count, 1, "%.0f", function(v) Ga.cfg.count = v debounce("gar", function() if Ga.cfg.on then Ga.build() end end) end)
	UI.slider(page, "LED size", "Размер огоньков", 0.5, 2.5, Ga.cfg.size, 0.1, "%.1f", function(v) Ga.cfg.size = v debounce("gar", function() if Ga.cfg.on then Ga.build() end end) end)
	UI.slider(page, "Glow strength", "Яркость свечения", 0, 6, Ga.cfg.bright, 0.1, "%.1f", function(v) Ga.setBright(v) end)
end

function Pages.shader(page)
	local Sh = Hub.Shader
	UI.section(page, "REALISTIC SHADER", "РЕАЛИСТИЧНЫЙ ШЕЙДЕР")
	local opts = {}
	for _, p in ipairs(Sh.presets) do opts[#opts + 1] = opt(p.n, (p.day and "Day: " or "Night: ") .. p.n, (p.day and "День: " or "Ночь: ") .. p.n) end
	local on
	UI.cycle(page, "Preset", "Пресет", opts, Sh.name or Sh.presets[1].n, function(n) Sh.name = n Sh.apply(n) if on then on.set(true) end end)
	on = UI.toggle(page, "Shader enabled", "Шейдер включён", Sh.on, function(v) if v then Sh.apply(Sh.name or Sh.presets[1].n) else Sh.restore() end end)
	UI.slider(page, "Intensity", "Интенсивность", 0.2, 2, Sh.intensity, 0.05, "%.2f", function(v) Sh.intensity = v if Sh.on then debounce("sh", function() Sh.apply(Sh.name) end) end end)
	UI.slider(page, "Reflections", "Отражения", 0, 2, 1, 0.05, "%.2f", function(v) Sh.reflect = v if Sh.on then pcall(function() Lighting.EnvironmentSpecularScale = v end) end end)
	UI.divider(page)
	UI.section(page, "EFFECTS", "ЭФФЕКТЫ")
	UI.toggle(page, "Bloom", "Свечение (Bloom)", true, function(v) Sh.toggleFx("bloom", v) end)
	UI.toggle(page, "Sun rays", "Лучи солнца", true, function(v) Sh.toggleFx("rays", v) end)
	UI.toggle(page, "Depth of field", "Глубина резкости", true, function(v) Sh.toggleFx("dof", v) end)
	UI.toggle(page, "Color grading", "Цветокоррекция", true, function(v) Sh.toggleFx("cc", v) end)
end

-- BETA страницы
function Pages.dash(page)
	local look = Hub.look
	local card = UI.row(page, 92)
	local logo = U.new("Frame", {Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(14, 14), BackgroundTransparency = 1}, card)
	local ring = U.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1}, logo)
	U.corner(ring, 32)
	local rs = U.new("UIStroke", {Thickness = 4}, ring)
	local rg = U.new("UIGradient", {Color = ColorSequence.new({ColorSequenceKeypoint.new(0, UI.acc.c1), ColorSequenceKeypoint.new(0.5, UI.acc.c2), ColorSequenceKeypoint.new(1, UI.acc.c1)})}, rs)
	local core = U.new("TextLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "K", Font = Enum.Font.GothamBlack, TextSize = 28}, logo)
	UI.r(core, "TextColor3", "text")
	local info = U.new("TextLabel", {Size = UDim2.new(1, -100, 1, -16), Position = UDim2.fromOffset(92, 8), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center, RichText = true}, card)
	UI.r(info, "TextColor3", "text")
	local acc = 0
	Hub.addUpdater(function(dt)
		if not card.Parent then return end
		rg.Rotation = (os.clock() * 120) % 360
		core.TextSize = 28 + math.sin(os.clock() * 3) * 1.5
		acc = acc + dt
		if acc < 0.25 then return end
		acc = 0
		local r = Reg.currentRig()
		local fps = math.floor(1 / math.max(dt, 1e-3) + 0.5)
		local spd = r and r.root and math.floor(r.root.AssemblyLinearVelocity.Magnitude) or 0
		info.Text = string.format("<b>%s</b>\n%s\n<font size='12'>FPS %d   •   %s   •   %d km/h</font>", player.DisplayName,
			r and ("Scooter: " .. r.model.Name .. "  (" .. #r.parts .. " parts)") or "Scooter: not found", fps, Hub.Wheelie.on and "wheelie ON" or "wheelie off", spd)
	end)
	UI.section(page, "QUICK ACTIONS", "БЫСТРЫЕ ДЕЙСТВИЯ")
	local rk = UI.toggle(page, "Rainbow Kugoo (full)", "Rainbow Kugoo (полный)", look.rainbow.paint == true, function(v) if v then Sk.apply(Sk.builtin[1]) else look.rainbow = {} Paint.restoreAll() Paint.refresh() Fx.smoke.restoreGame() Fx.restoreLights() Hub.syncUI() end end)
	sync(function() rk.set(look.rainbow.paint == true) end)
	local aw = UI.toggle(page, "Auto wheelie [G]", "Авто-вилли [G]", W.auto, function(v) W.setAuto(v) end)
	W.listeners[#W.listeners + 1] = function() aw.set(W.auto) end
	local gt = UI.toggle(page, "Underglow", "Подсветка", look.glow.on, function(v) look.glow.on = v Fx.glow.build() end)
	sync(function() gt.set(look.glow.on) end)
	local tt = UI.toggle(page, "Light trail", "Световой след", look.trail.on, function(v) look.trail.on = v Fx.trail.build() end)
	sync(function() tt.set(look.trail.on) end)
	UI.toggle(page, "Garland", "Гирлянда", Hub.Garland.cfg.on, function(v) Hub.Garland.set(v) end)
end

function Pages.rainbow(page)
	local look = Hub.look
	UI.section(page, "RAINBOW KUGOO", "RAINBOW KUGOO")
	UI.button(page, "Apply full Rainbow Kugoo", "Включить полный Rainbow Kugoo", function() Sk.apply(Sk.builtin[1]) end)
	UI.button(page, "Turn all rainbow off", "Выключить всю радугу", function()
		look.rainbow = {}
		Paint.restoreAll() Paint.refresh() Fx.smoke.restoreGame() Fx.restoreLights() Fx.glow.setColor(look.glow.c) Hub.syncUI()
	end, 38)
	UI.divider(page)
	UI.section(page, "PER PART (only what you pick glows)", "ПО ЧАСТЯМ (светится только выбранное)")
	local function rb(en, ru, key, after)
		local t = UI.toggle(page, en, ru, look.rainbow[key] == true, function(v)
			look.rainbow[key] = v or nil
			if not v then
				if key == "paint" then Paint.restoreAll() Paint.refresh()
				elseif CATIDX[key] then Paint.restoreCat(key) Paint.refresh()
				elseif key == "smoke" then Fx.smoke.restoreGame()
				elseif key == "lights" then Fx.restoreLights() end
			end
			if after then after(v) end
		end)
		sync(function() t.set(look.rainbow[key] == true) end)
	end
	rb("Rainbow paint (colored accent parts)", "Радужная краска (цветные акценты)", "paint")
	rb("Handlebar", "Руль", "handlebar")
	rb("Grips", "Грипсы", "grips")
	rb("Wheelie bar / bugel", "Вилли-бар / бугель", "wheelie")
	rb("Underglow", "Подсветка", "glow", function(v) if v and not look.glow.on then look.glow.on = true Fx.glow.build() end end)
	rb("Light trail", "Световой след", "trail", function(v) if v and not look.trail.on then look.trail.on = true Fx.trail.build() end end)
	rb("Rainbow smoke", "Радужный дым", "smoke", function(v) if v and not look.smoke.own then look.smoke.own = true Fx.smoke.build() end end)
	rb("Wheel rings", "Кольца колёс", "wheelglow", function(v) if v and not look.wheelGlow.on then look.wheelGlow.on = true Fx.wheelGlow.build() end end)
	rb("Scooter lights", "Фары самоката", "lights")
end

function Pages.autowheelie(page)
	UI.section(page, "AUTO WHEELIE (beta)", "АВТО-ВИЛЛИ (beta)")
	local aw = UI.toggle(page, "Auto wheelie [G]", "Авто-вилли [G]", W.auto, function(v) W.setAuto(v) end)
	W.listeners[#W.listeners + 1] = function() aw.set(W.auto) end
	UI.label(UI.row(page), "Holds the wheelie in place and gently rocks back and forth.", "Держит вилли на месте и слегка покачивает вперёд-назад.", {sub = true, TextSize = 12, Size = UDim2.new(1, -20, 1, 0)})
	UI.slider(page, "Wheelie angle", "Угол вилли", 15, 75, W.angle, 1, "%.0f°", function(v) W.angle = v end)
	UI.slider(page, "Hold power", "Сила удержания", 2, 14, W.power, 0.5, "%.1f", function(v) W.power = v end)
	UI.slider(page, "Rise speed", "Скорость подъёма", 20, 200, W.ramp, 5, "%.0f°/s", function(v) W.ramp = v end)
	UI.slider(page, "Rock strength", "Сила покачивания", 0, 4, W.nudgeAmp, 0.1, "%.1f", function(v) W.nudgeAmp = v end)
	UI.slider(page, "Rock speed (Hz)", "Скорость покачивания (Гц)", 0.1, 2, W.nudgeFreq, 0.05, "%.2f", function(v) W.nudgeFreq = v end)
	UI.slider(page, "Brake on F-wheelie", "Торможение при вилли (F)", 0, 4, W.brake, 0.1, "%.1f", function(v) W.brake = v end)
	UI.toggle(page, "Pivot on rear wheel", "Вращение вокруг заднего колеса", W.pivot, function(v) W.pivot = v end)
	UI.toggle(page, "Auto level (no roll)", "Авто-выравнивание (без крена)", W.level, function(v) W.level = v end)
	UI.toggle(page, "Invert direction (if it flips backwards)", "Инверт. направление (если кувыркается назад)", W.invert, function(v) W.invert = v end)
	UI.button(page, "Print detected parts (F9)", "Вывести найденные детали (F9)", function()
		local r = Reg.currentRig()
		if not r then print("[GIGAHUB] no scooter") return end
		print("[GIGAHUB] scooter:", r.model:GetFullName(), "root:", r.root and r.root.Name, "forward(local):", r.fwdLocal, "front wheels:", #r.front, "rear wheels:", #r.rear)
		for _, c in ipairs(CATS) do print("[GIGAHUB]", c.k, #r.byCat[c.k]) end
	end, 38)
end

local function speedoHud()
	local f = U.new("Frame", {Size = UDim2.fromOffset(150, 54), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Visible = false}, UI.gui)
	if Hub.speedo then Hub.speedo:Destroy() end
	Hub.speedo = f
	UI.r(f, "BackgroundColor3", "bg")
	U.corner(f, 14)
	local st = U.new("UIStroke", {Thickness = 1.5}, f)
	UI.r(st, "Color", "acc")
	local l = U.new("TextLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 24, RichText = true}, f)
	UI.r(l, "TextColor3", "text")
	Hub.addUpdater(function()
		if not f.Visible then return end
		local r = Reg.currentRig()
		local s = r and r.root and r.root.AssemblyLinearVelocity.Magnitude or 0
		l.Text = string.format("%d <font size='12'>km/h</font>", s)
	end)
	return f
end
function Pages.lab(page)
	local look = Hub.look
	UI.section(page, "TEST LAB (beta)", "ТЕСТ-ЛАБОРАТОРИЯ (beta)")
	local hud = speedoHud()
	UI.toggle(page, "Speedometer HUD", "Спидометр", false, function(v) hud.Visible = v end)
	UI.slider(page, "Field of view", "Угол обзора (FOV)", 40, 120, 70, 1, "%.0f", function(v) M.setFov(v) end)
	UI.toggle(page, "Cinematic filter", "Кинематографичный фильтр", false, function(v) M.cinematic(v) end)
	UI.toggle(page, "Photo mode (hide menu UI)", "Фото-режим (скрыть UI меню)", false, function(v)
		if Hub.menu then if v then Hub.menu.hide() UI.toast("Press menu key to return") else Hub.menu.show() end end
	end)
	UI.divider(page)
	UI.section(page, "ANIMATED IMAGE (sprite sheet PNG/JPG)", "АНИМИРОВАННАЯ КАРТИНКА (спрайт-лист PNG/JPG)")
	local cfg = {url = "", cols = 4, rows = 4, fps = 12, face = "Top"}
	local prevRow = UI.row(page, 120)
	local box = U.new("Frame", {Size = UDim2.fromOffset(100, 100), Position = UDim2.fromOffset(10, 10), BackgroundColor3 = RGB(0, 0, 0), ClipsDescendants = true}, prevRow)
	U.corner(box, 10)
	-- встроенная процедурная анимация (если URL не задан)
	local orb = {}
	for i = 1, 6 do
		orb[i] = U.new("Frame", {Size = UDim2.fromOffset(16, 16), AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0}, box)
		U.corner(orb[i], 8)
	end
	local anim = U.new("ImageLabel", {BackgroundTransparency = 1, Visible = false}, box)
	local ai = 0
	local acc = 0
	Hub.addUpdater(function(dt)
		if not box.Parent then return end
		if anim.Visible then
			acc = acc + dt
			if acc >= 1 / math.max(cfg.fps, 1) then
				acc = 0
				ai = (ai + 1) % (cfg.cols * cfg.rows)
				anim.Position = UDim2.fromScale(-(ai % cfg.cols), -math.floor(ai / cfg.cols))
			end
		else
			for i, o in ipairs(orb) do
				local a = os.clock() * 2 + i * (math.pi / 3)
				o.Position = UDim2.new(0.5, math.cos(a) * 30, 0.5, math.sin(a) * 30)
				o.BackgroundColor3 = HSV((os.clock() * 0.3 + i / 6) % 1, 0.85, 1)
			end
		end
	end)
	U.new("TextLabel", {Size = UDim2.new(1, -130, 1, -20), Position = UDim2.fromOffset(122, 10), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = RGB(140, 145, 160),
		Text = (Hub.lang == "ru") and "Roblox не умеет GIF/WebP/APNG. Сделай спрайт-лист PNG (кадры сеткой, напр. на ezgif.com), вставь ссылку, укажи столбцы × строки и FPS." or "Roblox can't play GIF/WebP/APNG. Make a PNG sprite sheet (frames in a grid, e.g. on ezgif.com), paste the link and set columns × rows and FPS."}, prevRow)
	UI.input(page, "Sheet URL", "Ссылка на лист", "https://.../sheet.png", function(t) cfg.url = t end)
	UI.slider(page, "Columns", "Столбцы", 1, 16, cfg.cols, 1, "%.0f", function(v) cfg.cols = v end)
	UI.slider(page, "Rows", "Строки", 1, 16, cfg.rows, 1, "%.0f", function(v) cfg.rows = v end)
	UI.slider(page, "FPS", "Кадров/сек", 1, 60, cfg.fps, 1, "%.0f", function(v) cfg.fps = v end)
	UI.button(page, "Preview animation", "Показать анимацию", function()
		task.spawn(function()
			local a, err = Img.get(cfg.url)
			if not a then UI.toast(err or "error", "bad") return end
			anim.Image, anim.Size, anim.Position, anim.Visible = a, UDim2.fromScale(cfg.cols, cfg.rows), UDim2.new(), true
			for _, o in ipairs(orb) do o.Visible = false end
		end)
	end, 38)
	UI.cycle(page, "Deck face", "Грань деки", (function() local t = {} for _, f in ipairs(Hub.FACES) do t[#t + 1] = opt(f, f) end return t end)(), "Top", function(v) cfg.face = v end)
	UI.button(page, "Apply animated texture to deck", "Наложить анимацию на деку", function()
		local r = Reg.currentRig()
		local name
		if r then for _, s in ipairs(r.slots) do if s.cat == "frame" then name = s.name break end end end
		if not name then UI.toast("deck part not found", "bad") return end
		Tex.setSlot(name, {url = cfg.url, face = cfg.face, mode = "Anim", cols = cfg.cols, rows = cfg.rows, fps = cfg.fps}, function(ok, err) UI.toast(ok and "Applied" or (err or "error"), ok and nil or "bad") end)
	end, 38)
end

---------------------------------------------------------------- 3D viewport (превью самоката)
local VP = {}
Hub.VP = VP
function VP.new(parent, size)
	local self = {map = {}, yaw = 0.6, pitch = 0.25, dist = 8, center = Vector3.zero}
	local frame = U.new("ViewportFrame", {Size = size or UDim2.fromScale(1, 1), BackgroundTransparency = 0, Ambient = RGB(150, 150, 160), LightColor = RGB(255, 255, 255), LightDirection = Vector3.new(-1, -1.2, -0.6), BorderSizePixel = 0}, parent)
	UI.r(frame, "BackgroundColor3", "side")
	U.corner(frame, 12)
	local wm = U.new("WorldModel", {}, frame)
	local cam = U.new("Camera", {FieldOfView = 40}, frame)
	frame.CurrentCamera = cam
	self.frame, self.wm, self.cam = frame, wm, cam
	local function upd()
		local cf = CFrame.new(self.center) * CFrame.Angles(0, self.yaw, 0) * CFrame.Angles(-self.pitch, 0, 0) * CFrame.new(0, 0, self.dist)
		cam.CFrame = CFrame.lookAt(cf.Position, self.center)
	end
	upd()
	function self:load(r)
		for _, c in ipairs(wm:GetChildren()) do c:Destroy() end
		self.map, self.rig = {}, r
		if not r or not r.root then return end
		local mn, mx = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, p in ipairs(r.parts) do
			if p.Transparency < 0.98 then
				local ok, c = pcall(function() return p:Clone() end)
				if ok and c then
					for _, ch in ipairs(c:GetChildren()) do if not (ch:IsA("SpecialMesh") or ch:IsA("Decal")) then ch:Destroy() end end
					c.Anchored, c.CanCollide = true, false
					c.CFrame = p.CFrame
					c.Parent = wm
					self.map[p] = c
					mn = Vector3.new(math.min(mn.X, p.Position.X), math.min(mn.Y, p.Position.Y), math.min(mn.Z, p.Position.Z))
					mx = Vector3.new(math.max(mx.X, p.Position.X), math.max(mx.Y, p.Position.Y), math.max(mx.Z, p.Position.Z))
				end
			end
		end
		self.center = (mn + mx) / 2
		self.dist = math.max((mx - mn).Magnitude * 1.1, 4)
		upd()
	end
	function self:colorSlot(name, c, m)
		local r = self.rig
		local s = r and r.slotMap[name]
		if not s then return end
		for _, p in ipairs(s.parts) do
			local cl = self.map[p]
			if cl then if c then cl.Color = c end if m then cl.Material = m end end
		end
	end
	function self:reset()
		for p, cl in pairs(self.map) do local o = self.rig.orig[p] if o then cl.Color, cl.Material, cl.Transparency = o.Color, o.Material, o.Transparency end end
	end
	-- превью скина (без применения к настоящему самокату)
	function self:showSkin(skin)
		self:reset()
		self.skin = skin
		local r = self.rig
		if not r then return end
		for p, cl in pairs(self.map) do
			local k = r.cat[p]
			local c = skin.cat and skin.cat[k]
			local sl = skin.slot and skin.slot[p.Name]
			if sl and sl.c then cl.Color = U.t2c(sl.c) elseif c then cl.Color = U.t2c(c.c) end
			local mname = (sl and sl.m) or (c and c.m)
			if mname then pcall(function() cl.Material = Enum.Material[mname] end) end
			if (sl and sl.h) or (skin.hide and skin.hide[k]) then cl.Transparency = 1 end
		end
	end
	function self:hideSlot(name, v)
		local s = self.rig and self.rig.slotMap[name]
		if not s then return end
		for _, p in ipairs(s.parts) do local cl = self.map[p] if cl then cl.Transparency = v and 1 or self.rig.orig[p].Transparency end end
	end
	function self:pick(m)
		local ap, as = frame.AbsolutePosition, frame.AbsoluteSize
		local ray = cam:ViewportPointToRay(m.X - ap.X, m.Y - ap.Y)
		local res = wm:Raycast(ray.Origin, ray.Direction * 500)
		if res then for p, cl in pairs(self.map) do if cl == res.Instance then return p end end end
	end
	-- управление: ЛКМ — вращать, колесо — зум, клик — выбрать деталь
	frame.InputBegan:Connect(function(i)
		if isPress(i) then
			local m0 = UIS:GetMouseLocation()
			local y0, p0 = self.yaw, self.pitch
			local moved = false
			UI.beginDrag(function(m)
				if (m - m0).Magnitude > 4 then moved = true end
				self.yaw, self.pitch = y0 - (m.X - m0.X) * 0.01, math.clamp(p0 + (m.Y - m0.Y) * 0.008, -1.2, 1.3)
				upd()
			end)
			local con
			con = UIS.InputEnded:Connect(function(e)
				if isPress(e) then
					con:Disconnect()
					if not moved and self.onPick then self.onPick(self:pick(UIS:GetMouseLocation())) end
				end
			end)
		end
	end)
	frame.MouseWheelForward:Connect(function() self.dist = math.max(self.dist * 0.9, 1.5) upd() end)
	frame.MouseWheelBackward:Connect(function() self.dist = math.min(self.dist * 1.1, 80) upd() end)
	Hub.addUpdater(function(dt) if frame.Parent and self.autoSpin then self.yaw = self.yaw + dt * 0.5 upd() end end)
	return self
end

---------------------------------------------------------------- Skins page (каталог + превью)
local MATS = {opt("", "Original", "Оригинал"), opt("SmoothPlastic", "Smooth"), opt("Metal", "Metal", "Металл"), opt("Neon", "Neon", "Неон"), opt("Glass", "Glass", "Стекло"), opt("Foil", "Foil"), opt("Plastic", "Plastic", "Пластик")}
function Pages.skins(page)
	local Av = Hub.Avatar
	UI.section(page, "BECOME ANOTHER PLAYER (visible only to you)", "СТАТЬ ДРУГИМ ИГРОКОМ (видно только тебе)")
	local prevRow = UI.row(page, 150)
	local prev = U.new("ImageLabel", {Size = UDim2.fromOffset(130, 130), Position = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, Image = Av.thumb(player.UserId, true)}, prevRow)
	U.corner(prev, 10)
	local status = U.new("TextLabel", {Size = UDim2.new(1, -160, 1, -20), Position = UDim2.fromOffset(150, 10), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13,
		TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top}, prevRow)
	UI.r(status, "TextColor3", "sub")
	local function say(en, ru) status.Text = (Hub.lang == "ru") and ru or en end
	say("Type a nickname (or UserId), press Preview, then Become.", "Введи ник (или UserId), нажми Просмотр, затем Стать.")
	local nick = UI.input(page, "Nickname", "Ник игрока", "Roblox username or UserId", function() end)
	local function resolve(cb)
		task.spawn(function()
			local id = Av.idOf(nick.Text)
			if not id then say("Player not found.", "Игрок не найден.") UI.toast("Player not found", "bad") return end
			cb(id)
		end)
	end
	UI.button(page, "Preview", "Просмотр", function()
		resolve(function(id) prev.Image = Av.thumb(id, true) say("UserId " .. id .. " - press Become to wear it.", "UserId " .. id .. " - нажми «Стать», чтобы надеть.") end)
	end, 38)
	UI.button(page, "Become this player", "Стать этим игроком", function()
		resolve(function(id)
			prev.Image = Av.thumb(id, true)
			say("Applying avatar...", "Применяю аватар...")
			local ok, err = Av.become(id)
			say(ok and "Done! You look like this player now (only on your screen)." or ("Failed: " .. tostring(err)), ok and "Готово! Ты выглядишь как этот игрок (только у тебя на экране)." or ("Ошибка: " .. tostring(err)))
			UI.toast(ok and "Avatar applied" or "Avatar failed", ok and nil or "bad")
		end)
	end)
	UI.button(page, "Restore my avatar", "Вернуть мой аватар", function()
		Av.restore() Av.clearAdded() prev.Image = Av.thumb(player.UserId, true) say("Your avatar is back.", "Твой аватар вернулся.")
	end, 38)
	UI.divider(page)
	UI.section(page, "MAKE YOUR OWN AVATAR", "СДЕЛАЙ СВОЙ АВАТАР")
	UI.colorRow(page, "Skin color", "Цвет кожи", function() return RGB(255, 220, 180) end, function(c) Av.setSkin(c) end)
	local shirt = UI.input(page, "Shirt ID", "ID рубашки", "Roblox shirt template id", function() end)
	local pants = UI.input(page, "Pants ID", "ID штанов", "Roblox pants template id", function() end)
	UI.button(page, "Apply shirt + pants", "Надеть рубашку + штаны", function()
		local a = Av.setClothes("Shirt", shirt.Text)
		local b = Av.setClothes("Pants", pants.Text)
		UI.toast((a or b) and "Clothes applied" or "Enter a valid ID", (a or b) and nil or "bad")
	end, 38)
	local acc = UI.input(page, "Accessory ID", "ID аксессуара", "hat / glasses / hair asset id", function() end)
	UI.button(page, "Add accessory", "Добавить аксессуар", function()
		Av.addAccessory(acc.Text, function(ok) UI.toast(ok and "Accessory added" or "Could not load accessory (executor needed)", ok and nil or "bad") end)
	end, 38)
	UI.toggle(page, "Hide my current hair / hats", "Скрыть мои волосы / шапки", false, function(v) Av.hideStock(v) end)
	UI.button(page, "Remove added accessories", "Убрать добавленные аксессуары", function() Av.clearAdded() end, 38)
	UI.divider(page)
	UI.section(page, "SAVE / CATALOG", "СОХРАНИТЬ / КАТАЛОГ")
	local nameBox = UI.input(page, "Avatar name", "Имя аватара", "My avatar", function() end)
	local grid = U.new("Frame", {Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = UI.order(page) + 2}, page)
	U.new("UIGridLayout", {CellSize = UDim2.new(0.5, -5, 0, 84), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder}, grid)
	local function refresh()
		for _, ch in ipairs(grid:GetChildren()) do if ch:IsA("GuiButton") then ch:Destroy() end end
		for i, a in ipairs(Av.saved) do
			local card = U.new("TextButton", {Text = "", AutoButtonColor = false, BorderSizePixel = 0, LayoutOrder = i}, grid)
			UI.r(card, "BackgroundColor3", "el")
			U.corner(card, 12)
			local img = U.new("ImageLabel", {Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(10, 12), BackgroundColor3 = a.skin and U.t2c(a.skin) or RGB(60, 64, 80), BorderSizePixel = 0,
				Image = a.kind == "user" and Av.thumb(a.id) or ""}, card)
			U.corner(img, 10)
			local nm = U.new("TextLabel", {Size = UDim2.new(1, -90, 0, 40), Position = UDim2.fromOffset(78, 12), BackgroundTransparency = 1, Text = a.name, Font = Enum.Font.GothamBold, TextSize = 13,
				TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top}, card)
			UI.r(nm, "TextColor3", "text")
			local tg = U.new("TextLabel", {Size = UDim2.new(1, -90, 0, 14), Position = UDim2.fromOffset(78, 54), BackgroundTransparency = 1, Text = a.kind == "user" and "PLAYER" or "CUSTOM", Font = Enum.Font.GothamMedium, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left}, card)
			UI.r(tg, "TextColor3", "sub")
			card.MouseButton1Click:Connect(function() task.spawn(function() local ok = Av.applySaved(a) UI.toast(ok and a.name or "failed", ok and nil or "bad") end) end)
			local d = U.new("TextButton", {Size = UDim2.fromOffset(22, 22), Position = UDim2.new(1, -28, 0, 6), BackgroundColor3 = RGB(190, 45, 45), Text = "x", TextColor3 = RGB(255, 255, 255), Font = Enum.Font.GothamBold, TextSize = 12, AutoButtonColor = true}, card)
			U.corner(d, 7)
			d.MouseButton1Click:Connect(function() Av.delete(a.name) refresh() end)
		end
	end
	UI.button(page, "Save current avatar", "Сохранить текущий аватар", function()
		local nm = nameBox.Text ~= "" and nameBox.Text or ("Avatar " .. (#Av.saved + 1))
		Av.save(nm) refresh() UI.toast("Saved: " .. nm)
	end, 38)
	refresh()
end

---------------------------------------------------------------- Creator (3D-редактор пресета)
local Cr = {}
Hub.Creator = Cr
function Cr.open()
	if Cr.win then Cr.win.root:Destroy() Cr.win = nil end
	local win = UI.window({name = "GIGACreator", title = "PRESET CREATOR", sub = "3D editor", w = 820, h = 520, beta = Hub.kind == "beta", noSide = true})
	Cr.win = win
	local page = win.addTab("main", "Editor", "Редактор", "✎")
	page.Visible = false
	local body = U.new("Frame", {Size = UDim2.new(1, -16, 1, -80), Position = UDim2.fromOffset(8, 72), BackgroundTransparency = 1}, win.root)
	-- левая колонка
	local left = U.new("Frame", {Size = UDim2.new(0, 286, 1, 0), BackgroundTransparency = 1}, body)
	local listBox = U.new("ScrollingFrame", {Size = UDim2.new(1, 0, 0, 190), BackgroundTransparency = 0, BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y}, left)
	UI.r(listBox, "BackgroundColor3", "side")
	U.corner(listBox, 12)
	U.new("UIListLayout", {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder}, listBox)
	U.new("UIPadding", {PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 8), PaddingBottom = UDim.new(0, 6)}, listBox)
	local ed = U.new("ScrollingFrame", {Size = UDim2.new(1, 0, 1, -198), Position = UDim2.fromOffset(0, 198), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y}, left)
	U.new("UIListLayout", {Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder}, ed)
	-- правая: viewport
	local right = U.new("Frame", {Size = UDim2.new(1, -296, 1, 0), Position = UDim2.fromOffset(296, 0), BackgroundTransparency = 1}, body)
	local vp = VP.new(right, UDim2.new(1, 0, 1, -44))
	local bottom = U.new("Frame", {Size = UDim2.new(1, 0, 0, 38), Position = UDim2.new(0, 0, 1, -38), BackgroundTransparency = 1}, right)

	local draft = {name = "My Preset", slot = {}, cat = {}, rainbow = {}}
	local selSlot, rows = nil, {}
	local live = false
	local rig = Reg.currentRig()
	local function setRig(r)
		rig = r
		vp:load(r)
		for _, c in ipairs(listBox:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
		rows = {}
		if not r then return end
		-- только реально существующие и видимые детали (группы по имени)
		for i, s in ipairs(r.slots) do
			local b = U.new("TextButton", {Size = UDim2.new(1, 0, 0, 28), AutoButtonColor = false, Text = "", BorderSizePixel = 0, LayoutOrder = i}, listBox)
			UI.r(b, "BackgroundColor3", "el")
			U.corner(b, 8)
			local dotc = U.new("Frame", {Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(8, 7), BackgroundColor3 = (r.orig[s.parts[1]] or {}).Color or RGB(128, 128, 128), BorderSizePixel = 0}, b)
			U.corner(dotc, 7)
			local nl = U.new("TextLabel", {Size = UDim2.new(1, -70, 1, 0), Position = UDim2.fromOffset(30, 0), BackgroundTransparency = 1, Text = s.name, Font = Enum.Font.GothamMedium, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd}, b)
			UI.r(nl, "TextColor3", "text")
			local cn = U.new("TextLabel", {Size = UDim2.fromOffset(34, 28), Position = UDim2.new(1, -38, 0, 0), BackgroundTransparency = 1, Text = "x" .. #s.parts, Font = Enum.Font.Gotham, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Right}, b)
			UI.r(cn, "TextColor3", "sub")
			rows[s.name] = {btn = b, dot = dotc}
			b.MouseButton1Click:Connect(function() Cr.select(s.name) end)
		end
	end

	-- панель редактирования выбранной детали
	local edTitle = U.new("TextLabel", {Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 1}, ed)
	UI.r(edTitle, "TextColor3", "sub")
	local function cur() return draft.slot[selSlot] end
	local function ensureSlot() draft.slot[selSlot] = draft.slot[selSlot] or {} return draft.slot[selSlot] end
	local function pushSlot()
		local s = draft.slot[selSlot]
		if not s then return end
		vp:colorSlot(selSlot, s.c and U.t2c(s.c) or nil, s.m and Enum.Material[s.m] or nil)
		vp:hideSlot(selSlot, s.h == true)
		if rows[selSlot] and s.c then rows[selSlot].dot.BackgroundColor3 = U.t2c(s.c) end
		if live then
			Hub.look.slot[selSlot] = {c = s.c and U.t2c(s.c) or nil, m = s.m and Enum.Material[s.m] or nil, h = s.h, tex = (Hub.look.slot[selSlot] or {}).tex}
			Paint.refresh()
		end
	end
	local colorHolder = U.new("Frame", {Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = 2}, ed)
	local cRow = UI.colorRow(colorHolder, "Part color", "Цвет детали", function() local s = cur() return s and s.c and U.t2c(s.c) or RGB(255, 255, 255) end, function(c)
		if not selSlot then UI.toast("select a part first", "bad") return end
		ensureSlot().c = U.c2t(c) pushSlot()
	end)
	colorHolder.Size = UDim2.new(1, 0, 0, 42)
	local mHolder = U.new("Frame", {Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = 3}, ed)
	local mCyc = UI.cycle(mHolder, "Material", "Материал", MATS, "", function(v)
		if not selSlot then return end
		ensureSlot().m = v ~= "" and v or nil pushSlot()
	end)
	local hHolder = U.new("Frame", {Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = 3.5}, ed)
	local hTog = UI.toggle(hHolder, "Hide part (delete)", "Скрыть деталь (удалить)", false, function(v)
		if not selSlot then UI.toast("select a part first", "bad") return end
		ensureSlot().h = v or nil pushSlot()
	end)
	local url, face, tmode = "", "Top", "Image"
	local uHolder = U.new("Frame", {Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = 4}, ed)
	local urlBox = UI.input(uHolder, "Image URL", "URL картинки", "PNG / JPG link", function(t) url = t end)
	local modeHolder = U.new("Frame", {Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = 4.5}, ed)
	UI.cycle(modeHolder, "Texture mode", "Режим текстуры", {opt("Image", "Image (any part)", "Картинка (любая деталь)"), opt("Decal", "Decal", "Декаль"), opt("UV", "UV (mesh)", "UV (меш)")}, "Image", function(v) tmode = v end)
	local fHolder = U.new("Frame", {Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1, LayoutOrder = 5}, ed)
	local fo = {}
	for _, f in ipairs(Hub.FACES) do fo[#fo + 1] = opt(f, f) end
	UI.cycle(fHolder, "Face", "Грань", fo, "Top", function(v) face = v end)
	local bHolder = U.new("Frame", {Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, LayoutOrder = 6}, ed)
	U.new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6)}, bHolder)
	local function small(en, ru, cb, parent, w)
		local b = U.new("TextButton", {Size = UDim2.new(w or 0.5, -3, 1, 0), AutoButtonColor = true, Font = Enum.Font.GothamBold, TextSize = 11, BorderSizePixel = 0}, parent)
		UI.r(b, "BackgroundColor3", "acc")
		UI.r(b, "TextColor3", "accText")
		UI.tx(b, en, ru)
		U.corner(b, 10)
		b.MouseButton1Click:Connect(cb)
		return b
	end
	small("APPLY IMAGE", "НАЛОЖИТЬ КАРТИНКУ", function()
		if not selSlot then UI.toast("select a part first", "bad") return end
		url = urlBox.Text
		local spec = {url = url, face = face, mode = tmode}
		ensureSlot().tex = {url = url, face = face, mode = tmode}
		Tex.setSlot(selSlot, spec, function(ok, err) UI.toast(ok and "Image applied to scooter" or (err or "error"), ok and nil or "bad") end)
	end, bHolder)
	small("REMOVE", "УБРАТЬ", function() if selSlot then ensureSlot().tex = nil Tex.setSlot(selSlot, nil) end end, bHolder)
	local rHolder = U.new("Frame", {Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, LayoutOrder = 7}, ed)
	small("RANDOM COLORS", "СЛУЧАЙНЫЕ ЦВЕТА", function()
		if not rig then return end
		local sk = Sk.random()
		for _, sl in ipairs(rig.slots) do
			local cc = sk.cat[sl.cat] or sk.cat.other
			draft.slot[sl.name] = draft.slot[sl.name] or {}
			draft.slot[sl.name].c = cc.c
			local keep = selSlot
			selSlot = sl.name pushSlot() selSlot = keep
		end
		if selSlot then Cr.select(selSlot) end
		UI.toast(sk.name)
	end, rHolder, 1)

	function Cr.select(name)
		selSlot = name
		for n, r in pairs(rows) do U.tween(r.btn, 0.15, {BackgroundColor3 = n == name and TH.elh or TH.el}) end
		edTitle.Text = "  " .. name
		local s = draft.slot[name]
		cRow.set(s and s.c and U.t2c(s.c) or RGB(255, 255, 255))
		mCyc.set(s and s.m or "")
		hTog.set(s and s.h == true or false)
		-- мигнуть деталями во вьюпорте
		local sl = rig and rig.slotMap[name]
		if sl then for _, p in ipairs(sl.parts) do local cl = vp.map[p] if cl then local oc = cl.Color cl.Color = RGB(255, 255, 255) task.delay(0.18, function() if cl.Parent then cl.Color = (s and s.c) and U.t2c(s.c) or oc end end) end end end
	end
	vp.onPick = function(p) if p and rig and rows[p.Name] then Cr.select(p.Name) end end

	-- нижняя панель: самокат, live, имя, сохранить
	U.new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6)}, bottom)
	local scIdx = 1
	local avail = Reg.list()
	small("SCOOTER: AUTO", "САМОКАТ: АВТО", function()
		avail = Reg.list()
		if #avail == 0 then UI.toast("no scooters found", "bad") return end
		scIdx = scIdx % (#avail + 1) + 1
		Reg.override = (scIdx > 1) and avail[scIdx - 1] or nil
		Reg.current = Reg.find()
		setRig(Reg.currentRig())
		Cr.select(nil)
		UI.toast(scIdx > 1 and avail[scIdx - 1].Name or "Auto")
	end, bottom, 0.27)
	local liveBtn
	liveBtn = small("LIVE: OFF", "LIVE: ВЫКЛ", function()
		live = not live
		liveBtn.Text = (Hub.lang == "ru" and (live and "LIVE: ВКЛ" or "LIVE: ВЫКЛ")) or (live and "LIVE: ON" or "LIVE: OFF")
		if live then for n, _ in pairs(draft.slot) do local keep = selSlot selSlot = n pushSlot() selSlot = keep end end
	end, bottom, 0.18)
	local nameBox = U.new("TextBox", {Size = UDim2.new(0.3, -3, 1, 0), Text = draft.name, PlaceholderText = "name", ClearTextOnFocus = false, Font = Enum.Font.GothamMedium, TextSize = 12, BorderSizePixel = 0}, bottom)
	UI.r(nameBox, "BackgroundColor3", "el")
	UI.r(nameBox, "TextColor3", "text")
	U.corner(nameBox, 10)
	nameBox.FocusLost:Connect(function() draft.name = nameBox.Text end)
	small("SAVE", "СОХРАНИТЬ", function()
		draft.name = nameBox.Text ~= "" and nameBox.Text or "My Preset"
		local s = Sk.capture(draft.name)
		for k, v in pairs(draft.slot) do s.slot[k] = {c = v.c, m = v.m, tex = v.tex, h = v.h} end
		Sk.saveUser(s)
		if Hub.refreshSkins then Hub.refreshSkins() end
		if Hub.refreshPresets then Hub.refreshPresets() end
		UI.toast("Saved: " .. s.name)
	end, bottom, 0.2)
	setRig(rig)
	if not rig then UI.toast("No scooter found — get on / near a Kukirin", "bad") end
	win.onHide = function() task.delay(0.35, function() if win.root.Parent and not win.open then win.root:Destroy() end end) end
	win.show()
end

---------------------------------------------------------------- menu builder
local Menu = {}
Hub.Menu = Menu
local function buildMenu(kind)
	if Hub.menu then Hub.menu.destroy() Hub.menu = nil end
	Hub.syncers, W.listeners = {}, {}
	Hub.kind = kind
	local beta = kind == "beta"
	if beta then UI.setAccent(RGB(110, 130, 255), RGB(200, 90, 255))
	elseif Hub.settings.accent then local c = U.t2c(Hub.settings.accent) UI.setAccent(c, c)
	else UI.setAccent(RGB(255, 255, 255), RGB(255, 255, 255)) end
	local win = UI.window({name = "GIGAMenu", title = "CUSTOM KUKIRIN", sub = beta and ("BETA  •  " .. player.DisplayName) or "DEFAULT  •  by ", w = beta and 800 or 680, h = beta and 560 or 500, beta = beta})
	Hub.menu = win
	-- переключатель версий
	local sw = U.new("Frame", {Size = UDim2.fromOffset(176, 30), Position = UDim2.new(1, -240, 0, 17), BorderSizePixel = 0}, win.bar)
	UI.r(sw, "BackgroundColor3", "side")
	U.corner(sw, 10)
	local sst = U.new("UIStroke", {Thickness = 1, Transparency = 0.4}, sw)
	UI.r(sst, "Color", "stroke")
	for i, k in ipairs({"default", "beta"}) do
		local on = k == kind
		local b = U.new("TextButton", {Size = UDim2.new(0.5, -4, 1, -6), Position = UDim2.new((i - 1) * 0.5, 2, 0, 3), BorderSizePixel = 0, AutoButtonColor = false, Font = Enum.Font.GothamBold, TextSize = 11,
			Text = (k == "beta" and not Hub.isBeta()) and "BETA (locked)" or k:upper(), BackgroundTransparency = on and 0 or 1}, sw)
		UI.r(b, "BackgroundColor3", "acc")
		UI.r(b, "TextColor3", on and "accText" or "sub")
		U.corner(b, 8)
		b.MouseButton1Click:Connect(function() Hub.switch(k) end)
	end
	local tabs = beta and {
		{"dash", "Dashboard", "Панель", "", Pages.dash}, {"rainbow", "Rainbow", "Радуга", "", Pages.rainbow}, {"autow", "Auto Wheelie", "Авто-вилли", "", Pages.autowheelie},
		{"lab", "Test Lab", "Лаборатория", "", Pages.lab}, {"presets", "Presets", "Пресеты", "", Pages.presets}, {"custom", "Make Custom", "Кастомизация", "", Pages.custom},
		{"details", "Custom Details", "Кастом детали", "", Pages.details}, {"glow", "UnderGlow", "Подсветка", "", Pages.glow}, {"shader", "Shaders", "Шейдеры", "", Pages.shader},
		{"skins", "Skins (avatar)", "Скины (аватар)", "", Pages.skins}, {"settings", "Settings", "Настройки", "", Pages.settings},
	} or {
		{"presets", "Presets", "Пресеты", "", Pages.presets}, {"custom", "Make Custom", "Кастомизация", "", Pages.custom}, {"details", "Custom Details", "Кастом детали", "", Pages.details},
		{"glow", "UnderGlow", "Подсветка", "", Pages.glow}, {"shader", "Shaders", "Шейдеры", "", Pages.shader}, {"skins", "Skins (avatar)", "Скины (аватар)", "", Pages.skins}, {"settings", "Settings", "Настройки", "", Pages.settings},
	}
	for _, t in ipairs(tabs) do
		local page = win.addTab(t[1], t[2], t[3], t[4])
		local ok, err = pcall(t[5], page, win)
		if not ok then warn("[GIGAHUB] page " .. t[1] .. ": " .. tostring(err)) end
	end
	win.select(tabs[1][1])
	return win
end
function Hub.switch(kind)
	if kind == Hub.kind then return end
	if kind == "beta" and not Hub.isBeta() then UI.toast("BETA access denied — your nickname is not on the list", "bad") return end
	local old = Hub.menu
	if old then old.hide() end
	task.wait(0.26)
	local win = buildMenu(kind)
	win.show()
	Hub.settings.last = kind
	Store.store = nil
	Store.save("settings", Hub.settings)
	UI.toast(kind == "beta" and "BETA version" or "DEFAULT version")
end
function Hub.toggleMenu()
	if not Hub.menu then return end
	if Hub.menu.open then Hub.menu.hide() else Hub.menu.show() end
end

---------------------------------------------------------------- loader (интро + выбор версии)
local Loader = {}
function Loader.run()
	local gui = U.new("ScreenGui", {Name = "GIGALoader", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling}, U.guiParent())
	Hub.onClean(function() gui:Destroy() end)
	local blur = U.new("BlurEffect", {Name = "GIGA_Blur", Size = 0}, Lighting)
	Hub.onClean(function() blur:Destroy() end)
	U.tween(blur, 0.8, {Size = 22})
	local bg = U.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundColor3 = RGB(6, 7, 11), BackgroundTransparency = 1, BorderSizePixel = 0}, gui)
	local bgg = U.new("UIGradient", {Color = ColorSequence.new({ColorSequenceKeypoint.new(0, RGB(20, 18, 40)), ColorSequenceKeypoint.new(1, RGB(5, 8, 16))}), Rotation = 45}, bg)
	U.tween(bg, 0.7, {BackgroundTransparency = 0.12})
	local A1, A2 = RGB(110, 130, 255), RGB(200, 90, 255)
	-- частицы-огоньки
	local sparks = {}
	for i = 1, 26 do
		local s = U.new("Frame", {Size = UDim2.fromOffset(3, 3), Position = UDim2.fromScale(math.random(), math.random()), BackgroundColor3 = HSV(math.random() * 0.2 + 0.6, 0.6, 1), BackgroundTransparency = 0.5, BorderSizePixel = 0}, bg)
		U.corner(s, 2)
		sparks[i] = {f = s, v = 0.02 + math.random() * 0.05, x = s.Position.X.Scale}
	end
	local conn = RS.RenderStepped:Connect(function(dt)
		bgg.Rotation = (os.clock() * 8) % 360
		for _, s in ipairs(sparks) do
			local y = s.f.Position.Y.Scale - s.v * dt
			if y < -0.02 then y = 1.02 s.x = math.random() end
			s.f.Position = UDim2.fromScale(s.x + math.sin(os.clock() + s.v * 40) * 0.01, y)
		end
	end)
	local center = U.new("Frame", {AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(640, 380), BackgroundTransparency = 1}, bg)
	-- кольцо-спиннер
	local ringBox = U.new("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.fromOffset(84, 84), BackgroundTransparency = 1}, center)
	local ring = U.new("Frame", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1}, ringBox)
	U.corner(ring, 42)
	local rst = U.new("UIStroke", {Thickness = 5, Transparency = 1}, ring)
	local rg = U.new("UIGradient", {Color = ColorSequence.new({ColorSequenceKeypoint.new(0, A1), ColorSequenceKeypoint.new(0.5, A2), ColorSequenceKeypoint.new(1, A1)})}, rst)
	U.tween(rst, 0.6, {Transparency = 0})
	local g1 = U.new("TextLabel", {Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "K", Font = Enum.Font.GothamBlack, TextSize = 36, TextColor3 = RGB(255, 255, 255), TextTransparency = 1}, ringBox)
	U.tween(g1, 0.6, {TextTransparency = 0})
	conn:Disconnect()
	conn = RS.RenderStepped:Connect(function(dt)
		bgg.Rotation = (os.clock() * 8) % 360
		rg.Rotation = (os.clock() * 200) % 360
		for _, s in ipairs(sparks) do
			local y = s.f.Position.Y.Scale - s.v * dt
			if y < -0.02 then y = 1.02 s.x = math.random() end
			s.f.Position = UDim2.fromScale(s.x + math.sin(os.clock() + s.v * 40) * 0.01, y)
		end
	end)
	Hub.onClean(function() conn:Disconnect() end)
	-- буквы
	local word = U.new("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 96), Size = UDim2.fromOffset(560, 70), BackgroundTransparency = 1}, center)
	U.new("UIListLayout", {FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center}, word)
	local letters = {}
	local WORD = "CUSTOM KUKIRIN"
	for i = 1, #WORD do
		local ch = WORD:sub(i, i)
		local l = U.new("TextLabel", {Size = UDim2.fromOffset(ch == " " and 18 or 34, 70), BackgroundTransparency = 1, Text = ch, Font = Enum.Font.GothamBlack, TextSize = 46, TextColor3 = RGB(255, 255, 255), TextTransparency = 1, LayoutOrder = i}, word)
		local gr = U.new("UIGradient", {Color = ColorSequence.new(A1, A2), Rotation = 90}, l)
		letters[i] = l
	end
	task.spawn(function()
		for _, l in ipairs(letters) do U.tween(l, 0.4, {TextTransparency = 0}, Enum.EasingStyle.Back) task.wait(0.07) end
	end)
	local line = U.new("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 172), Size = UDim2.fromOffset(0, 3), BorderSizePixel = 0, BackgroundColor3 = RGB(255, 255, 255)}, center)
	U.new("UIGradient", {Color = ColorSequence.new(A1, A2)}, line)
	U.corner(line, 2)
	task.wait(0.55)
	U.tween(line, 0.7, {Size = UDim2.fromOffset(300, 3)})
	local status = U.new("TextLabel", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 190), Size = UDim2.fromOffset(420, 20), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13, TextColor3 = RGB(160, 165, 190), Text = ""}, center)
	local barBg = U.new("Frame", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 220), Size = UDim2.fromOffset(300, 6), BackgroundColor3 = RGB(30, 32, 46), BorderSizePixel = 0}, center)
	U.corner(barBg, 3)
	local fill = U.new("Frame", {Size = UDim2.fromScale(0, 1), BackgroundColor3 = RGB(255, 255, 255), BorderSizePixel = 0}, barBg)
	U.corner(fill, 3)
	local fg = U.new("UIGradient", {Color = ColorSequence.new(A1, A2)}, fill)
	local shine = U.new("Frame", {Size = UDim2.fromOffset(40, 6), BackgroundColor3 = RGB(255, 255, 255), BackgroundTransparency = 0.7, BorderSizePixel = 0, ZIndex = 2}, barBg)
	U.corner(shine, 3)
	local sc2 = RS.RenderStepped:Connect(function() shine.Position = UDim2.new(((os.clock() * 0.9) % 1.3) - 0.15, 0, 0, 0) end)
	Hub.onClean(function() sc2:Disconnect() end)
	local steps = {
		{"Reading save data…", "Читаю сохранения…", function() Hub.settings = Store.load("settings", Hub.settings) Hub.lang = Hub.settings.lang or "en" Sk.user = Store.load("skins", Sk.user) end},
		{"Scanning scooters…", "Сканирую самокаты…", function() Reg.current = Reg.find() Reg.currentRig() end},
		{"Building modules…", "Собираю модули…", function() Fx.rebuildAll() end},
		{"Preparing interface…", "Готовлю интерфейс…", function() UI.init() end},
		{"Ready", "Готово", function() end},
	}
	for i, s in ipairs(steps) do
		status.Text = (Hub.lang == "ru") and s[2] or s[1]
		pcall(s[3])
		U.tween(fill, 0.45, {Size = UDim2.fromScale(i / #steps, 1)})
		task.wait(0.45)
	end
	task.wait(0.2)
	U.tween(status, 0.3, {TextTransparency = 1})
	U.tween(barBg, 0.3, {BackgroundTransparency = 1})
	U.tween(fill, 0.3, {BackgroundTransparency = 1})
	U.tween(shine, 0.3, {BackgroundTransparency = 1})
	task.wait(0.3)
	U.tween(center, 0.6, {Position = UDim2.new(0.5, 0, 0.5, -100)})
	-- выбор версии
	local choice
	local ru = Hub.lang == "ru"
	local isBeta = Hub.isBeta()
	local function card(x, title, desc, tag, locked, kind)
		local c = U.new("TextButton", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, x, 0, 215), Size = UDim2.fromOffset(280, 170), Text = "", AutoButtonColor = false, BackgroundColor3 = RGB(17, 19, 29), BorderSizePixel = 0, BackgroundTransparency = 1}, center)
		U.corner(c, 18)
		local cs = U.new("UIStroke", {Thickness = 2, Color = RGB(255, 255, 255), Transparency = 1}, c)
		local csg = U.new("UIGradient", {Color = kind == "beta" and ColorSequence.new(A1, A2) or ColorSequence.new(RGB(220, 225, 240), RGB(130, 140, 170))}, cs)
		local sca = U.new("UIScale", {Scale = 0.9}, c)
		local tl = U.new("TextLabel", {Size = UDim2.new(1, -28, 0, 34), Position = UDim2.fromOffset(18, 16), BackgroundTransparency = 1, Text = title, Font = Enum.Font.GothamBlack, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = RGB(255, 255, 255), TextTransparency = 1}, c)
		if kind == "beta" then U.new("UIGradient", {Color = ColorSequence.new(A1, A2)}, tl) end
		local tg = U.new("TextLabel", {Size = UDim2.new(1, -28, 0, 16), Position = UDim2.fromOffset(18, 52), BackgroundTransparency = 1, Text = tag, Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = locked and RGB(255, 120, 120) or RGB(130, 255, 190), TextTransparency = 1}, c)
		local ds = U.new("TextLabel", {Size = UDim2.new(1, -36, 0, 70), Position = UDim2.fromOffset(18, 78), BackgroundTransparency = 1, Text = desc, Font = Enum.Font.Gotham, TextSize = 13, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = RGB(160, 165, 190), TextTransparency = 1}, c)
		U.tween(c, 0.5, {BackgroundTransparency = locked and 0.35 or 0}) U.tween(cs, 0.5, {Transparency = locked and 0.7 or 0.15}) U.tween(sca, 0.5, {Scale = 1}, Enum.EasingStyle.Back)
		U.tween(tl, 0.5, {TextTransparency = locked and 0.4 or 0}) U.tween(tg, 0.5, {TextTransparency = 0}) U.tween(ds, 0.5, {TextTransparency = locked and 0.4 or 0})
		c.MouseEnter:Connect(function() if not locked then U.tween(sca, 0.2, {Scale = 1.05}) U.tween(cs, 0.2, {Transparency = 0}) end end)
		c.MouseLeave:Connect(function() if not locked then U.tween(sca, 0.2, {Scale = 1}) U.tween(cs, 0.2, {Transparency = 0.15}) end end)
		Hub.addUpdater(function() if c.Parent then csg.Rotation = (os.clock() * 60) % 360 end end)
		c.MouseButton1Click:Connect(function()
			if locked then UI.toast(ru and "Нет доступа к BETA — ника нет в списке" or "BETA access denied — nickname is not on the list", "bad") return end
			choice = kind
		end)
	end
	card(-150, "DEFAULT", ru and "Стабильная версия: пресеты, кастомизация частей, подсветка, скины, 3D-редактор, пружинная вилка." or "Stable build: presets, part customization, underglow, skins, 3D editor, spring fork.", ru and "● ДОСТУПНО" or "● AVAILABLE", false, "default")
	card(150, "BETA", ru and "Новое гуи + Auto Wheelie, Rainbow Kugoo, Test Lab, анимированные картинки." or "New GUI + Auto Wheelie, Rainbow Kugoo, Test Lab, animated images.", isBeta and (ru and "● ДОСТУП ОТКРЫТ" or "● ACCESS GRANTED") or (ru and "НЕТ ДОСТУПА" or "LOCKED"), not isBeta, "beta")
	local hint = U.new("TextLabel", {AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 395), Size = UDim2.fromOffset(500, 18), BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12, TextColor3 = RGB(120, 125, 150),
		Text = ru and "Версию можно сменить в любой момент в шапке меню" or "You can switch version any time in the menu header"}, center)
	while not choice do task.wait(0.05) end
	for _, d in ipairs(center:GetDescendants()) do
		if d:IsA("TextLabel") or d:IsA("TextButton") then U.tween(d, 0.35, {TextTransparency = 1}) end
		if d:IsA("Frame") or d:IsA("TextButton") then U.tween(d, 0.35, {BackgroundTransparency = 1}) end
	end
	U.tween(bg, 0.45, {BackgroundTransparency = 1})
	U.tween(blur, 0.45, {Size = 0})
	task.wait(0.5)
	gui:Destroy() blur:Destroy()
	return choice
end

---------------------------------------------------------------- boot
Hub.lang = Hub.settings.lang or "en"
task.spawn(function()
	local kind = Loader.run()
	if kind == "beta" and not Hub.isBeta() then kind = "default" end
	-- кнопка для телефона
	local mb = U.new("TextButton", {Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0, 10, 0, 64), Text = "K", Font = Enum.Font.GothamBlack, TextSize = 22, AutoButtonColor = false, ZIndex = 10}, UI.gui)
	UI.r(mb, "BackgroundColor3", "bg")
	UI.r(mb, "TextColor3", "text")
	U.corner(mb, 23)
	local ms = U.new("UIStroke", {Thickness = 2}, mb)
	UI.r(ms, "Color", "acc")
	Hub.mobileBtn = mb
	mb.MouseButton1Click:Connect(Hub.toggleMenu)
	local win = buildMenu(kind)
	win.show()
	Hub.settings.last = kind
	Store.save("settings", Hub.settings)
	UI.toast(kind == "beta" and "Custom Kukirin • BETA" or "Custom Kukirin • DEFAULT")
end)

U.connect(UIS.InputBegan, function(i, gpe)
	if gpe or i.UserInputType ~= Enum.UserInputType.Keyboard then return end
	for _, k in ipairs(CFG.MENU_KEYS) do if i.KeyCode == k then Hub.toggleMenu() return end end
	if i.KeyCode == CFG.WHEELIE_KEY then W.set(not W.on)
	elseif i.KeyCode == CFG.AUTO_WHEELIE_KEY and Hub.kind == "beta" then W.setAuto(not W.auto) end
end)
warn("[Custom Kukirin v3.1] loaded — menu: RightShift / LeftAlt | F wheelie | G auto wheelie (beta)")
