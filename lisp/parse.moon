
module "lisp.parse", package.seeall

require "lpeg"
require "moonscript.transform"
require "moonscript.compile"

import run_with_scope, p from require "moon"
import P, V, S, R, C, Cc, Ct from lpeg

import insert, concat from table

import LocalName from moonscript.transform
import RootBlock from moonscript.compile

Set = (items) -> { name, true for name in *items}

White = S" \t\r\n"^0
Comment =  ";" * (1 - S"\r\n")^0 * S"\r\n"
White = White * (Comment * White)^0

sym = (s) -> White * s

mark = (name) -> (...) -> { name, ... }

auto_variable = (fn) ->
  run_with_scope fn, setmetatable {}, {
    __index: (name) =>
      V name if name\match "^[A-Z]"
  }

parser = auto_variable ->
  P {
    Code

    Code: Ct(Value^0) * White * -1

    Number: White * C R"09"^1
    Atom: White * C (R("az", "AZ", "09") + S"-_*/+=<>%")^1
    String: White * C(sym'"') * C((P"\\\\" + '\\"' + (1 - S'"\r\n'))^0) * '"'
    Quote: sym"'" * Value

    SExp: White * sym"(" * Ct(Value^0) * sym")"

    Value: Number / mark"number" + String / mark"string" + SExp / mark"list" + Quote/ mark"quote" + Atom / mark"atom"
  }

CALLABLE = Set{"parens", "chain"}

atom = (exp) ->
  assert exp[1] == "atom"
  exp[2]

bigrams = (list) ->
  return {list} if #list == 1
  return for i = 1, #list - 1
    {list[i], list[i+1]}

to_func = (inner) ->
  {"chain", {"parens", {
    "fndef", {}, {}, "slim"
    inner
  }}, {"call", {}}}

assign = (name, value)->
  to_func {
    {"assign", {name}, {value}}
    name
  }

make_list = (exps) ->
  list = "nil"
  for i = #exps, 1, -1
    list = {"table", {{exps[i]}, {list}}}
  list

compile = nil
quote = (exp) ->
  switch exp[1]
    when "atom"
      str = ("%q")\format(exp)\sub 2, -2
      compile {"string", '"', str}
    when "list"
      make_list [quote(val) for val in *exp[2]]
    when "quote"
      error "don't know how to quote a quote"
    else
      exp

limit_args = (n, fn) ->
  (exp) ->
    if #exp > n + 1
      error "expecting ".. n .." arg(s) for `".. atom(exp[1]) .. "'"

    fn exp

operator_form = (exp) ->
  op = atom(exp[1])
  out = {"exp"}
  for i = 2, #exp
    insert out, compile exp[i]
    insert out, op if i != #exp
  {"parens", out}

index_on = (n) ->
  (exp) ->
    val = compile(exp[2])

    t = type val
    if t == "table" and not CALLABLE[val[1]] or t != "string"
      val = {"parens", val}

    {"chain", val, {"index", {"number", n}}}

-- system level macros
forms = {
  quote: (exp) ->
    error "too many parameters to quote" if #exp > 2
    quote exp[2]

  cons: (exp) ->
    {"table", [{compile(val)} for val in *exp[2,]]}

  car: index_on 1
  cdr: index_on 2

  setf: (exp) ->
    _, name, value = unpack exp
    assign atom(name), compile value

  defun: (exp) ->
    _, name, args, body = unpack exp
    body = [compile(e) for e in *exp[4,]]

    assign atom(name), {
      "fndef", [{atom name} for name in *args[2]]
      {}, "slim", body
    }

  -- make this generic for all other binary operators with more than two args
  eq: (exp) ->
    eqs = bigrams [e for e in *exp[2,]]
    out = {"exp"}
    if #eqs > 1
      for i = 1, #eqs
        p = eqs[i]
        insert out, {"exp", p[1], "==", p[2]}
        insert out, "and" if i != #eqs
      out
    else
      {"exp", exp[2], "==", exp[3]}

  not: (exp) ->
    {"not", compile exp[2]}

  ["+"]: operator_form
  ["-"]: operator_form
  ["*"]: operator_form
  ["/"]: operator_form

  ["<"]: limit_args 2, operator_form
  ["<="]: limit_args 2, operator_form
  [">"]: limit_args 2, operator_form
  [">="]: limit_args 2, operator_form

  and: operator_form
  or: operator_form
}

compile = (exp) ->
  switch exp[1]
    when "quote" -- the ' operator
      quote exp[2]
    when "atom"
      exp[2]
    when "list"
      lst = exp[2]
      operator = atom(lst[1])

      if forms[operator]
        forms[operator] lst
      else
        {
          "chain"
          operator
          {"call", [compile(val) for val in *lst[2,]]}
        }
    else
      exp

compile_all = (tree) ->
  stms = for exp in *tree
    compile exp

  root = RootBlock!
  root.has_name = -> true

  code, err = moonscript.compile.tree stms, root
  error err if not code
  code

boot = [[
require("moonscript")
require("lisp.lib");
]]

export parse_and_compile = (lisp_code) ->
  tree = parser\match lisp_code
  assert tree, "Parse failed"
  code = compile_all tree
  concat { boot, code }

