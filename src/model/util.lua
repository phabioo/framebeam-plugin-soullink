-- Small pure helpers shared by the model modules.
local U = {}

--- Deep copy of plain data (tables, strings, numbers, booleans).
function U.copy(v)
  if type(v) ~= "table" then return v end
  local c = {}
  for k, x in pairs(v) do c[k] = U.copy(x) end
  return c
end

--- Sorted list of the keys of `t` (strings or numbers; mixed keys sort by string form).
function U.keys(t)
  local out = {}
  for k in pairs(t or {}) do out[#out + 1] = k end
  table.sort(out, function(a, b)
    if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
    return tostring(a) < tostring(b)
  end)
  return out
end

--- Personality value -> 8-hex-digit lowercase string (the key of a Pokemon in the own state).
--- Returns nil when `n` is not an integer value.
function U.hex8(n)
  if math.type(n) == "float" then n = math.tointeger(n) end
  if math.type(n) ~= "integer" then return nil end
  return string.format("%08x", n & 0xffffffff)
end

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function enc_string(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return ESC[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function is_array(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  if n == 0 then return false end
  for i = 1, n do if t[i] == nil then return false end end
  return true
end

--- Deterministic JSON encoding (sorted object keys). Used to measure state and payload sizes.
--- Raises on functions and non-finite numbers.
function U.encode(v)
  local tv = type(v)
  if tv == "nil" then return "null" end
  if tv == "boolean" then return tostring(v) end
  if tv == "number" then
    if v ~= v or v == math.huge or v == -math.huge then error("non-finite number") end
    if math.type(v) == "integer" then return tostring(v) end
    return string.format("%.14g", v)
  end
  if tv == "string" then return enc_string(v) end
  if tv ~= "table" then error("cannot encode " .. tv) end
  local out = {}
  if is_array(v) then
    for i = 1, #v do out[i] = U.encode(v[i]) end
    return "[" .. table.concat(out, ",") .. "]"
  end
  for _, k in ipairs(U.keys(v)) do
    out[#out + 1] = enc_string(tostring(k)) .. ":" .. U.encode(v[k])
  end
  return "{" .. table.concat(out, ",") .. "}"
end

--- Size in bytes of the JSON encoding.
function U.json_size(v) return #U.encode(v) end

--- Trim and collapse whitespace; nil for empty.
function U.clean_text(s, max)
  if type(s) ~= "string" then return nil end
  s = s:gsub("%c", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
  if s == "" then return nil end
  if max and utf8.len(s) and utf8.len(s) > max then
    s = s:sub(1, (utf8.offset(s, max + 1) or (#s + 1)) - 1)
  elseif max and #s > max and not utf8.len(s) then
    s = s:sub(1, max)
  end
  return s
end

return U
