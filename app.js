const genreIndexPath = "data/genres/index.json";
const supportedMediaTypes = new Set(["image", "video", "audio", "text", "link"]);
const explorationStorageKey = "yohaku.exploration.v1";

const state = {
  index: null,
  published: [],
  cache: new Map(),
  selectedGenre: null,
  selectedItem: null,
  tag: "すべて",
  view: "map",
  panX: 0,
  panY: 0,
  sampleOffset: 0,
  itemFilter: "すべて",
  showAll: false,
  requestId: 0,
  exploration: loadExploration()
};

const elements = {
  explorer: document.querySelector("#explore"),
  map: document.querySelector("#genre-map"),
  stage: document.querySelector("#map-stage"),
  lines: document.querySelector("#map-lines"),
  nodes: document.querySelector("#map-nodes"),
  list: document.querySelector("#genre-list"),
  panel: document.querySelector("#exploration-panel"),
  tagFilter: document.querySelector("#tag-filter"),
  recentUpdates: document.querySelector("#recent-updates")
};

const escapeHtml = (value = "") => String(value)
  .replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;").replaceAll("'", "&#039;");

const mediaTypeOf = (item) => supportedMediaTypes.has(item.mediaType) ? item.mediaType : item.localImage ? "image" : "link";
const localAssetOf = (item) => item.localAsset || item.localImage || "";
const previewOf = (item) => item.previewImage || (mediaTypeOf(item) === "image" ? localAssetOf(item) : "");
const byId = (id) => state.published.find((genre) => genre.id === id);
const itemKey = (genreId, itemId) => `${genreId}:${itemId}`;

function loadExploration() {
  try {
    const stored = JSON.parse(sessionStorage.getItem(explorationStorageKey));
    return { visited: Array.isArray(stored?.visited) ? stored.visited : [], trail: Array.isArray(stored?.trail) ? stored.trail : [] };
  } catch {
    return { visited: [], trail: [] };
  }
}

function saveExploration() {
  sessionStorage.setItem(explorationStorageKey, JSON.stringify(state.exploration));
}

function rememberItem(genreId, item) {
  const key = itemKey(genreId, item.id);
  if (!state.exploration.visited.includes(key)) state.exploration.visited.push(key);
  state.exploration.trail = state.exploration.trail.filter((entry) => entry.key !== key);
  state.exploration.trail.push({ key, genreId, itemId: String(item.id), title: item.title });
  state.exploration.trail = state.exploration.trail.slice(-6);
  saveExploration();
}

function hashNumber(value) {
  let hash = 2166136261;
  for (const char of value) hash = Math.imul(hash ^ char.charCodeAt(0), 16777619);
  return hash >>> 0;
}

function sharedTags(a, b) {
  const other = new Set(b.tags || []);
  return (a.tags || []).filter((tag) => other.has(tag));
}

function relationWeight(a, b) {
  const shared = sharedTags(a, b).length;
  const manual = (a.relatedGenres || []).includes(b.id) || (b.relatedGenres || []).includes(a.id);
  return shared + (manual ? 2 : 0);
}

function computePositions(genres) {
  const points = genres.map((genre) => {
    const seed = hashNumber(genre.id);
    return { id: genre.id, x: genre.mapPosition?.x ?? 18 + (seed % 65), y: genre.mapPosition?.y ?? 20 + ((seed >>> 8) % 60), anchor: Boolean(genre.mapPosition) };
  });
  const genreById = (id) => genres.find((genre) => genre.id === id);
  for (let step = 0; step < 90; step += 1) {
    for (let i = 0; i < points.length; i += 1) {
      for (let j = i + 1; j < points.length; j += 1) {
        const a = points[i], b = points[j];
        let dx = b.x - a.x, dy = b.y - a.y;
        const distance = Math.max(7, Math.hypot(dx, dy));
        dx /= distance; dy /= distance;
        const weight = relationWeight(genreById(a.id), genreById(b.id));
        const force = distance < 24 ? -(24 - distance) * 0.055 : weight ? Math.min(0.08, (distance - 34) * 0.0025 * weight) : 0;
        if (!a.anchor) { a.x += dx * force; a.y += dy * force; }
        if (!b.anchor) { b.x -= dx * force; b.y -= dy * force; }
      }
    }
    points.forEach((point) => { point.x = Math.max(12, Math.min(88, point.x)); point.y = Math.max(15, Math.min(85, point.y)); });
  }
  return new Map(points.map((point) => [point.id, point]));
}

