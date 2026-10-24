// Map packs from a build file of the Zomboid Map Index: the map mods that load, what each needs, what a pack of them
// holds and where its maps overlap, the best maps to add for a list of priorities, and pack files.

export const VANILLA_MAP = 'Muldraugh, KY';
export const workshopUrl = id => `https://steamcommunity.com/sharedfiles/filedetails/?id=${id}`;

// Steam's score of a Workshop item from its up and down votes, which trusts more votes more, or null without votes.
export function rating(item) {
  const w = item.workshop;
  return w && w.votesUp + w.votesDown > 0 ? w.score : null;
}

const bytes = item => item.workshop?.fileSize ?? 0;
const hasMaps = item => item.mods.some(m => m.loads && m.maps.length > 0);

// What a suggestion can aim at: in order, each one breaking the ties of those before it, or weighed into one score.
// Each counts per map mod in the pack (mod) or per Workshop item in it (item), tile packs included.
export const CRITERIA = {
  maps: { label: 'More maps', mod: () => 1 },
  fewerMaps: { label: 'Fewer maps', mod: () => -1 },
  cells: { label: 'More cells', mod: m => m.cells },
  newCells: { label: 'More cells beyond the vanilla map', mod: m => m.newCells },
  spawns: { label: 'More spawn points', mod: m => m.spawnPoints },
  subscribers: { label: 'More subscribers', item: i => i.workshop?.subscribers ?? 0 },
  // Above Steam's middle score counts for, below it against.
  rating: { label: 'Better rated on the Workshop', item: i => (rating(i) ?? 0.5) - 0.5 },
  items: { label: 'Fewer Workshop items', item: () => -1 },
  tilePacks: { label: 'Fewer tile packs', item: i => (hasMaps(i) ? 0 : -1) },
  size: { label: 'Smaller download', item: i => -bytes(i) },
};

// One criterion for weights (keys of CRITERIA, any number): each criterion counts as its share of the largest value,
// for or against, that it has in the index, times its weight; in millionths, so that sums are exact.
export function scoring(read, weights) {
  const used = Object.entries(weights).filter(([, w]) => w > 0).map(([name, w]) => [CRITERIA[name], w]);
  const items = [...new Set(read.candidates.flatMap(c => c.order.map(m => m.item)))];
  const largest = used.map(([c]) => Math.max(0, ...(c.mod ? read.candidates.map(c.mod) : items.map(c.item)).map(Math.abs)));
  const score = (kind, x) => Math.round(1e6 * used.reduce((sum, [c, w], k) => (c[kind] && largest[k] ? sum + (w * c[kind](x)) / largest[k] : sum), 0));
  return { mod: m => score('mod', m), item: i => score('item', i) };
}

// Per map mod, the score of a pack of it and what it needs, for weights.
export function scores(read, weights) {
  const { mod, item } = scoring(read, weights);
  return new Map(read.candidates.map(c => [c.key,
    (c.order.filter(m => read.byKey.has(m.key)).reduce((sum, m) => sum + mod(read.byKey.get(m.key)), 0)
      + [...new Set(c.order.map(m => m.item))].reduce((sum, i) => sum + item(i), 0)) / 1e6]));
}

export const PRESETS = {
  maps: { label: 'Most maps', priorities: ['maps', 'cells'], limits: {} },
  plain: { label: 'Most maps without tile packs', priorities: ['maps', 'cells'], limits: { noTilePacks: true } },
  area: { label: 'Most cells with the fewest maps', priorities: ['cells', 'fewerMaps'], limits: {} },
};

const cellKey = (x, y) => `${x},${y}`;
function runCells(runs) {
  const cells = new Set();
  for (const [y, from, to] of runs) for (let x = from; x <= to; x++) cells.add(cellKey(x, y));
  return cells;
}

