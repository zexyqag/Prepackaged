// Map packs from a build file of the Zomboid Map Index: the map mods that load, what each needs, and the set of them
// that does best at a goal without two maps on one cell.

export const VANILLA_MAP = 'Muldraugh, KY';
export const workshopUrl = id => `https://steamcommunity.com/sharedfiles/filedetails/?id=${id}`;

// What a pack aims at: most map mods (more cells break ties), the same without items that bring no maps, or the most
// cells with the fewest map mods.
export const GOALS = {
  maps: { label: 'Most maps', weight: m => m.cells + 1e9 },
  plain: { label: 'Most maps without tile packs', weight: m => m.cells + 1e9, plain: true },
  area: { label: 'Most cells with the fewest maps', weight: m => m.cells * 1e6 - 1 },
};

const cellKey = (x, y) => `${x},${y}`;
function runCells(runs) {
  const cells = new Set();
  for (const [y, from, to] of runs) for (let x = from; x <= to; x++) cells.add(cellKey(x, y));
  return cells;
}

// Every mod of the build by "<item>/<folder>", with its item and maps, and of those that load and bring maps with cells,
// what they need: the mods they require, through the items that provide each mod ID (the mod's own item first, then the
// lowest Workshop ID), or why they can't be in a pack.
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
    const newCells = [...own].filter(c => !vanilla.has(c)).length;
    const tilePacks = [...new Set(order.filter(m => m.item !== mod.item && !m.item.mods.some(o => o.loads && o.maps.length > 0)).map(m => m.item))];
    let problem = null;
    if (missing.length) problem = `needs ${missing.join(', ')}, which no item in the index has`;
    else if (!fits) problem = "it can't go together with the mods it needs";
    else if (/[;\\]/.test(order.map(m => m.id).join(''))) problem = 'a mod ID has a ; or a \\, which a pack can\'t list';
    else if (mod.maps.some(m => m.name.includes(';'))) problem = 'a map folder has a ;, which Map= can\'t list';
    candidates.push({
      ...mod, order, cells: own.size, newCells, tilePacks, problem,
      zoneStops: mod.maps.flatMap(m => Object.entries(m.zones).filter(([, line]) => line !== null).map(([file, line]) => ({ map: m.name, file, line }))),
    });
  }
  candidates.sort((a, b) => Number(a.item.id) - Number(b.item.id) || (a.folder < b.folder ? -1 : 1));
  return { gameVersion: build.gameVersion, vanilla, vanillaRuns, mods, candidates };
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
    for (const id of m.incompatible) chosen.incompatible.set(id, [...(chosen.incompatible.get(id) ?? []), m]);
    for (const map of m.maps) for (const cell of map.cellSet) chosen.cells.set(cell, m);
  }
  return added;
}

function remove(added, chosen) {
  for (const m of added) {
    chosen.mods.delete(m.key);
    chosen.ids.delete(m.id);
    for (const id of m.incompatible) chosen.incompatible.set(id, chosen.incompatible.get(id).filter(o => o !== m));
    for (const map of m.maps) for (const cell of map.cellSet) chosen.cells.delete(cell);
  }
}

const empty = () => ({ mods: new Map(), ids: new Map(), incompatible: new Map(), cells: new Map() });

// The best set of the map mods members (indices into usable) by their worth own, all above 0, where a map mod brings
// the map mods it needs. Branch and bound in order of worth, each map mod in or out: a branch ends where even the best map mod of
// each group that all conflict with each other (cliques, made greedily) couldn't beat the best set found.
function bestOf(members, usable, own, conflict, at) {
  const order = [...members].sort((a, b) => own[b] - own[a] || Number(usable[a].item.id) - Number(usable[b].item.id));
  const cliques = [];
  const cliqueOf = new Map();
  for (const i of order) {
    let clique = cliques.find(c => c.every(j => conflict[i][j]));
    if (!clique) cliques.push((clique = []));
    clique.push(i);
    cliqueOf.set(i, clique);
  }
  // The map mods each brings, itself included.
  const brings = new Map(order.map(i => [i, usable[i].order.filter(m => at.has(m.key)).map(m => at.get(m.key))]));
  const state = new Map();
  const inSet = [];
  let best = { value: 0, set: [] };
  const fits = i => inSet.every(j => !conflict[i][j]);
  const bound = from => {
    const top = new Map();
    for (let k = from; k < order.length; k++) {
      const i = order[k];
      if (state.has(i) || !fits(i)) continue;
      const clique = cliqueOf.get(i);
      top.set(clique, Math.max(top.get(clique) ?? 0, own[i]));
    }
    let sum = 0;
    for (const v of top.values()) sum += v;
    return sum;
  };
  const step = (k, value) => {
    if (value + bound(k) <= best.value) return;
    if (k === order.length) {
      best = { value, set: [...inSet] };
      return;
    }
    const i = order[k];
    if (state.get(i) === 'in') return step(k + 1, value);
    const added = brings.get(i).filter(j => state.get(j) !== 'in');
    if (added.every(j => state.get(j) !== 'out' && fits(j))) {
      for (const j of added) {
        state.set(j, 'in');
        inSet.push(j);
      }
      step(k + 1, value + added.reduce((sum, j) => sum + own[j], 0));
      for (const j of added) {
        state.delete(j);
        inSet.pop();
      }
    }
    // Left out, it stays out, also of what later map mods bring.
    state.set(i, 'out');
    step(k + 1, value);
    state.delete(i);
  };
  step(0, 0);
  return best.set;
}

