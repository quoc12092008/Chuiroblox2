
local KT_VERSION = "1.8.0"

--==============================================================================
-- 1. SERVICES
--==============================================================================
local Svc = {
	Players = game:GetService("Players"),
	RS      = game:GetService("ReplicatedStorage"),
	Run     = game:GetService("RunService"),
	Tween   = game:GetService("TweenService"),
	UIS     = game:GetService("UserInputService"),
	Http    = game:GetService("HttpService"),
}
local LP = Svc.Players.LocalPlayer
if not LP then
	Svc.Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
	LP = Svc.Players.LocalPlayer
end

-- chống chạy 2 bản cùng lúc
if getgenv().AnimeDiceKaitun and getgenv().AnimeDiceKaitun.Stop then
	pcall(getgenv().AnimeDiceKaitun.Stop)
	task.wait(0.35)
end

--==============================================================================
-- 2. CONFIG
--==============================================================================
local CFG = {
	-- ===== CÔNG TẮC TO: tắt 1 cái là tắt cả cụm bên dưới =====
	-- Farm    : Roll, Collect, Plot, LevelUp, Sell
	-- Economy : Economy (kéo theo Dice, Upgrade, Rebirth)
	-- Content : Tower, Quest, Rewards, Codes, Boost, Tickets
	-- Utility : Keep, Webhook, Cleanup, Swap
	-- Từng chức năng nhỏ vẫn giữ cờ Enabled riêng để tinh chỉnh.
	Groups = {
		Farm    = true,
		Economy = true,
		Content = true,
		Utility = true,
	},

	-- ===== Giao diện =====
	UI = {
		Enabled        = true,
		StartMinimized = false,
		ToggleKey      = Enum.KeyCode.RightControl,
		LogLines       = 60,
	},

	-- ===== Quay xúc xắc =====
	Roll = {
		Enabled     = true,
		ServerAuto  = false,  -- true = bật AutoRoll của game (server) thay vì tự spam RF
		ExtraDelay  = 0.05,   -- cộng thêm vào Roll Duration buff
		StopWhenFull = true,  -- túi đầy thì ngừng quay (RollService.lua:140)
	},

	-- ===== Gom tiền các ô plot =====
	Collect = { Enabled = true, Interval = 1.0 },

	-- ===== Đặt pet lên plot (thông minh) =====
	Plot = {
		Enabled     = true,
		Interval    = 4,
		-- "normalized" = xếp hạng bằng income quy về LEVEL 1 (đúng ý chồng:
		--   pet mới base 2.4k phải thắng pet cũ base 2.3k dù pet cũ đã nâng lên 2.5k)
		CompareMode = "normalized",
		SwapMargin  = 0.02,   -- pet mới phải hơn pet cũ >= 2% base mới xét (chống nhảy qua nhảy lại)
		-- BÀI TOÁN HOÀN VỐN KHI ĐỔI (chống lỗ tiền đã nâng level cho pet cũ):
		--   pet cũ: base Bo, level L  -> đang ra Bo*(1+0.25*(L-1))/s
		--   pet mới: base Bn, level 1 -> muốn kéo nó lên level L phải tốn
		--        cost = Bmut * (1.6^(L-1) - 1) / 0.6      (UnitUtil.lua:26)
		--   lời thêm sau khi kéo xong = (Bn-Bo)*(1+0.25*(L-1))*MoneyMult /s
		--   chỉ đổi khi cost / lời-thêm <= SwapPaybackSeconds
		SwapPaybackSeconds = 600,
		-- Pet mới mạnh gấp >= ngần này lần pet cũ (tính theo base level 1) thì ĐỔI NGAY,
		-- khỏi cần xét hoàn vốn: tiền đã nâng cho pet cũ quá nhỏ so với phần lời mới.
		ForceSwapRatio = 5,
		UseEquipBest = false, -- true = xài remote EquipBest của game (nó so income CÓ level -> kém thông minh hơn)
	},

	-- ===== Nâng level pet trên plot (thông minh) =====
	LevelUp = {
		Enabled           = true,
		Interval          = 2.5,
		MaxPaybackSeconds = 300,   -- chỉ nâng khi hoàn vốn dưới 300s (UnitUtil.lua:26 -> 4*1.6^(lv-1)/mult giây)
		-- khi ví đang KHOÁ để dồn tiền mua dice (Dice.ReserveRatio) thì siết lại:
		-- chỉ nâng những cấp siêu rẻ, hoàn vốn dưới 60s, để không cản việc mua dice
		LockedPaybackSeconds = 60,
		MaxMoneyFraction  = 0.35,  -- 1 lần nâng không tiêu quá 35% tiền đang có
		MaxLevel          = 0,     -- 0 = không chặn trần level
	},

	-- ===== Bán pet dư theo chance thấp nhất trên plot =====
	Sell = {
		Enabled        = true,
		Interval       = 2,
		ServerAutoSell = true,
		BatchSize      = 60,
		UnlockWeakSecrets = true, -- gỡ khóa Secret dư <= ngưỡng, kể cả khóa từ bản cũ
		-- Chặn bán oan: pet chance thấp nhưng trait/grade tốt hơn đội hình thì GIỮ.
		-- Chỉ bán khi vừa dưới ngưỡng chance VỪA dưới income (quy về level 1) của đội hình.
		UseIncomeGuard = true,
		-- MinRarity/HardMaxRarity/KeepExtra/StartAfterRolls không còn được dùng.
	},

	-- ===== Quest: tự làm + tự nhận =====
	Quest = {
		Enabled       = true,
		Interval      = 3,
		ForceTower    = true,  -- quest "Defeat N towers" chỉ tính khi CLEAR HẾT tầng
		                       -- (TowerClass.lua:166) -> ép chọn tower clear nổi cho tới khi xong quest
		PushSell      = true,  -- hiển thị nhu cầu quest; không thay đổi ngưỡng chance
	},

	-- ===== Kinh tế: dice / upgrade / rebirth dùng CHUNG ví tiền =====
	Economy = {
		Enabled  = true,
		Interval = 2.5,
		-- thứ tự giành tiền, sửa thoải mái
		Priority = { "Dice", "RollSpeed", "Luck", "Damage", "Money", "Storage", "Health", "Sell", "Walkspeed" },
		-- khi đang để dành cho món ưu tiên cao chưa mua nổi, món thấp hơn chỉ được mua nếu giá <= 25% tiền
		FallThroughFraction = 0.25,
	},

	Dice = {
		Enabled  = true,
		MaxTier  = "",    -- "" = không chặn; đặt tên dice để chặn trần (vd "Void")
		AutoEquipBest = true,
		-- DỒN TIỀN CHO DICE: khi tiền đã >= 60% giá con dice kế tiếp thì KHÓA ví,
		-- không cho upgrade/rebirth tiêu lẻ nữa, để mua dice xịn nhất cho nhanh.
		ReserveRatio = 0.6,
	},

	Upgrade = {
		Enabled          = true,
		WalkspeedMaxTier = 1,  -- "walkspeed thì ko cần nâng nhiều" -> mặc định chỉ mua Walkspeed I
	},

	Rebirth = {
		Enabled = true,
		Mode    = "smart", -- "smart" = tiêu hết những thứ mua nổi rồi mới rebirth (Money về 0) | "asap"
		Margin  = 1.0,
		Max     = 0,       -- 0 = không giới hạn
		-- đang dồn tiền mua dice mà giá rebirth <= giá dice × tỉ lệ này thì rebirth TRƯỚC
		-- (rebirth cho hệ số NHÂN luck/money nên nó nhân luôn cho con dice mua sau)
		VsDiceRatio = 1.0,
		-- "auto rebirth khi đủ điều kiện để mở thêm plot":
		-- nếu lần rebirth kế tiếp MỞ THÊM Ô PLOT thì đủ tiền là rebirth LUÔN, không chờ tiêu hết
		UnlockFirst = true,
	},

	-- ===== Tower =====
	Tower = {
		Enabled   = true,
		Interval  = 3.2,     -- PlayTower debounce 3s, TowerService.lua
		Mode      = "auto",  -- "auto" = tự chọn tower lời nhất | "fixed"
		Fixed     = "Dragon Tower",
		MinFloors = 5,       -- không vào tower nếu mô phỏng qua chưa nổi 5 tầng
		AutoTeam  = true,    -- EquipBestTowerTeam trước mỗi lượt
		-- MỖI TOWER RƠI 1 BỘ BOOST RIÊNG và các bộ này là CATEGORY KHÁC NHAU
		-- (Luck / Dragon Luck / Cursed Luck / Pirate Luck) nên chúng NHÂN DỒN với nhau
		-- (BoostService.lua:78 giữ 1 boost mỗi category, BuffService.lua:110 bucket
		--  "multiplier" thì nhân). Source mới có thêm Leaf và boost thường tier IV.
		-- Bật cái này thì bot tự xoay vòng tower để nạp lại bộ boost đang cạn.
		FarmBoosts       = true,
		BoostStockTarget = 3,   -- mỗi category giữ tối thiểu 3 cái trong túi
		ResourceWeights = { Gems = 1, ["Trait Reroll"] = 1 },
		BoostWeight = 0.03, -- trọng số chiến lược, không phải xác suất game
		MaxSimFloors = 1500,
		LatencyMargin = 0.08,
		RefillEvery = 4, -- tối đa 1 lượt nạp boost sau mỗi 4 lượt farm tài nguyên
	},

	-- ===== Reward + code =====
	Rewards = {
		Enabled = true, Interval = 30,
		Daily = true, Group = true, Offline = true, Quests = true,
		GroupMaxTries = 3,  -- acc chua vao group thi thu 3 lan roi thoi, khong spam remote
	},
	Codes = {
		Enabled  = true,
		Interval = 120,   -- thử lại định kỳ, code đã nhận rồi thì bỏ qua
		-- Dump AnimeDice (MonetizationConfig.Codes) mới có 6 code: RELEASE, UPDATE1-3, 1KCCU, 5KCCU.
		-- 6 code còn lại do chồng đưa, CHƯA XÁC NHẬN TRONG SOURCE; server tự báo "Invalid code."
		-- nếu sai nên vẫn an toàn, và MaxTries ở dưới chặn việc thử lại mãi.
		List = { "100KLIKES", "40KCCU", "30KCCU", "UPDATE4", "20KCCU", "10KCCU",
			"5KCCU", "1KCCU", "UPDATE3", "UPDATE2", "UPDATE1", "RELEASE" },
		MaxTries = 3,     -- thử 1 code quá ngần này lần mà vẫn chưa nhận được thì bỏ qua
	},

	-- chống Roblox kick vì đứng yên 20 phút
	AntiAFK = { Enabled = true },

	-- ===== CHỐNG KẸT =====
	-- Tiền không nhảy VÀ không quay được dice quá StuckSeconds -> rejoin / kick.
	-- Chỉ chạy khi Auto Roll đang bật; chồng tắt roll thì watchdog tự nghỉ để khỏi
	-- rejoin oan lúc đang chỉnh tay.
	Watchdog = {
		Enabled      = true,
		Interval     = 10,
		StuckSeconds = 300,      -- 5 phút
		Action       = "rejoin", -- "rejoin" | "kick" | "log"
		RequireBoth  = true,     -- true = phải kẹt CẢ tiền lẫn roll mới tính
	},

	-- ===== KHÓA ĐỒ: bot KHÔNG được tiêu những món có tên trong đây =====
	-- Gõ đúng tên như trong túi, không phân biệt hoa/thường.
	-- Ví dụ để dành tự xài tay:  LockedItems = { "Jackpot Spin" }
	-- Áp cho mọi chỗ bot tiêu đồ: dùng Boost, dùng Spin.
	LockedItems = {},

	-- ===== Boost / Spin trong túi =====
	-- BoostConfig mới: Luck/Income/Damage × (thường, Dragon, Cursed, Pirate, Leaf).
	-- Các category KHÁC NHAU chạy song song và NHÂN DỒN, nên bật hết mới ăn đủ.
	Boost = {
		Enabled  = true,
		Interval = 3,
		UseLuck   = true,  -- Luck + Dragon Luck + Cursed Luck + Pirate Luck
		UseMoney  = true,  -- Income + Dragon/Cursed/Pirate Income
		UseDamage = true,  -- Damage ... (đánh mạnh -> clear tower sâu hơn -> nhiều drop hơn)
		UseSpins = true,
	},

	-- Không tự khóa mọi Secret; giữ/bán theo chance plot.
	Keep = { Interval = 0.5 },
	Webhook = {
		Enabled = true, URL = "https://discord.com/api/webhooks/1549156885280718989/2FjOJ3E9ajhAByuswUQvObXMZpa7hfDAoNguP0_4cELq4ENir65o0E596-8j7pvWT68F", -- chồng điền webhook Discord của mình ở config
		MinRarity = "Celestial", NotifyExisting = false,
		Interval = 2, MaxQueue = 100, MaxAttempts = 5,
	},
	-- ===== Đổi vé (Tickets) =====
	-- Tên phải trùng QuestConfig.Shop: "Lucky Spin" (20 vé), "Trait Reroll" (1), "Gems" (1),
	-- và 4 gamepass "Luck" (199), "Ultra Luck" (599), "More Cash" (199), "Roll Speed" (499).
	TicketShop = {
		Enabled = true, Interval = 0.4, Reserve = 0,
		Items = { "Trait Reroll", "Gems" }, -- đổi thành gì thì sửa danh sách này
		Mode  = "rotate",        -- "rotate" = xoay vòng đều | "priority" = ưu tiên từ trên xuống
		AllowGamepass = false,   -- true mới cho đổi vé lấy gamepass (giá vé rất cao)
	},

	-- ===== Đổi acc khi trúng đồ xịn (FarmSync) =====
	-- CHƯA ĐƯỢC XÁC NHẬN TRONG SOURCE AnimeDice: getgenv().client:ChangeToFolder là API của
	-- FarmSync, không nằm trong dump game. Code chỉ gọi khi thấy đủ client + hàm đó.
	-- Điều kiện: trong túi có >= Amount món Item (mặc định "Jackpot Spin", SpinConfig).
	AccountSwap = {
		Enabled    = false,          -- BẬT khi chồng đã điền 2 ID folder
		Interval   = 5,
		Item       = "Jackpot Spin", -- món dùng làm điều kiện đổi acc
		Amount     = 1,
		FromFolder = "",             -- ID folder acc chính
		ToFolder   = "",             -- ID folder acc thay thế
		Replace    = false,          -- tham số 3 của ChangeToFolder
		ConfigId   = nil,            -- tham số 4 (nil nếu không đổi config)
		KeepItem   = true,           -- không cho Boost xài món này trong lúc chờ đổi acc
	},
	Performance = { Enabled = true, DisableWind = true, UIInterval = 1 },
	-- Xóa object ở client. Tắt/Stop chỉ ngừng dọn; vào lại server để tải lại cảnh đã xóa.
	WorkspaceCleanup = {
		Enabled = true, Interval = 3, BatchSize = 4,
		OtherPlots = true, MapDecor = true, Leaderboards = true,
		-- Aggressive: xóa MỌI con của workspace.Map, chỉ chừa nhánh đang đỡ nền (raycast),
		-- nhánh có SpawnLocation (chỗ hồi sinh) và nhánh có script (tránh controller lỗi đỏ).
		Aggressive      = true,
		OtherCharacters = true,  -- xóa nhân vật người khác trong workspace.Players (nặng nhất khi server đông)
		Limiteds        = false, -- LimitedUnitController giữ tham chiếu part; bật nếu chấp nhận rủi ro
		DebrisChildren  = false, -- PlotController parent VFX tiền vào workspace.Debris -> giữ thư mục
		ClearTerrain    = false, -- Terrain:Clear() (không hoàn tác được cho tới khi vào lại server)
		Zones           = false, -- ZoneUtil/TopBarController đang dùng -> mặc định GIỮ
		-- Dump _tree.txt: còn 707 ParticleEmitter, 533 Texture, 62 Decal, 59 BillboardGui,
		-- 48 SurfaceGui nằm trong những nhánh bắt buộc phải giữ (có script / đỡ nền).
		-- Xóa nguyên nhánh thì hỏng game, nên lột riêng phần hiệu ứng.
		StripEffects    = true,  -- lột particle/beam/trail/sound/decal/texture/GUI/đèn
		StripBatch      = 400,   -- số instance xử lý mỗi lượt, tránh khựng
		-- Plot mình PHẢI giữ SurfaceGui/Hitbox (PlotController:447 WaitForChild) nên chỉ
		-- lột những thứ chắc chắn vô hại: particle/beam/trail/khói/lửa/âm thanh.
		StripOwnPlot    = true,
		HideKeptParts   = true,  -- part trang trí trong nhánh giữ lại: cho tàng hình thay vì xóa
		PlotPositions   = true,  -- workspace.PlotPositions: chỉ PlotClass phía server dùng
		Rigs            = true,  -- workspace.R6: rig mẫu, client không cần
		Lighting        = true,  -- xóa post-effect + Atmosphere trong Lighting
	},
}

-- merge config người dùng (mảng thì THAY, bảng thì trộn)
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
mergeCfg(CFG, getgenv().AnimeDiceConfig)

--==============================================================================
-- 3. RUNTIME STATE
--==============================================================================
local RT = {
	running   = true,
	threads   = {},
	log       = {},
	status    = {},     -- [module] = text
	err       = {},     -- [module] = last error
	stats     = {},
	sellRarity = "-",
	towerName = "-",
	towerFloor = 0,
	lastBuy   = "-",
	rollOk    = 0,
	rollFail  = 0,
	sold      = 0,
	soldCash  = 0,
	busyEquip = false,
	startClock = os.clock(),
	codeTries = {},
	connections = {},
	unitConfigCache = {},
	noticeSeen = {},
	noticeQueue = {},
	tokenLedger = {},
}

--==============================================================================
-- 4. REMOTES + MODULES
--==============================================================================
local function waitChild(parent, name, t)
	if not parent then return nil end
	local ok, res = pcall(function() return parent:WaitForChild(name, t or 15) end)
	if ok then return res end
	return nil
end

local Network = waitChild(Svc.RS, "Network", 30)
if not Network then
	warn("[KAITUN] Không tìm thấy ReplicatedStorage.Network — dừng.")
	return
end

local function rem(path)
	local cur = Network
	for seg in string.gmatch(path, "[^%.]+") do
		cur = waitChild(cur, seg, 15)
		if not cur then return nil end
	end
	return cur
end

