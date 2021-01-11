
local function getAllUnits()
	local a = {}
	a[UnitGUID("player")] = "player"
	if UnitExists("pet") then
		a[UnitGUID("pet")] = "pet"
	end
	if UnitExists("target") then
		a[UnitGUID("target")] = "target"
		if UnitExists("targettarget") then
			a[UnitGUID("targettarget")] = "targettarget"
		end
	end
	if IsInGroup() then
		if IsInRaid() then
			for i=1,40 do
				local u = "raid" .. tostring(i)
				if not UnitExists(u) then break end
				a[UnitGUID(u)] = u
				u = u .. "pet"
				if UnitExists(u) then a[UnitGUID(u)] = u end
			end
		else
			for i=1,5 do
				local u = "party" .. tostring(i)
				if not UnitExists(u) then break end
				a[UnitGUID(u)] = u
				u = u .. "pet"
				if UnitExists(u) then a[UnitGUID(u)] = u end
			end
		end
	end
	for i=1,40 do
		local u = "nameplate" .. tostring(i)
		if not UnitExists(u) then break end
		a[UnitGUID(u)] = u
	end
	return a
end

local function createClass()
	local a = {}
	a.__index = a
	a.new = function(self, ...)
		local b = {}
		setmetatable(b, a)
		b:constructor(...)
		return b
	end
	return a
end

local Snapshot = createClass()
Snapshot.constructor = function(self, target)
	self.timestamp = GetTime()
	self.threatMax = 0
	self.threat = {}
	for _,unitId in pairs(getAllUnits()) do
		local tanking, _, _, _, t = UnitDetailedThreatSituation(unitId, target)
		if tanking then
			self.tanking = UnitGUID(unitId)
		end
		if t ~= nil then
			t = t / 100
			self.threat[UnitGUID(unitId)] = t
			self.threatMax = math.max(self.threatMax, t)
		end
		if UnitExists(target .. "target") then
			self.target = UnitGUID(target .. "target")
		end
	end
end
Snapshot.__eq = function(self, other)
	for k,v in pairs(self.threat) do
		if other.threat[k] ~= v then
			return false
		end
	end
	for k,v in pairs(other.threat) do
		if self.threat[k] ~= v then
			return false
		end
	end
	return self.tanking == other.tanking and self.target == other.target
end
Snapshot.empty = function(self)
	for _,v in pairs(self.threat) do
		if v > 0 then
			return false
		end
	end
	return not self.target or not self.tanking
end

f = CreateFrame("FRAME", nil, UIParent)
local Plot = createClass()

local Unit = createClass()
Unit.constructor = function(self, unitId)
	self.name = UnitName(unitId)
	self.guid = UnitGUID(unitId)
	self.threatMax = 0
	self.snapshots = {}
	self.targets = {}
end
Unit.snapshot = function(self, unitId)
	if UnitGUID(unitId) ~= self.guid then
		print("Wrong guid.")
		return
	end
	-- Handles multiple calls for different unitIds
	if #self.snapshots > 0 and GetTime() == self.snapshots[#self.snapshots].timestamp then
		return
	end
	local snapshot = Snapshot:new(unitId)
	if snapshot:empty() or #self.snapshots > 0 and snapshot == self.snapshots[#self.snapshots] then
		return
	end
	table.insert(self.snapshots, snapshot)
	self.target = snapshot.target
	self.threatMax = math.max(self.threatMax, snapshot.threatMax)
	local allUnits = getAllUnits()
	for guid,_ in pairs(snapshot.threat) do
		if allUnits[guid] and not self.targets[guid] then
			self.targets[guid] = {select(1, UnitFullName(allUnits[guid])), select(2, UnitClass(allUnits[guid]))}
		end
	end
	if f.plot and f.plot.unit == self then
		f.plot:destroy()
		f.plot = Plot:new(self)
	end
end

local units = {}

-- Source: https://www.reddit.com/r/WowUI/comments/95o7qc/other_how_to_pixel_perfect_ui_xpost_rwow/
local pixelSize = 768 / UIParent:GetScale() / string.match( GetCVar( "gxWindowedResolution" ), "%d+x(%d+)" )