function mediaPlaceholder(item, type) {
  const labels = { image: "IMAGE", video: "VIDEO", audio: "AUDIO", text: "TEXT", link: "WEB" };
  const summary = item.excerpt || item.textContent || item.description || item.curatorNote || item.title;
  return `<div class="media-placeholder media-${type}"><span>${labels[type]}</span><p>${escapeHtml(summary)}</p></div>`;
}

function renderMedia(item, detailed = false, eager = false) {
  const type = mediaTypeOf(item), asset = localAssetOf(item), preview = previewOf(item), alt = escapeHtml(item.description || item.title);
  const loading = detailed || eager ? "" : ' loading="lazy"';
  if (type === "image" && asset) return `<img src="${escapeHtml(asset)}" alt="${alt}"${loading}>`;
  if (type === "video" && asset && detailed) return `<video controls preload="metadata"${preview ? ` poster="${escapeHtml(preview)}"` : ""}><source src="${escapeHtml(asset)}"></video>`;
  if (type === "video" && preview) return `<img src="${escapeHtml(preview)}" alt="${alt}"${loading}>`;
  if (type === "video" && asset) return `<video muted preload="metadata"><source src="${escapeHtml(asset)}"></video>`;
  if (type === "audio" && asset && detailed) return `<div class="media-placeholder media-audio"><span>AUDIO</span><p>${alt}</p><audio controls preload="metadata" src="${escapeHtml(asset)}"></audio></div>`;
  return mediaPlaceholder(item, type);
}

function formatRecordDate(value) {
  const raw = String(value || "").trim();
  if (!raw) return "不明";
  let match = raw.match(/^after\s+(\d{4})/i);
  if (match) return `${match[1]}年以降`;
  match = raw.match(/^circa\s+(\d{4})/i);
  if (match) return `${match[1]}年頃`;
  match = raw.match(/^between\s+(\d{4})\s+and\s+(\d{4})/i);
  if (match) return `${match[1]}年〜${match[2]}年`;
  match = raw.match(/^(\d{4})-tal$/i);
  if (match) return `${match[1]}年代`;
  match = raw.match(/^Taken on\s+(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})/i);
  if (match) {
    const months = { january: 1, february: 2, march: 3, april: 4, may: 5, june: 6, july: 7, august: 8, september: 9, october: 10, november: 11, december: 12 };
    const month = months[match[2].toLowerCase()];
    if (month) return `${match[3]}年${month}月${Number(match[1])}日`;
  }
  match = raw.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (match) return `${match[1]}年${Number(match[2])}月${Number(match[3])}日`;
  match = raw.match(/^(\d{4})-(\d{2})$/);
  if (match) return `${match[1]}年${Number(match[2])}月`;
  match = raw.match(/^(\d{4})$/);
  if (match) return `${match[1]}年`;
  return raw;
}

function recordDateRow(item) {
  return `<div><dt>記録日</dt><dd>${escapeHtml(formatRecordDate(item.date))}</dd></div>`;
}

