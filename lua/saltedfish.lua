local M = {}

local fn = require("infra.fn")
local jelly = require("infra.jellyfish")("saltedfish", "info")
local listlib = require("infra.listlib")
local prefer = require("infra.prefer")
local strlib = require("infra.strlib")

local ts = vim.treesitter
local api = vim.api

local ns = api.nvim_create_namespace("saltedfish")

---@param node TSNode
---@return string
local function get_node_text(bufnr, node) return ts.get_node_text(node, bufnr) end

---@param bufnr integer
---@param node TSNode
---@param msg string
---@return table
local function compose_dig(bufnr, node, msg)
  local start_lnum, start_col, stop_lnum, stop_col = node:range()

  return {
    bufnr = bufnr,
    lnum = start_lnum,
    end_lnum = stop_lnum,
    col = start_col,
    end_col = stop_col,
    severity = "WARN",
    message = msg,
    code = 1,
  }
end

local iter_nodes
do
  local patterns = [[
    ((command name: (word) @a (#eq? @a "test")) @b (#set! "kind" "test"))
    ((command name: (word) @a (#eq? @a "set")) @b (#set! "kind" "set"))
  ]]

  local query = ts.query.parse("fish", patterns)

  ---@param bufnr integer
  ---@param root TSNode
  ---@return fun(): 'test'|'set'|nil, TSNode|nil
  function iter_nodes(bufnr, root)
    local iter = assert(query:iter_matches(root, bufnr, 0, -1))

    return function()
      local pattern_id, match, metadata = iter()
      jelly.debug("pattern_id=%s, match=%s, metadata=%s", pattern_id, match, metadata)
      if not (pattern_id and match and metadata) then return end
      return metadata.kind, match[#match]
    end
  end
end

local rule_test_var_may_be_undefined
do
  ---@param bufnr integer
  ---@param set_node TSNode
  local function collect_args(bufnr, set_node)
    local args = {}

    local iter = fn.iter(set_node:field("argument"))

    for arg in iter do
      local text = get_node_text(bufnr, arg)
      if text == "--" then break end
      if not strlib.startswith(text, "-") then table.insert(args, arg) end
    end

    listlib.extend(args, iter)

    return args
  end

  ---@param bufnr integer
  ---@param arg_node TSNode
  ---@return table?
  local function lint_arg(bufnr, arg_node)
    local ntype = arg_node:type()
    if ntype == "integer" or ntype == "float" then return end

    local text = get_node_text(bufnr, arg_node)

    if text == "=" or text == "!=" or text == "!" then return end

    -- should be quoted or $-prefixed
    local c0 = string.sub(text, 1, 1)
    if c0 == "$" or c0 == "'" or c0 == '"' then return end

    return compose_dig(bufnr, arg_node, "string-arg of test should be quoted or $-prefixed")
  end

  ---@param bufnr integer
  ---@param test_node TSNode
  ---@return table[]
  function rule_test_var_may_be_undefined(bufnr, test_node)
    local digs = {}
    for _, arg in ipairs(collect_args(bufnr, test_node)) do
      local dig = lint_arg(bufnr, arg)
      if dig then table.insert(digs, dig) end
    end
    return digs
  end
end

local rule_set_var_with_dollar
do
  ---@param bufnr integer
  ---@param set_node TSNode
  ---@return TSNode?
  local function get_arg0(bufnr, set_node)
    local iter = fn.iter(set_node:field("argument"))

    for arg in iter do
      local text = get_node_text(bufnr, arg)
      if text == "--" then error("unreachable") end
      if not strlib.startswith(text, "-") then return arg end
    end

    return iter()
  end

  ---@param bufnr integer
  ---@param set_node TSNode
  ---@return table?
  local function lint(bufnr, set_node)
    local arg0 = get_arg0(bufnr, set_node)
    if arg0 == nil then return end

    -- should not be quoted nor $-prefixed
    local text = get_node_text(bufnr, arg0)

    local c0 = string.sub(text, 1, 1)
    if c0 == "$" then return compose_dig(bufnr, arg0, "arg0 of set should not be $-prefixed") end
    if c0 == "'" or c0 == '"' then return compose_dig(bufnr, arg0, "set's arg0 should not be quoted") end
  end

  ---@param bufnr integer
  ---@param set_node TSNode
  ---@return table[]
  function rule_set_var_with_dollar(bufnr, set_node) return { lint(bufnr, set_node) } end
end

function M.lint(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if prefer.bo(bufnr, "filetype") ~= "fish" then return jelly.warn("not a fish script") end

  local root
  do
    local parser = ts.get_parser(bufnr, "fish")
    local trees = parser:trees()
    assert(#trees == 1)
    local tree = trees[1]
    root = tree:root()
  end

  local digs = {}

  for kind, node in iter_nodes(bufnr, root) do
    if kind == "test" then
      listlib.extend(digs, rule_test_var_may_be_undefined(bufnr, node))
    elseif kind == "set" then
      listlib.extend(digs, rule_set_var_with_dollar(bufnr, node))
    else
      error("unreachable")
    end
  end

  jelly.debug("digs: %d", #digs)
  vim.diagnostic.set(ns, bufnr, digs)
end

function M.attach(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if prefer.bo(bufnr, "filetype") ~= "fish" then return jelly.warn("not a fish script") end

  error("not implemented")
end

return M
