const collectionIndexPath = "data/collections/index.json";
const gallery = document.querySelector("#gallery");
const filters = document.querySelector("#filters");
const collectionSelect = document.querySelector("#collection-select");
const dialog = document.querySelector("#specimen-dialog");
const dialogContent = document.querySelector("#dialog-content");
let collectionIndex = [];

const escapeHtml = (value = "") => String(value)
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&#039;");

function renderCard(item, index) {
  const figure = document.createElement("figure");
  figure.className = "specimen";
  figure.dataset.family = item.family;
  figure.tabIndex = 0;
  figure.setAttribute("role", "button");
  figure.setAttribute("aria-label", `${item.title} の詳細を見る`);
  figure.innerHTML = `
    <div class="specimen-frame">
      <img src="${escapeHtml(item.localImage)}" alt="${escapeHtml(item.description || item.title)}" loading="lazy">
      <span class="specimen-number">${String(index + 1).padStart(3, "0")}</span>
    </div>
    <figcaption>
      <span class="specimen-title">${escapeHtml(item.title)}</span>
      <span class="specimen-family">${escapeHtml(item.family)}</span>
    </figcaption>`;

  const open = () => openDialog(item, index);
  figure.addEventListener("click", open);
  figure.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      open();
    }
  });
  return figure;
}

function openDialog(item, index) {
  const license = item.licenseUrl
    ? `<a href="${escapeHtml(item.licenseUrl)}" target="_blank" rel="noreferrer">${escapeHtml(item.license || "原典参照")}</a>`
    : escapeHtml(item.license || "原典参照");
  dialogContent.innerHTML = `
    <div class="dialog-layout">
      <div class="dialog-image"><img src="${escapeHtml(item.localImage)}" alt="${escapeHtml(item.description || item.title)}"></div>
      <div class="dialog-meta">
        <p class="section-number">SPECIMEN ${String(index + 1).padStart(3, "0")} / ${escapeHtml(item.family)}</p>
        <h3>${escapeHtml(item.title)}</h3>
        <p class="curator-note">${escapeHtml(item.curatorNote)}</p>
        <dl class="metadata">
          <div><dt>作者</dt><dd>${escapeHtml(item.artist || "記載なし")}</dd></div>
          <div><dt>撮影・制作日</dt><dd>${escapeHtml(item.date || "記載なし")}</dd></div>
          <div><dt>ライセンス</dt><dd>${license}</dd></div>
          <div><dt>寸法</dt><dd>${item.width} × ${item.height} px（原画像）</dd></div>
        </dl>
        <a class="source-button" href="${escapeHtml(item.sourceUrl)}" target="_blank" rel="noreferrer">WIKIMEDIA COMMONS で原典を見る ↗</a>
      </div>
    </div>`;
  dialog.showModal();
}

function setupFilters(items) {
  filters.replaceChildren();
  const families = ["すべて", ...new Set(items.map((item) => item.family))];
  families.forEach((family, index) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `filter-button${index === 0 ? " active" : ""}`;
    button.textContent = family;
    button.addEventListener("click", () => {
      document.querySelectorAll(".filter-button").forEach((candidate) => candidate.classList.remove("active"));
      button.classList.add("active");
      document.querySelectorAll(".specimen").forEach((card) => {
        card.hidden = family !== "すべて" && card.dataset.family !== family;
      });
    });
    filters.append(button);
  });
}

function formatDate(date) {
  return date.replaceAll("-", ".");
}

function renderCollection(collection, entry, index) {
  gallery.replaceChildren();
  document.querySelector("#hero-index").textContent = String(index + 1).padStart(3, "0");
  document.querySelector("#hero-date").textContent = formatDate(collection.date);
  document.querySelector("#collection-number").textContent = `COLLECTION ${String(index + 1).padStart(3, "0")}`;
  document.querySelector("#collection-title").textContent = collection.title;
  document.querySelector("#collection-subtitle").textContent = collection.subtitle;
  document.querySelector("#collection-description").textContent = collection.description;
  document.querySelector("#item-count").textContent = String(collection.itemCount).padStart(2, "0");
  document.querySelector("#field-note-date").textContent = `FIELD NOTE / ${formatDate(collection.date)}`;
  document.querySelector("#field-note-title").textContent = collection.title;
  document.querySelector("#field-note-description").textContent = collection.description;
  document.querySelector("#field-note-method").textContent = collection.method;
  document.querySelector("#diary-link").href = entry.diaryPath;
  setupFilters(collection.items);
  collection.items.forEach((item, itemIndex) => gallery.append(renderCard(item, itemIndex)));
}

async function loadCollection(date, updateHistory = false) {
  const index = collectionIndex.findIndex((entry) => entry.date === date);
  if (index < 0) throw new Error(`コレクション ${date} は見つかりません`);
  const entry = collectionIndex[index];
  const response = await fetch(entry.path);
  if (!response.ok) throw new Error(`HTTP ${response.status}: ${entry.path}`);
  const collection = await response.json();
  renderCollection(collection, entry, index);
  collectionSelect.value = date;
  if (updateHistory) {
    const url = new URL(window.location.href);
    url.searchParams.set("collection", date);
    window.history.pushState({ date }, "", url);
  }
}

function setupCollectionPicker() {
  collectionSelect.replaceChildren();
  collectionIndex.forEach((entry, index) => {
    const option = document.createElement("option");
    option.value = entry.date;
    option.textContent = `${String(index + 1).padStart(3, "0")} / ${entry.date} / ${entry.title} (${entry.itemCount})`;
    collectionSelect.append(option);
  });
  collectionSelect.addEventListener("change", () => loadCollection(collectionSelect.value, true));
}

async function init() {
  try {
    const response = await fetch(collectionIndexPath);
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const indexData = await response.json();
    collectionIndex = [...indexData.collections].sort((a, b) => a.date.localeCompare(b.date));
    if (!collectionIndex.length) throw new Error("コレクション索引が空です");
    setupCollectionPicker();
    const requestedDate = new URLSearchParams(window.location.search).get("collection");
    const selectedDate = collectionIndex.some((entry) => entry.date === requestedDate)
      ? requestedDate
      : collectionIndex.at(-1).date;
    await loadCollection(selectedDate);
  } catch (error) {
    gallery.innerHTML = `<p class="error">コレクションデータを読み込めませんでした: ${escapeHtml(error.message)}</p>`;
  }
}

window.addEventListener("popstate", (event) => {
  const date = event.state?.date || new URLSearchParams(window.location.search).get("collection");
  if (date && collectionIndex.some((entry) => entry.date === date)) loadCollection(date);
});

document.querySelector(".dialog-close").addEventListener("click", () => dialog.close());
dialog.addEventListener("click", (event) => {
  if (event.target === dialog) dialog.close();
});

init();