function renderMap() {
  const positions = computePositions(state.published);
  elements.nodes.replaceChildren();
  elements.lines.replaceChildren();
  elements.list.replaceChildren();
  state.published.forEach((genre) => {
    const point = positions.get(genre.id), seed = hashNumber(genre.id);
    const node = document.createElement("button");
    node.type = "button";
    node.className = `genre-node shape-${seed % 4}`;
    node.dataset.genre = genre.id;
    node.dataset.tags = genre.tags.join("|");
    node.style.left = `${point.x}%`;
    node.style.top = `${point.y}%`;
    node.style.setProperty("--drift-x", `${4 + seed % 8}px`);
    node.style.setProperty("--drift-y", `${4 + (seed >>> 4) % 7}px`);
    node.style.setProperty("--drift-time", `${8 + seed % 7}s`);
    node.innerHTML = `<span class="genre-node-image"><img src="${escapeHtml(genre.representativeAsset)}" alt=""></span><span class="genre-node-copy"><b>${escapeHtml(genre.title)}</b><small>${genre.itemCount}標本</small></span>`;
    node.addEventListener("click", () => selectGenre(genre.id));
    node.addEventListener("mouseenter", () => highlightRelations(genre.id));
    node.addEventListener("mouseleave", () => highlightRelations(state.selectedGenre));
    elements.nodes.append(node);

    const card = document.createElement("button");
    card.type = "button";
    card.className = "genre-list-card";
    card.dataset.genre = genre.id;
    card.dataset.tags = genre.tags.join("|");
    card.innerHTML = `<img src="${escapeHtml(genre.representativeAsset)}" alt=""><span><small>${genre.tags.map(escapeHtml).join(" / ")}</small><b>${escapeHtml(genre.title)}</b><em>${genre.itemCount}標本</em></span>`;
    card.addEventListener("click", () => selectGenre(genre.id));
    elements.list.append(card);
  });
  for (let i = 0; i < state.published.length; i += 1) {
    for (let j = i + 1; j < state.published.length; j += 1) {
      const a = state.published[i], b = state.published[j], weight = relationWeight(a, b);
      if (!weight) continue;
      const pa = positions.get(a.id), pb = positions.get(b.id), line = document.createElementNS("http://www.w3.org/2000/svg", "line");
      line.setAttribute("x1", pa.x * 10); line.setAttribute("y1", pa.y * 6.4); line.setAttribute("x2", pb.x * 10); line.setAttribute("y2", pb.y * 6.4);
      line.dataset.a = a.id; line.dataset.b = b.id; line.dataset.tags = sharedTags(a, b).join("|"); line.style.setProperty("--edge-weight", Math.min(3, weight));
      elements.lines.append(line);
    }
  }
  setupTagFilter();
  applyMapFilter();
  updateStageTransform();
}

function setupTagFilter() {
  const tags = ["すべて", ...new Set(state.published.flatMap((genre) => genre.tags))];
  const body = elements.tagFilter.querySelector(".tag-filter-body");
  body.innerHTML = `<label for="map-tag-select">表示するタグ</label><select id="map-tag-select">${tags.map((tag) => `<option value="${escapeHtml(tag)}"${tag === state.tag ? " selected" : ""}>${escapeHtml(tag)}</option>`).join("")}</select>`;
  body.querySelector("select").addEventListener("change", (event) => chooseTag(event.target.value));
}

function chooseTag(tag) {
  state.tag = tag;
  setupTagFilter();
  applyMapFilter();
}

function applyMapFilter() {
  document.querySelectorAll(".genre-node, .genre-list-card").forEach((node) => node.classList.toggle("filtered", state.tag !== "すべて" && !node.dataset.tags.split("|").includes(state.tag)));
  document.querySelectorAll(".map-lines line").forEach((line) => line.classList.toggle("filtered", state.tag !== "すべて" && !line.dataset.tags.split("|").includes(state.tag)));
}

function highlightRelations(id) {
  const selected = byId(id);
  document.querySelectorAll(".genre-node").forEach((node) => node.classList.toggle("muted", Boolean(selected) && node.dataset.genre !== id && !relationWeight(selected, byId(node.dataset.genre))));
  document.querySelectorAll(".map-lines line").forEach((line) => line.classList.toggle("active", Boolean(id) && (line.dataset.a === id || line.dataset.b === id)));
}

async function fetchGenre(id) {
  if (state.cache.has(id)) return state.cache.get(id);
  const entry = byId(id);
  if (!entry) throw new Error(`Unknown genre: ${id}`);
  const response = await fetch(entry.path);
  if (!response.ok) throw new Error(`${response.status} ${entry.path}`);
  const genre = await response.json();
  state.cache.set(id, genre);
  return genre;
}

