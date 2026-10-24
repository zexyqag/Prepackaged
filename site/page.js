// The map pack page: reads the Zomboid Map Index's Build 42 file from the address in <html data-index>, and builds a
// pack from the maps added by hand or by Suggest, shown on the grid, as a list in Map= order and as a pack file. The
// pack lives in the page's address, Suggest's settings in this browser.
import * as Grid from './grid.js';
import { CRITERIA, PRESETS, describePack, packText, readBuild, readPack, suggest, validId, workshopUrl } from './packs.js';

const BUILD = 42;
const SETTINGS = 'prepackaged-map-packs';
const PAGE = 50;
const $ = id => document.getElementById(id);
const state = {
  keys: [],
  leftOut: new Set(),
  priorities: Object.keys(CRITERIA),
  on: new Set(PRESETS.maps.priorities),
  limits: {},
  showOthers: true,
  page: 0,
};
let read = null;
let pack = null;
let drawn = null;
let view = null;

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  Object.assign(node, props);
  node.append(...children.filter(c => c !== null && c !== undefined && c !== false));
  return node;
}
const button = (text, onclick, props = {}) => el('button', { type: 'button', textContent: text, onclick, ...props });
const itemLink = item => el('a', { href: workshopUrl(item.id), target: '_blank', rel: 'noopener', textContent: item.title || item.id });
const modName = m => m.name || m.id;
const count = n => n.toLocaleString('en-US');
const percent = (part, whole) => `${Math.round((100 * part) / whole)}%`;
const names = list => list.map(modName).join(', ');

function thumb(item) {
  const preview = item.workshop?.preview;
  return preview ? el('img', { className: 'thumb', src: preview, alt: '', loading: 'lazy' }) : null;
}

function message(text) {
  $('message').textContent = text;
}

// The pack in the page's address: maps=<keys in Map= order>&out=<left out of suggestions>&id=&name=.
function readAddress() {
  const params = new URLSearchParams(location.hash.slice(1));
  const keys = (params.get('maps') ?? '').split(',').filter(k => read.byKey.has(k));
  state.leftOut = new Set((params.get('out') ?? '').split(',').filter(k => read.byKey.has(k)));
  if (params.has('id')) $('pack-id').value = params.get('id');
  if (params.has('name')) $('pack-name').value = params.get('name');
  state.keys = describePack(read, keys).pack.map(c => c.key);
}
function writeAddress() {
  const params = new URLSearchParams();
  if (state.keys.length) params.set('maps', state.keys.join(','));
  if (state.leftOut.size) params.set('out', [...state.leftOut].join(','));
  params.set('id', $('pack-id').value);
  params.set('name', $('pack-name').value);
  history.replaceState(null, '', `#${params}`);
}

function loadSettings() {
  try {
    const saved = JSON.parse(localStorage.getItem(SETTINGS));
    if (!saved) return;
    const known = Object.keys(CRITERIA);
    const order = saved.priorities.filter(p => known.includes(p));
    state.priorities = [...order, ...known.filter(p => !order.includes(p))];
    state.on = new Set(saved.on.filter(p => known.includes(p)));
    state.limits = saved.limits ?? {};
  } catch {
    // Settings that can't be read are left as they start.
  }
}
function saveSettings() {
  try {
    localStorage.setItem(SETTINGS, JSON.stringify({ priorities: state.priorities, on: [...state.on], limits: state.limits }));
  } catch {
    // Without storage the settings last as long as the page.
  }
}

