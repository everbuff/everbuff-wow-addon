-- Pane tests: the auction rows Market builds for Loot > Gold, Auction house (tests/panes/gold.lua tests that
-- breakdown's page), and the crafts Market records, listed in Character > Professions (tests/panes/character.lua).
return function(P)
  local check, M, ns = P.check, P.M, P.ns
  local Market = ns.Market

  -- the auction rows: newest first, each with its session id (Loot > Gold lists a period's), Posted with its hours
  do
    P.open("loot", "gold", 900, 580, "long")
    local rows, sum = Market.buildAuctions()
    local sorted, sess, kinds = true, true, {}
    for i, r in ipairs(rows) do
      if i > 1 and (r.t or 0) > (rows[i - 1].t or 0) then sorted = false end
      if r.s == nil then sess = false end
      kinds[r.what] = true
    end
    check("Auctions: the rows are newest first and carry their session id", #rows >= 2 and sorted and sess, #rows)
    check("Auctions: posted, sold and bought rows are built", kinds.Posted and kinds.Sold and kinds.Bought)
    check("Auctions: the sums add up the sold and bought rows", sum.sold >= 1 and sum.net > 0 and sum.bought >= 1)
    local loot
    for _, tab in ipairs(P.T.tabs) do if tab.name == "Loot" then loot = tab end end
    check("Auctions: Loot has no Auctions pane of its own any more (it is Gold's Auction house)", loot and loot.paneByKey.auctions == nil and loot.paneByKey.gold ~= nil)
  end

  local char
  for _, tab in ipairs(P.T.tabs) do if tab.name == "Character" then char = tab end end
  P.open("character", "professions", 900, 580, "normal")
  check("Market: Character has no Crafting pane of its own any more (it is part of Professions)", char and char.paneByKey and char.paneByKey.crafting == nil and char.paneByKey.professions ~= nil)
  check("Market: no error while sizing or rendering", (function() for _, e in ipairs(M.errors) do if tostring(e):find("Market") then return false, e end end return true end)())
end
