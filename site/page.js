// The map pack page: reads the Zomboid Map Index's Build 42 file from the address in <html data-index>, and shows the
// pack for the goal picked, on the grid, with what was left out and why, and as a pack file.
import * as Grid from './grid.js';
import { GOALS, packText, readBuild, solve, validId, workshopUrl } from './packs.js';

const BUILD = 42;
const $ = id => document.getElementById(id);
const state = { goal: 'maps', leftOut: new Set(), noZoneStops: false, showOthers: true };
let read = null;
let solution = null;
let drawn = null;
let view = null;

function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  Object.assign(node, props);
  node.append(...children.filter(c => c !== null && c !== undefined));
  return node;
}
const itemLink = item => el('a', { href: workshopUrl(item.id), target: '_blank', rel: 'noopener', textContent: item.title || item.id });
const modName = m => m.name || m.id;

function why(reason) {
  switch (reason.kind) {
    case 'leftOut': return 'You left it out.';
    case 'problem': return `It ${reason.text}.`;
    case 'tilePacks': return `It needs ${reason.items.map(i => i.title || i.id).join(', ')}, which bring no maps.`;
    case 'zones': return `Its zones stop loading: ${reason.stops.map(s => `${s.map}/${s.file} at line ${s.line}`).join(', ')}.`;
    case 'needs': return `It needs ${modName(reason.with)}, which is left out.`;
    case 'cells': return `It shares cells with ${modName(reason.with)}.`;
    case 'id': return `Its mod ID is that of ${modName(reason.with)}.`;
    case 'incompatible': return `It and ${modName(reason.with)} are incompatible.`;
  }
}

const darkScheme = window.matchMedia('(prefers-color-scheme: dark)');
function gridColors() {
  for (const [name, color] of Object.entries(Grid.COLORS[darkScheme.matches ? 'dark' : 'light'])) {
    document.documentElement.style.setProperty(`--cell-${name}`, color);
  }
}

function drawGrid() {
  const canvas = $('grid');
  const mapsInOrder = solution.mapMods.flatMap(m => m.maps.map(map => ({ keys: Grid.runKeys(map.cells), item: m.item.id, mod: m })));
  const others = state.showOthers
    ? read.candidates.filter(c => !solution.mapMods.includes(c)).flatMap(c => c.maps.map(map => ({ keys: Grid.runKeys(map.cells), mod: c })))
    : [];
  const vanillaKeys = new Set(Grid.runKeys(read.vanillaRuns));
  view = { owners: Grid.cellMaps(mapsInOrder), vanillaKeys, others };
  drawn = Grid.draw(canvas, { ...view, squares: 256, width: $('grid-scroll').clientWidth, dark: darkScheme.matches });
  canvas.hidden = !drawn;
  if (drawn) {
    const { counts } = drawn;
    canvas.setAttribute('aria-label', `Cells: ${counts.vanilla} of the vanilla map only, ${counts.mod} with a map of the pack, ${counts.over} with a map of the pack over the vanilla map. The table below lists the maps.`);
  }
}

function describeCell(event) {
  const at = Grid.cellAt(drawn, $('grid'), event.clientX, event.clientY);
  if (!at) return;
  const here = view.owners.get(at.key) ?? [];
  const parts = [`Cell ${at.x},${at.y}:`];
  if (here.length) parts.push(`${here.map(o => `${modName(o.mod)} (${o.mod.item.title || o.mod.item.id})`).join(', ')} in the pack`);
  if (view.vanillaKeys.has(at.key)) parts.push(here.length ? 'over the vanilla map' : 'the vanilla map');
  const others = view.others.filter(o => o.keys.includes(at.key));
  if (others.length) parts.push(`left out here: ${[...new Set(others.map(o => modName(o.mod)))].join(', ')}`);
  if (parts.length === 1) parts.push('nothing');
  $('cell').textContent = parts.join(' ');
}

