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

function readIntEnv(name, fallback) {
  const n = Number(process.env[name]);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : fallback;
}

function isWideChar(char) {
  return /[\u1100-\u115F\u2E80-\uA4CF\uAC00-\uD7A3\uF900-\uFAFF\uFE10-\uFE19\uFE30-\uFE6F\uFF01-\uFF60\uFFE0-\uFFE6]/.test(
    char
  );
}

function stringDisplayWidth(value) {
  return Array.from(String(value ?? "")).reduce(
    (sum, char) => sum + (isWideChar(char) ? 2 : 1),
    0
  );
}

function padDisplayEnd(value, width) {
  const text = String(value ?? "");
  const current = stringDisplayWidth(text);
  if (current >= width) return text;
  return text + " ".repeat(width - current);
}

function padDisplayStart(value, width) {
  const text = String(value ?? "");
  const current = stringDisplayWidth(text);
  if (current >= width) return text;
  return " ".repeat(width - current) + text;
}

function makeRuleLine(name, fallbackWidth = 20, fallbackChar = "─") {
  const width = readIntEnv(name, fallbackWidth);
  const char = process.env[`${name}_CHAR`] || fallbackChar;
  return char.repeat(width);
}

////会計伝票のテキスト///////////////
function buildReceiptText({ tableId, items, summary }) {
  const ruleLine = makeRuleLine("RECEIPT_RULE_WIDTH");//////罫線の長さ
  const titleIndent = readIntEnv("RECEIPT_TITLE_INDENT", 16);//////タイトルのインデント（スペース数）
  const nameWidth = readIntEnv("RECEIPT_NAME_WIDTH", 14);/////品名幅
  const qtyWidth = readIntEnv("RECEIPT_QTY_WIDTH", 16);//////数量幅
  const priceWidth = readIntEnv("RECEIPT_PRICE_WIDTH", 16);//////金額幅
  const labelWidth = readIntEnv("RECEIPT_SUMMARY_LABEL_WIDTH", 22);//////集計ラベル幅 

  const lines = [];

  lines.push(ruleLine);
  lines.push(`${" ".repeat(titleIndent)}御 会 計 伝 票`);
  lines.push(ruleLine);
  lines.push(`席：${tableId}`);
  lines.push('');
  lines.push('[ 注文明細 ]');

  for (const item of items) {
    const name = padDisplayEnd(item.name, nameWidth);
    const qty  = padDisplayStart(`×${item.qty}`, qtyWidth);
    const lineTotal = item.priceEx * item.qty;
    const price = padDisplayStart(`¥${lineTotal.toLocaleString()}`, priceWidth);

    lines.push(`${name}${qty} ${price}`);
  }

  lines.push('');
  lines.push(ruleLine);
  lines.push(`${padDisplayEnd("課税対象小計", labelWidth)}${padDisplayStart(`¥${summary.taxableSubtotal.toLocaleString()}`, priceWidth)}`);
  lines.push(`${padDisplayEnd("消費税（10%）", labelWidth)}${padDisplayStart(`¥${summary.tax.toLocaleString()}`, priceWidth)}`);
  lines.push(`${padDisplayEnd("サービス料（25%）", labelWidth)}${padDisplayStart(`¥${summary.service.toLocaleString()}`, priceWidth)}`);
  lines.push(ruleLine);
  lines.push(`${padDisplayEnd("合計", labelWidth)}${padDisplayStart(`¥${summary.total.toLocaleString()}`, priceWidth)}`);
  lines.push(ruleLine);


  return lines.join('\n');
}
// ★ ここまで追加

module.exports = {
  TABLE_STATUS,
  assertTableStatus,
  nowIso,
  buildReceiptText, // ← これを足す
};
