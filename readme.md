provides some simple lint rules for fish scripts

## features
* based on vim.treesitter api
* populate diagnostics to vim.diagnostic
* try to spot these gotchas
    * `set $var var`
    * `test -n var`
    * `test var = var`

## non-goal
* a comprehensive linter for fish, these lint rules are just took from my daily use

## status
* far from usable

## prerequisites
* nvim 0.9.*
* infra.nvim

## usage
* `:lua require'saltedfish`.lint()`
