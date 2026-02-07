// src/printer.js
const { exec } = require("child_process");
const fs = require("fs");
const path = require("path");

// --- プリンタ割当（ここだけ触ればOK） ---
const PRINTER_MAP = {
  drink: "Brother DCP-J528N Printer",
  food: "Brother DCP-J528N Printer",
  receipt: "Brother DCP-J528N Printer",
};

// --- 共通印刷関数（Windows / PowerShell） ---
function printTextWindows(text, target = "receipt") {
  return new Promise((resolve, reject) => {
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
  PRINTER_MAP,
};
