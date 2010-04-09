if not modules then modules = { } end modules ['sort-ini'] = {
    version   = 1.001,
    comment   = "companion to sort-ini.mkiv",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

-- todo:
--
-- out of range
-- uppercase
-- texutil compatible
-- always expand to utf

local utf = unicode.utf8
local gsub, rep, sort, concat = string.gsub, string.rep, table.sort, table.concat
local utfcharacters, utfvalues, strcharacters = string.utfcharacters, string.utfvalues, string.characters

local trace_sorters = false -- true

sorters              = { }
sorters.comparers    = { }
sorters.splitters    = { }
sorters.entries      = { }
sorters.mappings     = { }
sorters.replacements = { }
sorters.language     = 'en'

local mappings = sorters.mappings
local entries  = sorters.entries

function sorters.comparers.basic(sort_a,sort_b)
    -- sm assignment is slow, will become sorters.initialize
    local sm = mappings[sorters.language or sorters.defaultlanguage] or mappings.en
    if #sort_a > #sort_b then
        if #sort_b == 0 then
            return 1
        else
            for i=1,#sort_b do
                local ai, bi = sort_a[i], sort_b[i]
                local am, bm = sm[ai], sm[bi]
                if am and bm then
                    if am > bm then
                        return  1
                    elseif am < bm then
                        return -1
                    end
                else
                    if ai > bi then
                        return  1
                    elseif ai < bi then
                        return -1
                    end
                end
            end
            return 1
        end
    elseif #sort_a < #sort_b then
        if #sort_a == 0 then
            return -1
        else
            for i=1,#sort_a do
                local ai, bi = sort_a[i], sort_b[i]
                local am, bm = sm[ai], sm[bi]
                if am and bm then
                    if am > bm then
                        return  1
                    elseif am < bm then
                        return -1
                    end
                else
                    if ai > bi then
                        return  1
                    elseif ai < bi then
                        return -1
                    end
                end
            end
            return -1
        end
    elseif #sort_a == 0 then
        return 0
    else
        for i=1,#sort_a do
            local ai, bi = sort_a[i], sort_b[i]
            local am, bm = sm[ai], sm[bi]
            if am and bm then
                if am > bm then
                    return  1
                elseif am < bm then
                    return -1
                end
            else
                if ai > bi then
                    return  1
                elseif ai < bi then
                    return -1
                end
            end
        end
        return 0
    end
end

local function padd(s) return rep(" ",10-#s) .. s end -- or format with padd

function sorters.strip(str) -- todo: only letters and such utf.gsub("([^%w%d])","")
    if str then
        str = gsub(str,"\\%S*","")
        str = gsub(str,"[%s%[%](){}%$\"\']*","")
        str = gsub(str,"(%d+)",padd) -- sort numbers properly
        return str
    else
        return ""
    end
end

function sorters.firstofsplit(split)
    -- numbers are left padded by spaces
    local se = entries[sorters.language or sorters.defaultlanguage] or entries.en-- slow, will become sorters.initialize
    local vs = split[1]
    local entry = (vs and vs[1]) or ""
    return entry, (se and se[entry]) or "\000"
end

sorters.defaultlanguage = 'en'

-- beware, numbers get spaces in front

function sorters.splitters.utf(str) -- brrr, todo: language
    local r = sorters.replacements[sorters.language] or sorters.replacements[sorters.defaultlanguage] or { }
 -- local m = mappings    [sorters.language] or mappings    [sorters.defaultlanguage] or { }
    local u = characters.uncompose
    local b = utf.byte
    local t = { }
    for _,v in next, r do
        str = gsub(str,v[1],v[2])
    end
    for c in utfcharacters(str) do -- maybe an lpeg
        if #c == 1 then
            t[#t+1] = c
        else
            for cc in strcharacters(c) do
                t[#t+1] = cc
            end
        end
    end
    return t
end

function sorters.sort(entries,cmp)
    if trace_sorters then
        sort(entries, function(a,b)
            local r = cmp(a,b)
            local as, bs = a.split, b.split
            if as and bs then
                logs.report("sorter","%s %s %s",
                    concat(as[1]), (not r and "?") or (r<0 and "<") or (r>0 and ">") or "=", concat(bs[1]))
            end
            return r == -1
        end)
    else
        sort(entries, function(a,b)
            return cmp(a,b) == -1
        end)
    end
end