function setKeys(keys) {
  state.keys = describePack(read, keys).pack.map(c => c.key);
  render();
}
function addMap(key) {
  state.leftOut.delete(key);
  const before = new Set(state.keys);
  setKeys([...state.keys, key]);
  const needed = state.keys.filter(k => k !== key && !before.has(k)).map(k => read.byKey.get(k));
  message(`Added ${modName(read.byKey.get(key))}${needed.length ? `, with ${names(needed)}, which it needs` : ''}.`);
}
function removeMap(key) {
  const gone = state.keys.filter(k => k === key || read.byKey.get(k).order.some(m => m.key === key));
  state.leftOut.add(key);
  setKeys(state.keys.filter(k => !gone.includes(k)));
  const also = gone.filter(k => k !== key).map(k => read.byKey.get(k));
  message(`Took out ${modName(read.byKey.get(key))}${also.length ? `, and ${names(also)}, which need it` : ''}.`);
}
function move(key, by) {
  const keys = [...state.keys];
  const at = keys.indexOf(key);
  [keys[at], keys[at + by]] = [keys[at + by], keys[at]];
  setKeys(keys);
}

// Where the pack's maps are: the first map mod on each cell, in Map= order.
function packOwners() {
  const owner = new Map();
  for (const c of pack.pack) for (const map of c.maps) for (const cell of map.cellSet) if (!owner.has(cell)) owner.set(cell, c);
  return owner;
}

function packNotes(c) {
  const notes = [];
  for (const o of pack.overlaps) {
    if (o.loser === c) notes.push(el('span', { className: 'warn-text', textContent: `Loses ${o.cells} cells to ${modName(o.winner)}.` }));
    if (o.winner === c) notes.push(el('span', { textContent: `Wins ${o.cells} cells over ${modName(o.loser)}.` }));
  }
  for (const k of pack.clashes) {
    if (!k.mods.some(m => m.key === c.key)) continue;
    const other = k.mods.find(m => m.key !== c.key);
    notes.push(el('span', { className: 'bad', textContent: k.kind === 'id' ? `Has the mod ID of ${modName(other)}.` : `Incompatible with ${modName(other)}.` }));
  }
  if (c.missing.length) notes.push(el('span', { className: 'bad', textContent: `Needs ${c.missing.join(', ')}, which no item in the index has.` }));
  if (c.zoneStops.length) notes.push(el('span', { className: 'warn-text', textContent: `Its zones stop loading at ${c.zoneStops.map(s => `${s.map}/${s.file} line ${s.line}`).join(', ')}.` }));
  return notes.flatMap((n, i) => (i ? [' ', n] : [n]));
}

function renderPack() {
  const ordered = pack.pack;
  $('summary').textContent = ordered.length
    ? `${ordered.length} map mods from ${pack.items.length} Workshop items, on ${count(pack.cells)} cells, ${count(pack.newCells)} of them beyond the vanilla map.`
    : 'The pack is empty: add maps from the list below, or let Suggest fill it.';
  const warnings = [];
  if (pack.overlaps.length) warnings.push(`Maps overlap in ${pack.overlaps.length} places: on those cells only the map higher in the list is there, so roads and buildings may end at its edge.`);
  if (pack.clashes.length) warnings.push(`${pack.clashes.length} pairs of mods can't go together: the game loads only one mod of each ID and refuses incompatible ones.`);
  if (pack.missing.length) warnings.push(`${names(pack.missing)} need mods no item in the index has: add their Workshop items to the pack yourself.`);
  $('warnings').replaceChildren(...warnings.map(text => el('li', { className: 'warn', textContent: text })));
  $('pack-maps').replaceChildren(...ordered.map((c, i) => el('tr', {},
    el('td', {}, thumb(c.item), modName(c)),
    el('td', {}, itemLink(c.item)),
    el('td', { className: 'num', textContent: count(c.cells) }),
    el('td', { className: 'num', textContent: count(c.newCells) }),
    el('td', { className: 'notes' }, ...packNotes(c)),
    el('td', { className: 'actions' },
      button('Up', () => move(c.key, -1), { disabled: i === 0, ariaLabel: `Move ${modName(c)} up` }), ' ',
      button('Down', () => move(c.key, 1), { disabled: i === ordered.length - 1, ariaLabel: `Move ${modName(c)} down` }), ' ',
      button('Take out', () => removeMap(c.key), { ariaLabel: `Take ${modName(c)} out` })),
  )));
  const others = pack.items.filter(item => !ordered.some(c => c.item === item));
  $('also').replaceChildren(...(others.length ? ['Also in the pack, for mods its maps need: ', ...others.flatMap((item, i) => (i ? [', ', itemLink(item)] : [itemLink(item)])), '.'] : []));
  $('clear').disabled = !ordered.length;
}

