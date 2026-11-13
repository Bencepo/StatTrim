-- StatTrim: hide and reorder categories and stats in the character window (WoW: Forever).
-- Edit mode (gear icon above the stats panel): checkboxes and arrows on every row.
-- Normal mode: unchecked rows are removed, the rest move up.

local ADDON = ...
local db, container, opt, editBtn
local editMode = false
local RefreshOptions

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

-- isStat, label of a row (nil if no readable text)
local function RowInfo(c)
  local n, label, lx = 0, nil, nil
  for _, r in ipairs({ c:GetRegions() }) do
    if r:GetObjectType() == "FontString" and r:IsShown() then
      n = n + 1
      local ok, t = pcall(Clean, r:GetText())
      if ok and t then
        local x = r:GetLeft() or 0
        if not lx or x < lx then label, lx = t, x end
      end
    end
  end
  if not label then return nil end
  return (c.Value ~= nil) or n >= 2, label
end

local function Walk(f, depth, cb)
  if f:IsForbidden() then return end
  cb(f)
  if depth <= 0 then return end
  for _, c in ipairs({ f:GetChildren() }) do Walk(c, depth - 1, cb) end
end

local function FindContainer()
  local best, bestN = nil, 0
  Walk(CharacterFrame, 10, function(f)
    local n = 0
    for _, c in ipairs({ f:GetChildren() }) do
      if not c:IsForbidden() and c:IsVisible() and RowInfo(c) then n = n + 1 end
    end
    if n > bestN then best, bestN = f, n end
  end)
  if bestN >= 5 then return best end
end

local function Key(cat, stat) return stat and (cat .. "::" .. stat) or cat end

---------------------------------------------------------------------------
-- Positions (legacy path): remember original, restack, restore
---------------------------------------------------------------------------
local function Capture(c)
  local ct, cl, cr = container:GetTop(), container:GetLeft(), container:GetRight()
  local t, l, r = c:GetTop(), c:GetLeft(), c:GetRight()
  if not (ct and cl and cr and t and l and r) then return false end
  local pts = {}
  for i = 1, c:GetNumPoints() do pts[i] = { c:GetPoint(i) } end
  c.__stOrig = { pts = pts, off = ct - t, l = l - cl, r = r - cr, h = c:GetHeight() }
  return true
end

local function IsOurs(c)
  local s = c.__stSet
  if not s or c:GetNumPoints() ~= 2 then return false end
  local pt, rel, _, x, y = c:GetPoint(1)
  return pt == "TOPLEFT" and rel == container
    and math.abs((x or 0) - s.x) < 0.01 and math.abs((y or 0) - s.y) < 0.01
end

local function Restore(c)
  if not c.__stSet then return end
  c:ClearAllPoints()
  for _, p in ipairs(c.__stOrig.pts) do c:SetPoint(unpack(p)) end
  c.__stSet = nil
end

local function Place(c, off)
  local o = c.__stOrig
  c:ClearAllPoints()
  c:SetPoint("TOPLEFT", container, "TOPLEFT", o.l, -off)
  c:SetPoint("TOPRIGHT", container, "TOPRIGHT", o.r, -off)
  c.__stSet = { x = o.l, y = -off }
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
local function Remember(items)
  local changed, k = false, db.known
  for _, it in ipairs(items) do
    if it.cat then
      if not k.stats[it.cat] then
        k.stats[it.cat] = {}; tinsert(k.cats, it.cat); changed = true
      end
      if it.stat then
        local found = false
        for _, s in ipairs(k.stats[it.cat]) do if s == it.label then found = true break end end
        if not found then tinsert(k.stats[it.cat], it.label); changed = true end
      end
    end
  end
  return changed
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
    editBtn:SetScript("OnClick", function()
      editMode = not editMode
      Apply()
    end)
    editBtn:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText("StatTrim")
      GameTooltip:AddLine(editMode and "Finish editing" or "Show/hide and reorder stats", 1, 1, 1)
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
local sb, sbOrig, tall, viewH
local scroll, maxScroll = 0, 0
local relayouting = false
local curCats, curStats = {}, {} -- current order (for arrows)
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

