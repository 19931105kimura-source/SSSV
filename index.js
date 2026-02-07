const express = require("express");
const path = require("path");
const fs = require("fs");
const multer = require("multer");
const http = require("http");
const WebSocket = require("ws");

const { store } = require("./src/store");
const { printTextWindows } = require("./src/printer");
const { buildReceiptText } = require("./src/domain");

const app = express();

const MENU_PATH = path.join(__dirname, "data", "menu.json");

// =========================
// アップロード（宣材）設定
// =========================
const uploadDir = path.join(__dirname, "uploads", "promos");

// ★ 必ずフォルダを作る（初回 ENOENT 対策）
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
  destination: (req, file, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    const name = `promo_${Date.now()}${ext}`;
    cb(null, name);
  },
});

// ★ upload は route より前に定義（ReferenceError 対策）
const upload = multer({
  storage,
  limits: { fileSize: 50 * 1024 * 1024 }, // 50MB（動画OK）
});

// =========================
// Middleware
// =========================
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// uploads を静的配信（/uploads/promos/xxx で見える）
app.use("/uploads", express.static(path.join(__dirname, "uploads")));

// ===== CORS許可（ローカル用）=====
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader(
  "Access-Control-Allow-Methods",
  "GET,POST,PATCH,DELETE,OPTIONS"
);

  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  next();
});

// =========================
// 共通：menu productId 安定化
// =========================
function makeKey(item) {
  return `${item.category}::${item.name}::${item.variantLabel}`;
}

function loadExistingMap() {
  if (!fs.existsSync(MENU_PATH)) return new Map();

  const json = JSON.parse(fs.readFileSync(MENU_PATH, "utf8"));
  const map = new Map();

  for (const it of json.items || []) {
    map.set(makeKey(it), it.productId);
  }
  return map;
}

// -------------------------
// 共通：テーブルの注文明細取得
// -------------------------
function getTableItems(tableId) {
  const orderIds = store.ordersByTable.get(tableId) || [];
  const itemIds = orderIds.flatMap(
    (orderId) => store.orderItemsByOrder.get(orderId) || []
  );
  return itemIds.map((id) => store.orderItems.get(id)).filter(Boolean);
}

// -------------------------
// 共通：オーダー表印刷（drink / food）
// -------------------------
async function printOrderSlip({ tableId, target }) {
  const rawItems = getTableItems(tableId);

  const items = rawItems.filter(
    (item) =>
      item.printTarget === target &&
      item.printed &&
      item.printed[target] === false
  );

  // 対象がなければ何もしない
  if (items.length === 0) {
    return { printed: false };
  }

  const orderedBy = items[0]?.orderedBy ?? "unknown";

  // 商品ごとに集計
  const aggregated = new Map();
  for (const item of items) {
    const key = item.productId || item.name;
    if (!aggregated.has(key)) {
      aggregated.set(key, { name: item.name, quantity: 0 });
    }
    aggregated.get(key).quantity += item.quantity;
  }

  let text = "";
  text += `${target.toUpperCase()} ORDER\n`;
  text += `TABLE: ${tableId}\n`;
  text += `BY: ${orderedBy}\n`;
  text += `TIME: ${new Date().toLocaleString()}\n`;
  text += "----------------\n";

  for (const agg of aggregated.values()) {
    text += `${agg.name} x${agg.quantity}\n`;
  }

  text += "----------------\n";

  console.log("=== PRINT ORDER TEXT ===");
  console.log(text);

  await printTextWindows(text, target);

  // 印刷済みフラグ
  for (const item of items) {
    item.printed[target] = true;
  }

  return { printed: true };
}

// -------------------------
// 共通：会計計算
// -------------------------
function calcReceiptSummary(tableId) {
  const items = getTableItems(tableId);

  let taxableSubtotal = 0;
  let nonTaxableSubtotal = 0;

  for (const item of items) {
    const lineTotal = item.price * item.quantity;
    const product = store.products.get(item.productId);
    const isNonTaxable = product && product.type === "set";

    if (isNonTaxable) {
      nonTaxableSubtotal += lineTotal;
    } else {
      taxableSubtotal += lineTotal;
    }
  }

  const taxIncludedAmount = Math.round(taxableSubtotal * 1.10);
  const serviceIncludedAmount = Math.round(taxIncludedAmount * 1.25);
  const grossTotal = serviceIncludedAmount + nonTaxableSubtotal;
  const total = Math.floor(grossTotal / 10) * 10;

  return {
    items,
    taxableSubtotal,
    nonTaxableSubtotal,
    tax: taxIncludedAmount - taxableSubtotal,
    service: serviceIncludedAmount - taxIncludedAmount,
    total,
  };
}