function updateUrl(genreId = null, itemId = null, replace = false) {
  const url = new URL(location.href);
  url.search = "";
  if (genreId) url.searchParams.set("genre", genreId);
  if (genreId && itemId) url.searchParams.set("item", itemId);
  const method = replace ? "replaceState" : "pushState";
  history[method]({ genre: genreId, item: itemId }, "", `${url.pathname}${url.search}${url.hash}`);
}

function setSelectedNode(id) {
  state.selectedGenre = id;
  document.querySelectorAll(".genre-node").forEach((node) => node.classList.toggle("selected", node.dataset.genre === id));
  document.querySelectorAll(".genre-list-card").forEach((card) => card.classList.toggle("selected", card.dataset.genre === id));
  highlightRelations(id);
}

async function selectGenre(id, options = {}) {
  const entry = byId(id);
  if (!entry) return showEmptyPanel(options.history !== false);
  const requestId = ++state.requestId;
  setSelectedNode(id);
  state.selectedItem = null;
  state.sampleOffset = 0;
  state.itemFilter = "すべて";
  state.showAll = false;
  elements.panel.dataset.state = "loading";
  elements.panel.innerHTML = `<div class="panel-loading"><span></span><p>${escapeHtml(entry.title)}を開いています</p></div>`;
  if (options.history !== false && !options.itemId) updateUrl(id);
  try {
    const genre = await fetchGenre(id);
    if (requestId !== state.requestId) return;
    if (options.itemId) {
      const item = genre.items.find((candidate) => String(candidate.id) === String(options.itemId));
      if (item) {
        showItem(genre, item, { history: options.history, replace: options.replace });
        revealPanelOnMobile();
        return;
      }
    }
    renderGenrePanel(genre, entry);
  } catch (error) {
    elements.panel.innerHTML = `<p class="error">棚を読み込めませんでした: ${escapeHtml(error.message)}</p>`;
  }
}

function showEmptyPanel(updateHistory = true) {
  state.selectedGenre = null;
  state.selectedItem = null;
  highlightRelations(null);
  document.querySelectorAll(".selected").forEach((node) => node.classList.remove("selected"));
  if (updateHistory) updateUrl();
  elements.panel.dataset.state = "empty";
  elements.panel.innerHTML = `<div class="panel-empty"><div class="panel-zone-title"><span>2</span><div><p class="section-number">EXPLORE SPECIMENS</p><h2>標本を探索する</h2></div></div><p>左のジャンルを選ぶと、標本と次の行き先がここに現れます。</p><button class="primary-action" type="button" data-random-entry>おまかせで1点見る</button></div>`;
  elements.panel.querySelector("[data-random-entry]").addEventListener("click", randomEntry);
}

function revealPanelOnMobile() {
  if (matchMedia("(max-width: 900px)").matches) {
    requestAnimationFrame(() => elements.panel.scrollIntoView({ behavior: "smooth", block: "start" }));
  }
}

function filteredItems(genre) {
  return genre.items.filter((item) => state.itemFilter === "すべて" || item.family === state.itemFilter || mediaTypeOf(item) === state.itemFilter);
}

function renderItemButtons(items, genreId) {
  return items.map((item) => `<button type="button" class="specimen-card" data-item="${escapeHtml(item.id)}"><span>${renderMedia(item, false)}</span><b>${escapeHtml(item.title)}</b><small>${escapeHtml(item.family)} / ${escapeHtml(mediaTypeOf(item))}</small></button>`).join("");
}