// The best set of map mods for a goal, leaving out those in leftOut (keys) and those whose zones stop loading when
// noZoneStops: the mods in load order, the map mods among them, and per map mod not chosen why.
export function solve(read, goalName, { leftOut = new Set(), noZoneStops = false } = {}) {
  const goal = GOALS[goalName];
  const reasons = new Map();
  for (const c of read.candidates) {
    if (leftOut.has(c.key)) reasons.set(c.key, { kind: 'leftOut' });
    else if (c.problem) reasons.set(c.key, { kind: 'problem', text: c.problem });
    else if (goal.plain && c.tilePacks.length) reasons.set(c.key, { kind: 'tilePacks', items: c.tilePacks });
    else if (noZoneStops && c.zoneStops.length) reasons.set(c.key, { kind: 'zones', stops: c.zoneStops });
  }
  // A map mod that needs one left out is left out too.
  for (let more = true; more;) {
    more = false;
    for (const c of read.candidates) {
      const out = !reasons.has(c.key) && c.order.find(m => m !== c && reasons.has(m.key));
      if (out) {
        reasons.set(c.key, { kind: 'needs', with: out });
        more = true;
      }
    }
  }
  const usable = read.candidates.filter(c => !reasons.has(c.key));
  const n = usable.length;
  const own = usable.map(c => goal.weight(c));
  const at = new Map(usable.map((c, i) => [c.key, i]));
  // Two map mods conflict when one, with what it needs, clashes with the other and what it needs. One that needs
  // another goes in the same part, so the parts can be solved one by one.
  const alone = usable.map(c => {
    const chosen = empty();
    add(c.order, chosen);
    return chosen;
  });
  const conflict = usable.map((a, i) => usable.map((b, j) => i !== j && (clash(a.order, alone[j]) !== null || clash(b.order, alone[i]) !== null)));
  const part = usable.map((_, i) => i);
  const root = i => (part[i] === i ? i : (part[i] = root(part[i])));
  usable.forEach((c, i) => {
    for (let j = 0; j < n; j++) if (conflict[i][j]) part[root(i)] = root(j);
    for (const m of c.order) if (at.has(m.key)) part[root(i)] = root(at.get(m.key));
  });
  const parts = new Map();
  for (let i = 0; i < n; i++) parts.set(root(i), [...(parts.get(root(i)) ?? []), i]);
  const picked = [];
  for (const members of parts.values()) picked.push(...bestOf(members, usable, own, conflict, at));
  const result = empty();
  for (const i of picked) add(usable[i].order, result);
  // Every goal is worth more with a map mod than without, so one not chosen clashes with the set.
  for (const c of usable) if (!result.mods.has(c.key)) reasons.set(c.key, clash(c.order, result));
  // Load order: each chosen map mod after what it needs, by Workshop ID.
  const mods = [];
  const placed = new Set();
  for (const c of read.candidates) {
    if (!result.mods.has(c.key)) continue;
    for (const m of c.order) {
      if (!placed.has(m.key) && result.mods.has(m.key)) {
        placed.add(m.key);
        mods.push(m);
      }
    }
  }
  const mapMods = read.candidates.filter(c => result.mods.has(c.key));
  return { mods, mapMods, reasons };
}

// A Prepackaged pack file with the mods of a solution: its items, Prepackaged and the mods in load order, and Map=
// with the map folders of the map mods and the vanilla map last.
export function packText({ id, name, version = '1.0.0', comment }, solution) {
  const items = [...new Set(solution.mods.map(m => m.item.id))];
  const maps = [...new Set(solution.mapMods.flatMap(m => m.maps.map(map => map.name)).filter(n => n !== VANILLA_MAP))];
  return [
    `# ${comment}`,
    '@pack',
    `id = ${id}`,
    ...(name ? [`name = ${name}`] : []),
    `version = ${version}`,
    `WorkshopItems = ${items.join(';')}`,
    `Mods = ${['Prepackaged', ...solution.mods.map(m => m.id)].join(';')}`,
    `Map = ${[...maps, VANILLA_MAP].join(';')}`,
    '',
  ].join('\n');
}

// Pack IDs Prepackaged takes.
export const validId = id => /^[A-Za-z0-9_-]{1,48}$/.test(id);