// Every mod of the build by "<item>/<folder>", with its item and maps, and the map mods: those that load and have
// cells, each with what it needs (the mods it requires, through the items that provide each mod ID: its own item
// first, then the lowest Workshop ID; and the map mod of each item its item requires on the Workshop, when that item
// has one), the map mods it builds on among them, the mod IDs no item provides, and what keeps it out of suggestions.
export function readBuild(build) {
  const vanillaRuns = build.vanilla.find(m => m.name === VANILLA_MAP)?.cells ?? [];
  const vanilla = runCells(vanillaRuns);
  const items = new Map(build.items.map(item => [item.id, item]));
  const maps = build.maps.map((m, index) => ({ ...m, index, cellSet: runCells(m.cells) }));
  const mods = new Map();
  for (const item of build.items) {
    for (const mod of item.mods) {
      const key = `${item.id}/${mod.folder}`;
      mods.set(key, { ...mod, key, item, maps: mod.maps.map(i => maps[i]) });
    }
  }
  const byId = (id, preferred) => {
    const from = [...(build.providers[id] ?? [])].sort((a, b) => (a === preferred ? -1 : b === preferred ? 1 : Number(a) - Number(b)));
    for (const itemId of from) {
      const mod = items.get(itemId)?.mods.find(m => m.loads && m.id === id);
      if (mod) return mods.get(`${itemId}/${mod.folder}`);
    }
    return null;
  };
  const isMap = m => m.loads && m.maps.some(map => map.cells.length);
  const mapsOf = new Map();
  for (const m of mods.values()) if (isMap(m)) mapsOf.set(m.item.id, [...(mapsOf.get(m.item.id) ?? []), m]);
  // The mods each map mod needs, in load order (what each requires first), itself last.
  const needs = new Map();
  for (const mod of mods.values()) {
    if (!isMap(mod)) continue;
    const order = [];
    const missing = [];
    const seen = new Set();
    const visit = m => {
      if (seen.has(m.key)) return;
      seen.add(m.key);
      for (const id of m.require) {
        const found = byId(id, m.item.id);
        if (found) visit(found);
        else if (!missing.includes(id)) missing.push(id);
      }
      for (const id of m.item.workshop?.requires ?? []) if (id !== m.item.id && mapsOf.get(id)?.length === 1) visit(mapsOf.get(id)[0]);
      order.push(m);
    };
    visit(mod);
    needs.set(mod, { order, missing });
    mod.buildsOn = new Set(order.filter(m => m !== mod && isMap(m)).map(m => m.key));
  }
  const candidates = [];
  for (const [mod, { order, missing }] of needs) {
    // Its own cells: those of the mods it needs count for them.
    const own = new Set(mod.maps.flatMap(m => [...m.cellSet]));
    const fits = clash(order, empty()) === null;
    const tilePacks = [...new Set(order.filter(m => m.item !== mod.item && !m.item.mods.some(o => o.loads && o.maps.length > 0)).map(m => m.item))];
    let problem = null;
    if (missing.length) problem = `needs ${missing.join(', ')}, which no item in the index has`;
    else if (!fits) problem = "can't go together with the mods it needs";
    else if (/[;\\]/.test(order.map(m => m.id).join(''))) problem = "has a mod ID with a ; or a \\, which a pack can't list";
    else if (mod.maps.some(m => m.name.includes(';'))) problem = "has a map folder with a ;, which Map= can't list";
    candidates.push({
      ...mod, order, missing, problem, tilePacks, cells: own.size, newCells: [...own].filter(c => !vanilla.has(c)).length,
      spawnPoints: mod.maps.reduce((sum, m) => sum + (m.spawns ?? 0), 0),
      zoneStops: mod.maps.flatMap(m => Object.entries(m.zones).filter(([, line]) => line !== null).map(([file, line]) => ({ map: m.name, file, line }))),
    });
  }
  candidates.sort((a, b) => Number(a.item.id) - Number(b.item.id) || (a.folder < b.folder ? -1 : 1));
  return { gameVersion: build.gameVersion, vanilla, vanillaRuns, mods, candidates, byKey: new Map(candidates.map(c => [c.key, c])) };
}

// Whether mods may share a cell: when one of them, a patch, builds on all the others.
const share = mods => mods.length < 2 || mods.some(top => mods.every(m => m === top || top.buildsOn?.has(m.key)));