function renderGenrePanel(genre, entry) {
  const options = ["すべて", ...new Set(genre.items.flatMap((item) => [item.family, mediaTypeOf(item)]))];
  const items = filteredItems(genre);
  const shown = state.showAll ? items : items.slice(state.sampleOffset, state.sampleOffset + 6);
  const historyItems = [...(genre.history || [])].sort((a, b) => String(b.date).localeCompare(String(a.date)));
  elements.panel.dataset.state = "genre";
  elements.panel.dataset.genre = genre.id;
  elements.panel.dataset.ready = "true";
  elements.panel.innerHTML = `<div class="panel-topbar"><div class="panel-zone-title compact"><span>2</span><div><p class="section-number">EXPLORE SPECIMENS</p><h2>標本を探索する</h2></div></div><button type="button" class="text-button" data-random-entry>別の1点へ</button></div>
    <nav class="breadcrumbs" aria-label="現在地"><button type="button" data-panel-home>ジャンル選択</button><span>›</span><b>${escapeHtml(genre.title)}</b></nav>
    <div class="panel-heading"><p class="section-number">GENRE / ${genre.itemCount}標本</p><div class="panel-cover"><img src="${escapeHtml(entry.representativeAsset)}" alt=""></div><h2>${escapeHtml(genre.title)}</h2><p class="panel-subtitle">${escapeHtml(genre.subtitle)}</p><p>${escapeHtml(genre.description)}</p></div>
    <div class="panel-tags">${genre.tags.map((tag) => `<button type="button" data-tag="${escapeHtml(tag)}">${escapeHtml(tag)}</button>`).join("")}</div>
    <div class="panel-section-heading"><h3>標本を見る</h3><button type="button" class="text-button" data-shuffle>別の標本を表示</button></div>
    <label class="item-filter">標本の絞り込み<select>${options.map((option) => `<option${option === state.itemFilter ? " selected" : ""}>${escapeHtml(option)}</option>`).join("")}</select></label>
    <div class="specimen-grid">${renderItemButtons(shown, genre.id)}</div>
    <button class="secondary-action" type="button" data-show-all>${state.showAll ? "標本を少なく表示" : `すべての標本を見る（${items.length}）`}</button>
    <details class="genre-details"><summary>この棚の見方と更新履歴</summary><p>${escapeHtml(genre.method)}</p><ol>${historyItems.map((item) => { const diary = item.diaryPath || item.diary; return `<li><time>${escapeHtml(item.date)}</time><p>${escapeHtml(item.summary || item.note || item.action || "更新")}</p>${diary ? `<a href="${escapeHtml(diary)}">採集日記</a>` : ""}</li>`; }).join("")}</ol></details>`;
  elements.panel.querySelector("[data-panel-home]").addEventListener("click", () => showEmptyPanel());
  elements.panel.querySelector("[data-random-entry]").addEventListener("click", randomEntry);
  elements.panel.querySelectorAll("[data-tag]").forEach((button) => button.addEventListener("click", () => { chooseTag(button.dataset.tag); elements.tagFilter.open = true; }));
  elements.panel.querySelector("[data-shuffle]").addEventListener("click", () => {
    state.sampleOffset = items.length ? (state.sampleOffset + 6) % items.length : 0;
    state.showAll = false;
    renderGenrePanel(genre, entry);
  });
  elements.panel.querySelector(".item-filter select").addEventListener("change", (event) => {
    state.itemFilter = event.target.value;
    state.sampleOffset = 0;
    state.showAll = false;
    renderGenrePanel(genre, entry);
  });
  elements.panel.querySelector("[data-show-all]").addEventListener("click", () => { state.showAll = !state.showAll; renderGenrePanel(genre, entry); });
  elements.panel.querySelectorAll("[data-item]").forEach((button) => button.addEventListener("click", () => {
    const item = genre.items.find((candidate) => String(candidate.id) === button.dataset.item);
    if (item) { showItem(genre, item); revealPanelOnMobile(); }
  }));
  revealPanelOnMobile();
}

function renderTrail() {
  if (!state.exploration.trail.length) return "";
  return `<div class="trail"><div class="panel-section-heading"><h3>今回の軌跡</h3><button class="text-button" type="button" data-reset-exploration>探索をリセット</button></div><div class="trail-list">${state.exploration.trail.map((entry, index) => `<button type="button" data-trail-genre="${escapeHtml(entry.genreId)}" data-trail-item="${escapeHtml(entry.itemId)}" aria-label="${escapeHtml(entry.title)}">${index + 1}</button>`).join("")}</div></div>`;
}

function attachTrailEvents() {
  elements.panel.querySelectorAll("[data-trail-item]").forEach((button) => button.addEventListener("click", () => selectGenre(button.dataset.trailGenre, { itemId: button.dataset.trailItem })));
  elements.panel.querySelector("[data-reset-exploration]")?.addEventListener("click", () => {
    state.exploration = { visited: [], trail: [] };
    saveExploration();
    showEmptyPanel();
  });
}

