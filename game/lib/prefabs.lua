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

-- Sports car: collider 2.0 x 1.2 x 4.6, low and long, with a wing.
function P.sports_parts(c)
  local glass, tire, rim, dark = {0.12, 0.16, 0.22}, {0.08, 0.08, 0.08}, {0.75, 0.75, 0.78}, {0.1, 0.1, 0.11}
  local parts = {
    {mesh = "cube", pos = {0, -0.25, 0}, size = {2.0, 0.45, 4.6}, color = c},
    {mesh = "cube", pos = {0, 0.12, -0.35}, size = {1.7, 0.36, 1.9}, color = {c[1] * 0.85, c[2] * 0.85, c[3] * 0.85}},
    {mesh = "cube", pos = {0, 0.14, -0.35}, size = {1.74, 0.26, 1.6}, color = glass},
    {mesh = "cube", pos = {0, 0.12, 0.62}, size = {1.5, 0.28, 0.06}, color = glass},
    {mesh = "cube", pos = {0, -0.02, 1.5}, size = {1.2, 0.04, 1.0}, color = dark},
    {mesh = "cube", pos = {0, 0.2, -2.15}, size = {1.9, 0.07, 0.4}, color = dark},
    {mesh = "cube", pos = {0.7, 0.05, -2.15}, size = {0.08, 0.25, 0.2}, color = dark},
    {mesh = "cube", pos = {-0.7, 0.05, -2.15}, size = {0.08, 0.25, 0.2}, color = dark},
    {mesh = "cube", pos = {0.62, -0.18, 2.31}, size = {0.5, 0.12, 0.04}, color = {1, 0.95, 0.7}, emissive = 1},
    {mesh = "cube", pos = {-0.62, -0.18, 2.31}, size = {0.5, 0.12, 0.04}, color = {1, 0.95, 0.7}, emissive = 1},
    {mesh = "cube", pos = {0, -0.15, -2.31}, size = {1.7, 0.1, 0.04}, color = {0.9, 0.05, 0.05}, emissive = 1},
  }
  for _, w in ipairs{{0.9, 1.45}, {-0.9, 1.45}, {0.92, -1.45}, {-0.92, -1.45}} do
    parts[#parts + 1] = {mesh = "cylinder", axis = "x", pos = {w[1], -0.3, w[2]}, size = {0.38, 0.68, 0.68}, color = tire}
    parts[#parts + 1] = {mesh = "cylinder", axis = "x", pos = {w[1] * 1.02, -0.3, w[2]}, size = {0.36, 0.4, 0.4}, color = rim}
  end
  return parts
end

-- Delivery van: collider 2.1 x 2.2 x 5.0, a cab and a tall box.
function P.van_parts(c)
  local glass, tire, rim = {0.15, 0.2, 0.28}, {0.08, 0.08, 0.08}, {0.55, 0.55, 0.55}
  local parts = {
    {mesh = "cube", pos = {0, -0.65, 0}, size = {2.1, 0.4, 5.0}, color = {0.2, 0.2, 0.22}},
    {mesh = "cube", pos = {0, 0.25, -0.6}, size = {2.1, 1.7, 3.8}, color = c},
    {mesh = "cube", pos = {0, -0.05, 1.85}, size = {2.04, 1.1, 1.3}, color = c},
    {mesh = "cube", pos = {0, 0.2, 2.25}, size = {1.86, 0.5, 0.5}, color = glass},
    {mesh = "cube", pos = {0, 0.2, 1.75}, size = {2.08, 0.45, 0.8}, color = glass},
    {mesh = "cube", pos = {0.65, -0.4, 2.51}, size = {0.4, 0.18, 0.04}, color = {1, 0.95, 0.7}, emissive = 1},
    {mesh = "cube", pos = {-0.65, -0.4, 2.51}, size = {0.4, 0.18, 0.04}, color = {1, 0.95, 0.7}, emissive = 1},
    {mesh = "cube", pos = {0.85, -0.3, -2.51}, size = {0.25, 0.4, 0.04}, color = {0.9, 0.05, 0.05}, emissive = 1},
    {mesh = "cube", pos = {-0.85, -0.3, -2.51}, size = {0.25, 0.4, 0.04}, color = {0.9, 0.05, 0.05}, emissive = 1},
    {mesh = "cube", pos = {0, 0.25, -2.52}, size = {0.04, 1.5, 0.02}, color = {0.25, 0.25, 0.27}},
  }
  for _, w in ipairs{{0.95, 1.7}, {-0.95, 1.7}, {0.95, -1.6}, {-0.95, -1.6}} do
    parts[#parts + 1] = {mesh = "cylinder", axis = "x", pos = {w[1], -0.72, w[2]}, size = {0.32, 0.76, 0.76}, color = tire}
    parts[#parts + 1] = {mesh = "cylinder", axis = "x", pos = {w[1] * 1.02, -0.72, w[2]}, size = {0.3, 0.36, 0.36}, color = rim}
  end
  return parts
end

-- Ambulance: the van in yellow with a green band, and a blue light bar on
-- the roof (its paint doesn't change with the colour it's given).
function P.ambulance_parts()
  local parts = P.van_parts({0.95, 0.82, 0.12})
  parts[#parts + 1] = {mesh = "cube", pos = {0, -0.15, -0.1}, size = {2.13, 0.32, 4.86}, color = {0.1, 0.5, 0.25}}
  parts[#parts + 1] = {mesh = "cube", pos = {0, 1.18, 0.9}, size = {1.5, 0.16, 0.3}, color = {0.15, 0.35, 1}, emissive = 1}
  parts[#parts + 1] = {mesh = "cube", pos = {0, 0.55, -2.53}, size = {0.5, 0.14, 0.02}, color = {0.85, 0.1, 0.1}}
  parts[#parts + 1] = {mesh = "cube", pos = {0, 0.55, -2.53}, size = {0.14, 0.5, 0.02}, color = {0.85, 0.1, 0.1}}
  return parts
end

-- Taxi: the car with a lit TAKSI sign on the roof.
function P.cab_parts(c)
  local parts = P.car_parts(c)
  parts[#parts + 1] = {mesh = "cube", pos = {0, 0.82, -0.3}, size = {0.75, 0.22, 0.32}, color = {1, 0.85, 0.15}, emissive = 1}
  return parts
end

-- Kinds of car, by mesh name prefix: their collider, mass, and how high
-- the body rides (half the collider's height, plus a little).
P.CAR_KINDS = {
  car = {size = {2.0, 1.4, 4.4}, mass = 1200, lift = 0.75, parts = P.car_parts},
  sports = {size = {2.0, 1.2, 4.6}, mass = 1100, lift = 0.65, parts = P.sports_parts},
  van = {size = {2.1, 2.2, 5.0}, mass = 1900, lift = 1.15, parts = P.van_parts},
  cab = {size = {2.0, 1.4, 4.4}, mass = 1200, lift = 0.75, parts = P.cab_parts},
  ambulance = {size = {2.1, 2.2, 5.0}, mass = 2000, lift = 1.15, parts = P.ambulance_parts},
}

-- "car", "sports", "van" or "cab" for a mesh like "van3"; nil for others.
function P.car_kind(mesh)
  local k = mesh and mesh:match("^(%a+)%d+$")
  return k and P.CAR_KINDS[k] and k or nil
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
  for kind, k in pairs(P.CAR_KINDS) do
    for i, c in ipairs(P.car_colors) do engine.mesh(kind .. i, k.parts(c)) end
  end

  P.person("person", {0.85, 0.85, 0.82}, {0.2, 0.25, 0.45}, {0.85, 0.7, 0.55}, {0.15, 0.1, 0.05})

  engine.mesh("tree", {
    {mesh = "cylinder", pos = {0, 1.0, 0}, size = {0.35, 2.0, 0.35}, color = {0.4, 0.27, 0.15}},
    {mesh = "sphere", pos = {0, 2.8, 0}, size = {2.4, 2.2, 2.4}, color = {0.22, 0.5, 0.2}},
    {mesh = "sphere", pos = {0.5, 3.6, 0.2}, size = {1.5, 1.4, 1.5}, color = {0.26, 0.56, 0.22}},
  })

  -- Leafy Aurajoki riverside boulevard linden / weeping willow tree
  engine.mesh("willow_tree", {
    {mesh = "cylinder", pos = {0, 1.5, 0}, size = {0.5, 3.0, 0.5}, color = {0.32, 0.22, 0.14}},
    {mesh = "sphere", pos = {0, 3.8, 0}, size = {3.6, 2.6, 3.6}, color = {0.28, 0.54, 0.24}},
    {mesh = "sphere", pos = {-0.6, 3.2, 0.5}, size = {2.2, 2.0, 2.2}, color = {0.22, 0.48, 0.20}},
    {mesh = "sphere", pos = {0.7, 3.1, -0.4}, size = {2.4, 2.1, 2.4}, color = {0.32, 0.58, 0.26}},
  })

  -- Cast-iron riverside park bench (Jokirannan puistonpenkki)
  local bench_wood, bench_iron = {0.62, 0.38, 0.18}, {0.18, 0.18, 0.20}
  engine.mesh("park_bench", {
    {mesh = "cube", pos = {0, 0.45, 0}, size = {2.0, 0.08, 0.55}, color = bench_wood},
    {mesh = "cube", pos = {0, 0.72, -0.24}, size = {2.0, 0.45, 0.08}, color = bench_wood},
    {mesh = "cube", pos = {-0.9, 0.35, 0}, size = {0.1, 0.7, 0.58}, color = bench_iron},
    {mesh = "cube", pos = {0.9, 0.35, 0}, size = {0.1, 0.7, 0.58}, color = bench_iron},
  })

  -- Koroistenniemi White Bishop's Cross (Koroisten valkoinen piispanristi)
  local cross_white, cross_stone = {0.96, 0.96, 0.98}, {0.55, 0.54, 0.52}
  engine.mesh("koroisten_risti", {
    -- Mound stone cairn base
    {mesh = "cube", pos = {0, 0.5, 0}, size = {2.6, 1.0, 2.6}, color = cross_stone},
    {mesh = "cube", pos = {0, 1.2, 0}, size = {2.0, 0.5, 2.0}, color = cross_stone},
    -- Vertical wooden beam (6 meters high)
    {mesh = "cube", pos = {0, 4.5, 0}, size = {0.35, 6.2, 0.35}, color = cross_white},
    -- Horizontal cross arm (3.2 meters wide)
    {mesh = "cube", pos = {0, 6.2, 0}, size = {3.4, 0.35, 0.35}, color = cross_white},
  })

  engine.mesh("lamp", {
    {mesh = "cylinder", pos = {0, 2.5, 0}, size = {0.15, 5.0, 0.15}, color = {0.25, 0.25, 0.27}},
    {mesh = "cube", pos = {0, 5.0, 0.6}, size = {0.15, 0.12, 1.3}, color = {0.25, 0.25, 0.27}},
    {mesh = "cube", pos = {0, 4.92, 1.15}, size = {0.35, 0.1, 0.5}, color = {1.0, 0.95, 0.75}, emissive = 1},
  })
  -- A knocked-over lamp (systems/lamps): the same post about its middle,
  -- so it tumbles like one, and its light out.
  engine.mesh("lamp_down", {
    {mesh = "cylinder", pos = {0, 0, 0}, size = {0.15, 5.0, 0.15}, color = {0.25, 0.25, 0.27}},
    {mesh = "cube", pos = {0, 2.5, 0.6}, size = {0.15, 0.12, 1.3}, color = {0.25, 0.25, 0.27}},
    {mesh = "cube", pos = {0, 2.42, 1.15}, size = {0.35, 0.1, 0.5}, color = {0.55, 0.55, 0.5}},
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

  -- Pöli Municipal Bus: Turku/Raisio regional transit bus (yellow & white livery)
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

  -- Puskuri XXL Speedboat: Finnish offshore planing motorboat
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

  -- Turun linna (Turku Castle) authentic medieval keep and Renaissance bailey
  local castle_stone = {0.74, 0.72, 0.68}
  local castle_wall_dark = {0.62, 0.60, 0.58}
  local roof_copper = {0.24, 0.48, 0.38}
  local roof_copper_dark = {0.18, 0.38, 0.30}
  local wood_dark = {0.35, 0.25, 0.18}
  local castle_parts = {
    -- 1. Main Keep (Päälinna) central hall block
    {mesh = "cube", pos = {0, 10.0, 0}, size = {26.0, 20.0, 48.0}, color = castle_stone},
    -- Steep copper pitched roof over the central keep (wedges back-to-back)
    {mesh = "wedge", pos = {-6.5, 24.5, 0}, yaw = math.pi / 2, size = {48.0, 9.0, 13.0}, color = roof_copper},
    {mesh = "wedge", pos = {6.5, 24.5, 0}, yaw = -math.pi / 2, size = {48.0, 9.0, 13.0}, color = roof_copper},
    -- Stepped gable walls at north and south ends
    {mesh = "cube", pos = {0, 22.0, 24.1}, size = {24.0, 4.0, 0.4}, color = castle_stone},
    {mesh = "cube", pos = {0, 25.0, 24.1}, size = {16.0, 4.0, 0.4}, color = castle_stone},
    {mesh = "cube", pos = {0, 27.5, 24.1}, size = {8.0, 3.0, 0.4}, color = castle_stone},
    {mesh = "cube", pos = {0, 22.0, -24.1}, size = {24.0, 4.0, 0.4}, color = castle_stone},
    {mesh = "cube", pos = {0, 25.0, -24.1}, size = {16.0, 4.0, 0.4}, color = castle_stone},
    {mesh = "cube", pos = {0, 27.5, -24.1}, size = {8.0, 3.0, 0.4}, color = castle_stone},

    -- 2. Massive West Keep Tower (Länsitorni)
    {mesh = "cube", pos = {-12.0, 14.0, 22.0}, size = {12.0, 28.0, 12.0}, color = castle_stone},
    {mesh = "cube", pos = {-12.0, 29.5, 22.0}, size = {12.6, 3.0, 12.6}, color = castle_wall_dark},
    {mesh = "cube", pos = {-12.0, 33.0, 22.0}, size = {11.5, 4.0, 11.5}, color = roof_copper_dark},
    {mesh = "cylinder", pos = {-12.0, 38.0, 22.0}, size = {0.2, 7.0, 0.2}, color = {0.85, 0.85, 0.88}},

    -- 3. Massive East Keep Tower (Itätorni)
    {mesh = "cube", pos = {12.0, 14.0, -22.0}, size = {12.0, 28.0, 12.0}, color = castle_stone},
    {mesh = "cube", pos = {12.0, 29.5, -22.0}, size = {12.6, 3.0, 12.6}, color = castle_wall_dark},
    {mesh = "cube", pos = {12.0, 33.0, -22.0}, size = {11.5, 4.0, 11.5}, color = roof_copper_dark},

    -- 4. Renaissance Outer Bailey (Esilinna)
    {mesh = "cube", pos = {18.0, 7.0, 8.0}, size = {18.0, 14.0, 32.0}, color = castle_stone},
    {mesh = "wedge", pos = {18.0, 17.0, 0}, size = {18.0, 6.0, 16.0}, color = roof_copper},
    {mesh = "wedge", pos = {18.0, 17.0, 16.0}, yaw = math.pi, size = {18.0, 6.0, 16.0}, color = roof_copper},

    -- 5. The iconic Round Tower (Pyöreä torni - Renaissance artillery roundel)
    {mesh = "cylinder", pos = {26.0, 9.0, 26.0}, size = {14.0, 18.0, 14.0}, color = castle_stone},
    {mesh = "cylinder", pos = {26.0, 19.5, 26.0}, size = {14.6, 3.0, 14.6}, color = castle_wall_dark},
    {mesh = "cylinder", pos = {26.0, 22.5, 26.0}, size = {12.0, 3.5, 12.0}, color = roof_copper},

    -- 6. Gatehouse and portal archway
    {mesh = "cube", pos = {9.0, 3.5, 24.5}, size = {5.0, 7.0, 2.0}, color = wood_dark},
  }
  engine.mesh("turun_linna", castle_parts)

  -- Suomen Joutsen: Historic three-masted full-rigged museum ship at Forum Marinum
  local joutsen_hull, teak, mast_color = {0.96, 0.96, 0.96}, {0.52, 0.40, 0.28}, {0.88, 0.85, 0.75}
  local joutsen_parts = {
    -- Main white steel hull
    {mesh = "cube", pos = {0, 1.2, 0}, size = {7.6, 2.8, 54.0}, color = joutsen_hull},
    -- Raised forecastle and poop deck
    {mesh = "cube", pos = {0, 3.0, 20.0}, size = {7.2, 1.2, 12.0}, color = joutsen_hull},
    {mesh = "cube", pos = {0, 3.0, -20.0}, size = {7.2, 1.2, 12.0}, color = joutsen_hull},
    -- Teak main deck
    {mesh = "cube", pos = {0, 2.45, 0}, size = {7.0, 0.1, 48.0}, color = teak},
    -- Fore-mast, Main-mast, Mizzen-mast
    {mesh = "cylinder", pos = {0, 14.0, 14.0}, size = {0.45, 24.0, 0.45}, color = mast_color},
    {mesh = "cylinder", pos = {0, 15.5, -1.0}, size = {0.45, 27.0, 0.45}, color = mast_color},
    {mesh = "cylinder", pos = {0, 13.5, -16.0}, size = {0.42, 23.0, 0.42}, color = mast_color},
    -- Horizontal yardarms across masts
    {mesh = "cylinder", axis = "x", pos = {0, 12.0, 14.0}, size = {14.0, 0.2, 0.2}, color = mast_color},
    {mesh = "cylinder", axis = "x", pos = {0, 18.0, 14.0}, size = {10.0, 0.16, 0.16}, color = mast_color},
    {mesh = "cylinder", axis = "x", pos = {0, 13.5, -1.0}, size = {16.0, 0.2, 0.2}, color = mast_color},
    {mesh = "cylinder", axis = "x", pos = {0, 20.0, -1.0}, size = {11.0, 0.16, 0.16}, color = mast_color},
    {mesh = "cylinder", axis = "x", pos = {0, 11.5, -16.0}, size = {13.0, 0.2, 0.2}, color = mast_color},
    -- Bowsprit
    {mesh = "cylinder", pos = {0, 3.8, 32.0}, size = {0.3, 9.0, 0.3}, color = mast_color},
  }
  engine.mesh("suomen_joutsen", joutsen_parts)

  -- Kakolan funikulaari (Turku slope elevator cabin)
  local f_yellow, f_chassis, f_glass = {0.96, 0.78, 0.12}, {0.18, 0.18, 0.20}, {0.15, 0.24, 0.32}
  local funi_parts = {
    -- Heavy wheel truck / chassis
    {mesh = "cube", pos = {0, 0.2, 0}, size = {2.3, 0.4, 4.6}, color = f_chassis},
    -- Lower yellow body panels
    {mesh = "cube", pos = {0, 0.75, 0}, size = {2.42, 0.7, 4.75}, color = f_yellow},
    -- Wrap-around panoramic passenger glass
    {mesh = "cube", pos = {0, 1.65, 0}, size = {2.38, 1.1, 4.65}, color = f_glass},
    -- Sloped yellow roof cap
    {mesh = "cube", pos = {0, 2.3, 0}, size = {2.45, 0.2, 4.8}, color = f_yellow},
    -- Roof equipment and air pod
    {mesh = "cube", pos = {0, 2.5, 0}, size = {1.6, 0.3, 3.2}, color = {0.82, 0.84, 0.86}},
  }
  engine.mesh("funikulaari", funi_parts)

  -- Funicular station terminal shelter
  local f_steel, f_zinc = {0.22, 0.24, 0.26}, {0.32, 0.35, 0.38}
  local station_parts = {
    -- Concrete platform foundation
    {mesh = "cube", pos = {0, 0.25, 0}, size = {6.5, 0.5, 8.0}, color = {0.6, 0.6, 0.62}},
    -- Steel canopy supports
    {mesh = "cube", pos = {-2.8, 2.0, -3.2}, size = {0.25, 3.2, 0.25}, color = f_steel},
    -- Glass passenger kiosk
    {mesh = "cube", pos = {1.8, 1.5, 0}, size = {2.2, 2.2, 5.0}, color = f_glass},
    -- Slanted terminal canopy
    {mesh = "cube", pos = {0, 3.4, 0}, size = {6.8, 0.35, 8.5}, color = f_zinc},
  }
  engine.mesh("funicular_station", station_parts)

  -- s/s Bore (Historic 1960 passenger steamship at Forum Marinum / Turku Harbor)
  local bore_white, bore_blue, bore_teak = {0.95, 0.95, 0.96}, {0.15, 0.28, 0.55}, {0.55, 0.42, 0.30}
  local bore_parts = {
    -- Lower dark blue hull
    {mesh = "cube", pos = {0, 1.2, 0}, size = {11.0, 3.2, 78.0}, color = bore_blue},
    -- Upper white hull & passenger decks
    {mesh = "cube", pos = {0, 3.5, 0}, size = {10.6, 2.4, 76.0}, color = bore_white},
    -- Promenade & boat deck
    {mesh = "cube", pos = {0, 5.5, -4.0}, size = {9.8, 2.2, 60.0}, color = bore_white},
    -- Teak top observation deck
    {mesh = "cube", pos = {0, 6.7, -4.0}, size = {9.2, 0.2, 58.0}, color = bore_teak},
    -- Bridge / wheelhouse forward
    {mesh = "cube", pos = {0, 7.6, 18.0}, size = {8.2, 2.0, 8.0}, color = bore_white},
    -- Distinctive yellow & blue steamship funnel
    {mesh = "cylinder", pos = {0, 9.5, -2.0}, size = {2.8, 4.8, 4.2}, color = {0.94, 0.78, 0.12}},
    {mesh = "cylinder", pos = {0, 11.2, -2.0}, size = {2.85, 1.2, 4.25}, color = {0.15, 0.28, 0.55}},
    -- Fore-mast and radar scanner
    {mesh = "cylinder", pos = {0, 11.0, 24.0}, size = {0.35, 9.0, 0.35}, color = {0.88, 0.88, 0.85}},
  }
  engine.mesh("ss_bore", bore_parts)

  -- Port of Turku intermodal cargo container stack (40ft shipping containers)
  local c_blue, c_red, c_yellow, c_green = {0.15, 0.35, 0.62}, {0.72, 0.20, 0.15}, {0.90, 0.74, 0.12}, {0.18, 0.48, 0.32}
  local container_parts = {
    -- Ground tier containers (two side by side)
    {mesh = "cube", pos = {-1.3, 1.3, 0}, size = {2.45, 2.6, 12.2}, color = c_blue},
    {mesh = "cube", pos = {1.3, 1.3, 0}, size = {2.45, 2.6, 12.2}, color = c_red},
    -- Second tier (offset)
    {mesh = "cube", pos = {-1.3, 3.9, 0}, size = {2.45, 2.6, 12.2}, color = c_yellow},
    {mesh = "cube", pos = {1.3, 3.9, 0}, size = {2.45, 2.6, 12.2}, color = c_green},
    -- Third tier single top container
    {mesh = "cube", pos = {0, 6.5, 0}, size = {2.45, 2.6, 12.2}, color = c_blue},
  }
  engine.mesh("container_stack", container_parts)

  -- Port of Turku quayside container portal crane
  local crane_yellow, crane_steel = {0.92, 0.72, 0.12}, {0.25, 0.26, 0.28}
  local crane_parts = {
    -- Portal legs straddling wharf tracks (left and right A-frames)
    {mesh = "cube", pos = {-4.5, 7.0, -4.0}, size = {0.8, 14.0, 0.8}, color = crane_yellow},
    {mesh = "cube", pos = {-4.5, 7.0, 4.0}, size = {0.8, 14.0, 0.8}, color = crane_yellow},
    {mesh = "cube", pos = {4.5, 7.0, -4.0}, size = {0.8, 14.0, 0.8}, color = crane_yellow},
    {mesh = "cube", pos = {4.5, 7.0, 4.0}, size = {0.8, 14.0, 0.8}, color = crane_yellow},
    -- Upper portal crossbeam table
    {mesh = "cube", pos = {0, 14.2, 0}, size = {10.5, 1.5, 9.5}, color = crane_yellow},
    -- Operator machinery cab & counterweight
    {mesh = "cube", pos = {0, 17.5, -3.0}, size = {5.0, 5.0, 6.0}, color = crane_yellow},
    {mesh = "cube", pos = {0, 16.5, -6.5}, size = {4.0, 3.0, 2.5}, color = crane_steel},
    -- Horizontal jib truss cantilever extending out over the water
    {mesh = "cube", pos = {0, 20.0, 12.0}, size = {2.2, 2.5, 32.0}, color = crane_yellow},
  }
  engine.mesh("port_crane", crane_parts)

  -- Turun Kauppatori: market tent stall with striped awning and produce crate
  local stall_wood, stall_orange = {0.62, 0.42, 0.25}, {0.96, 0.45, 0.12}
  local stall_parts = {
    -- Table / display counter
    {mesh = "cube", pos = {0, 0.45, 0}, size = {2.4, 0.9, 1.4}, color = stall_wood},
    -- Slanted canvas awning roof
    {mesh = "cube", pos = {0, 1.85, 0}, size = {2.6, 0.1, 1.6}, color = stall_orange},
    -- White accent awning trim
    {mesh = "cube", pos = {0, 1.82, 0.78}, size = {2.6, 0.25, 0.05}, color = {0.95, 0.95, 0.95}},
    -- Thin corner canopy poles
    {mesh = "cylinder", pos = {-1.2, 1.1, -0.7}, size = {0.05, 1.4, 0.05}, color = {0.8, 0.8, 0.82}},
    {mesh = "cylinder", pos = {1.2, 1.1, -0.7}, size = {0.05, 1.4, 0.05}, color = {0.8, 0.8, 0.82}},
    {mesh = "cylinder", pos = {-1.2, 0.9, 0.7}, size = {0.05, 1.0, 0.05}, color = {0.8, 0.8, 0.82}},
    {mesh = "cylinder", pos = {1.2, 0.9, 0.7}, size = {0.05, 1.0, 0.05}, color = {0.8, 0.8, 0.82}},
  }
  engine.mesh("market_stall", stall_parts)

  -- Kauppatori taxi rank illuminated marker pole
  engine.mesh("taxi_pole", {
    {mesh = "cylinder", pos = {0, 1.5, 0}, size = {0.12, 3.0, 0.12}, color = {0.25, 0.25, 0.27}},
    {mesh = "cube", pos = {0, 3.1, 0}, size = {0.7, 0.35, 0.25}, color = {0.96, 0.82, 0.08}, emissive = 0.8},
  })

  -- Brinkkalan talo & Joulurauhan parveke (Historic Christmas Peace balcony)
  local brink_yellow, brink_white = {0.92, 0.82, 0.58}, {0.96, 0.96, 0.96}
  local brink_balcony_wood = {0.60, 0.42, 0.26}
  engine.mesh("brinkkala_facade", {
    -- Main neoclassical 3-story palace body
    {mesh = "cube", pos = {0, 6.5, 0}, size = {28.0, 13.0, 12.0}, color = brink_yellow},
    -- Mansard copper/tin roof
    {mesh = "cube", pos = {0, 14.2, 0}, size = {27.0, 3.0, 11.0}, color = {0.35, 0.38, 0.36}},
    -- Classical pediment triangular gable over central portico
    {mesh = "cube", pos = {0, 14.5, 5.8}, size = {10.0, 2.2, 1.0}, color = brink_yellow},
    -- The famous Joulurauha wooden declaration balcony (2nd floor central)
    {mesh = "cube", pos = {0, 6.8, 6.5}, size = {6.2, 0.35, 2.0}, color = brink_balcony_wood},
    -- Balcony decorative balustrade railing
    {mesh = "cube", pos = {0, 7.6, 7.4}, size = {6.2, 1.2, 0.15}, color = brink_white},
    {mesh = "cube", pos = {-3.0, 7.6, 6.5}, size = {0.15, 1.2, 1.8}, color = brink_white},
    {mesh = "cube", pos = {3.0, 7.6, 6.5}, size = {0.15, 1.2, 1.8}, color = brink_white},
  })

  -- Henrik Gabriel Porthan monument (Porthaninpuisto bronze statue on granite plinth)
  local porthan_granite, porthan_bronze = {0.45, 0.43, 0.42}, {0.22, 0.35, 0.28}
  engine.mesh("porthan_monument", {
    {mesh = "cube", pos = {0, 0.6, 0}, size = {2.4, 1.2, 2.4}, color = porthan_granite},
    {mesh = "cube", pos = {0, 2.2, 0}, size = {1.8, 2.0, 1.8}, color = porthan_granite},
    -- Bronze statue figure on top
    {mesh = "cylinder", pos = {0, 4.0, 0}, size = {0.5, 1.8, 0.5}, color = porthan_bronze},
    {mesh = "sphere", pos = {0, 5.1, 0}, size = {0.6, 0.6, 0.6}, color = porthan_bronze},
  })

  -- Turun Tuomiokirkko (National Cathedral of Finland, consecrated 1300)
  local church_brick = {0.62, 0.26, 0.18}
  local church_copper = {0.24, 0.48, 0.38}
  local church_copper_dark = {0.20, 0.40, 0.32}
  local church_gold = {0.96, 0.84, 0.22}
  local cathedral_parts = {
    -- Western clock tower: lower masonry shaft (14x14m, 30m high)
    {mesh = "cube", pos = {-22.0, 15.0, 0}, size = {14.0, 30.0, 14.0}, color = church_brick},
    -- Western clock tower: copper clock face & belfry tier
    {mesh = "cube", pos = {-22.0, 32.5, 0}, size = {12.4, 5.0, 12.4}, color = church_copper},
    -- Western clock tower: octagonal/pyramidal copper spire (reaching ~52m in-game)
    {mesh = "cube", pos = {-22.0, 40.5, 0}, size = {9.0, 11.0, 9.0}, color = church_copper_dark},
    {mesh = "cube", pos = {-22.0, 48.0, 0}, size = {5.0, 5.0, 5.0}, color = church_copper},
    -- Tower pinnacle golden cross
    {mesh = "cube", pos = {-22.0, 52.0, 0}, size = {0.4, 3.2, 0.4}, color = church_gold, emissive = 0.6},
    {mesh = "cube", pos = {-22.0, 52.6, 0}, size = {1.8, 0.4, 0.4}, color = church_gold, emissive = 0.6},

    -- Main Gothic high nave (54m long, 24m wide, 22m high)
    {mesh = "cube", pos = {12.0, 11.0, 0}, size = {54.0, 22.0, 24.0}, color = church_brick},
    -- Steep copper ridge gable roof over nave
    {mesh = "cube", pos = {12.0, 24.5, 0}, size = {55.0, 5.0, 22.2}, color = church_copper},

    -- North side-aisle chapels (Tavast, Tigerstedt chapels)
    {mesh = "cube", pos = {10.0, 6.5, -14.5}, size = {40.0, 13.0, 6.0}, color = church_brick},
    {mesh = "cube", pos = {10.0, 14.0, -14.5}, size = {40.0, 2.2, 5.8}, color = church_copper},

    -- South side-aisle chapels (Kankaisten kappeli, Karin Månsdotter's tomb chapel)
    {mesh = "cube", pos = {10.0, 6.5, 14.5}, size = {40.0, 13.0, 6.0}, color = church_brick},
    {mesh = "cube", pos = {10.0, 14.0, 14.5}, size = {40.0, 2.2, 5.8}, color = church_copper},

    -- Eastern choir apse
    {mesh = "cube", pos = {41.5, 10.5, 0}, size = {9.0, 21.0, 18.0}, color = church_brick},
    {mesh = "cube", pos = {41.5, 22.5, 0}, size = {9.2, 3.5, 16.5}, color = church_copper},
  }
  engine.mesh("tuomiokirkko_cathedral", cathedral_parts)
end

return P