// Why mods (with each other) can't go with the mods already chosen: a mod of the same ID, one it or they say they are
// incompatible with, or maps of mods that share a cell, unless one builds on the others. Null when they can.
function clash(order, chosen) {
  const fresh = order.filter(m => !chosen.mods.has(m.key));
  const ids = new Map();
  const cells = new Map();
  for (const m of fresh) {
    const same = chosen.ids.get(m.id) ?? ids.get(m.id);
    if (same) return { kind: 'id', with: same };
    ids.set(m.id, m);
    for (const map of m.maps) for (const cell of map.cellSet) if (!cells.get(cell)?.includes(m)) cells.set(cell, [...(cells.get(cell) ?? []), m]);
  }
  for (const m of fresh) {
    for (const id of m.incompatible) if (chosen.ids.has(id) || ids.has(id)) return { kind: 'incompatible', with: chosen.ids.get(id) ?? ids.get(id) };
    const against = chosen.incompatible.get(m.id);
    if (against?.length) return { kind: 'incompatible', with: against[0] };
  }
  let found = null;
  for (const [cell, mods] of cells) {
    const here = [...(chosen.cells.get(cell) ?? []), ...mods];
    if (share(here)) continue;
    found ??= { kind: 'cells', with: here.find(m => !mods.includes(m)) ?? here[0], at: [] };
    found.at.push(cell);
  }
  return found;
}

// Whether a clash is only on cells where a patch could go: per cell, a map mod of patches (by cell) that builds on
// all the mods there, those chosen and those of order.
function curable(found, order, chosen, patches) {
  return found.kind === 'cells' && found.at.every(cell => {
    const here = [...(chosen.cells.get(cell) ?? []), ...order.filter(m => !chosen.mods.has(m.key) && m.maps.some(map => map.cellSet.has(cell)))];
    return (patches.get(cell) ?? []).some(p => here.every(m => m.key === p.key || p.buildsOn.has(m.key)));
  });
}

// Adds the mods not chosen yet, and returns them.
function add(order, chosen) {
  const added = order.filter(m => !chosen.mods.has(m.key));
  for (const m of added) {
    chosen.mods.set(m.key, m);
    chosen.ids.set(m.id, m);
    if (!chosen.items.has(m.item)) chosen.bytes += bytes(m.item);
    chosen.items.set(m.item, (chosen.items.get(m.item) ?? 0) + 1);
    for (const id of m.incompatible) chosen.incompatible.set(id, [...(chosen.incompatible.get(id) ?? []), m]);
    for (const map of m.maps) for (const cell of map.cellSet) if (!chosen.cells.get(cell)?.includes(m)) chosen.cells.set(cell, [...(chosen.cells.get(cell) ?? []), m]);
  }
  return added;
}

function remove(added, chosen) {
  for (const m of added) {
    chosen.mods.delete(m.key);
    chosen.ids.delete(m.id);
    const left = chosen.items.get(m.item) - 1;
    if (left) chosen.items.set(m.item, left);
    else {
      chosen.items.delete(m.item);
      chosen.bytes -= bytes(m.item);
    }
    for (const id of m.incompatible) chosen.incompatible.set(id, chosen.incompatible.get(id).filter(o => o !== m));
    for (const map of m.maps) {
      for (const cell of map.cellSet) {
        const left = chosen.cells.get(cell)?.filter(o => o !== m) ?? [];
        if (left.length) chosen.cells.set(cell, left);
        else chosen.cells.delete(cell);
      }
    }
  }
}

const empty = () => ({ mods: new Map(), ids: new Map(), items: new Map(), bytes: 0, incompatible: new Map(), cells: new Map() });

// Values are vectors, one number per priority, compared in order.
const zero = n => new Array(n).fill(0);
const plus = (a, b) => a.map((v, i) => v + b[i]);
const positive = a => a.map(v => Math.max(0, v));
function compare(a, b) {
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
  return 0;
}

// Under a second of search in a browser.
const BUDGET = 1000000;