async function allSpecimens() {
  const genres = await Promise.all(state.published.map((entry) => fetchGenre(entry.id)));
  return genres.flatMap((genre) => genre.items.map((item) => ({ genre, entry: byId(genre.id), item, key: itemKey(genre.id, item.id) })));
}

function scoreCandidate(current, candidate, mode) {
  const shared = sharedTags(current.item, candidate.item).length;
  const differentGenre = current.genre.id !== candidate.genre.id;
  const differentFamily = current.item.family !== candidate.item.family;
  const differentMedia = mediaTypeOf(current.item) !== mediaTypeOf(candidate.item);
  if (mode === "same") return shared * 6 + (differentFamily ? 1 : 0) + (differentGenre ? 1 : 0);
  if (mode === "cross") return (differentGenre ? 12 : -20) + shared * 4 + relationWeight(current.entry, candidate.entry);
  return (differentGenre ? 6 : 0) + (differentFamily ? 5 : 0) + (differentMedia ? 5 : 0) - shared * 3;
}

function pickBranch(current, specimens, mode, used) {
  const eligible = specimens.filter((candidate) => candidate.key !== current.key && !used.has(candidate.key));
  const unvisited = eligible.filter((candidate) => !state.exploration.visited.includes(candidate.key));
  const recent = new Set(state.exploration.trail.map((entry) => entry.key));
  const outsideRecentTrail = eligible.filter((candidate) => !recent.has(candidate.key));
  const pool = unvisited.length ? unvisited : outsideRecentTrail.length ? outsideRecentTrail : eligible;
  const ranked = pool
    .map((candidate) => ({ ...candidate, score: scoreCandidate(current, candidate, mode) + Math.random() * 1.5 }))
    .sort((a, b) => b.score - a.score);
  const preferred = mode === "same"
    ? ranked.find((candidate) => sharedTags(current.item, candidate.item).length)
    : mode === "cross"
      ? ranked.find((candidate) => candidate.genre.id !== current.genre.id && sharedTags(current.item, candidate.item).length)
      : ranked.find((candidate) => candidate.genre.id !== current.genre.id && candidate.item.family !== current.item.family);
  return preferred || ranked[0] || null;
}

async function renderBranches(genre, item) {
  const target = elements.panel.querySelector("#branch-options");
  if (!target) return;
  try {
    const specimens = await allSpecimens();
    const current = specimens.find((candidate) => candidate.genre.id === genre.id && String(candidate.item.id) === String(item.id));
    if (!current || state.selectedGenre !== genre.id || String(state.selectedItem) !== String(item.id)) return;
    const used = new Set();
    const definitions = [
      ["same", "似たもの", "共通する特徴から選ぶ", "↝"],
      ["cross", "別ジャンル", "共通点のある別の棚へ", "→"],
      ["far", "意外なもの", "離れた特徴へ飛ぶ", "↗"]
    ];
    const branches = definitions.map(([mode, label, description, symbol]) => {
      const candidate = pickBranch(current, specimens, mode, used);
      if (candidate) used.add(candidate.key);
      return { mode, label, description, symbol, candidate };
    }).filter((branch) => branch.candidate);
    target.innerHTML = branches.map((branch) => `<button type="button" data-branch-genre="${escapeHtml(branch.candidate.genre.id)}" data-branch-item="${escapeHtml(branch.candidate.item.id)}"><i>${branch.symbol}</i><span><small>${branch.label}</small><b>${escapeHtml(branch.candidate.item.title)}</b><em>${branch.description}</em></span></button>`).join("");
    target.querySelectorAll("[data-branch-item]").forEach((button) => button.addEventListener("click", () => selectGenre(button.dataset.branchGenre, { itemId: button.dataset.branchItem })));
  } catch (error) {
    target.innerHTML = `<p class="error compact">次の候補を読み込めませんでした。</p>`;
  }
}