local Net = {
	BuyUpgrade   = rem("RE.BuyUpgrade"),
	RollDice     = rem("RollService.RF.RollDice"),
	SetAutoRoll  = rem("RollService.RE.SetAutoRoll"),
	BuyDice      = rem("DiceShopService.RE.BuyDice"),
	EquipDice    = rem("DiceShopService.RE.EquipDice"),
	CollectBal   = rem("PlotService.RE.CollectBalance"),
	InteractSlot = rem("PlotService.RE.InteractSlot"),
	LevelUpSlot  = rem("PlotService.RE.LevelUpSlot"),
	EquipBest    = rem("PlotService.RE.EquipBest"),
	UnitEquip    = rem("UnitService.RF.Equip"),
	UnitUnequip  = rem("UnitService.RF.Unequip"),
	SetLocked    = rem("UnitService.RE.SetLocked"),
	SellInv      = rem("SellService.RF.SellInventory"),
	UpdAutoSell  = rem("SellService.RE.UpdateAutoSell"),
	Rebirth      = rem("RebirthService.RE.Rebirth"),
	PlayTower    = rem("Towers.RF.PlayTower"),
	CompleteFloor= rem("Towers.RF.CompleteTowerFloor"),
	CancelTower  = rem("Towers.RF.CancelTower"),
	BestTeam     = rem("Towers.RE.EquipBestTowerTeam"),
	RedeemCode   = rem("MonetizationService.RE.RedeemCode"),
	DailyClaim   = rem("DailyRewardService.RE.Claim"),
	GroupClaim   = rem("GroupRewardService.RE.Claim"),
	OfflineClaim = rem("OfflineEarningsService.RE.Claim"),
	QuestClaim   = rem("QuestService.RE.Claim"),
	BoostUse     = rem("BoostService.RE.Use"),
	SpinUse      = rem("SpinService.RE.Use"),
	QuestBuy     = rem("QuestService.RE.Buy"),
	-- CỐ Ý KHÔNG nối remote roll trait / roll grade:
	-- bot KHÔNG BAO GIỜ tiêu Trait Reroll / Gems (chồng để dành, tự dùng tay).
}

-- Hạ AutoSell trước khi tải module; pending roll của game cũng đọc ngưỡng này.
if Net.UpdAutoSell then pcall(function() Net.UpdAutoSell:FireServer(0) end) end

local Mods = {}
local function req(path, key)
	local ok, res = pcall(function()
		local cur = Svc.RS
		for seg in string.gmatch(path, "[^%.]+") do cur = cur[seg] end
		return require(cur)
	end)
	if ok then Mods[key] = res else warn("[KAITUN] require fail: " .. path) end
	return Mods[key]
end

req("Framework.Features.Data.DataController",                    "DC")
req("Framework.Features.Inventory.EntryRegistry",                "EntryRegistry")
req("Framework.Features.Inventory.Kinds.Unit.UnitUtil",          "UnitUtil")
req("Framework.Features.Buffs.BuffController",                   "BuffC")
req("Framework.Features.Upgrades.Upgrades",                      "Upgrades")
req("Framework.Features.Upgrades.TreeStructure",                 "Tree")
req("Framework.Features.Rolling.Dice",                           "Dice")
req("Framework.Features.Rebirth.Rebirths",                       "Rebirths")
req("Framework.Features.Plot.PlotConfig",                        "PlotConfig")
req("Framework.Features.Plot.PlotController",                    "PlotC")
req("Framework.Features.Towers.Towers",                          "Towers")
req("Framework.Features.Towers.TowerRefs",                       "TowerRefs")
req("Framework.Other.Rarities",                                  "Rarities")
req("Framework.Features.Quests.QuestConfig",                     "QuestConfig")
req("Framework.Features.Rewards.DailyRewardConfig",              "DailyCfg")
req("Framework.Features.Rewards.GroupRewardConfig",              "GroupCfg")
req("Packages.NumberFormatter",                                  "NumFmt")
req("Framework.Features.Inventory.Kinds.Unit.Mutations",          "Mutations")

local DC = Mods.DC
if not DC then
	warn("[KAITUN] Không require được DataController — dừng.")
	return
end

--==============================================================================
-- 5. HELPERS
--==============================================================================
local Util = {}

function Util.track(connection)
	if connection then table.insert(RT.connections, connection) end
	return connection
end

function Util.disconnect(connection)
	if type(connection) == "function" then pcall(connection)
	elseif connection then pcall(function() connection:Disconnect() end) end
end

function Util.fmt(n)
	n = tonumber(n) or 0
	if Mods.NumFmt then
		local ok, s = pcall(Mods.NumFmt.FormatCompact, n, 2)
		if ok and s then return s end
	end
	local a = math.abs(n)
	local suf = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
	local i = 1
	while a >= 1000 and i < #suf do a = a / 1000; i = i + 1 end
	return string.format("%.2f%s", a, suf[i])
end

function Util.log(tag, msg)
	local line = string.format("[%s] %s", tag, tostring(msg))
	table.insert(RT.log, line)
	while #RT.log > CFG.UI.LogLines do table.remove(RT.log, 1) end
	RT.logDirty = true
end

-- đọc data an toàn (Value proxy có thể chưa sẵn sàng)
function Util.get(fn, default)
	local ok, v = pcall(fn)
	if ok and v ~= nil then return v end
	return default
end

function Util.data(key, default)
	return Util.get(function() return DC[key]() end, default)
end

function Util.buff(name, default)
	if not Mods.BuffC then return default end
	local ok, v = pcall(Mods.BuffC.GetBuff, name)
	if ok and type(v) == "number" then return v end
	return default
end

function Util.count(t)
	local n = 0
	if type(t) == "table" then for _ in pairs(t) do n = n + 1 end end
	return n
end

function Util.attrsLv1(attrs)
	local t = {}
	if type(attrs) == "table" then for k, v in pairs(attrs) do t[k] = v end end
	t.level = 1
	return t
end

-- vòng lặp có tên, tự bắt lỗi, tự dừng khi Stop()
-- Mỗi vòng lặp thuộc 1 nhóm lớn; tắt nhóm là cả cụm ngừng chạy.
local GROUP_OF = {
	Roll = "Farm", Collect = "Farm", Plot = "Farm", LevelUp = "Farm", Sell = "Farm",
	Economy = "Economy",
	Tower = "Content", Quest = "Content", Rewards = "Content", Codes = "Content",
	Boost = "Content", Tickets = "Content",
	Keep = "Utility", Webhook = "Utility", Cleanup = "Utility", Swap = "Utility",
}

local function groupAllows(name)
	local group = GROUP_OF[name]
	if not group then return true, nil end
	local groups = CFG.Groups
	if type(groups) ~= "table" or groups[group] ~= false then return true, group end
	return false, group
end

local function loop(name, getInterval, fn)
	RT.status[name] = "chờ"
	local th = task.spawn(function()
		task.wait(math.random() * 0.6)
		while RT.running do
			local allowed, group = groupAllows(name)
			local ok, err = true, nil
			if not allowed then
				RT.status[name] = "tắt theo nhóm " .. tostring(group)
			else
				ok, err = pcall(fn)
			end
			if not ok then
				if name == "Plot" then RT.busyEquip = false end
				if name == "Tower" then RT.busyTeam = false end
				RT.err[name] = tostring(err)
				Util.log(name, "LỖI: " .. tostring(err))
				task.wait(2)
			end
			local iv = getInterval()
			task.wait(math.max(0.05, iv or 1))
		end
		RT.status[name] = "dừng"
	end)
	table.insert(RT.threads, th)
end

--==============================================================================
-- 6. GAME MATH (bám đúng source)
--==============================================================================
local Game = {}

-- ngưỡng chance -> rarity, UnitConfig.lua:14-25 (bảng u2, module không export nên chép lại)
Game.RARITY_FLOOR = {
	Common     = 0,
	Uncommon   = 100,
	Rare       = 1000,
	Epic       = 100000,
	Legendary  = 10000000,
	Mythical   = 1000000000,
	Divine     = 100000000000,
	Exotic     = 10000000000000,
	Celestial  = 1000000000000000,
	["Secret I"] = 1e17,
	["Secret II"] = 1e20, -- Live_20260915/ReplicatedStorage/.../UnitConfig.lua:23
}

function Game.raritySort(name)
	if not Mods.Rarities then return 0 end
	local ok, r = pcall(Mods.Rarities.Get, name)
	if ok and r and r.sortOrder then return r.sortOrder end
	return 99
end

function Game.unitCfg(entry)
	if not entry or not entry.name or not Mods.EntryRegistry then return nil end
	local cached = RT.unitConfigCache[entry.name]
	if cached then return cached end
	local ok, cfg = pcall(Mods.EntryRegistry.getEntryConfig, entry.name)
	if ok and cfg and cfg.kind == "Unit" then
		RT.unitConfigCache[entry.name] = cfg
		return cfg
	end
	return nil
end

function Game.income(entry, attrs)
	local cfg = Game.unitCfg(entry)
	if not cfg then return 0 end
	local ok, v = pcall(cfg.income, attrs or entry.attributes)
	return (ok and type(v) == "number") and v or 0
end

function Game.incomeLv1(entry)
	return Game.income(entry, Util.attrsLv1(entry.attributes))
end

function Game.chanceOf(entry)
	local cfg = Game.unitCfg(entry)
	if not cfg or not cfg.chance then return nil end
	local ok, v = pcall(cfg.chance, entry.attributes)
	return (ok and type(v) == "number") and v or nil
end

function Game.rarityOf(entry)
	local cfg = Game.unitCfg(entry)
	if not cfg then return nil end
	if cfg.getRarity then
		local ok, v = pcall(cfg.getRarity, entry.attributes)
		if ok and v then return v end
	end
	return cfg.rarity
end

function Game.damageOf(entry)
	local cfg = Game.unitCfg(entry)
	if not cfg or not cfg.damage then return 0 end
	local ok, v = pcall(cfg.damage, entry.attributes)
	return (ok and type(v) == "number") and v or 0
end

function Game.healthOf(entry)
	local cfg = Game.unitCfg(entry)
	if not cfg or not cfg.health then return 0 end
	local ok, v = pcall(cfg.health, entry.attributes)
	return (ok and type(v) == "number") and v or 0
end

-- điểm để xếp ô plot: "normalized" = so ở level 1 (đúng ý: pet base mạnh hơn thì phải thay)
function Game.slotScore(entry)
	if CFG.Plot.CompareMode == "current" then
		return Game.income(entry)
	end
	return Game.incomeLv1(entry)
end

-- giá nâng 1 cấp + thời gian hoàn vốn (UnitUtil.lua:26 + PlotClass.lua:167)
function Game.levelInfo(entry)
	if not Mods.UnitUtil then return nil end
	local ok, price = pcall(Mods.UnitUtil.GetLevelPrice, entry.name, entry.attributes)
	if not ok or type(price) ~= "number" then return nil end
	local gain = 0.25 * Game.incomeLv1(entry) * Util.buff("Money Multiplier", 1)
	if gain <= 0 then return { price = price, payback = math.huge, gain = 0 } end
	return { price = price, payback = price / gain, gain = gain }
end

-- giá gốc dùng cho công thức nâng cấp: GetLevelPrice ở level 1 = floor(income({mutation=...}))
function Game.levelBasePrice(entry)
	if not Mods.UnitUtil then return 0 end
	local a = entry.attributes or {}
	local ok, p = pcall(Mods.UnitUtil.GetLevelPrice, entry.name, { mutation = a.mutation, level = 1 })
	return (ok and type(p) == "number") and p or 0
end

-- tổng tiền để kéo 1 pet từ level 1 lên level L (tổng cấp số nhân công bội 1.6)
function Game.costToLevel(entry, L)
	L = math.floor(L or 1)
	if L <= 1 then return 0 end
	local base = Game.levelBasePrice(entry)
	if base <= 0 then return math.huge end
	return base * (1.6 ^ (L - 1) - 1) / 0.6
end

-- Có nên thay pet cũ bằng pet mới không?  trả về (nên, lý do, sốGiâyHoànVốn)
function Game.shouldSwap(oldEntry, newEntry)
	if not oldEntry then return true, "ô trống", 0 end

	local Bo = Game.incomeLv1(oldEntry)
	local Bn = Game.incomeLv1(newEntry)
	local margin = CFG.Plot.SwapMargin or 0
	if Bn <= Bo * (1 + margin) then
		return false, "base không hơn", math.huge
	end

	local force = tonumber(CFG.Plot.ForceSwapRatio) or 0
	if force > 1 and Bo > 0 and Bn >= Bo * force then
		return true, string.format("mạnh gấp %.1f lần", Bn / Bo), 0
	end

	local L = math.max(1, math.floor((oldEntry.attributes or {}).level or 1))
	if L <= 1 then
		-- pet cũ chưa nâng đồng nào -> đổi thẳng, không lỗ gì
		return true, "pet cũ lv1", 0
	end

	local mult  = 1 + 0.25 * (L - 1)
	local gain  = (Bn - Bo) * mult * Util.buff("Money Multiplier", 1)
	if gain <= 0 then return false, "không lời", math.huge end

	local cost    = Game.costToLevel(newEntry, L)
	local payback = cost / gain
	if payback <= (CFG.Plot.SwapPaybackSeconds or 600) then
		return true, string.format("hoàn vốn %ds", math.floor(payback)), payback
	end
	return false, string.format("hoàn vốn %ds quá lâu", math.floor(payback)), payback
end

-- rebirth tới mốc này có mở thêm ô plot nào không? (PlotConfig.GetSlotRebirthRequirement)
function Game.rebirthUnlocksSlot(level)
	if not Mods.PlotConfig then return false end
	local okMax, maxSlots = pcall(Mods.PlotConfig.GetMaxSlots)
	if not okMax then return false end
	for i = 1, maxSlots do
		local okR, need = pcall(Mods.PlotConfig.GetSlotRebirthRequirement, i)
		if okR and need == level then return true, i end
	end
	return false
end

function Game.unlockedSlots()
	local out = {}
	if not Mods.PlotConfig then return out end
	local rb = Util.data("Rebirth", 0)
	local okMax, maxSlots = pcall(Mods.PlotConfig.GetMaxSlots)
	if not okMax then return out end
	for i = 1, maxSlots do
		local okR, need = pcall(Mods.PlotConfig.GetSlotRebirthRequirement, i)
		if okR and rb >= (need or 0) then table.insert(out, i) end
	end
	return out
end

function Game.slots()
	return Util.data("Slots", {}) or {}
end

function Game.inventory()
	return Util.data("Inventory", {}) or {}
end

-- danh sách unit trong túi: { {key=, entry=, score=, chance=, rarity=} }
function Game.unitList()
	local out = {}
	for key, entry in pairs(Game.inventory()) do
		if type(entry) == "table" and Game.unitCfg(entry) then
			table.insert(out, {
				key    = key,
				entry  = entry,
				score  = Game.slotScore(entry),
				chance = Game.chanceOf(entry),
			})
		end
	end
	table.sort(out, function(a, b)
		if a.score == b.score then return a.key < b.key end
		return a.score > b.score
	end)
	return out
end

function Game.unitCount()
	if RT.inventoryObserved and RT.unitCountCache ~= nil then return RT.unitCountCache end
	local n = 0
	for _, entry in pairs(Game.inventory()) do
		if type(entry) == "table" and Game.unitCfg(entry) then n = n + 1 end
	end
	RT.unitCountCache = n
	return n
end

function Game.storageCap()
	-- RollService.lua:140 -> chặn khi UnitStorage + (Rolls-1) <= count
	local pending = Util.data("PendingTrade", nil) -- RollService trong Live_20260915
	local reserved = type(pending) == "table" and not pending.applied and (tonumber(pending.reservedUnits) or 0) or 0
	return math.max(0, Util.buff("Unit Storage", 100) + (Util.buff("Rolls", 1) - 1) - reserved)
end

function Game.plotIncome()
	local mult = Util.buff("Money Multiplier", 1)
	local inv, total = Game.inventory(), 0
	for _, slot in pairs(Game.slots()) do
		if type(slot) == "table" and slot.unitId then
			local e = inv[slot.unitId]
			if e then total = total + Game.income(e) end
		end
	end
	return total * mult
end

-- Các category boost đã thấy đều có đuôi Luck / Income / Damage (BoostConfig.lua).
-- "Dragon Luck" và "Luck" là 2 category KHÁC NHAU -> chạy song song, nhân dồn.
function Game.boostKind(category)
	if type(category) ~= "string" then return nil end
	if category:sub(-4) == "Luck"   then return "Luck"   end
	if category:sub(-6) == "Income" then return "Income" end
	if category:sub(-6) == "Damage" then return "Damage" end
	return nil
end

-- số boost đang còn trong túi theo từng category
-- Món bị khóa thì mọi chỗ tiêu đồ đều phải bỏ qua.
-- Gồm: danh sách CFG.LockedItems và món đang giữ lại để đổi acc.
function Game.isLocked(name)
	if type(name) ~= "string" then return false end
	local want = name:lower()
	for _, locked in ipairs(CFG.LockedItems or {}) do
		if type(locked) == "string" and locked:lower() == want then return true end
	end
	-- AccountSwap khai báo sau Game trong file; guard cho chắc nếu load dở.
	if type(AccountSwap.armed) == "function" and AccountSwap.armed()
		and type(CFG.AccountSwap.Item) == "string"
		and CFG.AccountSwap.Item:lower() == want then
		return true
	end
	return false
end

function Game.boostStock()
	local stock = {}
	if not Mods.EntryRegistry then return stock end
	for _, e in pairs(Game.inventory()) do
		if type(e) == "table" and e.name and (e.amount or 0) > 0 then
			local ok, cfg = pcall(Mods.EntryRegistry.getEntryConfig, e.name)
			if ok and type(cfg) == "table" and cfg.kind == "Boost" and cfg.category then
				stock[cfg.category] = (stock[cfg.category] or 0) + e.amount
			end
		end
	end
	return stock
end

-- category nào đang có boost CHẠY (đã được server cấp startedAt)
function Game.boostRunning()
	local run = {}
	if not Mods.EntryRegistry then return run end
	local now = workspace:GetServerTimeNow()
	for _, e in pairs(Util.data("ActiveEntries", {}) or {}) do
		if type(e) == "table" and e.name and type(e.startedAt) == "number"
			and type(e.remaining) == "number" and e.remaining > (now - e.startedAt) then
			local ok, cfg = pcall(Mods.EntryRegistry.getEntryConfig, e.name)
			if ok and type(cfg) == "table" and cfg.kind == "Boost" and cfg.category then
				run[cfg.category] = e.name
			end
		end
	end
	return run
end

function Game.towerTeamSet()
	local set = {}
	for _, k in pairs(Util.data("TowerTeam", {}) or {}) do
		if type(k) == "string" then set[k] = true end
	end
	return set
end

