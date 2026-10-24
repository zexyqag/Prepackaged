// Map packs from a build file of the Zomboid Map Index: the map mods that load, what each needs, what a pack of them
// holds and where its maps overlap, the best maps to add for a list of priorities, and pack files.

export const VANILLA_MAP = 'Muldraugh, KY';
export const workshopUrl = id => `https://steamcommunity.com/sharedfiles/filedetails/?id=${id}`;

// What a suggestion can aim at, in the order picked, each one breaking the ties of those before it: per map mod in the
// pack (mod) or per Workshop item in it (item), tile packs included.
export const CRITERIA = {
  maps: { label: 'More maps', mod: () => 1 },
  fewerMaps: { label: 'Fewer maps', mod: () => -1 },
  cells: { label: 'More cells', mod: m => m.cells },
  newCells: { label: 'More cells beyond the vanilla map', mod: m => m.newCells },
  spawns: { label: 'More spawn points', mod: m => m.spawnPoints },
  subscribers: { label: 'More subscribers', item: i => i.workshop?.subscribers ?? 0 },
  // Above Steam's middle score counts for, below it against.
  rating: { label: 'Better rated on the Workshop', item: i => (i.workshop?.score ?? 0.5) - 0.5 },
  items: { label: 'Fewer Workshop items', item: () => -1 },
  size: { label: 'Smaller download', item: i => -(i.workshop?.fileSize ?? 0) },
};

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
// first, then the lowest Workshop ID), the mod IDs no item provides, and what keeps it out of suggestions.
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
  const candidates = [];
  for (const mod of mods.values()) {
    // Its own cells: those of the mods it needs count for them.
    const own = new Set(mod.maps.flatMap(m => [...m.cellSet]));
    if (!mod.loads || own.size === 0) continue;
    // The mods it needs, in load order (what each requires first), itself last.
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
      order.push(m);
    };
    visit(mod);
    const together = empty();
    const fits = order.every(m => {
      const ok = clash([m], together) === null;
      add([m], together);
      return ok;
    });
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

// Why a mod can't go with the mods already chosen: a map of a different mod on one of its cells, a mod of the same
// ID, or one it or they say they are incompatible with. Null when it can.
function clash(order, chosen) {
  for (const m of order) {
    if (chosen.mods.has(m.key)) continue;
    const same = chosen.ids.get(m.id);
    if (same) return { kind: 'id', with: same };
    for (const id of m.incompatible) if (chosen.ids.has(id)) return { kind: 'incompatible', with: chosen.ids.get(id) };
    const against = chosen.incompatible.get(m.id);
    if (against?.length) return { kind: 'incompatible', with: against[0] };
    for (const map of m.maps) for (const cell of map.cellSet) if (chosen.cells.has(cell)) return { kind: 'cells', with: chosen.cells.get(cell) };
  }
  return null;
}

// Adds the mods not chosen yet, and returns them.
function add(order, chosen) {
  const added = order.filter(m => !chosen.mods.has(m.key));
  for (const m of added) {
    chosen.mods.set(m.key, m);
    chosen.ids.set(m.id, m);
    chosen.items.set(m.item, (chosen.items.get(m.item) ?? 0) + 1);
    for (const id of m.incompatible) chosen.incompatible.set(id, [...(chosen.incompatible.get(id) ?? []), m]);
    for (const map of m.maps) for (const cell of map.cellSet) if (!chosen.cells.has(cell)) chosen.cells.set(cell, m);
  }
  return added;
}

function remove(added, chosen) {
  for (const m of added) {
    chosen.mods.delete(m.key);
    chosen.ids.delete(m.id);
    const left = chosen.items.get(m.item) - 1;
    if (left) chosen.items.set(m.item, left);
    else chosen.items.delete(m.item);
    for (const id of m.incompatible) chosen.incompatible.set(id, chosen.incompatible.get(id).filter(o => o !== m));
    for (const map of m.maps) for (const cell of map.cellSet) if (chosen.cells.get(cell) === m) chosen.cells.delete(cell);
  }
}

const empty = () => ({ mods: new Map(), ids: new Map(), items: new Map(), incompatible: new Map(), cells: new Map() });

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