function browseNotes(c, owners) {
  if (pack.pack.includes(c)) return [el('span', { textContent: 'In the pack.' })];
  const notes = [];
  const shared = new Map();
  for (const map of c.maps) for (const cell of map.cellSet) if (owners.has(cell)) shared.set(owners.get(cell), (shared.get(owners.get(cell)) ?? 0) + 1);
  for (const [other, cells] of shared) notes.push(el('span', { className: 'warn-text', textContent: `Overlaps ${modName(other)} by ${cells} cells.` }));
  const inPack = pack.mods;
  for (const m of c.order) {
    if (inPack.includes(m)) continue;
    const same = inPack.find(o => o.id === m.id);
    if (same) notes.push(el('span', { className: 'bad', textContent: `Has the mod ID of ${modName(same)}.` }));
    const against = inPack.find(o => m.incompatible.includes(o.id) || o.incompatible.includes(m.id));
    if (against) notes.push(el('span', { className: 'bad', textContent: `Incompatible with ${modName(against)}.` }));
  }
  if (c.missing.length) notes.push(el('span', { className: 'bad', textContent: `Needs ${c.missing.join(', ')}, which no item in the index has.` }));
  if (c.tilePacks.length) notes.push(el('span', { textContent: `Needs ${c.tilePacks.map(i => i.title || i.id).join(', ')}.` }));
  if (c.zoneStops.length) notes.push(el('span', { className: 'warn-text', textContent: 'Its zones stop loading part way.' }));
  if (state.leftOut.has(c.key)) notes.push(el('span', { textContent: 'Left out of suggestions.' }));
  return notes.flatMap((n, i) => (i ? [' ', n] : [n]));
}

const SORTS = {
  subscribers: ['Subscribers', c => c.item.workshop?.subscribers ?? -1],
  rating: ['Rating', c => { const w = c.item.workshop; return w && w.votesUp + w.votesDown ? w.votesUp / (w.votesUp + w.votesDown) : -1; }],
  kept: ['Kept', c => { const w = c.item.workshop; return w?.lifetimeSubscribers ? w.subscribers / w.lifetimeSubscribers : -1; }],
  cells: ['Cells', c => c.cells],
  updated: ['Last updated', c => c.item.workshop?.timeUpdated ?? c.item.timeUpdated],
  name: ['Name', null],
};

