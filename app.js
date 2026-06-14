const genreIndexPath = "data/genres/index.json";
const supportedMediaTypes = new Set(["image", "video", "audio", "text", "link"]);
const state = { index: null, published: [], cache: new Map(), selected: null, current: null, tag: "すべて", panX: 0, panY: 0, previewOffset: 0, previewRequest: 0 };

const elements = {
  explorer: document.querySelector("#explore"), genreView: document.querySelector("#genre-view"), map: document.querySelector("#genre-map"),
  stage: document.querySelector("#map-stage"), lines: document.querySelector("#map-lines"), nodes: document.querySelector("#map-nodes"),
  preview: document.querySelector("#genre-preview"), list: document.querySelector("#genre-list"), tagFilter: document.querySelector("#tag-filter"),
  gallery: document.querySelector("#gallery"), filters: document.querySelector("#filters"), dialog: document.querySelector("#specimen-dialog"),
  dialogContent: document.querySelector("#dialog-content")
};

const escapeHtml = (value = "") => String(value)
  .replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;").replaceAll("'", "&#039;");

const mediaTypeOf = (item) => supportedMediaTypes.has(item.mediaType) ? item.mediaType : item.localImage ? "image" : "link";
const localAssetOf = (item) => item.localAsset || item.localImage || "";
const previewOf = (item) => item.previewImage || (mediaTypeOf(item) === "image" ? localAssetOf(item) : "");
const byId = (id) => state.published.find((genre) => genre.id === id);

function hashNumber(value) {
  let hash = 2166136261;
  for (const char of value) hash = Math.imul(hash ^ char.charCodeAt(0), 16777619);
  return hash >>> 0;
}

function sharedTags(a, b) { return a.tags.filter((tag) => b.tags.includes(tag)); }

function relationWeight(a, b) {
  const shared = sharedTags(a, b).length;
  const manual = a.relatedGenres.includes(b.id) || b.relatedGenres.includes(a.id);
  return shared + (manual ? 2 : 0);
}

