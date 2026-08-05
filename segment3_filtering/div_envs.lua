-- div_envs.lua
--
-- Pandoc's LaTeX writer does not automatically turn a fenced Div
-- (::: classname ... :::) into a LaTeX environment — it just drops the
-- class wrapper and renders the inner content plain. This filter fixes
-- that: for every Div in the document that carries a class name, it
-- wraps the Div's rendered content in \begin{<class>}...\end{<class>}
-- RawBlocks, so the corresponding tcolorbox environment defined in the
-- LaTeX preamble (see the header-includes in the pandoc call) actually
-- gets used.
--
-- Usage: pandoc ... --lua-filter=div_envs.lua ...

function Div(el)
  if #el.classes == 0 then
    return el
  end

  local className = el.classes[1]
  local beginBlock = pandoc.RawBlock('latex', '\\begin{' .. className .. '}')
  local endBlock = pandoc.RawBlock('latex', '\\end{' .. className .. '}')

  local wrapped = {}
  table.insert(wrapped, beginBlock)
  for _, block in ipairs(el.content) do
    table.insert(wrapped, block)
  end
  table.insert(wrapped, endBlock)

  return wrapped
end
