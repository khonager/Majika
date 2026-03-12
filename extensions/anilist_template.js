/**
 * MAJIKA EXTENSION TEMPLATE
 * 
 * Target Service: AniList (GraphQL)
 * This template demonstrates how community developers should structure
 * their JavaScript extensions to be loaded by the Majika Flutter Engine.
 */

const EXTENSION_CONFIG = {
  id: "com.majika.ext.anilist",
  name: "AniList",
  version: "1.0.0",
  type: ["anime", "manga"], // What type of content this extension provides
  nsfw: false, // Set to true if this is an 18+ service to enforce E2EE locally
  baseURL: "https://graphql.anilist.co",
};

/**
 * 1. FETCH DISCOVER FEED
 * Called by the Majika Recommender Engine to fetch raw standard items
 * (e.g., currently airing, highest rated) before local scoring.
 * 
 * @param {number} page - The page number for infinite scrolling
 * @returns {Array} List of standardized Majika Item objects
 */
async function fetchDiscoverFeed(page = 1) {
  const query = `
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
  `;

  const variables = { page: page, perPage: 20 };

  // Note: The Majika Flutter JS Sandbox injects the 'MajikaHttp' global
  // because pure JS engines don't have built-in browsers 'fetch' API.
  const responseStr = await MajikaHttp.post(EXTENSION_CONFIG.baseURL, {
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query, variables })
  });

  const response = JSON.parse(responseStr);
  const mediaList = response.data.Page.media;

  // Map to Majika Standard Item Format
  return mediaList.map(media => ({
    id: `anilist_${media.id}`,
    title: media.title.english || media.title.romaji,
    coverUrl: media.coverImage.extraLarge,
    tags: media.genres,
    rating: media.averageScore ? media.averageScore / 10 : null, // Normalize to 10
    subtitle: media.episodes ? `${media.episodes} Episodes` : '',
    extensionId: EXTENSION_CONFIG.id,
  }));
}

/**
 * 2. FETCH ITEM DETAILS
 * Called when the user taps an item to open the Reader/Details View.
 */
async function fetchItemDetails(itemId) {
  const anilistId = itemId.replace('anilist_', '');
  
  const query = `
    query ($id: Int) {
      Media (id: $id) {
        description(asHtml: false)
        status
        trailer { id site }
        characters (sort: [ROLE, RELEVANCE, ID]) {
          edges { node { name { full } } }
        }
      }
    }
  `;
  
  const responseStr = await MajikaHttp.post(EXTENSION_CONFIG.baseURL, {
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query, variables: { id: parseInt(anilistId) } })
  });
  
  const data = JSON.parse(responseStr).data.Media;
  
  return {
    description: data.description,
    status: data.status,
    extraData: { // Any extension specific extra data
      characters: data.characters.edges.map(e => e.node.name.full),
      trailer: data.trailer ? `${data.trailer.site}: ${data.trailer.id}` : null
    }
  };
}

/**
 * 3. GET USER EXTENSION PROFILE (For Recommendations)
 * Fetches the user's specific history/ratings ON THIS SERVICE to feed
 * into the local mathematical profiling engine.
 * 
 * @param {string} authTokens - Securely injected by Majika Core if user is logged into Extension
 */
async function fetchUserProfile(authTokens) {
  // If the user hasn't logged into this specific extension, we return an empty profile
  if (!authTokens) return { likedTags: [], ratedItems: [] };
  
  // E.g., Fetch Anilist User's highly rated Shows and their genres
  // ... (Implementation specific to graphQL user query)
  return {
    likedTags: ["Action", "Sci-Fi", "Mecha"], // Example returned format
    ratedItems: [
      { id: "anilist_1", score: 9.5 },
      { id: "anilist_145", score: 1.0 }
    ]
  };
}

// Ensure functions are exposed to the Flutter JS Sandbox
MajikaExtension.register({
  config: EXTENSION_CONFIG,
  fetchDiscoverFeed,
  fetchItemDetails,
  fetchUserProfile
});
