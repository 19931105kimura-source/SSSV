// src/store.js
const fs = require("fs");
const path = require("path");

const { nextOrderId, nextOrderItemId } = require("./ids");
const { TABLE_STATUS, nowIso } = require("./domain");

class Store {
  constructor() {
    this.products = new Map();
    this.tables = new Map();
    this.orders = new Map();
    this.orderItems = new Map();

    this.ordersByTable = new Map();      // tableId -> orderId[]
    this.orderItemsByOrder = new Map();  // orderId -> orderItemId[]

    // ★ RT / UI 用：席注文 snapshot
    this.tableOrders = new Map();        // tableId -> TableOrder

    // ----- menu.json から商品ロード -----
    const menuPath = path.join(__dirname, "..", "data", "menu.json");
    const raw = fs.readFileSync(menuPath, "utf-8");
    const menu = JSON.parse(raw);

    for (const item of menu.items) {
      this.products.set(item.productId, item);
    }
  }

  // ---------- Product ----------
  listActiveProducts() {
    return Array.from(this.products.values()).filter(p => p.isActive);
  }

  getProduct(productId) {
    return this.products.get(productId) || null;
  }

  // ---------- Menu Raw (for editor) ----------
  getMenuRawItems() {
    return Array.from(this.products.values());
  }

  // ---------- Table ----------
  openTable(tableId) {
    const existing = this.tables.get(tableId);
    if (existing && existing.status !== TABLE_STATUS.closed) {
      return existing;
    }

    const table = {
      tableId,
      status: TABLE_STATUS.ordering,
      openedAt: nowIso(),
      closedAt: null,
    };

    this.tables.set(tableId, table);
    if (!this.ordersByTable.has(tableId)) {
      this.ordersByTable.set(tableId, []);
    }
    return table;
  }

  getTable(tableId) {
    return this.tables.get(tableId) || null;
  }

  closeTable(tableId) {
    const table = this.tables.get(tableId);
    if (!table) {
      throw new Error(`Table not found: ${tableId}`);
    }
    table.status = TABLE_STATUS.closed;
    table.closedAt = nowIso();
    return table;
  }

  // ---------- Order（確定・印刷用：既存） ----------
  createOrder({ tableId, orderedBy, items }) {
    const table = this.getTable(tableId) || this.openTable(tableId);
    if (table.status === TABLE_STATUS.closed) {
      throw new Error(`Table is closed: ${tableId}`);
    }

    const orderId = nextOrderId();
    const order = {
      orderId,
      tableId,
      orderedAt: nowIso(),
      orderedBy,
      printed: false,
    };

    this.orders.set(orderId, order);

    const orderIds = this.ordersByTable.get(tableId);
    orderIds.push(orderId);

    const orderItemIds = [];

    for (const req of items) {
      const product = this.getProduct(req.productId);
      if (!product || !product.isActive) {
        throw new Error(`Invalid productId: ${req.productId}`);
      }

      const quantity = Number(req.quantity);
      if (!Number.isInteger(quantity) || quantity <= 0) {
        throw new Error(`Invalid quantity for productId=${req.productId}`);
      }
        this.addTableItem(tableId, {
    productId: product.productId,
    qty: quantity,
    addedBy: orderedBy,
  });
      const orderItemId = nextOrderItemId();
      const orderItem = {
        orderItemId,
        orderId,
        productId: product.productId,
        name: product.name,
        price: product.price,
        quantity,
        printTarget: product.printTarget || "none",
        printed: {
          drink: false,
          food: false,
        },
      };

      this.orderItems.set(orderItemId, orderItem);
      orderItemIds.push(orderItemId);
    }

    this.orderItemsByOrder.set(orderId, orderItemIds);

    return {
      order,
      orderItems: orderItemIds.map(id => this.orderItems.get(id)),
    };
  }

  markOrderPrinted(orderId) {
    const order = this.orders.get(orderId);
    if (!order) {
      throw new Error(`Order not found: ${orderId}`);
    }
    order.printed = true;
    return order;
  }

  // ---------- Snapshot（既存・会計用） ----------
  getTableSnapshot(tableId) {
    const table = this.getTable(tableId);
    if (!table) return null;

    const orderIds = this.ordersByTable.get(tableId) || [];
    const orders = orderIds.map(id => this.orders.get(id)).filter(Boolean);

    const orderItems = [];
    for (const order of orders) {
      const itemIds = this.orderItemsByOrder.get(order.orderId) || [];
      for (const itemId of itemIds) {
        const item = this.orderItems.get(itemId);
        if (item) orderItems.push(item);
      }
    }

    return { table, orders, orderItems };
  }

  // ---------- Checkout ----------
  calcCheckout(tableId) {
    const snap = this.getTableSnapshot(tableId);
    if (!snap) {
      throw new Error(`Table not found: ${tableId}`);
    }

    const lines = new Map();

    for (const item of snap.orderItems) {
      const cur = lines.get(item.productId) || {
        productId: item.productId,
        name: item.name,
        price: item.price,
        quantity: 0,
        amount: 0,
      };
      cur.quantity += item.quantity;
      cur.amount += item.price * item.quantity;
      lines.set(item.productId, cur);
    }

    const details = Array.from(lines.values());
    const total = details.reduce((sum, d) => sum + d.amount, 0);

    return {
      tableId,
      openedAt: snap.table.openedAt,
      details,
      total,
    };
  }

