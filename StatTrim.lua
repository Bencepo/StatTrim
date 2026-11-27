-- StatTrim: hide and reorder categories and stats in the character window (WoW: Forever).
-- Edit mode (gear icon above the stats panel): checkboxes and arrows on every row.
-- Normal mode: unchecked rows are removed, the rest move up.

local ADDON = ...
local ipairs, next, type, tostring, select, unpack, pcall, wipe = ipairs, next, type, tostring, select, unpack, pcall, wipe
local abs, max, min = math.abs, math.max, math.min
local tsort, tinsert, tremove = table.sort, tinsert, tremove
local format = string.format
local PREFIX = "|cff66ccffStatTrim|r"
local accDB, db, container, opt, editBtn
local editMode = false
local RefreshOptions, ToggleOptions
local EMPTY = {}

-- Non-stats tab frames inside CharacterFrame that must never be mistaken for the stats panel.
local OTHER_TABS = { "ReputationFrame", "TokenFrame", "SkillFrame", "HonorFrame", "PetPaperDollFrame", "CurrencyFrame" }

local function IsOtherTabFrame(f)
  for i = 1, #OTHER_TABS do
    local t = _G[OTHER_TABS[i]]
    if t and f == t then return true end
  end
  return false
end

local function IsOtherTabOpen()
  for i = 1, #OTHER_TABS do
    local t = _G[OTHER_TABS[i]]
    if t and t.IsVisible and t:IsVisible() then return true end
  end
  return false
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Clean(t)
  if t == nil then return nil end
  if issecretvalue and issecretvalue(t) then return nil end
  t = tostring(t):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  t = t:gsub("^%s+", ""):gsub("[%s:]+$", "")
  if t == "" then return nil end
  return t
end

-- A number StatTrim may compare or calculate with: nil for a secret value. WoW Forever hides
-- frame positions and sizes as secret numbers in some states; comparing one is a Lua error.
local function Pub(v)
  if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
  return v
end

local function RowInfoRegions(c, ...)
  local n, label, lx = 0, nil, nil
  for i = 1, select("#", ...) do
    local r = select(i, ...)
    if r:GetObjectType() == "FontString" and r:IsShown() then
      n = n + 1
      local ok, t = pcall(Clean, r:GetText())
      if ok and t then
        local x = Pub(r:GetLeft()) or 0
        if not label or (lx and x < lx) then label, lx = t, x end
      end
    end
  end
  if not label then return nil end
  return (c.Value ~= nil) or n >= 2, label
end

-- isStat, label of a row (nil if no readable text)
local function RowInfo(c)
  return RowInfoRegions(c, c:GetRegions())
end

local function CountRowChildren(...)
  local n = 0
  for i = 1, select("#", ...) do
    local c = select(i, ...)
    if not c:IsForbidden() and c:IsVisible() and RowInfo(c) then n = n + 1 end
  end
  return n
end

local function WalkChildren(depth, cb, ...)
  for i = 1, select("#", ...) do
    local c = select(i, ...)
    if not c:IsForbidden() and not IsOtherTabFrame(c) then
      cb(c)
      if depth > 0 then WalkChildren(depth - 1, cb, c:GetChildren()) end
    end
  end
end

local function Walk(f, depth, cb)
  if not f or f:IsForbidden() or IsOtherTabFrame(f) then return end
  cb(f)
  if depth <= 0 then return end
  WalkChildren(depth - 1, cb, f:GetChildren())
end

local function FindContainer()
  if not (CharacterFrame and CharacterFrame:IsVisible()) then return nil end
  if IsOtherTabOpen() then return nil end
  local best, bestN, bestHasDP = nil, 0, false
  Walk(CharacterFrame, 10, function(f)
    if not f:IsVisible() then return end
    local n = CountRowChildren(f:GetChildren())
    if n >= 5 then
      local p = f:GetParent()
      local hasDP = (p and p.GetDataProvider ~= nil) and true or false
      if (hasDP and not bestHasDP) or (hasDP == bestHasDP and n > bestN) then
        best, bestN, bestHasDP = f, n, hasDP
      end
    end
  end)
  return best
end

local function Key(cat, stat) return stat and (cat .. "::" .. stat) or cat end

---------------------------------------------------------------------------
-- Positions (legacy path): remember original, restack, restore
---------------------------------------------------------------------------
local function Capture(c)
  local ct, cl, cr = Pub(container:GetTop()), Pub(container:GetLeft()), Pub(container:GetRight())
  local t, l, r = Pub(c:GetTop()), Pub(c:GetLeft()), Pub(c:GetRight())
  local h = Pub(c:GetHeight())
  if not (ct and cl and cr and t and l and r and h) then return false end
  local pts = {}
  for i = 1, c:GetNumPoints() do pts[i] = { c:GetPoint(i) } end
  c.__stOrig = { pts = pts, off = ct - t, l = l - cl, r = r - cr, h = h }
  return true
end

local function IsOurs(c)
  local s = c.__stSet
  if not s or c:GetNumPoints() ~= 2 then return false end
  local pt, rel, _, x, y = c:GetPoint(1)
  x, y = Pub(x), Pub(y)
  return pt == "TOPLEFT" and rel == container
    and abs((x or 0) - s.x) < 0.01 and abs((y or 0) - s.y) < 0.01