function Game.slottedSet()
	local set = {}
	for _, slot in pairs(Game.slots()) do
		if type(slot) == "table" and slot.unitId then set[slot.unitId] = true end
	end
	return set
end

--==============================================================================
-- 7. GIAO DIỆN
--==============================================================================
-- Bảo vệ và thông báo dùng dữ liệu inventory thật, kể cả khi roll từ UI game.
local Keep = {}
local Notice = {}
local TicketShop = {}
local AccountSwap = {}
local Performance = {}
local WorldCleanup = {}

function Game.dumpRarities()
	local rows = {}
	for ref, name in pairs((Mods.Rarities and Mods.Rarities.Refs) or {}) do
		local meta = Util.get(function() return Mods.Rarities.Get(name) end)
		table.insert(rows, { ref = ref, name = name, order = meta and meta.sortOrder,
			floor = Game.RARITY_FLOOR[name], configured = meta ~= nil })
	end
	table.sort(rows, function(a, b)
		if a.order == b.order then return a.name < b.name end
		return (a.order or math.huge) < (b.order or math.huge)
	end)
	for _, row in ipairs(rows) do
		print("[KAITUN RARITY] " .. row.name .. " | floor=" .. (row.floor and string.format("%.17g", row.floor) or "chưa có")
			.. " | " .. (row.configured and "có metadata" or "chỉ có Refs"))
	end
	return rows
end

function Game.isSpecialRarity(entry)
	local rarity = Game.rarityOf(entry)
	if type(rarity) ~= "string" then return true end -- thiếu metadata: vẫn xét thông báo
	if rarity:lower():find("secret", 1, true) then return true end
	if not Mods.Rarities then return true end
	local ok, cfg = pcall(Mods.Rarities.Get, rarity)
	local okS, secret = pcall(Mods.Rarities.Get, "Secret I")
	if not ok or not okS or not cfg or not secret then return true end
	return not cfg.sortOrder or cfg.sortOrder >= secret.sortOrder
end

function Notice.eligible(entry)
	if Game.isSpecialRarity(entry) then return true end
	local r = Game.rarityOf(entry)
	return r ~= nil and Game.raritySort(r) >= Game.raritySort(CFG.Webhook.MinRarity)
end

function Game.validChance(entry)
	local chance = Game.chanceOf(entry)
	if type(chance) == "number" and chance == chance and chance > 0 and chance < math.huge then return chance end
	return nil
end

function Game.isSecret(entry)
	local rarity = Game.rarityOf(entry)
	return type(rarity) == "string" and rarity:lower():find("secret", 1, true) ~= nil
end

function Game.plotChanceFloor()
	local inv, lowest, count = Game.inventory(), nil, 0
	for _, slot in pairs(Game.slots()) do
		if type(slot) == "table" and slot.unitId then
			local entry = inv[slot.unitId]
			if not entry or not Game.unitCfg(entry) then return nil, "chờ đồng bộ pet plot" end
			local chance = Game.validChance(entry)
			if chance then lowest = lowest and math.min(lowest, chance) or chance; count = count + 1 end
		end
	end
	if not lowest then return nil, "chưa có pet plot với chance hợp lệ" end
	return lowest, nil, count
end

-- Mốc bán lấy từ ĐỘI HÌNH PLOT ĐANG MANG (đúng ý: "chance thấp nhất mà plot đang mang").
-- Phần "luôn mang pet xịn" do Plot.tick + Game.shouldSwap lo; khi plot đã mang con tốt nhất
-- thì mốc này tự dâng lên và rác tự động bị bán.
-- Trả về: chanceFloor, lý do, incomeFloor (income quy về level 1), số pet đã xét.
function Game.lineup()
	local inv, chanceFloor, incomeFloor, count = Game.inventory(), nil, nil, 0
	for _, slot in pairs(Game.slots()) do
		if type(slot) == "table" and slot.unitId then
			local entry = inv[slot.unitId]
			if not entry or not Game.unitCfg(entry) then return nil, "chờ đồng bộ pet plot" end
			local chance = Game.validChance(entry)
			if chance then
				chanceFloor = chanceFloor and math.min(chanceFloor, chance) or chance
				count = count + 1
				local income = Game.incomeLv1(entry)
				if type(income) == "number" and income == income and income < math.huge then
					incomeFloor = incomeFloor and math.min(incomeFloor, income) or income
				end
			end
		end
	end
	if not chanceFloor then return nil, "chưa có pet plot với chance hợp lệ" end
	return chanceFloor, nil, incomeFloor, count
end

function Game.keepForChance(key, entry, threshold, slotted, team, incomeFloor)
	if slotted[key] or team[key] then return true end
	local chance = Game.validChance(entry)
	if not threshold or not chance or chance > threshold then return true end
	if CFG.Sell.UseIncomeGuard and incomeFloor then
		local income = Game.incomeLv1(entry)
		-- thiếu số liệu hoặc khỏe hơn đội hình -> giữ
		if type(income) ~= "number" or income ~= income then return true end
		if income > incomeFloor then return true end
	end
	if (entry.attributes or {}).locked then
		return not (CFG.Sell.UnlockWeakSecrets and Game.isSecret(entry))
	end
	return false
end

function Keep.buildCeiling()
	local threshold, why, incomeFloor = Game.lineup()
	RT.sellChance, RT.sellChanceWhy, RT.sellIncomeFloor = threshold, why, incomeFloor
	-- SellService.UpdateAutoSell chấp nhận tối đa 1e18. Phần còn lại bán bằng SellInventory.
	RT.autoSellCeiling = threshold and math.min(threshold, 1e18) or 0
end

function Keep.syncAutoSell(wanted)
	Keep.buildCeiling()
	local actual = Util.data("AutoSell", nil)
	if type(actual) ~= "number" then RT.autoSellReady = false return false end
	local target = RT.autoSellCeiling
	if not CFG.Sell.Enabled or not CFG.Sell.ServerAutoSell or RT.busyEquip or wanted == 0 then target = 0 end
	RT.autoSellTarget = target
	if actual ~= target and Net.UpdAutoSell and (RT.lastAutoSellTarget ~= target
		or os.clock() - (RT.lastAutoSellSent or 0) >= 1) then
		local ok = pcall(function() Net.UpdAutoSell:FireServer(target) end)
		if ok then RT.lastAutoSellTarget, RT.lastAutoSellSent = target, os.clock() end
	end
	RT.autoSellReady = actual <= target
	return RT.autoSellReady
end

function Notice.payload(entry)
	local a = entry.attributes or {}
	local chance = Game.chanceOf(entry)
	local function field(name, value)
		return { name = name, value = tostring(value):sub(1, 900), inline = true }
	end
	return {
		username = "Anime Dice Kaitun",
		allowed_mentions = { parse = {} },
		embeds = { {
			title = ("Pet mới: " .. tostring(entry.name)):sub(1, 240),
			color = 10181046,
			fields = {
				field("Tài khoản", LP.Name), field("Rarity", Game.rarityOf(entry) or "chưa xác định"),
				field("Độ hiếm hiển thị", chance and ("1 / " .. string.format("%.17g", chance)) or "Không có chance trong source"),
				field("Mutation", a.mutation or "không"), field("Level", a.level or 1),
				field("Trait", a.trait or "không"), field("Grade", a.grade or "không"),
				field("Damage pet", string.format("%.6g", Game.damageOf(entry))),
				field("HP pet", string.format("%.6g", Game.healthOf(entry))),
				field("Income pet /s", string.format("%.6g", Game.income(entry))),
			},
			footer = { text = "Chance từ UnitConfig, gồm mutation; không phải xác suất thực sau luck và chuẩn hóa RollUtil. Thông số pet chưa nhân buff tài khoản." },
		} },
	}
end

function Notice.enqueue(entry)
	if not CFG.Webhook.Enabled or CFG.Webhook.URL == "" or not Notice.eligible(entry) then return end
	if #RT.noticeQueue >= math.max(1, CFG.Webhook.MaxQueue) then
		RT.noticeDropped = (RT.noticeDropped or 0) + 1
		Util.log("Webhook", "hàng đợi đầy, bỏ thông báo mới")
		return
	end
	table.insert(RT.noticeQueue, { payload = Notice.payload(entry), attempts = 0, at = 0 })
end

function Notice.tick()
	if not CFG.Webhook.Enabled then RT.status.Webhook = "tắt" return end
	local url = CFG.Webhook.URL
	if type(url) ~= "string" or url == "" then RT.status.Webhook = "chưa điền URL" return end
	local host, path = url:match("^https://([^/]+)(/.*)$")
	if (host ~= "discord.com" and host ~= "discordapp.com") or not path
		or not path:match("^/api/webhooks/%d+/[%w_%-]+$") then
		RT.status.Webhook = "URL webhook Discord không hợp lệ"
		return
	end
	local send = request or http_request or (syn and syn.request)
	if type(send) ~= "function" then RT.status.Webhook = "executor thiếu HTTP request" return end
	local item = RT.noticeQueue[1]
	if not item or os.clock() < item.at then return end
	local okBody, body = pcall(function() return Svc.Http:JSONEncode(item.payload) end)
	if not okBody then
		table.remove(RT.noticeQueue, 1)
		Util.log("Webhook", "không mã hóa được payload")
		return
	end
	item.attempts = item.attempts + 1
	-- API ngoài game: docs.discord.com/developers/resources/webhook.
	local ok, response = pcall(send, {
		Url = url .. "?wait=true", Method = "POST",
		Headers = { ["Content-Type"] = "application/json" }, Body = body,
	})
	local status = ok and type(response) == "table" and tonumber(response.StatusCode) or 0
	if status >= 200 and status < 300 then
		table.remove(RT.noticeQueue, 1)
		RT.noticeSent = (RT.noticeSent or 0) + 1
		RT.status.Webhook = "đã gửi " .. RT.noticeSent
		return
	end
	local delay = math.min(120, 2 ^ item.attempts)
	if status == 429 then
		local decoded = Util.get(function() return Svc.Http:JSONDecode(response.Body) end, {})
		local headers = response.Headers or {}
		delay = math.max(delay, tonumber(decoded.retry_after) or 0,
			tonumber(headers["Retry-After"] or headers["retry-after"]) or 0) + 0.5
	end
	-- Không log lỗi HTTP thô: executor có thể đính kèm token webhook vào lỗi.
	RT.status.Webhook = "HTTP " .. tostring(status) .. ", chờ thử lại"
	if item.attempts >= CFG.Webhook.MaxAttempts or (status >= 400 and status < 500 and status ~= 429) then
		table.remove(RT.noticeQueue, 1)
		Util.log("Webhook", "gửi thất bại (HTTP " .. tostring(status) .. "), đã bỏ khỏi hàng đợi")
	else
		item.at = os.clock() + delay
	end
end

function Keep.tick()
	Keep.syncAutoSell()
	if RT.inventoryObserved and not RT.inventoryDirty and os.clock() - (RT.lastKeepScan or 0) < 3 then return end
	RT.inventoryDirty = false
	RT.lastKeepScan = os.clock()
	local inv, seen, count, kept = Game.inventory(), {}, 0, 0
	local slotted, team = Game.slottedSet(), Game.towerTeamSet()
	for key, entry in pairs(inv) do
		if type(entry) == "table" and Game.unitCfg(entry) then
			count = count + 1
			seen[key] = true
			if not RT.noticeSeen[key] and (RT.noticeInitialized or CFG.Webhook.NotifyExisting) then Notice.enqueue(entry) end
			if Game.keepForChance(key, entry, RT.sellChance, slotted, team) then kept = kept + 1 end
		end
	end
	RT.noticeSeen, RT.noticeInitialized, RT.unitCountCache = seen, true, count
	RT.protectedCount = kept
	RT.status.Keep = "giữ " .. kept .. " pet theo chance/plot/tower/khóa"
end

function Game.tokenAmount(name)
	local n = 0
	for _, entry in pairs(Game.inventory()) do
		if type(entry) == "table" and entry.name == name then n = n + (tonumber(entry.amount) or 0) end
	end
	return n
end

function Game.tokenFlow(name, field)
	local ledger = RT.tokenLedger and RT.tokenLedger[name]
	return ledger and ledger[field] or 0
end

function TicketShop.shopEntry(name)
	for _, cfg in ipairs((Mods.QuestConfig and Mods.QuestConfig.Shop) or {}) do
		if cfg.name == name then return cfg end
	end
	return nil
end