function computePositions(genres) {
  const points = genres.map((genre) => {
    const seed = hashNumber(genre.id);
    return {
      id: genre.id,
      x: genre.mapPosition?.x ?? 18 + (seed % 65),
      y: genre.mapPosition?.y ?? 20 + ((seed >>> 8) % 60),
      anchor: Boolean(genre.mapPosition)
    };
  });
  for (let step = 0; step < 90; step += 1) {
    for (let i = 0; i < points.length; i += 1) {
      for (let j = i + 1; j < points.length; j += 1) {
        const a = points[i], b = points[j];
        let dx = b.x - a.x, dy = b.y - a.y;
        const distance = Math.max(7, Math.hypot(dx, dy));
        dx /= distance; dy /= distance;
        const weight = relationWeight(byId(a.id), byId(b.id));
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

function metadataRows(item) {
  const creator = item.creator || item.artist || "記載なし", rights = item.license || item.rights || "原典参照";
  const rightsValue = item.licenseUrl ? `<a href="${escapeHtml(item.licenseUrl)}" target="_blank" rel="noreferrer">${escapeHtml(rights)}</a>` : escapeHtml(rights);
  const rows = [["媒体", mediaTypeOf(item)], ["作者", creator], ["制作日", item.date || "記載なし"], ["権利", rightsValue, true]];
  if (item.width && item.height) rows.push(["寸法", `${item.width} × ${item.height} px`]);
  if (item.duration) rows.push(["長さ", item.duration]);
  if (item.format) rows.push(["形式", item.format]);
  return rows.map(([label, value, html]) => `<div><dt>${label}</dt><dd>${html ? value : escapeHtml(value)}</dd></div>`).join("");
}

function renderMap() {
  const positions = computePositions(state.published);
  elements.nodes.replaceChildren(); elements.lines.replaceChildren(); elements.list.replaceChildren();
  state.published.forEach((genre) => {
    const point = positions.get(genre.id), seed = hashNumber(genre.id);
    const node = document.createElement("button");
    node.type = "button"; node.className = `genre-node shape-${seed % 4}`; node.dataset.genre = genre.id; node.dataset.tags = genre.tags.join("|");
    node.style.left = `${point.x}%`; node.style.top = `${point.y}%`; node.style.setProperty("--drift-x", `${4 + seed % 8}px`); node.style.setProperty("--drift-y", `${4 + (seed >>> 4) % 7}px`); node.style.setProperty("--drift-time", `${8 + seed % 7}s`);
    node.innerHTML = `<span class="genre-node-image"><img src="${escapeHtml(genre.representativeAsset)}" alt=""></span><span class="genre-node-copy"><b>${escapeHtml(genre.title)}</b><small>${genre.itemCount} specimens</small></span>`;
    node.addEventListener("click", () => selectGenre(genre.id));
    node.addEventListener("dblclick", () => openGenre(genre.id));
    node.addEventListener("mouseenter", () => highlightRelations(genre.id));
    node.addEventListener("mouseleave", () => highlightRelations(state.selected));
    elements.nodes.append(node);

    const card = document.createElement("button"); card.type = "button"; card.className = "genre-list-card";
    card.innerHTML = `<img src="${escapeHtml(genre.representativeAsset)}" alt=""><span><small>${genre.tags.map(escapeHtml).join(" / ")}</small><b>${escapeHtml(genre.title)}</b><em>${genre.itemCount} specimens</em></span>`;
    card.addEventListener("click", () => openGenre(genre.id)); elements.list.append(card);
  });
  for (let i = 0; i < state.published.length; i += 1) for (let j = i + 1; j < state.published.length; j += 1) {
    const a = state.published[i], b = state.published[j], weight = relationWeight(a, b);
    if (!weight) continue;
    const pa = positions.get(a.id), pb = positions.get(b.id), line = document.createElementNS("http://www.w3.org/2000/svg", "line");
    line.setAttribute("x1", pa.x * 10); line.setAttribute("y1", pa.y * 6.4); line.setAttribute("x2", pb.x * 10); line.setAttribute("y2", pb.y * 6.4);
    line.dataset.a = a.id; line.dataset.b = b.id; line.dataset.tags = sharedTags(a, b).join("|"); line.style.setProperty("--edge-weight", Math.min(3, weight));
    elements.lines.append(line);
  }
  setupTagFilter(); applyMapFilter(); updateStageTransform();
}

function setupTagFilter() {
  const tags = ["すべて", ...new Set(state.published.flatMap((genre) => genre.tags))];
  elements.tagFilter.innerHTML = `<label for="map-tag-select">タグで絞る</label><select id="map-tag-select">${tags.map((tag) => `<option value="${escapeHtml(tag)}"${tag === state.tag ? " selected" : ""}>${escapeHtml(tag)}</option>`).join("")}</select>`;
  elements.tagFilter.querySelector("select").addEventListener("change", (event) => chooseTag(event.target.value));
}

function chooseTag(tag) {
  state.tag = tag; setupTagFilter(); applyMapFilter();
  const selected = byId(state.selected);
  if (tag !== "すべて" && (!selected || !selected.tags.includes(tag))) {
    const next = state.published.find((genre) => genre.tags.includes(tag));
    if (next) selectGenre(next.id);
  }
}

function applyMapFilter() {
  document.querySelectorAll(".genre-node").forEach((node) => node.classList.toggle("filtered", state.tag !== "すべて" && !node.dataset.tags.split("|").includes(state.tag)));
  document.querySelectorAll(".map-lines line").forEach((line) => line.classList.toggle("filtered", state.tag !== "すべて" && !line.dataset.tags.split("|").includes(state.tag)));
}

function highlightRelations(id) {
  const selected = byId(id);
  document.querySelectorAll(".genre-node").forEach((node) => node.classList.toggle("muted", Boolean(selected) && node.dataset.genre !== id && !relationWeight(selected, byId(node.dataset.genre))));
  document.querySelectorAll(".map-lines line").forEach((line) => line.classList.toggle("active", Boolean(id) && (line.dataset.a === id || line.dataset.b === id)));
}

async function selectGenre(id) {
  const genre = byId(id); if (!genre) return; const request = ++state.previewRequest; state.selected = id; state.previewOffset = 0; highlightRelations(id);
  document.querySelectorAll(".genre-node").forEach((node) => node.classList.toggle("selected", node.dataset.genre === id));
  elements.preview.dataset.genre = id; elements.preview.dataset.ready = "false";
  elements.preview.innerHTML = `<div class="preview-loading"><span></span><p>${escapeHtml(genre.title)}を開いています</p></div>`;
  try {
    const genreData = await fetchGenre(id);
    if (state.selected !== id || state.previewRequest !== request) return;
    renderGenrePreview(genreData, genre);
  } catch (error) {
    if (state.selected === id && state.previewRequest === request) elements.preview.innerHTML = `<p class="error">棚を読み込めませんでした: ${escapeHtml(error.message)}</p>`;
  }
}

function previewItems(genre, offset) {
  const count = Math.min(4, genre.items.length);
  return Array.from({ length: count }, (_, index) => genre.items[(offset + index) % genre.items.length]);
}

function renderGenrePreview(genre, entry) {
  const related = state.published.filter((candidate) => candidate.id !== entry.id && relationWeight(entry, candidate)).sort((a, b) => relationWeight(entry, b) - relationWeight(entry, a));
  const samples = previewItems(genre, state.previewOffset);
  elements.preview.innerHTML = `<div class="preview-head"><p class="section-number">SELECTED GENRE</p><span>${genre.itemCount} specimens</span></div><div class="preview-cover"><img src="${escapeHtml(entry.representativeAsset)}" alt=""></div><h2>${escapeHtml(genre.title)}</h2><p class="preview-subtitle">${escapeHtml(genre.subtitle)}</p><p class="preview-description">${escapeHtml(genre.description)}</p><div class="preview-tags">${genre.tags.map((tag) => `<button type="button" data-tag="${escapeHtml(tag)}">${escapeHtml(tag)}</button>`).join("")}</div><div class="preview-section-title"><span>標本を覗く</span><button class="preview-shuffle" type="button">入れ替える</button></div><div class="preview-specimens">${samples.map((item) => `<button type="button" data-specimen="${escapeHtml(item.id)}"><span>${renderMedia(item, false, true)}</span><b>${escapeHtml(item.title)}</b></button>`).join("")}</div>${related.length ? `<div class="preview-section-title"><span>隣の棚</span></div><div class="preview-related">${related.map((candidate) => `<button type="button" data-related="${escapeHtml(candidate.id)}">${escapeHtml(candidate.title)}<small>${escapeHtml(sharedTags(entry, candidate).join(" / ") || "編集された関係")}</small></button>`).join("")}</div>` : ""}<button class="primary-action open-selected" type="button">棚の全標本を見る</button>`;
  elements.preview.dataset.genre = entry.id; elements.preview.dataset.ready = "true";
  elements.preview.querySelector(".open-selected").addEventListener("click", () => openGenre(entry.id));
  elements.preview.querySelector(".preview-shuffle").addEventListener("click", () => { state.previewOffset = (state.previewOffset + 4) % genre.items.length; renderGenrePreview(genre, entry); });
  elements.preview.querySelectorAll("[data-tag]").forEach((button) => button.addEventListener("click", () => chooseTag(button.dataset.tag)));
  elements.preview.querySelectorAll("[data-related]").forEach((button) => button.addEventListener("click", () => selectGenre(button.dataset.related)));
  elements.preview.querySelectorAll("[data-specimen]").forEach((button) => button.addEventListener("click", () => {
    const index = genre.items.findIndex((item) => String(item.id) === button.dataset.specimen);
    if (index >= 0) openDialog(genre.items[index], index);
  }));
}

async function fetchGenre(id) {
  if (state.cache.has(id)) return state.cache.get(id);
  const entry = state.index.genres.find((genre) => genre.id === id); if (!entry) throw new Error(`ジャンル ${id} は見つかりません`);
  if (entry.status === "merged" && entry.redirectTo) return fetchGenre(entry.redirectTo);
  const response = await fetch(entry.path); if (!response.ok) throw new Error(`HTTP ${response.status}: ${entry.path}`);
  const genre = await response.json(); state.cache.set(id, genre); return genre;
}

async function openGenre(id, updateHistory = true) {
  const entry = state.index.genres.find((genre) => genre.id === id); if (!entry) return showMap(updateHistory);
  if (entry.status === "merged" && entry.redirectTo) return openGenre(entry.redirectTo, updateHistory);
  const genre = await fetchGenre(id); state.current = genre; renderGenre(genre); elements.explorer.hidden = true; elements.genreView.hidden = false;
  if (updateHistory) { const url = new URL(location.href); url.search = ""; url.searchParams.set("genre", genre.id); history.pushState({ genre: genre.id }, "", url); }
  scrollTo({ top: 0, behavior: "smooth" });
}

function showMap(updateHistory = true) {
  state.current = null; elements.genreView.hidden = true; elements.explorer.hidden = false;
  if (updateHistory) { const url = new URL(location.href); url.search = ""; history.pushState({}, "", url); }
  scrollTo({ top: 0, behavior: "smooth" });
}

function renderGenre(genre) {
  document.querySelector("#collection-number").textContent = `GENRE / ${genre.id.toUpperCase()}`;
  document.querySelector("#collection-title").textContent = genre.title; document.querySelector("#collection-subtitle").textContent = genre.subtitle;
  document.querySelector("#collection-description").textContent = genre.description; document.querySelector("#item-count").textContent = String(genre.itemCount).padStart(2, "0");
  document.querySelector("#field-note-method").textContent = genre.method;
  document.querySelector("#genre-tags").innerHTML = genre.tags.map((tag) => `<button type="button">${escapeHtml(tag)}</button>`).join("");
  document.querySelectorAll("#genre-tags button").forEach((button) => button.addEventListener("click", () => {
    chooseTag(button.textContent); showMap();
  }));
  setupFilters(genre.items); renderItems(genre.items); renderRelated(genre); renderHistory(genre);
}

function renderItems(items) { elements.gallery.replaceChildren(); items.forEach((item, index) => elements.gallery.append(renderCard(item, index))); }

function renderCard(item, index) {
  const figure = document.createElement("figure"); figure.className = "specimen"; figure.dataset.family = item.family; figure.dataset.mediaType = mediaTypeOf(item); figure.tabIndex = 0; figure.setAttribute("role", "button"); figure.setAttribute("aria-label", `${item.title} の詳細を見る`);
  figure.innerHTML = `<div class="specimen-frame">${renderMedia(item)}<span class="specimen-number">${String(index + 1).padStart(3, "0")}</span></div><figcaption><span class="specimen-title">${escapeHtml(item.title)}</span><span class="specimen-family">${escapeHtml(item.family)}</span></figcaption><div class="specimen-tags">${(item.tags || []).slice(0, 3).map(escapeHtml).join(" · ")}</div>`;
  const open = () => openDialog(item, index); figure.addEventListener("click", open); figure.addEventListener("keydown", (event) => { if (["Enter", " "].includes(event.key)) { event.preventDefault(); open(); } }); return figure;
}

function setupFilters(items) {
  const options = ["すべて", ...new Set(items.map((item) => item.family)), ...new Set(items.map(mediaTypeOf))]; elements.filters.replaceChildren();
  options.forEach((option, index) => { const button = document.createElement("button"); button.type = "button"; button.className = `filter-button${index === 0 ? " active" : ""}`; button.textContent = option;
    button.addEventListener("click", () => { document.querySelectorAll(".filter-button").forEach((candidate) => candidate.classList.remove("active")); button.classList.add("active"); document.querySelectorAll(".specimen").forEach((card) => { card.hidden = option !== "すべて" && card.dataset.family !== option && card.dataset.mediaType !== option; }); }); elements.filters.append(button); });
}

function renderRelated(genre) {
  const related = state.published.filter((candidate) => candidate.id !== genre.id && relationWeight(genre, candidate)).sort((a, b) => relationWeight(genre, b) - relationWeight(genre, a));
  const container = document.querySelector("#related-genres"); container.replaceChildren();
  if (!related.length) { container.innerHTML = "<p>現在、隣接する棚はありません。</p>"; return; }
  related.forEach((entry) => { const button = document.createElement("button"); button.type = "button"; button.innerHTML = `<img src="${escapeHtml(entry.representativeAsset)}" alt=""><span><b>${escapeHtml(entry.title)}</b><small>${sharedTags(genre, entry).join(" / ") || "編集された関係"}</small></span>`; button.addEventListener("click", () => openGenre(entry.id)); container.append(button); });
}

function renderHistory(genre) {
  const historyList = document.querySelector("#genre-history"); historyList.replaceChildren(); [...genre.history].sort((a, b) => b.date.localeCompare(a.date)).forEach((event) => { const item = document.createElement("li"); item.innerHTML = `<time>${escapeHtml(event.date)}</time><div><small>${escapeHtml(event.type)}</small><p>${escapeHtml(event.summary)}</p>${event.diaryPath ? `<a href="${escapeHtml(event.diaryPath)}">採集日記を読む ↗</a>` : ""}</div>`; historyList.append(item); });
}

function openDialog(item, index) {
  const sourceName = item.sourceName ? `${escapeHtml(item.sourceName)} で原典を見る` : "原典を見る";
  elements.dialogContent.innerHTML = `<div class="dialog-layout"><div class="dialog-media">${renderMedia(item, true)}</div><div class="dialog-meta"><p class="section-number">SPECIMEN ${String(index + 1).padStart(3, "0")} / ${escapeHtml(item.family)} / ${mediaTypeOf(item)}</p><h3>${escapeHtml(item.title)}</h3><p class="curator-note">${escapeHtml(item.curatorNote)}</p><div class="dialog-tags">${(item.tags || []).map((tag) => `<span>${escapeHtml(tag)}</span>`).join("")}</div><dl class="metadata">${metadataRows(item)}</dl><a class="source-button" href="${escapeHtml(item.sourceUrl)}" target="_blank" rel="noreferrer">${sourceName} ↗</a></div></div>`;
  elements.dialog.showModal();
}

function updateStageTransform() { elements.stage.style.transform = `translate(${state.panX}px, ${state.panY}px)`; }

function setupMapPan() {
  let dragging = false, startX = 0, startY = 0, originX = 0, originY = 0;
  elements.map.addEventListener("pointerdown", (event) => { if (event.target.closest("button")) return; dragging = true; startX = event.clientX; startY = event.clientY; originX = state.panX; originY = state.panY; elements.map.setPointerCapture(event.pointerId); });
  elements.map.addEventListener("pointermove", (event) => { if (!dragging) return; state.panX = Math.max(-240, Math.min(240, originX + event.clientX - startX)); state.panY = Math.max(-140, Math.min(140, originY + event.clientY - startY)); updateStageTransform(); });
  elements.map.addEventListener("pointerup", () => { dragging = false; });
  document.querySelector("#reset-map").addEventListener("click", () => { state.panX = 0; state.panY = 0; updateStageTransform(); });
}

function randomGenre(neighborsOnly = false) {
  let candidates = state.published;
  if (!neighborsOnly && state.tag !== "すべて") candidates = candidates.filter((genre) => genre.tags.includes(state.tag));
  if (neighborsOnly && state.current) candidates = state.published.filter((genre) => genre.id !== state.current.id && relationWeight(state.current, genre));
  if (!candidates.length) return; const picked = candidates[Math.floor(Math.random() * candidates.length)]; neighborsOnly ? openGenre(picked.id) : selectGenre(picked.id);
}

async function init() {
  try {
    const response = await fetch(genreIndexPath); if (!response.ok) throw new Error(`HTTP ${response.status}`); state.index = await response.json();
    state.published = state.index.genres.filter((genre) => genre.status === "published"); renderMap(); setupMapPan();
    const params = new URLSearchParams(location.search); const legacyDate = params.get("collection"); let requested = params.get("genre");
    if (legacyDate && state.index.legacyCollections[legacyDate]) { requested = state.index.legacyCollections[legacyDate]; const url = new URL(location.href); url.search = ""; url.searchParams.set("genre", requested); history.replaceState({ genre: requested }, "", url); }
    if (requested) await openGenre(requested, false); else showMap(false);
  } catch (error) { elements.explorer.innerHTML = `<p class="error">アーカイブを読み込めませんでした: ${escapeHtml(error.message)}</p>`; }
}

document.querySelectorAll("[data-map-link], .back-to-map").forEach((link) => link.addEventListener("click", (event) => {
  event.preventDefault(); const focusMap = link.matches(".back-to-map") || link.getAttribute("href") === "#explore"; showMap();
  if (focusMap) requestAnimationFrame(() => elements.explorer.scrollIntoView({ behavior: "smooth" }));
}));
document.querySelector("#random-genre").addEventListener("click", () => randomGenre()); document.querySelector("#random-neighbor").addEventListener("click", () => randomGenre(true));
document.querySelector("#toggle-view").addEventListener("click", (event) => { const listMode = elements.list.hidden; elements.list.hidden = !listMode; document.querySelector("#map-mode").hidden = listMode; event.currentTarget.textContent = listMode ? "地図へ戻る" : "一覧で見る"; event.currentTarget.setAttribute("aria-pressed", String(listMode)); });
document.querySelector(".dialog-close").addEventListener("click", () => elements.dialog.close()); elements.dialog.addEventListener("click", (event) => { if (event.target === elements.dialog) elements.dialog.close(); });
addEventListener("popstate", (event) => { const id = event.state?.genre || new URLSearchParams(location.search).get("genre"); id ? openGenre(id, false) : showMap(false); });
init();