end

local function Restore(c)
  if not c.__stSet then return end
  c:ClearAllPoints()
  for _, p in ipairs(c.__stOrig.pts) do c:SetPoint(unpack(p, 1, 5)) end
  c.__stSet = nil
end

local function Place(c, off)
  local o = c.__stOrig
  c:ClearAllPoints()
  c:SetPoint("TOPLEFT", container, "TOPLEFT", o.l, -off)
  c:SetPoint("TOPRIGHT", container, "TOPRIGHT", o.r, -off)
  local s = c.__stSet
  if s then
    s.x, s.y = o.l, -off
  else
    c.__stSet = { x = o.l, y = -off }
  end
end

-- mode: "show" | "dim" | "hide"
local function SetVisual(c, mode)
  if c.__stMouse == nil then c.__stMouse = c:IsMouseEnabled() end
  if mode == "hide" then
    c:SetAlpha(0)
    if c.__stMouse then c:EnableMouse(false) end
  else
    c:SetAlpha(mode == "dim" and 0.35 or 1)
    if c.__stMouse then c:EnableMouse(true) end
  end
end

---------------------------------------------------------------------------
-- Checkboxes on the rows
---------------------------------------------------------------------------
local Apply

local function GetRowCB(c)
  local cb = c.__stCB
  if not cb then
    cb = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
    cb:SetSize(18, 18)
    cb:SetPoint("LEFT", c, "LEFT", -6, 0)
    cb:SetFrameLevel(c:GetFrameLevel() + 10)
    if cb.SetIgnoreParentAlpha then cb:SetIgnoreParentAlpha(true) end
    cb:SetScript("OnClick", function(self)
      db.hidden[self.key] = (not self:GetChecked()) or nil
      Apply()
      if opt and opt:IsShown() then RefreshOptions() end
    end)
    c.__stCB = cb
  end
  return cb
end

local function HideRowCB(c)
  if c.__stCB then c.__stCB:Hide() end
end

---------------------------------------------------------------------------
-- Scan + apply
---------------------------------------------------------------------------
local knownSets = {}
local function Remember(items)
  local changed, k = false, db.known
  for i = 1, #items do
    local it = items[i]
    if it.cat then
      if not k.stats[it.cat] then
        k.stats[it.cat] = {}; tinsert(k.cats, it.cat); changed = true
      end
      if it.stat then
        local set = knownSets[it.cat]
        if not set then
          set = {}
          for _, s in ipairs(k.stats[it.cat]) do set[s] = true end
          knownSets[it.cat] = set
        end
        if not set[it.label] then
          set[it.label] = true
          tinsert(k.stats[it.cat], it.label)
          changed = true
        end
      end
    end
  end
  return changed
end

local tall -- forward declaration for editBtn combat guard

local function ToggleEditMode()
  if not editMode and not tall and InCombatLockdown() then
    print(PREFIX .. " Edit mode can only be entered out of combat.")
    return false
  end
  editMode = not editMode
  Apply()
  return true
end

local function UpdateEditButton()
  if not container then return end
  if not editBtn then
    local anchor = container:GetParent() or container
    editBtn = CreateFrame("Button", nil, anchor:GetParent() or CharacterFrame)
    editBtn:SetSize(20, 20)
    editBtn:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    editBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    editBtn:SetFrameLevel(anchor:GetFrameLevel() + 20)
    editBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    editBtn:SetScript("OnClick", function(_, button)
      if button == "RightButton" then ToggleOptions() return end
      ToggleEditMode()
    end)
    editBtn:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("StatTrim")
      GameTooltip:AddLine(editMode and "Click: finish editing" or "Click: show/hide and reorder stats", 1, 1, 1)
      GameTooltip:AddLine("Right-click: list window, default order, report a bug", 0.7, 0.7, 0.7)
      GameTooltip:Show()
    end)
    editBtn:SetScript("OnLeave", GameTooltip_Hide)
  end
  local anchor = container:GetParent() or container
  editBtn:ClearAllPoints()
  editBtn:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -2, 4)
  editBtn:Show()
  if editMode then editBtn:LockHighlight() else editBtn:UnlockHighlight() end
end

---------------------------------------------------------------------------
-- ScrollBox path (taint-safe): never touch Blizzard's data provider.
-- The ScrollBox is made tall once (out of combat) so every row frame exists,
-- then rows are only repositioned / faded. Scrolling is handled by StatTrim.
---------------------------------------------------------------------------
local sb, sbOrig, viewH
local scroll, maxScroll = 0, 0
local relayouting = false
local pendingRelayout = false
local curCats, curStats = {}, {} -- current order (for arrows)
local lastFinal = {}             -- cached ordered rows for lightweight wheel scrolling
local TALL_HEIGHT = 2000
local WHEEL_STEP = 46

local Relayout

local function Active()
  if editMode then return true end
  if next(db.hidden) then return true end
  if db.order.cats or next(db.order.stats) then return true end
  return false
end

-- Everything anchored to the ScrollBox (scrollbar, its own textures) is moved to a
-- proxy frame with the original rect, so nothing stretches with the tall ScrollBox.
local proxy
local moved = {}

