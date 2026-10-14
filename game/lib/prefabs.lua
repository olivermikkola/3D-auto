-- Low-poly models baked from primitives. Each is one mesh, one draw call.
local P = {}

P.car_colors = {
  {0.80, 0.12, 0.10}, {0.10, 0.30, 0.75}, {0.95, 0.80, 0.15}, {0.15, 0.55, 0.25},
  {0.90, 0.90, 0.92}, {0.12, 0.12, 0.14}, {0.55, 0.20, 0.60}, {0.95, 0.45, 0.10},
}

-- Car collider is 2.0 x 1.4 x 4.4 centered on the origin; +Z is the front.
function P.car_parts(c)
  local glass, tire, rim = {0.15, 0.2, 0.28}, {0.08, 0.08, 0.08}, {0.6, 0.6, 0.6}
  local parts = {
    {mesh = "cube", pos = {0, -0.2, 0}, size = {2.0, 0.6, 4.4}, color = c},
    {mesh = "cube", pos = {0, 0.4, -0.3}, size = {1.8, 0.6, 2.2}, color = {c[1] * 0.9, c[2] * 0.9, c[3] * 0.9}},
    {mesh = "cube", pos = {0, 0.42, -0.3}, size = {1.84, 0.42, 1.9}, color = glass},
    {mesh = "cube", pos = {0, 0.42, 0.82}, size = {1.6, 0.4, 0.06}, color = glass},
    {mesh = "cube", pos = {0, 0.42, -1.42}, size = {1.6, 0.4, 0.06}, color = glass},
    {mesh = "cube", pos = {0.6, -0.05, 2.21}, size = {0.45, 0.18, 0.04}, color = {1, 0.95, 0.7}, emissive = 1},
    {mesh = "cube", pos = {-0.6, -0.05, 2.21}, size = {0.45, 0.18, 0.04}, color = {1, 0.95, 0.7}, emissive = 1},
    {mesh = "cube", pos = {0.65, -0.05, -2.21}, size = {0.4, 0.15, 0.04}, color = {0.9, 0.05, 0.05}, emissive = 1},
    {mesh = "cube", pos = {-0.65, -0.05, -2.21}, size = {0.4, 0.15, 0.04}, color = {0.9, 0.05, 0.05}, emissive = 1},
    {mesh = "cube", pos = {0, -0.32, 2.22}, size = {1.9, 0.18, 0.08}, color = {0.2, 0.2, 0.2}},
  }
  for _, w in ipairs{{0.92, 1.4}, {-0.92, 1.4}, {0.92, -1.4}, {-0.92, -1.4}} do
    parts[#parts + 1] = {mesh = "cylinder", axis = "x", pos = {w[1], -0.3, w[2]}, size = {0.32, 0.8, 0.8}, color = tire}
    parts[#parts + 1] = {mesh = "cylinder", axis = "x", pos = {w[1] * 1.02, -0.3, w[2]}, size = {0.3, 0.4, 0.4}, color = rim}
  end
  return parts
end

-- Person collider is 0.7 x 1.8 x 0.7.
function P.person(name, shirt, pants, skin, hair)
  engine.mesh(name, {
    {mesh = "cube", pos = {0.14, -0.5, 0}, size = {0.22, 0.8, 0.28}, color = pants},
    {mesh = "cube", pos = {-0.14, -0.5, 0}, size = {0.22, 0.8, 0.28}, color = pants},
    {mesh = "cube", pos = {0, 0.25, 0}, size = {0.62, 0.72, 0.36}, color = shirt},
    {mesh = "cube", pos = {0.4, 0.2, 0}, size = {0.16, 0.65, 0.2}, color = skin},
    {mesh = "cube", pos = {-0.4, 0.2, 0}, size = {0.16, 0.65, 0.2}, color = skin},
    {mesh = "sphere", pos = {0, 0.78, 0}, size = 0.36, color = skin},
    {mesh = "cube", pos = {0, 0.88, -0.03}, size = {0.38, 0.12, 0.38}, color = hair},
  })
end

function P.build()
  for i, c in ipairs(P.car_colors) do engine.mesh("car" .. i, P.car_parts(c)) end

  P.person("person", {0.85, 0.85, 0.82}, {0.2, 0.25, 0.45}, {0.85, 0.7, 0.55}, {0.15, 0.1, 0.05})

  engine.mesh("tree", {
    {mesh = "cylinder", pos = {0, 1.0, 0}, size = {0.35, 2.0, 0.35}, color = {0.4, 0.27, 0.15}},
    {mesh = "sphere", pos = {0, 2.8, 0}, size = {2.4, 2.2, 2.4}, color = {0.22, 0.5, 0.2}},
    {mesh = "sphere", pos = {0.5, 3.6, 0.2}, size = {1.5, 1.4, 1.5}, color = {0.26, 0.56, 0.22}},
  })

  engine.mesh("lamp", {
    {mesh = "cylinder", pos = {0, 2.5, 0}, size = {0.15, 5.0, 0.15}, color = {0.25, 0.25, 0.27}},
    {mesh = "cube", pos = {0, 5.0, 0.6}, size = {0.15, 0.12, 1.3}, color = {0.25, 0.25, 0.27}},
    {mesh = "cube", pos = {0, 4.92, 1.15}, size = {0.35, 0.1, 0.5}, color = {1.0, 0.95, 0.75}, emissive = 1},
  })

  engine.mesh("crate", {
    {mesh = "cube", size = 1, color = {0.6, 0.42, 0.22}},
    {mesh = "cube", size = {1.02, 0.12, 1.02}, pos = {0, 0.38, 0}, color = {0.45, 0.3, 0.15}},
    {mesh = "cube", size = {1.02, 0.12, 1.02}, pos = {0, -0.38, 0}, color = {0.45, 0.3, 0.15}},
  })

  -- Hand-made OBJ asset, to show external models work too.
  engine.load_obj("cone", "assets/cone.obj")

  -- Military and border props
  engine.mesh("guardhouse", {
    {mesh = "cube", pos = {0, 0.1, 0}, size = {3.2, 0.2, 3.8}, color = {0.25, 0.25, 0.27}},
    {mesh = "cube", pos = {0, 1.4, 0}, size = {3.0, 2.4, 3.6}, color = {0.35, 0.38, 0.32}},
    {mesh = "cube", pos = {0, 2.7, 0}, size = {3.4, 0.25, 4.0}, color = {0.2, 0.22, 0.2}},
    {mesh = "cube", pos = {0, 1.6, 1.81}, size = {2.2, 0.9, 0.05}, color = {0.3, 0.45, 0.55}},
    {mesh = "cube", pos = {1.51, 1.1, 0}, size = {0.05, 2.0, 0.9}, color = {0.25, 0.25, 0.28}},
  })

  engine.mesh("barrier_post", {
    {mesh = "cylinder", pos = {0, 0.6, 0}, size = {0.35, 1.2, 0.35}, color = {0.9, 0.75, 0.1}},
    {mesh = "cube", pos = {0, 1.05, 0}, size = {0.4, 0.3, 0.4}, color = {0.2, 0.2, 0.2}},
  })

  engine.mesh("jersey_barrier", {
    {mesh = "cube", pos = {0, 0.2, 0}, size = {2.4, 0.4, 0.7}, color = {0.8, 0.8, 0.82}},
    {mesh = "cube", pos = {0, 0.55, 0}, size = {2.4, 0.5, 0.35}, color = {0.85, 0.2, 0.15}},
    {mesh = "cube", pos = {0, 0.85, 0}, size = {2.4, 0.2, 0.25}, color = {0.8, 0.8, 0.82}},
  })

  engine.mesh("wood_bollard", {
    {mesh = "cylinder", pos = {0, 0.45, 0}, size = {0.22, 0.9, 0.22}, color = {0.45, 0.32, 0.18}},
    {mesh = "sphere", pos = {0, 0.9, 0}, size = 0.24, color = {0.4, 0.28, 0.15}},
  })

  -- Sisu XA-180 "Pasi" 6x6 APC: Finnish military troop transport
  local camo_green, camo_dark, steel = {0.22, 0.28, 0.18}, {0.12, 0.16, 0.11}, {0.18, 0.18, 0.2}
  local tire = {0.08, 0.08, 0.08}
  local pasi_parts = {
    -- Lower sloped boat hull (amphibious V-hull)
    {mesh = "cube", pos = {0, 0.1, 0}, size = {2.6, 0.8, 6.8}, color = camo_dark},
    -- Main armored hull: forward sloped glacis plate and angular cabin
    {mesh = "cube", pos = {0, 0.85, -0.2}, size = {2.7, 0.9, 6.2}, color = camo_green},
    -- Sloped front nose
    {mesh = "cube", pos = {0, 0.6, 3.0}, size = {2.5, 0.6, 0.9}, color = camo_green},
    -- Commander cupola / armored roof turret
    {mesh = "cylinder", pos = {0, 1.5, 1.2}, size = {0.9, 0.5, 0.9}, color = steel},
    {mesh = "cube", pos = {0, 1.6, 1.8}, size = {0.14, 0.14, 0.9}, color = steel}, -- 12.7mm machine gun barrel
    -- Rear crew doors and vision blocks
    {mesh = "cube", pos = {0, 0.85, -3.32}, size = {2.1, 0.7, 0.05}, color = camo_dark},
    -- Heavy front steel ram bumper
    {mesh = "cube", pos = {0, 0.2, 3.42}, size = {2.7, 0.4, 0.25}, color = steel},
  }
  -- 6 heavy off-road tires (3 on each side)
  for _, z_pos in ipairs{-1.9, 0.0, 1.9} do
    for _, side in ipairs{-1.42, 1.42} do
      pasi_parts[#pasi_parts + 1] = {mesh = "cylinder", axis = "x", pos = {side, -0.05, z_pos}, size = {0.48, 1.15, 1.15}, color = tire}
      pasi_parts[#pasi_parts + 1] = {mesh = "cylinder", axis = "x", pos = {side * 1.03, -0.05, z_pos}, size = {0.45, 0.55, 0.55}, color = camo_dark}
    end
  end
  engine.mesh("pasi", pasi_parts)
  P.person("soldier", {0.24, 0.32, 0.19}, {0.16, 0.22, 0.14}, {0.8, 0.62, 0.48}, {0.08, 0.08, 0.08})

  -- Föli Municipal Bus: Turku/Raisio regional transit bus (yellow & white livery)
  local foli_yellow, foli_white, foli_glass, bumper = {0.95, 0.82, 0.08}, {0.94, 0.94, 0.96}, {0.15, 0.22, 0.3}, {0.18, 0.18, 0.2}
  local bus_parts = {
    -- Lower chassis & yellow skirt
    {mesh = "cube", pos = {0, 0.2, 0}, size = {2.6, 0.7, 11.8}, color = foli_yellow},
    -- Main body cabin (white)
    {mesh = "cube", pos = {0, 1.3, 0}, size = {2.56, 1.5, 11.6}, color = foli_white},
    -- Tinted passenger side windows (continuous band on left and right)
    {mesh = "cube", pos = {0, 1.45, -0.4}, size = {2.62, 0.85, 9.6}, color = foli_glass},
    -- Front windshield (sloped large glass)
    {mesh = "cube", pos = {0, 1.45, 5.2}, size = {2.45, 1.1, 1.3}, color = foli_glass},
    -- Rear window
    {mesh = "cube", pos = {0, 1.45, -5.75}, size = {2.2, 0.75, 0.12}, color = foli_glass},
    -- Front digital route display sign (orange LED destination board)
    {mesh = "cube", pos = {0, 2.1, 5.5}, size = {1.6, 0.25, 0.1}, color = {1.0, 0.6, 0.05}, emissive = 1},
    -- Front and rear bumpers
    {mesh = "cube", pos = {0, -0.05, 5.92}, size = {2.62, 0.35, 0.15}, color = bumper},
    {mesh = "cube", pos = {0, -0.05, -5.92}, size = {2.62, 0.35, 0.15}, color = bumper},
    -- Roof AC and vent pods
    {mesh = "cube", pos = {0, 2.2, -1.8}, size = {1.6, 0.35, 2.8}, color = foli_white},
  }
  -- Dual axle front/rear wheels
  for _, z_pos in ipairs{3.8, -3.8} do
    for _, side in ipairs{-1.34, 1.34} do
      bus_parts[#bus_parts + 1] = {mesh = "cylinder", axis = "x", pos = {side, -0.05, z_pos}, size = {0.38, 0.95, 0.95}, color = tire}
      bus_parts[#bus_parts + 1] = {mesh = "cylinder", axis = "x", pos = {side * 1.02, -0.05, z_pos}, size = {0.36, 0.45, 0.45}, color = bumper}
    end
  end
  engine.mesh("bus", bus_parts)

  -- The Föri: Turku's famous historic city cable ferry (bright orange hull)
  local fori_orange, fori_deck, fori_barrier = {0.96, 0.45, 0.05}, {0.35, 0.35, 0.38}, {0.9, 0.88, 0.15}
  local fori_parts = {
    -- Flat broad passenger/cyclist ferry deck (drivable flat pontoon)
    {mesh = "cube", pos = {0, -0.2, 0}, size = {10.5, 0.6, 9.2}, color = fori_orange},
    -- Non-slip timber/steel deck surface
    {mesh = "cube", pos = {0, 0.12, 0}, size = {9.8, 0.08, 8.6}, color = fori_deck},
    -- Low perimeter safety bulkheads (fore and aft ramps open for boarding)
    {mesh = "cube", pos = {-4.9, 0.6, 0}, size = {0.4, 0.9, 8.6}, color = fori_orange},
    {mesh = "cube", pos = {4.9, 0.6, 0}, size = {0.4, 0.9, 8.6}, color = fori_orange},
    -- Boarding gates / barrier arms across ends
    {mesh = "cube", pos = {0, 0.6, -4.35}, size = {9.6, 0.14, 0.14}, color = fori_barrier},
    {mesh = "cube", pos = {0, 0.6, 4.35}, size = {9.6, 0.14, 0.14}, color = fori_barrier},
    -- Central operator control booth and diesel/cable machinery housing
    {mesh = "cube", pos = {0, 1.4, 0}, size = {2.2, 1.8, 2.4}, color = fori_orange},
    {mesh = "cube", pos = {0, 1.6, 0}, size = {2.25, 0.8, 2.2}, color = foli_glass},
    {mesh = "cube", pos = {0, 2.4, 0}, size = {2.4, 0.2, 2.6}, color = {0.2, 0.2, 0.22}},
    -- Life rings on side bulwarks
    {mesh = "cylinder", axis = "x", pos = {-5.12, 0.6, 1.8}, size = {0.12, 0.7, 0.7}, color = {0.95, 0.2, 0.15}},
    {mesh = "cylinder", axis = "x", pos = {5.12, 0.6, -1.8}, size = {0.12, 0.7, 0.7}, color = {0.95, 0.2, 0.15}},
  }
  engine.mesh("fori", fori_parts)

  -- Aurajoki Riverboat restaurant / bar boat (floating vessel moored along river quays)
  local boat_white, boat_hull, canopy = {0.92, 0.92, 0.95}, {0.15, 0.22, 0.35}, {0.85, 0.25, 0.2}
  local riverboat_parts = {
    -- Stepped ship hull
    {mesh = "cube", pos = {0, 0.2, 0}, size = {5.2, 1.4, 22.0}, color = boat_hull},
    -- Main saloon deck
    {mesh = "cube", pos = {0, 1.2, -1.0}, size = {4.8, 1.2, 18.0}, color = boat_white},
    -- Window strip along saloon
    {mesh = "cube", pos = {0, 1.35, -1.0}, size = {4.9, 0.6, 17.0}, color = foli_glass},
    -- Sun deck with striped awning canopy
    {mesh = "cube", pos = {0, 2.1, 2.0}, size = {4.6, 0.15, 10.0}, color = canopy},
    -- Ship funnel / smokestack
    {mesh = "cylinder", pos = {0, 2.6, -4.0}, size = {0.8, 1.6, 0.8}, color = {0.85, 0.75, 0.15}},
    -- Forward bow taper
    {mesh = "cube", pos = {0, 0.5, 11.2}, size = {3.6, 1.2, 3.2}, color = boat_hull},
  }
  engine.mesh("riverboat", riverboat_parts)

  -- Buster XXL Aluminum Speedboat: Finnish offshore planing motorboat
  local hull_grey, interior, windshield = {0.68, 0.7, 0.72}, {0.25, 0.28, 0.3}, {0.15, 0.22, 0.3}
  local boat_parts = {
    -- V-shaped marine aluminum hull
    {mesh = "cube", pos = {0, 0.1, 0}, size = {2.4, 0.8, 6.2}, color = hull_grey},
    -- Pointed bow wedge
    {mesh = "cube", pos = {0, 0.3, 2.7}, size = {2.1, 0.7, 1.2}, color = hull_grey},
    -- Cockpit tub / deck
    {mesh = "cube", pos = {0, 0.45, -0.4}, size = {2.1, 0.5, 4.4}, color = interior},
    -- Wrap-around curved windscreen
    {mesh = "cube", pos = {0, 0.85, 0.8}, size = {2.15, 0.45, 0.25}, color = windshield},
    -- Outboard motor on stern (Yamaha 150hp style)
    {mesh = "cube", pos = {0, 0.5, -3.2}, size = {0.55, 0.9, 0.7}, color = {0.12, 0.12, 0.15}},
    {mesh = "cylinder", pos = {0, -0.05, -3.4}, size = {0.2, 0.5, 0.2}, color = {0.2, 0.2, 0.2}}, -- skeg / propeller shaft
  }
  engine.mesh("speedboat", boat_parts)

  -- Turun linna (Turku Castle) keep tower
  local castle_stone, roof_copper = {0.72, 0.7, 0.68}, {0.22, 0.48, 0.38}
  local castle_parts = {
    -- Main keep rectangular stone block
    {mesh = "cube", pos = {0, 8.0, 0}, size = {28.0, 16.0, 42.0}, color = castle_stone},
    -- West gatehouse tower
    {mesh = "cube", pos = {-12.0, 11.0, 18.0}, size = {10.0, 22.0, 10.0}, color = castle_stone},
    -- East keep tower
    {mesh = "cube", pos = {12.0, 11.0, -18.0}, size = {10.0, 22.0, 10.0}, color = castle_stone},
    -- Weathered green copper hipped roofs
    {mesh = "cube", pos = {0, 17.5, 0}, size = {26.0, 3.0, 40.0}, color = roof_copper},
    {mesh = "cube", pos = {-12.0, 23.0, 18.0}, size = {9.0, 2.5, 9.0}, color = roof_copper},
    {mesh = "cube", pos = {12.0, 23.0, -18.0}, size = {9.0, 2.5, 9.0}, color = roof_copper},
  }
  engine.mesh("turun_linna", castle_parts)

  -- Turun Tuomiokirkko (Turku Cathedral) landmark
  local brick_red, copper_green, stone_trim = {0.62, 0.28, 0.22}, {0.22, 0.48, 0.38}, {0.75, 0.72, 0.68}
  local cathedral_parts = {
    -- Main cathedral nave
    {mesh = "cube", pos = {0, 9.0, 0}, size = {24.0, 18.0, 52.0}, color = brick_red},
    -- Steep copper roof on nave
    {mesh = "cube", pos = {0, 20.0, 0}, size = {22.0, 4.0, 50.0}, color = copper_green},
    -- Main bell tower
    {mesh = "cube", pos = {0, 20.0, -28.0}, size = {14.0, 40.0, 14.0}, color = brick_red},
    -- Tower upper belfry lantern
    {mesh = "cube", pos = {0, 44.0, -28.0}, size = {11.0, 8.0, 11.0}, color = stone_trim},
    -- Copper spire
    {mesh = "cube", pos = {0, 56.0, -28.0}, size = {6.0, 16.0, 6.0}, color = copper_green},
    {mesh = "cube", pos = {0, 68.0, -28.0}, size = {2.0, 8.0, 2.0}, color = copper_green},
    -- Cross / spire apex
    {mesh = "cube", pos = {0, 73.0, -28.0}, size = {0.5, 2.5, 0.5}, color = {0.9, 0.85, 0.3}, emissive = 0.5},
  }
  engine.mesh("tuomiokirkko", cathedral_parts)
end

return P