// The best map mods to add to a pack for priorities (keys of CRITERIA, in order) or else weights (see scoring) within
// limits (noTilePacks, noZoneStops, withSpawns, minRating: the percent of Steam's score a map mod's own item has at
// least, maxItems, maxBytes: the most the pack's items download): the map mods of pinned (keys) stay, with what they
// need, whether or not they overlap, and those of leftOut never come in. Returns the pack's map mods, pinned first,
// per map mod left out why, and whether the search checked every set it had to within its budget, of map mods its
// steps look at (else the pack is the best it found).
export function suggest(read, { priorities, weights, limits = {}, pinned = [], leftOut = new Set(), budget = BUDGET }) {
  const criteria = weights ? [scoring(read, weights)] : priorities.map(name => CRITERIA[name]);
  const modValue = m => criteria.map(c => (c.mod ? c.mod(m) : 0));
  const itemValue = item => criteria.map(c => (c.item ? c.item(item) : 0));
  const base = empty();
  for (const key of pinned) add(read.byKey.get(key).order, base);
  // Per cell, the map mods on it that build on others.
  const patches = new Map();
  for (const c of read.candidates) if (c.buildsOn.size) for (const map of c.maps) for (const cell of map.cellSet) patches.set(cell, [...(patches.get(cell) ?? []), c]);
  const reasons = new Map();
  for (const c of read.candidates) {
    if (base.mods.has(c.key)) continue;
    let why = null;
    if (leftOut.has(c.key)) why = { kind: 'leftOut' };
    else if (c.problem) why = { kind: 'problem', text: c.problem };
    else if (limits.noTilePacks && c.tilePacks.length) why = { kind: 'tilePacks', items: c.tilePacks };
    else if (limits.noZoneStops && c.zoneStops.length) why = { kind: 'zones', stops: c.zoneStops };
    else if (limits.withSpawns && c.spawnPoints === 0) why = { kind: 'noSpawns' };
    else if (limits.minRating && !(rating(c.item) * 100 >= limits.minRating)) why = { kind: 'rating' };
    else {
      const against = clash(c.order, base);
      if (against && !curable(against, c.order, base, patches)) why = { ...against, pinned: true };
    }
    if (why) reasons.set(c.key, why);
  }
  // A map mod that needs one left out is left out too.
  for (let more = true; more;) {
    more = false;
    for (const c of read.candidates) {
      const out = !reasons.has(c.key) && !base.mods.has(c.key) && c.order.find(m => reasons.has(m.key));
      if (out) {
        reasons.set(c.key, { kind: 'needs', with: out });
        more = true;
      }
    }
  }
  const usable = read.candidates.filter(c => !reasons.has(c.key) && !base.mods.has(c.key));
  const n = usable.length;
  const at = new Map(usable.map((c, i) => [c.key, i]));
  const own = usable.map(modValue);
  // What adding a map mod with what it needs could bring at most: its own value and the gains of its items.
  const hope = usable.map((c, i) => [...new Set(c.order.map(m => m.item))].reduce((sum, item) => plus(sum, itemValue(item).map(v => Math.max(0, v))), own[i]));
  // Two map mods meet when one, with what it needs, clashes with the other and what it needs, and conflict when no
  // patch could make them go together. Only map mods that need mods touching each other (on a cell, by ID or
  // incompatible) are checked. Map mods go in one part when they meet, when one needs another or when they share an
  // item, and with an item or download limit all go in one, so the parts can be solved one by one.
  const { meets, hard: conflicts } = conflictsOf(usable, patches);
  const part = usable.map((_, i) => i);
  const root = i => (part[i] === i ? i : (part[i] = root(part[i])));
  const join = (i, j) => { part[root(i)] = root(j); };
  const byItem = new Map();
  usable.forEach((c, i) => {
    for (const j of meets[i]) join(i, j);
    if (limits.maxItems || limits.maxBytes) join(i, 0);
    for (const m of c.order) {
      if (at.has(m.key)) join(i, at.get(m.key));
      if (byItem.has(m.item)) join(i, byItem.get(m.item));
      else byItem.set(m.item, i);
    }
  });
  const parts = new Map();
  for (let i = 0; i < n; i++) parts.set(root(i), [...(parts.get(root(i)) ?? []), i]);
  const chosen = base;
  const picked = [];
  const steps = { left: budget, complete: true };
  const blocked = new Array(n).fill(0);
  for (const members of parts.values()) {
    const best = bestOf(members, { usable, own, hope, conflicts, blocked, at, itemValue, chosen, patches, steps, limits, size: criteria.length });
    for (const i of best) add(usable[i].order, chosen);
    picked.push(...best);
  }
  for (const c of usable) {
    if (chosen.mods.has(c.key)) continue;
    const why = clash(c.order, chosen);
    if (why) reasons.set(c.key, why);
    else {
      const newItems = [...new Set(c.order.map(m => m.item))].filter(item => !chosen.items.has(item));
      if (limits.maxItems && chosen.items.size + newItems.length > limits.maxItems) reasons.set(c.key, { kind: 'maxItems' });
      else if (limits.maxBytes && chosen.bytes + newItems.reduce((sum, item) => sum + bytes(item), 0) > limits.maxBytes) reasons.set(c.key, { kind: 'maxBytes' });
      else reasons.set(c.key, { kind: 'noGain' });
    }
  }
  const added = read.candidates.filter(c => chosen.mods.has(c.key) && !pinned.includes(c.key)).map(c => c.key);
  return { keys: [...pinned, ...added], reasons, complete: steps.complete };
}

