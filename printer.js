// src/printer.js
const { exec } = require("child_process");
const fs = require("fs");
const net = require("net");
const path = require("path");

// --- プリンタ割当（ここだけ触ればOK） ---
const PRINTER_MAP = {
  drink: "Brother DCP-J528N Printer",
  food: "Brother DCP-J528N Printer",
  register: "Brother DCP-J528N Printer",
  kitchen: "Brother DCP-J528N Printer",
  receipt: "Brother DCP-J528N Printer",
};

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

function printTextRawTcp(text, { host, port }) {
  return new Promise((resolve, reject) => {
    const socket = net.createConnection({ host, port }, () => {
      socket.write(text, "utf8", () => socket.end());
    });

    socket.setTimeout(5000);
    socket.on("timeout", () => socket.destroy(new Error("Raw TCP print timeout")));
    socket.on("error", reject);
    socket.on("close", (hadError) => {
      if (!hadError) resolve();
    });
  });
}

// --- 共通印刷関数（Windows / PowerShell） ---
function printTextWindows(text, target = "receipt") {
  return new Promise((resolve, reject) => {
    const transport = (process.env.PRINT_TRANSPORT || "rawtcp").toLowerCase();

    if (transport === "rawtcp") {
      const tcpConfig = resolveRawTcpConfig(target);
      if (!tcpConfig) {
        return reject(
          new Error(
            `PRINT_TRANSPORT=rawtcp but PRINTER_${String(target).toUpperCase()}_HOST or PRINTER_HOST is not set`
          )
        );
      }

      printTextRawTcp(text, tcpConfig)
        .then(resolve)
        .catch(reject);
      return;
    }

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
      if (err) {
        return reject(err);
      }
      resolve();
    });
  });
}

module.exports = {
  printTextWindows,
  printTextRawTcp,
  resolveRawTcpConfig,
  PRINTER_MAP,
};