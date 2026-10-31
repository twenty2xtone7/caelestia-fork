pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Caelestia
import Caelestia.Config
import Caelestia.I18n
import Caelestia.Services
import qs.components.misc

Singleton {
    id: root

    readonly property list<MprisPlayer> list: Mpris.players.values
    // A player is "real" when it reports both a title and an artist. The local
    // "Caelestia Music" MPRIS stub reports title "Unknown" with no artist, and
    // used to win over the player the user was actually listening to.
    function hasMeta(player: MprisPlayer): bool {
        return (player?.trackTitle ?? "") !== "" && (player?.trackArtist ?? "") !== "";
    }

    // Prefer the configured default player whenever it exists. A background
    // video in Firefox and the music in Spotify both report isPlaying, and
    // Spotify's metadata blanks out for a moment on track change; both made
    // `active` flap, which re-requested lyrics on every flip and kept
    // Lyrics.loading stuck at true.
    readonly property MprisPlayer active: {
        const preferred = list.find(p => getIdentity(p).toLowerCase() === GlobalConfig.services.defaultPlayer.toLowerCase());
        return props.manualActive ?? preferred ?? list.find(p => p.isPlaying && hasMeta(p)) ?? list.find(p => hasMeta(p)) ?? list[0] ?? null;
    }
    property alias manualActive: props.manualActive

    // Dedup key for progressive metadata (e.g. mpv-mpris/yt-dlp player fills title then artist later).
    property string lastNowPlayingKey: ""

    function getIdentity(player: MprisPlayer): string {
        if (!player)
            return "";
        const alias = GlobalConfig.services.playerAliases.values.find(a => a.from === player.identity);
        return alias?.to ?? player.identity;
    }

    function getArtUrl(player: MprisPlayer): string {
        if (!player)
            return "";
        if (player.trackArtUrl)
            return player.trackArtUrl;

        const url = player.metadata["xesam:url"] ?? "";
        if (url.startsWith("https://www.youtube.com/watch")) {
            // Fallback for youtube
            const id = url.match(/[?&]v=([\w-]{11})/)?.[1];
            return id ? `https://img.youtube.com/vi/${id}/hqdefault.jpg` : "";
        }
        return "";
    }

    // Quickshell only emits postTrackChanged when trackid/url/title change, so late
    // artist updates (common with mpv-mpris + yt-dlp player) never retrigger it. Watch
    // title/artist too and toast once both are usable.
    function maybeToastNowPlaying(): void {
        if (!GlobalConfig.utilities.toasts.nowPlaying)
            return;

        const player = root.active;
        if (!player)
            return;

        const title = player.trackTitle ?? "";
        const artist = player.trackArtist ?? "";
        if (!title || !artist)
            return;

        const key = `${getIdentity(player)}\0${player.uniqueId}\0${title}\0${artist}`;
        if (key === lastNowPlayingKey)
            return;

        lastNowPlayingKey = key;
        Toaster.toast(Tr.tr("Now playing"), Tr.trCtx("%1 - %2", "track artist and title").arg(artist).arg(title), "music_note");
    }

    property string lastLyricsKey: ""

    function syncLyrics(): void {
        const p = root.active;
        const artist = p?.trackArtist ?? "";
        const title = p?.trackTitle ?? "";

        if (!p) {
            if (lastLyricsKey !== "") {
                lastLyricsKey = "";
                Lyrics.clearTrack();
            }
            return;
        }

        // MPRIS blanks title/artist for a moment while a track changes. Treat
        // that as "keep what we have", not as "clear the lyrics", or every
        // track switch clears and re-requests twice.
        if (!hasMeta(p))
            return;

        const key = `${artist}\0${title}`;
        if (key === lastLyricsKey)
            return;

        lastLyricsKey = key;
        Lyrics.setTrack(artist, title, p.trackAlbum ?? "", p.length ?? 0);
    }

    onActiveChanged: {
        lastNowPlayingKey = "";
        syncLyrics();
    }

    Connections {
        ignoreUnknownSignals: true
        target: root.active

        function onTrackTitleChanged(): void {
            root.syncLyrics();
        }

        function onTrackArtistChanged(): void {
            root.syncLyrics();
        }

        function onPostTrackChanged(): void {
            root.syncLyrics();
        }
    }

    Connections {
        function onPostTrackChanged(): void {
            root.maybeToastNowPlaying();
        }

        function onTrackTitleChanged(): void {
            root.maybeToastNowPlaying();
        }

        function onTrackArtistChanged(): void {
            root.maybeToastNowPlaying();
        }

        target: root.active
    }

    PersistentProperties {
        id: props

        property MprisPlayer manualActive

        reloadableId: "players"
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaToggle"
        description: "Toggle media playback"
        onPressed: {
            const active = root.active;
            if (active && active.canTogglePlaying)
                active.togglePlaying();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaPrev"
        description: "Previous track"
        onPressed: {
            const active = root.active;
            if (active && active.canGoPrevious)
                active.previous();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaNext"
        description: "Next track"
        onPressed: {
            const active = root.active;
            if (active && active.canGoNext)
                active.next();
        }
    }

    // qmllint disable unresolved-type
    CustomShortcut {
        // qmllint enable unresolved-type
        name: "mediaStop"
        description: "Stop media playback"
        onPressed: root.active?.stop()
    }

    IpcHandler {
        function getActive(prop: string): string {
            const active = root.active;
            return active ? active[prop] ?? "Invalid property" : "No active player";
        }

        function list(): string {
            return root.list.map(p => root.getIdentity(p)).join("\n");
        }

        function play(): void {
            const active = root.active;
            if (active?.canPlay)
                active.play();
        }

        function pause(): void {
            const active = root.active;
            if (active?.canPause)
                active.pause();
        }

        function playPause(): void {
            const active = root.active;
            if (active?.canTogglePlaying)
                active.togglePlaying();
        }

        function previous(): void {
            const active = root.active;
            if (active?.canGoPrevious)
                active.previous();
        }

        function next(): void {
            const active = root.active;
            if (active?.canGoNext)
                active.next();
        }

        function stop(): void {
            root.active?.stop();
        }

        target: "mpris"
    }
}