// Per map mod of candidates, the indices of those it clashes with (meets), and of those it can never go with (hard):
// all but those that only share cells where a patch could go (see curable).
function conflictsOf(candidates, patches) {
  const alone = candidates.map(c => {
    const chosen = empty();
    add(c.order, chosen);
    return chosen;
  });
  // Per mod they need, the map mods that need it, and the mods it touches.
  const users = new Map();
  candidates.forEach((c, i) => {
    for (const m of c.order) {
      if (!users.has(m)) users.set(m, []);
      users.get(m).push(i);
    }
  });
  const touches = new Map([...users.keys()].map(m => [m, new Set()]));
  const together = (list, m) => {
    for (const o of list) {
      if (o === m) continue;
      touches.get(m).add(o);
      touches.get(o).add(m);
    }
    list.push(m);
  };
  const onCell = new Map();
  const withId = new Map();
  for (const m of users.keys()) {
    for (const cell of new Set(m.maps.flatMap(map => [...map.cellSet]))) {
      if (!onCell.has(cell)) onCell.set(cell, []);
      together(onCell.get(cell), m);
    }
    if (!withId.has(m.id)) withId.set(m.id, []);
    together(withId.get(m.id), m);
  }
  for (const m of users.keys()) {
    for (const id of m.incompatible) {
      for (const o of withId.get(id) ?? []) {
        if (o === m) continue;
        touches.get(m).add(o);
        touches.get(o).add(m);
      }
    }
  }
  const meets = candidates.map(() => new Set());
  const hard = candidates.map(() => new Set());
  candidates.forEach((c, i) => {
    const near = new Set();
    for (const m of c.order) for (const o of touches.get(m)) for (const j of users.get(o)) if (j !== i) near.add(j);
    for (const j of near) {
      const one = clash(c.order, alone[j]);
      const other = clash(candidates[j].order, alone[i]);
      if (!one && !other) continue;
      meets[i].add(j);
      if ((one && !curable(one, c.order, alone[j], patches)) || (other && !curable(other, candidates[j].order, alone[i], patches))) hard[i].add(j);
    }
  });
  return { meets, hard };
}