// =========================
// API
// =========================

// --------------------
// 宣材ファイルアップロード（画像/動画）
// --------------------
app.post("/api/upload/promo", upload.single("file"), (req, res) => {
  if (!req.file) {
    return res.status(400).json({ error: "file not found" });
  }

  // Flutter にはこのURLを返す（Webで見えるパス）
  const url = `/uploads/promos/${req.file.filename}`;
  res.json({ url });
});

// --------------------
// メニュー取得（編集用・原本）
// --------------------
app.get("/api/menu", (req, res) => {
  try {
    const items = store.getMenuRawItems();
    res.json(items);
  } catch (e) {
    console.error("MENU LOAD ERROR:", e);
    res.status(500).json({ error: "failed to load menu" });
  }
});

// --------------------
// メニュー保存（productId 安定化）
// --------------------
app.post("/api/menu", (req, res) => {
  console.log("POST /api/menu received");
  console.log("items length =", req.body.items?.length);

  const { items } = req.body;
  if (!Array.isArray(items)) {
    return res.status(400).json({ error: "items is required" });
  }

  const existing = loadExistingMap();

  let nextId = 1;
  for (const pid of existing.values()) {
    const n = Number(String(pid).replace("p_", ""));
    if (!isNaN(n)) nextId = Math.max(nextId, n + 1);
  }

  const stabilized = items.map((it) => {
    const key = makeKey(it);
    let productId = existing.get(key);
    if (!productId) productId = `p_${nextId++}`;
    return { ...it, productId };
  });

  fs.writeFileSync(
    MENU_PATH,
    JSON.stringify({ version: 2, updatedAt: new Date(), items: stabilized }, null, 2)
  );

  store.products.clear();
  for (const it of stabilized) {
    store.products.set(it.productId, it);
  }

  res.json({ success: true });
});

// --------------------
// オーダー表 手動印刷
// --------------------
app.post("/api/print/order", async (req, res) => {
  const { tableId, target } = req.body;

  if (!tableId || !target) {
    return res.json({ success: false, message: "tableId and target are required" });
  }

  try {
    const result = await printOrderSlip({ tableId, target });
    return res.json({ success: true, ...result });
  } catch (e) {
    console.error("PRINT ORDER ERROR:", e);
    return res.json({ success: false, message: "print failed" });
  }
});

// --------------------
// 会計伝票 印刷
// --------------------
app.post("/api/print/receipt", async (req, res) => {
  const { tableId } = req.body;
  if (!tableId) {
    return res.json({ success: false, message: "tableId is required" });
  }

  try {
    const summary = calcReceiptSummary(tableId);

    const text = buildReceiptText({
      tableId,
      items: summary.items.map((i) => ({
        name: i.name,
        qty: i.quantity,
        priceEx: i.price,
      })),
      summary: {
        taxableSubtotal: summary.taxableSubtotal,
        tax: summary.tax,
        service: summary.service,
        total: summary.total,
      },
    });

    console.log("=== PRINT RECEIPT TEXT ===");
    console.log(text);

    await printTextWindows(text, "receipt");

    return res.json({ success: true });
  } catch (e) {
    console.error("PRINT RECEIPT ERROR:", e);
    return res.json({ success: false, message: "print failed" });
  }
});

// =========================
// キャストドリンク（GET/POST）
// =========================
const CAST_DRINKS_FILE = path.join(__dirname, "data", "cast_drinks.json");

app.get("/api/cast-drinks", (req, res) => {
  try {
    if (!fs.existsSync(CAST_DRINKS_FILE)) return res.json([]);

    const json = JSON.parse(fs.readFileSync(CAST_DRINKS_FILE, "utf8") || "{}");
    res.json(json.items || []);
  } catch (_) {
    res.json([]);
  }
});

