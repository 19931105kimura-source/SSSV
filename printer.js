// src/printer.js
const { exec } = require("child_process");
const fs = require("fs");
const net = require("net");
const path = require("path");
const iconv = require("iconv-lite");

// --- Windows用（今回は未使用） ---
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
    .replace(/[）]/g, ")");
}

function encodePrintableText(text) {
  const normalized = normalizePrintableText(text);
  const encoding = (process.env.PRINTER_ENCODING || "cp932").toLowerCase();
  if (encoding === "utf8" || encoding === "utf-8") {
    return Buffer.from(normalized, "utf8");
  }
  return iconv.encode(normalized, encoding);
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
  const raw = (process.env.PRINTER_SEND_CODEPAGE || "true").toLowerCase();
  return raw !== "0" && raw !== "false";
}

// ESC/POS コマンド定数（バイト列）
const CMD = {
  init:        Buffer.from([0x1b, 0x40]),
  alignLeft:   Buffer.from([0x1b, 0x61, 0x00]),
  alignCenter: Buffer.from([0x1b, 0x61, 0x01]),
  alignRight:  Buffer.from([0x1b, 0x61, 0x02]),
  emphasisOn:  Buffer.from([0x1b, 0x45, 0x01]),
  emphasisOff: Buffer.from([0x1b, 0x45, 0x00]),
  dblSizeOn:   Buffer.from([0x1d, 0x21, 0x11]),  // 縦横2倍
  normalSize:  Buffer.from([0x1d, 0x21, 0x00]),  // 通常サイズ
};

/**
 * domain.js の buildReceiptText が返すセグメント配列を
 * ESC/POS Buffer に変換する。
 * テキストは encodePrintableText (cp932) を通すだけ。
 * コマンドは Buffer 定数を直接 push するため文字化けしない。
 */
function buildRawPrintData(segments) {
  const chunks = [];

  chunks.push(CMD.init);

  if (shouldSendCodePageCommand()) {
    chunks.push(Buffer.from([0x1b, 0x74, resolveCodePageByte()]));
  }

  for (const seg of segments) {
    if (seg.type === "title") {
      // 中央寄せのみ
      chunks.push(CMD.alignCenter);
      chunks.push(encodePrintableText(seg.text + "\n"));
      chunks.push(CMD.alignLeft);

    } else if (seg.type === "total") {
      // 強調・1行に「合計」ラベルと金額を並べる
      chunks.push(CMD.emphasisOn);
      const line = padEnd(seg.label, seg.labelWidth) +
                   padStart(seg.amount, seg.priceWidth) + "\n";
      chunks.push(encodePrintableText(line));
      chunks.push(CMD.emphasisOff);

    } else if (seg.type === "footer") {
      // 中央寄せ
      chunks.push(CMD.alignCenter);
      chunks.push(encodePrintableText(seg.text + "\n"));
      chunks.push(CMD.alignLeft);

    } else {
      // 通常テキスト
      chunks.push(encodePrintableText(seg.text));
    }
  }

  // 余白 + 紙送り + カット
  chunks.push(encodePrintableText("\n\n\n\n"));
  chunks.push(Buffer.from([0x1b, 0x64, 0x30]));
  chunks.push(Buffer.from([0x1d, 0x56, 0x01]));

  return Buffer.concat(chunks);
}

// padEnd / padStart （printer.js 内で total 行組立に必要）
function isWideChar(c) {
  const code = c.charCodeAt(0);
  return (code >= 0x3000 && code <= 0x9fff) || (code >= 0xff00 && code <= 0xffef);
}
function displayWidth(str) {
  let w = 0;
  for (const c of String(str ?? "")) w += isWideChar(c) ? 2 : 1;
  return w;
}
function padEnd(text, width) {
  text = String(text ?? "");
  const w = displayWidth(text);
  return w >= width ? text : text + " ".repeat(width - w);
}
function padStart(text, width) {
  text = String(text ?? "");
  const w = displayWidth(text);
  return w >= width ? text : " ".repeat(width - w) + text;
}

// --- Raw TCP設定 ---
function resolveRawTcpConfig(target) {
  const key = String(target || "receipt").toUpperCase();
  const host =
    process.env[`PRINTER_${key}_HOST`] || process.env.PRINTER_HOST;
  const portRaw =
    process.env[`PRINTER_${key}_PORT`] || process.env.PRINTER_PORT;
  const port = Number(portRaw || 9100);
  if (!host) return null;
  if (!Number.isFinite(port) || port <= 0) {
    throw new Error(`Invalid raw printer port for target=${target}: ${portRaw}`);
  }
  return { host, port };
}

// --- Raw TCP印刷 ---
function printTextRawTcp(segments, { host, port }) {
  return new Promise((resolve, reject) => {
    const socket = new net.Socket();
    socket.connect(port, host, () => {
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

// --- 共通印刷関数 ---
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

    // Windowsドライバ印刷（未使用）
    const printerName = PRINTER_MAP[target];
    if (!printerName) {
      return reject(new Error(`Unknown print target: ${target}`));
    }
    const text = segments.map(s => s.text || "").join("");
    const filePath = path.join(__dirname, `print_${target}_${Date.now()}.txt`);
    fs.writeFileSync(filePath, text, "utf8");
    const cmd = `powershell -NoProfile -Command "Get-Content '${filePath}' -Encoding UTF8 | Out-Printer -Name '${printerName}'"`;
    exec(cmd, (err) => {
      if (err) return reject(err);
      resolve();
    });
  });
}

module.exports = {
  printTextWindows,
  printTextRawTcp,
  resolveRawTcpConfig,
  PRINTER_MAP,
  buildRawPrintData,
  encodePrintableText,
  normalizePrintableText,
};