// The best set of the map mods members (indices into usable) to add to chosen, by value vectors: a map mod brings
// the map mods it needs and its items. Branch and bound in order of value, each map mod in or out: a branch ends where
// even the most hopeful map mod of each group that all conflict with each other (cliques, made greedily) couldn't beat
// the best set found. Under an item or download limit the new items bound it too, each worth at most its own value and
// that of the map mods in it, besides the map mods in items already in: under an item limit no more of them than are
// left, under a download limit per value the most of each that fits in what is left, a part of the last one included;
// the lowest bound counts. Whether a map mod can go in is checked against the set as it is, as a patch can make map
// mods that share cells go together. A map mod left out stays out, also of what later ones bring, so the bounds hold.
// The search starts from the set that taking each map mod in order when it gains makes (under a limit, or in order of
// value per new item or byte when that does better), and stops when the budget runs out.
function bestOf(members, { usable, own, hope, conflicts, blocked, at, itemValue, chosen, patches, steps, limits, size }) {
  const { maxItems, maxBytes } = limits;
  const order = [...members].sort((a, b) => compare(hope[b], hope[a]) || Number(usable[a].item.id) - Number(usable[b].item.id));
  const cliques = [];
  const cliqueOf = new Map();
  for (const i of order) {
    // The first clique whose map mods all conflict with it: one of those it conflicts with is in it.
    let clique = null;
    for (const j of conflicts[i]) {
      const c = cliqueOf.get(j);
      if (c && (!clique || c.at < clique.at) && c.every(k => conflicts[i].has(k))) clique = c;
    }
    if (!clique) {
      clique = [];
      clique.at = cliques.length;
      cliques.push(clique);
    }
    clique.push(i);
    cliqueOf.set(i, clique);
  }
  const position = new Map(order.map((i, k) => [i, k]));
  // Per item, the map mods that need it.
  const needing = new Map();
  for (const i of order) {
    for (const item of new Set(usable[i].order.map(m => m.item))) {
      if (!needing.has(item)) needing.set(item, []);
      needing.get(item).push(i);
    }
  }
  const state = new Map();
  // The map mods in, and per map mod how many of them it conflicts with.
  const inSet = [];
  const enter = j => {
    state.set(j, 'in');
    inSet.push(j);
    for (const k of conflicts[j]) blocked[k]++;
  };
  const leave = j => {
    state.delete(j);
    inSet.splice(inSet.lastIndexOf(j), 1);
    for (const k of conflicts[j]) blocked[k]--;
  };
  let best;
  const fits = i => blocked[i] === 0;
  const ownGain = new Map(order.map(i => [i, positive(own[i])]));
  const itemGain = new Map();
  for (const i of order) for (const m of usable[i].order) if (!itemGain.has(m.item)) itemGain.set(m.item, positive(itemValue(m.item)));
  // Whether the map mods from k on can't add more than the best set has over value: the first of each clique that can
  // still go in is its most hopeful, and a clique can add nothing.
  const beaten = (from, value) => {
    const top = new Set();
    const left = [];
    let sum = value;
    for (let k = from; k < order.length; k++) {
      const i = order[k];
      if (state.has(i) || !fits(i)) continue;
      left.push(i);
      const clique = cliqueOf.get(i);
      if (top.has(clique)) continue;
      top.add(clique);
      if (compare(hope[i], zero(size)) > 0) sum = plus(sum, hope[i]);
    }
    if (compare(sum, best.value) <= 0) return true;
    if (!maxItems && !maxBytes) return false;
    let old = value;
    const worth = new Map();
    for (const i of left) {
      const item = usable[i].item;
      if (chosen.items.has(item)) old = plus(old, ownGain.get(i));
      else worth.set(item, plus(worth.get(item) ?? itemGain.get(item), ownGain.get(i)));
      for (const m of usable[i].order) if (!chosen.items.has(m.item) && !worth.has(m.item)) worth.set(m.item, itemGain.get(m.item));
    }
    if (maxItems) {
      let most = old;
      for (const v of [...worth.values()].sort((a, b) => compare(b, a)).slice(0, Math.max(0, maxItems - chosen.items.size))) most = plus(most, v);
      if (compare(most, best.value) <= 0) return true;
    }
    if (maxBytes) {
      const most = [...old];
      for (let k = 0; k < size; k++) {
        const per = item => (bytes(item) ? worth.get(item)[k] / bytes(item) : Infinity);
        let room = maxBytes - chosen.bytes;
        for (const item of [...worth.keys()].filter(item => worth.get(item)[k] > 0).sort((a, b) => per(b) - per(a) || 0)) {
          const share = bytes(item) <= room ? 1 : room / bytes(item);
          most[k] += share * worth.get(item)[k];
          room -= share * bytes(item);
          if (share < 1) break;
        }
      }
      if (compare(most, best.value) <= 0) return true;
    }
    return false;
  };
  // What adding map mod i brings: the map mods it needs that aren't in yet, its new items, whether it can go in, the
  // clash it has (it can go in with one a patch could cure, which a patch must cure before the set is done), and the
  // gain.
  const adding = i => {
    const brought = usable[i].order.filter(m => !chosen.mods.has(m.key));
    const map = brought.filter(m => at.has(m.key)).map(m => at.get(m.key));
    const newItems = [...new Set(brought.map(m => m.item))].filter(item => !chosen.items.has(item));
    const open = map.every(j => state.get(j) !== 'out') && !(maxItems && chosen.items.size + newItems.length > maxItems)
      && !(maxBytes && chosen.bytes + newItems.reduce((sum, item) => sum + bytes(item), 0) > maxBytes);
    const found = open ? clash(usable[i].order, chosen) : null;
    const can = open && (!found || curable(found, usable[i].order, chosen, patches));
    const gain = newItems.reduce((sum, item) => plus(sum, itemValue(item)), map.reduce((sum, j) => plus(sum, own[j]), zero(size)));
    return { map, newItems, can, found, gain };
  };
  const greedy = sequence => {
    const added = [];
    let value = zero(size);
    for (const i of sequence) {
      if (state.has(i)) continue;
      const { map, can, found, gain } = adding(i);
      if (!can || found || compare(gain, zero(size)) <= 0) continue;
      added.push(add(usable[i].order, chosen));
      for (const j of map) enter(j);
      value = plus(value, gain);
    }
    const found = { value, set: [...inSet] };
    for (const mods of added.reverse()) remove(mods, chosen);
    for (const j of [...inSet]) leave(j);
    return found;
  };
  best = greedy(order);
  const scale = (v, by) => v.map(x => x * by);
  for (const [limit, price] of [[maxItems, () => 1], [maxBytes, bytes]]) {
    if (!limit) continue;
    const cost = new Map(order.map(i => [i, [...new Set(usable[i].order.map(m => m.item))].filter(item => !chosen.items.has(item)).reduce((sum, item) => sum + price(item), 0)]));
    const thrifty = greedy([...order].sort((a, b) => compare(scale(hope[b], cost.get(a)), scale(hope[a], cost.get(b)))));
    if (compare(thrifty.value, best.value) > 0) best = thrifty;
  }
  // The cells that went in shared without a patch yet.
  const owed = [];
  const step = (k, value) => {
    if (steps.left <= 0) {
      steps.complete = false;
      return;
    }
    steps.left -= 1 + order.length - k;
    if (beaten(k, value)) return;
    if (k === order.length) {
      if (owed.every(cell => share(chosen.cells.get(cell)))) best = { value, set: [...inSet] };
      return;
    }
    const i = order[k];
    if (state.get(i) === 'in') return step(k + 1, value);
    const { map, newItems, can, found, gain } = adding(i);
    const take = () => {
      const added = add(usable[i].order, chosen);
      for (const j of map) enter(j);
      const cells = found?.at ?? [];
      owed.push(...cells);
      step(k + 1, plus(value, gain));
      owed.length -= cells.length;
      for (const j of map) leave(j);
      remove(added, chosen);
    };
    const skip = () => {
      state.set(i, 'out');
      step(k + 1, value);
      state.delete(i);
    };
    // A map mod that gains nothing by itself can still pay with a later one that needs a costly item it brings; it
    // is tried after the sets without it, so that it goes in only when it does better.
    if (can && compare(gain, zero(size)) > 0) {
      take();
      skip();
    } else {
      skip();
      const costly = newItems.filter(item => itemValue(item).some(v => v < 0));
      if (can && costly.some(item => (needing.get(item) ?? []).some(j => position.get(j) > k && !state.has(j)))) take();
    }
  };
  step(0, zero(size));
  return best.set;
}

