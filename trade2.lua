--==============================================================================
--  ALIMIDAI AUTO TRADE  ·  v2.0.0  ·  MỘT file duy nhất
--
--  Tự chia vai theo tên acc:
--     LP.Name == MainAcc  ->  NHẬN  (đồng ý trade, KHÔNG đưa gì đi)
--     tên khác            ->  GỬI   (thấy MainAcc trong server -> mời + đưa hết đồ)
--
--  Bản v2 nhận NHIỀU acc GỬI cùng lúc: acc NHẬN xếp hàng từng người một,
--  acc nào xong trước thì launcher thả acc mới vào ngay.
--
--  ---------------------------------------------------------------------------
--  DÙNG ĐỘC LẬP (upload file này lên GitHub rồi loadstring):
--
--      getgenv().AlimidaiConfig = {
--          MainAcc = "TenAccNhan",          -- BẮT BUỘC
--          Items   = { "Jackpot Spin" },    -- gõ thiếu cũng khớp: "gem" -> "Gems"
--      }
--      loadstring(game:HttpGet(
--          "https://raw.githubusercontent.com/USER/REPO/main/trade.lua"))()
--
--  Mọi khoá config + giá trị mặc định nằm ở bảng DEFAULTS ngay bên dưới.
--  Chạy lại loadstring lần nữa sẽ tự tắt bản cũ rồi khởi động lại.
--
--  ---------------------------------------------------------------------------
--  DÙNG VỚI LAUNCHER (main.py):
--
--  main.py chèn `local SETTINGS_JSON = [[...]]` lên đầu chunk rồi bơm vào đúng
--  1 PID. Có biến đó -> chạy "chế độ coordinator" (báo HTTP về launcher).
--  Không có -> chạy độc lập bằng getgenv().
--==============================================================================

local TR_VERSION = "2.0.0"

local Http    = game:GetService("HttpService")
local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local UIS     = game:GetService("UserInputService")

local env = getgenv()

-- Launcher chèn biến này thành một local ở đầu chunk. Chạy độc lập thì nó là
-- global chưa khai báo -> nil, không lỗi.
local INJECTED = SETTINGS_JSON

--==============================================================================
-- CONFIG MẶC ĐỊNH  (mọi khoá đều đổi được qua getgenv().AlimidaiConfig)
--==============================================================================
local DEFAULTS = {
	-- Bật/tắt toàn bộ vòng lặp. Chế độ coordinator tự bật khi launcher cho phép.
	Enabled = true,

	-- Tên acc NHẬN đồ. Mọi acc khác thấy acc này trong server sẽ gửi trade.
	MainAcc = "",

	-- Tên món muốn đưa. Gõ thiếu cũng được: "gem" khớp "Gems".
	-- LUÔN đưa HẾT số đang có (trừ khi đặt MaxPerItem).
	Items = { "Jackpot Spin" },

	-- Chỉ bên NHẬN dùng: rỗng = đồng ý mọi lời mời (an toàn vì bên nhận không
	-- bao giờ đưa đồ đi). Điền tên để chỉ nhận từ mấy acc đó.
	OnlyFrom = {},

	MaxPerItem = 0,     -- 0 = đưa hết; đặt số để chặn trần mỗi loại
	Interval   = 2,     -- giây/lần quét tìm MainAcc

	-- ĐO LIVE 2026-09-24: server nhận CẢ CỤM trong 1 lần gọi và tự cắt xuống
	-- đúng số đang có nếu mình xin dư. 1376 Gems = 1 lần bắn, không phải 1376 lần.
	-- Giãn nhịp giữa các MÓN, vì server vẫn debounce 0.1s mỗi lần gọi.
	OfferDelay   = 0.15,
	-- Bắn xong thì đối chiếu với offer server ghi nhận rồi bù phần thiếu.
	VerifyRounds = 6,

	-- NHIỀU ACC GỬI CÙNG LÚC ----------------------------------------------
	-- REQUEST_COOLDOWN của game là 6s cho cùng 1 người.
	RequestCooldown = 6.5,
	-- Cộng thêm 0..RequestJitter giây ngẫu nhiên, để 4 acc không bắn trùng nhịp.
	RequestJitter   = 1.5,
	-- Acc NHẬN: đã bấm đồng ý thì giữ chỗ bấy nhiêu giây cho trade kịp mở.
	-- Hết hạn mà trade chưa mở -> nhả chỗ, acc khác vào được.
	AcceptHold      = 12,
	-- Acc NHẬN: nghỉ bao lâu sau mỗi lần trade xong rồi mới nhận người kế tiếp.
	MainSettle      = 1.5,
	-- Acc GỬI: chờ bao lâu cho túi cập nhật sau khi trade xong.
	SenderSettle    = 8,
	-- Acc GỬI (chỉ chế độ độc lập): đưa hết đồ thì tự rời server.
	LeaveWhenDone   = false,

	Log = true,
	UI  = { Enabled = true, ToggleKey = Enum.KeyCode.RightShift },
}

--==============================================================================
-- TRỘN CONFIG
--==============================================================================
local function isArray(t) return type(t) == "table" and #t > 0 end

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = deepCopy(v) end
	return out
end

