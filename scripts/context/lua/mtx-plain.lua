if not modules then modules = { } end modules ['mtx-plain'] = {
    version   = 1.002,
    comment   = "companion to mtxrun.lua",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

-- future version will use the texmf-cache/generic/formats/<engine> path
-- instead because then we can use some more of the generic context
-- initializers ... in that case we will also use the regular database
-- instead of kpse here, just like with the font database code (as that
-- one also works with kpse runtime)

local helpinfo = [[
<?xml version="1.0"?>
<application>
 <metadata>
  <entry name="name">mtx-plain</entry>
  <entry name="detail">Plain TeX Runner</entry>
  <entry name="version">1.00</entry>
 </metadata>
 <flags>
  <category name="basic">
   <subcategory>
    <flag name="make"><short>create format file</short></flag>
    <flag name="run"><short>process file</short></flag>
    <flag name="format" value="string"><short>format name (default: luatex-plain)</short></flag>
    <flag name="engine" value="string"><short>engine to use (default: luatex)</short></flag>
    <flag name="jit"><short>use luajittex</short></flag>
   </subcategory>
  </category>
 </flags>
</application>
]]

local application = logs.application {
    name     = "mtx-plain",
    banner   = "Plain TeX Runner 1.00",
    helpinfo = helpinfo,
}

local report = application.report

scripts       = scripts       or { }
scripts.plain = scripts.plain or { }

local function execute(...)
    local command = string.format(...)
    report("running command %a\n",command)
    os.execute(command)
end

local function resultof(...)
    local command = string.format(...)
    report("running command %a",command)
    return string.strip(os.resultof(command) or "")
end

function scripts.plain.make(texengine,texformat)
    report("generating kpse file database")
    execute("mktexlsr") -- better play safe and use this one
    local fmtpathspec = resultof("kpsewhich --var-value=TEXFORMATS --engine=%s",texengine)
    if fmtpathspec ~= "" then
        report("using path specification %a",fmtpathspec)
        fmtpathspec = resultof('kpsewhich -expand-braces="%s"',fmtpathspec)
    end
    if fmtpathspec ~= "" then
        report("using path expansion %a",fmtpathspec)
    else
        report("no valid path reported, trying alternative")
        fmtpathspec = resultof("kpsewhich --show-path=fmt --engine=%s",texengine)
        if fmtpathspec ~= "" then
            report("using path expansion %a",fmtpathspec)
        else
            report("no valid path reported, falling back to current path")
            fmtpathspec = "."
        end
    end
    fmtpathspec = string.splitlines(fmtpathspec)[1] or fmtpathspec
    fmtpathspec = file.splitpath(fmtpathspec)
    local fmtpath = nil
    for i=1,#fmtpathspec do
        local path = fmtpathspec[i]
        if path ~= "." then
            dir.makedirs(path)
            if lfs.isdir(path) and file.is_writable(path) then
                fmtpath = path
                break
            end
        end
    end
    if not fmtpath or fmtpath == "" then
        fmtpath = "."
    else
        lfs.chdir(fmtpath)
    end
    execute('%s --ini %s \\dump',texengine,file.addsuffix(texformat,"tex"))
    report("generating kpse file database")
    execute("mktexlsr")
    report("format %a saved on path %a",texformat,fmtpath)
end

function scripts.plain.run(texengine,texformat,filename)
    execute('%s --fmt=%s "%s"',texengine,file.removesuffix(texformat),filename)
end

local texformat = environment.arguments.texformat or environment.arguments.format
local texengine = environment.arguments.texengine or environment.arguments.engine

if type(texengine) ~= "string" or texengine == "" then
    texengine = environment.arguments.jit and "luajittex" or"luatex"
end

if type(texformat) ~= "string" or texformat == "" then
    texformat = "luatex-plain"
end

local filename = environment.files[1]

if environment.arguments.exporthelp then
    application.export(environment.arguments.exporthelp,filename)
elseif environment.arguments.make then
    scripts.plain.make(texengine,texformat)
elseif filename then
    scripts.plain.run(texengine,texformat,filename)
else
    application.help()
end