// A pack of map mods in Map= order, each before the map mods it builds on, so that a patch's map wins its cells: its
// mods in load order (each after what it needs), its items, its map folders, its cells, where its maps overlap (the
// earlier one wins, a patch on purpose), and its problems: mod IDs no item in the index has, and mods that clash by ID
// or say they are incompatible.
export function describePack(read, keys) {
  const pack = [];
  for (const key of keys) {
    for (const m of [...read.byKey.get(key).order].reverse()) {
      const c = read.byKey.get(m.key);
      if (c && !pack.includes(c)) pack.push(c);
    }
  }
  // One after a map mod it builds on (and that doesn't build on it) moves just before it.
  for (let moved = true; moved;) {
    moved = false;
    for (let i = 0; i < pack.length && !moved; i++) {
      const at = pack.findIndex(o => pack[i].buildsOn.has(o.key) && !o.buildsOn.has(pack[i].key));
      if (at >= 0 && at < i) {
        pack.splice(at, 0, ...pack.splice(i, 1));
        moved = true;
      }
    }
  }
  const mods = [];
  const placed = new Set();
  for (const c of pack) {
    for (const m of c.order) {
      if (!placed.has(m.key)) {
        placed.add(m.key);
        mods.push(m);
      }
    }
  }
  const owner = new Map();
  const overlaps = [];
  for (const c of pack) {
    const lost = new Map();
    for (const map of c.maps) {
      for (const cell of map.cellSet) {
        const first = owner.get(cell);
        if (first && first !== c) lost.set(first, (lost.get(first) ?? 0) + 1);
        else if (!first) owner.set(cell, c);
      }
    }
    for (const [winner, cells] of lost) overlaps.push({ winner, loser: c, cells, patch: winner.buildsOn.has(c.key) });
  }
  const clashes = [];
  const ids = new Map();
  for (const m of mods) {
    if (ids.has(m.id)) clashes.push({ kind: 'id', mods: [ids.get(m.id), m] });
    else ids.set(m.id, m);
  }
  for (const m of mods) for (const id of m.incompatible) if (ids.has(id) && ids.get(id) !== m) clashes.push({ kind: 'incompatible', mods: [m, ids.get(id)] });
  const cells = new Set(owner.keys());
  const items = [...new Set(mods.map(m => m.item))];
  return {
    pack, mods, overlaps, clashes, items,
    // What its items download, as far as the Workshop's figures tell.
    bytes: items.reduce((sum, item) => sum + bytes(item), 0),
    maps: [...new Set(pack.flatMap(c => c.maps.map(map => map.name)))].filter(name => name !== VANILLA_MAP),
    missing: pack.filter(c => c.missing.length),
    cells: cells.size,
    newCells: [...cells].filter(cell => !read.vanilla.has(cell)).length,
  };
}

