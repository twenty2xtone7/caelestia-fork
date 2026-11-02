.pragma library

// SpicyLyrics provider — opt-in, needs a Spotify access token pasted into
// Settings → Services.
//
// The endpoint is the extension's own client API, so it only answers a request
// that looks like the extension:
//   - a Spotify-desktop User-Agent (a plain curl UA gets 418 "internal client
//     API"),
//   - `SpicyLyrics-Version` matching a released extension version ("unknown" is
//     a 400),
//   - `SpicyLyrics-WebAuth: Bearer <spotify token>` (without it the query
//     result comes back 401).
//
// It is a POST, and Quickshell's Requests helper is GET-only, so the singleton
// drives it with a curl Process. The reply carries SLObjPack-packed lyrics;
// this adapter returns the raw payload and Core.unpackLyrics() decodes it.

var name = "Spicy";

var HOST = "https://api.spicylyrics.org";

// Must be a released version string. Bump when the API starts refusing it.
var VERSION = "6.4.70";

var UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Spotify/1.2.0 Chrome/122.0.0.0 Safari/537.36";

function command(spotifyTrackId, token) {
    const body = JSON.stringify({
        queries: [{
            operation: "lyrics",
            variables: {
                id: spotifyTrackId,
                auth: "SpicyLyrics-WebAuth"
            }
        }],
        client: {
            version: VERSION
        }
    });
    return ["curl", "-sS", "--max-time", "15", "-X", "POST", "-H", "Content-Type: application/json", "-H", "X-mode: 2", "-H", `SpicyLyrics-Version: ${VERSION}`, "-H", `SpicyLyrics-WebAuth: Bearer ${token}`, "-H", `User-Agent: ${UA}`, "-d", body, `${HOST}/query`];
}

// The envelope holds a leading notice entry, so the result is the entry that
// actually carries one. Returns its `data` untouched: an object when the server
// answered in plain JSON, an SLObjPack array otherwise.
function parse(text) {
    let doc;
    try {
        doc = JSON.parse(text);
    } catch (e) {
        return null;
    }
    if (!Array.isArray(doc?.queries))
        return null;
    const entry = doc.queries.find(q => q && q.result);
    if (!entry || entry.result.httpStatus !== 200)
        return null;
    const data = entry.result.data;
    return data && typeof data === "object" ? data : null;
}
