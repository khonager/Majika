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

function fetchDiscoverFeed(page)
  page = page or 1
  
  local query = [[
    query ($page: Int, $perPage: Int) {
      Page (page: $page, perPage: $perPage) {
        media (sort: TRENDING_DESC, type: ANIME, isAdult: false) {
          id
          title { romaji english }
          coverImage { extraLarge }
          genres
          averageScore
          episodes
        }
      }
    }
  ]]

  -- Since we lack cjson in Lua, we will let Dart build the JSON body for GraphQL!
  -- We pass the query as arg 4 (body), and the 'page' variable as arg 5.
  local responseStr, err = MajikaHttp("POST", EXTENSION_CONFIG.baseURL, nil, query, tostring(page))
  
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