app.post("/api/cast-drinks", (req, res) => {
  const items = req.body.items;
  if (!Array.isArray(items)) {
    return res.status(400).json({ error: "items is required" });
  }

  fs.writeFileSync(
    CAST_DRINKS_FILE,
    JSON.stringify({ updatedAt: new Date(), items }, null, 2),
    "utf8"
  );

  res.json({ success: true });
});

// =========================
// キャスト（GET/POST）
// =========================
const CASTS_FILE = path.join(__dirname, "data", "casts.json");

app.get("/api/casts", (req, res) => {
  try {
    if (!fs.existsSync(CASTS_FILE)) return res.json({ casts: [] });

    const raw = fs.readFileSync(CASTS_FILE, "utf-8");
    if (!raw) return res.json({ casts: [] });

    const json = JSON.parse(raw);
    const casts = Array.isArray(json.casts) ? json.casts : [];
    res.json({ casts });
  } catch (_) {
    res.json({ casts: [] });
  }
});

app.post("/api/casts", (req, res) => {
  try {
    const casts = Array.isArray(req.body.casts) ? req.body.casts : [];
    fs.writeFileSync(CASTS_FILE, JSON.stringify({ casts }, null, 2), "utf-8");
    res.json({ ok: true });
  } catch (_) {
    res.status(500).json({ ok: false });
  }
});

// =========================
// セット（GET/POST）
// =========================
const SETS_FILE = path.join(__dirname, "data", "sets.json");

app.get("/api/sets", (req, res) => {
  try {
    if (!fs.existsSync(SETS_FILE)) return res.json({ sets: [] });

    const raw = fs.readFileSync(SETS_FILE, "utf-8");
    if (!raw) return res.json({ sets: [] });

    const json = JSON.parse(raw);
    const sets = Array.isArray(json.sets) ? json.sets : [];
    res.json({ sets });
  } catch (_) {
    res.json({ sets: [] });
  }
});

app.post("/api/sets", (req, res) => {
  try {
    const sets = Array.isArray(req.body.sets) ? req.body.sets : [];
    fs.writeFileSync(SETS_FILE, JSON.stringify({ sets }, null, 2), "utf-8");
    res.json({ ok: true });
  } catch (_) {
    res.status(500).json({ ok: false });
  }
});

// =========================
// その他（GET/POST）
// =========================
const OTHER_ITEMS_FILE = path.join(__dirname, "data", "other_items.json");

app.get("/api/other-items", (req, res) => {
  try {
    if (!fs.existsSync(OTHER_ITEMS_FILE)) return res.json({ items: [] });

    const raw = fs.readFileSync(OTHER_ITEMS_FILE, "utf8");
    const json = JSON.parse(raw || "{}");
    res.json({ items: json.items || [] });
  } catch (e) {
    console.error("other-items GET error", e);
    res.json({ items: [] });
  }
});

app.post("/api/other-items", (req, res) => {
  try {
    const items = req.body.items;
    if (!Array.isArray(items)) {
      return res.status(400).json({ error: "items must be array" });
    }

    fs.writeFileSync(
      OTHER_ITEMS_FILE,
      JSON.stringify({ items }, null, 2),
      "utf8"
    );

    res.json({ ok: true });
  } catch (e) {
    console.error("other-items POST error", e);
    res.status(500).json({ error: "save failed" });
  }
});

// =========================
// 宣材（GET/POST）
// =========================
const PROMOS_FILE = path.join(__dirname, "data", "promos.json");

app.get("/api/promos", (req, res) => {
  try {
    if (!fs.existsSync(PROMOS_FILE)) {
      return res.json({ top: [], bottom: [] });
    }

    const raw = fs.readFileSync(PROMOS_FILE, "utf8");
    const json = JSON.parse(raw || "{}");

    res.json({
      top: Array.isArray(json.top) ? json.top : [],
      bottom: Array.isArray(json.bottom) ? json.bottom : [],
    });
  } catch (e) {
    console.error("promos GET error", e);
    res.json({ top: [], bottom: [] });
  }
});