// The list a page at a time, from the first page when what it shows changes.
function renderBrowse() {
  const owners = packOwners();
  const inPack = new Set(pack.pack);
  const search = $('search').value.trim().toLowerCase();
  const hideOverlapping = $('hide-overlapping').checked;
  const hideMissing = $('hide-missing').checked;
  const [, key] = SORTS[$('sort').value];
  const shown = read.candidates.filter(c => {
    if (search && !`${modName(c)} ${c.item.title}`.toLowerCase().includes(search)) return false;
    if (hideMissing && c.missing.length) return false;
    if (hideOverlapping && !inPack.has(c) && c.maps.some(map => [...map.cellSet].some(cell => owners.has(cell)))) return false;
    return true;
  });
  shown.sort((a, b) => (key ? key(b) - key(a) : 0) || modName(a).localeCompare(modName(b)));
  const pages = Math.max(1, Math.ceil(shown.length / PAGE));
  state.page = Math.min(state.page, pages - 1);
  const from = state.page * PAGE;
  const rows = shown.slice(from, from + PAGE);
  $('count').textContent = shown.length > rows.length
    ? `${count(from + 1)} to ${count(from + rows.length)} of ${count(shown.length)} map mods${shown.length < read.candidates.length ? `, of ${count(read.candidates.length)}` : ''}.`
    : `${count(shown.length)} of ${count(read.candidates.length)} map mods.`;
  const turn = to => () => {
    state.page = to;
    renderBrowse();
    $('maps-heading').scrollIntoView({ block: 'start' });
  };
  $('pager').hidden = pages === 1;
  $('pager').replaceChildren(
    button('Previous', turn(state.page - 1), { disabled: state.page === 0 }), ' ',
    `Page ${state.page + 1} of ${pages}`, ' ',
    button('Next', turn(state.page + 1), { disabled: state.page === pages - 1 }),
  );
  $('browse').replaceChildren(...rows.map(c => {
    const w = c.item.workshop;
    const votes = w ? w.votesUp + w.votesDown : 0;
    return el('tr', {},
      el('td', {}, thumb(c.item), modName(c)),
      el('td', {}, itemLink(c.item)),
      el('td', { className: 'num', textContent: count(c.cells) }),
      el('td', { className: 'num', textContent: w?.subscribers == null ? '' : count(w.subscribers) }),
      el('td', { className: 'num', textContent: w?.lifetimeSubscribers ? percent(w.subscribers, w.lifetimeSubscribers) : '' }),
      el('td', { className: 'num', textContent: votes ? percent(w.votesUp, votes) : '', title: votes ? `${count(w.votesUp)} up, ${count(w.votesDown)} down` : '' }),
      el('td', { className: 'notes' }, ...browseNotes(c, owners)),
      el('td', { className: 'actions' }, inPack.has(c)
        ? button('Take out', () => removeMap(c.key), { ariaLabel: `Take ${modName(c)} out` })
        : button('Add', () => addMap(c.key), { ariaLabel: `Add ${modName(c)}` })),
    );
  }));
}

const darkScheme = window.matchMedia('(prefers-color-scheme: dark)');
function gridColors() {
  for (const [name, color] of Object.entries(Grid.COLORS[darkScheme.matches ? 'dark' : 'light'])) {
    document.documentElement.style.setProperty(`--cell-${name}`, color);
  }
}

function drawGrid() {
  const canvas = $('grid');
  const inPack = new Set(pack.pack);
  const inOrder = pack.pack.flatMap(c => c.maps.map(map => ({ keys: Grid.runKeys(map.cells), item: c.item.id, mod: c })));
  const others = state.showOthers
    ? read.candidates.filter(c => !inPack.has(c)).flatMap(c => c.maps.map(map => ({ keys: Grid.runKeys(map.cells), mod: c })))
    : [];
  view = { owners: Grid.cellMaps(inOrder), vanillaKeys: new Set(Grid.runKeys(read.vanillaRuns)), others };
  drawn = Grid.draw(canvas, { ...view, squares: 256, width: $('grid-scroll').clientWidth, dark: darkScheme.matches });
  canvas.hidden = !drawn;
  if (drawn) {
    const { counts } = drawn;
    canvas.setAttribute('aria-label', `Cells: ${counts.vanilla} of the vanilla map only, ${counts.mod} with a map of the pack, ${counts.over} with a map of the pack over the vanilla map, ${counts.shared} where maps of the pack overlap. The list below has the maps.`);
  }
}

function describeCell(event) {
  const at = Grid.cellAt(drawn, $('grid'), event.clientX, event.clientY);
  if (!at) return;
  const here = [...new Set((view.owners.get(at.key) ?? []).map(o => o.mod))];
  const parts = [`Cell ${at.x},${at.y}:`];
  if (here.length) parts.push(`${here.map(c => `${modName(c)} (${c.item.title || c.item.id})`).join(', then ')} in the pack`);
  if (view.vanillaKeys.has(at.key)) parts.push(here.length ? 'over the vanilla map' : 'the vanilla map');
  const others = [...new Set(view.others.filter(o => o.keys.includes(at.key)).map(o => o.mod))];
  if (others.length) parts.push('not in the pack:');
  else if (parts.length === 1) parts.push('nothing');
  $('cell').replaceChildren(parts.join(' '), ...others.flatMap(c => [' ', modName(c), ' ', button('Add', () => addMap(c.key), { ariaLabel: `Add ${modName(c)}` })]));
}

