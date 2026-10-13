import "scripts/fzf.js" as Fzf
import "scripts/fuzzysort.js" as Fuzzy
import QtQuick
import Quickshell

Singleton {
    required property list<QtObject> list
    property string key: "name"
    property bool useFuzzy: false
    property var extraOpts: ({})

    // Extra stuff for fuzzy
    property list<string> keys: [key]
    property list<real> weights: [1]

    // Built on first query, not at singleton creation. Dropped when the list changes.
    property var fzf: null
    property var fuzzyPrepped: []

    onListChanged: {
        fzf = null;
        fuzzyPrepped = [];
    }

    function ensureIndex(): void {
        if (useFuzzy) {
            if (fuzzyPrepped.length === list.length && list.length > 0)
                return;
            fuzzyPrepped = list.map(e => {
                const obj = {
                    _item: e
                };
                for (const k of keys)
                    obj[k] = Fuzzy.prepare(e[k]);
                return obj;
            });
        } else if (!fzf) {
            fzf = new Fzf.Finder(list, Object.assign({
                selector
            }, extraOpts));
        }
    }

    function transformSearch(search: string): string {
        return search;
    }

    function selector(item: var): string {
        // Only for fzf
        return item[key];
    }

    function query(search: string): var {
        search = transformSearch(search.trim().replace(/\s+/g, " "));
        if (!search)
            return [...list];

        ensureIndex();

        if (useFuzzy)
            return Fuzzy.go(search, fuzzyPrepped, Object.assign({
                all: true,
                keys,
                scoreFn: r => weights.reduce((a, w, i) => a + r[i].score * w, 0)
            }, extraOpts)).map(r => r.obj._item);

        return fzf.find(search).sort((a, b) => {
            if (a.score === b.score)
                return selector(a.item).trim().length - selector(b.item).trim().length;
            return b.score - a.score;
        }).map(r => r.item);
    }
}
