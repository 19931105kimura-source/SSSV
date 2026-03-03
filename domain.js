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
  return /[ᄀ-ᅟ⺀-꓏가-힣豈-﫿︐-︙︰-﹯！-｠￠-￦]/.test(
    char
  );
}

function stringDisplayWidth(value) {
  return Array.from(String(value ?? "")).reduce(
    (sum, char) => sum + (isWideChar(char) ? 2 : 1),
    0
  );
}

function sliceDisplayStart(value, width) {
  if (width <= 0) return "";
  let used = 0;
  let result = "";
  for (const char of Array.from(String(value ?? ""))) {
    const w = isWideChar(char) ? 2 : 1;
    if (used + w > width) break;
    result += char;
    used += w;
  }
  return result;
}

function sliceDisplayEnd(value, width) {
  if (width <= 0) return "";
  let used = 0;
  let result = "";
  const chars = Array.from(String(value ?? ""));
  for (let i = chars.length - 1; i >= 0; i -= 1) {
    const char = chars[i];
    const w = isWideChar(char) ? 2 : 1;
    if (used + w > width) break;
    result = char + result;
    used += w;
  }
  return result;
}

function fitDisplayEnd(value, width) {
  return sliceDisplayStart(value, width);
}

function fitDisplayStart(value, width) {
  return sliceDisplayEnd(value, width);
}

function fitPrefixedStart(value, width, prefix) {
  const text = String(value ?? "");
  if (stringDisplayWidth(text) <= width) return text;
  if (!text.startsWith(prefix) || width <= stringDisplayWidth(prefix)) {
    return fitDisplayStart(text, width);
  }
  const remain = width - stringDisplayWidth(prefix);
  return `${prefix}${sliceDisplayEnd(text.slice(prefix.length), remain)}`;
}

function padDisplayEnd(value, width) {
  const text = fitDisplayEnd(value, width);
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

function centerDisplayText(value, width) {
  const text = fitDisplayEnd(value, width);
  const current = stringDisplayWidth(text);
  if (current >= width) return text;
  const leftPad = Math.floor((width - current) / 2);
  return " ".repeat(leftPad) + text;
}

function makeRuleLine(name, fallbackWidth = 20, fallbackChar = "─") {
  const width = readIntEnv(name, fallbackWidth);
  const char = process.env[`${name}_CHAR`] || fallbackChar;
  return char.repeat(width);
}


function resolveSummaryWidths(receiptWidth, desiredLabel, desiredPrice) {
  let label = Math.max(4, Math.min(desiredLabel, receiptWidth));
  let price = Math.max(6, Math.min(desiredPrice, receiptWidth));

  while (label + price > receiptWidth) {
    if (label >= price && label > 4) {
      label -= 1;
    } else if (price > 6) {
      price -= 1;
    } else if (label > 1) {
      label -= 1;
    } else {
      price = Math.max(1, price - 1);
    }
  }

  return { label, price };
}

function resolveDetailWidths(receiptWidth, desired) {
  const separatorWidth = 1;
  let price = Math.max(6, Math.min(desired.price, receiptWidth));
  let qty = Math.max(4, Math.min(desired.qty, receiptWidth));
  let name = Math.max(4, Math.min(desired.name, receiptWidth));

  while (name + qty + price + separatorWidth > receiptWidth) {
    if (name >= qty && name >= price && name > 4) {
      name -= 1;
    } else if (qty >= price && qty > 4) {
      qty -= 1;
    } else if (price > 6) {
      price -= 1;
    } else if (name > 1) {
      name -= 1;
    } else if (qty > 1) {
      qty -= 1;
    } else {
      price = Math.max(1, price - 1);
    }
  }

  return { name, qty, price, separatorWidth };
}

////会計伝票のテキスト///////////////
function buildReceiptText({ tableId, items, summary }) {
  const ruleLine = makeRuleLine("RECEIPT_RULE_WIDTH");//////罫線の長さ
  const receiptWidth = stringDisplayWidth(ruleLine);
   const desiredNameWidth = readIntEnv("RECEIPT_NAME_WIDTH", 14);
  const desiredQtyWidth = readIntEnv("RECEIPT_QTY_WIDTH", 16);
  const desiredPriceWidth = readIntEnv("RECEIPT_PRICE_WIDTH", 16);
  const desiredLabelWidth = readIntEnv("RECEIPT_SUMMARY_LABEL_WIDTH", 22);

  const detail = resolveDetailWidths(receiptWidth, {
    name: desiredNameWidth,
    qty: desiredQtyWidth,
    price: desiredPriceWidth,
  });

  const summaryWidths = resolveSummaryWidths(receiptWidth, desiredLabelWidth, desiredPriceWidth);
  const summaryLabelWidth = summaryWidths.label;
  const summaryPriceWidth = summaryWidths.price;

  const lines = [];

  lines.push(ruleLine);
  lines.push(centerDisplayText("御会計伝票", receiptWidth));
  lines.push(ruleLine);
   lines.push(fitDisplayEnd(`席：${tableId}`, receiptWidth));
  lines.push("");
  lines.push(fitDisplayEnd("[ 注文明細 ]", receiptWidth));
  lines.push(
    `${padDisplayEnd("商品名", detail.name)}${padDisplayStart("数量", detail.qty)} ${padDisplayStart("金額", detail.price)}`
  );

  lines.push(ruleLine);

for (const item of items) {
    const name = padDisplayEnd(item.name, detail.name);
    const qtyText = fitPrefixedStart(`×${item.qty}`, detail.qty, "×");
    const qty = padDisplayStart(qtyText, detail.qty);
    const lineTotal = item.priceEx * item.qty;
    const priceText = fitPrefixedStart(`¥${lineTotal.toLocaleString()}`, detail.price, "¥");
    const price = padDisplayStart(priceText, detail.price);

    lines.push(`${name}${qty} ${price}`);
  }

  lines.push("");
  lines.push(ruleLine);
  lines.push(
    `${padDisplayEnd("課税対象小計", summaryLabelWidth)}${padDisplayStart(fitPrefixedStart(`¥${summary.taxableSubtotal.toLocaleString()}`, summaryPriceWidth, "¥"), summaryPriceWidth)}`
  );
  lines.push(
    `${padDisplayEnd("消費税（10%）", summaryLabelWidth)}${padDisplayStart(fitPrefixedStart(`¥${summary.tax.toLocaleString()}`, summaryPriceWidth, "¥"), summaryPriceWidth)}`
  );
  lines.push(
    `${padDisplayEnd("サービス料（25%）", summaryLabelWidth)}${padDisplayStart(fitPrefixedStart(`¥${summary.service.toLocaleString()}`, summaryPriceWidth, "¥"), summaryPriceWidth)}`
  );
  lines.push(ruleLine);
  lines.push(
    `${padDisplayEnd("合計", summaryLabelWidth)}${padDisplayStart(fitPrefixedStart(`¥${summary.total.toLocaleString()}`, summaryPriceWidth, "¥"), summaryPriceWidth)}`
  );
  lines.push(ruleLine);

  return lines.join("\n");
}

module.exports = {
  TABLE_STATUS,
  assertTableStatus,
  nowIso,
  buildReceiptText,
};