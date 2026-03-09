// src/printer.js
const { exec } = require("child_process");
const fs = require("fs");
const net = require("net");
const path = require("path");
const iconv = require("iconv-lite");

const PRINTER_MAP = {
  drink:    "Brother DCP-J528N Printer",
  food:     "Brother DCP-J528N Printer",
  register: "Brother DCP-J528N Printer",
  kitchen:  "Brother DCP-J528N Printer",
  receipt:  "Brother DCP-J528N Printer",
};

function normalizePrintableText(text) {
  return String(text ?? "")
    .replace(/[─━]/g, "-")
    .replace(/[（]/g, "(")
    .replace(/[）]/g, ")")
    .replace(/\u3000/g, "  ");
}

function toCP932(text) {
  return iconv.encode(normalizePrintableText(text), "cp932");
}

function resolveCodePageByte() {
  const raw = process.env.PRINTER_CODEPAGE;
  if (!raw) return 0x01;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 0 || value > 255) {
    throw new Error(`Invalid PRINTER_CODEPAGE: ${raw}`);
  }
  return value;
}

function shouldSendCodePageCommand() {
  const raw = (process.env.PRINTER_SEND_CODEPAGE || "false").toLowerCase();
  return raw !== "0" && raw !== "false";
}

const CMD = {
  init:        Buffer.from([0x1b, 0x40]),
  emphasisOn:  Buffer.from([0x1b, 0x45]),
  emphasisOff: Buffer.from([0x1b, 0x46]),
  feed:        Buffer.from([0x1b, 0x64, 0x03]),
  cut:         Buffer.from([0x1b, 0x0c]),
};

function buildLine(leftBuf, rightBuf, totalBytes) {
  const padBytes = totalBytes - leftBuf.length - rightBuf.length;
  const pad = Buffer.alloc(Math.max(0, padBytes), 0x20);
  return Buffer.concat([leftBuf, pad, rightBuf, Buffer.from([0x0a])]);
}

// ¥を0x5Cで送る（CP932/StarPRNT共通の円記号）
function formatAmountBuf(yenStr) {
  const num = yenStr.startsWith("¥") ? yenStr.slice(1) : yenStr;
  const padded = num.padStart(7);
  return Buffer.concat([
    Buffer.from([0x5C]),           // CP932/StarPRNT で ¥
    Buffer.from(padded, "ascii"),  // 数字はASCIIそのまま
  ]);
}

function centerLine(text, totalBytes) {
  const buf = toCP932(text);
  const pad = Math.max(0, Math.floor((totalBytes - buf.length) / 2));
  return Buffer.concat([
    Buffer.alloc(pad, 0x20),
    buf,
    Buffer.from([0x0a]),
  ]);
}