function renderPack() {
  const id = $('pack-id').value.trim();
  const ok = validId(id);
  $('pack-id-help').textContent = ok ? 'Letters, digits, _ and -, up to 48.' : 'The ID takes only letters, digits, _ and -, up to 48.';
  $('pack-id-help').className = ok ? 'help' : 'help error';
  $('pack').value = ok
    ? packText({ id, name: $('pack-name').value.replace(/[\r\n]+/g, ' ').trim(), comment: `A map pack from the Zomboid Map Index for Build ${read.gameVersion}: ${GOALS[state.goal].label.toLowerCase()}.` }, solution)
    : '';
  $('copy').disabled = !ok;
  $('download').disabled = !ok;
}

function render() {
  solution = solve(read, state.goal, { leftOut: state.leftOut, noZoneStops: state.noZoneStops });
  const cells = solution.mapMods.reduce((sum, m) => sum + m.cells, 0);
  const newCells = solution.mapMods.reduce((sum, m) => sum + m.newCells, 0);
  const items = new Set(solution.mods.map(m => m.item.id));
  $('summary').textContent = `${solution.mapMods.length} map mods from ${items.size} Workshop items, on ${cells} cells, ${newCells} of them beyond the vanilla map.`;
  $('chosen').replaceChildren(...solution.mapMods.map(m => el('tr', {},
    el('td', { textContent: modName(m) }),
    el('td', {}, itemLink(m.item)),
    el('td', { className: 'num', textContent: String(m.cells) }),
    el('td', { className: 'num', textContent: String(m.newCells) }),
    el('td', {}, el('button', { type: 'button', textContent: 'Leave out', onclick: () => { state.leftOut.add(m.key); render(); } })),
  )));
  const left = read.candidates.filter(c => solution.reasons.has(c.key));
  $('left-out').replaceChildren(...left.map(c => el('tr', {},
    el('td', { textContent: modName(c) }),
    el('td', {}, itemLink(c.item)),
    el('td', { textContent: why(solution.reasons.get(c.key)) }),
    el('td', {}, state.leftOut.has(c.key) ? el('button', { type: 'button', textContent: 'Bring back', onclick: () => { state.leftOut.delete(c.key); render(); } }) : null),
  )));
  drawGrid();
  renderPack();
}

function setUp() {
  $('version').textContent = read.gameVersion;
  const usable = read.candidates.filter(c => !c.problem).length;
  $('counts').textContent = `${read.candidates.length} map mods that load, ${usable} of them with everything they need in the index,`;
  $('goals').replaceChildren(...Object.entries(GOALS).map(([name, goal]) => el('label', { className: 'choice' },
    el('input', { type: 'radio', name: 'goal', value: name, checked: name === state.goal, onchange: () => { state.goal = name; render(); } }),
    ` ${goal.label}`)));
  $('legend').replaceChildren(...[['vanilla', 'The vanilla map'], ['mod', 'A map of the pack'], ['over', 'A map of the pack over the vanilla map'], ['other', 'A map left out']]
    .map(([kind, text]) => el('li', {}, el('span', { className: `swatch ${kind}`, style: kind === 'other' ? '' : `background: var(--cell-${kind})` }), text)));
  $('no-zone-stops').onchange = e => { state.noZoneStops = e.target.checked; render(); };
  $('show-others').onchange = e => { state.showOthers = e.target.checked; drawGrid(); };
  $('pack-id').oninput = renderPack;
  $('pack-name').oninput = renderPack;
  $('grid').onclick = describeCell;
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
  gridColors();
  darkScheme.addEventListener('change', () => { gridColors(); drawGrid(); });
  window.addEventListener('resize', drawGrid);
}

async function start() {
  const base = document.documentElement.dataset.index;
  const url = new URL(`build-${BUILD}.json`, base || undefined);
  const build = await (await fetch(url, { cache: 'no-cache' }).then(r => (r.ok ? r : Promise.reject(new Error(`${r.status} ${r.statusText}`))))).json();
  read = readBuild(build);
  setUp();
  $('status').hidden = true;
  $('main').hidden = false;
  render();
}

start().catch(error => {
  $('status').className = 'error';
  $('status').textContent = `The Zomboid Map Index could not be read (${error.message}).`;
});