f:Hide()
f.textures = {}
f.lines = {}
f.texts = {}
f:SetFrameStrata("BACKGROUND")
f:SetPoint("CENTER", 0, 0)
f:SetWidth(500)
f:SetHeight(500)
f:SetMovable(true)
f:SetResizable(true)
f:SetFrameStrata("DIALOG")
f.background = f:CreateTexture()
f.background:SetDrawLayer("BACKGROUND", -1)
f.background:SetColorTexture(0, 0, 0, .5)
f.background:SetAllPoints()
f.title = CreateFrame("FRAME", nil, f)
f.title:SetPoint("TOPLEFT")
f.title:SetPoint("RIGHT")
f.title:SetMovable(true)
f.title:EnableMouse(true)
f.title:RegisterForDrag("LeftButton")
f.title:SetScript("OnDragStart", function() f:StartMoving() end)
f.title:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
f.title.background = f.title:CreateTexture()
f.title.background:SetColorTexture(0, 0, 0, 0.5)
f.title.background:SetAllPoints()
f.title.text = f.title:CreateFontString(nil, "ARTWORK")
f.title.text:SetFont("Fonts\\FRIZQT__.TTF", 11)
f.title.text:SetText("Threat")
f.title.text:SetPoint("TOPLEFT")
f.title:SetHeight(f.title.text:GetStringHeight())
f.resize = CreateFrame("FRAME", nil, f)
f.resize:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
f.resize:SetWidth(10)
f.resize:SetHeight(10)
f.resize:SetMovable(true)
f.resize:EnableMouse(true)
f.resize:RegisterForDrag("LeftButton")
f.resize:SetScript("OnDragStart", function() f:StartSizing("BOTTOMRIGHT") end)
f.resize:SetScript("OnDragStop", function()
	f:StopMovingOrSizing()
	if f.plot then
		local u = f.plot.unit
		f.plot:destroy()
		f.plot = Plot:new(u)
	end
end)
f.resize.texture = f.resize:CreateTexture(nil, "BACKGROUND")
f.resize.texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
f.resize.texture:SetAllPoints()
f.resize.texture:Show()

local function OnUpdate(self)
	for guid,unitId in pairs(getAllUnits()) do
		if units[guid] and units[guid].target ~= UnitGUID(unitId .. "target") then
			units[guid]:snapshot(unitId)
		end
	end
	if not self.plot or not f:IsVisible() then
		return
	end
	local x,y = GetCursorPosition()
	x = x / self:GetEffectiveScale() - self:GetLeft() - self.plot.plotLeft
	y = y / self:GetEffectiveScale() - self:GetBottom() - self.plot.plotBottom
	if x < 0 or x > self.plot.plotWidth or y < 0 or y > self.plot.plotHeight then
		return
	end
	local t = x * self.plot.duration / self.plot.plotWidth + self.plot.timeMin
	local lastSnapshot
	for _,snapshot in pairs(self.plot.unit.snapshots) do
		if snapshot.timestamp > t then break end
		lastSnapshot = snapshot
	end
	if lastSnapshot == nil then
		GameTooltip:Hide()
		return
	end
	local a = {}
	for guid,threat in pairs(lastSnapshot.threat) do
		table.insert(a, {threat, guid})
	end
	table.sort(a, function(a,b) return a[1] > b[1] end)
	GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
	GameTooltip:AddDoubleLine("Time", string.format("%.3f", lastSnapshot.timestamp - self.plot.timeMin))
	for i = 1, #a do
		local b = a[i]
		local target = self.plot.unit.targets[b[2]]
		local cr,cg,cb = GetClassColor(target[2])
		if lastSnapshot.tanking == b[2] then
			GameTooltip:AddDoubleLine(target[1], b[1], cr,cg,cb,1,0,0)
		else
			GameTooltip:AddDoubleLine(target[1], b[1], cr,cg,cb,cr,cg,cb)
		end
	end
	GameTooltip:Show()