function buildRawPrintData(segments) {
  const chunks = [];
  chunks.push(CMD.init);

  if (shouldSendCodePageCommand()) {
    chunks.push(Buffer.from([0x1b, 0x74, resolveCodePageByte()]));
  }

  const ROW_BYTES    = 42;
  const MARGIN       = 1;
  const AMOUNT_BYTES = 8;
  const QTY_BYTES    = 3;
  const SEP          = 1;

  const ITEM_RIGHT  = QTY_BYTES + SEP + AMOUNT_BYTES + MARGIN; // 13
  const LABEL_RIGHT = AMOUNT_BYTES + MARGIN;                    // 9

  for (const seg of segments) {

    if (seg.type === "title") {
      chunks.push(centerLine(seg.text, ROW_BYTES));

    } else if (seg.type === "item") {
      const qtyStr = seg.qty.padStart(QTY_BYTES);
      const rightBuf = Buffer.concat([
        Buffer.from(qtyStr),
        Buffer.from(" "),
        formatAmountBuf(seg.price),
        Buffer.alloc(MARGIN, 0x20),
      ]);
      const nameBuf = toCP932(seg.name);
      chunks.push(buildLine(nameBuf, rightBuf, ROW_BYTES));

      for (const extra of seg.nameExtra || []) {
        chunks.push(Buffer.concat([toCP932(extra), Buffer.from([0x0a])]));
      }

    } else if (seg.type === "labelright") {
      const rightBuf = Buffer.concat([
        formatAmountBuf(seg.amount),
        Buffer.alloc(MARGIN, 0x20),
      ]);
      const labelBuf = toCP932(seg.label);
      chunks.push(buildLine(labelBuf, rightBuf, ROW_BYTES));

    } else if (seg.type === "total") {
      chunks.push(CMD.emphasisOn);
      const rightBuf = Buffer.concat([
        formatAmountBuf(seg.amount),
        Buffer.alloc(MARGIN, 0x20),
      ]);
      const labelBuf = toCP932("合計");
      chunks.push(buildLine(labelBuf, rightBuf, ROW_BYTES));
      chunks.push(CMD.emphasisOff);

    } else if (seg.type === "footer") {
      chunks.push(centerLine(seg.text, ROW_BYTES));

    } else {
      chunks.push(Buffer.concat([toCP932(seg.text)]));
    }
  }

  chunks.push(Buffer.from([0x0a, 0x0a, 0x0a]));
  chunks.push(CMD.feed);
  chunks.push(CMD.cut);

  return Buffer.concat(chunks);
}

function encodePrintableText(text) {
  return toCP932(text);
}

function normalizePrintableTextExport(text) {
  return normalizePrintableText(text);
}

function resolveRawTcpConfig(target) {
  const key = String(target || "receipt").toUpperCase();
  const host = process.env[`PRINTER_${key}_HOST`] || process.env.PRINTER_HOST;
  const portRaw = process.env[`PRINTER_${key}_PORT`] || process.env.PRINTER_PORT;
  const port = Number(portRaw || 9100);
  if (!host) return null;
  if (!Number.isFinite(port) || port <= 0) {
    throw new Error(`Invalid raw printer port for target=${target}: ${portRaw}`);
  }
  return { host, port };
}

function printTextRawTcp(segments, { host, port }) {
  return new Promise((resolve, reject) => {
    const socket = require("net").createConnection(port, host);
    socket.on("connect", () => {
      try {
        const data = buildRawPrintData(segments);
        socket.write(data, () => {
          setTimeout(() => { socket.end(); resolve(); }, 200);
        });
      } catch (err) {
        reject(err);
      }
    });
    socket.on("error", reject);
  });
}

function printTextWindows(segments, target = "receipt") {
  return new Promise((resolve, reject) => {
    const transport = (process.env.PRINT_TRANSPORT || "rawtcp").toLowerCase();
    if (transport === "rawtcp") {
      const tcpConfig = resolveRawTcpConfig(target);
      if (!tcpConfig) {
        return reject(new Error(
          `PRINT_TRANSPORT=rawtcp but PRINTER_${String(target).toUpperCase()}_HOST or PRINTER_HOST is not set`
        ));
      }
      printTextRawTcp(segments, tcpConfig).then(resolve).catch(reject);
      return;
    }
    const printerName = PRINTER_MAP[target];
    if (!printerName) return reject(new Error(`Unknown print target: ${target}`));
    const text = segments.map(s => s.text || s.name || s.label || "").join("\n");
    const filePath = path.join(__dirname, `print_${target}_${Date.now()}.txt`);
    fs.writeFileSync(filePath, text, "utf8");
    const cmd = `powershell -NoProfile -Command "Get-Content '${filePath}' -Encoding UTF8 | Out-Printer -Name '${printerName}'"`;
    exec(cmd, (err) => { if (err) return reject(err); resolve(); });
  });
}

module.exports = {
  printTextWindows,
  printTextRawTcp,
  resolveRawTcpConfig,
  PRINTER_MAP,
  buildRawPrintData,
  encodePrintableText,
  normalizePrintableText: normalizePrintableTextExport,
};