app.post("/api/promos", (req, res) => {
  try {
    const { top, bottom } = req.body;

    if (!Array.isArray(top) || !Array.isArray(bottom)) {
      return res.status(400).json({ error: "top and bottom must be arrays" });
    }

    fs.writeFileSync(
      PROMOS_FILE,
      JSON.stringify({ top, bottom }, null, 2),
      "utf8"
    );

    res.json({ ok: true });
  } catch (e) {
    console.error("promos POST error", e);
    res.status(500).json({ error: "save failed" });
  }
});

// =========================
// listen（必ず最後）
// =========================


app.post("/api/promos/delete-file", (req, res) => {
  const { url } = req.body;
  if (!url) {
    return res.status(400).json({ error: "url required" });
  }

  // /uploads/promos/xxx.jpg → 実ファイルパス
  const filePath = path.join(__dirname, url);

  // uploads 配下以外は削除させない（安全）
  if (!filePath.startsWith(path.join(__dirname, "uploads"))) {
    return res.status(400).json({ error: "invalid path" });
  }

  if (fs.existsSync(filePath)) {
    fs.unlinkSync(filePath);
  }

  res.json({ ok: true });
});

// =========================
// 注文確定（最小・ダミー）
// =========================
 app.post("/api/orders", (req, res) => {
  console.log("ORDER RECEIVED", req.body);

  // Flutter 側の payload が items/lines/order のどれでも動くように吸収
  const tableId = String(req.body.tableId ?? req.body.table ?? "");
  const rawItems =
    (Array.isArray(req.body.items) && req.body.items) ||
    (Array.isArray(req.body.lines) && req.body.lines) ||
    (req.body.order && Array.isArray(req.body.order.lines) && req.body.order.lines) ||
    [];

  if (!tableId || rawItems.length === 0) {
    return res.status(400).json({ error: "invalid payload (tableId/items)" });
  }

 // ★ 注文確定時：テーブルは必ず「開始中」にする（正本）
store.openTable(tableId);



  // ② orderId を作る
  const orderId = "order_" + Date.now();

  // ③ テーブル → orderId を紐づけ
  if (!store.ordersByTable.has(tableId)) {
    store.ordersByTable.set(tableId, []);
  }
  store.ordersByTable.get(tableId).push(orderId);

  // ④ orderId → itemIds を作る（getTableItems がここを見る）
  if (!store.orderItemsByOrder) store.orderItemsByOrder = new Map();
  const itemIds = [];

  // ⑤ item を 1件ずつ store.orderItems に保存（key は itemId）
  //    ※ printOrderSlip が見る shape に寄せる
  // ★ 既存の RT スナップショットを上書き（payload は合算済み想定）
  const snap = store.getTableOrderSnapshot(tableId);
  snap.items = [];

  rawItems.forEach((it, idx) => {
    const itemId = `item_${Date.now()}_${idx}`;

    const quantity = Number(it.qty ?? it.quantity ?? 1);
    const price = Number(it.price ?? 0);

    const name =
      it.name ??
      (it.brand && it.label ? `${it.brand} / ${it.label}` : (it.label ?? "unknown"));

    const printTarget = it.printGroup ?? it.printTarget ?? "kitchen";

    const normalized = {
      id: itemId,
      orderId,
      tableId,
      productId: it.productId ?? null,
      name,
      price,
      quantity,
      printTarget,                 // 'kitchen' / 'register'
      printed: { kitchen: false, register: false, receipt: false },
      orderedBy: req.body.orderedBy ?? "guest",
      createdAt: new Date().toISOString(),
    };

    store.orderItems.set(itemId, normalized);
    itemIds.push(itemId);

    

    if (normalized.productId) {
      store.addTableItem(tableId, {
        productId: normalized.productId,
        qty: quantity,
        addedBy: normalized.orderedBy,
      });
    } else {
      store.addTableItemSnapshot(tableId, {
        name,
        price,
        qty: quantity,
        addedBy: normalized.orderedBy,
      });
    }
  });

  store.orderItemsByOrder.set(orderId, itemIds);

  // ⑥ 全端末に snapshot 配信
  broadcastSnapshot();

  res.json({ ok: true, orderId, itemCount: itemIds.length });


});


