-- HEAJ Alteration : les gestes d'alteration du cours, reunis dans une seule fenetre.
-- Cours Environnements sonores (HEAJ - Transmedia M1) - Nicolas Debois
-- Version 1.0
--
-- Utilisation : selectionnez un ou plusieurs items audio, puis cliquez sur un bouton.
-- Chaque clic peut etre annule avec Ctrl+Z (Cmd+Z sur Mac).

local r = reaper
local W, H = 460, 404
local status = "Sélectionnez un item audio, puis cliquez sur un bouton."

---------------------------------------------------------------- outils
local function selected_takes()
  local list = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local item = r.GetSelectedMediaItem(0, i)
    local take = r.GetActiveTake(item)
    if take and not r.TakeIsMIDI(take) then
      list[#list + 1] = { item = item, take = take }
    end
  end
  return list
end

local function act(name, fn)
  local list = selected_takes()
  if #list == 0 then
    status = "Aucun item audio sélectionné."
    return
  end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  fn(list)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("HEAJ Altération : " .. name, -1)
  status = name .. " (" .. #list .. " item" .. (#list > 1 and "s" or "") .. ")"
end

local function shift_pitch(st)
  act((st > 0 and "+" or "") .. st .. " demi-ton" .. (math.abs(st) > 1 and "s" or ""), function(list)
    for _, t in ipairs(list) do
      local p = r.GetMediaItemTakeInfo_Value(t.take, "D_PITCH")
      r.SetMediaItemTakeInfo_Value(t.take, "D_PITCH", p + st)
    end
  end)
end

local function set_rate(factor, label)
  act("Vitesse " .. label, function(list)
    for _, t in ipairs(list) do
      local rate = r.GetMediaItemTakeInfo_Value(t.take, "D_PLAYRATE")
      local len = r.GetMediaItemInfo_Value(t.item, "D_LENGTH")
      local new = math.max(0.05, math.min(20, rate * factor))
      r.SetMediaItemTakeInfo_Value(t.take, "D_PLAYRATE", new)
      r.SetMediaItemInfo_Value(t.item, "D_LENGTH", len * rate / new)
    end
  end)
end

local function set_preserve(on)
  act(on and "Hauteur préservée" or "La hauteur suit la vitesse", function(list)
    for _, t in ipairs(list) do
      r.SetMediaItemTakeInfo_Value(t.take, "B_PPITCH", on and 1 or 0)
    end
  end)
end

local function reverse()
  act("Inversion", function()
    r.Main_OnCommand(41051, 0) -- Item properties: Toggle take reverse
  end)
end

local function chop_shuffle(n)
  act("Découpé en " .. n .. " et mélangé", function(list)
    for _, t in ipairs(list) do
      local item = t.item
      local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      local slice = len / n
      local pieces, cur = { item }, item
      for k = 1, n - 1 do
        cur = r.SplitMediaItem(cur, pos + k * slice)
        if not cur then break end
        pieces[#pieces + 1] = cur
      end
      local order = {}
      for k = 1, #pieces do order[k] = k end
      for k = #order, 2, -1 do
        local j = math.random(k)
        order[k], order[j] = order[j], order[k]
      end
      for k, idx in ipairs(order) do
        local it = pieces[idx]
        r.SetMediaItemInfo_Value(it, "D_POSITION", pos + (k - 1) * slice)
        r.SetMediaItemInfo_Value(it, "D_LENGTH", slice)
        r.SetMediaItemInfo_Value(it, "D_FADEINLEN", 0.005)
        r.SetMediaItemInfo_Value(it, "D_FADEOUTLEN", 0.005)
        r.SetMediaItemSelected(it, true)
      end
    end
  end)
end

local function reset()
  act("Remis à zéro", function(list)
    for _, t in ipairs(list) do
      local rate = r.GetMediaItemTakeInfo_Value(t.take, "D_PLAYRATE")
      local len = r.GetMediaItemInfo_Value(t.item, "D_LENGTH")
      r.SetMediaItemTakeInfo_Value(t.take, "D_PITCH", 0)
      r.SetMediaItemTakeInfo_Value(t.take, "D_PLAYRATE", 1)
      r.SetMediaItemInfo_Value(t.item, "D_LENGTH", len * rate)
    end
  end)
end

local function freeze()
  act("Figé en audio (nouvelle prise)", function()
    r.Main_OnCommand(40601, 0) -- Item: Render items to new take
  end)
end

---------------------------------------------------------------- interface
local rows = {
  { title = "Hauteur", buttons = {
    { "-12", function() shift_pitch(-12) end }, { "-1", function() shift_pitch(-1) end },
    { "+1", function() shift_pitch(1) end }, { "+12", function() shift_pitch(12) end } } },
  { title = "Vitesse", buttons = {
    { "÷ 2", function() set_rate(0.5, "÷ 2") end }, { "× 0,8", function() set_rate(0.8, "× 0,8") end },
    { "× 1,25", function() set_rate(1.25, "× 1,25") end }, { "× 2", function() set_rate(2, "× 2") end } } },
  { title = "La hauteur suit la vitesse ?", buttons = {
    { "Oui (bande)", function() set_preserve(false) end }, { "Non (préservée)", function() set_preserve(true) end } } },
  { title = "Transformer", buttons = {
    { "Inverser", reverse }, { "Découper + mélanger", function() chop_shuffle(8) end } } },
  { title = "Terminer", buttons = {
    { "Remettre à zéro", reset }, { "Figer en audio", freeze } } },
}

local RED = { 0.894, 0.071, 0.153 }
local mouse_was_down = false
local hover_btn = nil

local function rgb(c, a) gfx.set(c[1], c[2], c[3], a or 1) end

local function draw()
  rgb({ 0.075, 0.08, 0.1 }); gfx.rect(0, 0, gfx.w, gfx.h, 1)
  gfx.setfont(1, "Arial", 20, string.byte("b"))
  rgb(RED); gfx.x, gfx.y = 16, 12; gfx.drawstr("HEAJ")
  rgb({ 1, 1, 1 }); gfx.drawstr("  Altération")
  local y = 48
  local clicked = nil
  local mx, my = gfx.mouse_x, gfx.mouse_y
  local down = gfx.mouse_cap & 1 == 1
  for _, row in ipairs(rows) do
    gfx.setfont(2, "Arial", 14, string.byte("b"))
    rgb({ 0.62, 0.65, 0.7 }); gfx.x, gfx.y = 16, y; gfx.drawstr(string.upper(row.title))
    y = y + 20
    local n = #row.buttons
    local gap = 8
    local bw = (gfx.w - 32 - gap * (n - 1)) / n
    for i, b in ipairs(row.buttons) do
      local bx = 16 + (i - 1) * (bw + gap)
      local over = mx >= bx and mx <= bx + bw and my >= y and my <= y + 32
      if over and down then rgb(RED)
      elseif over then rgb({ 0.24, 0.25, 0.3 })
      else rgb({ 0.16, 0.17, 0.2 }) end
      gfx.rect(bx, y, bw, 32, 1)
      gfx.setfont(3, "Arial", 15)
      rgb({ 1, 1, 1 })
      local tw, th = gfx.measurestr(b[1])
      gfx.x, gfx.y = bx + (bw - tw) / 2, y + (32 - th) / 2
      gfx.drawstr(b[1])
      if over and mouse_was_down and not down then clicked = b[2] end
    end
    y = y + 42
  end
  gfx.setfont(4, "Arial", 13)
  rgb({ 0.62, 0.65, 0.7 }); gfx.x, gfx.y = 16, gfx.h - 24
  gfx.drawstr(status)
  mouse_was_down = down
  gfx.update()
  return clicked
end

local function loop()
  local ch = gfx.getchar()
  if ch < 0 or ch == 27 then gfx.quit() return end
  local fn = draw()
  if fn then fn() end
  r.defer(loop)
end

math.randomseed(os.time())
gfx.init("HEAJ Altération", W, H)
loop()