end

f.popTexture = function(self)
	if #self.textures > 0 then
		return table.remove(self.textures)
	end
	return self:CreateTexture(nil, "BACKGROUND")
end
f.pushTexture = function(self, tex)
	if tex == nil then return end
	tex:Hide()
	tex:ClearAllPoints()
	table.insert(self.textures, tex)
end
f.popLine = function(self)
	if #self.lines > 0 then
		return table.remove(self.lines)
	end
	return self:CreateLine()
end
f.pushLine = function(self, line)
	if line == nil then return end
	line:Hide()
	table.insert(self.lines, line)
end
f.popText = function(self)
	if #self.texts > 0 then
		return table.remove(self.texts)
	end
	return self:CreateFontString()
end
f.pushText = function(self, text)
	if text == nil then return end
	text:Hide()
	text:ClearAllPoints()
	table.insert(self.texts, text)
end

local Trace = createClass()
Trace.constructor = function(self, unit, targetGuid, plot)
	self.lines = {}
	self.aggrolines = {}
	self:draw(unit, targetGuid, plot)
end
Trace.destroy = function(self)
	for i = 1, #self.lines do
		f:pushLine(table.remove(self.lines))
	end
	for i = 1, #self.aggrolines do
		f:pushLine(table.remove(self.aggrolines))
	end
	f:pushText(self.text)
	self.text = nil
