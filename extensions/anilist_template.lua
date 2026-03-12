-- MAJIKA LUA EXTENSION TEMPLATE
-- Target Service: AniList (GraphQL)

local EXTENSION_CONFIG = {
  id = "com.majika.ext.anilist",
  name = "AniList",
  version = "1.0.0",
  type = {"anime", "manga"},
  nsfw = false,
  baseURL = "https://graphql.anilist.co"
}

-- 1. FETCH DISCOVER FEED
function fetchDiscoverFeed(page)
  page = page or 1
  
  -- Call the Dart-injected MajikaHttp global function
  local responseStr, err = MajikaHttp("POST", EXTENSION_CONFIG.baseURL, nil, "")
  
  if err ~= nil and err ~= "" then
    -- Escape quotes and newlines from HTML error pages before sending as JSON string
    local safeErr = string.gsub(err, '"', '\\"')
    safeErr = string.gsub(safeErr, '\n', ' ')
    safeErr = string.gsub(safeErr, '\r', ' ')
    return '{"error": "' .. safeErr .. '"}'
  end

  -- For this template execution, Dart returns the exact exact MediaItem formatted JSON string directly
  -- Because lua_dardo 0.0.5 does not have a native string to table JSON parser built-in.
  return responseStr
end

-- Must return the globally accessible config and entry functions to Dart
return {
  config = EXTENSION_CONFIG,
  fetchDiscoverFeed = fetchDiscoverFeed
}