local function MakeTall()
  if tall then return true end
  if InCombatLockdown() then return false end
  local parent = sb:GetParent()
  local l, t, pl, pt = sb:GetLeft(), sb:GetTop(), parent:GetLeft(), parent:GetTop()
  if not (l and t and pl and pt) then return false end
  local pts = {}
  for i = 1, sb:GetNumPoints() do pts[i] = { sb:GetPoint(i) } end
  viewH = sb:GetHeight()
  sbOrig = { pts = pts, w = sb:GetWidth(), hit = { sb:GetHitRectInsets() } }

  proxy = proxy or CreateFrame("Frame", nil, parent)
  proxy:ClearAllPoints()
  for _, p in ipairs(pts) do proxy:SetPoint(unpack(p)) end
  if #pts < 2 then proxy:SetSize(sbOrig.w, viewH) end

  wipe(moved)
  for _, c in ipairs({ parent:GetChildren() }) do
    if c ~= sb and c ~= proxy and c ~= editBtn and not c:IsForbidden() then Reanchor(c, false) end
  end
  for _, r in ipairs({ sb:GetRegions() }) do Reanchor(r, true) end

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
  for _, p in ipairs(sbOrig.pts) do sb:SetPoint(unpack(p)) end
  sb:SetHeight(viewH)
  sb:SetHitRectInsets(unpack(sbOrig.hit))
  for i = #moved, 1, -1 do
    local m = moved[i]
    m.obj:ClearAllPoints()
    for _, p in ipairs(m.pts) do m.obj:SetPoint(unpack(p)) end
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

local function SetTip(f, text)
  f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(text, 1, 1, 1); GameTooltip:Show()
  end)
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

local function RestoreText(c)
  if not c.__stTextEdited then return end
  c.__stTextEdited = nil
  for _, r in ipairs({ c:GetRegions() }) do
    if r:GetObjectType() == "FontString" and r.__stEdit then
      if r.__stPts then
        r:ClearAllPoints()
        for _, p in ipairs(r.__stPts) do r:SetPoint(unpack(p)) end
      end
      if r.__stAlpha then r:SetAlpha(r.__stAlpha) end
      r.__stEdit, r.__stPts, r.__stAlpha = nil, nil, nil
    end
  end
end