function showItem(genre, item, options = {}) {
  const entry = byId(genre.id);
  setSelectedNode(genre.id);
  state.selectedItem = String(item.id);
  rememberItem(genre.id, item);
  const items = filteredItems(genre);
  const index = items.findIndex((candidate) => String(candidate.id) === String(item.id));
  const previous = index > 0 ? items[index - 1] : null;
  const next = index >= 0 && index < items.length - 1 ? items[index + 1] : null;
  if (options.history !== false) updateUrl(genre.id, item.id, options.replace);
  elements.panel.dataset.state = "item";
  elements.panel.dataset.genre = genre.id;
  elements.panel.dataset.item = item.id;
  elements.panel.dataset.ready = "true";
  elements.panel.innerHTML = `<div class="item-explore-dock">
      <nav class="breadcrumbs" aria-label="現在地"><button type="button" data-panel-home>ジャンル選択</button><span>›</span><button type="button" data-panel-genre>${escapeHtml(genre.title)}</button><span>›</span><b>${Math.max(0, index + 1)} / ${items.length}</b></nav>
      <div class="item-pagination" aria-label="標本の前後移動"><button type="button" data-previous${previous ? "" : " disabled"}>← 前へ</button><strong>${escapeHtml(item.title)}</strong><button type="button" data-next${next ? "" : " disabled"}>次へ →</button></div>
      <div id="branch-options" class="branch-options"><p>次の行き先を探しています…</p></div>
    </div>
    ${renderTrail()}
    <div class="item-media">${renderMedia(item, true, true)}</div>
    <div class="item-heading"><p class="section-number">SPECIMEN ${index >= 0 ? String(index + 1).padStart(3, "0") : "---"} / ${escapeHtml(item.family)} / ${escapeHtml(mediaTypeOf(item))}</p><h2>${escapeHtml(item.title)}</h2><dl class="metadata">${recordDateRow(item)}</dl><a class="source-button" href="${escapeHtml(item.sourceUrl)}" target="_blank" rel="noreferrer">原典を見る ↗</a></div>
    <details class="item-information"><summary>この標本の採集メモ</summary><p class="curator-note">${escapeHtml(item.curatorNote)}</p></details>`;
  elements.panel.querySelector("[data-panel-home]").addEventListener("click", () => showEmptyPanel());
  elements.panel.querySelector("[data-panel-genre]").addEventListener("click", () => { state.selectedItem = null; updateUrl(genre.id); renderGenrePanel(genre, entry); });
  elements.panel.querySelector("[data-previous]").addEventListener("click", () => previous && showItem(genre, previous));
  elements.panel.querySelector("[data-next]").addEventListener("click", () => next && showItem(genre, next));
  attachTrailEvents();
  renderBranches(genre, item);
}

async function randomEntry() {
  const specimens = await allSpecimens();
  const unseen = specimens.filter((candidate) => !state.exploration.visited.includes(candidate.key));
  const pool = unseen.length ? unseen : specimens;
  const candidate = pool[Math.floor(Math.random() * pool.length)];
  if (!candidate) return;
  await selectGenre(candidate.genre.id, { itemId: candidate.item.id });
  revealPanelOnMobile();
}

function setView(view) {
  state.view = view;
  elements.map.hidden = view !== "map";
  elements.list.hidden = view !== "list";
  document.querySelectorAll("[data-view]").forEach((button) => button.setAttribute("aria-pressed", String(button.dataset.view === view)));
}

function updateStageTransform() {
  elements.stage.style.transform = `translate(${state.panX}px, ${state.panY}px)`;
}

function setupMapPan() {
  let dragging = false, startX = 0, startY = 0, originX = 0, originY = 0;
  elements.map.addEventListener("pointerdown", (event) => {
    if (event.target.closest("button") || (event.pointerType === "touch" && innerWidth <= 900)) return;
    dragging = true; startX = event.clientX; startY = event.clientY; originX = state.panX; originY = state.panY; elements.map.setPointerCapture(event.pointerId);
  });
  elements.map.addEventListener("pointermove", (event) => {
    if (!dragging) return;
    state.panX = Math.max(-240, Math.min(240, originX + event.clientX - startX));
    state.panY = Math.max(-140, Math.min(140, originY + event.clientY - startY));
    updateStageTransform();
  });
  elements.map.addEventListener("pointerup", () => { dragging = false; });
  document.querySelector("#reset-map").addEventListener("click", () => { state.panX = 0; state.panY = 0; updateStageTransform(); });
}

