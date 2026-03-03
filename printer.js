// src/printer.js
const { exec } = require("child_process");
const fs = require("fs");
const net = require("net");
const path = require("path");
const iconv = require("iconv-lite");

// --- Windows用（今回は未使用） ---
const PRINTER_MAP = {
  drink: "Brother DCP-J528N Printer",
  food: "Brother DCP-J528N Printer",
  register: "Brother DCP-J528N Printer",
  kitchen: "Brother DCP-J528N Printer",
  receipt: "Brother DCP-J528N Printer",
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

function buildRawPrintData(text) {
  // 初期化
  const init = Buffer.from([0x1b, 0x40]);

  const chunks = [init];

  // 文字コードテーブル指定（必要な機種のみ）
  if (shouldSendCodePageCommand()) {
    const codePageByte = resolveCodePageByte();
    chunks.push(Buffer.from([0x1b, 0x74, codePageByte]));
  }

  // 日本語エンコード（既定: cp932）
  chunks.push(encodePrintableText(text));

  // 余白 + 紙送り + カット
  chunks.push(Buffer.from("\n\n\n\n"));
  chunks.push(Buffer.from([0x1b, 0x64, 0x30])); // feed
  chunks.push(Buffer.from([0x1d, 0x56, 0x01])); // full cut

  return Buffer.concat(chunks);
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
    throw new Error(
      `Invalid raw printer port for target=${target}: ${portRaw}`
    );
  }

  return { host, port };
}

// --- Raw TCP印刷（mC-Print3安定版） ---
function printTextRawTcp(text, { host, port }) {
  return new Promise((resolve, reject) => {
    const socket = new net.Socket();

    socket.connect(port, host, () => {
      try {
        const data = buildRawPrintData(text);

        socket.write(data, () => {
          // 少し待ってから切断（安定）
          setTimeout(() => {
            socket.end();
            resolve();
          }, 200);
        });
      } catch (err) {
        reject(err);
      }
    });

    socket.on("error", reject);
  });
}

// --- 共通印刷関数 ---
function printTextWindows(text, target = "receipt") {
  return new Promise((resolve, reject) => {
    const transport = (process.env.PRINT_TRANSPORT || "rawtcp").toLowerCase();

    if (transport === "rawtcp") {
      const tcpConfig = resolveRawTcpConfig(target);

      if (!tcpConfig) {
        return reject(
          new Error(
            `PRINT_TRANSPORT=rawtcp but PRINTER_${String(
              target
            ).toUpperCase()}_HOST or PRINTER_HOST is not set`
          )
        );
      }

      printTextRawTcp(text, tcpConfig)
        .then(resolve)
        .catch(reject);

      return;
    }

    // Windowsドライバ印刷（未使用）
    const printerName = PRINTER_MAP[target];

    if (!printerName) {
      return reject(new Error(`Unknown print target: ${target}`));
    }

    const filePath = path.join(
      __dirname,
      `print_${target}_${Date.now()}.txt`
    );

    fs.writeFileSync(filePath, text, "utf8");

    const cmd =
      `powershell -NoProfile -Command "Get-Content '${filePath}' -Encoding UTF8 | Out-Printer -Name '${printerName}'"`;

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