local function mergeCfg(dst, src)
	if type(src) ~= "table" then return dst end
	for k, v in pairs(src) do
		if type(v) == "table" and type(dst[k]) == "table" and not isArray(v) then
			mergeCfg(dst[k], v)
		else
			dst[k] = deepCopy(v)
		end
	end
	return dst
end

-- Ưu tiên: DEFAULTS < AnimeDiceTradeConfig (tên cũ) < AlimidaiConfig
--          < overrides (coordinator bơm vào)
local function buildConfig(overrides)
	local cfg = deepCopy(DEFAULTS)
	mergeCfg(cfg, env.AnimeDiceTradeConfig)
	mergeCfg(cfg, env.AlimidaiConfig)
	mergeCfg(cfg, overrides)
	return cfg
end

--==============================================================================
-- ĐỘNG CƠ TRADE
-- Trả về handle: { CFG, RT, TR, Net, Force, Cancel, Stop }
--==============================================================================
local function startTrade(overrides)
	local LP = Players.LocalPlayer
	if not LP then
		Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
		LP = Players.LocalPlayer
	end

	-- Tắt bản đang chạy (cả tên cũ lẫn tên mới) trước khi dựng bản mới.
	for _, key in ipairs({ "AlimidaiTrade", "AnimeDiceTrade" }) do
		local old = env[key]
		if type(old) == "table" and type(old.Stop) == "function" then
			pcall(old.Stop)
		end
	end
	task.wait(0.3)

	local CFG = buildConfig(overrides)

	--==========================================================================
	-- RUNTIME
	--==========================================================================
	local RT = {
		running  = true,
		threads  = {},
		conns    = {},
		status   = "khởi động",
		phase    = "-",
		partner  = "-",
		role     = "-",
		sent     = 0,      -- số lần ChangeOffer đã bắn trong lượt này
		total    = 0,      -- tổng cần bắn
		done     = 0,      -- số lượt trade đã xong
		log      = {},
		trading  = false,
		offered  = false,
		advanced = 0,
		ownOffer = {},     -- server ghi nhận mình đang đưa gì (từ sự kiện Updated)
		offerNames = {},   -- key -> tên món, để cộng dồn sau khi trade xong
		missed   = 0,      -- số món phải bù lại
		bulk     = true,   -- true = bắn cả cụm 1 lần; tự tắt nếu server chỉ nhận +1
		sentTotals = {},
		completedByPartner = {},
		-- hàng đợi nhiều acc gửi
		holdUntil    = 0,  -- acc NHẬN: giữ chỗ cho người vừa được đồng ý
		queued       = nil,-- tên người đang giữ chỗ
		settlingUntil = 0, -- acc GỬI: chờ túi cập nhật sau khi trade xong
		lastRequest  = nil,
		nextGap      = 0,
		served       = 0,  -- acc NHẬN: đã phục vụ bao nhiêu lượt
	}

	local TR = {}
	local function track(c) if c then table.insert(RT.conns, c) end return c end

	local function log(msg)
		local line = "[TRADE] " .. tostring(msg)
		table.insert(RT.log, line)
		while #RT.log > 30 do table.remove(RT.log, 1) end
		if CFG.Log then print(line) end
	end

	--==========================================================================
	-- REMOTE + MODULE
	--==========================================================================
	local function waitChild(parent, name, t)
		if not parent then return nil end
		local ok, res = pcall(function() return parent:WaitForChild(name, t or 15) end)
		return ok and res or nil
	end

	local Network = waitChild(RS, "Network", 30)
	local TS = Network and waitChild(Network, "TradeService", 20)
	local RE = TS and waitChild(TS, "RE", 20)

	local Net = {}
	for _, name in ipairs({ "RequestTrade", "RespondToRequest", "ChangeOffer",
		"AdvanceTrade", "CancelTrade", "SetTradeRequestsEnabled", "TradeEvent" }) do
		Net[name] = RE and waitChild(RE, name, 10) or nil
	end

	local DC, TradeCfg
	pcall(function() DC = require(RS.Framework.Features.Data.DataController) end)
	pcall(function() TradeCfg = require(RS.Framework.Features.Trading.TradeConfig) end)

	--==========================================================================
	-- HÀM THUẦN (test offline được)
	--==========================================================================

	-- Acc này đóng vai gì?
	function TR.role(myName, mainAcc)
		if type(mainAcc) ~= "string" or mainAcc == "" then return "chưa điền MainAcc" end
		if tostring(myName):lower() == mainAcc:lower() then return "main" end
		return "sender"
	end

	-- Món này có bị cấm trade không? (TradeConfig.UNTRADEABLE_ENTRIES)
	function TR.untradeable(name, list)
		for _, banned in ipairs(list or {}) do
			if tostring(banned):lower() == tostring(name):lower() then return true end
		end
		return false
	end

	-- Tìm mọi món trong túi khớp danh sách tên chồng gõ.
	-- Khớp ĐÚNG TÊN trước; không có cái nào thì mới khớp CHỨA CHUỖI ("gem" -> "Gems").
	-- Trả về: danh sách { key, name, amount }, đã bỏ món cấm trade.
	function TR.matchItems(inv, wanted, banned, maxUnique)
		local out, seen = {}, {}
		maxUnique = maxUnique or 20
		for _, want in ipairs(wanted or {}) do
			local needle = tostring(want):lower()
			local exact, loose = {}, {}
			for key, e in pairs(inv or {}) do
				if type(e) == "table" and type(e.name) == "string" and (tonumber(e.amount) or 0) > 0
					and not seen[key] and not TR.untradeable(e.name, banned) then
					local low = e.name:lower()
					if low == needle then
						exact[#exact + 1] = { key = key, name = e.name, amount = tonumber(e.amount) or 0 }
					elseif low:find(needle, 1, true) then
						loose[#loose + 1] = { key = key, name = e.name, amount = tonumber(e.amount) or 0 }
					end
				end
			end
			local pick = #exact > 0 and exact or loose
			table.sort(pick, function(a, b)
				if a.name == b.name then return tostring(a.key) < tostring(b.key) end
				return a.name < b.name
			end)
			for _, item in ipairs(pick) do
				if #out >= maxUnique then break end
				seen[item.key] = true
				out[#out + 1] = item
			end
		end
		return out
	end

	-- Tổng số món phải đưa trong lượt này.
	function TR.totalCalls(items, cap)
		local n = 0
		for _, item in ipairs(items or {}) do
			local amount = item.amount
			if cap and cap > 0 then amount = math.min(amount, cap) end
			n = n + amount
		end
		return n
	end

	-- Số truyền cho ChangeOffer.
	-- ĐO LIVE: server làm math.clamp(dangCo + delta, 0, soTrongTui) nên xin DƯ thì
	-- nó TỰ CẮT xuống đúng số đang có. Vậy khi "đưa hết" (cap = 0) cứ xin thừa —
	-- vừa chắc lấy hết, vừa không sợ đọc túi cũ (bot vẫn đang farm ra thêm đồ).
	-- Có chặn trần (cap > 0) thì phải xin ĐÚNG số, không được xin dư.
	TR.BULK_ASK = 999999   -- con số đã thử thật trên server

	function TR.askAmount(item, cap)
		if cap and cap > 0 then return math.min(item.amount, cap) end
		return math.max(item.amount, TR.BULK_ASK)
	end

	-- So offer server ĐANG ghi nhận với số mình ĐỊNH đưa -> trả về phần còn thiếu.
	-- Cần vì server chặn 0.1s/lần và nuốt im lặng call bắn quá nhanh.
	function TR.missing(items, ownOffer, cap)
		local out = {}
		ownOffer = ownOffer or {}
		for _, item in ipairs(items or {}) do
			local want = item.amount
			if cap and cap > 0 then want = math.min(want, cap) end
			local have = tonumber(ownOffer[item.key]) or 0
			if have < want then
				out[#out + 1] = { key = item.key, name = item.name, amount = want - have }
			end
		end
		return out
	end

	-- Bên NHẬN có được đồng ý lời mời của người này không?
	function TR.acceptFrom(name, onlyFrom)
		if type(onlyFrom) ~= "table" or #onlyFrom == 0 then return true end
		for _, allowed in ipairs(onlyFrom) do
			if tostring(allowed):lower() == tostring(name):lower() then return true end
		end
		return false
	end

	-- Acc đã đủ điều kiện trade chưa? Trả về: ok, lýDo
	function TR.canTrade(accountAge, rolls, cfg)
		cfg = cfg or {}
		local minAge = tonumber(cfg.MIN_ACCOUNT_AGE) or 14
		local minRolls = tonumber(cfg.MIN_ROLLS) or 1000
		if (tonumber(accountAge) or 0) < minAge then
			return false, string.format("acc mới %d ngày, cần %d", tonumber(accountAge) or 0, minAge)
		end
		if (tonumber(rolls) or 0) < minRolls then
			return false, string.format("mới roll %d lần, cần %d", tonumber(rolls) or 0, minRolls)
		end
		return true, nil
	end

	-- Acc NHẬN đang bận với một acc GỬI khác?
	function TR.busy()
		return RT.trading or os.clock() < (RT.holdUntil or 0)
	end

	--==========================================================================
	-- ĐỌC DỮ LIỆU GAME
	--==========================================================================
	function TR.inventory()
		if not DC then return nil end
		local ok, inv = pcall(function() return DC.Inventory() end)
		return ok and type(inv) == "table" and inv or nil
	end

	function TR.rolls()
		if not DC then return nil end
		local ok, n = pcall(function() return DC.Rolls() end)
		return ok and tonumber(n) or nil
	end

	function TR.banned()
		return (TradeCfg and TradeCfg.UNTRADEABLE_ENTRIES) or { "Tickets" }
	end

	function TR.maxUnique()
		return (TradeCfg and tonumber(TradeCfg.MAX_UNIQUE_ENTRIES)) or 20
	end

	-- Tìm MainAcc trong server
	function TR.findMain()
		local want = tostring(CFG.MainAcc):lower()
		if want == "" then return nil end
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= LP and p.Name:lower() == want then return p end
		end
		return nil
	end

	--==========================================================================
	-- HÀNH ĐỘNG
	--==========================================================================
	function TR.allowRequests()
		if Net.SetTradeRequestsEnabled then
			pcall(function() Net.SetTradeRequestsEnabled:FireServer(true) end)
		end
	end

	function TR.respond(accept)
		if Net.RespondToRequest then
			pcall(function() Net.RespondToRequest:FireServer(accept and true or false) end)
		end
	end

	function TR.cancel()
		if Net.CancelTrade then
			pcall(function() Net.CancelTrade:FireServer() end)
		end
	end

	function TR.advance()
		if Net.AdvanceTrade then
			pcall(function() Net.AdvanceTrade:FireServer() end)
			RT.advanced = RT.advanced + 1
		end
	end

	function TR.reset()
		RT.trading, RT.offered = false, false
		RT.sent, RT.total, RT.advanced = 0, 0, 0
		RT.phase, RT.partner = "-", "-"
		RT.ownOffer, RT.missed = {}, 0
		RT.queued = nil
		RT.status = "chờ dữ liệu túi cập nhật"
	end

	-- Đưa hết đồ khớp tên.
	function TR.offerAll()
		if RT.offered or not Net.ChangeOffer then return end
		local inv = TR.inventory()
		if not inv then log("chưa đọc được túi") return end

		local items = TR.matchItems(inv, CFG.Items, TR.banned(), TR.maxUnique())
		if #items == 0 then
			log("không có món nào khớp: " .. table.concat(CFG.Items, ", "))
			RT.offered = true
			return
		end

		local cap = tonumber(CFG.MaxPerItem) or 0
		RT.total = TR.totalCalls(items, cap)
		RT.sent = 0
		RT.offered = true

		local names = {}
		local desired = {}
		RT.offerNames = {}
		for _, item in ipairs(items) do
			RT.offerNames[item.key] = item.name
			desired[item.key] = cap > 0 and math.min(item.amount, cap) or item.amount
			names[#names + 1] = string.format("%s x%d", item.name, desired[item.key])
		end
		log("đưa: " .. table.concat(names, ", ") .. "  (" .. RT.total .. " món)")

		local delay = math.max(0.12, tonumber(CFG.OfferDelay) or 0.15)

		-- Bắn 1 lượt. bulk = true -> mỗi món 1 lần gọi với cả cụm.
		-- bulk = false -> quay về kiểu cũ, mỗi lần +1 (phòng khi game siết lại).
		local function fire(list)
			for _, item in ipairs(list) do
				if not RT.running or not RT.trading then return false end
				if RT.bulk then
					-- xin dư khi đưa hết; server tự cắt xuống số thật trong túi
					local ask = TR.askAmount(item, cap)
					pcall(function() Net.ChangeOffer:FireServer(item.key, ask) end)
					RT.sent = RT.sent + item.amount
				else
					for _ = 1, item.amount do
						if not RT.running or not RT.trading then return false end
						-- Sự kiện Updated về muộn có thể đã gồm cả cụm. Thấy server
						-- xác nhận đủ thì dừng bắn bù ngay.
						if (tonumber(RT.ownOffer[item.key]) or 0) >= desired[item.key] then break end
						pcall(function() Net.ChangeOffer:FireServer(item.key, 1) end)
						RT.sent = RT.sent + 1
						RT.status = string.format("đang đưa %d/%d", math.min(RT.sent, RT.total), RT.total)
						task.wait(delay)
					end
				end
				RT.status = string.format("đang đưa %d/%d", math.min(RT.sent, RT.total), RT.total)
				task.wait(delay)
			end
			return true
		end

		local first = {}
		for _, item in ipairs(items) do
			first[#first + 1] = { key = item.key, name = item.name, amount = desired[item.key] }
		end
		if not fire(first) then return end

		-- ĐỐI CHIẾU với offer server thật sự ghi nhận rồi bù đúng phần thiếu.
		local rounds = math.max(0, math.floor(tonumber(CFG.VerifyRounds) or 6))
		for i = 1, rounds do
			if not RT.running or not RT.trading then return end
			task.wait(0.5) -- chờ sự kiện Updated về
			local miss = TR.missing(items, RT.ownOffer, cap)
			if #miss == 0 then break end
			local n = 0
			for _, m in ipairs(miss) do n = n + m.amount end
			-- Lượt đầu mà server gần như không nhận gì -> chắc game siết lại +1.
			if i >= 3 and RT.bulk and n >= RT.total - #items then
				RT.bulk = false
				log("server không nhận cả cụm -> chuyển về kiểu bắn từng cái (chậm hơn)")
			end
			RT.missed = RT.missed + n
			log(string.format("thiếu %d món (lượt bù %d/%d)", n, i, rounds))
			if not fire(miss) then return end
		end

		local left = TR.missing(items, RT.ownOffer, cap)
		if #left == 0 then
			log("đưa đủ " .. RT.total .. " món" .. (RT.missed > 0 and (" (bù " .. RT.missed .. ")") or ""))
		else
			local n = 0
			for _, m in ipairs(left) do n = n + m.amount end
			log("CẢNH BÁO: vẫn thiếu " .. n .. " món sau " .. rounds .. " lượt bù")
		end
	end

	--==========================================================================
	-- NGHE SỰ KIỆN TỪ SERVER
	--==========================================================================
	function TR.onEvent(kind, data)
		data = type(data) == "table" and data or {}
		local who = data.player and data.player.Name or "?"

		if kind == "RequestReceived" then
			if RT.role ~= "main" then
				log("từ chối lời mời từ " .. who .. " (acc này chỉ GỬI cho MainAcc)")
				TR.respond(false)
				return
			end
			-- Acc NHẬN chỉ trade được 1 người một lúc. Đang bận -> từ chối để
			-- acc kia tự mời lại sau cooldown, không chiếm chỗ của ai.
			if TR.busy() then
				log("bận -> hoãn " .. who)
				TR.respond(false)
				return
			end
			if not TR.acceptFrom(who, CFG.OnlyFrom) then
				log("từ chối " .. who .. " (không có trong OnlyFrom)")
				TR.respond(false)
				return
			end
			-- Giữ chỗ ngay khi đồng ý, để lời mời đến sau không chen ngang.
			RT.holdUntil = os.clock() + (tonumber(CFG.AcceptHold) or 12)
			RT.queued = who
			log("nhận lời mời từ " .. who .. " -> đồng ý")
			TR.respond(true)

		elseif kind == "Started" then
			RT.trading, RT.offered = true, false
			RT.advanced = 0
			RT.partner = data.partner and data.partner.Name or "?"
			RT.ownOffer = {}
			RT.holdUntil = 0   -- cờ trading đã thay chỗ cho việc giữ chỗ
			log("bắt đầu trade với " .. RT.partner)
			-- CHẶN AN TOÀN: bên GỬI chỉ được đưa đồ cho đúng MainAcc.
			if RT.role == "sender" and RT.partner:lower() ~= tostring(CFG.MainAcc):lower() then
				log("KHÔNG phải MainAcc -> huỷ ngay")
				TR.cancel()
				TR.reset()
				return
			end
			if RT.role == "main" and not TR.acceptFrom(RT.partner, CFG.OnlyFrom) then
				TR.cancel()
				TR.reset()
				return
			end
			if RT.role == "sender" then
				task.spawn(function()
					TR.offerAll()
					if RT.running and RT.trading then TR.advance() end
				end)
			else
				TR.advance() -- bên nhận không đưa gì, sẵn sàng luôn
			end

		elseif kind == "Updated" then
			RT.phase = tostring(data.phase)
			RT.partner = data.partner and data.partner.Name or RT.partner
			-- ownOffer = server đang ghi nhận mình đưa gì; dùng để bù phần bị nuốt.
			RT.ownOffer = type(data.ownOffer) == "table" and data.ownOffer or {}
			if data.phase == "Confirm" and not data.ownAccepted then
				-- cả 2 đã ready -> gọi Advance lần 2 để chốt
				TR.advance()
			elseif data.phase == "Offer" and RT.role == "main" and not data.ownReady then
				TR.advance()
			end

		elseif kind == "Ended" then
			-- Bỏ qua thông báo kết thúc lặp lại sau khi đã reset.
			if not RT.trading then return end
			local why = tostring(data.reason or "?")
			local partner = RT.partner:lower()
			if why == "Completed" or why == "Success" then
				RT.done = RT.done + 1
				RT.completedByPartner[partner] = (RT.completedByPartner[partner] or 0) + 1
				if RT.role == "sender" then
					for key, amount in pairs(RT.ownOffer) do
						local name = RT.offerNames and RT.offerNames[key]
						if name and tonumber(amount) and tonumber(amount) > 0 then
							RT.sentTotals[name] = (RT.sentTotals[name] or 0) + tonumber(amount)
						end
					end
					-- Bên GỬI chờ lâu hơn: phải chắc túi đã cập nhật mới dám báo hết đồ.
					RT.settlingUntil = os.clock() + (tonumber(CFG.SenderSettle) or 8)
				else
					RT.served = RT.served + 1
				end
				log("TRADE XONG (" .. why .. ") — tổng " .. RT.done .. " lượt")
			else
				log("trade kết thúc: " .. why)
			end
			-- Bên NHẬN chỉ nghỉ ngắn rồi mở cửa cho acc kế tiếp trong hàng đợi.
			if RT.role == "main" then
				RT.holdUntil = os.clock() + (tonumber(CFG.MainSettle) or 1.5)
			end
			TR.reset()

		elseif kind == "RequestExpired" or kind == "RequestClosed" then
			RT.status = kind == "RequestExpired" and "lời mời hết hạn" or "lời mời bị đóng"
			-- Người giữ chỗ bỏ cuộc -> nhả chỗ ngay, khỏi bắt acc khác chờ hết AcceptHold.
			if RT.role == "main" and not RT.trading and RT.queued
				and who ~= "?" and who:lower() == tostring(RT.queued):lower() then
				RT.holdUntil = 0
				RT.queued = nil
			end
		end
	end

	--==========================================================================
	-- VÒNG LẶP
	--==========================================================================
	function TR.tick()
		if not CFG.Enabled then RT.status = "tắt" return end
		if not RE then RT.status = "không thấy remote TradeService" return end

		RT.role = TR.role(LP.Name, CFG.MainAcc)
		if RT.role == "chưa điền MainAcc" then RT.status = RT.role return end

		TR.allowRequests()

		if RT.role == "main" then
			if RT.trading then
				RT.status = "đang nhận từ " .. RT.partner
			elseif os.clock() < (RT.holdUntil or 0) then
				RT.status = "giữ chỗ cho " .. tostring(RT.queued or "?")
			else
				RT.status = "chờ acc khác gửi trade (xong " .. RT.served .. " lượt)"
			end
			return
		end

		local ok, why = TR.canTrade(LP.AccountAge, TR.rolls(), TradeCfg)
		if not ok then RT.status = "chưa trade được: " .. why return end
		if os.clock() < (RT.settlingUntil or 0) then
			RT.status = "chờ túi cập nhật sau khi trade"
			return
		end

		if RT.trading then
			RT.status = RT.total > 0 and string.format("đang đưa %d/%d", math.min(RT.sent, RT.total), RT.total)
				or ("đang trade với " .. RT.partner)
			return
		end

		local target = TR.findMain()
		if not target then RT.status = "chưa thấy " .. CFG.MainAcc .. " trong server" return end

		local inv = TR.inventory()
		local items = inv and TR.matchItems(inv, CFG.Items, TR.banned(), TR.maxUnique()) or {}
		if #items == 0 then
			RT.status = "không có món nào để đưa"
			-- Chỉ chế độ độc lập mới tự rời; chế độ coordinator để launcher quyết.
			if inv and CFG.LeaveWhenDone and RT.done > 0 then
				log("hết đồ -> rời server")
				RT.running = false
				pcall(function() LP:Kick("Đưa xong đồ") end)
			end
			return
		end

		-- REQUEST_COOLDOWN = 6s cho cùng 1 người; cộng jitter để nhiều acc gửi
		-- không dồn vào cùng một khoảnh khắc.
		local gap = RT.nextGap
		if gap <= 0 then gap = tonumber(CFG.RequestCooldown) or 6.5 end
		if os.clock() - (RT.lastRequest or -99) < gap then
			RT.status = "chờ hồi lời mời"
			return
		end
		RT.lastRequest = os.clock()
		RT.nextGap = (tonumber(CFG.RequestCooldown) or 6.5)
			+ math.random() * math.max(0, tonumber(CFG.RequestJitter) or 1.5)
		log("mời " .. target.Name .. " trade")
		RT.status = "đã mời " .. target.Name
		if Net.RequestTrade then
			pcall(function() Net.RequestTrade:FireServer(target) end)
		end
	end

	-- Launcher đọc túi trực tiếp; không bao giờ coi "chưa đọc được túi" là
	-- "túi rỗng". Không chặn maxUnique ở đây: mọi món khớp đều phải hết.
	function TR.snapshot()
		local inv = TR.inventory()
		local rolls = TR.rolls()
		local moduleReady = Net.TradeEvent ~= nil and Net.ChangeOffer ~= nil
			and Net.RequestTrade ~= nil and Net.RespondToRequest ~= nil
			and Net.AdvanceTrade ~= nil and Net.CancelTrade ~= nil
		local ready = inv ~= nil and moduleReady and TradeCfg ~= nil and rolls ~= nil
		local remaining = {}
		if inv then
			for _, item in ipairs(TR.matchItems(inv, CFG.Items, TR.banned(), math.huge)) do
				remaining[item.name] = (remaining[item.name] or 0) + item.amount
			end
		end
		local allowed, reason = TR.canTrade(LP.AccountAge, rolls, TradeCfg)
		local sent, completed = {}, {}
		for name, amount in pairs(RT.sentTotals) do sent[name] = amount end
		for name, count in pairs(RT.completedByPartner) do completed[name] = count end
		return {inventory_ready = ready, module_ready = moduleReady, remaining = remaining,
			sent = sent, completed_trades = RT.done, completed_by_partner = completed,
			trading = RT.trading, partner = RT.partner, phase = RT.phase,
			status = RT.status, can_trade = allowed, trade_reason = reason,
			rolls = rolls, account_age = LP.AccountAge, served = RT.served}
	end

	--==========================================================================
	-- GIAO DIỆN
	--==========================================================================
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
		local okH, hui = pcall(function() return gethui and gethui() end)
		if okH and hui then parent = hui end
		local old = parent:FindFirstChild("AlimidaiTradeGui")
		if old then old:Destroy() end

		local sg = mk("ScreenGui", { Name = "AlimidaiTradeGui", ResetOnSpawn = false,
			DisplayOrder = 99997, IgnoreGuiInset = true })
		pcall(function() sg.Parent = parent end)
		if not sg.Parent then sg.Parent = LP:WaitForChild("PlayerGui") end
		UI.gui = sg

		local f = mk("Frame", { Size = UDim2.new(0, 320, 0, 128),
			Position = UDim2.new(1, -340, 0, 20),
			BackgroundColor3 = Color3.fromRGB(20, 22, 30), BorderSizePixel = 0 }, sg)
		mk("UICorner", { CornerRadius = UDim.new(0, 10) }, f)
		mk("UIStroke", { Color = Color3.fromRGB(120, 200, 255), Thickness = 1.5,
			Transparency = 0.3 }, f)
		UI.frame = f

		mk("TextLabel", { Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 12, 0, 8),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 13,
			TextColor3 = Color3.fromRGB(120, 200, 255),
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = "ALIMIDAI TRADE v" .. TR_VERSION }, f)

		local function row(y, label)
			mk("TextLabel", { Size = UDim2.new(0, 70, 0, 16), Position = UDim2.new(0, 12, 0, y),
				BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
				TextColor3 = Color3.fromRGB(150, 158, 175),
				TextXAlignment = Enum.TextXAlignment.Left, Text = label }, f)
			return mk("TextLabel", { Size = UDim2.new(1, -92, 0, 16),
				Position = UDim2.new(0, 84, 0, y), BackgroundTransparency = 1,
				Font = Enum.Font.GothamMedium, TextSize = 11,
				TextColor3 = Color3.fromRGB(235, 240, 250),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd, Text = "-" }, f)
		end
		UI.roleLabel   = row(32, "Vai")
		UI.statusLabel = row(52, "Trạng thái")
		UI.phaseLabel  = row(72, "Giai đoạn")
		UI.doneLabel   = row(92, "Đã xong")

		track(UIS.InputBegan:Connect(function(input, gpe)
			if gpe then return end
			if input.KeyCode == CFG.UI.ToggleKey then f.Visible = not f.Visible end
		end))
	end

	function UI.refresh()
		if not UI.frame or not UI.frame.Visible then return end
		if UI.roleLabel then
			UI.roleLabel.Text = RT.role == "main" and ("NHẬN (" .. LP.Name .. ")")
				or (RT.role == "sender" and ("GỬI -> " .. tostring(CFG.MainAcc)) or tostring(RT.role))
		end
		if UI.statusLabel then UI.statusLabel.Text = tostring(RT.status) end
		if UI.phaseLabel then
			UI.phaseLabel.Text = RT.trading and (RT.phase .. " · " .. RT.partner) or "-"
		end
		if UI.doneLabel then UI.doneLabel.Text = tostring(RT.done) .. " lượt" end
	end

	--==========================================================================
	-- CHẠY
	--==========================================================================
	RT.role = TR.role(LP.Name, CFG.MainAcc)
	UI.build()

	if Net.TradeEvent then
		track(Net.TradeEvent.OnClientEvent:Connect(function(kind, data)
			if not RT.running then return end
			local ok, err = pcall(TR.onEvent, kind, data)
			if not ok then log("lỗi xử lý " .. tostring(kind) .. ": " .. tostring(err)) end
		end))
	else
		log("KHÔNG thấy TradeService.RE.TradeEvent — script không chạy được")
	end

	table.insert(RT.threads, task.spawn(function()
		while RT.running do
			local ok, err = pcall(TR.tick)
			if not ok then
				RT.status = "lỗi: " .. tostring(err)
				log("lỗi: " .. tostring(err))
			end
			task.wait(math.max(0.5, tonumber(CFG.Interval) or 2))
		end
	end))

	table.insert(RT.threads, task.spawn(function()
		while RT.running do
			pcall(UI.refresh)
			task.wait(0.4)
		end
	end))

	local handle
	handle = {
		Version = TR_VERSION,
		CFG = CFG, RT = RT, TR = TR, Net = Net,
		-- gọi tay
		Force = function()
			RT.lastRequest = nil
			RT.nextGap = 0
			RT.settlingUntil = 0
			return TR.tick()
		end,
		Cancel = function()
			TR.cancel()
			TR.reset()
		end,
		Stop = function()
			if not RT.running then return end
			RT.running = false
			if RT.trading then TR.cancel() end
			for _, th in ipairs(RT.threads) do pcall(task.cancel, th) end
			for _, c in ipairs(RT.conns) do pcall(function() c:Disconnect() end) end
			if UI.gui then pcall(function() UI.gui:Destroy() end) end
			RT.threads, RT.conns = {}, {}
			if env.AlimidaiTrade == handle then env.AlimidaiTrade = nil end
			if env.AnimeDiceTrade == handle then env.AnimeDiceTrade = nil end
			print("[TRADE] đã dừng.")
		end,
	}
	env.AlimidaiTrade  = handle
	env.AnimeDiceTrade = handle   -- tên cũ, giữ cho script/lệnh cũ còn chạy

	print("[TRADE] v" .. TR_VERSION .. " sẵn sàng — " .. LP.Name
		.. " | vai: " .. tostring(RT.role) .. " | Shift phải để ẩn bảng.")
	return handle
end

--==============================================================================
-- CHẾ ĐỘ ĐỘC LẬP — chạy bằng getgenv(), không cần launcher
--==============================================================================
local function runStandalone()
	local preview = buildConfig(nil)
	if type(preview.MainAcc) ~= "string" or preview.MainAcc == "" then
		warn("[ALIMIDAI] Chưa điền MainAcc — script sẽ đứng yên. Dùng như sau:")
		warn('  getgenv().AlimidaiConfig = { MainAcc = "TenAccNhan", Items = { "Jackpot Spin" } }')
		warn('  loadstring(game:HttpGet("<link raw github>/trade.lua"))()')
	end
	return startTrade()
end

--==============================================================================
-- CHẾ ĐỘ COORDINATOR — main.py chèn SETTINGS_JSON và theo dõi qua HTTP
--==============================================================================
local function runCoordinator(settings)
	if not game:IsLoaded() then game.Loaded:Wait() end
	while not Players.LocalPlayer do task.wait(0.2) end
	local player = Players.LocalPlayer

	local send = request or http_request or (syn and syn.request)
	assert(send, "HTTP request function unavailable")

	local identity = {
		username = player.Name, place_id = tostring(game.PlaceId),
		job_id = game.JobId, attempt_id = settings.attempt_id,
	}
	assert(identity.username == settings.username and identity.place_id == settings.place_id
		and identity.job_id == settings.job_id, "Wrong account / server; trade disabled")

	-- Cùng một lượt bơm script hai lần -> bỏ qua lần sau.
	if env.AlimidaiAttempt == identity.attempt_id then return end
	for _, key in ipairs({ "AlimidaiTrade", "AnimeDiceTrade" }) do
		local old = env[key]
		if type(old) == "table" and type(old.Stop) == "function" then pcall(old.Stop) end
	end
	env.AlimidaiAttempt = identity.attempt_id

	local stopped = false
	local function active()
		return not stopped and env.AlimidaiAttempt == identity.attempt_id
			and tostring(game.PlaceId) == identity.place_id and game.JobId == identity.job_id
	end

	local function post(path, extra)
		local data = {}
		for key, value in pairs(identity) do data[key] = value end
		for key, value in pairs(extra or {}) do data[key] = value end
		local ok, response = pcall(send, {
			Url = settings.api .. path, Method = "POST",
			Headers = {["Content-Type"] = "application/json"}, Body = Http:JSONEncode(data),
		})
		if not ok or not response then return nil end
		local decoded, result = pcall(function() return Http:JSONDecode(response.Body) end)
		if response.StatusCode == 200 and decoded and result.status == "ok" then return result end
		return nil, response.StatusCode, decoded and result.message or "HTTP error"
	end

	local function retry(path, data)
		for _ = 1, 20 do
			if not active() then return nil end
			local result, status = post(path, data)
			if result then return result end
			if status == 422 then return nil end
			task.wait(1)
		end
	end

	local function run()
		assert(retry("/auth"), "Coordinator auth failed")
		if settings.role == "main" then
			assert(retry("/main/job"), "JobId callback failed")
		end
		-- Giữ launcher biết client còn sống trong lúc module game đang nạp,
		-- mà chưa vội báo ready.
		task.spawn(function()
			while active() do
				task.wait(20)
				if not active() then break end
				local result, status = post("/trade/heartbeat")
				if status == 409 or (result and result.stop) then
					stopped = true
					if env.AlimidaiTrade then pcall(env.AlimidaiTrade.Stop) end
				end
			end
		end)

		if settings.smoke_test then
			local fake = {inventory_ready=true, module_ready=true, remaining={}, sent={},
				completed_by_partner={}, completed_trades=0, trading=false,
				can_trade=true, status="smoke"}
			assert(retry("/trade/ready", {sequence=1, snapshot=fake}), "Smoke ready failed")
			if settings.role == "hold" then
				assert(retry("/trade/smoke-done"), "Smoke callback failed")
			end
			return
		end

		local trade = assert(startTrade({
			MainAcc = settings.main_name,
			Items = settings.items,
			OnlyFrom = settings.allowed,
			Enabled = false,          -- launcher bật khi main đã sẵn sàng
			MaxPerItem = 0,
			LeaveWhenDone = false,    -- launcher quyết lúc nào rời
			UI = { Enabled = settings.show_ui == true },
			Log = true,
		}), "Trade module did not initialize")
		assert(trade.TR.snapshot, "Trade module missing snapshot support")

		local sequence = 0
		local ready = false
		local emptyChecks = 0
		local emptySince
		local lastSuccess = os.clock()
		local started = os.clock()
		local ineligibleSince
		while active() do
			local snapshot = trade.TR.snapshot()
			sequence = sequence + 1
			local payload = {sequence=sequence, snapshot=snapshot}
			local response
			if not ready then
				if snapshot.module_ready and (settings.role == "main" or snapshot.inventory_ready) then
					if settings.role == "hold" and not snapshot.can_trade and next(snapshot.remaining) then
						ineligibleSince = ineligibleSince or os.clock()
						if os.clock() - ineligibleSince >= 15 then
							error(snapshot.trade_reason or "Account cannot trade")
						end
					else
						ineligibleSince = nil
						response = post("/trade/ready", payload)
						if response and response.start then
							ready = true
							trade.CFG.Enabled = true
						end
					end
				elseif os.clock() - started > 120 then
					error("Inventory / trade modules unavailable")
				end
			else
				response = post("/trade/update", payload)
			end
			if response then lastSuccess = os.clock() end
			if response and response.stop then break end
			if os.clock() - lastSuccess > 60 then
				error("Coordinator unavailable; stopping trade")
			end
			if ready and settings.role == "hold" then
				if snapshot.inventory_ready and not snapshot.trading and not next(snapshot.remaining) then
					emptyChecks = emptyChecks + 1
					emptySince = emptySince or os.clock()
				else
					emptyChecks = 0
					emptySince = nil
				end
				if emptyChecks >= 3 and emptySince and os.clock() - emptySince >= 6 then
					-- Launcher còn bắt buộc phải thấy sự kiện trade xong bên main và
					-- fsync sổ done.txt TRƯỚC khi trả lời ok ở đây.
					local ack = post("/trade/done", payload)
					if ack and ack.saved then
						trade.Stop()
						stopped = true
						player:Kick("Trade complete; saved to done.txt")
						return
					end
				end
			end
			task.wait(2)
		end
		trade.Stop()
	end

	local ok, failure = pcall(run)
	if not ok then
		if env.AlimidaiTrade then pcall(env.AlimidaiTrade.Stop) end
		post("/trade/error", {message=tostring(failure)})
		warn("[COORDINATOR] " .. tostring(failure))
		stopped = true
	end
end

--==============================================================================
-- VÀO ĐÂY
--==============================================================================
if INJECTED then
	runCoordinator(Http:JSONDecode(INJECTED))
else
	runStandalone()
end
