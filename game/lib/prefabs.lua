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
end

return P
