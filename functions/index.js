const {initializeApp} = require("firebase-admin/app");
const {HttpsError, onCall} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");

initializeApp();

const steamWebApiKey = defineSecret("STEAM_WEB_API_KEY");
const steamApiBase = "https://api.steampowered.com";

exports.steamApi = onCall(
  {
    region: "us-central1",
    secrets: [steamWebApiKey],
    cors: true,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Sign in before importing Steam data.",
      );
    }

    const action = stringParam(request.data, "action");
    switch (action) {
      case "resolveVanityUrl":
        return steamGet("/ISteamUser/ResolveVanityURL/v1/", {
          vanityurl: stringParam(request.data, "vanity"),
        });
      case "getPlayerSummaries":
        return steamGet("/ISteamUser/GetPlayerSummaries/v2/", {
          steamids: steamIdParam(request.data, "steamId"),
        });
      case "getOwnedGames":
        return steamGet("/IPlayerService/GetOwnedGames/v1/", {
          steamid: steamIdParam(request.data, "steamId"),
          include_appinfo: "true",
          include_played_free_games: "true",
          format: "json",
        });
      case "getRecentlyPlayedGames":
        return steamGet("/IPlayerService/GetRecentlyPlayedGames/v1/", {
          steamid: steamIdParam(request.data, "steamId"),
          format: "json",
        });
      default:
        throw new HttpsError("invalid-argument", "Unknown Steam action.");
    }
  },
);

function stringParam(data, key) {
  const value = data?.[key];
  if (typeof value !== "string" || value.trim() === "") {
    throw new HttpsError("invalid-argument", `Missing ${key}.`);
  }
  return value.trim();
}

function steamIdParam(data, key) {
  const value = stringParam(data, key);
  if (!/^\d{15,20}$/.test(value)) {
    throw new HttpsError("invalid-argument", "Invalid SteamID64.");
  }
  return value;
}

async function steamGet(path, query) {
  const key = steamWebApiKey.value();
  if (!key) {
    throw new HttpsError(
      "failed-precondition",
      "STEAM_WEB_API_KEY is not configured.",
    );
  }

  const url = new URL(`${steamApiBase}${path}`);
  url.searchParams.set("key", key);
  for (const [name, value] of Object.entries(query)) {
    url.searchParams.set(name, value);
  }

  const response = await fetch(url, {
    headers: {"User-Agent": "Majika/1.0 Firebase Functions"},
  });
  if (!response.ok) {
    throw new HttpsError(
      "unavailable",
      `Steam returned HTTP ${response.status}.`,
    );
  }

  return response.json();
}
