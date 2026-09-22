

local AC_VERSION = "1.2.0"
local Svc = {
	Players = game:GetService("Players"),
	RS      = game:GetService("ReplicatedStorage"),
	UIS     = game:GetService("UserInputService"),
	Http    = game:GetService("HttpService"),
}
local LP = Svc.Players.LocalPlayer
if not LP then
	Svc.Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	LP = Svc.Players.LocalPlayer
end

if getgenv().AnimeDiceAutoChange and getgenv().AnimeDiceAutoChange.Stop then
	pcall(getgenv().AnimeDiceAutoChange.Stop)
	task.wait(0.3)
end

local CFG = {
	Enabled  = true,
	Interval = 3,                -- giây/lần kiểm tra túi

	Item     = "Jackpot Spin",   -- món làm điều kiện (tên đúng như trong túi)
	Amount   = 1,                -- có >= ngần này thì đổi acc

	-- Cách đổi acc:
	--   "farmsync" = getgenv().client:ChangeToFolder(...)   [mặc định, như cũ]
	--   "api"      = POST /api/accounts/autoswap-complete   [dashboard v5]
	Backend = "farmsync",

	-- ===== Dùng cho Backend = "farmsync" =====
	FromFolder = "",             -- ID folder acc chính
	ToFolder   = "",             -- ID folder acc thay thế
	Replace    = false,          -- tham số 3 của ChangeToFolder
	-- ConfigId = "id_config_moi",  -- tham số 4, bỏ dấu -- nếu muốn đổi config

	-- ===== Dùng cho Backend = "api" =====
	-- Spec do chồng cung cấp, KHÔNG nằm trong source game.
	Api = {
		Url      = "",           -- gốc dashboard, vd "https://abc.xyz" (KHÔNG kèm /api/...)
		Key      = "",           -- ak_xxx — nên tạo key loại "Complete early only"
		AuthMode = "x-api-key",  -- "x-api-key" | "bearer"
		Username = "",           -- rỗng = tự lấy tên acc đang chơi
		Option   = 1,            -- số thứ tự rule trong Autoswap Config (#1, #2...)
		RetryEvery = 60,         -- chưa đổi được thì cứ ngần này giây gọi lại 1 lần
	},

	RetryOnFail = true,          -- FarmSync trả về false thì lượt sau thử lại
	Log = true,                  -- in ra console

	UI = {
		Enabled   = true,
		ToggleKey = Enum.KeyCode.RightAlt,
	},
}

local function isArray(t)
	return type(t) == "table" and #t > 0
end
local function mergeCfg(dst, src)
	if type(src) ~= "table" then return dst end
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" and not isArray(v) then
			mergeCfg(dst[k], v)
		else
			dst[k] = v
		end
	end
	return dst
end
mergeCfg(CFG, getgenv().AnimeDiceAutoChangeConfig)

local RT = {
	running = true,
	threads = {},
	conns   = {},
	status  = "khởi động",
	count   = 0,
	fired   = false,
	apiTries = 0,       -- đếm để in log cho dễ theo dõi, không dùng để dừng
	apiNextAt = 0,      -- mốc thời gian sớm nhất được phép gọi API lại
	log     = {},
}

local AC = {}

local function track(conn)
	if conn then table.insert(RT.conns, conn) end
	return conn
end

local function log(msg)
	local line = "[AUTOCHANGE] " .. tostring(msg)
	table.insert(RT.log, line)
	while #RT.log > 30 do table.remove(RT.log, 1) end
	if CFG.Log then print(line) end
end

local DC = nil
do
	local ok, mod = pcall(function()
		return require(Svc.RS.Framework.Features.Data.DataController)
	end)
	if ok then DC = mod else warn("[AUTOCHANGE] không require được DataController") end
end

function AC.inventory()
	if not DC then return nil end
	local ok, inv = pcall(function() return DC.Inventory() end)
	if ok and type(inv) == "table" then return inv end
	return nil
end

function AC.count(inv, name)
	if type(inv) ~= "table" or type(name) ~= "string" or name == "" then return 0 end
	local want, total = name:lower(), 0
	for _, entry in pairs(inv) do
		if type(entry) == "table" and type(entry.name) == "string" and entry.name:lower() == want then
			local amount = tonumber(entry.amount) or 0
			if amount > 0 then total = total + amount end
		end
	end
	return total
end

function AC.decide(count)
	if not CFG.Enabled then return false, "tắt" end
	if RT.fired then return false, "đã gọi đổi acc, chờ xử lý" end
	if CFG.Backend == "api" then
		local api = CFG.Api or {}
		local wait = (RT.apiNextAt or 0) - AC.now()
		if wait > 0 then
			return false, string.format("%ds nữa gọi lại API", math.ceil(wait))
		end
		if type(api.Url) ~= "string" or api.Url == "" then return false, "chưa điền Api.Url" end
		if type(api.Key) ~= "string" or api.Key == "" then return false, "chưa điền Api.Key" end
		-- spec: option = 0 chắc chắn trả 400, chặn luôn ở client cho đỡ tốn request
		if (tonumber(api.Option) or 0) < 1 then return false, "Api.Option phải >= 1" end
	else
		if type(CFG.FromFolder) ~= "string" or CFG.FromFolder == ""
			or type(CFG.ToFolder) ~= "string" or CFG.ToFolder == "" then
			return false, "chưa điền FromFolder/ToFolder"
		end
	end
	local need = math.max(1, math.floor(tonumber(CFG.Amount) or 1))
	if count < need then
		return false, string.format("chờ %s: %d/%d", tostring(CFG.Item), count, need)
	end
	return true, string.format("có %d %s", count, tostring(CFG.Item))
end

function AC.client()
	local ok, client = pcall(function() return getgenv().client end)
	if not ok or client == nil then return nil, "không thấy getgenv().client (FarmSync)" end
	local okFn, fn = pcall(function() return client.ChangeToFolder end)
	if not okFn or type(fn) ~= "function" then return nil, "client không có ChangeToFolder" end
	return client, nil
end

function AC.changeFarmSync(reason)
	local client, why = AC.client()
	if not client then
		RT.status = why
		log(why)
		return false
	end
	RT.fired = true
	log(string.format("%s -> đổi acc: %s => %s", tostring(reason),
		tostring(CFG.FromFolder), tostring(CFG.ToFolder)))
	local ok, changed = pcall(function()
		return client:ChangeToFolder(CFG.FromFolder, CFG.ToFolder, CFG.Replace == true, CFG.ConfigId)
	end)
	if not ok then
		RT.fired = false
		RT.status = "gọi ChangeToFolder lỗi"
		log("ChangeToFolder lỗi: " .. tostring(changed))
		return false
	end
	if changed then
		RT.status = "đã yêu cầu đổi acc"
		log("FarmSync nhận lệnh đổi acc")
		return true
	end
	RT.status = "FarmSync từ chối đổi"
	log("FarmSync trả về false")
	if CFG.RetryOnFail then RT.fired = false end
	return false
end


--==============================================================================
--  BACKEND "api" — POST /api/accounts/autoswap-complete
--  Spec do chồng cung cấp (dashboard v5). KHÔNG phải remote của game AnimeDice.
--==============================================================================

-- Tách ra để test offline điều khiển được thời gian.
function AC.now()
	return os.clock()
end

-- Executor nào cũng đặt tên khác nhau; dò hết rồi báo rõ nếu không có cái nào.
function AC.httpFn()
	local fn
	pcall(function() fn = (syn and syn.request) or (http and http.request) end)
	if type(fn) ~= "function" then pcall(function() fn = http_request end) end
	if type(fn) ~= "function" then pcall(function() fn = request end) end
	if type(fn) ~= "function" then return nil, "executor không có hàm request()" end
	return fn, nil
end

-- Che API key khi in log: chỉ giữ 10 ký tự đầu.
function AC.maskKey(key)
	if type(key) ~= "string" or key == "" then return "(trống)" end
	if #key <= 10 then return key end
	return key:sub(1, 10) .. "..."
end

-- Ghép URL, bỏ dấu / thừa ở cuối để không thành "//api".
function AC.apiUrl(base)
	base = tostring(base or "")
	while base:sub(-1) == "/" do base = base:sub(1, -2) end
	return base .. "/api/accounts/autoswap-complete"
end

-- HÀM THUẦN: dịch (status, body) -> quyết định. Tách riêng để test offline.
-- Trả về: done, retry, dead, msg
function AC.apiOutcome(status, body)
	status = tonumber(status) or 0
	if status == 403 then
		return false, false, true, "403 — thiếu hoặc sai API key"
	end
	if status == 404 then
		return false, false, true, "404 — dashboard không có account tên này"
	end
	if status == 400 then
		return false, true, false, "400 — acc chưa gán device, hoặc Option = 0"
	end
	if status < 200 or status >= 300 then
		return false, true, false, status .. " — máy chủ/mạng lỗi"
	end
	local ok, data = pcall(function() return Svc.Http:JSONDecode(body) end)
	if not ok or type(data) ~= "table" then
		return false, true, false, "không đọc được JSON trả về"
	end
	local outcome = tostring(data.outcome)
	if outcome == "swapped" then
		return true, false, false, "swapped — acc thay thế: " .. tostring(data.replacement)
	end
	if outcome == "moved" then
		return true, false, false, "moved — acc đã ra, không có acc thay thế"
	end
	if outcome == "not_fired" then
		-- spec: an toàn để thử lại
		return false, true, false, "not_fired — sai số rule / rule đang pause / không có acc trống"
	end
	return false, true, false, "outcome lạ: " .. outcome
end

function AC.changeApi(reason)
	local api = CFG.Api or {}
	local fn, why = AC.httpFn()
	if not fn then
		RT.status = why
		log(why)
		return false
	end

	local user = api.Username
	if type(user) ~= "string" or user == "" then user = LP.Name end
	local option = math.max(1, math.floor(tonumber(api.Option) or 1))
	local url = AC.apiUrl(api.Url)

	local headers = { ["Content-Type"] = "application/json" }
	if tostring(api.AuthMode):lower() == "bearer" then
		headers["Authorization"] = "Bearer " .. tostring(api.Key)
	else
		headers["X-Api-Key"] = tostring(api.Key)
	end

	RT.fired = true
	RT.apiTries = (RT.apiTries or 0) + 1
	log(string.format("%s -> POST %s | user=%s option=%d key=%s",
		tostring(reason), url, user, option, AC.maskKey(api.Key)))

	local okCall, res = pcall(function()
		return fn({
			Url = url,
			Method = "POST",
			Headers = headers,
			Body = Svc.Http:JSONEncode({ username = user, option = option }),
		})
	end)
	if not okCall or type(res) ~= "table" then
		RT.fired = false
		RT.status = "gọi request() lỗi"
		log("request() lỗi: " .. tostring(res))
		return false
	end

	local done, _, dead, msg = AC.apiOutcome(res.StatusCode, res.Body)
	log("API: " .. msg)
	if done then
		RT.status = "đã đổi acc — " .. msg
		return true
	end
	-- Chưa đổi được thì cứ hẹn giờ gọi lại, không bỏ cuộc.
	-- 403/404 thì thử lại cũng không tự hết, nhưng vẫn gọi theo ý chồng;
	-- chỉ in log to cho dễ thấy mà đi sửa key/username.
	if dead then
		log("CHÚ Ý: lỗi này không tự hết. Kiểm tra Api.Key và Api.Username trên dashboard.")
	end
	local every = math.max(5, tonumber(api.RetryEvery) or 60)
	RT.fired = false
	RT.apiNextAt = AC.now() + every
	RT.status = string.format("lần %d hỏng (%s), %ds nữa thử lại", RT.apiTries, msg, every)
	return false
end

-- Router: chọn backend theo config.
function AC.change(reason)
	if CFG.Backend == "api" then return AC.changeApi(reason) end
	return AC.changeFarmSync(reason)
end

function AC.Force()
	RT.fired, RT.apiTries, RT.apiNextAt = false, 0, 0
	return AC.change("gọi tay")
end

function AC.tick()
	if not CFG.Enabled then RT.status = "tắt" return end
	local inv = AC.inventory()
	if not inv then RT.status = "chờ dữ liệu túi" return end
	RT.count = AC.count(inv, CFG.Item)
	local go, why = AC.decide(RT.count)
	RT.status = why
	if go then AC.change(why) end
end

local UI = {}

local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

function UI.build()
	if not CFG.UI.Enabled then return end
	local parent = LP:WaitForChild("PlayerGui")
	local ok, hui = pcall(function() return gethui and gethui() end)
	if ok and hui then parent = hui end
	local old = parent:FindFirstChild("AnimeDiceAutoChangeGui")
	if old then old:Destroy() end

	local sg = mk("ScreenGui", {
		Name = "AnimeDiceAutoChangeGui", ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 9998,
	})
	pcall(function() sg.Parent = parent end)
	if not sg.Parent then sg.Parent = LP:WaitForChild("PlayerGui") end
	UI.gui = sg

	local main = mk("Frame", {
		Name = "Main", Size = UDim2.new(0, 330, 0, 118),
		Position = UDim2.new(0.5, -165, 0, 24),
		BackgroundColor3 = Color3.fromRGB(16, 18, 24), BorderSizePixel = 0,
	}, sg)
	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, main)
	mk("UIStroke", { Color = Color3.fromRGB(255, 170, 60), Thickness = 1.5,
		Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, main)
	UI.main = main

	local head = mk("Frame", { Size = UDim2.new(1, 0, 0, 30),
		BackgroundColor3 = Color3.fromRGB(23, 26, 34), BorderSizePixel = 0 }, main)
	mk("UICorner", { CornerRadius = UDim.new(0, 10) }, head)
	mk("TextLabel", {
		Size = UDim2.new(1, -80, 1, 0), Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13,
		TextColor3 = Color3.fromRGB(255, 200, 120), TextXAlignment = Enum.TextXAlignment.Left,
		Text = "AUTO CHANGE · v" .. AC_VERSION,
	}, head)
	local btnHide = mk("TextButton", {
		Size = UDim2.new(0, 60, 0, 20), Position = UDim2.new(1, -68, 0, 5),
		BackgroundColor3 = Color3.fromRGB(28, 32, 42), BorderSizePixel = 0,
		Font = Enum.Font.GothamBold, TextSize = 11,
		TextColor3 = Color3.fromRGB(235, 240, 250), Text = "Ẩn",
	}, head)
	mk("UICorner", { CornerRadius = UDim.new(0, 6) }, btnHide)
	btnHide.Activated:Connect(function() main.Visible = false end)

	local function row(y, label)
		mk("TextLabel", {
			Size = UDim2.new(0, 110, 0, 18), Position = UDim2.new(0, 12, 0, y),
			BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12,
			TextColor3 = Color3.fromRGB(150, 158, 175),
			TextXAlignment = Enum.TextXAlignment.Left, Text = label,
		}, main)
		return mk("TextLabel", {
			Size = UDim2.new(1, -130, 0, 18), Position = UDim2.new(0, 120, 0, y),
			BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12,
			TextColor3 = Color3.fromRGB(235, 240, 250),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Text = "-",
		}, main)
	end

	UI.itemLabel   = row(38, "Đang canh")
	UI.countLabel  = row(58, "Trong túi")
	UI.statusLabel = row(78, "Trạng thái")

	local btnForce = mk("TextButton", {
		Size = UDim2.new(0, 96, 0, 20), Position = UDim2.new(1, -108, 1, -26),
		BackgroundColor3 = Color3.fromRGB(200, 120, 40), BorderSizePixel = 0,
		Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.new(1, 1, 1),
		Text = "ĐỔI NGAY",
	}, main)
	mk("UICorner", { CornerRadius = UDim.new(0, 6) }, btnForce)
	btnForce.Activated:Connect(function() task.spawn(AC.Force) end)

	local drag, startPos, startInput = false, nil, nil
	head.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			drag, startPos, startInput = true, main.Position, input.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then drag = false end
			end)
		end
	end)
	track(Svc.UIS.InputChanged:Connect(function(input)
		if not drag then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local d = input.Position - startInput
			main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))

	track(Svc.UIS.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == CFG.UI.ToggleKey then main.Visible = not main.Visible end
	end))