end
Trace.draw = function(self, unit, targetGuid, plot)
	local timeMin = unit.snapshots[1].timestamp
	local timeMax = unit.snapshots[#unit.snapshots].timestamp
	local duration = timeMax - timeMin
	self.x = timeMin
	self.y = 0
	self.tanking = false
	for i = 1, #unit.snapshots do
		local snapshot = unit.snapshots[i]
		local u = snapshot.timestamp
		local v = snapshot.threat[targetGuid]
		if v then
			self:addPoint(plot, u, v, snapshot.tanking == targetGuid, snapshot.target == targetGuid)
		else
			if self.y ~= 0 then
				self:addPoint(plot, u, 0, snapshot.tanking == targetGuid, snapshot.target == targetGuid)
			end
			self.x = u
		end
	end
	if self.lastVisibleX then
		self.text = f:popText()
		self.text:SetDrawLayer("BACKGROUND")
		self.text:SetFont("Fonts\\FRIZQT__.TTF", 11)
		self.text:SetText(unit.targets[targetGuid][1])
		local a,b = plot:mapPoint(self.lastVisibleX,self.y)
		self.text:SetPoint("LEFT", f, "BOTTOMLEFT", a + 4, b)
		self.text:Show()
	end
end
Trace.SetColorTexture = function(self, ...)
	for _,t in pairs(self.lines) do
		t:SetColorTexture(...)
	end
	self.text:SetTextColor(...)
end
Trace.addPoint = function(self, plot, x, y, tanking, target)
	if self.tanking then
		local T = f:popLine()
		local a,b = plot:mapPoint(self.x,self.y)
		T:SetStartPoint("BOTTOMLEFT", a - 3 * pixelSize, b)
		T:SetEndPoint("BOTTOMLEFT", plot:mapPoint(x,self.y))
		T:SetThickness(6 * pixelSize)
		T:SetColorTexture(1, 0, 0)
		T:SetDrawLayer("BACKGROUND", -1)
		T:Show()
		table.insert(self.aggrolines, T)
	end
	if self.target then
		local T = f:popLine()
		local a,b = plot:mapPoint(self.x,self.y)
		T:SetStartPoint("BOTTOMLEFT", a - 3 * pixelSize, b)
		T:SetEndPoint("BOTTOMLEFT", plot:mapPoint(x,self.y))
		T:SetThickness(10 * pixelSize)
		T:SetColorTexture(0, 0, 1)
		T:SetDrawLayer("BACKGROUND", -2)
		T:Show()
		table.insert(self.aggrolines, T)
	end
	local T = f:popLine()
	T:SetStartPoint("BOTTOMLEFT", plot:mapPoint(self.x,self.y))
	T:SetEndPoint("BOTTOMLEFT", plot:mapPoint(x,self.y))
	T:SetThickness(2 * pixelSize)
	T:SetDrawLayer("BACKGROUND", 0)
	T:Show()
	table.insert(self.lines, T)
	if y ~= self.y then
		if tanking then
			local T = f:popLine()
			local a,b = plot:mapPoint(x,self.y)
			T:SetStartPoint("BOTTOMLEFT", a, b - 3 * pixelSize)
			T:SetEndPoint("BOTTOMLEFT", plot:mapPoint(x,y))
			T:SetThickness(6 * pixelSize)
			T:SetColorTexture(1, 0, 0)
			T:SetDrawLayer("BACKGROUND", -1)
			T:Show()
			table.insert(self.aggrolines, T)
		end
		if target then
			local T = f:popLine()
			local a,b = plot:mapPoint(x,self.y)
			T:SetStartPoint("BOTTOMLEFT", a, b - 3 * pixelSize)
			T:SetEndPoint("BOTTOMLEFT", plot:mapPoint(x,y))
			T:SetThickness(10 * pixelSize)
			T:SetColorTexture(0, 0, 1)
			T:SetDrawLayer("BACKGROUND", -2)
			T:Show()
			table.insert(self.aggrolines, T)
		end
		T = f:popLine()
		T:SetStartPoint("BOTTOMLEFT", plot:mapPoint(x,self.y))
		T:SetEndPoint("BOTTOMLEFT", plot:mapPoint(x,y))
		T:SetThickness(2 * pixelSize)
		T:SetDrawLayer("BACKGROUND", 0)
		T:Show()
		table.insert(self.lines, T)
	end
	self.x = x
	self.y = y
	self.tanking = tanking
	self.target = target
	self.lastVisibleX = x
end

Plot.constructor = function(self, unit)
	self.unit = unit
	f.title.text:SetText("Threat for " .. unit.name)
	local longestName = 0
	for _,u in pairs(unit.targets) do
		longestName = math.max(longestName, string.len(u[1]))
	end
	self.plotLeft = 20
	self.plotBottom = 20
	self.plotWidth = f:GetWidth() - 20
	self.plotHeight = f:GetHeight() - f.title:GetHeight() - 20
	if #unit.snapshots > 0 then
		self.timeMin = unit.snapshots[1].timestamp
		self.timeMax = unit.snapshots[#unit.snapshots].timestamp
	else
		self.timeMin = 0
		self.timeMax = 1
	end
	self.duration = (self.timeMax - self.timeMin) * (1.05 + (longestName+1) / self.plotWidth * 6)
	self.timeMax = self.timeMin + self.duration
	self.threatMax = unit.threatMax * 1.05
	self.lines = {}
	self.texts = {}
	self.traces = {}
	if self.duration == 0 or self.threatMax == 0 then return end
	self.xtick = 10 ^ math.floor(math.log10(self.duration))
	self.ytick = 10 ^ math.floor(math.log10(self.threatMax))
	if self.duration / self.xtick < 4 then self.xtick = self.xtick / 2 end
	if self.duration / self.xtick < 4 then self.xtick = self.xtick / 2 end
	if self.threatMax / self.ytick < 4 then self.ytick = self.ytick / 2 end
	if self.threatMax / self.ytick < 4 then self.ytick = self.ytick / 2 end
	for x = 0, self.duration, self.xtick do
		local T = f:popLine()
		T:SetColorTexture(.5, .5, .5)
		T:SetStartPoint("BOTTOMLEFT", self:mapPoint(x + self.timeMin, 0))
		T:SetEndPoint("BOTTOMLEFT", self:mapPoint(x + self.timeMin, self.threatMax))
		T:SetThickness(pixelSize)
		T:SetDrawLayer("BACKGROUND", -4)
		T:Show()
		table.insert(self.lines, T)
		local text = f:popText()
		text:SetFont("Fonts\\FRIZQT__.TTF", 11)
		text:SetTextColor(1,1,1)
		text:SetText(tostring(x))
		text:SetPoint("TOP", f, "BOTTOMLEFT", self:mapPoint(x + self.timeMin, 0))
		text:Show()
		table.insert(self.texts, text)
	end
	for y = 0, self.threatMax, self.ytick do
		local T = f:popLine()
		T:SetColorTexture(.5, .5, .5)
		T:SetStartPoint("BOTTOMLEFT", self:mapPoint(self.timeMin, y))
		T:SetEndPoint("BOTTOMLEFT", self:mapPoint(self.timeMax, y))
		T:SetThickness(pixelSize)
		T:SetDrawLayer("BACKGROUND", -4)
		T:Show()
		table.insert(self.lines, T)
		local text = f:popText()
		text:SetFont("Fonts\\FRIZQT__.TTF", 11)
		text:SetTextColor(1,1,1)
		text:SetText(tostring(y))
		text:SetPoint("RIGHT", f, "BOTTOMLEFT", self:mapPoint(self.timeMin, y))
		text:Show()
		table.insert(self.texts, text)
	end
	for guid,_ in pairs(unit.targets) do
		local trace = Trace:new(unit, guid, self)
		trace:SetColorTexture(GetClassColor(unit.targets[guid][2]))
		table.insert(self.traces, trace)
	end
end
Plot.destroy = function(self)
	for i = 1, #self.lines do
		f:pushLine(table.remove(self.lines))
	end
	for i = 1, #self.texts do
		f:pushText(table.remove(self.texts))
	end
	for i = 1, #self.traces do
		table.remove(self.traces):destroy()
	end
end
Plot.mapPoint = function(self, time, threat)
	return self.plotLeft + (time - self.timeMin) / self.duration * self.plotWidth,
			self.plotBottom + threat / self.threatMax * self.plotHeight
end

f:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
f:RegisterEvent("PLAYER_TARGET_CHANGED")
f:SetScript("OnLeave", function(self)
	GameTooltip:Hide()
end)
f:SetScript("OnUpdate", OnUpdate)
f:SetScript("OnEvent", function(self,e,t)
	if e == "UNIT_THREAT_LIST_UPDATE" then
		local guid = UnitGUID(t)
		if not units[guid] then
			units[guid] = Unit:new(t)
		end
		units[guid]:snapshot(t)
		if not f.plot and f:IsVisible() and t == "target" then
			f.plot = Plot:new(units[guid])
		end
	elseif e == "PLAYER_TARGET_CHANGED" then
		if f.plot then
			f.plot:destroy()
			f.plot = nil
		end
		local guid = UnitGUID("target")
		if guid and units[guid] then
			f.plot = Plot:new(units[guid])
		end
	end
end)

SLASH_THREATLOG1 = "/threatlog"
SlashCmdList.THREATLOG = function(s)
	if s == "show" then
		f:Show()
		if f.plot then
			f.plot:destroy()
			f.plot = nil
		end
		if UnitExists("target") and units[UnitGUID("target")] then
			f.plot = Plot:new(units[UnitGUID("target")])
		end
	elseif s == "hide" then
		f:Hide()
		if f.plot then
			f.plot:destroy()
			f.plot = nil
		end
	elseif s == "list" then
		print("Targets saved by threatlog:")
		for _,u in pairs(units) do
			print(string.format("  %s (%s)", u.name, u.guid))
		end
	elseif s:match("^search ") then
		local t = s:match(" (.*)")
		for _,u in pairs(units) do
			if u.guid:match(t) or u.name:match(t) then
				if f.plot then
					f.plot:destroy()
				end
				f.plot = Plot:new(u)
				print(string.format("Showing threat plot for %s (%s).", u.name, u.guid))
				return
			end
		end
	else
		print("Usage:\n  /threatlog show - Shows the plot\n  /threatlog hide - Hides the plot\n  /threatlog list - Lists all saved targets.\n  /threatlog search name - Shows the plot for some unit matching the string. Case sensitive.")
	end
end
