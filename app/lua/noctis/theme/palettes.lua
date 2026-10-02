-- Tema varyantları yalnızca temel tokenları tanımlar. Seçim, arama, diff,
-- diagnostics arka planları gibi türetilmiş tonlar `theme/tokens.lua` içinde
-- aynı formülle üretilir; böylece üç tema tek bir tasarım sistemini paylaşır.
local M = {}

M.order = { "midnight-violet", "glacier", "amber" }

M.labels = {
  ["midnight-violet"] = "Midnight Violet",
  glacier = "Glacier",
  amber = "Amber",
}

M["midnight-violet"] = {
  bg = "#0B1020", -- editör zemini
  panel = "#11182A", -- gezgin, yan paneller
  float = "#182238", -- komut paleti, açılır pencereler
  border = "#2A3652",
  fg = "#DCE5F5",
  muted = "#8D9BB5",
  accent = "#A78BFA", -- ana vurgu (mor)
  accent2 = "#67E8F9", -- ikincil vurgu (camgöbeği)
  success = "#9AE6B4",
  warning = "#F6C177",
  error = "#F7768E",
  -- Söz dizimi: ölçülü, 6 ton + metin tonları
  syntax = {
    keyword = "#B69CFF",
    func = "#7DD8F0",
    string = "#A6DDB8",
    number = "#F2BE82",
    type = "#8FB3F5",
    special = "#F09ACB",
    comment = "#6C7A98",
    property = "#C5D0E6",
  },
}

M.glacier = {
  bg = "#0A141B",
  panel = "#0E1B25",
  float = "#142734",
  border = "#24394A",
  fg = "#D9E8F1",
  muted = "#89A2B4",
  accent = "#5CC6F0",
  accent2 = "#8FE3D2",
  success = "#90E0B0",
  warning = "#F2CC80",
  error = "#F3798E",
  syntax = {
    keyword = "#6FCBF2",
    func = "#9BE3D5",
    string = "#A9DDB9",
    number = "#F0C98C",
    type = "#A2B9F2",
    special = "#E4A1D2",
    comment = "#6C8294",
    property = "#C6D7E3",
  },
}

M.amber = {
  bg = "#14100B",
  panel = "#1A1510",
  float = "#251D15",
  border = "#3B2F21",
  fg = "#EDE3D3",
  muted = "#A99A84",
  accent = "#F2A65A",
  accent2 = "#E7C77E",
  success = "#AFD69E",
  warning = "#F5D267",
  error = "#F07C6C",
  syntax = {
    keyword = "#F2AC66",
    func = "#E9CC8A",
    string = "#B6D59F",
    number = "#E8A0A0",
    type = "#9EC2D9",
    special = "#D9A0D0",
    comment = "#8A7C68",
    property = "#DCCFBB",
  },
}

return M
