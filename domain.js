// src/domain.js
const TABLE_STATUS = {
  ordering: "ordering",
  precheck: "precheck",
  closed: "closed",
};

function assertTableStatus(value) {
  const ok = Object.values(TABLE_STATUS).includes(value);
  if (!ok) {
    throw new Error(`Invalid table status: ${value}`);
  }
}

function nowIso() {
  return new Date().toISOString();
}

// ★ ここから追加
function buildReceiptText({ tableId, items, summary }) {
  const lines = [];

  lines.push('────────────────────');
  lines.push('        会 計 伝 票');
  lines.push('────────────────────');
  lines.push(`席：${tableId}`);
  lines.push('');
  lines.push('[ 注文明細 ]');

  for (const item of items) {
    const name = item.name.padEnd(14, ' ');
    const qty  = `×${item.qty}`.padStart(4, ' ');
    const lineTotal = item.priceEx * item.qty;
    const price = `¥${lineTotal.toLocaleString()}`.padStart(8, ' ');

    lines.push(`${name}${qty} ${price}`);
  }

  lines.push('');
  lines.push('────────────────────');
  lines.push(`課税対象小計           ¥${summary.taxableSubtotal.toLocaleString()}`);
  lines.push(`消費税（10%）            ¥${summary.tax.toLocaleString()}`);
  lines.push(`サービス料（25%）        ¥${summary.service.toLocaleString()}`);
  lines.push('────────────────────');
  lines.push(`合計                   ¥${summary.total.toLocaleString()}`);
  lines.push('────────────────────');

  return lines.join('\n');
}
// ★ ここまで追加

module.exports = {
  TABLE_STATUS,
  assertTableStatus,
  nowIso,
  buildReceiptText, // ← これを足す
};
