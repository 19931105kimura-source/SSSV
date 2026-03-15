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

function isWideChar(c) {
  const code = c.charCodeAt(0);
  // U+00D7(×)はcp932で全角2バイトとして印字される
  if (code === 0x00D7) return true;
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

function yen(n) {
  return "¥" + Number(n).toLocaleString();
}

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
function normalizeName(text) {
  return String(text ?? "")
    .replace(/[─━]/g, "-")
    .replace(/[（]/g, "(")
    .replace(/[）]/g, ")")
    .replace(/\u3000/g, "  ");
}  // ← ここで閉じる

function buildReceiptText({ tableId, items, summary }) {

  const receiptWidth = 42;
  const qtyWidth     = 3;
  const priceWidth   = 11;
  const nameWidth    = receiptWidth - qtyWidth - priceWidth - 1; // 28
  //変更後
const rule    = "-".repeat(receiptWidth - 1);  // 41文字
const dblRule = "=".repeat(receiptWidth - 1);  // 41文字

  const segments = [];
  const t  = (text)        => segments.push({ type: "text", text });
  // CR上書き方式で左ラベル・右金額を揃えるセグメント
  const lr = (label, amount) => segments.push({ type: "labelright", label, amount, priceWidth });

  segments.push({ type: "title", text: "御会計伝票" });

  t(rule + "\n");
  t(`席：${tableId}\n`);
  t("\n");
  t("[ 注文明細 ]\n");
  t("商品名                     数量   金額\n");
  t(rule + "\n");

  for (const item of items) {
    const names = wrap(normalizeName(item.name), nameWidth);
    segments.push({
      type:      "item",
      name:      names[0],
      nameExtra: names.slice(1),
      qty:       String(item.qty),
      price:     yen(item.priceEx * item.qty),
      nameWidth,
      qtyWidth,
      priceWidth,
    });
  }

  t("\n");
  t(rule + "\n");

  // 税系はCR上書きで金額を右端固定
  lr("課税対象小計", yen(summary.taxableSubtotal));
  lr("消費税(10%)",  yen(summary.tax));
  lr("サービス料(25%)", yen(summary.service));

  t(dblRule + "\n");

  // 合計（縦横2倍＋太字）
  segments.push({ type: "total", label: "合計", amount: yen(summary.total), priceWidth });

  t("\n");
  t(dblRule + "\n");

  segments.push({ type: "footer", text: "ありがとうございました" });

  return segments;
}

module.exports = {
  TABLE_STATUS,
  assertTableStatus,
  nowIso,
  buildReceiptText,
};