end

function UI.refresh()
	if not UI.main or not UI.main.Visible then return end
	if UI.itemLabel then UI.itemLabel.Text = tostring(CFG.Item) .. " x" .. tostring(CFG.Amount) end
	if UI.countLabel then UI.countLabel.Text = tostring(RT.count) end
	if UI.statusLabel then UI.statusLabel.Text = tostring(RT.status) end
end


UI.build()
log("v" .. AC_VERSION .. " chạy — " .. LP.Name .. " | canh " .. tostring(CFG.Item))
if not DC then RT.status = "không đọc được túi (DataController)" end

table.insert(RT.threads, task.spawn(function()
	while RT.running do
		local ok, err = pcall(AC.tick)
		if not ok then
			RT.status = "lỗi: " .. tostring(err)
			log("LỖI: " .. tostring(err))
			task.wait(2)
		end
		task.wait(math.max(1, tonumber(CFG.Interval) or 3))
	end
end))

table.insert(RT.threads, task.spawn(function()
	while RT.running do
		pcall(UI.refresh)
		task.wait(0.5)
	end
end))

getgenv().AnimeDiceAutoChange = {
	Version = AC_VERSION,
	CFG = CFG,
	RT  = RT,
	AC  = AC,
	Force = AC.Force,
	Stop = function()
		if not RT.running then return end
		RT.running = false
		for _, th in ipairs(RT.threads) do pcall(task.cancel, th) end
		for _, c in ipairs(RT.conns) do pcall(function() c:Disconnect() end) end
		if UI.gui then pcall(function() UI.gui:Destroy() end) end
		RT.threads, RT.conns = {}, {}
		print("[AUTOCHANGE] đã dừng.")
	end,
}

print("[AUTOCHANGE] v" .. AC_VERSION .. " sẵn sàng. Alt phải để ẩn/hiện bảng.")
