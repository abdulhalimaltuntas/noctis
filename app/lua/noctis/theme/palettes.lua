-- Theme variants only define the base tokens. Derived tones such as the
-- selection, search, diff and diagnostics backgrounds are produced in
-- `theme/tokens.lua` with the same formulas, so every theme shares one design system.
-- `background` tells Neovim (and plugins) whether the variant is dark or light.
-- Text tokens must stay readable on bg, panel and float: `theme.audit()` checks
-- WCAG contrast for every variant and the test suite fails if one regresses.
local M = {}

M.order = { "midnight-violet", "glacier", "amber", "daybreak" }

M.labels = {
  ["midnight-violet"] = "Midnight Violet",
  glacier = "Glacier",
  amber = "Amber",
  daybreak = "Daybreak",
}

M["midnight-violet"] = {
  background = "dark",
  bg = "#0B1020", -- editor background
  panel = "#11182A", -- explorer, side panels
  float = "#182238", -- command palette, popups
  border = "#2A3652",
  fg = "#DCE5F5",
  muted = "#919FB9",
  accent = "#A78BFA", -- primary accent (violet)
  accent2 = "#67E8F9", -- secondary accent (cyan)
  success = "#9AE6B4",
  warning = "#F6C177",
  error = "#F7768E",
  -- Syntax: restrained, 6 hues + text tones
  syntax = {
    keyword = "#B69CFF",
    func = "#7DD8F0",
    string = "#A6DDB8",
    number = "#F2BE82",
    type = "#8FB3F5",
    special = "#F09ACB",
    comment = "#7E8CAA",
    property = "#C5D0E6",
  },
}

M.glacier = {
  background = "dark",
  bg = "#0A141B",
  panel = "#0E1B25",
  float = "#142734",
  border = "#24394A",
  fg = "#D9E8F1",
  muted = "#8FA8BA",
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
    comment = "#7E94A6",
    property = "#C6D7E3",
  },
}

M.amber = {
  background = "dark",
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
    comment = "#9E8F78",
    property = "#DCCFBB",
  },
}

-- Light counterpart of Midnight Violet: same accents, deepened until they pass
-- AA on a light ground. Panels sit slightly darker than the editor and
-- popups slightly lighter, so elevation reads the same way as in the dark themes.
M.daybreak = {
  background = "light",
  tint = 0.7, -- tints read stronger on a light ground
  dim = 0.78, -- dim text needs more weight to stay at 3:1
  bg = "#F7F8FC",
  panel = "#ECEEF5",
  float = "#FFFFFF",
  border = "#CDD3E2",
  fg = "#1E2433",
  muted = "#535C74",
  accent = "#6A42D6",
  accent2 = "#09678A",
  success = "#1C774A",
  warning = "#965600",
  error = "#C22E48",
  syntax = {
    keyword = "#6B3DD0",
    func = "#0A6A8F",
    string = "#28763B",
    number = "#9C5309",
    type = "#3354B0",
    special = "#A93274",
    comment = "#5F6980",
    property = "#38425A",
  },
}

return M