-- Chỉ nhận món có thật trong QuestConfig.Shop; tên sai thì bỏ qua thay vì đoán.
function TicketShop.items()
	local out = {}
	for _, name in ipairs(CFG.TicketShop.Items or {}) do
		local cfg = TicketShop.shopEntry(name)
		if cfg and cfg.tickets and (not cfg.gamepass or CFG.TicketShop.AllowGamepass) then
			out[#out + 1] = { name = name, cfg = cfg }
		end
	end
	return out
end

function TicketShop.choose(state)
	local list = TicketShop.items()
	if #list == 0 then return nil end
	if CFG.TicketShop.Mode == "priority" then
		local spare = Game.tokenAmount("Tickets") - (CFG.TicketShop.Reserve or 0)
		for _, item in ipairs(list) do
			if spare >= item.cfg.tickets then return item end
		end
		return list[1]
	end
	for _, item in ipairs(list) do
		if item.name == state.next then return item end
	end
	return list[1]
end

function TicketShop.advance(state, name)
	local list = TicketShop.items()
	if #list == 0 then state.next = nil return end
	for i, item in ipairs(list) do
		if item.name == name then state.next = list[i % #list + 1].name return end
	end
	state.next = list[1].name
end

function TicketShop.tick()
	if not CFG.TicketShop.Enabled or not Net.QuestBuy then RT.status.TicketShop = "tắt/thiếu remote" return end
	local state = RT.ticketState
	local pending = state.pending
	if pending then
		-- Chỉ chuyển lượt khi đã TRỪ vé và đã NHẬN món; không đổi lượt chỉ vì FireServer thành công.
		local paid = Game.tokenFlow("Tickets", "spent") - (pending.spent or 0) >= (pending.cost or 1)
			or Game.tokenAmount("Tickets") <= (pending.ticketsBefore or 0) - (pending.cost or 1)
		local received
		if pending.gamepass then
			-- Gamepass không vào Inventory; QuestService gọi PurchaseGamepassWithTickets.
			received = (Util.data("OwnedGamepasses", {}) or {})[pending.name] == true
		else
			received = Game.tokenFlow(pending.name, "gained") - (pending.gained or 0) >= pending.amount
				or Game.tokenAmount(pending.name) >= pending.before + pending.amount
		end
		if received and paid then
			TicketShop.advance(state, pending.name)
			state.pending = nil
			RT.status.TicketShop = "đã đổi " .. pending.name
		else
			RT.status.TicketShop = os.clock() - pending.at > 8 and "chờ xác nhận đổi vé (không gửi trùng)" or "chờ nhận " .. pending.name
			return
		end
	end
	local item = TicketShop.choose(state)
	if not item then RT.status.TicketShop = "danh sách đổi vé trống / tên không có trong shop" return end
	state.next = item.name
	local product = item.cfg
	if Game.tokenAmount("Tickets") - (CFG.TicketShop.Reserve or 0) < product.tickets then
		RT.status.TicketShop = "chờ vé → " .. item.name
		return
	end
	state.pending = { name = item.name, gamepass = product.gamepass == true,
		before = Game.tokenAmount(item.name), amount = product.amount or 1,
		cost = product.tickets, ticketsBefore = Game.tokenAmount("Tickets"),
		gained = Game.tokenFlow(item.name, "gained"), spent = Game.tokenFlow("Tickets", "spent"), at = os.clock() }
	local ok = pcall(function() Net.QuestBuy:FireServer(item.name) end)
	if not ok then state.pending = nil end
end

function Performance.apply()
	if not CFG.Performance.Enabled then return end
	if CFG.Performance.DisableWind then
		RT.oldWindDisabled = LP:GetAttribute("WindDisabled")
		LP:SetAttribute("WindDisabled", true) -- WindController: Cleanup/Pause, giữ collision/map
		RT.windChanged = true
	end
	Util.log("Performance", "tắt gió; giới hạn cache/log, dọn connection khi Stop; giữ object gameplay")
end

-- Dọn theo _tree.txt và PlotController/CharacterService/ZoneUtil trong dump AnimeDice.
-- Không ClearAllChildren Workspace: Zones, camera, nhân vật, Limiteds và Debris đang có controller dùng.
WorldCleanup.MAP_CLASSES = {
	["Palm Tree"] = "Model", Model = "Model", Stand = "Model", Wind = "Model",
	cylidner2 = "Model", CastleTower = "Model", ["Rock 1"] = "MeshPart", Grass = "MeshPart",
}

-- Lột ở mọi nhánh KHÔNG phải plot mình: những thứ này chỉ để nhìn/nghe.
WorldCleanup.STRIP_CLASSES = {
	ParticleEmitter = true, Trail = true, Beam = true, Smoke = true, Fire = true,
	Sparkles = true, Explosion = true, Sound = true, Decal = true, Texture = true,
	BillboardGui = true, SurfaceGui = true, PointLight = true, SpotLight = true,
	SurfaceLight = true, Highlight = true, ClickDetector = true,
}

-- Trong plot mình chỉ lột phần chắc chắn vô hại: PlotController còn đọc
-- Balance/Main/SurfaceGui/Hitbox và ProximityPrompt của chính plot đó.
WorldCleanup.SAFE_STRIP_CLASSES = {
	ParticleEmitter = true, Trail = true, Beam = true, Smoke = true, Fire = true,
	Sparkles = true, Explosion = true, Sound = true,
}

function WorldCleanup.shouldStrip(className, inOwnPlot)
	if inOwnPlot then
		if not CFG.WorkspaceCleanup.StripOwnPlot then return false end
		return WorldCleanup.SAFE_STRIP_CLASSES[className] == true
	end
	return WorldCleanup.STRIP_CLASSES[className] == true
end

function WorldCleanup.contains(root, node)
	return node and (node == root or node:IsDescendantOf(root)) or false
end

function WorldCleanup.ownPlot()
	-- PlotController.plot lấy từ property PlotId của server, không đoán theo tên account/khoảng cách.
	local plots = workspace:FindFirstChild("Plots")
	local claimed = plots and plots:FindFirstChild("Claimed")
	local own = Mods.PlotC and Mods.PlotC.plot
	if typeof(own) ~= "Instance" or not own:IsA("Model") or not claimed or own.Parent ~= claimed then
		return nil, "chờ xác nhận plot của mình"
	end
	local spawn = own:FindFirstChild("Spawn")
	if not own:FindFirstChild("Slots") or not spawn or not spawn:IsA("BasePart") then
		return nil, "chờ plot tải đủ Slots/Spawn"
	end
	return own, nil, claimed, plots:FindFirstChild("Unclaimed")
end

function WorldCleanup.ground(position)
	-- Raycast như PlotController; bỏ part không va chạm để không nhầm VFX/zone là nền.
	local ignore = {}
	for _, node in pairs({ workspace:FindFirstChild("Players"), LP.Character,
		workspace:FindFirstChild("Zones"), workspace:FindFirstChild("Debris"), workspace.CurrentCamera }) do
		ignore[#ignore + 1] = node
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	for _ = 1, 12 do
		params.FilterDescendantsInstances = ignore
		local hit = workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -100, 0), params)
		if not hit then return nil end
		local part = hit.Instance
		if part:IsA("Terrain") or (part:IsA("BasePart") and part.CanCollide) then return part end
		ignore[#ignore + 1] = part
	end
	return nil
end

function WorldCleanup.context()
	if game.PlaceId ~= 113290951185459 then return nil, "không phải Anime Dice" end
	local own, why, claimed, unclaimed = WorldCleanup.ownPlot()
	if not own then return nil, why end
	local character = LP.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local hum = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 or not character:IsDescendantOf(workspace) then
		return nil, "chờ nhân vật"
	end
	local floor = WorldCleanup.ground(root.Position)
	if not floor then return nil, "chờ xác định nền dưới nhân vật" end
	local ctx = { own = own, claimed = claimed, unclaimed = unclaimed,
		map = workspace:FindFirstChild("Map"), supports = { floor } }
	local anchors = { own:FindFirstChild("Spawn"), workspace:FindFirstChild("SpawnLocation") }
	local zones = workspace:FindFirstChild("Zones")
	if zones then
		for _, part in ipairs(zones:GetDescendants()) do
			if part:IsA("BasePart") then anchors[#anchors + 1] = part end
		end
	end
	for _, anchor in pairs(anchors) do
		if anchor and anchor:IsA("BasePart") then
			local support = WorldCleanup.ground(anchor.Position)
			if support then ctx.supports[#ctx.supports + 1] = support end
		end
	end
	return ctx
end

function WorldCleanup.isSupport(node, ctx)
	if WorldCleanup.contains(node, ctx.own) or WorldCleanup.contains(node, LP.Character)
		or WorldCleanup.contains(node, workspace.CurrentCamera) then return true end
	for _, part in ipairs(ctx.supports) do
		if WorldCleanup.contains(node, part) then return true end
	end
	return false
end

function WorldCleanup.mapReason(node)
	if CFG.WorkspaceCleanup.Aggressive then
		-- Nền thật đã được isSupport giữ bằng raycast, nên ở đây chỉ cần chừa chỗ hồi sinh
		-- và nhánh có script để controller của game không văng lỗi.
		for _, child in ipairs(node:GetDescendants()) do
			if child:IsA("SpawnLocation") then return "chỗ hồi sinh" end
			if child:IsA("LuaSourceContainer") then return "nhánh có script" end
		end
		if node:IsA("SpawnLocation") then return "chỗ hồi sinh" end
		return nil
	end
	-- Ground Part Grass khác MeshPart Grass trang trí; giữ toàn bộ Baseplate/Sand/Path và Part Grass.
	if node:IsA("BasePart") and (node.Name == "Baseplate" or node.Name == "Sand"
		or node.Name == "Path" or (node.Name == "Grass" and node:IsA("Part"))) then return "nền/đường đi" end
	local class = WorldCleanup.MAP_CLASSES[node.Name]
	if not class or node.ClassName ~= class then return "object map chưa xác nhận" end
	-- Conveyor có script server trong dump; giữ nguyên nhánh cơ chế/tương tác thay vì đoán là rác.
	for _, child in ipairs(node:GetDescendants()) do
		if child:IsA("LuaSourceContainer") or child:IsA("ProximityPrompt") or child:IsA("ClickDetector")
			or child:IsA("TouchTransmitter") or child:IsA("Humanoid") or child:IsA("SpawnLocation") then
			return "nhánh có script/tương tác/nhân vật"
		end
	end
	return nil
end

function WorldCleanup.plan()
	-- Chỉ đọc: cho phép xem trước target/reason mà không xóa hoặc gửi remote.
	local ctx, why = WorldCleanup.context()
	local plan = { targets = {}, kept = {}, reason = why, context = ctx }
	if not ctx then return plan end
	local function add(node, kind)
		if WorldCleanup.isSupport(node, ctx) then plan.kept[node] = "plot mình/nền cần giữ" return end
		if kind == "map" then
			local reason = WorldCleanup.mapReason(node)
			if reason then plan.kept[node] = reason return end
		end
		plan.targets[#plan.targets + 1] = { node = node, kind = kind }
	end
	if CFG.WorkspaceCleanup.OtherPlots then
		for _, container in pairs({ ctx.claimed, ctx.unclaimed }) do
			for _, plot in ipairs(container:GetChildren()) do
				if plot:IsA("Model") and plot ~= ctx.own then add(plot, "plot") end
			end
		end
	end
	if CFG.WorkspaceCleanup.MapDecor and ctx.map then
		for _, node in ipairs(ctx.map:GetChildren()) do add(node, "map") end
	end
	if CFG.WorkspaceCleanup.OtherCharacters then
		-- CharacterService.lua:20 parent nhân vật vào workspace.Players; isSupport giữ nhân vật mình.
		local folder = workspace:FindFirstChild("Players")
		if folder then
			for _, node in ipairs(folder:GetChildren()) do add(node, "nhân vật") end
		end
	end
	if CFG.WorkspaceCleanup.Limiteds then
		local node = workspace:FindFirstChild("Limiteds")
		if node then add(node, "limited") end
	end
	if CFG.WorkspaceCleanup.DebrisChildren then
		local folder = workspace:FindFirstChild("Debris")
		if folder then
			for _, node in ipairs(folder:GetChildren()) do add(node, "debris") end
		end
	end
	if CFG.WorkspaceCleanup.Zones then
		local node = workspace:FindFirstChild("Zones")
		if node then add(node, "zone") end
	end
	if CFG.WorkspaceCleanup.PlotPositions then
		local node = workspace:FindFirstChild("PlotPositions")
		if node then add(node, "vị trí plot") end
	end
	if CFG.WorkspaceCleanup.Rigs then
		local node = workspace:FindFirstChild("R6")
		if node then add(node, "rig mẫu") end
	end
	if CFG.WorkspaceCleanup.Leaderboards then
		-- Chỉ LeaderboardService phía server truy cập hai nhánh này; không đụng LimitedUnitController.
		for _, name in ipairs({ "Leaderboards", "BestRollPoduium" }) do
			local node = workspace:FindFirstChild(name)
			if node and (node:IsA("Folder") or node:IsA("Model")) then add(node, "leaderboard") end
		end
	end
	return plan
end

-- Lột hiệu ứng ở những nhánh buộc phải giữ. Không đụng nhân vật mình và camera.
function WorldCleanup.strip(ctx)
	if not CFG.WorkspaceCleanup.StripEffects then return 0, 0 end
	local budget = math.max(1, math.floor(tonumber(CFG.WorkspaceCleanup.StripBatch) or 400))
	local stripped, hidden = 0, 0
	local own, character = ctx.own, LP.Character
	local hideKept = CFG.WorkspaceCleanup.HideKeptParts
	local ok, list = pcall(function() return workspace:GetDescendants() end)
	if not ok then return 0, 0 end
	for _, node in ipairs(list) do
		if stripped + hidden >= budget then break end
		if node.Parent and not WorldCleanup.contains(node, character)
			and not WorldCleanup.contains(node, workspace.CurrentCamera) then
			local inOwnPlot = own and node:IsDescendantOf(own) or false
			if WorldCleanup.shouldStrip(node.ClassName, inOwnPlot) then
				if pcall(function() node:Destroy() end) then stripped = stripped + 1 end
			elseif hideKept and not inOwnPlot and node:IsA("BasePart")
				and node.Transparency < 1 and not WorldCleanup.isSupport(node, ctx) then
				-- Nhánh giữ lại vì có script: xóa part có thể làm script văng lỗi,
				-- nên chỉ cho tàng hình, không đổi CanCollide.
				if pcall(function() node.Transparency = 1 end) then hidden = hidden + 1 end
			end
		end
	end
	return stripped, hidden
end

function WorldCleanup.lighting()
	if not CFG.WorkspaceCleanup.Lighting or RT.lightingCleared then return 0 end
	local ok, lighting = pcall(function() return game:GetService("Lighting") end)
	if not ok or not lighting then return 0 end
	local removed = 0
	for _, node in ipairs(lighting:GetChildren()) do
		if node:IsA("PostEffect") or node:IsA("Atmosphere") or node:IsA("Clouds") then
			if pcall(function() node:Destroy() end) then removed = removed + 1 end
		end
	end
	RT.lightingCleared = true
	if removed > 0 then Util.log("Cleanup", "xóa " .. removed .. " hiệu ứng Lighting") end
	return removed
end

function WorldCleanup.tick()
	if not CFG.WorkspaceCleanup.Enabled then RT.status.Cleanup = "tắt" return end
	local plan = WorldCleanup.plan()
	if not plan.context then RT.status.Cleanup = plan.reason return end
	local removed, plots, instances = 0, 0, 0
	if CFG.WorkspaceCleanup.ClearTerrain and not RT.terrainCleared then
		local terrain = workspace:FindFirstChildOfClass("Terrain")
		-- Terrain không Destroy được; Clear() xóa voxel và không đụng part nào.
		if terrain and pcall(function() terrain:Clear() end) then
			RT.terrainCleared = true
			Util.log("Cleanup", "đã xóa terrain")
		end
	end
	local limit = math.max(1, math.min(10, math.floor(tonumber(CFG.WorkspaceCleanup.BatchSize) or 2)))
	for _, target in ipairs(plan.targets) do
		if not RT.running or not CFG.WorkspaceCleanup.Enabled or removed >= limit then break end
		-- Xác nhận lại owner ngay trước Destroy; không xóa khi controller đang đổi plot.
		if WorldCleanup.ownPlot() ~= plan.context.own then break end
		local node = target.node
		if node.Parent and node:IsDescendantOf(workspace) and not WorldCleanup.isSupport(node, plan.context) then
			local count = #node:GetDescendants() + 1
			local ok = pcall(function() node:Destroy() end)
			if ok then
				removed, instances = removed + 1, instances + count
				if target.kind == "plot" then plots = plots + 1 end
				-- Destroying của PlotController dọn cả thư mục chứa slot xa ở dưới module.
			else Util.log("Cleanup", "không xóa được một nhánh " .. target.kind) end
		end
	end
	WorldCleanup.lighting()
	local stripped, hidden = WorldCleanup.strip(plan.context)
	RT.strippedFx = (RT.strippedFx or 0) + stripped
	RT.hiddenParts = (RT.hiddenParts or 0) + hidden
	RT.cleanedRoots = (RT.cleanedRoots or 0) + removed
	RT.cleanedPlots = (RT.cleanedPlots or 0) + plots
	RT.cleanedInstances = (RT.cleanedInstances or 0) + instances
	RT.status.Cleanup = string.format("%d plot / %d object / %d hiệu ứng / %d part ẩn",
		RT.cleanedPlots, RT.cleanedInstances, RT.strippedFx or 0, RT.hiddenParts or 0)
	if removed > 0 then Util.log("Cleanup", "dọn " .. removed .. " nhánh (" .. plots .. " plot), " .. instances .. " object") end
	-- Không lưu plan/instance đã xóa, không clone backup; lượt sau đọc lại container để xử lý spawn/stream lại.
end

-- ĐỔI ACC KHI TRÚNG ĐỒ XỊN.
-- getgenv().client:ChangeToFolder(from, to, replace, configId) là API FarmSync,
-- KHÔNG có trong dump AnimeDice -> chỉ gọi khi kiểm tra thấy đủ client và hàm đó.
function AccountSwap.count()
	local name = CFG.AccountSwap.Item
	if type(name) ~= "string" or name == "" then return 0 end
	return Game.tokenAmount(name)
end

-- Đang chờ đổi acc thì giữ món điều kiện lại, không cho module khác tiêu.
function AccountSwap.armed()
	if not CFG.AccountSwap.Enabled or RT.swapDone then return false end
	return CFG.AccountSwap.KeepItem == true
end

function AccountSwap.client()
	local ok, client = pcall(function() return getgenv().client end)
	if not ok or client == nil then return nil, "không thấy getgenv().client (FarmSync)" end
	local okFn, fn = pcall(function() return client.ChangeToFolder end)
	if not okFn or type(fn) ~= "function" then return nil, "client không có ChangeToFolder" end
	return client, nil
end

function AccountSwap.tick()
	local cfg = CFG.AccountSwap
	if not cfg.Enabled then RT.status.Swap = "tắt" return end
	if RT.swapDone then RT.status.Swap = "đã đổi acc, chờ FarmSync xử lý" return end
	if type(cfg.FromFolder) ~= "string" or cfg.FromFolder == ""
		or type(cfg.ToFolder) ~= "string" or cfg.ToFolder == "" then
		RT.status.Swap = "chưa điền FromFolder/ToFolder"
		return
	end
	local need = math.max(1, math.floor(tonumber(cfg.Amount) or 1))
	local have = AccountSwap.count()
	if have < need then
		RT.status.Swap = string.format("chờ %s: %d/%d", tostring(cfg.Item), have, need)
		return
	end
	local client, why = AccountSwap.client()
	if not client then RT.status.Swap = why return end
	RT.swapDone = true
	Util.log("Swap", string.format("có %d %s -> đổi acc sang folder %s", have, tostring(cfg.Item), tostring(cfg.ToFolder)))
	local ok, changed = pcall(function()
		return client:ChangeToFolder(cfg.FromFolder, cfg.ToFolder, cfg.Replace == true, cfg.ConfigId)
	end)
	if not ok then
		RT.swapDone = false
		RT.status.Swap = "gọi ChangeToFolder lỗi"
		Util.log("Swap", "ChangeToFolder lỗi: " .. tostring(changed))
		return
	end
	RT.swapResult = changed
	RT.status.Swap = changed and "đã yêu cầu đổi acc" or "FarmSync từ chối đổi"
	if not changed then
		RT.swapDone = false
		Util.log("Swap", "FarmSync trả về false, sẽ thử lại lượt sau")
	end
end

-- CHỐNG KẸT: mốc thời gian đổi mỗi khi tiền hoặc số lần roll thay đổi.
local Watchdog = {}

function Watchdog.sample(now, money, rolls)
	if RT.wdMoney ~= money then RT.wdMoney, RT.wdMoneyAt = money, now end
	if RT.wdRolls ~= rolls then RT.wdRolls, RT.wdRollsAt = rolls, now end
	if not RT.wdMoneyAt then RT.wdMoneyAt = now end
	if not RT.wdRollsAt then RT.wdRollsAt = now end
end

-- rollWatched = Auto Roll đang thật sự chạy. Tắt roll thì không coi là kẹt.
function Watchdog.stuck(now, rollWatched)
	if not rollWatched then return false, "roll đang tắt, tạm nghỉ" end
	local limit = math.max(30, tonumber(CFG.Watchdog.StuckSeconds) or 300)
	local moneyIdle = now - (RT.wdMoneyAt or now)
	local rollIdle  = now - (RT.wdRollsAt or now)
	local moneyStuck, rollStuck = moneyIdle >= limit, rollIdle >= limit
	local hit = (CFG.Watchdog.RequireBoth ~= false) and (moneyStuck and rollStuck)
		or ((CFG.Watchdog.RequireBoth == false) and (moneyStuck or rollStuck))
	if hit then
		return true, string.format("tiền đứng %ds, không roll %ds", math.floor(moneyIdle), math.floor(rollIdle))
	end
	return false, string.format("tiền %ds / roll %ds (mốc %ds)",
		math.floor(moneyIdle), math.floor(rollIdle), limit)
end

function Watchdog.fire(reason)
	if RT.watchdogFired then return false end
	RT.watchdogFired = true
	local action = CFG.Watchdog.Action or "rejoin"
	Util.log("Watchdog", "KẸT: " .. reason .. " -> " .. action)
	if action == "log" then return true end
	if action == "kick" then
		pcall(function() LP:Kick("KAITUN stuck: " .. reason) end)
		return true
	end
	-- rejoin: sang server khác cho chắc, hỏng thì kick để FarmSync tự vào lại.
	local ok = pcall(function()
		game:GetService("TeleportService"):Teleport(game.PlaceId, LP)
	end)
	if not ok then pcall(function() LP:Kick("KAITUN stuck: " .. reason) end) end
	return true
end

function Watchdog.tick()
	if not CFG.Watchdog.Enabled then RT.status.Watchdog = "tắt" return end
	-- Đang chờ FarmSync đổi acc thì đừng đụng vào phiên.
	if RT.swapDone then RT.status.Watchdog = "chờ đổi acc" return end
	local now = os.clock()
	Watchdog.sample(now, Util.data("Money", 0), RT.rollOk or 0)
	local rollWatched = CFG.Roll.Enabled == true and groupAllows("Roll") == true
	local stuck, why = Watchdog.stuck(now, rollWatched)
	RT.status.Watchdog = why
	if stuck then Watchdog.fire(why) end
end

local UI = { rows = {}, toggles = {} }

local function mk(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props or {}) do o[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function corner(p, r)
	mk("UICorner", { CornerRadius = UDim.new(0, r or 8) }, p)
end

local function stroke(p, col, th)
	mk("UIStroke", {
		Color = col or Color3.fromRGB(90, 170, 255),
		Thickness = th or 1.4,
		Transparency = 0.35,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, p)
end

local C = {
	bg      = Color3.fromRGB(16, 18, 24),
	panel   = Color3.fromRGB(23, 26, 34),
	row     = Color3.fromRGB(28, 32, 42),
	accent  = Color3.fromRGB(90, 170, 255),
	on      = Color3.fromRGB(60, 200, 120),
	off     = Color3.fromRGB(200, 70, 80),
	text    = Color3.fromRGB(235, 240, 250),
	dim     = Color3.fromRGB(150, 158, 175),
}

function UI.build()
	if not CFG.UI.Enabled then return end

	local parent = LP:WaitForChild("PlayerGui")
	local ok, hui = pcall(function() return gethui and gethui() end)
	if ok and hui then parent = hui end

	for _, n in ipairs({ "AnimeDiceKaitunGui" }) do
		local old = parent:FindFirstChild(n)
		if old then old:Destroy() end
		local pg = LP:FindFirstChild("PlayerGui")
		if pg and pg:FindFirstChild(n) then pg[n]:Destroy() end
	end

	local sg = mk("ScreenGui", {
		Name = "AnimeDiceKaitunGui",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 9999,
	})
	pcall(function() sg.Parent = parent end)
	if not sg.Parent then sg.Parent = LP:WaitForChild("PlayerGui") end
	UI.gui = sg

	-- khung chính GIỮA màn hình
	local main = mk("Frame", {
		Name = "MainFrame",
		Size = UDim2.new(0, 760, 0, 486),
		Position = UDim2.new(0.5, -380, 0.5, -243),
		BackgroundColor3 = C.bg,
		BorderSizePixel = 0,
		Visible = not CFG.UI.StartMinimized,
	}, sg)
	corner(main, 12); stroke(main, C.accent, 1.6)
	UI.main = main

	local scale = mk("UIScale", {}, main)
	local function fitScale()
		local cam = workspace.CurrentCamera
		local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
		scale.Scale = math.clamp(math.min(vp.X / 1140, vp.Y / 780), 0.55, 1.05)
	end
	fitScale()
	if workspace.CurrentCamera then
		Util.track(workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale))
	end

	-- header
	local head = mk("Frame", {
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = C.panel, BorderSizePixel = 0,
	}, main)
	corner(head, 12)
	mk("Frame", { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12),
		BackgroundColor3 = C.panel, BorderSizePixel = 0 }, head)
	mk("Frame", { Size = UDim2.new(0, 4, 0, 26), Position = UDim2.new(0, 12, 0, 13),
		BackgroundColor3 = C.accent, BorderSizePixel = 0 }, head)

	mk("TextLabel", {
		Size = UDim2.new(1, -190, 0, 20), Position = UDim2.new(0, 24, 0, 8),
		BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 16,
		TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "KAITUN · Anime Dice",
	}, head)
	UI.rows.acc = mk("TextLabel", {
		Size = UDim2.new(1, -190, 0, 14), Position = UDim2.new(0, 24, 0, 28),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 12,
		TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left,
		Text = "v" .. KT_VERSION .. " - " .. LP.Name,
	}, head)

	local btnMin = mk("TextButton", {
		Size = UDim2.new(0, 30, 0, 26), Position = UDim2.new(1, -140, 0, 13),
		BackgroundColor3 = C.row, BorderSizePixel = 0, AutoButtonColor = true,
		Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C.text, Text = "-",
	}, head)
	corner(btnMin, 6)
	local btnHide = mk("TextButton", {
		Size = UDim2.new(0, 96, 0, 26), Position = UDim2.new(1, -104, 0, 13),
		BackgroundColor3 = C.row, BorderSizePixel = 0, AutoButtonColor = true,
		Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = C.text, Text = "Ẩn (Ctrl phải)",
	}, head)
	corner(btnHide, 6)
	btnHide.Activated:Connect(function() main.Visible = false end)

	-- ==== thanh tab ====
	local tabBar = mk("Frame", {
		Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 58),
		BackgroundTransparency = 1,
	}, main)
	mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, tabBar)

	local pages = mk("Frame", {
		Size = UDim2.new(1, -20, 1, -128), Position = UDim2.new(0, 10, 0, 92),
		BackgroundColor3 = C.panel, BorderSizePixel = 0,
	}, main)
	corner(pages, 10)

	local function newPage()
		return mk("ScrollingFrame", {
			Size = UDim2.new(1, -12, 1, -12), Position = UDim2.new(0, 6, 0, 6),
			BackgroundTransparency = 1, BorderSizePixel = 0, Visible = false,
			ScrollBarThickness = 4, CanvasSize = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarImageColor3 = C.accent,
		}, pages)
	end

	local pageStat, pageFunc, pageLog = newPage(), newPage(), newPage()
	UI.pages = { pageStat, pageFunc, pageLog }
	local tabButtons = {}
	local function selectTab(index)
		for i, page in ipairs(UI.pages) do page.Visible = (i == index) end
		for i, btn in ipairs(tabButtons) do
			btn.BackgroundColor3 = (i == index) and C.accent or C.row
			btn.TextColor3 = (i == index) and Color3.new(1, 1, 1) or C.dim
		end
		UI.tab = index
	end
	local function addTab(text, index)
		local b = mk("TextButton", {
			Size = UDim2.new(0, 118, 1, 0), BackgroundColor3 = C.row, BorderSizePixel = 0,
			AutoButtonColor = true, Font = Enum.Font.GothamBold, TextSize = 13,
			TextColor3 = C.dim, Text = text, LayoutOrder = index,
		}, tabBar)
		corner(b, 7)
		tabButtons[index] = b
		b.Activated:Connect(function() selectTab(index) end)
	end
	addTab("Tổng quan", 1); addTab("Chức năng", 2); addTab("Nhật ký", 3)

	-- ==== trang 1: thẻ thông số 2 cột ====
	mk("UIGridLayout", {
		CellSize = UDim2.new(0.5, -5, 0, 44), CellPadding = UDim2.new(0, 8, 0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}, pageStat)

	local order = 0
	local function statRow(key, label)
		order = order + 1
		local card = mk("Frame", {
			BackgroundColor3 = C.row, BackgroundTransparency = 0.25,
			BorderSizePixel = 0, LayoutOrder = order,
		}, pageStat)
		corner(card, 8)
		mk("Frame", { Size = UDim2.new(0, 3, 1, -16), Position = UDim2.new(0, 0, 0, 8),
			BackgroundColor3 = C.accent, BackgroundTransparency = 0.45, BorderSizePixel = 0 }, card)
		mk("TextLabel", {
			Size = UDim2.new(1, -18, 0, 14), Position = UDim2.new(0, 12, 0, 6),
			BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
			TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left, Text = label,
		}, card)
		UI.rows[key] = mk("TextLabel", {
			Size = UDim2.new(1, -18, 0, 18), Position = UDim2.new(0, 12, 0, 21),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 14,
			TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Text = "-",
		}, card)
	end

	statRow("money",   "Tiền")
	statRow("income",  "Thu nhập plot /s")
	statRow("luck",    "Luck")
	statRow("moneym",  "Money mult")
	statRow("dice",    "Dice đang dùng")
	statRow("nextdice","Dice kế (giá)")
	statRow("rebirth", "Rebirth")
	statRow("nextrb",  "Rebirth kế (giá)")
	statRow("rolls",   "Số lần roll")
	statRow("units",   "Unit / sức chứa")
	statRow("slots",   "Ô plot mở")
	statRow("sellr",   "Bán chance từ ngưỡng xuống")
	statRow("sold",    "Đã bán")
	statRow("keep",    "Pet giữ theo chance")
	statRow("gems",    "Gems / Trait / Vé")
	statRow("tickets", "Đổi vé")
	statRow("boost",   "Boost đang chạy")
	statRow("tower",   "Tower")
	statRow("quest",   "Quest")
	statRow("cleanup", "Dọn Workspace")
	statRow("buy",     "Mua gần nhất")
	statRow("save",    "Đang để dành")
	statRow("webhook", "Webhook")
	statRow("locked",  "Đồ đang khóa")
	statRow("swap",    "Đổi acc")
	statRow("watchdog","Chống kẹt")
	statRow("uptime",  "Thời gian chạy")

	-- ==== trang 2: bật/tắt 2 cột ====
	mk("UIGridLayout", {
		CellSize = UDim2.new(0.5, -5, 0, 32), CellPadding = UDim2.new(0, 8, 0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Left,
	}, pageFunc)

	local torder = 0
	local function toggleRow(tbl, label)
		torder = torder + 1
		local f = mk("Frame", {
			BackgroundColor3 = C.row, BackgroundTransparency = 0.25,
			BorderSizePixel = 0, LayoutOrder = torder,
		}, pageFunc)
		corner(f, 8)
		mk("TextLabel", {
			Size = UDim2.new(1, -74, 1, 0), Position = UDim2.new(0, 10, 0, 0),
			BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 12,
			TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Text = label,
		}, f)
		local b = mk("TextButton", {
			Size = UDim2.new(0, 54, 0, 22), Position = UDim2.new(1, -62, 0, 5),
			BackgroundColor3 = tbl.Enabled and C.on or C.off, BorderSizePixel = 0,
			Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.new(1, 1, 1),
			Text = tbl.Enabled and "BẬT" or "TẮT", AutoButtonColor = true,
		}, f)
		corner(b, 6)
		b.Activated:Connect(function()
			tbl.Enabled = not tbl.Enabled
			b.BackgroundColor3 = tbl.Enabled and C.on or C.off
			b.Text = tbl.Enabled and "BẬT" or "TẮT"
			Util.log("UI", label .. " -> " .. (tbl.Enabled and "BẬT" or "TẮT"))
		end)
		UI.toggles[label] = b
	end

	-- công tắc to: tắt 1 nhóm là cả cụm bên dưới ngừng chạy
	local function groupRow(key, label)
		torder = torder + 1
		local f = mk("Frame", {
			BackgroundColor3 = C.accent, BackgroundTransparency = 0.72,
			BorderSizePixel = 0, LayoutOrder = torder,
		}, pageFunc)
		corner(f, 8)
		mk("TextLabel", {
			Size = UDim2.new(1, -74, 1, 0), Position = UDim2.new(0, 10, 0, 0),
			BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
			TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left,
			TextTruncate = Enum.TextTruncate.AtEnd, Text = label,
		}, f)
		local on = CFG.Groups[key] ~= false
		local b = mk("TextButton", {
			Size = UDim2.new(0, 54, 0, 22), Position = UDim2.new(1, -62, 0, 5),
			BackgroundColor3 = on and C.on or C.off, BorderSizePixel = 0,
			Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.new(1, 1, 1),
			Text = on and "BẬT" or "TẮT", AutoButtonColor = true,
		}, f)
		corner(b, 6)
		b.Activated:Connect(function()
			CFG.Groups[key] = CFG.Groups[key] == false
			local state = CFG.Groups[key] ~= false
			b.BackgroundColor3 = state and C.on or C.off
			b.Text = state and "BẬT" or "TẮT"
			Util.log("UI", label .. " -> " .. (state and "BẬT" or "TẮT"))
		end)
		UI.toggles[label] = b
	end

	groupRow("Farm",    "NHÓM · Farm")
	groupRow("Economy", "NHÓM · Kinh tế")
	groupRow("Content", "NHÓM · Tower/Quest/Boost")
	groupRow("Utility", "NHÓM · Tiện ích")

	toggleRow(CFG.Roll,    "Auto Roll")
	toggleRow(CFG.Collect, "Gom tiền plot")
	toggleRow(CFG.Plot,    "Đặt pet lên plot")
	toggleRow(CFG.LevelUp, "Nâng level pet")
	toggleRow(CFG.Sell,    "Bán pet dỏm")
	toggleRow(CFG.Economy, "Kinh tế (mua sắm)")
	toggleRow(CFG.Dice,    "Mua dice")
	toggleRow(CFG.Upgrade, "Mua upgrade tree")
	toggleRow(CFG.Rebirth, "Auto rebirth")
	toggleRow(CFG.Tower,   "Auto tower")
	toggleRow(CFG.Quest,   "Auto quest")
	toggleRow(CFG.Rewards, "Nhận reward")
	toggleRow(CFG.Boost,   "Dùng boost")
	toggleRow(CFG.WorkspaceCleanup, "Dọn map / plot khác")
	toggleRow(CFG.TicketShop, "Đổi vé xen kẽ")
	toggleRow(CFG.Webhook, "Báo pet Discord")
	toggleRow(CFG.AccountSwap, "Đổi acc khi có Jackpot")
	toggleRow(CFG.Watchdog, "Chống kẹt (rejoin)")

	-- ==== trang 3: nhật ký ====
	UI.logBox = pageLog
	UI.logLabel = mk("TextLabel", {
		Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 12,
		TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, Text = "",
	}, pageLog)

	selectTab(1)

	-- ==== thanh trạng thái dưới cùng ====
	local footer = mk("Frame", {
		Size = UDim2.new(1, -20, 0, 26), Position = UDim2.new(0, 10, 1, -32),
		BackgroundColor3 = C.panel, BorderSizePixel = 0,
	}, main)
	corner(footer, 8)
	UI.statusLabel = mk("TextLabel", {
		Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 10, 0, 0),
		BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 11,
		TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd, Text = "đang khởi động...",
	}, footer)

	-- nút thu gọn: chỉ còn thanh tiêu đề
	btnMin.Activated:Connect(function()
		UI.collapsed = not UI.collapsed
		tabBar.Visible = not UI.collapsed
		pages.Visible = not UI.collapsed
		footer.Visible = not UI.collapsed
		main.Size = UI.collapsed and UDim2.new(0, 760, 0, 52) or UDim2.new(0, 760, 0, 486)
		btnMin.Text = UI.collapsed and "+" or "-"
	end)

	-- ==== nút tròn BÊN TRÁI để ẩn/hiện ====
	local float = mk("Frame", {
		Name = "FloatToggle",
		Size = UDim2.new(0, 54, 0, 54),
		Position = UDim2.new(0.035, 0, 0.34, 0),
		BackgroundColor3 = C.panel, BorderSizePixel = 0, ZIndex = 50,
	}, sg)
	mk("UICorner", { CornerRadius = UDim.new(1, 0) }, float)
	stroke(float, C.accent, 2)
	mk("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 51,
		Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C.accent, Text = "KT",
	}, float)
	local fbtn = mk("TextButton", {
		Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 52,
	}, float)

	-- kéo thả + click
	local dragging, dragStart, startPos, moved = false, nil, nil, false
	fbtn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging, moved = true, false
			dragStart, startPos = input.Position, float.Position
			Util.disconnect(UI.floatEnd)
			UI.floatEnd = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if not moved then main.Visible = not main.Visible end
					Util.disconnect(UI.floatEnd)
					UI.floatEnd = nil
				end
			end)
		end
	end)
	Util.track(Svc.UIS.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local d = input.Position - dragStart
			if d.Magnitude > 6 then moved = true end
			float.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))

	-- kéo khung chính bằng header
	local hDrag, hStart, hPos = false, nil, nil
	head.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			hDrag, hStart, hPos = true, input.Position, main.Position
			Util.disconnect(UI.headerEnd)
			UI.headerEnd = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					hDrag = false
					Util.disconnect(UI.headerEnd)
					UI.headerEnd = nil
				end
			end)
		end
	end)
	Util.track(Svc.UIS.InputChanged:Connect(function(input)
		if not hDrag then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local d = input.Position - hStart
			main.Position = UDim2.new(hPos.X.Scale, hPos.X.Offset + d.X,
				hPos.Y.Scale, hPos.Y.Offset + d.Y)
		end
	end))

	Util.track(Svc.UIS.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.KeyCode == CFG.UI.ToggleKey then main.Visible = not main.Visible end
	end))