  // ---------- Print Data Builder ----------
  buildPrintJobs(orderId) {
    const order = this.orders.get(orderId);
    if (!order) {
      throw new Error(`Order not found: ${orderId}`);
    }

    const itemIds = this.orderItemsByOrder.get(orderId) || [];
    const items = itemIds
      .map(id => this.orderItems.get(id))
      .filter(Boolean);

    const jobs = {
      drink: [],
      food: [],
    };

    for (const item of items) {
      if (item.printTarget === "drink") {
        jobs.drink.push(item);
      } else if (item.printTarget === "food") {
        jobs.food.push(item);
      }
    }

    return {
      orderId,
      tableId: order.tableId,
      orderedAt: order.orderedAt,
      jobs,
    };
  }

  // ==================================================
  // ===== Table Order Snapshot（RT / UI 用・新規）=====
  // ==================================================

  _makeLineId() {
    return "l_" + Math.random().toString(36).slice(2, 10);
  }

  getTableOrderSnapshot(tableId) {
    const key = String(tableId);
    let snap = this.tableOrders.get(key);

    if (!snap) {
      snap = {
        tableId: key,
        openedAt: nowIso(),
        items: [],
      };
      this.tableOrders.set(key, snap);
    }
    return snap;
  }

    addTableItem(tableId, { productId, qty, addedBy }){
    const product = this.getProduct(productId);
    if (!product || !product.isActive) {
      throw new Error(`Invalid productId: ${productId}`);
    }

    const quantity = Number(qty);
    if (!Number.isInteger(quantity) || quantity <= 0) {
      throw new Error("Invalid qty");
    }

    const snap = this.getTableOrderSnapshot(tableId);

    const line = {
      lineId: this._makeLineId(),
      productId: product.productId,
      name: product.name,
      price: product.price,
      qty: quantity,
      addedBy: addedBy === "owner" ? "owner" : "guest",
    };

    snap.items.push(line);
    return line;
  }

  addTableItemSnapshot(tableId, { name, price, qty, addedBy }) {
    const quantity = Number(qty);
    if (!Number.isInteger(quantity) || quantity <= 0) {
      throw new Error("Invalid qty");
    }

    const snap = this.getTableOrderSnapshot(tableId);

    const line = {
      lineId: this._makeLineId(),
      productId: null,
      name: name ?? "",
      price: Number(price) || 0,
      qty: quantity,
      addedBy: addedBy === "owner" ? "owner" : "guest",
    };

    snap.items.push(line);
    return line;
  }


  addTableItemSnapshot(tableId, { name, price, qty, addedBy }) {
    const quantity = Number(qty);
    if (!Number.isInteger(quantity) || quantity <= 0) {
      throw new Error("Invalid qty");
    }

    const snap = this.getTableOrderSnapshot(tableId);

    const line = {
      lineId: this._makeLineId(),
      productId: null,
      name: name ?? "",
      price: Number(price) || 0,
      qty: quantity,
      addedBy: addedBy === "owner" ? "owner" : "guest",
    };

    snap.items.push(line);
    return line;
  }

  updateTableItemQty(tableId, lineId, qty) {
    const snap = this.getTableOrderSnapshot(tableId);
    const q = Number(qty);

    if (!Number.isInteger(q) || q <= 0) {
      throw new Error("Invalid qty");
    }

    const item = snap.items.find(i => i.lineId === String(lineId));
    if (!item) {
      throw new Error("Line not found");
    }

    item.qty = q;
    return item;
  }

  removeTableItem(tableId, lineId) {
    const snap = this.getTableOrderSnapshot(tableId);
    const before = snap.items.length;

    snap.items = snap.items.filter(i => i.lineId !== String(lineId));

    if (before === snap.items.length) {
      throw new Error("Line not found");
    }
  }

  removeTableItemsByNamePrice(tableId, name, price) {
    const snap = this.getTableOrderSnapshot(tableId);
    const targetName = String(name ?? "");
    const targetPrice = Number(price ?? 0);
    const before = snap.items.length;

    snap.items = snap.items.filter(
      i =>
        String(i.name ?? "") !== targetName ||
        Number(i.price ?? 0) !== targetPrice,
    );

    if (before === snap.items.length) {
      throw new Error("Line not found");
    }

    return before - snap.items.length;
  }
  buildRealtimeSnapshot() {
    const tables = {};
    const ordersByTable = {};
    const orderItems = {};

    // ★ 追加：tables（使用中/closed 等）を正本として全席を流す
    for (const [tableId, table] of this.tables.entries()) {
      const order = this.tableOrders.get(tableId) ?? {
        tableId,
        openedAt: table.openedAt,
        items: [],
      };

      tables[tableId] = {
        tableId,
        status: table.status, // ★ ordering / closed
        openedAt: table.openedAt,
        order, // ★ 注文スナップショット（items）
      };

      const rtOrderId = `rt_${tableId}`;
      ordersByTable[tableId] = [rtOrderId];
      orderItems[rtOrderId] = (order.items || []).map((item) => ({
        lineId: item.lineId,
        category: "",
        brand: "",
        name: item.name ?? "",
        label: item.name ?? "",
        price: item.price ?? 0,
        qty: item.qty ?? 0,
        quantity: item.qty ?? 0,
        section: null,
        subCategory: "",
        shouldPrint: true,
        printGroup: "kitchen",
      }));
    }

    return {
      tables,
      ordersByTable,
      orderItems,
      at: nowIso(),
    };
  }
}
const store = new Store();
module.exports = { store };