// =========================
// =========================
// snapshot 作成（RT 正本）
// =========================
function buildSnapshot() {
  return {
    type: "snapshot",
    payload: store.buildRealtimeSnapshot(), // ★ ここが正本
  };
}

  // ★ ここを追加 ★

///////////////////
function broadcastSnapshot() {
  const data = JSON.stringify(buildSnapshot()); // ★ここだけ
  for (const client of wss.clients) {
    if (client.readyState === WebSocket.OPEN) {
      client.send(data);
    }
  }
}

// =========================
// listen（必ず最後）
// =========================
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });
wss.on("connection", (ws) => {
  console.log("WebSocket connected. clients =", wss.clients.size);

  // 接続時に snapshot を1回送る（既存の buildSnapshot を使う）
  ws.send(JSON.stringify(buildSnapshot()));


  ws.on("close", () => {
    console.log("WebSocket disconnected. clients =", wss.clients.size);
  });
});


server.listen(3000, () => {
  console.log("server started :3000");
});
// =========================
// RT 注文：追加（tableOrders 用）
// =========================
app.post("/api/rt/tables/:tableId/items", (req, res) => {
  try {
    const { tableId } = req.params;
    const { productId, qty, addedBy } = req.body;
     // ★ 追加：開始チェック
    const table = store.getTable(tableId);
    if (!table || table.status !== "ordering") {
      return res.status(400).json({ ok: false, error: "table not active" });
    }

    const line = store.addTableItem(tableId, {
      productId,
      qty,
      addedBy, // "guest" or "owner"
    });

    // ★ 追加後に全端末へ snapshot 配信
    broadcastSnapshot();

    res.json({ ok: true, line });
  } catch (e) {
    console.error("RT ADD ERROR:", e);
    res.status(400).json({ ok: false, error: e.message });
  }
});
// =========================
// RT 注文：数量変更（tableOrders 用）
// =========================
app.patch("/api/rt/tables/:tableId/items/:lineId", (req, res) => {
  try {
    const { tableId, lineId } = req.params;
    const { qty } = req.body;

    const line = store.updateTableItemQty(tableId, lineId, qty);

    // ★ 変更後に全端末へ snapshot 配信
    broadcastSnapshot();

    res.json({ ok: true, line });
  } catch (e) {
    console.error("RT QTY UPDATE ERROR:", e);
    res.status(400).json({ ok: false, error: e.message });
  }
});
// =========================
// RT 注文：削除（tableOrders 用）
// =========================
app.delete("/api/rt/tables/:tableId/items/:lineId", (req, res) => {
  try {
    const { tableId, lineId } = req.params;

    store.removeTableItem(tableId, lineId);

    // ★ 削除後に全端末へ snapshot 配信
    broadcastSnapshot();

    res.json({ ok: true });
  } catch (e) {
    console.error("RT DELETE ERROR:", e);
    res.status(400).json({ ok: false, error: e.message });
  }
});
// =========================
// RT：テーブル開始
// =========================
app.post("/api/rt/tables/:tableId/start", (req, res) => {
  try {
    const { tableId } = req.params;

    // 既存ロジックを再利用
    store.openTable(tableId);

    // ★ status を realtime で配信
    broadcastSnapshot();

    res.json({ ok: true });
  } catch (e) {
    console.error("RT TABLE START ERROR:", e);
    res.status(400).json({ ok: false, error: e.message });
  }
});
// =========================
// テーブル開始
// =========================
app.post("/api/rt/tables/:tableId/start", (req, res) => {
  const { tableId } = req.params;

  try {
    store.openTable(tableId);   // ★ 正本はサーバー
    broadcastSnapshot();        // ★ 全端末に通知
    res.json({ ok: true });
  } catch (e) {
    res.status(400).json({ ok: false, error: e.message });
  }
});

// =========================
// テーブル終了
// =========================
app.post("/api/rt/tables/:tableId/end", (req, res) => {
  const { tableId } = req.params;

  try {
    store.closeTable(tableId);
    broadcastSnapshot();
    res.json({ ok: true });
  } catch (e) {
    res.status(400).json({ ok: false, error: e.message });
  }
});
