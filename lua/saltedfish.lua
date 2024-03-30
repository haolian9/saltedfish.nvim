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

---@param root TSNode
---@return TSNode[]
local function collect_cmd_nodes(root)
  local cmds = {}
  local queue = { root }
  while #queue > 0 do
    ---@type TSNode
    local node = listlib.pop(queue)
    if node:type() == "command" then
      table.insert(cmds, node)
    else
      for i = 0, node:named_child_count() do
        table.insert(queue, node:named_child(i))
      end
    end
  end
  return cmds
end

local rule_test_var_may_be_undefined
do
  ---@param bufnr integer
  ---@param cmd_nodes TSNode[]
  ---@return TSNode[]
  local function collect_test_nodes(bufnr, cmd_nodes)
    local tests = {}
    for _, cmd in ipairs(cmd_nodes) do
      local names = cmd:field("name")
      assert(#names == 1)
      if get_node_text(bufnr, names[1]) == "test" then table.insert(tests, cmd) end
    end
    return tests
  end

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

    return compose_dig(bufnr, arg_node, "test's string args should be quoted or $-prefixed")
  end

  ---@param bufnr integer
  ---@param cmd_nodes TSNode[]
  ---@return table[]
  function rule_test_var_may_be_undefined(bufnr, cmd_nodes)
    local digs = {}
    for _, test in ipairs(collect_test_nodes(bufnr, cmd_nodes)) do
      for _, arg in ipairs(collect_args(bufnr, test)) do
        local dig = lint_arg(bufnr, arg)
        if dig then table.insert(digs, dig) end
      end
    end
    return digs
  end
end

local rule_set_var_with_dollar
do
  ---@param bufnr integer
  ---@param cmd_nodes TSNode[]
  ---@return TSNode[]
  local function get_set_nodes(bufnr, cmd_nodes)
    local sets = {}
    for _, cmd in ipairs(cmd_nodes) do
      local names = cmd:field("name")
      assert(#names == 1)
      if get_node_text(bufnr, names[1]) == "set" then table.insert(sets, cmd) end
    end
    return sets
  end

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
    if c0 == "$" then return compose_dig(bufnr, arg0, "set's arg0 should not be $-prefixed") end
    if c0 == "'" or c0 == '"' then return compose_dig(bufnr, arg0, "set's arg0 should not be quoted") end
  end

  ---@param bufnr integer
  ---@param cmd_nodes TSNode[]
  ---@return table[]
  function rule_set_var_with_dollar(bufnr, cmd_nodes)
    local digs = {}
    for _, node in ipairs(get_set_nodes(bufnr, cmd_nodes)) do
      local dig = lint(bufnr, node)
      if dig then table.insert(digs, dig) end
    end
    return digs
  end
end

function M.lint(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if prefer.bo(bufnr, "filetype") ~= "fish" then return jelly.warn("not a fish script") end

  local cmd_nodes
  do
    local trees = ts.get_parser(bufnr, "fish"):trees()
    local root = assert(trees[1]):root()
    cmd_nodes = collect_cmd_nodes(root)
  end

  local digs = {}
  listlib.extend(digs, rule_test_var_may_be_undefined(bufnr, cmd_nodes))
  listlib.extend(digs, rule_set_var_with_dollar(bufnr, cmd_nodes))

  jelly.debug("digs: %d", #digs)
  vim.diagnostic.set(ns, bufnr, digs)
end

function M.attach(bufnr)
  bufnr = bufnr or api.nvim_get_current_buf()

  if prefer.bo(bufnr, "filetype") ~= "fish" then return jelly.warn("not a fish script") end

  error("not implemented")
end

return M