// A Prepackaged pack file for a described pack: its items, Prepackaged and its mods in load order, Map= with its map
// folders and the vanilla map last, and the same priority as MapOrder for the game's map order.
export function packText({ id, name, version = '1.0.0', comment }, pack) {
  return [
    `# ${comment}`,
    '@pack',
    `id = ${id}`,
    ...(name ? [`name = ${name}`] : []),
    `version = ${version}`,
    `WorkshopItems = ${pack.items.map(item => item.id).join(';')}`,
    `Mods = ${['Prepackaged', ...pack.mods.map(m => m.id)].join(';')}`,
    `Map = ${[...pack.maps, VANILLA_MAP].join(';')}`,
    ...(pack.maps.length ? [`MapOrder = ${pack.maps.join(';')}`] : []),
    '',
  ].join('\n');
}

// The map mods of a pack file as Prepackaged reads its @pack section (keys in any case, lists that repeat, \ dropped
// from Mods): those whose mod ID is in Mods and whose item is in WorkshopItems, in the order of MapOrder or else
// Map, then the rest; and the pack's id and name, and its mods the index doesn't know.
export function readPack(read, text) {
  const lists = { mods: [], workshopitems: [], map: [], maporder: [] };
  const single = {};
  let section = null;
  for (const raw of text.replace(/^﻿/, '').split(/\r?\n/)) {
    const line = raw.trim();
    if (line === '' || line.startsWith('#')) continue;
    if (line.startsWith('@')) {
      section = line.slice(1).trim().toLowerCase();
      continue;
    }
    const at = line.indexOf('=');
    if (section !== 'pack' || at < 0) continue;
    const key = line.slice(0, at).trim().toLowerCase();
    const value = line.slice(at + 1).trim();
    if (key in lists) lists[key].push(...(key === 'mods' ? value.replace(/\\/g, '') : value).split(';').map(v => v.trim()).filter(Boolean));
    else if (key === 'id' || key === 'name') single[key] = value;
  }
  const items = new Set(lists.workshopitems);
  const ids = new Set(lists.mods);
  const found = read.candidates.filter(c => ids.has(c.id) && items.has(c.item.id));
  const priority = lists.maporder.length ? lists.maporder : lists.map;
  const place = c => {
    const at = Math.min(...c.maps.map(map => priority.indexOf(map.name)).filter(i => i >= 0));
    return Number.isFinite(at) ? at : priority.length;
  };
  found.sort((a, b) => place(a) - place(b));
  const known = new Set([...read.mods.values()].filter(m => items.has(m.item.id)).map(m => m.id));
  return {
    id: single.id ?? null, name: single.name ?? null, keys: found.map(c => c.key),
    unknown: lists.mods.filter(id => id !== 'Prepackaged' && !known.has(id)),
  };
}

// Pack IDs Prepackaged takes.
export const validId = id => /^[A-Za-z0-9_-]{1,48}$/.test(id);