async function renderRecentUpdates() {
  try {
    const genres = await Promise.all(state.published.map((entry) => fetchGenre(entry.id)));
    let sequence = 0;
    const updates = genres.flatMap((genre) => (genre.history || []).map((item) => ({ ...item, genreId: genre.id, genreTitle: genre.title, sequence: sequence++ })))
      .sort((a, b) => String(b.date).localeCompare(String(a.date)) || b.sequence - a.sequence).slice(0, 4);
    elements.recentUpdates.innerHTML = updates.map((item) => `<li><time>${escapeHtml(item.date)}</time><button type="button" data-update-genre="${escapeHtml(item.genreId)}">${escapeHtml(item.genreTitle)}</button><p>${escapeHtml(item.summary || item.note || item.action || "更新")}</p></li>`).join("");
    elements.recentUpdates.querySelectorAll("[data-update-genre]").forEach((button) => button.addEventListener("click", () => { selectGenre(button.dataset.updateGenre); elements.explorer.scrollIntoView({ behavior: "smooth" }); }));
  } catch {
    elements.recentUpdates.innerHTML = "<li>更新履歴を読み込めませんでした。</li>";
  }
}

async function routeFromUrl(replaceLegacy = true) {
  const params = new URLSearchParams(location.search);
  const legacy = params.get("collection");
  let genreId = params.get("genre");
  if (legacy && state.index.legacyCollections?.[legacy]) {
    genreId = state.index.legacyCollections[legacy];
    updateUrl(genreId, null, true);
  }
  if (!genreId) return showEmptyPanel(false);
  const entry = state.index.genres.find((genre) => genre.id === genreId);
  if (entry?.status === "merged" && entry.redirectTo) {
    genreId = entry.redirectTo;
    updateUrl(genreId, null, true);
  }
  const published = byId(genreId);
  if (!published) return showEmptyPanel(replaceLegacy);
  await selectGenre(genreId, { itemId: params.get("item"), history: false });
}

async function init() {
  try {
    const response = await fetch(genreIndexPath);
    if (!response.ok) throw new Error(`${response.status} ${genreIndexPath}`);
    state.index = await response.json();
    state.published = state.index.genres.filter((genre) => genre.status === "published");
    document.querySelector("#overview-genre-count").textContent = state.published.length;
    document.querySelector("#overview-item-count").textContent = state.published.reduce((sum, genre) => sum + Number(genre.itemCount || 0), 0);
    document.querySelector(".status").lastChild.textContent = ` ${state.published.length} GENRES / ${state.published.reduce((sum, genre) => sum + Number(genre.itemCount || 0), 0)} SPECIMENS`;
    renderMap();
    setupMapPan();
    showEmptyPanel(false);
    await routeFromUrl();
    renderRecentUpdates();
  } catch (error) {
    elements.explorer.innerHTML = `<p class="error">アーカイブを読み込めませんでした: ${escapeHtml(error.message)}</p>`;
  }
}

document.querySelectorAll("[data-view]").forEach((button) => button.addEventListener("click", () => setView(button.dataset.view)));
document.querySelector("[data-home-link]").addEventListener("click", (event) => { event.preventDefault(); showEmptyPanel(); scrollTo({ top: 0, behavior: "smooth" }); });
elements.panel.querySelector("[data-random-entry]").addEventListener("click", randomEntry);
addEventListener("popstate", () => routeFromUrl(false));
addEventListener("keydown", (event) => {
  if (!state.selectedItem || ["INPUT", "SELECT", "TEXTAREA", "BUTTON", "A"].includes(document.activeElement?.tagName)) return;
  if (event.key === "ArrowLeft") elements.panel.querySelector("[data-previous]:not(:disabled)")?.click();
  if (event.key === "ArrowRight") elements.panel.querySelector("[data-next]:not(:disabled)")?.click();
});

init();