end

function UI.refresh()
	if not UI.gui or not UI.main or not UI.main.Visible then return end
	local r = UI.rows
	local function set(k, v)
		if r[k] then r[k].Text = tostring(v) end
	end

	local money = Util.data("Money", 0)
	set("money", Util.fmt(money))
	set("gems", Game.tokenAmount("Gems") .. " / " .. Game.tokenAmount("Trait Reroll") .. " / " .. Game.tokenAmount("Tickets"))
	set("keep", RT.protectedCount or 0)
	set("tickets", RT.status.TicketShop or "-")
	set("webhook", RT.status.Webhook or "-")
	set("income", Util.fmt(Game.plotIncome()) .. "/s")

	local rb = Util.data("Rebirth", 0)
	set("rebirth", rb)
	local nxt = Mods.Rebirths and select(2, pcall(Mods.Rebirths.GetNext, rb)) or nil
	set("nextrb", (type(nxt) == "table" and nxt.cost) and Util.fmt(nxt.cost) or "hết")

	local dname = Util.data("Dice", "?")
	local dcfg = Mods.Dice and select(2, pcall(Mods.Dice.Get, dname)) or nil
	set("dice", tostring(dname) .. (type(dcfg) == "table" and (" (x" .. Util.fmt(dcfg.luck) .. ")") or ""))
	set("nextdice", RT.nextDiceText or "-")

	set("luck", "x" .. Util.fmt(Util.buff("Luck", 1)))
	set("moneym", "x" .. string.format("%.2f", Util.buff("Money Multiplier", 1)))
	set("rolls", Util.data("Rolls", 0) .. "  (ok " .. RT.rollOk .. ")")
	set("units", Game.unitCount() .. " / " .. math.floor(Game.storageCap()))
	set("slots", #Game.unlockedSlots())
	set("sellr", RT.sellRarity)
	set("sold", RT.sold .. " con | " .. Util.fmt(RT.soldCash))
	set("tower", RT.towerName .. (RT.towerFloor > 0 and (" — tầng " .. RT.towerFloor) or ""))
	set("boost", RT.boostText or "-")
	set("quest", RT.questText or "-")
	set("buy", RT.lastBuy)
	set("save", RT.savingFor or "-")
	set("cleanup", RT.status.Cleanup or "chờ")
	set("swap", RT.status.Swap or "-")
	set("watchdog", RT.status.Watchdog or "-")
	do
		local locked = {}
		for _, name in ipairs(CFG.LockedItems or {}) do locked[#locked + 1] = tostring(name) end
		if type(AccountSwap.armed) == "function" and AccountSwap.armed()
			and type(CFG.AccountSwap.Item) == "string" then
			locked[#locked + 1] = CFG.AccountSwap.Item .. " (chờ đổi acc)"
		end
		set("locked", #locked > 0 and table.concat(locked, ", ") or "không khóa gì")
	end
	set("acc", "v" .. KT_VERSION .. " - " .. LP.Name)
	local up = math.max(0, math.floor(os.clock() - (RT.startClock or os.clock())))
	set("uptime", string.format("%02d:%02d:%02d", math.floor(up / 3600), math.floor(up % 3600 / 60), up % 60))

	if UI.statusLabel then
		local parts = {}
		for _, name in ipairs({ "Roll", "Plot", "Sell", "Economy", "Tower", "Cleanup" }) do
			parts[#parts + 1] = name .. ": " .. tostring(RT.status[name] or "-")
		end
		UI.statusLabel.Text = table.concat(parts, "   |   ")
	end

	if RT.logDirty and UI.logLabel then
		UI.logLabel.Text = table.concat(RT.log, "\n")
		RT.logDirty = false
	end
end

--==============================================================================
-- 8. MODULE: ROLL
--==============================================================================
local Roll = {}

function Roll.tick()
	if not CFG.Roll.Enabled or not Net.RollDice then
		if Net.SetAutoRoll and Util.data("AutoRoll", false) then
			pcall(function() Net.SetAutoRoll:FireServer(false) end)
		end
		RT.status.Roll = "tắt"
		return
	end
	if not Keep.syncAutoSell() then RT.status.Roll = "chờ ngưỡng bán an toàn" return end
	if CFG.Roll.ServerAuto then
		if Net.SetAutoRoll and not Util.data("AutoRoll", false) then
			pcall(function() Net.SetAutoRoll:FireServer(true) end)
			Util.log("Roll", "bật AutoRoll của game")
		end
		RT.status.Roll = "server auto"
		return
	end
	if Net.SetAutoRoll and Util.data("AutoRoll", false) then
		-- tự spam thì tắt auto của game cho khỏi đè nhau
		pcall(function() Net.SetAutoRoll:FireServer(false) end)
	end

	if CFG.Roll.StopWhenFull and Game.unitCount() >= Game.storageCap() then
		RT.status.Roll = "túi đầy"
		return
	end

	local ok, res = pcall(function() return Net.RollDice:InvokeServer() end)
	if ok and type(res) == "table" then
		RT.rollOk = RT.rollOk + 1
		RT.status.Roll = "đang quay"
	else
		RT.rollFail = RT.rollFail + 1
		RT.status.Roll = ok and "chờ hồi" or "lỗi"
	end
end

function Roll.interval()
	if not CFG.Roll.Enabled or CFG.Roll.ServerAuto then return 2 end
	local d = Util.buff("Roll Duration", 2.5)
	return math.max(0.15, d + (CFG.Roll.ExtraDelay or 0.05))
end

--==============================================================================
-- 9. MODULE: GOM TIỀN
--==============================================================================
local function collectTick()
	if not CFG.Collect.Enabled or not Net.CollectBal then
		RT.status.Collect = "tắt"
		return
	end
	local slots = Game.slots()
	local n = 0
	for _, idx in ipairs(Game.unlockedSlots()) do
		local s = slots[tostring(idx)]
		if s and (s.balance or 0) > 0 then
			pcall(function() Net.CollectBal:FireServer(idx) end)
			n = n + 1
		end
	end
	RT.status.Collect = n > 0 and ("gom " .. n .. " ô") or "trống"
end

--==============================================================================
-- 10. MODULE: ĐẶT PET LÊN PLOT (thông minh)
--==============================================================================
local Plot = {}

function Plot.charReady()
	local ch = LP.Character
	if not ch then return false end
	local hum = ch:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0 and LP:FindFirstChild("Backpack") ~= nil
end

-- đặt 1 unit vào 1 ô: gom tiền -> cầm unit -> tương tác ô
function Plot.place(slotIdx, unitKey)
	if RT.selling then return false end
	if not (Net.UnitEquip and Net.InteractSlot) then return false end
	if not Plot.charReady() then return false end

	if Net.CollectBal then
		pcall(function() Net.CollectBal:FireServer(slotIdx) end)
		task.wait(0.1)
	end

	local ok, res = pcall(function() return Net.UnitEquip:InvokeServer(unitKey) end)
	if not ok or res == false then return false end
	task.wait(0.12)

	pcall(function() Net.InteractSlot:FireServer(slotIdx) end)
	-- server debounce: UnitAction 0.5s (UnitService.lua:121) + PlotSlotInteraction 0.5s
	-- (PlotService.lua:133) -> chờ đủ để lần đặt kế tiếp không bị nuốt
	task.wait(0.45)

	-- xác nhận
	local s = Game.slots()[tostring(slotIdx)]
	if s and s.unitId == unitKey then return true end

	-- thất bại -> nhả tay cho sạch
	if Net.UnitUnequip then pcall(function() Net.UnitUnequip:InvokeServer() end) end
	return false
end

function Plot.tick()
	if not CFG.Plot.Enabled then
		RT.status.Plot = "tắt"
		return
	end
	if RT.busyEquip or RT.selling then return end

	if CFG.Plot.UseEquipBest then
		if Net.EquipBest then
			RT.busyEquip = true
			Keep.syncAutoSell(0)
			pcall(function() Net.EquipBest:FireServer() end)
			task.wait(0.6)
			RT.busyEquip = false
			RT.status.Plot = "EquipBest (server)"
		end
		return
	end

	local unlocked = Game.unlockedSlots()
	if #unlocked == 0 then
		RT.status.Plot = "chưa mở ô"
		return
	end
	if not Plot.charReady() then
		RT.status.Plot = "chờ nhân vật"
		return
	end

	local units = Game.unitList()              -- đã sort giảm dần theo điểm
	if #units == 0 then
		RT.status.Plot = "chưa có unit"
		return
	end

	local slots  = Game.slots()
	local target = {}                          -- key -> true, N con tốt nhất
	for i = 1, math.min(#unlocked, #units) do target[units[i].key] = true end

	local scoreOf = {}
	for _, u in ipairs(units) do scoreOf[u.key] = u.score end

	-- ô đang giữ đúng con trong top -> để yên
	local keep, free = {}, {}
	for _, idx in ipairs(unlocked) do
		local s = slots[tostring(idx)]
		local uid = s and s.unitId
		if uid and target[uid] then
			keep[uid] = true
		else
			table.insert(free, idx)
		end
	end

	if #free == 0 then
		RT.status.Plot = "đã tối ưu"
		return
	end

	-- con trong top mà chưa được đặt
	local pending = {}
	for _, u in ipairs(units) do
		if target[u.key] and not keep[u.key] then table.insert(pending, u) end
	end
	if #pending == 0 then
		RT.status.Plot = "đã tối ưu"
		return
	end

	RT.busyEquip = true
	Keep.syncAutoSell(0)
	local done, blocked = 0, 0
	local inv = Game.inventory()

	-- ô trống trước, ô đang có pet (phải tính hoàn vốn) sau
	table.sort(free, function(a, b)
		local sa = slots[tostring(a)]
		local sb = slots[tostring(b)]
		local ea = (sa and sa.unitId) and 1 or 0
		local eb = (sb and sb.unitId) and 1 or 0
		if ea ~= eb then return ea < eb end
		return a < b
	end)

	for _, idx in ipairs(free) do
		local cand = table.remove(pending, 1)
		if not cand then break end

		local s = slots[tostring(idx)]
		local oldKey = s and s.unitId
		local oldEntry = oldKey and inv[oldKey] or nil

		local ok, why = Game.shouldSwap(oldEntry, cand.entry)
		if not ok then
			-- giữ pet cũ, trả ứng viên về đầu hàng chờ để thử ô khác
			table.insert(pending, 1, cand)
			blocked = blocked + 1
		else
			if Plot.place(idx, cand.key) then
				done = done + 1
				if oldEntry then
					Util.log("Plot", string.format("ô %d: %s -> %s (base %s/s, %s)",
						idx, oldEntry.name, cand.entry.name, Util.fmt(cand.score), why))
				else
					Util.log("Plot", string.format("ô %d <- %s (base %s/s)",
						idx, cand.entry.name, Util.fmt(cand.score)))
				end
			else
				table.insert(pending, 1, cand)
				break
			end
			slots = Game.slots()
			inv   = Game.inventory()
		end
	end
	RT.busyEquip = false
	if done > 0 then
		RT.status.Plot = "đặt " .. done .. " con"
	elseif blocked > 0 then
		RT.status.Plot = "giữ pet đã nâng (đổi lỗ)"
	else
		RT.status.Plot = "đã tối ưu"
	end
end

--==============================================================================
-- 11. MODULE: NÂNG LEVEL (thông minh — chỉ nâng khi hoàn vốn nhanh)
--==============================================================================
local function levelTick()
	if not CFG.LevelUp.Enabled or not Net.LevelUpSlot then
		RT.status.LevelUp = "tắt"
		return
	end
	local money = Util.data("Money", 0)
	if money <= 0 then RT.status.LevelUp = "hết tiền" return end

	-- ví đang khoá để dồn mua dice (ưu tiên số 1) -> chỉ cho nâng cấp siêu rẻ
	local capPayback = CFG.LevelUp.MaxPaybackSeconds or 300
	if RT.walletLocked then
		capPayback = math.min(capPayback, CFG.LevelUp.LockedPaybackSeconds or 60)
	end

	local inv, slots = Game.inventory(), Game.slots()
	local best = nil
	for _, idx in ipairs(Game.unlockedSlots()) do
		local s = slots[tostring(idx)]
		local e = s and s.unitId and inv[s.unitId]
		if e and Game.unitCfg(e) then
			local lv = (e.attributes and e.attributes.level) or 1
			if CFG.LevelUp.MaxLevel == 0 or lv < CFG.LevelUp.MaxLevel then
				local info = Game.levelInfo(e)
				if info and info.price <= money * (CFG.LevelUp.MaxMoneyFraction or 0.35)
					and info.payback <= capPayback then
					if not best or info.payback < best.payback then
						best = { slot = idx, price = info.price, payback = info.payback,
							name = e.name, lv = lv }
					end
				end
			end
		end
	end

	if not best then
		RT.status.LevelUp = RT.walletLocked and "nhường tiền cho dice" or "không đáng nâng"
		return
	end

	pcall(function() Net.LevelUpSlot:FireServer(best.slot) end)
	RT.status.LevelUp = string.format("nâng ô %d", best.slot)
	Util.log("Level", string.format("ô %d %s Lv%d -> Lv%d | %s (hoàn vốn %ds)",
		best.slot, best.name, best.lv, best.lv + 1, Util.fmt(best.price), math.floor(best.payback)))
end

--==============================================================================
-- 12. MODULE: BÁN PET DƯ THEO CHANCE PLOT
--==============================================================================
local Sell = {}

-- Kế hoạch bán chỉ đọc dữ liệu; dùng được để kiểm tra trước khi chạy thật.
function Sell.plan()
	local threshold, why, incomeFloor = Game.lineup()
	local plan = { threshold = threshold, reason = why, incomeFloor = incomeFloor,
		batch = {}, unlocks = {}, eligible = 0 }
	if not threshold then return plan end
	local inv, slotted, team = Game.inventory(), Game.slottedSet(), Game.towerTeamSet()
	local candidates = {}
	for key, entry in pairs(inv) do
		if type(entry) == "table" and Game.unitCfg(entry)
			and not Game.keepForChance(key, entry, threshold, slotted, team, incomeFloor) then
			table.insert(candidates, { key = key, chance = Game.validChance(entry), locked = (entry.attributes or {}).locked })
		end
	end
	table.sort(candidates, function(a, b)
		if a.chance == b.chance then return tostring(a.key) < tostring(b.key) end
		return a.chance < b.chance
	end)
	plan.eligible = #candidates
	local limit = math.max(1, math.floor(tonumber(CFG.Sell.BatchSize) or 60))
	for i = 1, math.min(limit, #candidates) do
		local item = candidates[i]
		if item.locked then plan.unlocks[item.key] = false
		else table.insert(plan.batch, item.key) end
	end
	return plan
end

function Sell.tick()
	Keep.syncAutoSell()
	if not CFG.Sell.Enabled then RT.status.Sell, RT.sellRarity = "tắt", "-" return end
	if RT.busyEquip or RT.busyTeam or RT.selling then RT.status.Sell = "chờ thao tác pet" return end
	Keep.tick() -- chụp thông báo pet mới trước khi bán thủ công
	local plan = Sell.plan()
	if not plan.threshold then
		RT.status.Sell, RT.sellRarity = plan.reason, "chưa có ngưỡng plot"
		return
	end
	RT.sellRarity = "≤ 1 / " .. Util.fmt(plan.threshold)
	RT.sellEligible = plan.eligible
	local unlocked = 0
	if next(plan.unlocks) and Net.SetLocked then
		local ok = pcall(function() Net.SetLocked:FireServer(plan.unlocks) end)
		if ok then unlocked = Util.count(plan.unlocks) end
		-- Không bán các key này cho đến tick sau thấy attributes.locked=false.
	end
	if #plan.batch == 0 then
		RT.status.Sell = unlocked > 0 and ("chờ gỡ khóa " .. unlocked .. " Secret yếu") or "không có pet dư dưới ngưỡng"
		return
	end
	if not Net.SellInv then RT.status.Sell = "thiếu remote SellInventory" return end
	RT.selling = true
	local ok, cash, n = pcall(function() return Net.SellInv:InvokeServer(plan.batch) end)
	RT.selling = false
	if ok and type(cash) == "number" and type(n) == "number" then
		RT.sold, RT.soldCash = RT.sold + n, RT.soldCash + cash
		RT.status.Sell = "đã bán " .. n .. " pet"
		if n > 0 then Util.log("Sell", "bán " .. n .. " pet chance ≤ " .. string.format("%.17g", plan.threshold) .. " +" .. Util.fmt(cash)) end
	else
		RT.status.Sell = "bán lỗi/chưa xác nhận số lượng"
	end
end

--==============================================================================
-- 13. MODULE: KINH TẾ (dice / upgrade / rebirth dùng chung ví)
--==============================================================================
local Eco = {}

Eco.CATEGORY = {
	Luck      = { "Luck", "Fortune" },
	Money     = { "Money" },
	Damage    = { "Damage" },
	Storage   = { "Unit Storage" },
	Health    = { "Health" },
	RollSpeed = { "Roll Speed" },
	Sell      = { "Sell" },
	Walkspeed = { "Walkspeed" },
}

local ROMAN = { I = 1, II = 2, III = 3, IV = 4, V = 5, VI = 6, VII = 7, VIII = 8,
	IX = 9, X = 10, XI = 11, XII = 12 }

local function upgradeTier(name)
	local last = name:match("([%w%+]+)$")
	return ROMAN[last or ""] or 99
end

local function belongsTo(name, cat)
	for _, prefix in ipairs(Eco.CATEGORY[cat] or {}) do
		if name:sub(1, #prefix) == prefix then return true end
	end
	return false
end

-- upgrade rẻ nhất của 1 nhóm mà đã mở khoá (cha đã mua) và chưa sở hữu
function Eco.nextUpgrade(cat)
	if not (Mods.Upgrades and Mods.Tree) then return nil end
	local owned = Util.data("Upgrades", {}) or {}
	local best = nil
	for name, cfg in pairs(Mods.Upgrades) do
		if type(cfg) == "table" and cfg.price and cfg.price > 0 and not owned[name]
			and belongsTo(name, cat) then
			if not (cat == "Walkspeed" and upgradeTier(name) > (CFG.Upgrade.WalkspeedMaxTier or 99)) then
				local okP, parent = pcall(Mods.Tree.GetParent, name)
				local unlocked = (not okP) or (parent == nil) or (parent == "Start") or (owned[parent] == true)
				if unlocked and (not best or cfg.price < best.price) then
					best = { name = name, price = cfg.price }
				end
			end
		end
	end
	return best
end

-- dice mạnh nhất mua nổi (ưu tiên cao nhất theo yêu cầu) + dice kế tiếp để dành tiền
function Eco.diceTargets(money)
	if not Mods.Dice then return nil, nil end
	local okAll, all = pcall(Mods.Dice.GetAll)
	if not okAll or type(all) ~= "table" then return nil, nil end

	local owned = Util.data("OwnedDice", {}) or {}
	local curName = Util.data("Dice", "")
	local curCfg = select(2, pcall(Mods.Dice.Get, curName))
	local curLuck = (type(curCfg) == "table" and curCfg.luck) or 0

	-- luck cao nhất trong số dice đang sở hữu
	local bestOwnedLuck = curLuck
	for name, cfg in pairs(all) do
		if owned[name] and type(cfg) == "table" and (cfg.luck or 0) > bestOwnedLuck then
			bestOwnedLuck = cfg.luck
		end
	end

	local capLuck = math.huge
	if CFG.Dice.MaxTier and CFG.Dice.MaxTier ~= "" then
		local cc = select(2, pcall(Mods.Dice.Get, CFG.Dice.MaxTier))
		if type(cc) == "table" and cc.luck then capLuck = cc.luck end
	end

	local affordable, cheapestNext = nil, nil
	for name, cfg in pairs(all) do
		if type(cfg) == "table" and cfg.price and cfg.price > 0 and not owned[name]
			and (cfg.luck or 0) > bestOwnedLuck and (cfg.luck or 0) <= capLuck then
			if cfg.price <= money then
				if not affordable or cfg.luck > affordable.luck then
					affordable = { name = name, price = cfg.price, luck = cfg.luck }
				end
			else
				if not cheapestNext or cfg.price < cheapestNext.price then
					cheapestNext = { name = name, price = cfg.price, luck = cfg.luck }
				end
			end
		end
	end
	return affordable, cheapestNext
end

function Eco.equipBestDice()
	if not (CFG.Dice.AutoEquipBest and Net.EquipDice and Mods.Dice) then return end
	local okAll, all = pcall(Mods.Dice.GetAll)
	if not okAll then return end
	local owned = Util.data("OwnedDice", {}) or {}
	local curName = Util.data("Dice", "")
	local curCfg = select(2, pcall(Mods.Dice.Get, curName))
	local curLuck = (type(curCfg) == "table" and curCfg.luck) or 0

	local best, bestLuck = nil, curLuck
	for name, cfg in pairs(all) do
		if owned[name] and type(cfg) == "table" and (cfg.luck or 0) > bestLuck then
			best, bestLuck = name, cfg.luck
		end
	end
	if best then
		pcall(function() Net.EquipDice:FireServer(best) end)
		Util.log("Dice", "đeo dice " .. best .. " (luck x" .. Util.fmt(bestLuck) .. ")")
	end
end

function Eco.tick()
	if not CFG.Economy.Enabled then
		RT.status.Economy = "tắt"
		return
	end

	Eco.equipBestDice()

	local money = Util.data("Money", 0)
	local diceBuy, diceNext = nil, nil
	if CFG.Dice.Enabled then diceBuy, diceNext = Eco.diceTargets(money) end
	RT.nextDiceText = diceNext and (diceNext.name .. " — " .. Util.fmt(diceNext.price))
		or (diceBuy and (diceBuy.name .. " — " .. Util.fmt(diceBuy.price)) or "hết")

	-- dựng danh sách ứng viên theo thứ tự ưu tiên
	local cands = {}
	for _, entry in ipairs(CFG.Economy.Priority) do
		if entry == "Dice" then
			if CFG.Dice.Enabled then
				table.insert(cands, {
					kind = "Dice",
					price = diceBuy and diceBuy.price or (diceNext and diceNext.price or nil),
					affordable = diceBuy ~= nil,
					label = diceBuy and diceBuy.name or (diceNext and diceNext.name or nil),
					run = function()
						if not (diceBuy and Net.BuyDice) then return false end
						pcall(function() Net.BuyDice:FireServer(diceBuy.name) end)
						RT.lastBuy = "Dice " .. diceBuy.name
						Util.log("Dice", "mua " .. diceBuy.name .. " — " .. Util.fmt(diceBuy.price)
							.. " (luck x" .. Util.fmt(diceBuy.luck) .. ")")
						return true
					end,
				})
			end
		elseif Eco.CATEGORY[entry] then
			if CFG.Upgrade.Enabled then
				local up = Eco.nextUpgrade(entry)
				if up then
					table.insert(cands, {
						kind = "Upgrade",
						price = up.price,
						affordable = up.price <= money,
						label = up.name,
						run = function()
							if not Net.BuyUpgrade then return false end
							pcall(function() Net.BuyUpgrade:FireServer(up.name) end)
							RT.lastBuy = up.name
							Util.log("Upgrade", "mua " .. up.name .. " — " .. Util.fmt(up.price))
							return true
						end,
					})
				end
			end
		end
	end

	-- món ưu tiên cao nhất còn tồn tại = món đang để dành
	local topTarget = cands[1]
	local savingFor = topTarget and (not topTarget.affordable) and topTarget or nil
	RT.savingFor = savingFor and (savingFor.label .. " — " .. Util.fmt(savingFor.price)) or nil

	-- DỒN TIỀN CHO DICE: đã gom được >= ReserveRatio giá dice kế tiếp thì khoá ví lại
	local diceLock = false
	RT.walletLocked = false
	if CFG.Dice.Enabled and diceNext and not diceBuy then
		local ratio = CFG.Dice.ReserveRatio or 0.6
		if ratio > 0 and money >= diceNext.price * ratio then
			diceLock = true
			RT.walletLocked = true
			RT.status.Economy = string.format("dồn tiền mua %s (%s / %s)",
				diceNext.name, Util.fmt(money), Util.fmt(diceNext.price))
		end
	end

	local anyAffordable = false
	for _, c in ipairs(cands) do
		if c.affordable then anyAffordable = true break end
	end

	-- REBIRTH xét TRƯỚC khi khoá ví cho dice.
	-- Rebirth reset Money về 0 (RebirthService.lua:33) nhưng luckMultiplier/moneyMultiplier
	-- là hệ số NHÂN (BuffService.lua:59) nên nó nhân luôn cho mọi con dice mua sau này
	-- => nếu rebirth rẻ hơn con dice đang để dành thì rebirth trước có lợi hơn.
	if CFG.Rebirth.Enabled and Net.Rebirth and Mods.Rebirths then
		local rb = Util.data("Rebirth", 0)
		if CFG.Rebirth.Max == 0 or rb < CFG.Rebirth.Max then
			local okN, nxt = pcall(Mods.Rebirths.GetNext, rb)
			if okN and type(nxt) == "table" and nxt.cost then
				local need = nxt.cost * (CFG.Rebirth.Margin or 1)
				local dicePrice = diceNext and diceNext.price or math.huge
				local cheaperThanDice = nxt.cost <= dicePrice * (CFG.Rebirth.VsDiceRatio or 1)
				local unlocks, newSlot = Game.rebirthUnlocksSlot(rb + 1)
				local go = (money >= need) and (
					   (CFG.Rebirth.Mode == "asap")
					or (unlocks and CFG.Rebirth.UnlockFirst)
					or (not anyAffordable)
					or (diceLock and cheaperThanDice)
				)
				if go then
					pcall(function() Net.Rebirth:FireServer() end)
					RT.lastBuy = "REBIRTH " .. (rb + 1)
					Util.log("Rebirth", string.format("rebirth %d -> %d (tốn %s)%s",
						rb, rb + 1, Util.fmt(nxt.cost),
						unlocks and (" — MỞ Ô PLOT " .. tostring(newSlot)) or ""))
					RT.status.Economy = "rebirth"
					return
				end
				RT.rebirthInfo = string.format("%s / %s%s", Util.fmt(money), Util.fmt(nxt.cost),
					unlocks and " (mở ô)" or "")
			end
		end
	end

	if diceLock then return end

	local frac = CFG.Economy.FallThroughFraction or 0.25
	for i, c in ipairs(cands) do
		if c.affordable then
			local allow = (not savingFor) or (i == 1) or (c.price <= money * frac)
			if allow then
				if c.run() then
					RT.status.Economy = "mua " .. tostring(c.label)
					return
				end
			end
		end
	end

	RT.status.Economy = savingFor and ("để dành: " .. savingFor.label) or "chờ tiền"
end

--==============================================================================
-- 14. MODULE: TOWER
--==============================================================================
local Tower = {}
Tower.busy = false

-- chép đúng TowerRefs.lua
local TW = {
	start = { initial = 0.76, transition = 0.38, repeated = 0 },
	wait  = { damagePlayer = 0.62, damageEnemy = 0.62, floorCompleted = 0.24,
		memberDefeated = 0.32, ended = 0, floorStarted = 0.76 },
}
if Mods.TowerRefs then
	local ok = pcall(function()
		TW.start = Mods.TowerRefs.FloorStartedWaitTime
		TW.wait  = Mods.TowerRefs.ActionWaitTime
	end)
	if not ok then Util.log("Tower", "dùng hằng số TowerRefs dự phòng") end
end

function Tower.seqWait(seq)
	local t = 0
	for i, v in ipairs(seq) do
		if v.action == "floorStarted" then
			local prev = seq[i - 1]
			if i == 1 then
				t = t + ((v.floor == 1) and TW.start.initial or TW.start.transition)
			elseif prev and prev.action == "memberDefeated" then
				t = t + TW.start.transition
			else
				t = t + (TW.start.repeated or 0)
			end
		else
			t = t + (TW.wait[v.action] or 0)
		end
	end
	return t
end

function Tower.buildTeam()
	local inv = Game.inventory()
	local dmgM = Util.buff("Damage Multiplier", 1)
	local hpM  = Util.buff("Health Multiplier", 1)
	local team = {}
	local selected = Util.data("TowerTeam", {})
	-- TowerClass chụp team theo đúng thứ tự slot; không tự đổi thứ tự khi AutoTeam tắt.
	for i = 1, (Mods.TowerRefs and Mods.TowerRefs.MAX_TEAM_SIZE) or 4 do
		local entry = inv[selected[i]]
		if entry and Game.unitCfg(entry) then
			table.insert(team, { damage = Game.damageOf(entry) * dmgM, health = Game.healthOf(entry) * hpM })
		end
	end
	return team
end

-- mô phỏng đúng TowerClass.completeFloor
function Tower.simulate(tcfg, team)
	if #team == 0 or not tcfg.enemyHealth or not tcfg.enemyDamage then return 0, 0, 0 end
	local mem = {}
	for _, m in ipairs(team) do table.insert(mem, { damage = m.damage, health = m.health }) end
	local floor, cur, elapsed, floors = 1, 1, 0, 0
	local totals = { Gems = 0, ["Trait Reroll"] = 0 }
	local bestScore, bestFloor, bestTotals, bestTime = -1, 0, {}, 0
	local weighted = 0
	local cap = math.min(tcfg.maxFloors or math.huge, CFG.Tower.MaxSimFloors)
	while floor <= cap and cur <= #mem do
		local eH, eD = tcfg.enemyHealth(floor), tcfg.enemyDamage(floor)
		if eH ~= eH or eD ~= eD or eH <= 0 or eD < 0 then break end
		local cleared = false
		elapsed = elapsed + (floor == 1 and TW.start.initial or TW.start.transition)
		while cur <= #mem do
			local m = mem[cur]
			if m.damage <= 0 or m.health <= 0 then break end
			-- TowerClass: đánh trước; địch chết thì không phản công.
			-- Gộp số đòn để không lặp hàng nghìn lần trên CPU.
			local killHits = math.ceil(eH / m.damage)
			local liveHits = eD > 0 and math.ceil(m.health / eD) or math.huge
			if killHits <= liveHits then
				elapsed = elapsed + killHits * TW.wait.damageEnemy + (killHits - 1) * (TW.wait.damagePlayer + TW.start.repeated)
				m.health = m.health - (killHits - 1) * eD
				cleared = true
				break
			else
				elapsed = elapsed + liveHits * (TW.wait.damageEnemy + TW.wait.damagePlayer)
					+ (liveHits - 1) * TW.start.repeated + TW.wait.memberDefeated
				eH = eH - liveHits * m.damage
				cur = cur + 1
				if cur <= #mem then elapsed = elapsed + TW.start.transition end
			end
		end
		if not cleared then break end
		floors = floor
		elapsed = elapsed + TW.wait.floorCompleted + CFG.Tower.LatencyMargin
		for _, grp in ipairs(tcfg.drops or {}) do
			if grp.minFloor <= floor then
				for _, drop in ipairs(grp.entries or {}) do
					local amount = (drop.chance or 0) / 100 * (drop.amount or 1)
					totals[drop.name] = (totals[drop.name] or 0) + amount
					local weight = CFG.Tower.ResourceWeights[drop.name]
					if not weight then
						local cfg = Mods.EntryRegistry and Util.get(function() return Mods.EntryRegistry.getEntryConfig(drop.name) end)
						weight = cfg and cfg.kind == "Boost" and CFG.Tower.BoostWeight * (cfg.tier or 1) or 0
					end
					weighted = weighted + amount * weight
				end
			end
		end
		local duration = elapsed + math.max(3.2, CFG.Tower.Interval) + (CFG.Tower.AutoTeam and 0.6 or 0)
		local rate = weighted / math.max(duration, 0.01)
		if floor >= CFG.Tower.MinFloors and rate > bestScore then
			bestScore, bestFloor, bestTime = rate, floor, duration
			bestTotals = { Gems = totals.Gems, ["Trait Reroll"] = totals["Trait Reroll"] }
		end
		floor = floor + 1
	end
	return floors, math.max(0, bestScore), elapsed, {
		targetFloor = bestFloor, duration = bestTime, rewards = bestTotals,
		fullClear = tcfg.maxFloors ~= nil and floors >= tcfg.maxFloors,
		clearSeconds = elapsed + math.max(3.2, CFG.Tower.Interval),
	}
end

-- Chỉ tính boost rơi ở các tầng đánh tới được, không tính tầng chưa đủ sức.
function Tower.boostCategories(tcfg, maxFloor)
	local set = {}
	if not Mods.EntryRegistry then return set end
	for _, grp in ipairs(tcfg.drops or {}) do
		for _, e in ipairs((not maxFloor or grp.minFloor <= maxFloor) and (grp.entries or {}) or {}) do
			local ok, cfg = pcall(Mods.EntryRegistry.getEntryConfig, e.name)
			if ok and type(cfg) == "table" and cfg.kind == "Boost" and cfg.category then
				set[cfg.category] = true
			end
		end
	end
	return set
end

-- tower này đang thiếu bao nhiêu category boost (tính cả cái đang chạy là "đã có")
function Tower.boostNeed(tcfg, stock, running, maxFloor)
	local want = {}
	if CFG.Boost.UseLuck   then want.Luck   = true end
	if CFG.Boost.UseMoney  then want.Income = true end
	if CFG.Boost.UseDamage then want.Damage = true end

	local target, need = CFG.Tower.BoostStockTarget or 3, 0
	for cat in pairs(Tower.boostCategories(tcfg, maxFloor)) do
		local kind = Game.boostKind(cat)
		if kind and want[kind] then
			local have = (stock[cat] or 0) + (running[cat] and 1 or 0)
			if have < target then need = need + (target - have) end
		end
	end
	return need
end

function Tower.pick()
	if not Mods.Towers then return nil end
	local okAll, all = pcall(Mods.Towers.GetAll)
	if not okAll or type(all) ~= "table" then return nil end
	local team = Tower.buildTeam()
	if #team == 0 then return nil end
	local stock = CFG.Tower.FarmBoosts and Game.boostStock() or {}
	local running = CFG.Tower.FarmBoosts and Game.boostRunning() or {}
	local best, clear, refill
	local reports = {}
	for name, tcfg in pairs(all) do
		local ok, floors, score, seconds, details = pcall(Tower.simulate, tcfg, team)
		if ok and details and floors >= CFG.Tower.MinFloors then
			local item = { name = name, score = score, floors = floors, details = details, order = tcfg.order or 0 }
			reports[name] = item
			if not best or score > best.score or (score == best.score and item.order > best.order) then best = item end
			if details.fullClear and (not clear or details.clearSeconds < clear.details.clearSeconds
				or (details.clearSeconds == clear.details.clearSeconds and score > clear.score)) then clear = item end
			local need = CFG.Tower.FarmBoosts and Tower.boostNeed(tcfg, stock, running, details.targetFloor) or 0
			item.need = need
			if need > 0 and (not refill or need > refill.need or (need == refill.need and score > refill.score)) then refill = item end
		end
	end
	RT.towerReports = reports
	local chosen, quest = best, false
	RT.towerWhy = "gems + reroll / thời gian dự kiến"
	if CFG.Tower.Mode == "fixed" then
		chosen = reports[CFG.Tower.Fixed]
		RT.towerWhy = "tower cố định, đã kiểm tra sức mạnh"
	elseif RT.questNeedTower and clear then
		chosen, quest = clear, true
		RT.towerWhy = "ưu tiên quest daily/weekly"
	elseif refill and (RT.resourceRuns or 0) >= CFG.Tower.RefillEvery then
		chosen = refill
		RT.resourceRuns = 0
		RT.towerWhy = "nạp boost có thể rơi trong các tầng đánh được"
	end
	if not chosen then return nil end
	RT.towerTarget = quest and chosen.floors or chosen.details.targetFloor
	RT.towerEstimate = chosen.details
	return chosen.name, chosen.floors, quest
end

-- CancelTower chỉ xếp cờ; phải gọi CompleteFloor sau cooldown để server dọn lượt.
function Tower.forceEnd()
	if not (Net.CancelTower and Net.CompleteFloor) then return false end
	local okCancel, queued = pcall(function() return Net.CancelTower:InvokeServer() end)
	if okCancel and queued == false then return true end
	if not okCancel then return false end
	local waitLeft = (RT.towerNextAt or 0) - os.clock()
	if waitLeft > 0 then task.wait(waitLeft + CFG.Tower.LatencyMargin) end
	for _ = 1, 12 do
		local ok, seq = pcall(function() return Net.CompleteFloor:InvokeServer() end)
		if ok and type(seq) == "table" and #seq > 0 then
			for _, st in ipairs(seq) do
				if st.action == "ended" then return true end
			end
		end
		task.wait(0.6)
	end
	return false
end

function Tower.run(name)
	if not (Net.PlayTower and Net.CompleteFloor) then return end
	local gap = 3.1 - (os.clock() - (RT.lastTowerStart or -math.huge))
	if gap > 0 then task.wait(gap) end
	RT.lastTowerStart = os.clock()
	local ok, started = pcall(function() return Net.PlayTower:InvokeServer(name) end)
	if not ok or not started then
		RT.status.Tower = "dọn tower treo"
		Util.log("Tower", "vào không được — dọn lượt cũ còn treo trên server")
		if not Tower.forceEnd() then return end
		task.wait(math.max(0, 3.1 - (os.clock() - RT.lastTowerStart)))
		if not RT.running or not CFG.Tower.Enabled then return end
		RT.lastTowerStart = os.clock()
		local ok2, started2 = pcall(function() return Net.PlayTower:InvokeServer(name) end)
		if not ok2 or not started2 then return end
	end
	RT.towerName = name
	RT.towerFloor = 0
	Util.log("Tower", "vào " .. name)

	local guard, ended, emptyReplies = CFG.Tower.MaxSimFloors + 20, false, 0
	while RT.running and CFG.Tower.Enabled and guard > 0 do
		guard = guard - 1
		local okF, seq = pcall(function() return Net.CompleteFloor:InvokeServer() end)
		if not okF or type(seq) ~= "table" or #seq == 0 then
			emptyReplies = emptyReplies + 1
			if emptyReplies >= 12 then break end
			task.wait(0.5)
		else
			emptyReplies = 0
			for _, step in ipairs(seq) do
				if step.action == "floorCompleted" and step.floor then
					RT.towerFloor = step.floor
					RT.towerResources = RT.towerResources or { Gems = 0, ["Trait Reroll"] = 0 }
					for item, amount in pairs(step.rewards or {}) do
						if RT.towerResources[item] then RT.towerResources[item] = RT.towerResources[item] + amount end
					end
				elseif step.action == "ended" then
					ended = true
				end
			end
			if ended then break end
			local waitTime = math.max(0.15, Tower.seqWait(seq) + CFG.Tower.LatencyMargin)
			RT.towerNextAt = os.clock() + waitTime
			task.wait(waitTime)
			if RT.towerTarget and RT.towerFloor >= RT.towerTarget then break end
		end
	end

	-- chỉ khi server chưa tự kết thúc mới phải ép huỷ (nếu không tower treo lại)
	if not ended then Tower.forceEnd() end
	Util.log("Tower", string.format("xong %s — tầng %d", name, RT.towerFloor))
	RT.lastTowerFloor = RT.towerFloor
	RT.resourceRuns = (RT.resourceRuns or 0) + 1
	RT.towerName  = "-"
	RT.towerFloor = 0
end

function Tower.tick()
	if not CFG.Tower.Enabled then
		RT.status.Tower = "tắt"
		return
	end
	if Tower.busy then return end
	if RT.selling then return end

	if CFG.Tower.AutoTeam and Net.BestTeam then
		RT.busyTeam = true
		pcall(function() Net.BestTeam:FireServer() end)
		task.wait(0.6)
		RT.busyTeam = false
	end

	local name, floors, forQuest = Tower.pick()
	if not name then
		RT.status.Tower = "chưa đủ sức"
		return
	end
	RT.status.Tower = string.format("%s (~%d tầng) — %s", name, floors or 0,
		RT.towerWhy or "")

	Tower.busy = true
	local ok, err = pcall(Tower.run, name)
	Tower.busy = false
	if not ok then Util.log("Tower", "lỗi: " .. tostring(err)) end
end

--==============================================================================
-- 14b. MODULE: QUEST (tự làm + tự nhận)
--==============================================================================
local Quest = {}

-- trả về bảng { [questId] = {period=, target=, progress=, expiresAt=, done=, claimed=} }
function Quest.scan()
	local out = {}
	if not Mods.QuestConfig then return out end
	local q = Util.data("Quests", {}) or {}
	for period, pcfg in pairs(Mods.QuestConfig.Periods or {}) do
		local pd = q[period]
		if type(pd) == "table" then
			for _, quest in ipairs(pcfg.quests or {}) do
				local prog    = (pd.progress or {})[quest.id] or 0
				local claimed = ((pd.claimed or {})[quest.id]) == true
				table.insert(out, {
					period = period, id = quest.id, target = quest.target,
					progress = prog, expiresAt = pd.expiresAt,
					done = prog >= quest.target, claimed = claimed,
					tickets = quest.tickets,
				})
			end
		end
	end
	return out
end

function Quest.tick()
	if not CFG.Quest.Enabled then
		RT.status.Quest = "tắt"
		RT.questNeedTower, RT.questNeedSell = false, false
		return
	end

	local list = Quest.scan()
	if #list == 0 then
		RT.questNeedTower, RT.questNeedSell = false, false
		RT.status.Quest = "chưa có dữ liệu"
		return
	end

	-- 1) NHẬN những quest đã xong
	local claimed = 0
	if Net.QuestClaim then
		for _, q in ipairs(list) do
			if q.done and not q.claimed and type(q.expiresAt) == "number" and q.expiresAt > os.time() then
				pcall(function() Net.QuestClaim:FireServer(q.period, q.id, q.expiresAt) end)
				Util.log("Quest", string.format("nhận %s/%s (+%s vé)",
					q.period, q.id, tostring(q.tickets)))
				claimed = claimed + 1
				task.wait(0.3)
			end
		end
	end

	-- 2) LÀM: báo cho Tower/Sell biết quest nào còn thiếu
	local needTower, needSell, pending = false, false, 0
	for _, q in ipairs(list) do
		if not q.done and type(q.expiresAt) == "number" and q.expiresAt > os.time() then
			pending = pending + 1
			if q.id == "Towers"    then needTower = true end
			if q.id == "UnitsSold" then needSell  = true end
		end
	end
	RT.questNeedTower = needTower and CFG.Quest.ForceTower or false
	RT.questNeedSell  = needSell  and CFG.Quest.PushSell   or false

	-- tóm tắt cho GUI
	local parts = {}
	for _, q in ipairs(list) do
		if not q.claimed then
			table.insert(parts, string.format("%s/%s %d/%d", q.period, q.id, math.floor(q.progress), q.target))
		end
	end
	RT.questText = (#parts > 0) and table.concat(parts, " | ") or "xong hết"
	RT.status.Quest = claimed > 0 and ("nhận " .. claimed)
		or (pending > 0 and ("còn " .. pending) or "xong hết")
end

--==============================================================================
-- 15. MODULE: REWARD + CODE + BOOST
--==============================================================================
local function rewardTick()
	if not CFG.Rewards.Enabled then
		RT.status.Rewards = "tắt"
		return
	end
	local did = {}

	if CFG.Rewards.Offline and Net.OfflineClaim and Util.data("PendingOfflineEarnings", 0) > 0 then
		pcall(function() Net.OfflineClaim:FireServer() end)
		table.insert(did, "offline")
	end

	-- Group: server từ chối nếu chưa vào group (GroupRewardService.lua:27) -> thử vài lần rồi thôi,
	-- không spam remote mỗi 30 giây
	if CFG.Rewards.Group and Net.GroupClaim and Util.data("ClaimedGroupReward", false) ~= true then
		RT.groupTries = (RT.groupTries or 0) + 1
		if RT.groupTries <= (CFG.Rewards.GroupMaxTries or 3) then
			pcall(function() Net.GroupClaim:FireServer() end)
			table.insert(did, "group")
		elseif RT.groupTries == (CFG.Rewards.GroupMaxTries or 3) + 1 then
			Util.log("Reward", "bỏ qua group reward (acc chưa vào group " ..
				tostring((Mods.GroupCfg and Mods.GroupCfg.GroupId) or "?") .. ")")
		end
	end

	if CFG.Rewards.Daily and Net.DailyClaim then
		local last = Util.data("LastDailyRewardClaim", 0)
		local cd = (Mods.DailyCfg and Mods.DailyCfg.Cooldown) or 82800
		if last == 0 or (os.time() - last) >= cd then
			pcall(function() Net.DailyClaim:FireServer() end)
			table.insert(did, "daily")
		end
	end

	-- quest do module Quest lo (vừa làm vừa nhận), không nhận trùng ở đây

	if #did > 0 then
		Util.log("Reward", "nhận: " .. table.concat(did, ", "))
		RT.status.Rewards = "vừa nhận " .. #did
	else
		RT.status.Rewards = "đã nhận hết"
	end
end

local function codeTick()
	if not (CFG.Codes.Enabled and Net.RedeemCode) then
		RT.status.Codes = "tắt"
		return
	end
	local done = Util.data("RedeemedCodes", {}) or {}
	local tries = RT.codeTries
	local maxTries = math.max(1, math.floor(tonumber(CFG.Codes.MaxTries) or 3))
	local n, left, dead = 0, 0, 0
	for _, code in ipairs(CFG.Codes.List or {}) do
		-- Code sai thì RedeemedCodes không bao giờ có nó (MonetizationService.lua:297 chỉ
		-- gửi thông báo lỗi), nên phải tự đếm để khỏi spam remote mỗi vòng.
		if not done[code] then
			if (tries[code] or 0) < maxTries then
				tries[code] = (tries[code] or 0) + 1
				pcall(function() Net.RedeemCode:FireServer(code) end)
				n = n + 1
				task.wait(0.7)
			else
				dead = dead + 1
			end
		end
	end
	local nowDone = Util.data("RedeemedCodes", {}) or {}
	for _, code in ipairs(CFG.Codes.List or {}) do
		if not nowDone[code] then left = left + 1 end
	end
	if n > 0 then Util.log("Code", "nhập " .. n .. " code") end
	if left == 0 then
		RT.status.Codes = "đã nhận hết"
	elseif dead > 0 then
		RT.status.Codes = string.format("còn %d/%d (%d code không nhận được)",
			left, #(CFG.Codes.List or {}), dead)
	else
		RT.status.Codes = "còn " .. left .. "/" .. #(CFG.Codes.List or {})
	end
end

local function antiAFK()
	if not CFG.AntiAFK.Enabled then return end
	local okVU, VU = pcall(function() return game:GetService("VirtualUser") end)
	if not okVU or not VU then
		Util.log("AntiAFK", "không có VirtualUser, bỏ qua")
		return
	end
	Util.track(LP.Idled:Connect(function()
		if not RT.running or not CFG.AntiAFK.Enabled then return end
		pcall(function()
			VU:CaptureController()
			VU:ClickButton2(Vector2.new())
		end)
	end))
	Util.log("AntiAFK", "đã bật chống kick idle")
end

local function boostTick()
	if not CFG.Boost.Enabled then
		RT.status.Boost = "tắt"
		return
	end
	local inv = Game.inventory()
	local active = Util.data("ActiveEntries", {}) or {}

	-- Theo đuôi category, gồm cả bộ Leaf trong source mới.
	local want = {}
	if CFG.Boost.UseLuck   then want.Luck   = true end
	if CFG.Boost.UseMoney  then want.Income = true end
	if CFG.Boost.UseDamage then want.Damage = true end

	local used = 0
	if Net.BoostUse and Mods.EntryRegistry then
		-- mỗi category chỉ chạy 1 boost tại 1 thời điểm (BoostService.lua:78)
		-- nhưng CÁC CATEGORY KHÁC NHAU chạy song song và nhân dồn
		-- -> chỉ bỏ qua category đang bận, không bỏ qua cả nhóm
		local busyCat = {}
		for _, e in pairs(active) do
			if type(e) == "table" and e.name then
				local cfg = select(2, pcall(Mods.EntryRegistry.getEntryConfig, e.name))
				local left = type(e.remaining) == "number" and e.remaining
					- (type(e.startedAt) == "number" and math.max(0, workspace:GetServerTimeNow() - e.startedAt) or 0)
					or (type(e.expiresAt) == "number" and e.expiresAt - os.time() or 0)
				if left > 0 and type(cfg) == "table" and cfg.kind == "Boost" and cfg.category then
					busyCat[cfg.category] = math.max(busyCat[cfg.category] or 0, cfg.tier or 0)
				end
			end
		end
		local best = {}
		for key, e in pairs(inv) do
			if type(e) == "table" and e.name and (e.amount or 0) > 0 then
				local cfg = select(2, pcall(Mods.EntryRegistry.getEntryConfig, e.name))
				if type(cfg) == "table" and cfg.kind == "Boost" and cfg.category
					and not Game.isLocked(e.name) then
					local kind = Game.boostKind(cfg.category)
					if kind and want[kind] and (cfg.tier or 0) > (busyCat[cfg.category] or 0) then
						local cur = best[cfg.category]
						if not cur or (cfg.tier or 0) > cur.tier then
							best[cfg.category] = { key = key, tier = cfg.tier or 0, name = e.name }
						end
					end
				end
			end
		end
		for _, b in pairs(best) do
			pcall(function() Net.BoostUse:FireServer(b.key) end)
			Util.log("Boost", "dùng " .. b.name)
			used = used + 1
			task.wait(0.3)
		end
	end

	local activeSpin = false
	for _, e in pairs(active) do
		local cfg = type(e) == "table" and Mods.EntryRegistry and Util.get(function() return Mods.EntryRegistry.getEntryConfig(e.name) end)
		if cfg and cfg.kind == "Spin" then activeSpin = true break end
	end
	if CFG.Boost.UseSpins and CFG.Roll.Enabled and Game.unitCount() < Game.storageCap()
		and not activeSpin and Net.SpinUse and Mods.EntryRegistry then
		for key, e in pairs(inv) do
			if type(e) == "table" and e.name and (e.amount or 0) > 0 then
				local cfg = select(2, pcall(Mods.EntryRegistry.getEntryConfig, e.name))
				-- Game.isLocked gồm cả LockedItems lẫn món đang giữ để đổi acc.
				if type(cfg) == "table" and cfg.kind == "Spin" and not Game.isLocked(e.name) then
					pcall(function() Net.SpinUse:FireServer(key) end)
					Util.log("Boost", "dùng " .. e.name)
					used = used + 1
					task.wait(0.3)
					break
				end
			end
		end
	end

	local running = Game.boostRunning()
	local nl, ni, nd = 0, 0, 0
	local names = {}
	for cat, bname in pairs(running) do
		local k = Game.boostKind(cat)
		if k == "Luck"   then nl = nl + 1 end
		if k == "Income" then ni = ni + 1 end
		if k == "Damage" then nd = nd + 1 end
		table.insert(names, bname)
	end
	RT.boostText = string.format("Luck %d lớp | Tiền %d | Dame %d", nl, ni, nd)
	RT.boostRunningNames = table.concat(names, ", ")
	RT.status.Boost = used > 0 and ("dùng " .. used) or RT.boostText
end

--==============================================================================
-- 16. KHỞI ĐỘNG
--==============================================================================
-- Chỉ giữ trạng thái đổi vé nhỏ trong cùng phiên executor, không ghi dữ liệu tài khoản ra đĩa.
local firstTicketItem = (CFG.TicketShop.Items or {})[1] or "Trait Reroll"
local session = getgenv().AnimeDiceSession
if type(session) ~= "table" or session.owner ~= LP.UserId then
	session = { owner = LP.UserId, tickets = { next = firstTicketItem } }
	getgenv().AnimeDiceSession = session
end
session.tickets = session.tickets or { next = firstTicketItem }
RT.ticketState = session.tickets
-- Đổi danh sách Items giữa chừng thì lượt cũ không còn hợp lệ.
do
	local valid = false
	for _, name in ipairs(CFG.TicketShop.Items or {}) do
		if name == RT.ticketState.next then valid = true break end
	end
	if not valid then RT.ticketState.next, RT.ticketState.pending = firstTicketItem, nil end
end
local ledgerNames = { Tickets = true, [firstTicketItem] = true }
for _, name in ipairs(CFG.TicketShop.Items or {}) do ledgerNames[name] = true end
if type(CFG.AccountSwap.Item) == "string" and CFG.AccountSwap.Item ~= "" then
	ledgerNames[CFG.AccountSwap.Item] = true
end
local ledgerList = {}
for name in pairs(ledgerNames) do ledgerList[#ledgerList + 1] = name end
table.sort(ledgerList)
for _, token in ipairs(ledgerList) do
	local name = token
	local ledger = { last = Game.tokenAmount(name), gained = 0, spent = 0 }
	RT.tokenLedger[name] = ledger
	pcall(function()
		-- Data.Value.Changed truyền giá trị mới; delta không bị che bởi drop tower.
		Util.track(DC.Inventory[name].amount.Changed(function(value)
			if not RT.running then return end
			local amount = tonumber(value) or 0
			local delta = amount - ledger.last
			if delta > 0 then ledger.gained = ledger.gained + delta
			elseif delta < 0 then ledger.spent = ledger.spent - delta end
			ledger.last = amount
		end))
	end)
end
if RT.ticketState.pending then
	RT.ticketState.pending.gained = 0
	RT.ticketState.pending.spent = 0
end
local observed = pcall(function()
	Util.track(DC.Inventory.Changed(function()
		if not RT.running then return end
		RT.unitCountCache = nil
		RT.inventoryDirty = true
	end))
end)
RT.inventoryObserved = observed
pcall(function()
	Util.track(DC.Slots.Changed(function()
		if not RT.running then return end
		RT.inventoryDirty = true
		Keep.syncAutoSell()
	end))
	-- OnKeyAdded truyền key và entry mới (Data.Value); chụp trước lượt quét định kỳ.
	Util.track(DC.Inventory.OnKeyAdded(function(key, entry)
		if not RT.running or type(entry) ~= "table" or not Game.unitCfg(entry) then return end
		if RT.noticeSeen[key] then return end
		RT.noticeSeen[key] = true
		Notice.enqueue(entry)
	end))
end)
pcall(function()
	Util.track(DC.AutoSell.Changed(function() if RT.running then Keep.syncAutoSell() end end))
end)
Keep.buildCeiling()
Keep.tick()
pcall(Performance.apply)
UI.build()
Util.log("KAITUN", "v" .. KT_VERSION .. " khởi động — " .. LP.Name)
Game.dumpRarities()
-- Cập nhật quest và boost trước lượt tower đầu tiên.
pcall(Quest.tick)
pcall(boostTick)

-- kiểm tra chéo bảng rarity với hàm getRarity thật của game
table.insert(RT.threads, task.spawn(function()
	if not Mods.EntryRegistry then return end
	local okAll, all = pcall(Mods.EntryRegistry.entriesOfKind, "Unit")
	if not okAll or type(all) ~= "table" then return end
	local bad = 0
	for _, cfg in pairs(all) do
		if cfg.chance and cfg.getRarity then
			local okC, ch = pcall(cfg.chance, nil)
			local okR, r = pcall(cfg.getRarity, nil)
			if okC and okR and ch and r and Game.RARITY_FLOOR[r] then
				local floorv = Game.RARITY_FLOOR[r]
				if ch < floorv then bad = bad + 1 end
			end
		end
	end
	if bad > 0 then
		Util.log("KAITUN", "CẢNH BÁO: bảng ngưỡng rarity lệch " .. bad .. " mục")
	end
end))

loop("Roll",    Roll.interval,                          Roll.tick)
loop("Collect", function() return CFG.Collect.Interval end, collectTick)
loop("Plot",    function() return CFG.Plot.Interval end,    Plot.tick)
loop("LevelUp", function() return CFG.LevelUp.Interval end, levelTick)
loop("Sell",    function() return CFG.Sell.Interval end,    Sell.tick)
loop("Economy", function() return CFG.Economy.Interval end, Eco.tick)
loop("Tower",   function() return CFG.Tower.Interval end,   Tower.tick)
loop("Quest",   function() return CFG.Quest.Interval end,   Quest.tick)
loop("Rewards", function() return CFG.Rewards.Interval end, rewardTick)
loop("Boost",   function() return CFG.Boost.Interval end,   boostTick)
loop("Codes",   function() return CFG.Codes.Interval end,   codeTick)
loop("Keep",    function() return CFG.Keep.Interval end,    Keep.tick)
loop("Webhook", function() return CFG.Webhook.Interval end, Notice.tick)
loop("Tickets", function() return CFG.TicketShop.Interval end, TicketShop.tick)
loop("Cleanup", function() return math.max(1, tonumber(CFG.WorkspaceCleanup.Interval) or 3) end, WorldCleanup.tick)
loop("Swap",    function() return math.max(1, tonumber(CFG.AccountSwap.Interval) or 5) end, AccountSwap.tick)
-- Watchdog cố ý KHÔNG thuộc nhóm nào: tắt nhóm Utility vẫn còn lưới cứu kẹt.
loop("Watchdog", function() return math.max(5, tonumber(CFG.Watchdog.Interval) or 10) end, Watchdog.tick)

pcall(antiAFK)

table.insert(RT.threads, task.spawn(function()
	while RT.running do
		pcall(UI.refresh)
		task.wait(math.max(0.5, CFG.Performance.UIInterval))
	end
end))

getgenv().AnimeDiceKaitun = {
	Version = KT_VERSION,
	CFG = CFG,
	RT  = RT,
	Game = Game,
	Util = Util,
	Net  = Net,
	Mods = Mods,
	-- để debug / gọi tay
	Plot = Plot, Sell = Sell, Eco = Eco, Tower = Tower, Quest = Quest, Roll = Roll,
	Keep = Keep, Notice = Notice, TicketShop = TicketShop,
	WorldCleanup = WorldCleanup, AccountSwap = AccountSwap, Watchdog = Watchdog,
	Stop = function()
		if not RT.running then return end
		RT.running = false
		for _, th in ipairs(RT.threads) do pcall(task.cancel, th) end
		for _, connection in ipairs(RT.connections) do Util.disconnect(connection) end
		Util.disconnect(UI.floatEnd)
		Util.disconnect(UI.headerEnd)
		if Net.SetAutoRoll then pcall(function() Net.SetAutoRoll:FireServer(false) end) end
		if Net.UpdAutoSell then pcall(function() Net.UpdAutoSell:FireServer(0) end) end
		if RT.windChanged then pcall(function() LP:SetAttribute("WindDisabled", RT.oldWindDisabled) end) end
		if UI.gui then pcall(function() UI.gui:Destroy() end) end
		RT.connections, RT.threads, RT.unitConfigCache = {}, {}, {}
		RT.noticeSeen, RT.noticeQueue = {}, {}
		RT.log, RT.err, RT.towerReports = {}, {}, nil
		RT.tokenLedger = {}
		RT.busyEquip, Tower.busy = false, false
		RT.selling, RT.busyTeam = false, false
		-- Hủy và hoàn tất cooldown trước khi bản chạy kế tiếp được khởi động.
		pcall(Tower.forceEnd)
		print("[KAITUN] đã dừng.")
	end,
}

print("[KAITUN] Anime Dice v" .. KT_VERSION .. " sẵn sàng. Nút tròn 'KT' bên trái để ẩn/hiện.")