function renderPackFile() {
  const id = $('pack-id').value.trim();
  const ok = validId(id);
  $('pack-id-help').textContent = ok ? 'Letters, digits, _ and -, up to 48.' : 'The ID takes only letters, digits, _ and -, up to 48.';
  $('pack-id-help').className = ok ? 'help' : 'help error';
  $('pack').value = ok
    ? packText({ id, name: $('pack-name').value.trim(), comment: `A map pack from the Zomboid Map Index for Build ${read.gameVersion}.` }, pack)
    : '';
  $('copy').disabled = !ok;
  $('download').disabled = !ok;
}

function render() {
  pack = describePack(read, state.keys);
  renderPack();
  drawGrid();
  renderBrowse();
  renderPackFile();
  writeAddress();
}

function renderSettings() {
  $('priorities').replaceChildren(...state.priorities.map((name, i) => el('li', { className: state.on.has(name) ? '' : 'off' },
    el('label', {}, el('input', { type: 'checkbox', checked: state.on.has(name), onchange: e => {
      if (e.target.checked) state.on.add(name);
      else state.on.delete(name);
      settingsChanged();
    } }), ` ${CRITERIA[name].label} `),
    button('Up', () => movePriority(i, -1), { disabled: i === 0, ariaLabel: `Move ${CRITERIA[name].label} up` }), ' ',
    button('Down', () => movePriority(i, 1), { disabled: i === state.priorities.length - 1, ariaLabel: `Move ${CRITERIA[name].label} down` }))));
  $('no-tile-packs').checked = Boolean(state.limits.noTilePacks);
  $('no-zone-stops').checked = Boolean(state.limits.noZoneStops);
  $('with-spawns').checked = Boolean(state.limits.withSpawns);
  $('max-items').value = state.limits.maxItems ?? '';
  const any = state.on.size > 0;
  $('fill').disabled = !any;
  $('replace').disabled = !any;
}
function settingsChanged() {
  saveSettings();
  renderSettings();
}
function movePriority(at, by) {
  const order = [...state.priorities];
  [order[at], order[at + by]] = [order[at + by], order[at]];
  state.priorities = order;
  settingsChanged();
}
function usePreset(name) {
  const { priorities, limits } = PRESETS[name];
  state.priorities = [...priorities, ...Object.keys(CRITERIA).filter(p => !priorities.includes(p))];
  state.on = new Set(priorities);
  state.limits = { ...limits };
  settingsChanged();
}

const WHY = {
  leftOut: 'you took out', problem: "can't go in a pack", tilePacks: 'need tile packs', zones: 'have zones that stop loading',
  noSpawns: 'have no spawn points', needs: 'need a map left out', cells: 'overlap', id: 'have a mod ID already in it',
  incompatible: 'are incompatible with it', maxItems: 'go past the item limit', noGain: 'add nothing to the priorities',
};
function runSuggest(keep) {
  const before = new Set(state.keys);
  const result = suggest(read, {
    priorities: state.priorities.filter(p => state.on.has(p)), limits: state.limits,
    pinned: keep ? state.keys : [], leftOut: state.leftOut,
  });
  setKeys(result.keys);
  const added = state.keys.filter(k => !before.has(k)).length;
  const kinds = new Map();
  for (const why of result.reasons.values()) kinds.set(why.kind, (kinds.get(why.kind) ?? 0) + 1);
  const left = [...kinds].map(([kind, n]) => `${n} ${WHY[kind]}`).join(', ');
  $('suggested').textContent = `${keep ? `Added ${added} map mods` : `Suggested ${state.keys.length} map mods`}.${left ? ` Not in it: ${left}.` : ''}${result.complete ? '' : ' Suggest stopped before it checked every combination, so a better pack may exist.'}`;
  message('');
}