local function EditText(c, isStat)
  if c.__stTextEdited == (isStat and "stat" or "head") then return end
  RestoreText(c)
  if not isStat then c.__stTextEdited = "head"; return end
  local fss, label, lx = {}, nil, nil
  for _, r in ipairs({ c:GetRegions() }) do
    if r:GetObjectType() == "FontString" and r:IsShown() then
      fss[#fss + 1] = r
      local x = r:GetLeft()
      if x and (not lx or x < lx) then label, lx = r, x end
    end
  end
  for _, r in ipairs(fss) do
    r.__stEdit = true
    if r == label then
      local pts = {}
      for i = 1, r:GetNumPoints() do pts[i] = { r:GetPoint(i) } end
      r.__stPts = pts
      r:ClearAllPoints()
      for _, p in ipairs(pts) do
        r:SetPoint(p[1], p[2], p[3], (p[4] or 0) + LABEL_SHIFT, p[5] or 0)
      end
    else
      r.__stAlpha = r:GetAlpha()
      r:SetAlpha(0)
    end
  end
  c.__stTextEdited = "stat"
end

local function HideControls(c)
  local t = c.__stCtl
  if t then t.cb:Hide(); t.name:Hide(); t.up:Hide(); t.down:Hide() end
  HideRowCB(c)
  RestoreText(c)
end

local function Rank(list, v, fallback)
  if list then for i, x in ipairs(list) do if x == v then return i end end end
  return 1000 + fallback
end

local touched = false -- rows were moved, faded or got controls since the last RestoreAll

local function RestoreAll()
  if not (touched or tall) then return end
  touched = false
  for _, c in ipairs({ container:GetChildren() }) do
    if not c:IsForbidden() then
      Restore(c)
      HideControls(c)
      SetVisual(c, "show")
    end
  end
  RestoreSB()
end

local function DoRelayout()
  if not Active() then
    RestoreAll()
    return
  end
  if not MakeTall() then return end
  touched = true

  -- Collect rows; recapture positions Blizzard has (re)set
  local items = {}
  for _, c in ipairs({ container:GetChildren() }) do
    if not c:IsForbidden() and c:IsShown() then
      c.__stSeen = true
      local isStat, label = RowInfo(c)
      if label then
        if c.__stSet and not IsOurs(c) then c.__stSet = nil; c.__stOrig = nil end
        if c.__stOrig or Capture(c) then
          items[#items + 1] = { f = c, stat = isStat, label = label, off = c.__stOrig.off, h = c.__stOrig.h }
        end
      end
    end
  end
  table.sort(items, function(a, b) return a.off < b.off end)

  local cat
  for _, it in ipairs(items) do
    if not it.stat then cat = it.label end
    it.cat = cat
  end
  if Remember(items) and opt and opt:IsShown() then RefreshOptions() end

  -- Blocks per category
  local pre, blocks, cats = {}, {}, {}
  for _, it in ipairs(items) do
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
  local catPos = {}
  for i, c in ipairs(cats) do catPos[c] = i end
  table.sort(cats, function(a, b)
    local ra, rb = Rank(db.order.cats, a, catPos[a]), Rank(db.order.cats, b, catPos[b])
    if ra ~= rb then return ra < rb end
    return catPos[a] < catPos[b]
  end)
  curCats = cats

  -- Groups: a category whose name is hidden merges its stats into the group above
  local groups = {}
  for _, c in ipairs(cats) do
    local b = blocks[c]
    if db.hidden[c .. "##name"] and #groups > 0 then
      local g = groups[#groups]
      for _, it in ipairs(b.stats) do g.stats[#g.stats + 1] = it end
      g.extra[#g.extra + 1] = b.header
    else
      local st = {}
      for i, it in ipairs(b.stats) do st[i] = it end
      groups[#groups + 1] = { cat = c, header = b.header, stats = st, extra = {} }
    end
  end

  -- Stat order within each group
  curStats = {}
  for _, g in ipairs(groups) do
    local order = db.order.stats[g.cat]
    for p, it in ipairs(g.stats) do it.pos = p; it.host = g.cat end
    table.sort(g.stats, function(a, b)
      local ra, rb = Rank(order, a.label, a.pos), Rank(order, b.label, b.pos)
      if ra ~= rb then return ra < rb end
      return a.pos < b.pos
    end)
    local labels = {}
    for i, it in ipairs(g.stats) do labels[i] = it.label end
    curStats[g.cat] = labels
  end

  -- Visibility
  for _, g in ipairs(groups) do
    local allOff = #g.stats > 0
    for _, it in ipairs(g.stats) do
      it.hide = db.hidden[it.cat] or db.hidden[Key(it.cat, it.label)]
      if not it.hide then allOff = false end
    end
    g.header.hide = db.hidden[g.cat] or db.hidden[g.cat .. "##name"] or allOff
    for _, h in ipairs(g.extra) do h.hide = true end
  end

  local final = {}
  for _, it in ipairs(pre) do final[#final + 1] = it end
  for _, g in ipairs(groups) do
    final[#final + 1] = g.header
    for _, it in ipairs(g.stats) do final[#final + 1] = it end
    for _, h in ipairs(g.extra) do final[#final + 1] = h end
  end

  -- Total height of shown rows -> scroll range
  local total = 0
  for _, it in ipairs(final) do
    if editMode or not it.hide then total = total + it.h end
  end
  maxScroll = math.max(0, total - (viewH or total))
  if scroll > maxScroll then scroll = maxScroll end
  if scroll < 0 then scroll = 0 end

  -- Place rows
  local cursor = 0
  for _, it in ipairs(final) do
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
        t.up.cat, t.up.label, t.down.cat, t.down.label = mc, it.label, mc, it.label
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

-- An error must not leave the guard set: StatTrim would stop working until a /reload.
function Relayout()
  if relayouting or not (container and sb) then return end
  relayouting = true
  local ok, err = pcall(DoRelayout)
  relayouting = false
  if not ok then geterrorhandler()(err) end
end

-- Has Blizzard changed the panel since the last layout? New rows, or rows it moved back.
local function Stale()
  for _, c in ipairs({ container:GetChildren() }) do
    if not c:IsForbidden() and c:IsShown() then
      if not c.__stSeen then return true end
      if c.__stSet and not IsOurs(c) then return true end
    end
  end
  return false
end

local hookedSB
local function HookSB()
  if hookedSB == sb then return end
  hookedSB = sb
  -- Runs after Blizzard's own (secure) update; we only move/fade frames.
  if sb.Update then hooksecurefunc(sb, "Update", function() Relayout() end) end
  sb:HookScript("OnMouseWheel", function(_, delta)
    if not tall then return end
    scroll = math.min(maxScroll, math.max(0, scroll - delta * WHEEL_STEP))
    Relayout()
  end)
end

local warned
-- fromPoll: the 0.1 s poll while the character window is open; it only lays out again
-- when Blizzard changed the panel. Every other caller (clicks, settings) always does.
function Apply(fromPoll)
  if not (CharacterFrame and CharacterFrame:IsVisible()) then return end
  if fromPoll and container and container:IsVisible() and sb == container:GetParent() then
    if not ((tall or Active()) and Stale()) then return end
  end
  if not (container and container:IsVisible()) then container = FindContainer() end
  if not container then return end
  local parent = container:GetParent()
  if not (parent and parent.GetDataProvider) then
    if not warned then
      warned = true
      print("|cff66ccffStatTrim|r Unsupported stats panel layout.")
    end
    return
  end
  sb = parent
  UpdateEditButton()
  HookSB()
  Relayout()
end

---------------------------------------------------------------------------
-- List window (/stt list)
---------------------------------------------------------------------------
local function GetCheck(i)
  local cb = opt.checks[i]
  if not cb then
    cb = CreateFrame("CheckButton", nil, opt.content, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb:SetScript("OnClick", function(self)
      db.hidden[self.key] = (not self:GetChecked()) or nil
      Apply(); RefreshOptions()
    end)
    opt.checks[i] = cb
  end
  cb:Show()
  return cb
end

function RefreshOptions()
  for _, cb in ipairs(opt.checks) do cb:Hide() end
  opt.empty:SetShown(#db.known.cats == 0)
  local i, y = 0, 0
  for _, cat in ipairs(db.known.cats) do
    i = i + 1
    local cb = GetCheck(i)
    cb:ClearAllPoints(); cb:SetPoint("TOPLEFT", 0, -y)
    cb.key = cat
    cb:SetChecked(not db.hidden[cat]); cb:Enable()
    cb.label:SetFontObject("GameFontNormal"); cb.label:SetText(cat)
    y = y + 24
    for _, stat in ipairs(db.known.stats[cat] or {}) do
      i = i + 1
      local scb = GetCheck(i)
      scb:ClearAllPoints(); scb:SetPoint("TOPLEFT", 20, -y)
      scb.key = Key(cat, stat)
      scb:SetChecked(not db.hidden[scb.key])
      scb.label:SetFontObject("GameFontHighlightSmall"); scb.label:SetText(stat)
      if db.hidden[cat] then scb:Disable(); scb.label:SetTextColor(0.5, 0.5, 0.5)
      else scb:Enable(); scb.label:SetTextColor(1, 1, 1) end
      y = y + 22
    end
    y = y + 6
  end
  opt.content:SetHeight(math.max(y, 10))
end

local function BuildOptions()
  opt = CreateFrame("Frame", "StatTrimOptions", UIParent, "BasicFrameTemplateWithInset")
  opt:SetSize(300, 480); opt:SetPoint("CENTER"); opt:SetFrameStrata("DIALOG")
  opt:SetMovable(true); opt:EnableMouse(true); opt:SetClampedToScreen(true)
  opt:RegisterForDrag("LeftButton")
  opt:SetScript("OnDragStart", opt.StartMoving)
  opt:SetScript("OnDragStop", opt.StopMovingOrSizing)
  tinsert(UISpecialFrames, "StatTrimOptions")

  local title = opt:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", 0, -5); title:SetText("StatTrim – checked = visible")

  local sf = CreateFrame("ScrollFrame", nil, opt, "UIPanelScrollFrameTemplate")
  sf:SetPoint("TOPLEFT", 12, -32); sf:SetPoint("BOTTOMRIGHT", -32, 42)
  opt.content = CreateFrame("Frame", nil, sf); opt.content:SetSize(240, 10)
  sf:SetScrollChild(opt.content)
  opt.checks = {}

  opt.empty = opt.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  opt.empty:SetPoint("TOPLEFT", 4, -4); opt.empty:SetWidth(230); opt.empty:SetJustifyH("LEFT")
  opt.empty:SetText("Nothing detected yet. Open the character window with the stats view once.")

  local reset = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
  reset:SetSize(120, 22); reset:SetPoint("BOTTOMLEFT", 12, 12); reset:SetText("Show all")
  reset:SetScript("OnClick", function() wipe(db.hidden); Apply(); RefreshOptions() end)

  local forget = CreateFrame("Button", nil, opt, "UIPanelButtonTemplate")
  forget:SetSize(120, 22); forget:SetPoint("BOTTOMRIGHT", -12, 12); forget:SetText("Rescan list")
  forget:SetScript("OnClick", function()
    db.known = { cats = {}, stats = {} }; container = nil; Apply(); RefreshOptions()
  end)
end

local function ToggleOptions()
  if not opt then BuildOptions() end
  if opt:IsShown() then opt:Hide() else RefreshOptions(); opt:Show() end
end

---------------------------------------------------------------------------
-- Debug
---------------------------------------------------------------------------
local function Dump()
  local p = function(...) print("|cff66ccffStatTrim|r", ...) end
  if not (CharacterFrame and CharacterFrame:IsVisible()) then
    p("Open the character window (stats view), then /stt dump."); return
  end
  container = FindContainer()
  if not container then p("No stats panel found."); return end
  p("Container:", container:GetDebugName(), container:GetObjectType(),
    "Parent:", container:GetParent() and container:GetParent():GetDebugName())
  p("Tall mode:", tall and "yes" or "no", "view height:", viewH and string.format("%.0f", viewH) or "-",
    "scroll:", string.format("%.0f/%.0f", scroll, maxScroll))
  for _, c in ipairs({ container:GetChildren() }) do
    if c:IsShown() then
      local isStat, label = RowInfo(c)
      if label then
        local pt, rel, rp, x, y = c:GetPoint(1)
        p(isStat and "  W" or "H", label, "|", pt, rel and rel.GetDebugName and rel:GetDebugName() or tostring(rel), rp,
          x and string.format("%.1f", x), y and string.format("%.1f", y), "h=" .. string.format("%.1f", c:GetHeight()))
      end
    end
  end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg)
  if event == "ADDON_LOADED" and arg == ADDON then
    StatTrimDB = StatTrimDB or {}
    db = StatTrimDB
    db.hidden = db.hidden or {}
    db.known = db.known or { cats = {}, stats = {} }
    db.order = db.order or { cats = nil, stats = {} }
    db.order.stats = db.order.stats or {}
    -- Remove leftover from v0.1
    local old = "Ohne Kategorie"
    if db.known.stats[old] then
      db.known.stats[old] = nil
      for i = #db.known.cats, 1, -1 do if db.known.cats[i] == old then tremove(db.known.cats, i) end end
    end
  elseif event == "PLAYER_LOGIN" then
    if not CharacterFrame then
      print("|cff66ccffStatTrim|r CharacterFrame not found – addon inactive.")
      return
    end
    local driver = CreateFrame("Frame", nil, CharacterFrame)
    local acc = 0
    driver:SetScript("OnShow", function() acc = 0; Apply() end)
    driver:SetScript("OnHide", function() editMode = false end)
    driver:SetScript("OnUpdate", function(_, dt)
      acc = acc + dt
      if acc >= 0.1 then acc = 0; Apply(true) end
    end)
  end
end)

SLASH_STATTRIM1 = "/stattrim"
SLASH_STATTRIM2 = "/stt"
SlashCmdList.STATTRIM = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  if msg == "dump" then Dump()
  elseif msg == "reset" then
    wipe(db.hidden); Apply(); if opt and opt:IsShown() then RefreshOptions() end
  elseif msg == "list" then ToggleOptions()
  elseif msg == "order" then
    db.order = { cats = nil, stats = {} }; Apply()
  else
    editMode = not editMode; Apply()
    if not (CharacterFrame and CharacterFrame:IsVisible()) then
      print("|cff66ccffStatTrim|r Edit mode applies once the character window is open.")
    end
  end
end
