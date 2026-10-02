-- Semantik tokenlardan highlight gruplarını üretir. Bileşenler renk değil,
-- yalnızca bu grupları kullanır; tema değişince her şey birlikte güncellenir.
local M = {}

---@param c table tokens.derive() çıktısı
---@param opts {transparent:boolean}
---@return table<string, vim.api.keyset.highlight>
function M.build(c, opts)
  local s = c.syntax
  local bg = opts.transparent and "NONE" or c.bg
  local panel = opts.transparent and "NONE" or c.panel
  local h = {}

  -- ── Editör yüzeyi ──────────────────────────────────────────────────────
  h.Normal = { fg = c.fg, bg = bg }
  h.NormalNC = { fg = c.fg, bg = bg }
  h.NormalFloat = { fg = c.fg, bg = c.float }
  h.FloatBorder = { fg = c.border, bg = c.float }
  h.FloatTitle = { fg = c.accent, bg = c.float, bold = true }
  h.FloatFooter = { fg = c.muted, bg = c.float }
  h.NoctisPanel = { fg = c.fg, bg = panel }
  h.NoctisPanelBorder = { fg = c.border, bg = panel }
  h.ColorColumn = { bg = c.cursorline }
  h.Conceal = { fg = c.fg_dim }
  h.Cursor = { fg = c.bg, bg = c.fg }
  h.lCursor = { link = "Cursor" }
  h.CursorIM = { link = "Cursor" }
  h.TermCursor = { fg = c.bg, bg = c.accent2 }
  h.CursorLine = { bg = c.cursorline }
  h.CursorColumn = { bg = c.cursorline }
  h.CursorLineNr = { fg = c.accent, bg = c.cursorline, bold = true }
  h.CursorLineSign = { bg = c.cursorline }
  h.CursorLineFold = { bg = c.cursorline }
  h.LineNr = { fg = c.fg_dim }
  h.LineNrAbove = { link = "LineNr" }
  h.LineNrBelow = { link = "LineNr" }
  h.SignColumn = { fg = c.fg_dim, bg = bg }
  h.FoldColumn = { fg = c.fg_dim, bg = bg }
  h.Folded = { fg = c.muted, bg = c.cursorline, italic = true }
  h.EndOfBuffer = { fg = c.bg }
  h.NonText = { fg = c.fg_dim }
  h.Whitespace = { fg = c.ws }
  h.SpecialKey = { fg = c.fg_dim }
  h.Directory = { fg = c.accent2 }
  h.Title = { fg = c.accent, bold = true }
  h.WinSeparator = { fg = c.border, bg = bg }
  h.VertSplit = { link = "WinSeparator" }
  h.WinBar = { fg = c.muted, bg = bg }
  h.WinBarNC = { fg = c.fg_dim, bg = bg }
  h.MatchParen = { fg = c.accent2, bg = c.match, bold = true }
  h.Visual = { bg = c.visual }
  h.VisualNOS = { bg = c.visual }
  h.Search = { fg = c.fg, bg = c.search }
  h.CurSearch = { fg = c.bg, bg = c.cursearch, bold = true }
  h.IncSearch = { link = "CurSearch" }
  h.Substitute = { fg = c.bg, bg = c.error }
  h.QuickFixLine = { bg = c.panel_cursor, bold = true }
  h.Question = { fg = c.accent2 }
  h.ModeMsg = { fg = c.fg, bold = true }
  h.MoreMsg = { fg = c.accent2 }
  h.MsgArea = { fg = c.fg }
  h.ErrorMsg = { fg = c.error, bold = true }
  h.WarningMsg = { fg = c.warning }
  h.OkMsg = { fg = c.success }
  h.WildMenu = { fg = c.bg, bg = c.accent }
  h.StatusLine = { fg = c.fg, bg = panel }
  h.StatusLineNC = { fg = c.muted, bg = panel }
  h.StatusLineTerm = { link = "StatusLine" }
  h.StatusLineTermNC = { link = "StatusLineNC" }
  h.TabLine = { fg = c.muted, bg = panel }
  h.TabLineFill = { bg = panel }
  h.TabLineSel = { fg = c.fg, bg = bg, bold = true }

  -- Açılır menüler (completion dahil)
  h.Pmenu = { fg = c.fg, bg = c.float }
  h.PmenuSel = { bg = c.accent_bg, bold = true }
  h.PmenuKind = { fg = c.accent2, bg = c.float }
  h.PmenuKindSel = { fg = c.accent2, bg = c.accent_bg }
  h.PmenuExtra = { fg = c.muted, bg = c.float }
  h.PmenuExtraSel = { fg = c.muted, bg = c.accent_bg }
  h.PmenuSbar = { bg = c.float }
  h.PmenuThumb = { bg = c.border }
  h.PmenuMatch = { fg = c.accent, bold = true }
  h.PmenuMatchSel = { fg = c.accent, bg = c.accent_bg, bold = true }
  h.PmenuBorder = { link = "FloatBorder" }
  h.ComplMatchIns = { fg = c.muted }
  h.SnippetTabstop = { bg = c.hint_bg }

  -- Diff: ekleme/silme/değişiklik anlamları sabittir.
  h.DiffAdd = { bg = c.diff_add }
  h.DiffDelete = { fg = c.diff_del_text, bg = c.diff_del }
  h.DiffChange = { bg = c.diff_change }
  h.DiffText = { bg = c.diff_text, bold = true }
  h.DiffTextAdd = { bg = c.diff_add_text }
  h.Added = { fg = c.success }
  h.Changed = { fg = c.syntax.type }
  h.Removed = { fg = c.error }
  h.diffAdded = { link = "Added" }
  h.diffRemoved = { link = "Removed" }
  h.diffChanged = { link = "Changed" }
  h.diffFile = { fg = c.accent, bold = true }
  h.diffLine = { fg = c.accent2 }
  h.diffIndexLine = { fg = c.muted }

  h.SpellBad = { sp = c.error, undercurl = true }
  h.SpellCap = { sp = c.warning, undercurl = true }
  h.SpellLocal = { sp = c.accent2, undercurl = true }
  h.SpellRare = { sp = c.accent, undercurl = true }

  -- ── Söz dizimi (Vim regex + Tree-sitter ortak) ────────────────────────
  h.Comment = { fg = s.comment, italic = true }
  h.Constant = { fg = s.number }
  h.String = { fg = s.string }
  h.Character = { fg = s.string }
  h.Number = { fg = s.number }
  h.Boolean = { fg = s.number }
  h.Float = { fg = s.number }
  h.Identifier = { fg = c.fg }
  h.Function = { fg = s.func }
  h.Statement = { fg = s.keyword }
  h.Conditional = { fg = s.keyword }
  h.Repeat = { fg = s.keyword }
  h.Label = { fg = s.keyword }
  h.Operator = { fg = c.muted }
  h.Keyword = { fg = s.keyword }
  h.Exception = { fg = s.keyword }
  h.PreProc = { fg = s.keyword }
  h.Include = { fg = s.keyword }
  h.Define = { fg = s.keyword }
  h.Macro = { fg = s.special }
  h.PreCondit = { fg = s.keyword }
  h.Type = { fg = s.type }
  h.StorageClass = { fg = s.keyword }
  h.Structure = { fg = s.type }
  h.Typedef = { fg = s.type }
  h.Special = { fg = s.special }
  h.SpecialChar = { fg = s.special }
  h.Tag = { fg = s.keyword }
  h.Delimiter = { fg = c.muted }
  h.SpecialComment = { fg = s.comment, bold = true }
  h.Debug = { fg = c.warning }
  h.Underlined = { underline = true }
  h.Ignore = { fg = c.fg_dim }
  h.Error = { fg = c.error }
  h.Todo = { fg = c.bg, bg = c.accent2, bold = true }

  h["@variable"] = { fg = c.fg }
  h["@variable.builtin"] = { fg = s.special }
  h["@variable.parameter"] = { fg = c.fg_subtle, italic = true }
  h["@variable.member"] = { fg = s.property }
  h["@property"] = { fg = s.property }
  h["@constant"] = { fg = s.number }
  h["@constant.builtin"] = { fg = s.number }
  h["@constant.macro"] = { fg = s.special }
  h["@module"] = { fg = s.type }
  h["@module.builtin"] = { fg = s.special }
  h["@label"] = { fg = s.keyword }
  h["@string"] = { link = "String" }
  h["@string.escape"] = { fg = s.special }
  h["@string.regexp"] = { fg = s.special }
  h["@string.special"] = { fg = s.special }
  h["@string.special.url"] = { fg = c.accent2, underline = true }
  h["@character"] = { link = "Character" }
  h["@number"] = { link = "Number" }
  h["@boolean"] = { link = "Boolean" }
  h["@type"] = { link = "Type" }
  h["@type.builtin"] = { fg = s.type, italic = true }
  h["@attribute"] = { fg = s.special }
  h["@function"] = { link = "Function" }
  h["@function.builtin"] = { fg = s.func, italic = true }
  h["@function.call"] = { fg = s.func }
  h["@function.method"] = { fg = s.func }
  h["@function.method.call"] = { fg = s.func }
  h["@constructor"] = { fg = s.type }
  h["@operator"] = { link = "Operator" }
  h["@keyword"] = { link = "Keyword" }
  h["@keyword.function"] = { fg = s.keyword }
  h["@keyword.return"] = { fg = s.keyword, italic = true }
  h["@keyword.import"] = { fg = s.keyword }
  h["@keyword.operator"] = { fg = s.keyword }
  h["@punctuation"] = { fg = c.muted }
  h["@punctuation.bracket"] = { fg = c.muted }
  h["@punctuation.delimiter"] = { fg = c.muted }
  h["@punctuation.special"] = { fg = s.special }
  h["@comment"] = { link = "Comment" }
  h["@comment.todo"] = { fg = c.bg, bg = c.accent2, bold = true }
  h["@comment.note"] = { fg = c.bg, bg = c.info, bold = true }
  h["@comment.warning"] = { fg = c.bg, bg = c.warning, bold = true }
  h["@comment.error"] = { fg = c.bg, bg = c.error, bold = true }
  h["@tag"] = { fg = s.keyword }
  h["@tag.builtin"] = { fg = s.keyword }
  h["@tag.attribute"] = { fg = s.property, italic = true }
  h["@tag.delimiter"] = { fg = c.muted }
  h["@markup.heading"] = { fg = c.accent, bold = true }
  h["@markup.strong"] = { bold = true }
  h["@markup.italic"] = { italic = true }
  h["@markup.strikethrough"] = { strikethrough = true }
  h["@markup.link"] = { fg = c.accent2 }
  h["@markup.link.url"] = { fg = c.accent2, underline = true }
  h["@markup.raw"] = { fg = s.string }
  h["@markup.list"] = { fg = s.keyword }
  h["@markup.quote"] = { fg = c.muted, italic = true }
  h["@diff.plus"] = { link = "Added" }
  h["@diff.minus"] = { link = "Removed" }
  h["@diff.delta"] = { link = "Changed" }
  h["@lsp.type.comment"] = {}
  h["@lsp.mod.deprecated"] = { strikethrough = true }

  -- ── Diagnostics: renk + simge/etiket birlikte ──────────────────────────
  h.DiagnosticError = { fg = c.error }
  h.DiagnosticWarn = { fg = c.warning }
  h.DiagnosticInfo = { fg = c.info }
  h.DiagnosticHint = { fg = c.hint }
  h.DiagnosticOk = { fg = c.success }
  h.DiagnosticVirtualTextError = { fg = c.error, bg = c.err_bg }
  h.DiagnosticVirtualTextWarn = { fg = c.warning, bg = c.warn_bg }
  h.DiagnosticVirtualTextInfo = { fg = c.info, bg = c.info_bg }
  h.DiagnosticVirtualTextHint = { fg = c.hint, bg = c.hint_bg }
  h.DiagnosticUnderlineError = { sp = c.error, undercurl = true }
  h.DiagnosticUnderlineWarn = { sp = c.warning, undercurl = true }
  h.DiagnosticUnderlineInfo = { sp = c.info, undercurl = true }
  h.DiagnosticUnderlineHint = { sp = c.hint, undercurl = true }
  h.DiagnosticUnnecessary = { fg = c.fg_dim }
  h.DiagnosticDeprecated = { strikethrough = true }
  h.LspReferenceText = { bg = c.match }
  h.LspReferenceRead = { bg = c.match }
  h.LspReferenceWrite = { bg = c.match, underline = true }
  h.LspSignatureActiveParameter = { fg = c.accent, bold = true, underline = true }
  h.LspInlayHint = { fg = c.fg_dim, bg = c.cursorline, italic = true }
  h.LspCodeLens = { fg = c.fg_dim }

  -- ── Eklentiler ─────────────────────────────────────────────────────────
  h.GitSignsAdd = { fg = c.success }
  h.GitSignsChange = { fg = s.type }
  h.GitSignsDelete = { fg = c.error }
  h.GitSignsAddPreview = { link = "DiffAdd" }
  h.GitSignsDeletePreview = { link = "DiffDelete" }
  h.GitSignsCurrentLineBlame = { fg = c.fg_dim, italic = true }

  h.SnacksPicker = { link = "NormalFloat" }
  h.SnacksPickerBorder = { link = "FloatBorder" }
  h.SnacksPickerTitle = { fg = c.bg, bg = c.accent, bold = true }
  h.SnacksPickerPreviewTitle = { fg = c.bg, bg = c.accent2, bold = true }
  h.SnacksPickerInputBorder = { fg = c.accent_soft, bg = c.float }
  h.SnacksPickerPrompt = { fg = c.accent, bg = c.float }
  h.SnacksPickerMatch = { fg = c.accent, bold = true }
  h.SnacksPickerListCursorLine = { bg = c.accent_bg }
  h.SnacksPickerCursorLine = { bg = c.accent_bg }
  h.SnacksPickerDir = { fg = c.muted }
  h.SnacksPickerFile = { fg = c.fg }
  h.SnacksPickerTree = { fg = c.border }
  h.SnacksPickerDimmed = { fg = c.fg_dim }
  h.SnacksPickerTotals = { fg = c.muted }
  h.SnacksPickerToggle = { fg = c.bg, bg = c.accent2 }
  h.SnacksPickerSelected = { fg = c.accent }
  h.SnacksPickerGitStatusAdded = { fg = c.success }
  h.SnacksPickerGitStatusModified = { fg = s.type }
  h.SnacksPickerGitStatusDeleted = { fg = c.error }
  h.SnacksPickerGitStatusUntracked = { fg = c.accent2 }
  h.SnacksPickerGitStatusIgnored = { fg = c.fg_dim }
  h.SnacksPickerPathHidden = { fg = c.fg_dim }
  h.SnacksPickerPathIgnored = { fg = c.fg_dim, italic = true }
  -- Gezgin yan paneli: panel zemini
  h.NoctisExplorer = { fg = c.fg, bg = panel }
  h.NoctisExplorerBorder = { fg = c.border, bg = panel }
  h.NoctisExplorerTitle = { fg = c.accent, bg = panel, bold = true }
  h.SnacksNotifierInfo = { fg = c.fg, bg = c.float }
  h.SnacksNotifierBorderInfo = { fg = c.accent2, bg = c.float }
  h.SnacksNotifierTitleInfo = { fg = c.accent2, bg = c.float, bold = true }
  h.SnacksNotifierIconInfo = { fg = c.accent2 }
  h.SnacksNotifierWarn = { fg = c.fg, bg = c.float }
  h.SnacksNotifierBorderWarn = { fg = c.warning, bg = c.float }
  h.SnacksNotifierTitleWarn = { fg = c.warning, bg = c.float, bold = true }
  h.SnacksNotifierIconWarn = { fg = c.warning }
  h.SnacksNotifierError = { fg = c.fg, bg = c.float }
  h.SnacksNotifierBorderError = { fg = c.error, bg = c.float }
  h.SnacksNotifierTitleError = { fg = c.error, bg = c.float, bold = true }
  h.SnacksNotifierIconError = { fg = c.error }
  h.SnacksInputNormal = { link = "NormalFloat" }
  h.SnacksInputBorder = { fg = c.accent_soft, bg = c.float }
  h.SnacksInputTitle = { fg = c.accent, bg = c.float, bold = true }
  h.SnacksInputIcon = { fg = c.accent }
  h.SnacksIndent = { fg = c.indent }
  h.SnacksIndentScope = { fg = c.border }

  h.WhichKey = { fg = c.accent2 }
  h.WhichKeyGroup = { fg = c.accent }
  h.WhichKeyDesc = { fg = c.fg }
  h.WhichKeySeparator = { fg = c.fg_dim }
  h.WhichKeyNormal = { link = "NormalFloat" }
  h.WhichKeyBorder = { link = "FloatBorder" }
  h.WhichKeyTitle = { link = "FloatTitle" }
  h.WhichKeyValue = { fg = c.muted }

  h.BlinkCmpMenu = { link = "Pmenu" }
  h.BlinkCmpMenuBorder = { link = "FloatBorder" }
  h.BlinkCmpMenuSelection = { link = "PmenuSel" }
  h.BlinkCmpLabel = { fg = c.fg }
  h.BlinkCmpLabelMatch = { fg = c.accent, bold = true }
  h.BlinkCmpLabelDetail = { fg = c.muted }
  h.BlinkCmpLabelDescription = { fg = c.muted }
  h.BlinkCmpLabelDeprecated = { fg = c.fg_dim, strikethrough = true }
  h.BlinkCmpKind = { fg = c.accent2 }
  h.BlinkCmpSource = { fg = c.fg_dim, italic = true }
  h.BlinkCmpGhostText = { fg = c.fg_dim, italic = true }
  h.BlinkCmpDoc = { link = "NormalFloat" }
  h.BlinkCmpDocBorder = { link = "FloatBorder" }
  h.BlinkCmpDocSeparator = { fg = c.border, bg = c.float }
  h.BlinkCmpSignatureHelp = { link = "NormalFloat" }
  h.BlinkCmpSignatureHelpBorder = { link = "FloatBorder" }
  h.BlinkCmpSignatureHelpActiveParameter = { link = "LspSignatureActiveParameter" }
  h.BlinkCmpScrollBarThumb = { bg = c.border }
  h.BlinkCmpScrollBarGutter = { bg = c.float }

  h.LazyNormal = { link = "NormalFloat" }
  h.LazyH1 = { fg = c.bg, bg = c.accent, bold = true }
  h.LazyButton = { fg = c.fg, bg = c.cursorline }
  h.LazyButtonActive = { fg = c.bg, bg = c.accent, bold = true }
  h.LazySpecial = { fg = c.accent2 }
  h.LazyProgressDone = { fg = c.accent }
  h.LazyProgressTodo = { fg = c.border }
  h.MasonNormal = { link = "NormalFloat" }
  h.MasonHeader = { fg = c.bg, bg = c.accent, bold = true }
  h.MasonHighlight = { fg = c.accent2 }
  h.MasonHighlightBlock = { fg = c.bg, bg = c.accent2 }
  h.MasonHighlightBlockBold = { fg = c.bg, bg = c.accent, bold = true }
  h.MasonMuted = { fg = c.muted }
  h.MasonMutedBlock = { fg = c.muted, bg = c.cursorline }

  -- ── NOCTIS bileşenleri ─────────────────────────────────────────────────
  h.NoctisAccent = { fg = c.accent }
  h.NoctisAccent2 = { fg = c.accent2 }
  h.NoctisMuted = { fg = c.muted }
  h.NoctisDim = { fg = c.fg_dim }
  h.NoctisSuccess = { fg = c.success }
  h.NoctisWarning = { fg = c.warning }
  h.NoctisError = { fg = c.error }
  h.NoctisBold = { fg = c.fg, bold = true }
  h.NoctisFlash = { bg = c.flash }
  -- Yazma animasyonu: vurgu renginden satır zeminine sönen basamaklar
  for i, col in ipairs(c.type_glow) do
    h["NoctisType" .. i] = { bg = col }
  end

  -- Dashboard
  h.NoctisDashTitle = { fg = c.accent, bold = true }
  h.NoctisDashSubtitle = { fg = c.muted }
  h.NoctisDashSection = { fg = c.accent2, bold = true }
  h.NoctisDashKey = { fg = c.accent, bold = true }
  h.NoctisDashDesc = { fg = c.fg }
  h.NoctisDashPath = { fg = c.muted }
  h.NoctisDashEmpty = { fg = c.fg_dim, italic = true }
  h.NoctisDashSel = { bg = c.accent_bg }

  -- Statusline
  local stbg = panel
  h.NoctisStNormal = { fg = c.bg, bg = c.accent, bold = true }
  h.NoctisStInsert = { fg = c.bg, bg = c.success, bold = true }
  h.NoctisStVisual = { fg = c.bg, bg = c.accent2, bold = true }
  h.NoctisStReplace = { fg = c.bg, bg = c.error, bold = true }
  h.NoctisStCommand = { fg = c.bg, bg = c.warning, bold = true }
  h.NoctisStTerminal = { fg = c.bg, bg = c.accent2, bold = true }
  h.NoctisStText = { fg = c.fg, bg = stbg }
  h.NoctisStMuted = { fg = c.muted, bg = stbg }
  h.NoctisStDim = { fg = c.fg_dim, bg = stbg }
  h.NoctisStFile = { fg = c.fg, bg = stbg, bold = true }
  h.NoctisStModified = { fg = c.warning, bg = stbg, bold = true }
  h.NoctisStBranch = { fg = c.accent, bg = stbg }
  h.NoctisStAdded = { fg = c.success, bg = stbg }
  h.NoctisStChanged = { fg = s.type, bg = stbg }
  h.NoctisStRemoved = { fg = c.error, bg = stbg }
  h.NoctisStError = { fg = c.error, bg = stbg, bold = true }
  h.NoctisStWarn = { fg = c.warning, bg = stbg, bold = true }
  h.NoctisStInfo = { fg = c.info, bg = stbg }
  h.NoctisStHint = { fg = c.hint, bg = stbg }
  h.NoctisStAI = { fg = c.accent2, bg = stbg, bold = true }
  h.NoctisStConflict = { fg = c.bg, bg = c.error, bold = true }
  h.NoctisStBadge = { fg = c.bg, bg = c.warning, bold = true }
  h.NoctisStSep = { fg = c.border, bg = stbg }

  -- Tabline (buffer listesi)
  h.NoctisTabActive = { fg = c.fg, bg = bg, bold = true }
  h.NoctisTabActiveMark = { fg = c.accent, bg = bg, bold = true }
  h.NoctisTabInactive = { fg = c.muted, bg = panel }
  h.NoctisTabModified = { fg = c.warning, bg = panel, bold = true }
  h.NoctisTabModifiedActive = { fg = c.warning, bg = bg, bold = true }
  h.NoctisTabFill = { bg = panel }
  h.NoctisTabRight = { fg = c.muted, bg = panel }
  h.NoctisTabPage = { fg = c.bg, bg = c.accent2, bold = true }

  -- Komut paleti
  h.NoctisPaletteKey = { fg = c.accent, bold = true }
  h.NoctisPaletteGroup = { fg = c.accent2 }
  h.NoctisPaletteDesc = { fg = c.muted }
  h.NoctisPaletteUnavailable = { fg = c.fg_dim, italic = true }

  -- AI Workbench ve değişiklik inceleme
  h.NoctisAIHeader = { fg = c.fg, bg = c.panel, bold = true }
  h.NoctisAITabActive = { fg = c.bg, bg = c.accent, bold = true }
  h.NoctisAITabInactive = { fg = c.muted, bg = c.cursorline }
  h.NoctisAIStatusRun = { fg = c.success }
  h.NoctisAIStatusStart = { fg = c.warning }
  h.NoctisAIStatusExit = { fg = c.muted }
  h.NoctisAIStatusFail = { fg = c.error, bold = true }
  h.NoctisAIPath = { fg = c.muted }
  h.NoctisChangeAdded = { fg = c.success, bold = true }
  h.NoctisChangeModified = { fg = s.type, bold = true }
  h.NoctisChangeDeleted = { fg = c.error, bold = true }
  h.NoctisChangeConflict = { fg = c.bg, bg = c.error, bold = true }
  h.NoctisChangeReviewed = { fg = c.success }
  h.NoctisChangeOutOfScope = { fg = c.fg_dim, italic = true }
  h.NoctisDiffHunk = { fg = c.accent2, bg = c.cursorline, bold = true }
  h.NoctisDiffAdd = { fg = c.fg, bg = c.diff_add }
  h.NoctisDiffDel = { fg = c.fg, bg = c.diff_del }
  h.NoctisDiffAddSign = { fg = c.success, bg = c.diff_add, bold = true }
  h.NoctisDiffDelSign = { fg = c.error, bg = c.diff_del, bold = true }
  h.NoctisDiffContext = { fg = c.muted }
  h.NoctisDiffFile = { fg = c.accent, bold = true }

  return h
end

--- Entegre terminal için 16 renkli ANSI paleti
function M.terminal_colors(c)
  local s = c.syntax
  return {
    c.panel, c.error, c.success, c.warning, s.type, c.accent, c.accent2, c.fg_subtle,
    c.fg_dim, c.error, c.success, c.warning, s.type, c.accent, c.accent2, c.fg,
  }
end

return M