function loadPack(text) {
  const loaded = readPack(read, text);
  if (!loaded.keys.length) {
    message(`That pack file has no map mods of the index${loaded.unknown.length ? ` (it has ${loaded.unknown.join(', ')})` : ''}.`);
    return;
  }
  if (loaded.id) $('pack-id').value = loaded.id;
  if (loaded.name) $('pack-name').value = loaded.name;
  setKeys(loaded.keys);
  message(`Loaded ${loaded.keys.length} map mods from the pack file.${loaded.unknown.length ? ` The index doesn't have ${loaded.unknown.join(', ')}, so they are left out.` : ''}`);
}

function setUp() {
  $('legend').replaceChildren(...[['vanilla', 'The vanilla map'], ['mod', 'A map of the pack'], ['over', 'A map of the pack over the vanilla map'], ['shared', 'Maps of the pack that overlap'], ['other', 'A map not in the pack']]
    .map(([kind, text]) => el('li', {}, el('span', { className: `swatch ${kind}`, style: kind === 'other' ? '' : `background: var(--cell-${kind})` }), text)));
  $('presets').replaceChildren('Start from: ', ...Object.entries(PRESETS).flatMap(([name, p], i) => [i ? ' ' : '', button(p.label, () => usePreset(name))]));
  $('sort').replaceChildren(...Object.entries(SORTS).map(([value, [label]]) => el('option', { value, textContent: label })));
  $('no-tile-packs').onchange = e => { state.limits.noTilePacks = e.target.checked; settingsChanged(); };
  $('no-zone-stops').onchange = e => { state.limits.noZoneStops = e.target.checked; settingsChanged(); };
  $('with-spawns').onchange = e => { state.limits.withSpawns = e.target.checked; settingsChanged(); };
  $('max-items').onchange = e => {
    const n = Number.parseInt(e.target.value, 10);
    state.limits.maxItems = n > 0 ? n : undefined;
    settingsChanged();
  };
  $('fill').onclick = () => runSuggest(true);
  $('replace').onclick = () => runSuggest(false);
  $('show-others').onchange = e => { state.showOthers = e.target.checked; drawGrid(); };
  for (const id of ['search', 'sort', 'hide-overlapping', 'hide-missing']) {
    $(id).oninput = () => {
      state.page = 0;
      renderBrowse();
    };
  }
  $('pack-id').oninput = () => { renderPackFile(); writeAddress(); };
  $('pack-name').oninput = () => { renderPackFile(); writeAddress(); };
  $('grid').onclick = describeCell;
  $('clear').onclick = () => {
    setKeys([]);
    message('The pack is empty.');
  };
  $('share').onclick = async () => {
    await navigator.clipboard.writeText(location.href);
    $('share').textContent = 'Copied';
    setTimeout(() => { $('share').textContent = 'Copy a link to this pack'; }, 1500);
  };
  $('copy').onclick = async () => {
    await navigator.clipboard.writeText($('pack').value);
    $('copy').textContent = 'Copied';
    setTimeout(() => { $('copy').textContent = 'Copy'; }, 1500);
  };
  $('download').onclick = () => {
    const link = el('a', { href: URL.createObjectURL(new Blob([$('pack').value], { type: 'text/plain' })), download: `${$('pack-id').value.trim()}.txt` });
    link.click();
    URL.revokeObjectURL(link.href);
  };
  $('load-text').onclick = () => loadPack($('load').value);
  $('load-file').onchange = async e => {
    const [file] = e.target.files;
    if (file) loadPack(await file.text());
    e.target.value = '';
  };
  gridColors();
  darkScheme.addEventListener('change', () => { gridColors(); drawGrid(); });
  window.addEventListener('resize', drawGrid);
}

async function start() {
  const base = document.documentElement.dataset.index;
  const url = new URL(`build-${BUILD}.json`, base || undefined);
  const build = await (await fetch(url, { cache: 'no-cache' }).then(r => (r.ok ? r : Promise.reject(new Error(`${r.status} ${r.statusText}`))))).json();
  read = readBuild(build);
  loadSettings();
  setUp();
  renderSettings();
  readAddress();
  $('status').hidden = true;
  $('main').hidden = false;
  render();
}

start().catch(error => {
  $('status').className = 'error';
  $('status').textContent = `The Zomboid Map Index could not be read (${error.message}).`;
});
