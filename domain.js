const TABLE_STATUS = {
  ordering: "ordering",
  precheck: "precheck",
  closed: "closed",
};

function assertTableStatus(value) {
  if (!Object.values(TABLE_STATUS).includes(value)) {
    throw new Error(`Invalid table status: ${value}`);
  }
}

function nowIso() {
  return new Date().toISOString();
}

// ----------------
// padding
// ----------------
function isWideChar(c) {
  const code = c.charCodeAt(0);
  return (
    (code >= 0x3000 && code <= 0x9fff) ||
    (code >= 0xff00 && code <= 0xffef)
  );
}

function displayWidth(str) {
  let w = 0;
  for (const c of String(str ?? "")) {
    w += isWideChar(c) ? 2 : 1;
  }
  return w;
}

function padEnd(text, width) {
  text = String(text ?? "");
  const w = displayWidth(text);
  if (w >= width) return text;
  return text + " ".repeat(width - w);
}

function padStart(text, width) {
  text = String(text ?? "");
  const w = displayWidth(text);
  if (w >= width) return text;
  return " ".repeat(width - w) + text;
}

// ----------------
// 金額
// ----------------
function yen(n) {
  return "¥" + Number(n).toLocaleString();
}

// ----------------
// 折り返し
// ----------------
function wrap(text, width) {
  const lines = [];
  let rest = String(text ?? "");
  while (displayWidth(rest) > width) {
    let w = 0;
    let i = 0;
    for (const c of rest) {
      const cw = isWideChar(c) ? 2 : 1;
      if (w + cw > width) break;
      w += cw;
      i += c.length;
    }
    lines.push(rest.slice(0, i));
    rest = rest.slice(i);
  }
  lines.push(rest);
  return lines;
}

// ----------------
// レシート
// ----------------
//
// buildReceiptText はESC/POSコマンドを一切含まないセグメント配列を返す。
// 各セグメントは { type, text?, align?, emphasis?, dblSize?, dblWidth? } の形式。
// printer.js 側でセグメントを見てコマンドを組み立てる。
//
// type一覧:
//   "text"   : テキスト行（改行含む）
//   "title"  : タイトル行（中央寄せ・縦横2倍）
//   "total"  : 合計行（強調・1行に合計ラベルと金額を並べる）

function buildReceiptText({ tableId, items, summary }) {

  const receiptWidth = 42;
  const qtyWidth     = 4;
  const priceWidth   = 11;
  const labelWidth   = receiptWidth - priceWidth;
  const rule         = "-".repeat(receiptWidth);
  const dblRule      = "=".repeat(receiptWidth);

  const segments = [];
  const t = (text) => segments.push({ type: "text", text });

  // タイトル（中央寄せ・縦横2倍）
  segments.push({ type: "title", text: "御会計伝票" });

  t(rule + "\n");
  t(`席：${tableId}\n`);
  t("\n");
  t("[ 注文明細 ]\n");
  t("商品名\n");
  t(rule + "\n");

  for (const item of items) {
    const names = wrap(item.name, receiptWidth);
    for (const name of names) {
      t(name + "\n");
    }
    const qty   = padStart("×" + item.qty, qtyWidth);
    const price = padStart(yen(item.priceEx * item.qty), priceWidth);
    t(" ".repeat(receiptWidth - qtyWidth - priceWidth) + qty + price + "\n");
  }

  t("\n");
  t(rule + "\n");

  t(padEnd("課税対象小計", labelWidth) + padStart(yen(summary.taxableSubtotal), priceWidth) + "\n");
  t(padEnd("消費税(10%)",  labelWidth) + padStart(yen(summary.tax),             priceWidth) + "\n");
  t(padEnd("サービス料(25%)", labelWidth) + padStart(yen(summary.service),      priceWidth) + "\n");

  t(dblRule + "\n");

  // 合計（強調・1行）
  segments.push({ type: "total", label: "合計", amount: yen(summary.total), labelWidth, priceWidth });

  t("\n");
  t(dblRule + "\n");

  // フッター（中央寄せ）
  segments.push({ type: "footer", text: "ありがとうございました" });

  return segments;
}

module.exports = {
  TABLE_STATUS,
  assertTableStatus,
  nowIso,
  buildReceiptText,
};