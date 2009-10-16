if not modules then modules = { } end modules ['lxml-tab'] = {
    version   = 1.001,
    comment   = "this module is the basis for the lxml-* ones",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

-- this module needs a cleanup: check latest lpeg, passing args, (sub)grammar, etc etc
-- stripping spaces from e.g. cont-en.xml saves .2 sec runtime so it's not worth the
-- trouble

local trace_entities = false  trackers.register("xml.entities", function(v) trace_entities = v end)

--[[ldx--
<p>The parser used here is inspired by the variant discussed in the lua book, but
handles comment and processing instructions, has a different structure, provides
parent access; a first version used different trickery but was less optimized to we
went this route. First we had a find based parser, now we have an <l n='lpeg'/> based one.
The find based parser can be found in l-xml-edu.lua along with other older code.</p>

<p>Beware, the interface may change. For instance at, ns, tg, dt may get more
verbose names. Once the code is stable we will also remove some tracing and
optimize the code.</p>
--ldx]]--

xml = xml or { }

--~ local xml = xml

local concat, remove, insert = table.concat, table.remove, table.insert
local type, next, setmetatable, getmetatable, tonumber = type, next, setmetatable, getmetatable, tonumber
local format, lower, find = string.format, string.lower, string.find
local utfchar = unicode.utf8.char

--[[ldx--
<p>First a hack to enable namespace resolving. A namespace is characterized by
a <l n='url'/>. The following function associates a namespace prefix with a
pattern. We use <l n='lpeg'/>, which in this case is more than twice as fast as a
find based solution where we loop over an array of patterns. Less code and
much cleaner.</p>
--ldx]]--

xml.xmlns = xml.xmlns or { }

local check = lpeg.P(false)
local parse = check

--[[ldx--
<p>The next function associates a namespace prefix with an <l n='url'/>. This
normally happens independent of parsing.</p>

<typing>
xml.registerns("mml","mathml")
</typing>
--ldx]]--

function xml.registerns(namespace, pattern) -- pattern can be an lpeg
    check = check + lpeg.C(lpeg.P(lower(pattern))) / namespace
    parse = lpeg.P { lpeg.P(check) + 1 * lpeg.V(1) }
end

--[[ldx--
<p>The next function also registers a namespace, but this time we map a
given namespace prefix onto a registered one, using the given
<l n='url'/>. This used for attributes like <t>xmlns:m</t>.</p>

<typing>
xml.checkns("m","http://www.w3.org/mathml")
</typing>
--ldx]]--

function xml.checkns(namespace,url)
    local ns = parse:match(lower(url))
    if ns and namespace ~= ns then
        xml.xmlns[namespace] = ns
    end
end

--[[ldx--
<p>Next we provide a way to turn an <l n='url'/> into a registered
namespace. This used for the <t>xmlns</t> attribute.</p>

<typing>
resolvedns = xml.resolvens("http://www.w3.org/mathml")
</typing>

This returns <t>mml</t>.
--ldx]]--

function xml.resolvens(url)
     return parse:match(lower(url)) or ""
end

--[[ldx--
<p>A namespace in an element can be remapped onto the registered
one efficiently by using the <t>xml.xmlns</t> table.</p>
--ldx]]--

--[[ldx--
<p>This version uses <l n='lpeg'/>. We follow the same approach as before, stack and top and
such. This version is about twice as fast which is mostly due to the fact that
we don't have to prepare the stream for cdata, doctype etc etc. This variant is
is dedicated to Luigi Scarso, who challenged me with 40 megabyte <l n='xml'/> files that
took 12.5 seconds to load (1.5 for file io and the rest for tree building). With
the <l n='lpeg'/> implementation we got that down to less 7.3 seconds. Loading the 14
<l n='context'/> interface definition files (2.6 meg) went down from 1.05 seconds to 0.55.</p>

<p>Next comes the parser. The rather messy doctype definition comes in many
disguises so it is no surprice that later on have to dedicate quite some
<l n='lpeg'/> code to it.</p>

<typing>
<!DOCTYPE Something PUBLIC "... ..." "..." [ ... ] >
<!DOCTYPE Something PUBLIC "... ..." "..." >
<!DOCTYPE Something SYSTEM "... ..." [ ... ] >
<!DOCTYPE Something SYSTEM "... ..." >
<!DOCTYPE Something [ ... ] >
<!DOCTYPE Something >
</typing>

<p>The code may look a bit complex but this is mostly due to the fact that we
resolve namespaces and attach metatables. There is only one public function:</p>

<typing>
local x = xml.convert(somestring)
</typing>

<p>An optional second boolean argument tells this function not to create a root
element.</p>

<p>Valid entities are:</p>

<typing>
<!ENTITY xxxx SYSTEM "yyyy" NDATA zzzz>
<!ENTITY xxxx PUBLIC "yyyy" >
<!ENTITY xxxx "yyyy" >
</typing>
--ldx]]--

-- not just one big nested table capture (lpeg overflow)

local nsremap, resolvens = xml.xmlns, xml.resolvens

local stack, top, dt, at, xmlns, errorstr, entities = {}, {}, {}, {}, {}, nil, {}
local strip, cleanup, utfize, resolve = false, false, false, false

local mt = { }

function initialize_mt(root) -- we will make a xml.new that then sets the mt as field
    mt = { __tostring = xml.text, __index = root }
end

function xml.setproperty(root,k,v)
    getmetatable(root).__index[k] = v
end

function xml.check_error(top,toclose)
    return ""
end

local function add_attribute(namespace,tag,value)
    if cleanup and #value > 0 then
        value = cleanup(value) -- new
    end
    if tag == "xmlns" then
        xmlns[#xmlns+1] = resolvens(value)
        at[tag] = value
    elseif namespace == "xmlns" then
        xml.checkns(tag,value)
        at["xmlns:" .. tag] = value
    else
        at[tag] = value
    end
end

local function add_empty(spacing, namespace, tag)
    if #spacing > 0 then
        dt[#dt+1] = spacing
    end
    local resolved = (namespace == "" and xmlns[#xmlns]) or nsremap[namespace] or namespace
    top = stack[#stack]
    dt = top.dt
    local t = { ns=namespace or "", rn=resolved, tg=tag, at=at, dt={}, __p__ = top }
    dt[#dt+1] = t
    setmetatable(t, mt)
    if at.xmlns then
        remove(xmlns)
    end
    at = { }
end

local function add_begin(spacing, namespace, tag)
    if #spacing > 0 then
        dt[#dt+1] = spacing
    end
    local resolved = (namespace == "" and xmlns[#xmlns]) or nsremap[namespace] or namespace
    top = { ns=namespace or "", rn=resolved, tg=tag, at=at, dt={}, __p__ = stack[#stack] }
    setmetatable(top, mt)
    dt = top.dt
    stack[#stack+1] = top
    at = { }
end

local function add_end(spacing, namespace, tag)
    if #spacing > 0 then
        dt[#dt+1] = spacing
    end
    local toclose = remove(stack)
    top = stack[#stack]
    if #stack < 1 then
        errorstr = format("nothing to close with %s %s", tag, xml.check_error(top,toclose) or "")
    elseif toclose.tg ~= tag then -- no namespace check
        errorstr = format("unable to close %s with %s %s", toclose.tg, tag, xml.check_error(top,toclose) or "")
    end
    dt = top.dt
    dt[#dt+1] = toclose
 -- dt[0] = top -- nasty circular reference when serializing table
    if toclose.at.xmlns then
        remove(xmlns)
    end
end

local function add_text(text)
    if cleanup and #text > 0 then
        dt[#dt+1] = cleanup(text)
    else
        dt[#dt+1] = text
    end
end

local function add_special(what, spacing, text)
    if #spacing > 0 then
        dt[#dt+1] = spacing
    end
    if strip and (what == "@cm@" or what == "@dt@") then
        -- forget it
    else
        dt[#dt+1] = { special=true, ns="", tg=what, dt={text} }
    end
end

local function set_message(txt)
    errorstr = "garbage at the end of the file: " .. gsub(txt,"([ \n\r\t]*)","")
end

local reported_attribute_errors = { }

local function attribute_value_error(str)
    if not reported_attribute_errors[str] then
        logs.report("xml","invalid attribute value: %q",str)
        reported_attribute_errors[str] = true
        at._error_ = str
    end
    return str
end
local function attribute_specification_error(str)
    if not reported_attribute_errors[str] then
        logs.report("xml","invalid attribute specification: %q",str)
        reported_attribute_errors[str] = true
        at._error_ = str
    end
    return str
end

local dcache, hcache, acache = { }, { }, { }

function xml.unknown_dec_entity_format(str) return format("&%s;",  str) end
function xml.unknown_hex_entity_format(str) return format("&#x%s;",str) end
function xml.unknown_any_entity_format(str) return format("&%s;",  str) end

local function handle_hex_entity(str)
    local h = hcache[str]
    if not h then
        if utfize then
            local n = tonumber(str,16)
            h = (n and utfchar(n)) or xml.unknown_hex_entity_format(str) or ""
            if not n then
                logs.report("xml","utfize, ignoring hex entity &#x%s;",str)
            elseif trace_entities then
                logs.report("xml","utfize, converting hex entity &#x%s; into %s",str,c)
            end
        else
            if trace_entities then
                logs.report("xml","found entity &#x%s;",str)
            end
            h = "&#" .. str .. ";"
        end
        hcache[str] = h
    end
    return h
end
local function handle_dec_entity(str)
    local d = dcache[str]
    if not d then
        if utfize then
            local n = tonumber(str)
            d = (n and utfchar(n)) or xml.unknown_dec_entity_format(str) or ""
            if not n then
                logs.report("xml","utfize, ignoring dec entity &#%s;",str)
            elseif trace_entities then
                logs.report("xml","utfize, converting dec entity &#%s; into %s",str,c)
            end
        else
            if trace_entities then
                logs.report("xml","found entity &#%s;",str)
            end
            d = "&" .. str .. ";"
        end
        dcache[str] = d
    end
    return d
end
local function handle_any_entity(str)
    if resolve then
        local a = entities[str] -- per instance !
        if not a then
            a = acache[str]
            if not a then
                if trace_entities then
                    logs.report("xml","ignoring entity &%s;",str)
                else
                    -- can be defined in a global mapper and intercepted elsewhere
                    -- as happens in lxml-tex.lua
                end
                a = xml.unknown_any_entity_format(str) or ""
                acache[str] = a
            end
        elseif trace_entities then
            if not acache[str] then
                logs.report("xml","converting entity &%s; into %s",str,r)
                acache[str] = a
            end
        end
        return a
    else
        local a = acache[str]
        if not a then
            if trace_entities then
                logs.report("xml","found entity &%s;",str)
            end
            a = "&" .. str .. ";"
            acache[str] = a
        end
        return a
    end
end

local P, S, R, C, V, Cs = lpeg.P, lpeg.S, lpeg.R, lpeg.C, lpeg.V, lpeg.Cs

local space            = S(' \r\n\t')
local open             = P('<')
local close            = P('>')
local squote           = S("'")
local dquote           = S('"')
local equal            = P('=')
local slash            = P('/')
local colon            = P(':')
local semicolon        = P(';')
local ampersand        = P('&')
local valid            = R('az', 'AZ', '09') + S('_-.')
local name_yes         = C(valid^1) * colon * C(valid^1)
local name_nop         = C(P(true)) * C(valid^1)
local name             = name_yes + name_nop

local utfbom           = P('\000\000\254\255') + P('\255\254\000\000') +
                         P('\255\254') + P('\254\255') + P('\239\187\191') -- no capture

local spacing          = C(space^0)

local entitycontent    = (1-open-semicolon)^0
local entity           = ampersand/"" * (
                            P("#")/"" * (
                                P("x")/"" * (entitycontent/handle_hex_entity) +
                                            (entitycontent/handle_dec_entity)
                            ) +             (entitycontent/handle_any_entity)
                         ) * (semicolon/"")

local text_unparsed    = C((1-open)^1)
local text_parsed      = Cs(((1-open-ampersand)^1 + entity)^1)

local somespace        = space^1
local optionalspace    = space^0

local value            = (squote * C((1 - squote)^0) * squote) + (dquote * C((1 - dquote)^0) * dquote) -- ampersand and < also invalid in value

local whatever         = space * name * optionalspace * equal
local wrongvalue       = C(P(1-whatever-close)^1 + P(1-close)^1) / attribute_value_error

local attributevalue   = value + wrongvalue

local attribute        = (somespace * name * optionalspace * equal * optionalspace * attributevalue) / add_attribute
----- attributes       = (attribute)^0

local endofattributes  = slash * close + close -- recovery of flacky html
local attributes       = (attribute + somespace^-1 * (((1-endofattributes)^1)/attribute_specification_error))^0

local parsedtext       = text_parsed   / add_text
local unparsedtext     = text_unparsed / add_text
local balanced         = P { "[" * ((1 - S"[]") + V(1))^0 * "]" } -- taken from lpeg manual, () example

local emptyelement     = (spacing * open         * name * attributes * optionalspace * slash * close) / add_empty
local beginelement     = (spacing * open         * name * attributes * optionalspace         * close) / add_begin
local endelement       = (spacing * open * slash * name              * optionalspace         * close) / add_end

local begincomment     = open * P("!--")
local endcomment       = P("--") * close
local begininstruction = open * P("?")
local endinstruction   = P("?") * close
local begincdata       = open * P("![CDATA[")
local endcdata         = P("]]") * close

local someinstruction  = C((1 - endinstruction)^0)
local somecomment      = C((1 - endcomment    )^0)
local somecdata        = C((1 - endcdata      )^0)

local function normalentity(k,v  ) entities[k] = v end
local function systementity(k,v,n) entities[k] = v end
local function publicentity(k,v,n) entities[k] = v end

local begindoctype     = open * P("!DOCTYPE")
local enddoctype       = close
local beginset         = P("[")
local endset           = P("]")
local doctypename      = C((1-somespace-close)^0)
local elementdoctype   = optionalspace * P("<!ELEMENT") * (1-close)^0 * close

local normalentitytype = (doctypename * somespace * value)/normalentity
local publicentitytype = (doctypename * somespace * P("PUBLIC") * somespace * value)/publicentity
local systementitytype = (doctypename * somespace * P("SYSTEM") * somespace * value * somespace * P("NDATA") * somespace * doctypename)/systementity
local entitydoctype    = optionalspace * P("<!ENTITY") * somespace * (systementitytype + publicentitytype + normalentitytype) * optionalspace * close

local doctypeset       = beginset * optionalspace * P(elementdoctype + entitydoctype + space)^0 * optionalspace * endset
local definitiondoctype= doctypename * somespace * doctypeset
local publicdoctype    = doctypename * somespace * P("PUBLIC") * somespace * value * somespace * value * somespace * doctypeset
local systemdoctype    = doctypename * somespace * P("SYSTEM") * somespace * value * somespace * doctypeset
local simpledoctype    = (1-close)^1 -- * balanced^0
local somedoctype      = C((somespace * (publicdoctype + systemdoctype + definitiondoctype + simpledoctype) * optionalspace)^0)

local instruction      = (spacing * begininstruction * someinstruction * endinstruction) / function(...) add_special("@pi@",...) end
local comment          = (spacing * begincomment     * somecomment     * endcomment    ) / function(...) add_special("@cm@",...) end
local cdata            = (spacing * begincdata       * somecdata       * endcdata      ) / function(...) add_special("@cd@",...) end
local doctype          = (spacing * begindoctype     * somedoctype     * enddoctype    ) / function(...) add_special("@dt@",...) end

--  nicer but slower:
--
--  local instruction = (lpeg.Cc("@pi@") * spacing * begininstruction * someinstruction * endinstruction) / add_special
--  local comment     = (lpeg.Cc("@cm@") * spacing * begincomment     * somecomment     * endcomment    ) / add_special
--  local cdata       = (lpeg.Cc("@cd@") * spacing * begincdata       * somecdata       * endcdata      ) / add_special
--  local doctype     = (lpeg.Cc("@dt@") * spacing * begindoctype     * somedoctype     * enddoctype    ) / add_special

local trailer = space^0 * (text_unparsed/set_message)^0

--  comment + emptyelement + text + cdata + instruction + V("parent"), -- 6.5 seconds on 40 MB database file
--  text + comment + emptyelement + cdata + instruction + V("parent"), -- 5.8
--  text + V("parent") + emptyelement + comment + cdata + instruction, -- 5.5

local grammar_parsed_text = P { "preamble",
    preamble = utfbom^0 * instruction^0 * (doctype + comment + instruction)^0 * V("parent") * trailer,
    parent   = beginelement * V("children")^0 * endelement,
    children = parsedtext + V("parent") + emptyelement + comment + cdata + instruction,
}

local grammar_unparsed_text = P { "preamble",
    preamble = utfbom^0 * instruction^0 * (doctype + comment + instruction)^0 * V("parent") * trailer,
    parent   = beginelement * V("children")^0 * endelement,
    children = unparsedtext + V("parent") + emptyelement + comment + cdata + instruction,
}

local function xmlconvert(data, settings)
    settings = settings or { } -- no_root strip_cm_and_dt given_entities parent_root error_handler
    strip = settings.strip_cm_and_dt
    utfize = settings.utfize_entities
    resolve = settings.resolve_entities
    cleanup = settings.text_cleanup
    stack, top, at, xmlns, errorstr, result, entities = {}, {}, {}, {}, nil, nil, settings.entities or {}
    reported_attribute_errors = { }
    if settings.parent_root then
        mt = getmetatable(settings.parent_root)
    else
        initialize_mt(top)
    end
    stack[#stack+1] = top
    top.dt = { }
    dt = top.dt
    if not data or data == "" then
        errorstr = "empty xml file"
    elseif utfize or resolve then
        if grammar_parsed_text:match(data) then
            errorstr = ""
        else
            errorstr = "invalid xml file - parsed text"
        end
    else
        if grammar_unparsed_text:match(data) then
            errorstr = ""
        else
            errorstr = "invalid xml file - unparsed text"
        end
    end
    if errorstr and errorstr ~= "" then
        result = { dt = { { ns = "", tg = "error", dt = { errorstr }, at={}, er = true } } }
        setmetatable(stack, mt)
        local error_handler = settings.error_handler
        if error_handler == false then
            -- no error message
        else
            error_handler = error_handler or xml.error_handler
            if error_handler then
                xml.error_handler("load",errorstr)
            end
        end
    else
        result = stack[1]
    end
    if not settings.no_root then
        result = { special = true, ns = "", tg = '@rt@', dt = result.dt, at={}, entities = entities, settings = settings }
        setmetatable(result, mt)
        local rdt = result.dt
        for k=1,#rdt do
            local v = rdt[k]
            if type(v) == "table" and not v.special then -- always table -)
                result.ri = k -- rootindex
                break
            end
        end
    end
    if errorstr and errorstr ~= "" then
        result.error = true
    end
    return result
end

xml.convert = xmlconvert

--[[ldx--
<p>Packaging data in an xml like table is done with the following
function. Maybe it will go away (when not used).</p>
--ldx]]--

function xml.is_valid(root)
    return root and root.dt and root.dt[1] and type(root.dt[1]) == "table" and not root.dt[1].er
end

function xml.package(tag,attributes,data)
    local ns, tg = tag:match("^(.-):?([^:]+)$")
    local t = { ns = ns, tg = tg, dt = data or "", at = attributes or {} }
    setmetatable(t, mt)
    return t
end

function xml.is_valid(root)
    return root and not root.error
end

xml.error_handler = (logs and logs.report) or (input and logs.report) or print

--[[ldx--
<p>We cannot load an <l n='lpeg'/> from a filehandle so we need to load
the whole file first. The function accepts a string representing
a filename or a file handle.</p>
--ldx]]--

function xml.load(filename)
    if type(filename) == "string" then
        local f = io.open(filename,'r')
        if f then
            local root = xmlconvert(f:read("*all"))
            f:close()
            return root
        else
            return xmlconvert("")
        end
    elseif filename then -- filehandle
        return xmlconvert(filename:read("*all"))
    else
        return xmlconvert("")
    end
end

--[[ldx--
<p>When we inject new elements, we need to convert strings to
valid trees, which is what the next function does.</p>
--ldx]]--

local no_root = { no_root = true }

function xml.toxml(data)
    if type(data) == "string" then
        local root = { xmlconvert(data,no_root) }
        return (#root > 1 and root) or root[1]
    else
        return data
    end
end

--[[ldx--
<p>For copying a tree we use a dedicated function instead of the
generic table copier. Since we know what we're dealing with we
can speed up things a bit. The second argument is not to be used!</p>
--ldx]]--

local function copy(old,tables)
    if old then
        tables = tables or { }
        local new = { }
        if not tables[old] then
            tables[old] = new
        end
        for k,v in pairs(old) do
            new[k] = (type(v) == "table" and (tables[v] or copy(v, tables))) or v
        end
        local mt = getmetatable(old)
        if mt then
            setmetatable(new,mt)
        end
        return new
    else
        return { }
    end
end

xml.copy = copy

--[[ldx--
<p>In <l n='context'/> serializing the tree or parts of the tree is a major
actitivity which is why the following function is pretty optimized resulting
in a few more lines of code than needed. The variant that uses the formatting
function for all components is about 15% slower than the concatinating
alternative.</p>
--ldx]]--

-- todo: add <?xml version='1.0' standalone='yes'?> when not present

function xml.checkbom(root) -- can be made faster
    if root.ri then
        local dt, found = root.dt, false
        for k=1,#dt do
            local v = dt[k]
            if type(v) == "table" and v.special and v.tg == "@pi" and find(v.dt,"xml.*version=") then
                found = true
                break
            end
        end
        if not found then
            insert(dt, 1, { special=true, ns="", tg="@pi@", dt = { "xml version='1.0' standalone='yes'"} } )
            insert(dt, 2, "\n" )
        end
    end
end

--[[ldx--
<p>At the cost of some 25% runtime overhead you can first convert the tree to a string
and then handle the lot.</p>
--ldx]]--

-- new experimental reorganized serialize

local function verbose_element(e,handlers)
    local handle = handlers.handle
    local serialize = handlers.serialize
    local ens, etg, eat, edt, ern = e.ns, e.tg, e.at, e.dt, e.rn
    local ats = eat and next(eat) and { }
    if ats then
        for k,v in next, eat do
            ats[#ats+1] = format('%s=%q',k,v)
        end
    end
    if ern and trace_remap and ern ~= ens then
        ens = ern
    end
    if ens ~= "" then
        if edt and #edt > 0 then
            if ats then
                handle("<",ens,":",etg," ",concat(ats," "),">")
            else
                handle("<",ens,":",etg,">")
            end
            for i=1,#edt do
                local e = edt[i]
                if type(e) == "string" then
                    handle(e)
                else
                    serialize(e,handlers)
                end
            end
            handle("</",ens,":",etg,">")
        else
            if ats then
                handle("<",ens,":",etg," ",concat(ats," "),"/>")
            else
                handle("<",ens,":",etg,"/>")
            end
        end
    else
        if edt and #edt > 0 then
            if ats then
                handle("<",etg," ",concat(ats," "),">")
            else
                handle("<",etg,">")
            end
            for i=1,#edt do
                local ei = edt[i]
                if type(ei) == "string" then
                    handle(ei)
                else
                    serialize(ei,handlers)
                end
            end
            handle("</",etg,">")
        else
            if ats then
                handle("<",etg," ",concat(ats," "),"/>")
            else
                handle("<",etg,"/>")
            end
        end
    end
end

local function verbose_pi(e,handlers)
    handlers.handle("<?",e.dt[1],"?>")
end

local function verbose_comment(e,handlers)
    handlers.handle("<!--",e.dt[1],"-->")
end

local function verbose_cdata(e,handlers)
    handlers.handle("<![CDATA[", e.dt[1],"]]>")
end

local function verbose_doctype(e,handlers)
    handlers.handle("<!DOCTYPE ",e.dt[1],">")
end

local function verbose_root(e,handlers)
    handlers.serialize(e.dt,handlers)
end

local function verbose_text(e,handlers)
    handlers.handle(e)
end

local function verbose_document(e,handlers)
    local serialize = handlers.serialize
    local functions = handlers.functions
    for i=1,#e do
        local ei = e[i]
        if type(ei) == "string" then
            functions["@tx@"](ei,handlers)
        else
            serialize(ei,handlers)
        end
    end
end

local function serialize(e,handlers,...)
    local initialize = handlers.initialize
    local finalize   = handlers.finalize
    local functions  = handlers.functions
    if initialize then
        local state = initialize(...)
        if not state == true then
            return state
        end
    end
    local etg = e.tg
    if etg then
        (functions[etg] or functions["@el@"])(e,handlers)
 -- elseif type(e) == "string" then
 --     functions["@tx@"](e,handlers)
    else
        functions["@dc@"](e,handlers)
    end
    if finalize then
        return finalize()
    end
end

local function xserialize(e,handlers)
    local functions = handlers.functions
    local etg = e.tg
    if etg then
        (functions[etg] or functions["@el@"])(e,handlers)
 -- elseif type(e) == "string" then
 --     functions["@tx@"](e,handlers)
    else
        functions["@dc@"](e,handlers)
    end
end

local handlers = { }

local function newhandlers(settings)
    local t = table.copy(handlers.verbose or { }) -- merge
    if settings then
        for k,v in next, settings do
            if type(v) == "table" then
                tk = t[k] if not tk then tk = { } t[k] = tk end
                for kk,vv in next, v do
                    tk[kk] = vv
                end
            else
                t[k] = v
            end
        end
        if settings.name then
            handlers[settings.name] = t
        end
    end
    return t
end

local nofunction = function() end

function xml.sethandlersfunction(handler,name,fnc)
    handler.functions[name] = fnc or nofunction
end

function xml.gethandlersfunction(handler,name)
    return handler.functions[name]
end

function xml.gethandlers(name)
    return handlers[name]
end

newhandlers {
    name       = "verbose",
    initialize = false, -- faster than nil and mt lookup
    finalize   = false, -- faster than nil and mt lookup
    serialize  = xserialize,
    handle     = print,
    functions  = {
        ["@dc@"]   = verbose_document,
        ["@dt@"]   = verbose_doctype,
        ["@rt@"]   = verbose_root,
        ["@el@"]   = verbose_element,
        ["@pi@"]   = verbose_pi,
        ["@cm@"]   = verbose_comment,
        ["@cd@"]   = verbose_cdata,
        ["@tx@"]   = verbose_text,
    }
}

--[[ldx--
<p>How you deal with saving data depends on your preferences. For a 40 MB database
file the timing on a 2.3 Core Duo are as follows (time in seconds):</p>

<lines>
1.3 : load data from file to string
6.1 : convert string into tree
5.3 : saving in file using xmlsave
6.8 : converting to string using xml.tostring
3.6 : saving converted string in file
</lines>

<p>Beware, these were timing with the old routine but measurements will not be that
much different I guess.</p>
--ldx]]--

-- maybe this will move to lxml-xml

local result

local xmlfilehandler = newhandlers {
    name       = "file",
    initialize = function(name) result = io.open(name,"wb") return result end,
    finalize   = function() result:close() return true end,
    handle     = function(...) result:write(...) end,
}

-- no checking on writeability here but not faster either
--
-- local xmlfilehandler = newhandlers {
--     initialize = function(name) io.output(name,"wb") return true end,
--     finalize   = function() io.close() return true end,
--     handle     = io.write,
-- }


function xml.save(root,name)
    serialize(root,xmlfilehandler,name)
end

local result

local xmlstringhandler = newhandlers {
    name       = "string",
    initialize = function() result = { } return result end,
    finalize   = function() return concat(result) end,
    handle     = function(...) result[#result+1] = concat { ... } end
}

local function xmltostring(root) -- 25% overhead due to collecting
    if root then
        if type(root) == 'string' then
            return root
        else -- if next(root) then -- next is faster than type (and >0 test)
            return serialize(root,xmlstringhandler) or ""
        end
    end
    return ""
end

local function xmltext(root) -- inline
    return (root and xmltostring(root)) or ""
end

function initialize_mt(root)
    mt = { __tostring = xmltext, __index = root }
end

xml.defaulthandlers = handlers
xml.newhandlers     = newhandlers
xml.serialize       = serialize
xml.tostring        = xmltostring
xml.text            = xmltext

--[[ldx--
<p>The next function operated on the content only and needs a handle function
that accepts a string.</p>
--ldx]]--

local function xmlstring(e,handle)
    if not handle or (e.special and e.tg ~= "@rt@") then
        -- nothing
    elseif e.tg then
        local edt = e.dt
        if edt then
            for i=1,#edt do
                xmlstring(edt[i],handle)
            end
        end
    else
        handle(e)
    end
end

xml.string = xmlstring

--[[ldx--
<p>A few helpers:</p>
--ldx]]--

function xml.parent(root)
    return root.__p__
end

function xml.body(root)
    return (root.ri and root.dt[root.ri]) or root
end

function xml.text(root)
    return (root and xml.tostring(root)) or ""
end

function xml.content(root) -- bugged
    return (root and root.dt and xml.tostring(root.dt)) or ""
end

--[[ldx--
<p>The next helper erases an element but keeps the table as it is,
and since empty strings are not serialized (effectively) it does
not harm. Copying the table would take more time. Usage:</p>
--ldx]]--

function xml.erase(dt,k)
    if dt then
        if k then
            dt[k] = ""
        else for k=1,#dt do
            dt[1] = { "" }
        end end
    end
end

--[[ldx--
<p>The next helper assigns a tree (or string). Usage:</p>

<typing>
dt[k] = xml.assign(root) or xml.assign(dt,k,root)
</typing>
--ldx]]--

function xml.assign(dt,k,root)
    if dt and k then
        dt[k] = (type(root) == "table" and xml.body(root)) or root
        return dt[k]
    else
        return xml.body(root)
    end
end