local function Reanchor(obj, isOwnRegion)
  local n = obj:GetNumPoints()
  if n == 0 then return end
  local pts, hit = {}, false
  for i = 1, n do
    local p = { obj:GetPoint(i) }
    pts[i] = p
    if p[2] == sb or (isOwnRegion and p[2] == nil) then hit = true end
  end
  if not hit then return end
  moved[#moved + 1] = { obj = obj, pts = pts }
  obj:ClearAllPoints()
  for _, p in ipairs(pts) do
    local rel = p[2]
    if rel == sb or (isOwnRegion and rel == nil) then rel = proxy end
    obj:SetPoint(p[1], rel, p[3], p[4], p[5])
  end
end

local function ReanchorChildren(...)
  for i = 1, select("#", ...) do
    local c = select(i, ...)
    if c ~= sb and c ~= proxy and c ~= editBtn and not c:IsForbidden() then Reanchor(c, false) end
  end
end

local function ReanchorRegions(...)
  for i = 1, select("#", ...) do
    Reanchor(select(i, ...), true)
  end
end

local function MakeTall()
  if tall then return true end
  if InCombatLockdown() then
    pendingRelayout = true
    return false
  end
  local parent = sb:GetParent()
  local l, t, pl, pt = Pub(sb:GetLeft()), Pub(sb:GetTop()), Pub(parent:GetLeft()), Pub(parent:GetTop())
  if not (l and t and pl and pt and Pub(sb:GetHeight()) and Pub(sb:GetWidth())) then return false end
  local pts = {}
  for i = 1, sb:GetNumPoints() do pts[i] = { sb:GetPoint(i) } end
  viewH = sb:GetHeight()
  sbOrig = { pts = pts, w = sb:GetWidth(), hit = { sb:GetHitRectInsets() } }

  proxy = proxy or CreateFrame("Frame", nil, parent)
  proxy:ClearAllPoints()
  for _, p in ipairs(pts) do proxy:SetPoint(unpack(p, 1, 5)) end
  if #pts < 2 then proxy:SetSize(sbOrig.w, viewH) end

  wipe(moved)
  ReanchorChildren(parent:GetChildren())
  ReanchorRegions(sb:GetRegions())

  sb:ClearAllPoints()
  sb:SetPoint("TOPLEFT", parent, "TOPLEFT", l - pl, t - pt)
  sb:SetSize(sbOrig.w, TALL_HEIGHT)
  -- Only the original area reacts to the mouse
  sb:SetHitRectInsets(0, 0, 0, TALL_HEIGHT - viewH)
  tall = true
  scroll = 0
  return true
end

local function RestoreSB()
  if not tall or InCombatLockdown() then return end
  sb:ClearAllPoints()
  for _, p in ipairs(sbOrig.pts) do sb:SetPoint(unpack(p, 1, 5)) end
  sb:SetHeight(viewH)
  sb:SetHitRectInsets(unpack(sbOrig.hit))
  for i = #moved, 1, -1 do
    local m = moved[i]
    m.obj:ClearAllPoints()
    for _, p in ipairs(m.pts) do m.obj:SetPoint(unpack(p, 1, 5)) end
  end
  wipe(moved)
  tall = false
end

local function Move(kind, cat, label, dir)
  local src = (kind == "cat") and curCats or curStats[cat]
  if not src then return end
  local list = {}
  for i, v in ipairs(src) do list[i] = v end
  local want = (kind == "cat") and cat or label
  for i, v in ipairs(list) do
    if v == want then
      local j = i + dir
      if j >= 1 and j <= #list then list[i], list[j] = list[j], list[i] end
      break
    end
  end
  if kind == "cat" then db.order.cats = list else db.order.stats[cat] = list end
  Apply()
end

local function TipOnEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(self.__stTip, 1, 1, 1); GameTooltip:Show()
end

-- scripts are set once per frame; later calls only change the text
local function SetTip(f, text)
  f.__stTip = text
  if f.__stTipSet then return end
  f.__stTipSet = true
  f:SetScript("OnEnter", TipOnEnter)
  f:SetScript("OnLeave", GameTooltip_Hide)
end

local function MakeArrow(parent, up)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(16, 16)
  b:SetNormalTexture(up and "Interface\\Buttons\\Arrow-Up-Up" or "Interface\\Buttons\\Arrow-Down-Up")
  b:SetPushedTexture(up and "Interface\\Buttons\\Arrow-Up-Down" or "Interface\\Buttons\\Arrow-Down-Down")
  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  b:SetFrameLevel(parent:GetFrameLevel() + 10)
  if b.SetIgnoreParentAlpha then b:SetIgnoreParentAlpha(true) end
  b:SetScript("OnClick", function(self) Move(self.kind, self.cat, self.label, up and -1 or 1) end)
  SetTip(b, up and "Move up" or "Move down")
  return b
end

local function Controls(c)
  local t = c.__stCtl
  if t then return t end
  t = {}
  t.cb = GetRowCB(c)
  t.name = CreateFrame("CheckButton", nil, c, "UICheckButtonTemplate")
  t.name:SetSize(18, 18)
  t.name:SetPoint("RIGHT", c, "RIGHT", -38, 0)
  t.name:SetFrameLevel(c:GetFrameLevel() + 10)
  if t.name.SetIgnoreParentAlpha then t.name:SetIgnoreParentAlpha(true) end
  t.name:SetScript("OnClick", function(self)
    db.hidden[self.key] = (not self:GetChecked()) or nil
    Apply()
  end)
  SetTip(t.name, "Show category name (stats stay visible)")
  t.up = MakeArrow(c, true);  t.up:SetPoint("RIGHT", c, "RIGHT", -20, 0)
  t.down = MakeArrow(c, false); t.down:SetPoint("RIGHT", c, "RIGHT", -4, 0)
  c.__stCtl = t
  return t
end

-- Edit mode text layout: shift the label right of the checkbox, hide the value
-- so the arrows don't cover it. Restored when edit mode ends.
local LABEL_SHIFT = 14

local function RestoreTextRegions(...)
  for i = 1, select("#", ...) do
    local r = select(i, ...)
    if r.__stEdit and r:GetObjectType() == "FontString" then
      if r.__stPts then
        r:ClearAllPoints()
        for _, p in ipairs(r.__stPts) do r:SetPoint(unpack(p, 1, 5)) end
      end
      if r.__stAlpha then r:SetAlpha(r.__stAlpha) end
      r.__stEdit, r.__stPts, r.__stAlpha = nil, nil, nil
    end
  end
end

local function RestoreText(c)
  if not c.__stTextEdited then return end
  c.__stTextEdited = nil
  RestoreTextRegions(c:GetRegions())
end

local function TextIntactRegions(...)
  for i = 1, select("#", ...) do
    local r = select(i, ...)
    if r.__stEdit and r:GetObjectType() == "FontString" then
      if r.__stPts then
        local p = r.__stPts[1]
        local _, _, _, x = r:GetPoint(1)
        x = Pub(x)
        if not (p and x) or math.abs(x - ((p[4] or 0) + LABEL_SHIFT)) > 0.01 then return false end
      elseif r.__stAlpha and (Pub(r:GetAlpha()) or 0) > 0 then
        return false
      end
    end
  end
  return true
end

-- false if Blizzard reset the shifted label's points or a faded text's alpha
local function TextIntact(c)
  return TextIntactRegions(c:GetRegions())
end

local function DropStaleEditRegions(...)
  for i = 1, select("#", ...) do
    local r = select(i, ...)
    if r.__stEdit then
      if r.__stAlpha then r:SetAlpha(r.__stAlpha) end
      r.__stEdit, r.__stPts, r.__stAlpha = nil, nil, nil
    end
  end
end

local editFS = {}
local function CollectVisibleFS(...)
  wipe(editFS)
  local label, lx = nil, nil
  for i = 1, select("#", ...) do
    local r = select(i, ...)
    if r:GetObjectType() == "FontString" and r:IsShown() then
      editFS[#editFS + 1] = r
      local x = Pub(r:GetLeft())
      if not label or (x and (not lx or x < lx)) then label, lx = r, x end
    end
  end
  return label
end

local function EditText(c, isStat)
  if c.__stTextEdited == "stat" and not TextIntact(c) then
    -- Blizzard put the label back itself: drop the stale state, keep its points
    DropStaleEditRegions(c:GetRegions())
    c.__stTextEdited = nil
  end
  if c.__stTextEdited == (isStat and "stat" or "head") then return end
  RestoreText(c)
  if not isStat then c.__stTextEdited = "head"; return end
  local label = CollectVisibleFS(c:GetRegions())
  for i = 1, #editFS do
    local r = editFS[i]
    r.__stEdit = true
    if r == label then
      local pts = {}
      for j = 1, r:GetNumPoints() do pts[j] = { r:GetPoint(j) } end
      r.__stPts = pts
      r:ClearAllPoints()
      for _, p in ipairs(pts) do
        r:SetPoint(p[1], p[2], p[3], (p[4] or 0) + LABEL_SHIFT, p[5] or 0)
      end
    else
      r.__stAlpha = Pub(r:GetAlpha()) or 1
      r:SetAlpha(0)
    end
  end
  c.__stTextEdited = "stat"
end

local function HideControls(c)
  local t = c.__stCtl
  if t then
    t.cb:Hide(); t.name:Hide(); t.up:Hide(); t.down:Hide()
  else
    HideRowCB(c)
  end
  RestoreText(c)
end

-- Hoisted sort helpers + O(1) rank maps
local function SortByOff(a, b) return a.off < b.off end

local sortCatRank, sortCatPos
local function SortCats(a, b)
  local ra = (sortCatRank and sortCatRank[a]) or (1000 + sortCatPos[a])
  local rb = (sortCatRank and sortCatRank[b]) or (1000 + sortCatPos[b])
  if ra ~= rb then return ra < rb end
  return sortCatPos[a] < sortCatPos[b]
end

local sortStatRank
local function SortStats(a, b)
  local ra = (sortStatRank and (sortStatRank[a.okey] or (a.okey ~= a.label and sortStatRank[a.label]))) or (1000 + a.pos)
  local rb = (sortStatRank and (sortStatRank[b.okey] or (b.okey ~= b.label and sortStatRank[b.label]))) or (1000 + b.pos)
  if ra ~= rb then return ra < rb end
  return a.pos < b.pos
end

local rankMapScratch = {}
local function BuildRankMap(list)
  if not list then return nil end
  wipe(rankMapScratch)
  for i = 1, #list do
    if rankMapScratch[list[i]] == nil then rankMapScratch[list[i]] = i end
  end
  return rankMapScratch
end

local touched = false -- rows were moved, faded or got controls since the last RestoreAll

local function RestoreChildren(...)
  for i = 1, select("#", ...) do
    local c = select(i, ...)
    if not c:IsForbidden() then
      Restore(c)
      HideControls(c)
      SetVisual(c, "show")
    end
  end
end

local function HideChildrenControls(...)
  for i = 1, select("#", ...) do
    local c = select(i, ...)
    if not c:IsForbidden() then HideControls(c) end
  end
end

local function RestoreAll()
  if not (touched or tall) then return end
  touched = false
  wipe(lastFinal)
  if container then RestoreChildren(container:GetChildren()) end
  RestoreSB()
end

-- Reposition and apply visibility/controls for the ordered `lastFinal` rows.
-- Used both at the end of DoRelayout() and directly on mouse-wheel scrolling.
local function PositionRows()
  local cursor = 0
  for i = 1, #lastFinal do
    local it = lastFinal[i]
    local c = it.f
    if not editMode and it.hide then
      HideControls(c)
      SetVisual(c, "hide")
    else
      local y = cursor - scroll
      Place(c, y)
      cursor = cursor + it.h
      local inside = y > -0.5 and (y + it.h) <= (viewH or 0) + 0.5
      if not inside then
        HideControls(c)
        SetVisual(c, "hide")
      elseif editMode and it.cat then
        local t = Controls(c)
        local catOff = db.hidden[it.cat]
        if it.stat then
          t.cb.key = Key(it.cat, it.label)
          t.cb:SetChecked(not db.hidden[t.cb.key])
          if catOff then t.cb:Disable() else t.cb:Enable() end
          t.name:Hide()
          t.up.kind, t.down.kind = "stat", "stat"
        else
          t.cb.key = it.cat
          t.cb:SetChecked(not catOff); t.cb:Enable()
          t.name.key = it.cat .. "##name"
          t.name:SetChecked(not db.hidden[t.name.key]); t.name:Show()
          t.up.kind, t.down.kind = "cat", "cat"
        end
        SetTip(t.cb, it.stat and "Show stat" or "Show whole category")
        local mc = it.stat and (it.host or it.cat) or it.cat
        local ml = it.stat and it.okey or it.label
        t.up.cat, t.up.label, t.down.cat, t.down.label = mc, ml, mc, ml
        t.cb:Show(); t.up:Show(); t.down:Show()
        EditText(c, it.stat)
        SetVisual(c, it.hide and "dim" or "show")
      else
        HideControls(c)
        SetVisual(c, "show")
      end
    end
  end
end

local relayoutItems, itemPool = {}, {}
local preBuf, catPosBuf = {}, {}

local function CollectRows(...)
  local n = #relayoutItems
  for i = 1, select("#", ...) do
    local c = select(i, ...)
    if not c:IsForbidden() and c:IsShown() then
      c.__stSeen = true
      local isStat, label = RowInfo(c)
      if label then
        if c.__stSet and not IsOurs(c) then c.__stSet = nil; c.__stOrig = nil end
        if c.__stOrig or Capture(c) then
          -- Always read current height so ScrollBox recycling of row #1 never uses a stale height.
          local h = Pub(c:GetHeight()) or 0
          n = n + 1
          local it = itemPool[n]
          if not it then
            it = {}
            itemPool[n] = it
          end
          it.f, it.stat, it.label = c, isStat, label
          it.off, it.h = c.__stOrig.off, h > 0 and h or c.__stOrig.h
          it.cat, it.pos, it.host, it.okey, it.hide = nil, nil, nil, nil, nil
          relayoutItems[n] = it
        end
      end
    end
  end
end

local function DoRelayout()
  if not Active() then
    pendingRelayout = false
    RestoreAll()
    return
  end
  if not MakeTall() then return end
  pendingRelayout = false
  touched = true
  wipe(lastFinal)

  -- Collect rows; recapture positions Blizzard has (re)set
  wipe(relayoutItems)
  CollectRows(container:GetChildren())
  local items = relayoutItems
  tsort(items, SortByOff)

  local cat
  for i = 1, #items do
    local it = items[i]
    if not it.stat then cat = it.label end
    it.cat = cat
  end
  if Remember(items) and opt and opt:IsShown() then RefreshOptions() end

  -- Blocks per category
  wipe(preBuf)
  local pre, blocks, cats = preBuf, {}, {}
  for i = 1, #items do
    local it = items[i]
    if not it.cat then
      pre[#pre + 1] = it
    elseif not it.stat then
      if not blocks[it.cat] then cats[#cats + 1] = it.cat end
      blocks[it.cat] = { header = it, stats = {} }
    elseif blocks[it.cat] then
      tinsert(blocks[it.cat].stats, it)
    end
  end

  -- Category order
  wipe(catPosBuf)
  for i = 1, #cats do catPosBuf[cats[i]] = i end
  sortCatRank = BuildRankMap(db.order.cats)
  sortCatPos = catPosBuf
  tsort(cats, SortCats)
  curCats = cats

  -- Groups: a category whose name is hidden merges its stats into the group above
  local groups = {}
  for i = 1, #cats do
    local c = cats[i]
    local b = blocks[c]
    if db.hidden[c .. "##name"] and #groups > 0 then
      local g = groups[#groups]
      for j = 1, #b.stats do g.stats[#g.stats + 1] = b.stats[j] end
      g.extra[#g.extra + 1] = b.header
    else
      local st = {}
      for j = 1, #b.stats do st[j] = b.stats[j] end
      groups[#groups + 1] = { cat = c, header = b.header, stats = st, extra = {} }
    end
  end

  -- Stat order within each group
  curStats = {}
  for gi = 1, #groups do
    local g = groups[gi]
    local order = db.order.stats[g.cat]
    -- merged stats are keyed with their own category, so equal labels stay apart
    for p = 1, #g.stats do
      local it = g.stats[p]
      it.pos = p; it.host = g.cat
      it.okey = (it.cat == g.cat) and it.label or Key(it.cat, it.label)
    end
    sortStatRank = BuildRankMap(order)
    tsort(g.stats, SortStats)
    local labels = {}
    for p = 1, #g.stats do labels[p] = g.stats[p].okey end
    curStats[g.cat] = labels
  end

  -- Visibility
  for gi = 1, #groups do
    local g = groups[gi]
    local allOff = #g.stats > 0
    for p = 1, #g.stats do
      local it = g.stats[p]
      it.hide = db.hidden[it.cat] or db.hidden[Key(it.cat, it.label)]
      if not it.hide then allOff = false end
    end
    g.header.hide = db.hidden[g.cat] or db.hidden[g.cat .. "##name"] or allOff
    for p = 1, #g.extra do g.extra[p].hide = true end
  end

  for i = 1, #pre do lastFinal[#lastFinal + 1] = pre[i] end
  for gi = 1, #groups do
    local g = groups[gi]
    lastFinal[#lastFinal + 1] = g.header
    for p = 1, #g.stats do lastFinal[#lastFinal + 1] = g.stats[p] end
    for p = 1, #g.extra do lastFinal[#lastFinal + 1] = g.extra[p] end
  end

  -- Total height of shown rows -> scroll range
  local total = 0
  for i = 1, #lastFinal do
    local it = lastFinal[i]
    if editMode or not it.hide then total = total + it.h end
  end
  maxScroll = max(0, total - (viewH or total))
  if scroll > maxScroll then scroll = maxScroll end
  if scroll < 0 then scroll = 0 end

  PositionRows()
end

-- An error must not leave the guard set: StatTrim would stop working until a /reload.
function Relayout()
  if relayouting or not (container and sb) then return end
  relayouting = true
  local ok, err = pcall(DoRelayout)
  relayouting = false
  if not ok then geterrorhandler()(err) end
end

local function StaleChildren(...)
  for i = 1, select("#", ...) do
    local c = select(i, ...)
    if not c:IsForbidden() and c:IsShown() then
      if not c.__stSeen then return true end
      if c.__stSet and not IsOurs(c) then return true end
    end
  end
  return false
end

-- Has Blizzard changed the panel since the last layout? New rows, or rows it moved back.
local function Stale()
  return StaleChildren(container:GetChildren())
end

local hookedSB
local function HookSB()
  if hookedSB == sb then return end
  hookedSB = sb
  -- Runs after Blizzard's own (secure) update; we only move/fade frames.
  if sb.Update then hooksecurefunc(sb, "Update", function() Relayout() end) end
  sb:HookScript("OnMouseWheel", function(_, delta)
    if not tall then return end
    local nextScroll = min(maxScroll, max(0, scroll - delta * WHEEL_STEP))
    if nextScroll == scroll then return end
    scroll = nextScroll
    if #lastFinal > 0 and not Stale() then
      relayouting = true
      local ok, err = pcall(PositionRows)
      relayouting = false
      if not ok then geterrorhandler()(err) end
    else
      Relayout()
    end
  end)
end

local warned
-- fromPoll: the 0.1 s poll while the character window is open; it only lays out again
-- when Blizzard changed the panel. Every other caller (clicks, settings) always does.
function Apply(fromPoll)
  if not (CharacterFrame and CharacterFrame:IsVisible()) then return end
  if container and not container:IsVisible() then
    if editBtn then editBtn:Hide() end
    return
  end
  if fromPoll then
    if InCombatLockdown() and not tall then
      if Active() then pendingRelayout = true end
      return
    end
    if container and container:IsVisible() and sb == container:GetParent() then
      if editBtn and not editBtn:IsShown() then editBtn:Show() end
      if not ((tall or Active()) and Stale()) then return end
    end
  end
  if not container then
    container = FindContainer()
  end
  if not (container and container:IsVisible()) then return end
  local parent = container:GetParent()
  if not (parent and parent.GetDataProvider) then
    if not warned then
      warned = true
      print(PREFIX .. " Unsupported stats panel layout.")
    end
    return
  end
  sb = parent
  UpdateEditButton()
  HookSB()
  Relayout()
end

---------------------------------------------------------------------------
-- List window: every known category and stat with a checkbox (BencepoUI, like the
-- settings of the other Bencepo addons; "Report a bug" sits in its footer)
---------------------------------------------------------------------------
local BUG_URL = "https://github.com/Bencepo/StatTrim/issues/new/choose"
local ACCENT = { 0.40, 0.80, 1, 1 }
local OPT_W, OPT_H = 340, 460
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CHECK_BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

-- A flat checkbox in the window's colours, with its label; the whole line is clickable.
local function GetCheck(i)
  local cb = opt.checks[i]
  if not cb then
    local T = opt.T
    cb = CreateFrame("Button", nil, opt.content, "BackdropTemplate")
    cb:SetSize(16, 16)
    cb:SetBackdrop(CHECK_BACKDROP)
    cb:SetBackdropColor(T.well[1], T.well[2], T.well[3], T.well[4] or 1)
    cb:SetBackdropBorderColor(T.line[1], T.line[2], T.line[3], 1)
    cb.mark = cb:CreateTexture(nil, "OVERLAY")
    cb.mark:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb.mark:SetPoint("CENTER", 1, 0)
    cb.mark:SetSize(20, 20)
    cb.mark:SetVertexColor(T.accent[1], T.accent[2], T.accent[3])
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    cb:SetHitRectInsets(0, -230, -3, -3)
    function cb:SetChecked(v) self.checked = v and true or false; self.mark:SetShown(self.checked) end
    function cb:GetChecked() return self.checked end
    cb:SetScript("OnClick", function(self)
      self:SetChecked(not self.checked)
      db.hidden[self.key] = (not self.checked) or nil
      Apply(); RefreshOptions()
    end)
    cb:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(T.accent[1], T.accent[2], T.accent[3], 1) end)
    cb:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(T.line[1], T.line[2], T.line[3], 1) end)
    opt.checks[i] = cb
  end
  cb:Show()
  return cb
end

local function PlaceCheck(cb, x, y, isCat)
  if cb.x ~= x or cb.y ~= y then
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", x, -y)
    cb.x, cb.y = x, y
  end
  if cb.isCat ~= isCat then
    cb.label:SetFontObject(isCat and "GameFontNormal" or "GameFontHighlightSmall")
    cb.isCat = isCat
  end
end

function RefreshOptions()
  opt.empty:SetShown(#db.known.cats == 0)
  local i, y = 0, 2
  for _, cat in ipairs(db.known.cats) do
    local catHidden = db.hidden[cat]
    i = i + 1
    local cb = GetCheck(i)
    PlaceCheck(cb, 2, y, true)
    cb.key = cat
    cb:SetChecked(not catHidden); cb:Enable(); cb:SetAlpha(1)
    cb.label:SetText(cat)
    y = y + 24
    for _, stat in ipairs(db.known.stats[cat] or EMPTY) do
      i = i + 1
      local scb = GetCheck(i)
      PlaceCheck(scb, 22, y, false)
      scb.key = Key(cat, stat)
      scb:SetChecked(not db.hidden[scb.key])
      scb.label:SetText(stat)
      -- a hidden category hides its stats too: their boxes are greyed out
      if catHidden then scb:Disable(); scb:SetAlpha(0.4) else scb:Enable(); scb:SetAlpha(1) end
      y = y + 21
    end
    y = y + 6
  end
  for j = i + 1, #opt.checks do opt.checks[j]:Hide() end
  opt.content:SetHeight(max(y, 10))
end

local function ResetHidden()
  wipe(db.hidden)
  Apply()
  if opt and opt:IsShown() then RefreshOptions() end
end

local function ResetOrder()
  db.order = { cats = nil, stats = {} }
  Apply()
end

local function BuildOptions()
  local UI = LibStub("BencepoUI-1.0")
  opt = UI:CreateWindow({
    name = "StatTrimOptions", title = "StatTrim", subtitle = "checked = visible",
    width = OPT_W, height = OPT_H, accent = ACCENT, db = accDB, posKey = "optPos", bugUrl = BUG_URL,
    hint = "drag to move",
  })
  local sf = CreateFrame("ScrollFrame", nil, opt, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 16, -44)
  sf:SetPoint("BOTTOMRIGHT", opt, "TOPRIGHT", -30, -(OPT_H - 40))
  opt.content = CreateFrame("Frame", nil, sf)
  opt.content:SetSize(OPT_W - 60, 10)
  sf:SetScrollChild(opt.content)
  opt.checks = {}

  opt.empty = opt.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  opt.empty:SetPoint("TOPLEFT", 4, -4); opt.empty:SetWidth(OPT_W - 70); opt.empty:SetJustifyH("LEFT")
  opt.empty:SetText("Nothing detected yet. Open the character window with the stats view once.")

  local y = -(OPT_H - 32)
  local showAll = opt:Button("Show all", 90, ResetHidden,
    "Every category and stat visible again.")
  showAll:SetPoint("TOPLEFT", 16, y)
  local rescan = opt:Button("Rescan list", 90, function()
    db.known = { cats = {}, stats = {} }; wipe(knownSets); container = nil; Apply(); RefreshOptions()
  end, "Forgets the list and reads the stats panel again, e.g. after the game added a stat.")
  rescan:SetPoint("LEFT", showAll, "RIGHT", 6, 0)
  local order = opt:Button("Default order", 110, ResetOrder,
    "Puts categories and stats back in the game's own order. What is hidden stays hidden.")
  order:SetPoint("LEFT", rescan, "RIGHT", 6, 0)
end

function ToggleOptions()
  if not db then return end
  if not opt then BuildOptions() end
  if opt:IsShown() then opt:Hide() else RefreshOptions(); opt:Show() end
end

-- Entry in the game's addon menu (the button next to the minimap): the list window.
function StatTrim_OnCompartmentClick()
  if db then ToggleOptions() end
end

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------
local function Say(...)
  print(PREFIX, ...)
end

local function DumpChildren(...)
  for i = 1, select("#", ...) do
    local c = select(i, ...)
    if not c:IsForbidden() and c:IsShown() then
      local isStat, label = RowInfo(c)
      if label then
        local pt, rel, rp, x, y = c:GetPoint(1)
        Say(isStat and "  W" or "H", label, "|", pt, rel and rel.GetDebugName and rel:GetDebugName() or tostring(rel), rp,
          Pub(x) and format("%.1f", x), Pub(y) and format("%.1f", y), "h=" .. format("%.1f", Pub(c:GetHeight()) or -1))
      end
    end
  end
end

local function Dump()
  if not (CharacterFrame and CharacterFrame:IsVisible()) then
    Say("Open the character window (stats view), then /stt dump."); return
  end
  container = FindContainer()
  if not container then Say("No stats panel found."); return end
  Say("Container:", container:GetDebugName(), container:GetObjectType(),
    "Parent:", container:GetParent() and container:GetParent():GetDebugName())
  Say("Tall mode:", tall and "yes" or "no", "view height:", viewH and format("%.0f", viewH) or "-",
    "scroll:", format("%.0f/%.0f", scroll, maxScroll))
  DumpChildren(container:GetChildren())
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(self, event, arg)
  if event == "ADDON_LOADED" and arg == ADDON then
    self:UnregisterEvent("ADDON_LOADED")
    StatTrimDB = StatTrimDB or {}
    accDB = StatTrimDB
    StatTrimCharDB = StatTrimCharDB or {}
    db = StatTrimCharDB
    -- One-time migration from account-wide StatTrimDB to per-character StatTrimCharDB.
    if not accDB.migrated and db.hidden == nil and (accDB.hidden or accDB.order or accDB.known) then
      if type(accDB.hidden) == "table" then db.hidden = CopyTable(accDB.hidden) end
      if type(accDB.known) == "table" then db.known = CopyTable(accDB.known) end
      if type(accDB.order) == "table" then db.order = CopyTable(accDB.order) end
      accDB.migrated = true
    end
    db.hidden = db.hidden or {}
    db.known = db.known or { cats = {}, stats = {} }
    db.known.cats = db.known.cats or {}
    db.known.stats = db.known.stats or {}
    db.order = db.order or { cats = nil, stats = {} }
    db.order.stats = db.order.stats or {}
    -- Remove leftover from v0.1
    local old = "Ohne Kategorie"
    if db.known.stats[old] then
      db.known.stats[old] = nil
      for i = #db.known.cats, 1, -1 do if db.known.cats[i] == old then tremove(db.known.cats, i) end end
    end
  elseif event == "PLAYER_REGEN_ENABLED" then
    if not db then return end
    -- Finish deferred restore or relayout once combat ends.
    if tall and not Active() then
      RestoreAll()
    elseif pendingRelayout then
      pendingRelayout = false
      if CharacterFrame and CharacterFrame:IsVisible() then Apply() end
    end
  elseif event == "PLAYER_LOGIN" then
    self:UnregisterEvent("PLAYER_LOGIN")
    if not CharacterFrame then
      print(PREFIX .. " CharacterFrame not found – addon inactive.")
      return
    end
    local driver = CreateFrame("Frame", nil, CharacterFrame)
    local acc = 0
    driver:SetScript("OnShow", function() acc = 0; Apply() end)
    driver:SetScript("OnHide", function()
      local wasEdit = editMode
      editMode = false
      if editBtn then editBtn:UnlockHighlight() end
      if wasEdit and db then
        if not Active() then
          RestoreAll()
        elseif container then
          HideChildrenControls(container:GetChildren())
        end
      end
    end)
    driver:SetScript("OnUpdate", function(_, dt)
      acc = acc + dt
      if acc >= 0.1 then acc = 0; Apply(true) end
    end)
  end
end)

SLASH_STATTRIM1 = "/stattrim"
SLASH_STATTRIM2 = "/stt"
SlashCmdList.STATTRIM = function(msg)
  if not db then return end
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "dump" then Dump()
  elseif msg == "reset" then ResetHidden()
  elseif msg == "list" then ToggleOptions()
  elseif msg == "order" then ResetOrder()
  else
    if not ToggleEditMode() then return end
    if not (CharacterFrame and CharacterFrame:IsVisible()) then
      print(PREFIX .. " Edit mode applies once the character window is open.")
    end
  end
end