// The best map mods to add to a pack for priorities (keys of CRITERIA) within limits (noTilePacks, noZoneStops,
// withSpawns, maxItems): the map mods of pinned (keys) stay, with what they need, whether or not they overlap, and
// those of leftOut never come in. Returns the pack's map mods, pinned first, per map mod left out why, and whether the
// search checked every set it had to within its budget, of map mods its steps look at (else the pack is the best it
// found).
export function suggest(read, { priorities, limits = {}, pinned = [], leftOut = new Set(), budget = BUDGET }) {
  const criteria = priorities.map(name => CRITERIA[name]);
  const modValue = m => criteria.map(c => (c.mod ? c.mod(m) : 0));
  const itemValue = item => criteria.map(c => (c.item ? c.item(item) : 0));
  const base = empty();
  for (const key of pinned) add(read.byKey.get(key).order, base);
  const reasons = new Map();
  for (const c of read.candidates) {
    if (base.mods.has(c.key)) continue;
    let why = null;
    if (leftOut.has(c.key)) why = { kind: 'leftOut' };
    else if (c.problem) why = { kind: 'problem', text: c.problem };
    else if (limits.noTilePacks && c.tilePacks.length) why = { kind: 'tilePacks', items: c.tilePacks };
    else if (limits.noZoneStops && c.zoneStops.length) why = { kind: 'zones', stops: c.zoneStops };
    else if (limits.withSpawns && c.spawnPoints === 0) why = { kind: 'noSpawns' };
    else {
      const against = clash(c.order, base);
      if (against) why = { ...against, pinned: true };
    }
    if (why) reasons.set(c.key, why);
  }
  // A map mod that needs one left out is left out too.
  for (let more = true; more;) {
    more = false;
    for (const c of read.candidates) {
      const out = !reasons.has(c.key) && !base.mods.has(c.key) && c.order.find(m => m !== c && reasons.has(m.key));
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
  // Two map mods conflict when one, with what it needs, clashes with the other and what it needs. Only map mods that
  // need mods touching each other (on a cell, by ID or incompatible) are checked. Map mods go in one part when they
  // conflict, when one needs another or when they share an item, and with an item limit all go in one, so the parts
  // can be solved one by one.
  const conflicts = conflictsOf(usable);
  const part = usable.map((_, i) => i);
  const root = i => (part[i] === i ? i : (part[i] = root(part[i])));
  const join = (i, j) => { part[root(i)] = root(j); };
  const byItem = new Map();
  usable.forEach((c, i) => {
    for (const j of conflicts[i]) join(i, j);
    if (limits.maxItems) join(i, 0);
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
    const best = bestOf(members, { usable, own, hope, conflicts, blocked, at, itemValue, chosen, steps, maxItems: limits.maxItems, size: criteria.length });
    for (const i of best) add(usable[i].order, chosen);
    picked.push(...best);
  }
  for (const c of usable) {
    if (chosen.mods.has(c.key)) continue;
    const why = clash(c.order, chosen);
    if (why) reasons.set(c.key, why);
    else if (limits.maxItems && chosen.items.size + c.order.filter(m => !chosen.items.has(m.item)).length > limits.maxItems) reasons.set(c.key, { kind: 'maxItems' });
    else reasons.set(c.key, { kind: 'noGain' });
  }
  const added = read.candidates.filter(c => chosen.mods.has(c.key) && !pinned.includes(c.key)).map(c => c.key);
  return { keys: [...pinned, ...added], reasons, complete: steps.complete };
}

// Per map mod of candidates, the indices of those it conflicts with.
function conflictsOf(candidates) {
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
  return candidates.map((c, i) => {
    const near = new Set();
    for (const m of c.order) for (const o of touches.get(m)) for (const j of users.get(o)) if (j !== i) near.add(j);
    return new Set([...near].filter(j => clash(c.order, alone[j]) !== null || clash(candidates[j].order, alone[i]) !== null));
  });
}

// The best set of the map mods members (indices into usable) to add to chosen, by value vectors: a map mod brings
// the map mods it needs and its items. Branch and bound in order of value, each map mod in or out: a branch ends where
// even the most hopeful map mod of each group that all conflict with each other (cliques, made greedily) couldn't beat
// the best set found. Under an item limit the new items bound it too: no more of them than are left, each worth at
// most its own value and that of the map mods in it, besides the map mods in items already in; the lower bound counts.
// A map mod left out stays out, also of what later ones bring, so the bounds hold. The search starts from the set that
// taking each map mod in order when it gains makes (under an item limit, or in order of value per new item when that
// does better), and stops when the budget runs out.
function bestOf(members, { usable, own, hope, conflicts, blocked, at, itemValue, chosen, steps, maxItems, size }) {
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
    if (!maxItems) return false;
    let old = value;
    const worth = new Map();
    for (const i of left) {
      const item = usable[i].item;
      if (chosen.items.has(item)) old = plus(old, ownGain.get(i));
      else worth.set(item, plus(worth.get(item) ?? itemGain.get(item), ownGain.get(i)));
      for (const m of usable[i].order) if (!chosen.items.has(m.item) && !worth.has(m.item)) worth.set(m.item, itemGain.get(m.item));
    }
    for (const v of [...worth.values()].sort((a, b) => compare(b, a)).slice(0, Math.max(0, maxItems - chosen.items.size))) old = plus(old, v);
    return compare(old, best.value) <= 0;
  };
  // What adding map mod i brings: the map mods it needs that aren't in yet, its new items, whether it can go in, and
  // the gain.
  const adding = i => {
    const brought = usable[i].order.filter(m => !chosen.mods.has(m.key));
    const map = brought.filter(m => at.has(m.key)).map(m => at.get(m.key));
    const newItems = [...new Set(brought.map(m => m.item))].filter(item => !chosen.items.has(item));
    const can = map.every(j => state.get(j) !== 'out' && fits(j)) && !(maxItems && chosen.items.size + newItems.length > maxItems);
    const gain = newItems.reduce((sum, item) => plus(sum, itemValue(item)), map.reduce((sum, j) => plus(sum, own[j]), zero(size)));
    return { map, newItems, can, gain };
  };
  const greedy = sequence => {
    const added = [];
    let value = zero(size);
    for (const i of sequence) {
      if (state.has(i)) continue;
      const { map, can, gain } = adding(i);
      if (!can || compare(gain, zero(size)) <= 0) continue;
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
  if (maxItems) {
    const cost = new Map(order.map(i => [i, new Set(usable[i].order.map(m => m.item).filter(item => !chosen.items.has(item))).size]));
    const scale = (v, by) => v.map(x => x * by);
    const thrifty = greedy([...order].sort((a, b) => compare(scale(hope[b], cost.get(a)), scale(hope[a], cost.get(b)))));
    if (compare(thrifty.value, best.value) > 0) best = thrifty;
  }
  const step = (k, value) => {
    if (steps.left <= 0) {
      steps.complete = false;
      return;
    }
    steps.left -= 1 + order.length - k;
    if (beaten(k, value)) return;
    if (k === order.length) {
      best = { value, set: [...inSet] };
      return;
    }
    const i = order[k];
    if (state.get(i) === 'in') return step(k + 1, value);
    const { map, newItems, can, gain } = adding(i);
    const take = () => {
      const added = add(usable[i].order, chosen);
      for (const j of map) enter(j);
      step(k + 1, plus(value, gain));
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

// A pack of map mods in Map= order, each after the map mods it needs: its mods in load order (each after what it
// needs), its items, its map folders, its cells, where its maps overlap (the earlier one wins), and its problems: mod
// IDs no item in the index has, and mods that clash by ID or say they are incompatible.
export function describePack(read, keys) {
  const pack = [];
  for (const key of keys) {
    for (const m of read.byKey.get(key).order) {
      const c = read.byKey.get(m.key);
      if (c && !pack.includes(c)) pack.push(c);
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
    for (const [winner, cells] of lost) overlaps.push({ winner, loser: c, cells });
  }
  const clashes = [];
  const ids = new Map();
  for (const m of mods) {
    if (ids.has(m.id)) clashes.push({ kind: 'id', mods: [ids.get(m.id), m] });
    else ids.set(m.id, m);
  }
  for (const m of mods) for (const id of m.incompatible) if (ids.has(id) && ids.get(id) !== m) clashes.push({ kind: 'incompatible', mods: [m, ids.get(id)] });
  const cells = new Set(owner.keys());
  return {
    pack, mods, overlaps, clashes,
    items: [...new Set(mods.map(m => m.item))],
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
