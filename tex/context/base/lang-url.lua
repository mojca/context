if not modules then modules = { } end modules ['lang-url'] = {
    version   = 1.001,
    comment   = "companion to lang-url.tex",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

commands = commands or { }

--[[
<p>Hyphenating <l n='url'/>'s is somewhat tricky and a matter of taste. I did
consider using a dedicated hyphenation pattern or dealing with it by node
parsing, but the following solution suits as well. After all, we're mostly
dealing with <l n='ascii'/> characters.</p>
]]--

do

    commands.hyphenatedurl = commands.hyphenatedurl or { }

    commands.hyphenatedurl.characters = {
      ["!"] = 1,
      ["\""] = 1,
      ["#"] = 1,
      ["$"] = 1,
      ["%"] = 1,
      ["&"] = 1,
      ["("] = 1,
      ["*"] = 1,
      ["+"] = 1,
      [","] = 1,
      ["-"] = 1,
      ["."] = 1,
      ["/"] = 1,
      [":"] = 1,
      [";"] = 1,
      ["<"] = 1,
      ["="] = 1,
      [">"] = 1,
      ["?"] = 1,
      ["@"] = 1,
      ["["] = 1,
      ["\\"] = 1,
      ["^"] = 1,
      ["_"] = 1,
      ["`"] = 1,
      ["{"] = 1,
      ["|"] = 1,
      ["~"] = 1,

      ["'"] = 2,
      [")"] = 2,
      ["]"] = 2,
      ["}"] = 2
    }

    commands.hyphenatedurl.lefthyphenmin  = 2
    commands.hyphenatedurl.righthyphenmin = 3

    local chars = commands.hyphenatedurl.characters

    function commands.hyphenatedurl.action(str, left, right)
        local n = 0
        local b = math.max(left or commands.hyphenatedurl.lefthyphenmin,2)
        local e = math.min(#str-(right or commands.hyphenatedurl.righthyphenmin)+2,#str)
        local u = utf.byte
        str = utf.gsub(str,"(.)",function(s)
            n = n + 1
            local c = chars[s]
            if not c or n<=b or n>=e then
                return "\\n{" .. u(s) .. "}"
            elseif c == 1 then
                return "\\b{" .. u(s) .. "}"
            elseif c == 2 then
                return "\\a{" .. u(s) .. "}"
            end
        end )
        tex.sprint(tex.ctxcatcodes,str)
    end

end